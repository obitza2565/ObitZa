import express, { NextFunction, Request, Response } from "express";
import cors from "cors";
import rateLimit from "express-rate-limit";
import { config } from "./config";
import { miningPool } from "./miningPool";
import { hotWallet } from "./hotWallet";
import { withdrawalLedger } from "./withdrawalLedger";
import { logActivity, logError } from "./logger";
import { sendAlert } from "./notifier";
import { requireAdmin } from "./adminAuth";
import {
  validateStartMining,
  validateUserIdBody,
  validateUserIdParam,
  validateWithdraw,
  validateWithdrawalIdParam,
} from "./validators";

export function createServer() {
  const app = express();
  app.set("trust proxy", config.trustProxyHops);
  app.use(express.json());
  app.use(
    cors({
      origin: config.corsOrigins.length > 0 ? config.corsOrigins : false,
    })
  );
  app.use(
    rateLimit({
      windowMs: config.rateLimitWindowMs,
      max: config.rateLimitMax,
      standardHeaders: true,
      legacyHeaders: false,
      handler: (req, res) => {
        logActivity("rate_limit_exceeded", { ip: req.ip, path: req.path });
        res.status(429).json({ error: "too many requests, please slow down" });
      },
    })
  );

  app.get("/api/vmining/pool", (_req, res) => {
    res.json(miningPool.getPoolStatus());
  });

  app.post("/api/vmining/start", validateStartMining, (req: Request, res: Response) => {
    const { userId, walletAddress, ratePerHour } = req.body;
    const status = miningPool.startMining(userId, walletAddress, ratePerHour ? Number(ratePerHour) : undefined);
    logActivity("mining_started", { userId, walletAddress });
    res.json(status);
  });

  app.post("/api/vmining/stop", validateUserIdBody, (req: Request, res: Response) => {
    try {
      const status = miningPool.stopMining(req.body.userId);
      logActivity("mining_stopped", { userId: req.body.userId });
      res.json(status);
    } catch (err) {
      res.status(404).json({ error: (err as Error).message });
    }
  });

  app.get("/api/vmining/status/:userId", validateUserIdParam, (req: Request, res: Response) => {
    try {
      res.json(miningPool.getStatus(req.params.userId));
    } catch (err) {
      res.status(404).json({ error: (err as Error).message });
    }
  });

  app.post("/api/vmining/withdraw", validateWithdraw, async (req: Request, res: Response) => {
    const { userId, walletAddress, amount } = req.body;
    const amountObz = Number(amount);
    const amountUsdt = amountObz * config.obzPriceUsdt;

    try {
      miningPool.reserveForWithdrawal(userId, amountObz);
    } catch (err) {
      return res.status(400).json({ error: (err as Error).message });
    }

    logActivity("withdrawal_requested", { userId, walletAddress, amountObz, amountUsdt });
    void sendAlert(
      `💸 <b>Withdrawal requested</b>\nUser: ${userId}\nAmount: ${amountObz} OBZ (~${amountUsdt.toFixed(2)} USDT)\nTo: ${walletAddress}`
    );

    // Large withdrawals are queued for manual approval instead of an
    // automatic single-shot transfer.
    if (amountUsdt > config.withdrawalApprovalThresholdUsdt) {
      const request = withdrawalLedger.create(userId, walletAddress, amountObz, amountUsdt);
      logActivity("withdrawal_pending_approval", { id: request.id, userId, amountUsdt });
      void sendAlert(
        `⏳ <b>Approval required</b>\nUser: ${userId}\nAmount: ${amountObz} OBZ (~${amountUsdt.toFixed(2)} USDT)\nTo: ${walletAddress}\nID: <code>${request.id}</code>\nOpen the admin panel to approve or reject.`
      );
      return res.status(202).json(request);
    }

    try {
      const payout = await hotWallet.sendObzPayout(walletAddress, amountObz);
      miningPool.commitWithdrawal(userId);
      logActivity("withdrawal_paid", { userId, ...payout });
      void sendAlert(
        `✅ <b>Withdrawal paid</b>\nUser: ${userId}\nAmount: ${amountObz} OBZ\nTX: <code>${payout.txHash}</code>`
      );
      res.json({ status: "PAID", ...payout });
    } catch (err) {
      miningPool.refundWithdrawal(userId, amountObz);
      logError("withdrawal_failed", err, { userId, walletAddress, amountObz });
      void sendAlert(
        `🔴 <b>Withdrawal FAILED (refunded)</b>\nUser: ${userId}\nAmount: ${amountObz} OBZ\nError: ${(err as Error).message}`
      );
      res.status(502).json({ error: (err as Error).message });
    }
  });

  app.get("/api/vmining/hot-wallet/balance", async (_req, res) => {
    try {
      res.json(await hotWallet.getBalances());
    } catch (err) {
      res.status(500).json({ error: (err as Error).message });
    }
  });

  // ── Admin: manual approval for withdrawals above the threshold ──────────
  app.get("/api/admin/withdrawals", requireAdmin, (req, res) => {
    const status = typeof req.query.status === "string" ? req.query.status : undefined;
    res.json(withdrawalLedger.list(status as never));
  });

  app.post("/api/admin/withdrawals/:id/approve", requireAdmin, validateWithdrawalIdParam, async (req: Request, res: Response) => {
    const request = withdrawalLedger.get(req.params.id);
    if (!request) return res.status(404).json({ error: "withdrawal request not found" });
    if (request.status !== "PENDING") return res.status(409).json({ error: `request is already ${request.status}` });

    try {
      const payout = await hotWallet.sendObzPayout(request.walletAddress, request.amountObz);
      miningPool.commitWithdrawal(request.userId);
      withdrawalLedger.markDecided(request.id, "PAID", { txHash: payout.txHash });
      logActivity("withdrawal_approved", { id: request.id, userId: request.userId, txHash: payout.txHash });
      void sendAlert(
        `✅ <b>Withdrawal approved & paid</b>\nUser: ${request.userId}\nAmount: ${request.amountObz} OBZ\nTX: <code>${payout.txHash}</code>`
      );
      res.json({ status: "PAID", ...payout });
    } catch (err) {
      miningPool.refundWithdrawal(request.userId, request.amountObz);
      withdrawalLedger.markDecided(request.id, "FAILED", { note: (err as Error).message });
      logError("withdrawal_approval_failed", err, { id: request.id, userId: request.userId });
      void sendAlert(
        `🔴 <b>Approved withdrawal FAILED (refunded)</b>\nUser: ${request.userId}\nAmount: ${request.amountObz} OBZ\nError: ${(err as Error).message}`
      );
      res.status(502).json({ error: (err as Error).message });
    }
  });

  app.post("/api/admin/withdrawals/:id/reject", requireAdmin, validateWithdrawalIdParam, (req: Request, res: Response) => {
    const request = withdrawalLedger.get(req.params.id);
    if (!request) return res.status(404).json({ error: "withdrawal request not found" });
    if (request.status !== "PENDING") return res.status(409).json({ error: `request is already ${request.status}` });

    miningPool.refundWithdrawal(request.userId, request.amountObz);
    withdrawalLedger.markDecided(request.id, "REJECTED", { note: req.body?.note });
    logActivity("withdrawal_rejected", { id: request.id, userId: request.userId });
    void sendAlert(
      `❌ <b>Withdrawal rejected (refunded)</b>\nUser: ${request.userId}\nAmount: ${request.amountObz} OBZ\nNote: ${req.body?.note || "-"}`
    );
    res.json(withdrawalLedger.get(request.id));
  });

  app.use((err: Error, req: Request, res: Response, _next: NextFunction) => {
    logError("unhandled_request_error", err, { path: req.path });
    res.status(500).json({ error: err.message });
  });

  return app;
}

import { NextFunction, Request, Response } from "express";
import { config } from "./config";
import { logActivity } from "./logger";

/** Guards admin-only routes (withdrawal approval) with a shared secret header. */
export function requireAdmin(req: Request, res: Response, next: NextFunction): void {
  const suppliedKey = req.header("x-admin-key") || "";
  if (!config.adminApiKey || suppliedKey !== config.adminApiKey) {
    logActivity("admin_auth_rejected", { path: req.path, ip: req.ip });
    res.status(401).json({ error: "invalid or missing admin key" });
    return;
  }
  next();
}

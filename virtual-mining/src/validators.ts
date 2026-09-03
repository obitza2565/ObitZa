import { NextFunction, Request, Response } from "express";
import { body, param, validationResult } from "express-validator";

const USER_ID_PATTERN = /^[a-zA-Z0-9_-]{1,128}$/;
const WALLET_ADDRESS_PATTERN = /^0x[a-fA-F0-9]{40}$/;

/** Rejects requests with a 400 if any express-validator chain above it failed. */
export function validateRequest(req: Request, res: Response, next: NextFunction): void {
  const result = validationResult(req);
  if (!result.isEmpty()) {
    res.status(400).json({ error: "invalid request", details: result.array().map((e) => e.msg) });
    return;
  }
  next();
}

export const validateStartMining = [
  body("userId").trim().matches(USER_ID_PATTERN).withMessage("userId must be 1-128 alphanumeric/-/_ characters"),
  body("walletAddress").trim().matches(WALLET_ADDRESS_PATTERN).withMessage("walletAddress must be a valid 0x address"),
  body("ratePerHour").optional().isFloat({ gt: 0, lt: 1000 }).withMessage("ratePerHour must be between 0 and 1000"),
  validateRequest,
];

export const validateUserIdBody = [
  body("userId").trim().matches(USER_ID_PATTERN).withMessage("userId must be 1-128 alphanumeric/-/_ characters"),
  validateRequest,
];

export const validateUserIdParam = [
  param("userId").trim().matches(USER_ID_PATTERN).withMessage("userId must be 1-128 alphanumeric/-/_ characters"),
  validateRequest,
];

export const validateWithdraw = [
  body("userId").trim().matches(USER_ID_PATTERN).withMessage("userId must be 1-128 alphanumeric/-/_ characters"),
  body("walletAddress").trim().matches(WALLET_ADDRESS_PATTERN).withMessage("walletAddress must be a valid 0x address"),
  body("amount").isFloat({ gt: 0, lt: 100000 }).withMessage("amount must be a positive number below 100000"),
  validateRequest,
];

export const validateWithdrawalIdParam = [
  param("id").trim().isUUID().withMessage("id must be a valid withdrawal id"),
  validateRequest,
];

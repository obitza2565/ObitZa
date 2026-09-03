import fs from "fs";
import path from "path";
import winston from "winston";

const logsDir = path.join(__dirname, "..", "logs");
fs.mkdirSync(logsDir, { recursive: true });

const jsonWithTimestamp = winston.format.combine(winston.format.timestamp(), winston.format.json());

const activityLogger = winston.createLogger({
  level: "info",
  format: jsonWithTimestamp,
  transports: [new winston.transports.File({ filename: path.join(logsDir, "activity.log") })],
});

const errorLogger = winston.createLogger({
  level: "error",
  format: jsonWithTimestamp,
  transports: [new winston.transports.File({ filename: path.join(logsDir, "error.log") })],
});

if (process.env.NODE_ENV !== "production") {
  const consoleFormat = winston.format.combine(winston.format.timestamp(), winston.format.simple());
  activityLogger.add(new winston.transports.Console({ format: consoleFormat }));
  errorLogger.add(new winston.transports.Console({ format: consoleFormat }));
}

/** Records auth/session, mining, and deposit/withdrawal activity for audit purposes. */
export function logActivity(event: string, meta: Record<string, unknown> = {}): void {
  activityLogger.info(event, meta);
}

export function logError(event: string, err: unknown, meta: Record<string, unknown> = {}): void {
  const message = err instanceof Error ? err.message : String(err);
  errorLogger.error(event, { ...meta, error: message });
}

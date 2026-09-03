import "dotenv/config";

function envNumber(name: string, fallback: number): number {
  const raw = process.env[name];
  if (!raw) return fallback;
  const parsed = Number(raw);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function envList(name: string, fallback: string[]): string[] {
  const raw = process.env[name];
  if (!raw) return fallback;
  return raw.split(",").map((v) => v.trim()).filter(Boolean);
}

export const config = {
  port: envNumber("PORT", 4100),
  corsOrigins: envList("CORS_ORIGINS", []),

  // Fixed-price virtual mining economics.
  obzPriceUsdt: envNumber("OBZ_PRICE_USDT", 1),
  dailyMiningCapObz: envNumber("DAILY_MINING_CAP_OBZ", 100),
  defaultMiningRatePerHour: envNumber("DEFAULT_MINING_RATE_OBZ_PER_HOUR", 0.5),
  tickIntervalMs: envNumber("TICK_INTERVAL_MS", 1000),

  // Hot wallet / BNB Chain settings. Values are read lazily so the mining
  // simulator can run even before payout credentials are configured.
  bscRpcUrl: process.env.BSC_RPC_URL || "https://bsc-dataseed.binance.org/",
  obzTokenAddress: process.env.OBZ_TOKEN_ADDRESS || "",
  obzTokenDecimals: envNumber("OBZ_TOKEN_DECIMALS", 18),
  hotWalletPrivateKey: process.env.HOT_WALLET_PRIVATE_KEY || "",

  // Withdrawals above this USDT value require manual admin approval.
  withdrawalApprovalThresholdUsdt: envNumber("WITHDRAWAL_APPROVAL_THRESHOLD_USDT", 50),

  // Hot wallet low-balance alerting.
  minBnbGasBalance: envNumber("MIN_BNB_GAS_BALANCE", 0.02),
  minObzHotWalletBalance: envNumber("MIN_OBZ_HOT_WALLET_BALANCE", 100),
  balanceCheckIntervalMs: envNumber("BALANCE_CHECK_INTERVAL_MS", 5 * 60 * 1000),
  alertWebhookUrl: process.env.ALERT_WEBHOOK_URL || "",

  // Telegram notification channel (preferred). Create a bot via @BotFather
  // to get the token; the chat ID is your user/group chat identifier.
  telegramBotToken: process.env.TELEGRAM_BOT_TOKEN || "",
  telegramChatId: process.env.TELEGRAM_CHAT_ID || "",

  // Admin API access (required to approve/reject pending withdrawals).
  adminApiKey: process.env.ADMIN_API_KEY || "",

  // Per-IP request throttling.
  rateLimitWindowMs: envNumber("RATE_LIMIT_WINDOW_MS", 60_000),
  rateLimitMax: envNumber("RATE_LIMIT_MAX", 60),

  // Number of trusted reverse-proxy hops (1 = only the immediate proxy, e.g.
  // nginx). A boolean `true` would let any client spoof X-Forwarded-For and
  // bypass IP-based rate limiting, so a hop count is used instead.
  trustProxyHops: envNumber("TRUST_PROXY_HOPS", 1),
};

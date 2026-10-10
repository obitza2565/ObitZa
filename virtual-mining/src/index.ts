import { config } from "./config";
import { createServer } from "./server";
import { miningPool } from "./miningPool";
import { hotWallet } from "./hotWallet";
import { sendAlert } from "./notifier";
import { startTelegramBot, stopTelegramBot } from "./telegramBot";
import { logActivity, logError } from "./logger";

miningPool.start();

// Start Telegram bot if configured
startTelegramBot();

// Graceful shutdown
process.on("SIGINT", () => {
  stopTelegramBot();
  process.exit(0);
});
process.on("SIGTERM", () => {
  stopTelegramBot();
  process.exit(0);
});

/** Periodically checks hot wallet gas/token balances and alerts if either runs low. */
// Cooldown trackers: each alert fires at most once per ALERT_COOLDOWN_MS.
const ALERT_COOLDOWN_MS = 12 * 60 * 60 * 1000; // 12 hours
const lastAlertAt = { bnb: 0, obz: 0 };

async function checkHotWalletBalances(): Promise<void> {
  if (!config.hotWalletPrivateKey || !config.obzTokenAddress) return;

  try {
    const balances = await hotWallet.getBalances();
    const bnb = Number(balances.bnb);
    const obz = Number(balances.obz);
    const now = Date.now();

    if (bnb < config.minBnbGasBalance && now - lastAlertAt.bnb >= ALERT_COOLDOWN_MS) {
      lastAlertAt.bnb = now;
      await sendAlert(`⚠️ Hot wallet BNB gas balance is low: ${balances.bnb} BNB (address ${balances.address})\n<i>Reminder repeats every 12h until topped up</i>`);
    }
    if (obz < config.minObzHotWalletBalance && now - lastAlertAt.obz >= ALERT_COOLDOWN_MS) {
      lastAlertAt.obz = now;
      await sendAlert(`⚠️ Hot wallet OBZ balance is low: ${balances.obz} OBZ (address ${balances.address})\n<i>Reminder repeats every 12h until topped up</i>`);
    }
    logActivity("hot_wallet_balance_check", balances);
  } catch (err) {
    logError("hot_wallet_balance_check_failed", err);
  }
}

setInterval(checkHotWalletBalances, config.balanceCheckIntervalMs);
checkHotWalletBalances();

const app = createServer();
app.listen(config.port, () => {
  logActivity("service_started", { port: config.port });
  console.log(`OBZ virtual mining service listening on port ${config.port}`);
});

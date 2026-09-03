import { config } from "./config";
import { hotWallet } from "./hotWallet";
import { miningPool } from "./miningPool";
import { withdrawalLedger } from "./withdrawalLedger";
import { sendAlert } from "./notifier";
import { logActivity, logError } from "./logger";

const API_BASE = `https://api.telegram.org/bot${config.telegramBotToken}`;

let lastUpdateId = 0;
let pollTimer: NodeJS.Timeout | null = null;

/** Sends a message back to the configured chat. */
async function reply(text: string): Promise<void> {
  if (!config.telegramBotToken || !config.telegramChatId) return;
  
  try {
    await fetch(`${API_BASE}/sendMessage`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        chat_id: config.telegramChatId,
        text,
        parse_mode: "HTML",
        disable_web_page_preview: true,
      }),
    });
  } catch (err) {
    logError("telegram_reply_failed", err, { text });
  }
}

/** Formats hot wallet balances for display. */
async function getBalanceText(): Promise<string> {
  try {
    const b = await hotWallet.getBalances();
    const pool = miningPool.getPoolStatus();
    const pending = withdrawalLedger.list("PENDING").length;
    
    return `💰 <b>OBZ Hot Wallet Status</b>\n\n` +
      `Address: <code>${b.address}</code>\n` +
      `BNB (Gas): <b>${b.bnb}</b> BNB ${Number(b.bnb) < 0.02 ? "⚠️ LOW" : "✅"}\n` +
      `OBZ: <b>${Number(b.obz).toLocaleString()}</b> OBZ ${Number(b.obz) < 100 ? "⚠️ LOW" : "✅"}\n\n` +
      `📊 <b>Mining Pool Today</b>\n` +
      `Mined: ${pool.totalMinedTodayObz.toFixed(2)} / ${pool.dailyCapObz} OBZ\n` +
      `Remaining: ${pool.remainingObz.toFixed(2)} OBZ\n` +
      `Active Miners: ${pool.activeMiners}\n` +
      `Pending Withdrawals: ${pending}`;
  } catch (err) {
    return `❌ Error fetching balance: ${(err as Error).message}`;
  }
}

/** Handles incoming Telegram commands. */
async function handleCommand(text: string): Promise<void> {
  const cmd = text.toLowerCase().trim();
  logActivity("telegram_command", { command: cmd });

  if (cmd === "/start" || cmd === "/help") {
    await reply(
      `🤖 <b>OBZ Mining Bot Commands</b>\n\n` +
      `/balance - ดูยอดเงิน Hot Wallet และสถานะ Pool\n` +
      `/pending - ดูคำขอถอนที่รออนุมัติ\n` +
      `/status - สถานะระบบทั้งหมด\n` +
      `/help - แสดงคำสั่งทั้งหมด`
    );
  } else if (cmd === "/balance" || cmd === "balance" || cmd === "ยอดเงิน") {
    await reply(await getBalanceText());
  } else if (cmd === "/pending" || cmd === "pending") {
    const pending = withdrawalLedger.list("PENDING");
    if (pending.length === 0) {
      await reply("✅ ไม่มีคำขอถอนที่รออนุมัติ");
    } else {
      const list = pending.map(r => 
        `• ${r.userId}: ${r.amountObz} OBZ (${r.amountUsdt.toFixed(2)} USDT)\n  ID: <code>${r.id.slice(0, 8)}...</code>`
      ).join("\n\n");
      await reply(`⏳ <b>Pending Withdrawals (${pending.length})</b>\n\n${list}\n\nเปิด Admin Panel เพื่ออนุมัติ`);
    }
  } else if (cmd === "/status" || cmd === "status") {
    const pool = miningPool.getPoolStatus();
    await reply(
      `🟢 <b>System Online</b>\n\n` +
      `Server: Running\n` +
      `Mining Pool: ${pool.totalMinedTodayObz.toFixed(2)}/${pool.dailyCapObz} OBZ\n` +
      `Active Miners: ${pool.activeMiners}\n` +
      `Price: 1 OBZ = $${pool.obzPriceUsdt}`
    );
  } else if (cmd === "/alert" || cmd === "test") {
    await sendAlert("🔔 Test alert from Telegram bot");
    await reply("✅ Test alert sent! Check your notification channel.");
  } else {
    await reply("❓ ไม่รู้จักคำสั่งนี้ พิมพ์ /help เพื่อดูคำสั่งทั้งหมด");
  }
}

/** Polls Telegram for new messages (long polling). */
async function pollUpdates(): Promise<void> {
  if (!config.telegramBotToken || !config.telegramChatId) return;

  try {
    const res = await fetch(`${API_BASE}/getUpdates?offset=${lastUpdateId + 1}&timeout=30&limit=10`);
    const data = await res.json() as { ok: boolean; result?: Array<{ update_id: number; message?: { text?: string; chat: { id: number } } }> };
    
    if (!data.ok || !data.result) return;

    for (const update of data.result) {
      lastUpdateId = update.update_id;
      
      // Only respond to messages from the configured chat (security)
      if (update.message?.chat?.id?.toString() === config.telegramChatId && update.message?.text) {
        await handleCommand(update.message.text);
      }
    }
  } catch (err) {
    // Silently ignore polling errors (network issues, etc.)
  }
}

/** Starts the Telegram bot polling loop. */
export function startTelegramBot(): void {
  if (!config.telegramBotToken || !config.telegramChatId) {
    logActivity("telegram_bot_disabled", { reason: "missing token or chat_id" });
    return;
  }

  logActivity("telegram_bot_started", { chatId: config.telegramChatId });
  
  // Poll every 5 seconds
  pollTimer = setInterval(pollUpdates, 5000);
  pollUpdates(); // Initial poll
}

/** Stops the Telegram bot. */
export function stopTelegramBot(): void {
  if (pollTimer) {
    clearInterval(pollTimer);
    pollTimer = null;
  }
}

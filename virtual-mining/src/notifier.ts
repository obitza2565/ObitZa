import { config } from "./config";
import { logActivity, logError } from "./logger";

/** Sends a message to the configured Telegram chat via the Bot API. */
async function sendTelegram(message: string): Promise<boolean> {
  if (!config.telegramBotToken || !config.telegramChatId) return false;

  const url = `https://api.telegram.org/bot${config.telegramBotToken}/sendMessage`;
  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      chat_id: config.telegramChatId,
      text: message,
      parse_mode: "HTML",
      disable_web_page_preview: true,
    }),
  });
  if (!res.ok) {
    throw new Error(`telegram api responded ${res.status}`);
  }
  return true;
}

/** Posts a message to the configured webhook (Discord/Slack-compatible payload). */
async function sendWebhook(message: string): Promise<boolean> {
  if (!config.alertWebhookUrl) return false;

  const res = await fetch(config.alertWebhookUrl, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ content: message, text: message }),
  });
  if (!res.ok) {
    throw new Error(`webhook responded ${res.status}`);
  }
  return true;
}

/**
 * Delivers an alert to every configured channel (Telegram first, then
 * webhook). Always records the alert in the activity log so events are
 * never lost even if delivery fails.
 */
export async function sendAlert(message: string): Promise<void> {
  logActivity("alert_triggered", { message });

  const attempts: Array<() => Promise<boolean>> = [
    () => sendTelegram(message),
    () => sendWebhook(message),
  ];

  for (const attempt of attempts) {
    try {
      if (await attempt()) return;
    } catch (err) {
      logError("alert_delivery_failed", err, { message });
    }
  }
}

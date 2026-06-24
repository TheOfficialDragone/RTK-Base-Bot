# RTK Base Station Telegram Monitor

A lightweight Shell script (`.sh`) designed to monitor your RTK base station status and send real-time alerts directly to a Telegram bot when issues arise. Keep your high-precision positioning system running smoothly with instant notifications.

---

## 🚀 Features

* **Real-time Monitoring:** Continuously or periodically checks the health and connectivity of your RTK base station.
* **Instant Telegram Alerts:** Sends immediate notifications regarding downtime, signal loss, or hardware issues straight to your pocket.
* **Lightweight & Efficient:** Written in pure Shell script, requiring minimal dependencies and system resources.

---

## 🛠️ Prerequisites

Before running the script, ensure you have:
* A configured and running RTK base station.
* `curl` installed on your system (used for sending Telegram API requests).
* A Telegram Bot Token and Chat ID. (If you don't have them, you can create a bot via [@BotFather](https://t.me/BotFather)).

---

## 📦 Quick Start & Configuration

1. Clone this repository to your local machine or RTK server.
2. Open the script and fill in your specific Telegram credentials and station parameters:
   ```bash
   TELEGRAM_BOT_TOKEN="your_bot_token_here"
   TELEGRAM_CHAT_ID="your_chat_id_here"

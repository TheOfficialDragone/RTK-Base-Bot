# RTK Base Monitor — Telegram Bot

Lightweight bash script that monitors a GNSS RTK base station on Raspberry Pi and sends real-time alerts via Telegram. Designed for **rtkbase v2.7** (Stefal) with **u-blox ZED-F9P** receiver.

---

## Features

- Long polling Telegram — commands answered in under 3 seconds
- Automatic monitoring every 60 seconds
- Alerts only on state change (no spam on repeated failures)
- Disconnection counter with hourly reset
- Full hardware monitoring: CPU, RAM, swap, disk, temperature
- Reboot detection via boot ID
- Sender authorization — only your Chat ID can trigger commands
- NTRIP end-to-end test for local caster and public network

---

## Prerequisites

- Raspberry Pi running **Raspberry Pi OS Debian 12+**
- **rtkbase v2.7** installed and running (services: `str2str_tcp`, `str2str_ntrip_A`, `str2str_ntrip_B`)
- `curl`, `getent`, `vmstat`, `ss`, `nc` — all included in Raspberry Pi OS
- A Telegram bot token and Chat ID (create via [@BotFather](https://t.me/BotFather))

---

## Configuration

Edit the variables at the top of `rtk_monitor.sh`:

```bash
TOKEN="your_bot_token_here"       # from @BotFather
CHAT_ID="your_chat_id_here"       # your personal Telegram chat ID

DELL_IP="192.168.1.37"            # IP of your local NTRIP caster (SNIP/RTKLIB)
INTERVAL=60                       # seconds between automatic checks

# NTRIP local caster (for /ntrip end-to-end test)
SNIP_HOST="192.168.1.37"
SNIP_PORT="2101"
SNIP_MOUNT="YOUR-MOUNT"
SNIP_USER="your_user"
SNIP_PASS="your_pass"

# Public NTRIP network (Centipede or similar)
CENTIPEDE_HOST="crtk.net"
CENTIPEDE_PORT="2101"
CENTIPEDE_MOUNT="YOUR-MOUNT"
```

---

## Installation

```bash
# 1. Copy script to Raspberry Pi
scp rtk_monitor.sh basegnss@192.168.1.72:/home/basegnss/rtk_monitor.sh

# 2. Make executable
chmod +x /home/basegnss/rtk_monitor.sh

# 3. Create systemd service
sudo nano /etc/systemd/system/monitor-rtk.service
```

Service file:

```ini
[Unit]
Description=RTK Base Monitor Telegram Bot
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=basegnss
ExecStart=/bin/bash /home/basegnss/rtk_monitor.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

```bash
# 4. Enable and start
sudo systemctl daemon-reload
sudo systemctl enable monitor-rtk
sudo systemctl start monitor-rtk

# 5. Check logs
sudo journalctl -u monitor-rtk -f
```

---

## Update

```bash
wget -O /home/basegnss/rtk_monitor.sh \
  https://raw.githubusercontent.com/TheOfficialDragone/RTK-Base-Bot/main/rtk_monitor.sh
sudo systemctl restart monitor-rtk
```

---

## Bot Commands

| Command | Response |
|---------|----------|
| `/stato` | Full status: connections + hardware (CPU, RAM, swap, disk, temp, IP) |
| `/uptime` | Raspberry Pi uptime + Dell SNIP connection duration |
| `/log` | Last 5 lines of rtkbase log (`~/rtkbase/logs/`) |
| `/satelliti` | GNSS satellite count and fix status via gpsd |
| `/ntrip` | End-to-end NTRIP test on local caster and public network |
| `/help` | Command list and alert thresholds |

---

## Automatic Alerts

Alerts fire only when status **changes** (DOWN or UP). Every alarm has a corresponding recovery notification.

| Alert | Trigger |
|-------|---------|
| ❌ Internet lost | ping 8.8.8.8 fails |
| ❌ Dell SNIP disconnected | TCP connection to `DELL_IP:2101` missing |
| ❌ Centipede disconnected | TCP connection to `crtk.net:2101` missing |
| ❌ str2str stopped | `str2str_tcp`, `str2str_ntrip_A` or `str2str_ntrip_B` inactive |
| ❌ gpsd stopped | process not found |
| 🌡 High temperature | CPU temp > 75°C |
| 🧠 High RAM | RAM usage > 80% |
| 💾 Swap almost full | Swap usage > 90% |
| 💿 Disk almost full | Disk usage > 80% |
| ⚠️ Raspberry rebooted | boot ID changed |

---

## Test Scripts

### `test_allarmi.sh` — Connectivity test (safe, no services touched)

Sends all alarm messages directly to Telegram via curl. Tests token, Chat ID, network, and message formatting.

```bash
wget -O ~/test_allarmi.sh \
  https://raw.githubusercontent.com/TheOfficialDragone/RTK-Base-Bot/main/test_allarmi.sh
bash ~/test_allarmi.sh /home/basegnss/rtk_monitor.sh
```

### `test_reale.sh` — Real end-to-end test (stops actual services)

Stops each service one at a time via `systemctl stop` (no auto-restart triggered), waits 70s for the monitor to detect the fault, then restarts and waits for the recovery alert. Interactive — asks you to confirm each Telegram alert received.

```bash
wget -O ~/test_reale.sh \
  https://raw.githubusercontent.com/TheOfficialDragone/RTK-Base-Bot/main/test_reale.sh
sudo bash ~/test_reale.sh
```

Services tested: `gpsd`, `str2str_ntrip_A`, `str2str_ntrip_B`, `str2str_tcp` (master).  
Estimated time: ~10 minutes.

---

## Files

| File | Description |
|------|-------------|
| `rtk_monitor.sh` | Main monitoring script |
| `test_allarmi.sh` | Telegram connectivity and formatting test |
| `test_reale.sh` | Real end-to-end test (stops/starts services) |
| `documentation_rtk_bot_english.pdf` | Full documentation |

---

## Architecture

```
ZED-F9P (USB) → str2str_tcp :5015
                    ├── str2str_ntrip_A → Local NTRIP caster (Dell SNIP)
                    ├── str2str_ntrip_B → Public NTRIP (Centipede)
                    └── gpsd → chrony (time sync)

monitor-rtk.service (this script) → Telegram Bot API
```

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Bot does not respond | `sudo systemctl status monitor-rtk` |
| Service keeps restarting | `sudo journalctl -u monitor-rtk -n 50` |
| `str2str` always shown as stopped | Check process name: `pgrep -a str2str` |
| `/log` shows nothing | Check log dir: `ls ~/rtkbase/logs/` |

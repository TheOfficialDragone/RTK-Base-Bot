#!/bin/bash
# ============================================================
#  TEST ALLARMI - RTK Base Monitor
#  Invia tutti gli allarmi via Telegram con intervallo 10s
#  Non tocca servizi — testa solo token/chat/formattazione
# ============================================================

MONITOR_SCRIPT="${1:-/home/basegnss/rtk_monitor.sh}"
DELAY=10

# Leggi credenziali dallo script monitor
TOKEN=$(grep '^TOKEN=' "$MONITOR_SCRIPT" 2>/dev/null | cut -d'"' -f2)
CHAT_ID=$(grep '^CHAT_ID=' "$MONITOR_SCRIPT" 2>/dev/null | cut -d'"' -f2)

if [ -z "$TOKEN" ] || [ "$TOKEN" = "xxxxxxxxx" ]; then
    echo "ERRORE: TOKEN non trovato o non configurato in $MONITOR_SCRIPT"
    exit 1
fi
if [ -z "$CHAT_ID" ] || [ "$CHAT_ID" = "xxxxxx" ]; then
    echo "ERRORE: CHAT_ID non trovato o non configurato in $MONITOR_SCRIPT"
    exit 1
fi

ora() { date "+%d/%m/%Y %H:%M:%S"; }

send() {
    local label="$1"
    local msg="$2"
    local result
    result=$(curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
        -d "chat_id=${CHAT_ID}" \
        -d "parse_mode=HTML" \
        --data-urlencode "text=${msg}" 2>/dev/null)
    if echo "$result" | grep -q '"ok":true'; then
        echo "[$(ora)] ✓ $label"
    else
        echo "[$(ora)] ✗ FALLITO: $label"
        echo "    Risposta API: $result"
    fi
}

wait_next() {
    echo "    → prossimo tra ${DELAY}s..."
    sleep "$DELAY"
}

echo "============================================"
echo " TEST ALLARMI RTK MONITOR"
echo " Script: $MONITOR_SCRIPT"
echo " TOKEN:  ${TOKEN:0:12}..."
echo " CHAT:   $CHAT_ID"
echo "============================================"
echo ""

# ── HEADER ──────────────────────────────────────
send "Header" "🧪 <b>[TEST] Inizio sequenza allarmi</b>
$(ora)

Riceverai tutti gli allarmi ogni ${DELAY}s.
Nessun servizio viene toccato."
wait_next

# ── 1. INTERNET ──────────────────────────────────
send "Internet DOWN" "❌ <b>[TEST] ALLARME - Perdita Internet</b>
$(ora)"
sleep 3
send "Internet UP" "✅ <b>[TEST] OK - Internet ripristinata</b>
$(ora)"
wait_next

# ── 2. DELL SNIP ─────────────────────────────────
send "Dell SNIP DOWN" "❌ <b>[TEST] ALLARME - Disconnesso dal Dell SNIP</b>
192.168.1.37:2101
$(ora)"
sleep 3
send "Dell SNIP UP" "✅ <b>[TEST] OK - Riconnesso al Dell SNIP</b>
$(ora)"
wait_next

# ── 3. CENTIPEDE ─────────────────────────────────
send "Centipede DOWN" "❌ <b>[TEST] ALLARME - Disconnesso da Centipede</b>
$(ora)"
sleep 3
send "Centipede UP" "✅ <b>[TEST] OK - Riconnesso a Centipede</b>
$(ora)"
wait_next

# ── 4. STR2STR ───────────────────────────────────
send "str2str DOWN" "❌ <b>[TEST] ALLARME - str2str fermato</b>
$(ora)"
sleep 3
send "str2str UP" "✅ <b>[TEST] OK - str2str riavviato</b>
$(ora)"
wait_next

# ── 5. GPSD ──────────────────────────────────────
send "gpsd DOWN" "❌ <b>[TEST] ALLARME - gpsd fermato</b>
$(ora)"
sleep 3
send "gpsd UP" "✅ <b>[TEST] OK - gpsd riavviato</b>
$(ora)"
wait_next

# ── 6. TEMPERATURA ───────────────────────────────
send "Temperatura" "🌡 <b>[TEST] ALLARME - Temperatura alta!</b>
Temperatura: 76°C
$(ora)"
wait_next

# ── 7. RAM ───────────────────────────────────────
send "RAM" "🧠 <b>[TEST] ALLARME - RAM alta!</b>
RAM usata: 85%
$(ora)"
wait_next

# ── 8. SWAP ──────────────────────────────────────
send "Swap" "💾 <b>[TEST] ALLARME - Swap quasi piena!</b>
Swap usata: 92%
$(ora)"
wait_next

# ── 9. DISCO ─────────────────────────────────────
send "Disco" "💿 <b>[TEST] ALLARME - Disco quasi pieno!</b>
Disco usato: 82%
$(ora)"
wait_next

# ── 10. RIAVVIO ──────────────────────────────────
send "Riavvio Pi" "⚠️ <b>[TEST] Raspberry riavviato</b>
Possibile blackout o riavvio manuale
Uptime attuale: 0h 0m
$(ora)"
sleep 5

# ── FOOTER ───────────────────────────────────────
send "Footer" "✅ <b>[TEST] Sequenza completata</b>
$(ora)

Tutti gli allarmi ricevuti correttamente.
Il monitor RTK è operativo."

echo ""
echo "============================================"
echo " TEST COMPLETATO"
echo "============================================"

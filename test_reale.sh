#!/bin/bash
# ============================================================
#  TEST REALE ALLARMI - RTK Base Monitor
#  Ferma servizi uno alla volta, verifica che il monitor
#  rilevi il guasto e mandi l'allarme Telegram reale.
#  systemctl stop NON triggera il restart automatico.
# ============================================================

WAIT=70   # secondi da aspettare dopo stop/start (ciclo monitor = 60s)

ora() { date "+%d/%m/%Y %H:%M:%S"; }

header() {
    echo ""
    echo "════════════════════════════════════════"
    echo " $1"
    echo "════════════════════════════════════════"
}

status_service() {
    local svc="$1"
    local state
    state=$(systemctl is-active "$svc" 2>/dev/null)
    echo "  $svc → $state"
}

check_all_running() {
    echo "Stato servizi prima del test:"
    status_service str2str_tcp
    status_service str2str_ntrip_A
    status_service str2str_ntrip_B
    status_service gpsd
    echo ""
    local all_ok=1
    for svc in str2str_tcp str2str_ntrip_A str2str_ntrip_B gpsd; do
        if ! systemctl is-active --quiet "$svc"; then
            echo "ATTENZIONE: $svc non è attivo — skippo nel test"
            all_ok=0
        fi
    done
    echo ""
    [ $all_ok -eq 1 ] && echo "Tutti i servizi sono attivi. Pronti per il test." || true
}

test_service() {
    local service="$1"
    local label="$2"
    local extra_services="${3:-}"

    header "TEST: $label ($service)"

    if ! systemctl is-active --quiet "$service"; then
        echo "  SKIP: $service già non attivo"
        return
    fi

    echo "  [$(ora)] Fermo $service..."
    systemctl stop $service $extra_services 2>/dev/null
    sleep 1
    echo "  Stato dopo stop:"
    status_service "$service"
    [ -n "$extra_services" ] && for s in $extra_services; do status_service "$s"; done

    echo ""
    echo "  Attendo ${WAIT}s che il monitor (ciclo 60s) rilevi il guasto..."
    echo "  → Controlla Telegram: deve arrivare l'allarme ❌"

    local i=$WAIT
    while [ $i -gt 0 ]; do
        printf "\r  Countdown: %2ds " $i
        sleep 1
        i=$((i-1))
    done
    echo ""
    echo ""

    read -rp "  Allarme ricevuto su Telegram? [s/n]: " risposta
    echo ""

    echo "  [$(ora)] Riavvio $service..."
    systemctl start "$service"
    [ -n "$extra_services" ] && systemctl start $extra_services 2>/dev/null
    sleep 2
    echo "  Stato dopo start:"
    status_service "$service"
    [ -n "$extra_services" ] && for s in $extra_services; do status_service "$s"; done

    echo ""
    echo "  Attendo ${WAIT}s per recovery alert..."
    echo "  → Controlla Telegram: deve arrivare il OK ✅"

    i=$WAIT
    while [ $i -gt 0 ]; do
        printf "\r  Countdown: %2ds " $i
        sleep 1
        i=$((i-1))
    done
    echo ""
    echo ""

    read -rp "  Recovery ricevuto su Telegram? [s/n]: " risposta2
    echo "  Risultato: allarme=$risposta recovery=$risposta2"
}

# ── MAIN ─────────────────────────────────────────────────────

if [ "$(id -u)" -ne 0 ]; then
    echo "ERRORE: eseguire con sudo"
    echo "  sudo bash test_reale.sh"
    exit 1
fi

header "TEST REALE ALLARMI RTK MONITOR"
echo "Ogni test ferma UN servizio alla volta."
echo "Il monitor ha ciclo 60s → attesa ${WAIT}s per ogni rilevamento."
echo "Tempo totale stimato: ~$((WAIT * 2 * 4 / 60)) minuti."
echo ""
check_all_running

read -rp "Premi INVIO per iniziare o CTRL+C per annullare..."

# ── 1. GPSD ──────────────────────────────────────────────────
test_service "gpsd" "gpsd"

# ── 2. STR2STR NTRIP_A (Dell SNIP) ──────────────────────────
# Fermare ntrip_A rimuove la connessione TCP a Dell →
# scattano sia check_str2str che check_dell
test_service "str2str_ntrip_A" "str2str ntrip_A + Dell SNIP"

# ── 3. STR2STR NTRIP_B (Centipede) ──────────────────────────
test_service "str2str_ntrip_B" "str2str ntrip_B + Centipede"

# ── 4. STR2STR_TCP (master) ──────────────────────────────────
# Fermarlo causa anche stop di ntrip_A e ntrip_B (Requires=)
test_service "str2str_tcp" "str2str_tcp master" "str2str_ntrip_A str2str_ntrip_B"

# ── RIEPILOGO ────────────────════════════════════════════════
header "TEST COMPLETATO"
echo "Stato finale servizi:"
status_service str2str_tcp
status_service str2str_ntrip_A
status_service str2str_ntrip_B
status_service gpsd
echo ""
echo "Se qualche servizio è ancora down: sudo systemctl start <nome>"

#!/bin/bash
# ============================================================
#  MONITOR BASE RTK v6
#  - Long polling 2 secondi (risposta rapida)
#  - Comandi: /stato /uptime /log /satelliti /ntrip /help
#  - Allarmi: disconnessione, temperatura, RAM, swap, disco
#  - Allarme riavvio Raspberry
#  - Contatore disconnessioni ultima ora
#  - Test NTRIP end-to-end caster Dell e Centipede
# ============================================================

TOKEN="xxxxxxxxx"
CHAT_ID="xxxxxx"
DELL_IP="192.168.1.37"
INTERVAL=60
LAST_UPDATE_ID=0
last_check=0
BOOT_FILE="/home/basegnss/.last_boot_id"

# Configurazione test NTRIP
SNIP_HOST="192.168.1.37"
SNIP_PORT="2101"
SNIP_MOUNT="CARPI-FARM"
SNIP_USER="Monitor"
SNIP_PASS="Pippo1"
CENTIPEDE_HOST="crtk.net"
CENTIPEDE_PORT="2101"
CENTIPEDE_MOUNT="CRPF"

# Stato precedente
prev_internet=1
prev_dell=1
prev_centipede=1
prev_str2str=1
prev_gpsd=1

# Contatori disconnessioni ultima ora
disc_internet=0
disc_dell=0
disc_centipede=0
disc_str2str=0
disc_gpsd=0
last_counter_reset=$(date +%s)

# Timestamp connessione Dell
dell_connected_since=$(date +%s)

telegram() {
    curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
        -d "chat_id=${CHAT_ID}" \
        -d "parse_mode=HTML" \
        -d "text=$1" > /dev/null 2>&1
}

ora() { date "+%d/%m/%Y %H:%M:%S"; }

check_internet()  { ping -c1 -W3 8.8.8.8 > /dev/null 2>&1 && echo 1 || echo 0; }
check_dell()      { ss -tnp | grep -q "${DELL_IP}:2101" && echo 1 || echo 0; }
check_centipede() {
    local ip
    ip=$(getent ahostsv4 "${CENTIPEDE_HOST}" 2>/dev/null | awk 'NR==1{print $1}')
    [ -n "$ip" ] && ss -tnp | grep -q "${ip}:${CENTIPEDE_PORT}" && echo 1 || echo 0
}
check_str2str()   { systemctl is-active --quiet str2str_tcp && systemctl is-active --quiet str2str_ntrip_A && systemctl is-active --quiet str2str_ntrip_B && echo 1 || echo 0; }
check_gpsd()      { pgrep -x gpsd > /dev/null 2>&1 && echo 1 || echo 0; }
emojione()        { [ "$1" -eq 1 ] && echo "✅" || echo "❌"; }

# Hardware
get_temperatura() {
    local temp=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
    [ -n "$temp" ] && echo "$((temp/1000))°C" || echo "N/D"
}
get_temp_raw()   { cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo 0; }
get_cpu()        { vmstat 1 2 2>/dev/null | awk 'END{print 100-$15}'; }
get_ram()        { free -m | awk '/^Mem:/ {printf "Usata: %dMB / %dMB (libera: %dMB) - %d%%", $3, $2, $4, ($3/$2)*100}'; }
get_ram_pct()    { free -m | awk '/^Mem:/ {printf "%d", ($3/$2)*100}'; }
get_swap()       { free -m | awk '/^Swap:/ {if ($2>0) printf "Usata: %dMB / %dMB - %d%%", $3, $2, ($3/$2)*100; else print "N/D"}'; }
get_swap_pct()   { free -m | awk '/^Swap:/ {if ($2>0) printf "%d", ($3/$2)*100; else print "0"}'; }
get_disco()      { df -h / | awk 'NR==2 {printf "Usato: %s / %s (%s)", $3, $2, $5}'; }
get_disco_pct()  { df / | awk 'NR==2 {gsub("%","",$5); print $5}'; }
get_uptime()     { uptime -p | sed 's/up //'; }
get_carico()     { uptime | awk -F'load average:' '{print $2}' | xargs; }
get_ip()         { hostname -I | awk '{print $1}'; }

get_dell_uptime() {
    local now=$(date +%s)
    local diff=$((now - dell_connected_since))
    local h=$((diff/3600))
    local m=$(((diff%3600)/60))
    echo "${h}h ${m}m"
}

get_log() {
    local logdir="/home/basegnss/rtkbase/logs"
    local log_file
    log_file=$(ls -t "${logdir}"/str2str_tcp_*.log 2>/dev/null | head -1)
    [ -z "$log_file" ] && log_file=$(ls -t "${logdir}"/str2str_ntrip_A*.log 2>/dev/null | head -1)
    if [ -n "$log_file" ] && [ -f "$log_file" ]; then
        tail -5 "$log_file" 2>/dev/null
    else
        journalctl -u str2str_tcp --no-pager -n 5 2>/dev/null || echo "Log non disponibile"
    fi
}

get_satelliti() {
    local raw
    raw=$( (echo '?WATCH={"enable":true,"json":true};'; sleep 2) | timeout 4 nc 127.0.0.1 2947 2>/dev/null)

    if [ -z "$raw" ]; then
        echo "N/D (gpsd non risponde sulla porta 2947)"
        return
    fi

    local sky=$(echo "$raw" | grep -m1 '"class":"SKY"')
    local tpv=$(echo "$raw" | grep -m1 '"class":"TPV"')

    local nsat=0
    local ntot=0
    if [ -n "$sky" ]; then
        nsat=$(echo "$sky" | grep -o '"used":true' | wc -l)
        ntot=$(echo "$sky" | grep -o '"PRN"' | wc -l)
    fi

    local mode=""
    [ -n "$tpv" ] && mode=$(echo "$tpv" | grep -o '"mode":[0-9]' | head -1 | grep -o '[0-9]$')

    local fixstr="Nessun fix"
    case "$mode" in
        2) fixstr="Fix 2D" ;;
        3) fixstr="Fix 3D" ;;
    esac

    if [ "$ntot" -eq 0 ] && [ -z "$tpv" ]; then
        echo "N/D (nessun dato SKY/TPV ricevuto, riprova)"
        return
    fi

    echo "Satelliti usati: ${nsat} / ${ntot} visibili%0AStato fix: ${fixstr}"
}

# Test NTRIP end-to-end: si connette come client e verifica che arrivino bytes
ntrip_test() {
    # $1=label $2=host $3=port $4=mount $5=user $6=pass
    local label=$1 host=$2 port=$3 mount=$4 user=$5 pass=$6
    local tmpfile=$(mktemp)

    local auth=""
    if [ -n "$user" ] && [ -n "$pass" ] && [ "$user" != "INSERISCI_USER_SNIP" ]; then
        auth="Authorization: Basic $(echo -n "${user}:${pass}" | base64 -w0)\r\n"
    fi

    local request="GET /${mount} HTTP/1.0\r\nUser-Agent: NTRIP MonitorRTK/1.0\r\n${auth}Accept: */*\r\nConnection: close\r\n\r\n"

    ( printf "$request"; sleep 3 ) | timeout 5 nc -w 5 "$host" "$port" > "$tmpfile" 2>/dev/null

    if [ ! -s "$tmpfile" ]; then
        rm -f "$tmpfile"
        echo "<b>❌ ${label}</b>%0AConnessione fallita o caster offline"
        return
    fi

    local header=$(head -c 200 "$tmpfile" | head -1 | tr -d '\r')
    local total_bytes=$(stat -c%s "$tmpfile")
    local data_bytes=$total_bytes

    case "$header" in
        *"ICY 200"*)
            data_bytes=$((total_bytes - 17))
            [ $data_bytes -lt 0 ] && data_bytes=0
            local kbps=$(awk "BEGIN {printf \"%.1f\", ($data_bytes*8)/3000}")
            if [ $data_bytes -gt 100 ]; then
                echo "<b>✅ ${label}</b>%0AStream attivo%0ABytes: ${data_bytes} in 3s%0AThroughput: ~${kbps} kbps"
            else
                echo "<b>⚠️ ${label}</b>%0ACaster risponde ma flusso vuoto%0AIl mountpoint potrebbe essere down"
            fi
            ;;
        *"SOURCETABLE 200"*)
            echo "<b>⚠️ ${label}</b>%0AMountpoint '${mount}' non trovato%0ARisposta: source table"
            ;;
        *"401"*)
            echo "<b>❌ ${label}</b>%0ACredenziali errate (401)"
            ;;
        *"403"*)
            echo "<b>❌ ${label}</b>%0AAccesso negato (403)"
            ;;
        *)
            if [ $total_bytes -gt 100 ]; then
                local kbps=$(awk "BEGIN {printf \"%.1f\", ($total_bytes*8)/3000}")
                echo "<b>✅ ${label}</b>%0ARisposta non standard ma flusso presente%0ABytes: ${total_bytes} (~${kbps} kbps)"
            else
                echo "<b>❌ ${label}</b>%0ARisposta sconosciuta o vuota"
            fi
            ;;
    esac

    rm -f "$tmpfile"
}

check_reboot() {
    local current_boot=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)
    if [ ! -f "$BOOT_FILE" ]; then
        echo "$current_boot" > "$BOOT_FILE"
        return
    fi
    local saved_boot=$(cat "$BOOT_FILE" 2>/dev/null)
    if [ "$current_boot" != "$saved_boot" ]; then
        telegram "<b>⚠️ Raspberry riavviato</b>%0APossibile blackout o riavvio manuale%0AUptime attuale: $(get_uptime)%0A$(ora)"
        echo "$current_boot" > "$BOOT_FILE"
        echo "[$(ora)] WARN: Rilevato riavvio del Raspberry"
        dell_connected_since=$(date +%s)
    fi
}

stato_completo() {
    local i=$(check_internet)
    local d=$(check_dell)
    local c=$(check_centipede)
    local s=$(check_str2str)
    local g=$(check_gpsd)

    echo "<b>Stato Base RTK CARPI-FARM</b>%0A$(ora)%0A%0A<b>Connessioni:</b>%0A$(emojione $i) Internet%0A$(emojione $d) Dell SNIP (${DELL_IP}:2101)%0A$(emojione $c) Centipede%0A$(emojione $s) str2str%0A$(emojione $g) gpsd%0A%0A<b>Stabilita connessione Dell:</b>%0A⏱ Connesso da: $(get_dell_uptime)%0A%0A<b>Disconnessioni ultima ora:</b>%0A📶 Internet: ${disc_internet}x%0A🖥 Dell: ${disc_dell}x%0A🛰 Centipede: ${disc_centipede}x%0A⚙️ str2str: ${disc_str2str}x%0A📡 gpsd: ${disc_gpsd}x%0A%0A<b>Hardware Raspberry Pi:</b>%0A🌡 Temperatura: $(get_temperatura)%0A💻 CPU: $(get_cpu)%25%0A📊 Carico: $(get_carico)%0A🧠 RAM: $(get_ram)%0A💾 Swap: $(get_swap)%0A💿 Disco: $(get_disco)%0A⏱ Uptime: $(get_uptime)%0A🌐 IP LAN: $(get_ip)"
}

monitoraggio() {
    check_reboot

    local internet=$(check_internet)
    local dell=$(check_dell)
    local centipede=$(check_centipede)
    local str2str=$(check_str2str)
    local gpsd=$(check_gpsd)

    [ $internet -eq 0 ] && [ $prev_internet -eq 1 ] && telegram "<b>❌ ALLARME - Perdita Internet</b>%0A$(ora)" && disc_internet=$((disc_internet+1))
    [ $internet -eq 1 ] && [ $prev_internet -eq 0 ] && telegram "<b>✅ OK - Internet ripristinata</b>%0A$(ora)"

    if [ $dell -eq 0 ] && [ $prev_dell -eq 1 ]; then
        telegram "<b>❌ ALLARME - Disconnesso dal Dell SNIP</b>%0A${DELL_IP}:2101%0A$(ora)"
        disc_dell=$((disc_dell+1))
    elif [ $dell -eq 1 ] && [ $prev_dell -eq 0 ]; then
        telegram "<b>✅ OK - Riconnesso al Dell SNIP</b>%0A$(ora)"
        dell_connected_since=$(date +%s)
    fi

    [ $centipede -eq 0 ] && [ $prev_centipede -eq 1 ] && telegram "<b>❌ ALLARME - Disconnesso da Centipede</b>%0A$(ora)" && disc_centipede=$((disc_centipede+1))
    [ $centipede -eq 1 ] && [ $prev_centipede -eq 0 ] && telegram "<b>✅ OK - Riconnesso a Centipede</b>%0A$(ora)"

    [ $str2str -eq 0 ] && [ $prev_str2str -eq 1 ] && telegram "<b>❌ ALLARME - str2str fermato</b>%0A$(ora)" && disc_str2str=$((disc_str2str+1))
    [ $str2str -eq 1 ] && [ $prev_str2str -eq 0 ] && telegram "<b>✅ OK - str2str riavviato</b>%0A$(ora)"

    [ $gpsd -eq 0 ] && [ $prev_gpsd -eq 1 ] && telegram "<b>❌ ALLARME - gpsd fermato</b>%0A$(ora)" && disc_gpsd=$((disc_gpsd+1))
    [ $gpsd -eq 1 ] && [ $prev_gpsd -eq 0 ] && telegram "<b>✅ OK - gpsd riavviato</b>%0A$(ora)"

    local temp_raw=$(get_temp_raw)
    [ "$temp_raw" -gt 75000 ] && telegram "<b>🌡 ALLARME - Temperatura alta!</b>%0ATemperatura: $((temp_raw/1000))°C%0A$(ora)"

    local ram_pct=$(get_ram_pct)
    [ "$ram_pct" -gt 80 ] && telegram "<b>🧠 ALLARME - RAM alta!</b>%0ARAM usata: ${ram_pct}%25%0A$(ora)"

    local swap_pct=$(get_swap_pct)
    [ "$swap_pct" -gt 90 ] && telegram "<b>💾 ALLARME - Swap quasi piena!</b>%0ASwap usata: ${swap_pct}%25%0A$(ora)"

    local disco_pct=$(get_disco_pct)
    [ "$disco_pct" -gt 80 ] && telegram "<b>💿 ALLARME - Disco quasi pieno!</b>%0ADisco usato: ${disco_pct}%25%0A$(ora)"

    local now=$(date +%s)
    if [ $((now - last_counter_reset)) -ge 3600 ]; then
        disc_internet=0; disc_dell=0; disc_centipede=0
        disc_str2str=0; disc_gpsd=0
        last_counter_reset=$now
        echo "[$(ora)] Contatori resettati"
    fi

    prev_internet=$internet
    prev_dell=$dell
    prev_centipede=$centipede
    prev_str2str=$str2str
    prev_gpsd=$gpsd
}

# Avvio
echo "[$(ora)] Monitor Base RTK v6 avviato"
cat /proc/sys/kernel/random/boot_id 2>/dev/null > "$BOOT_FILE"
telegram "<b>🛰 Base RTK Online</b>%0AMonitor v6 avviato alle $(ora)%0A%0AComandi: /stato /uptime /log /satelliti /ntrip /help"

# Loop principale
while true; do

    response=$(curl -s --max-time 3 \
        "https://api.telegram.org/bot${TOKEN}/getUpdates?offset=$((LAST_UPDATE_ID+1))&timeout=2")

    update_id=$(echo "$response" | grep -o '"update_id":[0-9]*' | tail -1 | grep -o '[0-9]*')
    text=$(echo "$response" | grep -o '"text":"[^"]*"' | tail -1 | sed 's/"text":"//;s/"//')

    if [ -n "$update_id" ] && [ "$update_id" -gt "$LAST_UPDATE_ID" ]; then
        LAST_UPDATE_ID=$update_id
        case "$text" in
            /stato*)
                telegram "$(stato_completo)"
                echo "[$(ora)] Comando /stato"
                ;;
            /uptime*)
                telegram "<b>⏱ Uptime Raspberry</b>%0A$(get_uptime)%0A%0A<b>Connessione Dell:</b>%0AAttiva da: $(get_dell_uptime)"
                echo "[$(ora)] Comando /uptime"
                ;;
            /log*)
                log_content=$(get_log | tr '\n' '|' | sed 's/|/%0A/g')
                telegram "<b>📋 Ultime righe log:</b>%0A%0A${log_content}"
                echo "[$(ora)] Comando /log"
                ;;
            /satelliti*)
                telegram "<b>🛰 Stato GNSS</b>%0A$(ora)%0A%0A$(get_satelliti)"
                echo "[$(ora)] Comando /satelliti"
                ;;
            /ntrip*)
                telegram "<b>🔍 Test NTRIP in corso...</b>%0A$(ora)%0AAttendi ~10 secondi"
                snip_result=$(ntrip_test "SNIP Dell (${SNIP_MOUNT})" "$SNIP_HOST" "$SNIP_PORT" "$SNIP_MOUNT" "$SNIP_USER" "$SNIP_PASS")
                centipede_result=$(ntrip_test "Centipede (${CENTIPEDE_MOUNT})" "$CENTIPEDE_HOST" "$CENTIPEDE_PORT" "$CENTIPEDE_MOUNT" "" "")
                telegram "${snip_result}%0A%0A${centipede_result}"
                echo "[$(ora)] Comando /ntrip"
                ;;
            /help*)
                telegram "<b>Comandi disponibili:</b>%0A%0A/stato - Stato completo + hardware%0A/uptime - Uptime rapido%0A/log - Ultime righe log%0A/satelliti - Satelliti GNSS e fix%0A/ntrip - Test end-to-end caster%0A/help - Questo messaggio%0A%0A<b>Allarmi automatici:</b>%0A❌ Disconnessioni%0A🌡 Temperatura sopra 75°C%0A🧠 RAM sopra 80%25%0A💾 Swap sopra 90%25%0A💿 Disco sopra 80%25%0A⚠️ Riavvio Raspberry rilevato"
                echo "[$(ora)] Comando /help"
                ;;
        esac
    fi

    now=$(date +%s)
    if [ $((now - last_check)) -ge $INTERVAL ]; then
        monitoraggio
        last_check=$now
        echo "[$(ora)] Monitoraggio eseguito"
    fi

done
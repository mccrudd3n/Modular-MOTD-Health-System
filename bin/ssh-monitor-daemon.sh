#!/bin/bash
# /usr/local/bin/ssh-monitor-daemon.sh
set -u

# --- CONFIGURATION ---
LOG_DIR="/var/log/ssh-defense"
STATE_DIR="/run/ssh-defense"
STATS_FILE="$STATE_DIR/stats.json"
EVENTS_LOG="$LOG_DIR/events.jsonl"
BLOCK_LOG="$LOG_DIR/blocks.jsonl"

# Thresholds
MAX_FAILURES=3
WINDOW_SECONDS=3600
WHITELIST_IPS=("127.0.0.1" "::1" "192.168.1.0/24")

# Setup
mkdir -p "$LOG_DIR" "$STATE_DIR"
touch "$EVENTS_LOG" "$BLOCK_LOG"

declare -A FAIL_COUNTS
declare -A FIRST_SEEN
TOTAL_PROCESSED=0
TOTAL_BLOCKED=0
START_TIME=$(date +%s)

# --- FUNCTIONS ---
update_stats() {
    local uptime=$(( $(date +%s) - START_TIME ))
    # Calculate active threats count
    local threat_count=${#FAIL_COUNTS[@]}
    
    cat <<EOF > "$STATS_FILE.tmp"
{
  "status": "active",
  "uptime_sec": $uptime,
  "processed": $TOTAL_PROCESSED,
  "blocked_total": $TOTAL_BLOCKED,
  "active_threats": $threat_count
}
EOF
    mv "$STATS_FILE.tmp" "$STATS_FILE"
}

log_event() {
    local type=$1; local ip=$2; local user=$3; local details=$4
    echo "{\"timestamp\": \"$(date -u +%FT%TZ)\", \"type\": \"$type\", \"ip\": \"$ip\", \"user\": \"$user\", \"details\": \"$details\"}" >> "$EVENTS_LOG"
}

block_ip() {
    local ip=$1; local reason=$2
    for safe in "${WHITELIST_IPS[@]}"; do [[ "$ip" == "$safe" ]] && return; done
    if iptables -C INPUT -s "$ip" -j DROP 2>/dev/null; then return; fi
    
    iptables -I INPUT -s "$ip" -j DROP -m comment --comment "SSH-Defense: $reason"
    echo "{\"timestamp\": \"$(date -u +%FT%TZ)\", \"action\": \"BLOCK\", \"ip\": \"$ip\", \"reason\": \"$reason\"}" >> "$BLOCK_LOG"
    ((TOTAL_BLOCKED++))
    unset FAIL_COUNTS[$ip]
    unset FIRST_SEEN[$ip]
}

# --- STARTUP ---
echo "Starting SSH Defense Monitor..."

# *** THE FIX: Write initial stats immediately ***
update_stats

# --- MAIN LOOP ---
journalctl -u ssh -f -n 0 -o cat | while read -r line; do
    ((TOTAL_PROCESSED++))
    IP=""
    REASON=""

    # 1. Invalid User
    if [[ "$line" =~ Invalid\ user\ (.*)\ from\ ([^ ]+) ]]; then
        REASON="Invalid User"; IP="${BASH_REMATCH[2]}"; USER="${BASH_REMATCH[1]}"

    # 2. Key Auth Failure (The Proxmox Root Scenario)
    elif [[ "$line" =~ Connection\ closed\ by\ authenticating\ user\ ([^ ]+)\ ([^ ]+) ]]; then
        REASON="Key Auth Failure"; IP="${BASH_REMATCH[2]}"; USER="${BASH_REMATCH[1]}"
    
    # 3. Classic Password Failure
    elif [[ "$line" =~ Failed\ password\ for\ (invalid\ user\ )?([^ ]+)\ from\ ([^ ]+) ]]; then
        REASON="Failed Password"; IP="${BASH_REMATCH[3]}"; USER="${BASH_REMATCH[2]}"
    fi

    if [[ -n "$IP" ]]; then
        log_event "THREAT" "$IP" "$USER" "$REASON"
        
        curr_time=$(date +%s)
        FAIL_COUNTS[$IP]=$(( ${FAIL_COUNTS[$IP]:-0} + 1 ))
        
        if [[ ${FAIL_COUNTS[$IP]} -ge $MAX_FAILURES ]]; then
            block_ip "$IP" "$REASON"
        fi
        update_stats
    fi
done
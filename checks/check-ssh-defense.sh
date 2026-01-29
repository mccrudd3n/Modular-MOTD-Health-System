#!/bin/bash
set -u

# Configuration
STATE_DIR="/run/motd-health"
DAEMON_STATE="/run/ssh-defense/stats.json"
STATE_FILE="$STATE_DIR/ssh-defense.state"
TEMP_FILE="$STATE_FILE.tmp"

mkdir -p "$STATE_DIR"

# Defaults
STATUS="PASS"
SUMMARY="SSH Defense active"
DETAIL=""
REMEDIATE=""

# 1. Check if Daemon is Running
if ! systemctl is-active --quiet ssh-monitor.service; then
    STATUS="FAIL"
    SUMMARY="SSH Defense Daemon is DEAD"
    REMEDIATE="systemctl start ssh-monitor.service"
elif [[ ! -f "$DAEMON_STATE" ]]; then
    STATUS="WARN"
    SUMMARY="Initializing defense metrics..."
else
    # 2. Parse Daemon Stats
    # Using grep/sed to avoid jq dependency if not present
    PROCESSED=$(grep -o '"processed": [0-9]*' "$DAEMON_STATE" | awk '{print $2}')
    BLOCKED=$(grep -o '"blocked_total": [0-9]*' "$DAEMON_STATE" | awk '{print $2}')
    ACTIVE=$(grep -o '"active_threats": [0-9]*' "$DAEMON_STATE" | awk '{print $2}')
    
    SUMMARY="Defense Active: ${BLOCKED} blocked IPs"
    
    # 3. Format Details for Renderer (using || separator for lines)
    DETAIL="Processed Events: $PROCESSED || Active Threats: $ACTIVE || Log: /var/log/ssh-defense/blocks.jsonl"
    
    # 4. Warn if Threat Level is High
    if [[ "$ACTIVE" -gt 10 ]]; then
        STATUS="WARN"
        SUMMARY="High threat activity detected"
    fi
fi

# 5. Atomic Write
{
    echo "STATUS=\"$STATUS\""
    echo "SUMMARY=\"$SUMMARY\""
    echo "DETAIL=\"$DETAIL\""
    [[ -n "$REMEDIATE" ]] && echo "REMEDIATE=\"$REMEDIATE\""
} > "$TEMP_FILE"

mv "$TEMP_FILE" "$STATE_FILE"
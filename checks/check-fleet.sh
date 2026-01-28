#!/bin/bash
set -u

# Configuration
STATE_DIR="/run/motd-health"
STATE_FILE="$STATE_DIR/fleet.state"
TEMP_FILE="$STATE_FILE.tmp"

mkdir -p "$STATE_DIR"

# 1. Fetch Fleet Data via pvesh
# We filter for guests with IDs >= 100 (user-created)
RESOURCES=$(pvesh get /cluster/resources --type vm --output-format json 2>/dev/null)

# Decision Logic
STATUS="PASS"
SUMMARY="All virtual guests are running"
DETAIL=""
REMEDIATE=""

if [[ $? -ne 0 || -z "$RESOURCES" ]]; then
    STATUS="WARN"
    SUMMARY="Fleet status unavailable"
    DETAIL="Proxmox API (pvesh) failed to respond"
    REMEDIATE="/usr/bin/systemctl restart pvedaemon"
else
    # Parse stopped guests using Python (standard on Proxmox/Debian)
    STOPPED=$(echo "$RESOURCES" | python3 -c "import sys, json; print(','.join([str(v['vmid']) for v in json.load(sys.stdin) if v.get('status') != 'running' and v.get('vmid', 0) >= 100]))" 2>/dev/null)
    
    if [[ -n "$STOPPED" ]]; then
        STATUS="WARN"
        SUMMARY="Detected stopped guests"
        DETAIL="Offline IDs: $STOPPED"
        REMEDIATE="/usr/bin/pve-manager list"
    fi
fi

# Atomic Write
{
    echo "STATUS=$STATUS"
    echo "SUMMARY=$SUMMARY"
    [[ -n "$DETAIL" ]] && echo "DETAIL=$DETAIL"
    [[ -n "$REMEDIATE" ]] && echo "REMEDIATE=$REMEDIATE"
} > "$TEMP_FILE"

mv "$TEMP_FILE" "$STATE_FILE"
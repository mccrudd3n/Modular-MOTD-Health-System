#!/bin/bash
set -u

# Configuration
STATE_DIR="/run/motd-health"
STATE_FILE="$STATE_DIR/services.state"
TEMP_FILE="$STATE_FILE.tmp"

mkdir -p "$STATE_DIR"

# 1. Check for failed systemd units
FAILED_UNITS=$(systemctl list-units --state=failed --no-legend --plain 2>/dev/null | awk '{print $1}')
UNIT_COUNT=$(echo "$FAILED_UNITS" | grep -v '^$' | wc -l)

# 2. Check for critical Proxmox services
# pve-cluster is vital for quorum/config access
PVE_STATUS=$(systemctl is-active pve-cluster 2>/dev/null)

# Decision Logic
STATUS="PASS"
SUMMARY="All critical services are active"
DETAIL=""
REMEDIATE=""

if [[ "$PVE_STATUS" != "active" ]]; then
    STATUS="FAIL"
    SUMMARY="Critical Service Failure: pve-cluster"
    DETAIL="Proxmox cluster configuration filesystem is unavailable"
    REMEDIATE="/usr/bin/systemctl status pve-cluster"
elif [[ "$UNIT_COUNT" -gt 0 ]]; then
    STATUS="FAIL"
    SUMMARY="Detected $UNIT_COUNT failed systemd units"
    DETAIL=$(echo "$FAILED_UNITS" | xargs | cut -c1-60)
    REMEDIATE="/usr/bin/systemctl --failed"
fi

# Atomic Write
{
    echo "STATUS=$STATUS"
    echo "SUMMARY=$SUMMARY"
    [[ -n "$DETAIL" ]] && echo "DETAIL=$DETAIL"
    [[ -n "$REMEDIATE" ]] && echo "REMEDIATE=$REMEDIATE"
} > "$TEMP_FILE"

mv "$TEMP_FILE" "$STATE_FILE"
#!/bin/bash
set -u

# Configuration
STATE_DIR="/run/motd-health"
STATE_FILE="$STATE_DIR/maintenance.state"
TEMP_FILE="$STATE_FILE.tmp"

mkdir -p "$STATE_DIR"

# 1. Check for Pending Updates
# Using /var/lib/apt/lists/ directly to avoid slow 'apt update' calls
UP_COUNT=$(apt list --upgradable 2>/dev/null | grep -v "Listing..." | wc -l)

# 2. Check for Reboot Flag
REBOOT_REQ=0
if [[ -f /var/run/reboot-required ]]; then
    REBOOT_REQ=1
fi

# Decision Logic
STATUS="PASS"
SUMMARY="System software is up to date"
DETAIL=""
REMEDIATE=""

if [[ $REBOOT_REQ -eq 1 ]]; then
    STATUS="WARN"
    SUMMARY="Reboot required to apply updates"
    REMEDIATE="/usr/sbin/reboot"
elif [[ "$UP_COUNT" -gt 0 ]]; then
    STATUS="WARN"
    SUMMARY="$UP_COUNT software updates pending"
    REMEDIATE="/usr/bin/apt list --upgradable"
fi

# Atomic Write
{
    echo "STATUS=$STATUS"
    echo "SUMMARY=$SUMMARY"
    [[ -n "$DETAIL" ]] && echo "DETAIL=$DETAIL"
    [[ -n "$REMEDIATE" ]] && echo "REMEDIATE=$REMEDIATE"
} > "$TEMP_FILE"

mv "$TEMP_FILE" "$STATE_FILE"
#!/bin/bash
set -u

# Configuration
STATE_DIR="/run/motd-health"
STATE_FILE="$STATE_DIR/integrity.state"
TEMP_FILE="$STATE_FILE.tmp"

# Ensure runtime directory exists
mkdir -p "$STATE_DIR"

# Initialize variables
STATUS="PASS"
SUMMARY="System boot and shutdown were graceful"
DETAIL=""
REMEDIATE=""

# 1. Check for Dirty Shutdown
# We look for the "System is powering down" string in the PREVIOUS boot logs
WAS_CLEAN=$(journalctl -b -1 -u systemd-logind 2>/dev/null | grep -q "System is powering down" && echo "YES" || echo "NO")

if [[ "$WAS_CLEAN" == "NO" ]]; then
    STATUS="FAIL"
    SUMMARY="Dirty shutdown detected"
    # Capture the last 3 lines of the previous boot for context
    DETAIL=$(journalctl -b -1 -n 3 --no-pager 2>/dev/null | tail -n 1 | sed 's/=/ /g')
    REMEDIATE="/usr/bin/journalctl -b -1 -e"
fi

# 2. Check for Kernel Taint (Optional but useful for integrity)
if [ -f /proc/sys/kernel/tainted ] && [ "$(cat /proc/sys/kernel/tainted)" -ne 0 ]; then
    if [[ "$STATUS" != "FAIL" ]]; then
        STATUS="WARN"
        SUMMARY="Kernel is tainted"
        DETAIL="Taint bitmask: $(cat /proc/sys/kernel/tainted)"
        REMEDIATE="/usr/bin/dmesg | grep -i tainted"
    fi
fi

# Atomic Write State File
{
    echo "STATUS=$STATUS"
    echo "SUMMARY=$SUMMARY"
    [[ -n "$DETAIL" ]] && echo "DETAIL=$DETAIL"
    [[ -n "$REMEDIATE" ]] && echo "REMEDIATE=$REMEDIATE"
} > "$TEMP_FILE"

mv "$TEMP_FILE" "$STATE_FILE"
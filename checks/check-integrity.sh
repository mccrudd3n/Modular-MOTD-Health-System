#!/bin/bash
set -u

STATE_DIR="/run/motd-health"
STATE_FILE="$STATE_DIR/integrity.state"
TEMP_FILE="$STATE_FILE.tmp"
mkdir -p "$STATE_DIR"

# 1. Get Uptime Data
UPTIME_SEC=$(awk '{print int($1)}' /proc/uptime)
# Convert to "X days, Y hours"
UPTIME_PRETTY=$(awk '{d=int($1/86400); h=int(($1%86400)/3600); print d " days, " h " hours"}' /proc/uptime)

# Threshold: 15 minutes (900 seconds)
STABLE_TIME=900

# 2. Check Previous Boot for Dirty Shutdown
WAS_CLEAN=$(journalctl -b -1 -n 200 2>/dev/null | grep -qE "System is powering down|Powering off|Rebooting" && echo "YES" || echo "NO")

STATUS="PASS"
SUMMARY="System integrity verified"
DETAIL=""
REMEDIATE=""

# 3. Shutdown Logic
if [[ "$WAS_CLEAN" == "NO" ]]; then
    if [[ "$UPTIME_SEC" -lt "$STABLE_TIME" ]]; then
        STATUS="FAIL"
        SUMMARY="Dirty shutdown detected"
        REMEDIATE="/usr/bin/journalctl -b -1 -e"
    else
        STATUS="PASS"
        SUMMARY="Recovered from dirty shutdown"
        DETAIL="System stable for $UPTIME_PRETTY"
    fi
fi

# 4. Kernel Taint Check (With ZFS Exclusion)
if [ -f /proc/sys/kernel/tainted ] && [ "$(cat /proc/sys/kernel/tainted)" -ne 0 ]; then
     # Check if ZFS is loaded (ZFS always taints the kernel)
     IS_ZFS=$(lsmod | grep "^zfs" | wc -l)
     
     # Only warn if it's NOT just ZFS causing the taint
     if [[ "$STATUS" == "PASS" && "$IS_ZFS" -eq 0 ]]; then
         STATUS="WARN"
         SUMMARY="Kernel is tainted"
         REMEDIATE="/usr/bin/dmesg | grep -i tainted"
     fi
fi

# 5. ATOMIC WRITE
{
    echo "STATUS=\"$STATUS\""
    echo "SUMMARY=\"$SUMMARY\""
    echo "DETAIL=\"$DETAIL\""
    [[ -n "$REMEDIATE" ]] && echo "REMEDIATE=\"$REMEDIATE\""
} > "$TEMP_FILE"

mv "$TEMP_FILE" "$STATE_FILE"
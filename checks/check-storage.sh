#!/bin/bash
set -u

# Configuration
STATE_DIR="/run/motd-health"
STATE_FILE="$STATE_DIR/storage.state"
TEMP_FILE="$STATE_FILE.tmp"
CAPACITY_THRESHOLD=85

mkdir -p "$STATE_DIR"

# 1. ZFS Pool Health
ZPOOL_HEALTH=$(zpool status -x)
Z_ERR=0
if [[ "$ZPOOL_HEALTH" != "all pools are healthy" ]]; then
    Z_ERR=1
fi

# 2. Capacity Check
MAX_CAP=$(df -h --output=pcent / | tail -1 | tr -dc '0-9')
# Check ZFS pools specifically
Z_CAP=$(zpool list -H -o cap | tr -dc '0-9\n' | sort -rn | head -n 1)
[[ -n "$Z_CAP" && "$Z_CAP" -gt "$MAX_CAP" ]] && MAX_CAP=$Z_CAP

# 3. Read-Only Filesystem Check
RO_CHECK=$(awk '$4~/(^|,)ro($|,)/' /proc/mounts | grep -v "loop" | grep -v "pve")

# Decision Logic
STATUS="PASS"
SUMMARY="Storage subsystems are healthy and within capacity"
DETAIL=""
REMEDIATE=""

if [[ -n "$RO_CHECK" ]]; then
    STATUS="FAIL"
    SUMMARY="Read-only filesystem detected"
    DETAIL=$(echo "$RO_CHECK" | awk '{print $2}' | xargs)
    REMEDIATE="/usr/bin/dmesg | grep -i 'I/O error'"
elif [[ $Z_ERR -eq 1 ]]; then
    STATUS="FAIL"
    SUMMARY="ZFS pool(s) non-optimal"
    DETAIL=$(zpool status -s | grep -v "healthy" | xargs)
    REMEDIATE="/usr/sbin/zpool status -v"
elif [[ "$MAX_CAP" -gt "$CAPACITY_THRESHOLD" ]]; then
    STATUS="WARN"
    SUMMARY="Storage capacity high: ${MAX_CAP}%"
    DETAIL="Check zfs list and purge snapshots"
    REMEDIATE="/usr/bin/zfs list -o name,used,avail,refer,mountpoint"
fi

# Atomic Write
{
    echo "STATUS=$STATUS"
    echo "SUMMARY=$SUMMARY"
    [[ -n "$DETAIL" ]] && echo "DETAIL=$DETAIL"
    [[ -n "$REMEDIATE" ]] && echo "REMEDIATE=$REMEDIATE"
} > "$TEMP_FILE"

mv "$TEMP_FILE" "$STATE_FILE"
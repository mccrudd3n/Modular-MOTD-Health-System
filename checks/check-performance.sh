#!/bin/bash
set -u

# Configuration
STATE_DIR="/run/motd-health"
STATE_FILE="$STATE_DIR/performance.state"
TEMP_FILE="$STATE_FILE.tmp"
IO_WAIT_THRESHOLD=15
MEM_THRESHOLD_PERCENT=10

mkdir -p "$STATE_DIR"

# 1. CPU Load Check
LOAD=$(cat /proc/loadavg | awk '{print $1}')
CORES=$(nproc)
LOAD_INT=$(printf "%.0f" "$LOAD")

# 2. Memory Check
MEM_DATA=$(free -m | grep Mem)
TOTAL_MEM=$(echo "$MEM_DATA" | awk '{print $2}')
AVAIL_MEM=$(echo "$MEM_DATA" | awk '{print $7}')
MEM_PERCENT=$(( AVAIL_MEM * 100 / TOTAL_MEM ))

# 3. I/O Wait Check (Non-blocking /proc/stat calculation)
S1=$(grep 'cpu ' /proc/stat)
sleep 0.2
S2=$(grep 'cpu ' /proc/stat)
IOW=$(echo "$S1 $S2" | awk '{u1=$5; i1=$6; u2=$16; i2=$17; printf "%.0f", (i2-i1)/((u2+i2)-(u1+i1))*100}')

# Decision Logic
STATUS="PASS"
SUMMARY="Resources operating within nominal parameters"
DETAIL=""
REMEDIATE=""

if [ "$IOW" -gt "$IO_WAIT_THRESHOLD" ]; then
    STATUS="FAIL"
    SUMMARY="High I/O Wait detected: ${IOW}%"
    DETAIL="Disk subsystem is saturating CPU cycles"
    REMEDIATE="/usr/bin/iotop -Pa"
elif [ "$LOAD_INT" -ge "$CORES" ]; then
    STATUS="WARN"
    SUMMARY="CPU Load high: $LOAD"
    DETAIL="Load average exceeds core count ($CORES)"
    REMEDIATE="/usr/bin/top -bc -n 1 -o +%CPU | head -n 20"
elif [ "$MEM_PERCENT" -lt "$MEM_THRESHOLD_PERCENT" ]; then
    STATUS="WARN"
    SUMMARY="Memory pressure high"
    DETAIL="Available RAM: ${AVAIL_MEM}MB (${MEM_PERCENT}%)"
    REMEDIATE="/usr/bin/top -bc -n 1 -o +%MEM | head -n 20"
fi

# Atomic Write
{
    echo "STATUS=$STATUS"
    echo "SUMMARY=$SUMMARY"
    [[ -n "$DETAIL" ]] && echo "DETAIL=$DETAIL"
    [[ -n "$REMEDIATE" ]] && echo "REMEDIATE=$REMEDIATE"
} > "$TEMP_FILE"

mv "$TEMP_FILE" "$STATE_FILE"
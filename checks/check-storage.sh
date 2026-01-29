#!/bin/bash
set -u

STATE_DIR="/run/motd-health"
STATE_FILE="$STATE_DIR/storage.state"
TEMP_FILE="$STATE_FILE.tmp"
CAPACITY_THRESHOLD=85

mkdir -p "$STATE_DIR"

render_bar() {
    local pct=$1
    local width=10
    local filled=$(( pct / width ))
    local empty=$(( width - filled ))
    local bar="["
    for i in $(seq 1 $filled); do bar="${bar}="; done
    for i in $(seq 1 $empty); do bar="${bar}-"; done
    bar="${bar}]"
    echo "$bar"
}

# --- 1. GATHER DATA ---
ZPOOL_STATUS_X=$(zpool status -x)
SCRUBBING=$(zpool status | grep -c "scrub in progress")
RO_CHECK=$(awk '$4~/(^|,)ro($|,)/' /proc/mounts | grep -vE "loop|pve|/run/credentials|/sys/kernel")

POOL_DETAILS=""
MAX_CAP=0

# Loop through pools and build a SINGLE LINE string separated by " || "
while read -r name size alloc cap; do
    pct=$(echo "$cap" | tr -d '%')
    [[ $pct -gt $MAX_CAP ]] && MAX_CAP=$pct
    BAR=$(render_bar "$pct")
    # THE FIX: Using '||' instead of '\n'
    POOL_DETAILS="${POOL_DETAILS}${name}: ${BAR} ${pct}% || "
done < <(zpool list -H -o name,size,alloc,cap)

# Strip the trailing " || "
POOL_DETAILS="${POOL_DETAILS% || }"

# --- 2. DECISION LOGIC ---
STATUS="PASS"
SUMMARY="Storage is healthy"
DETAIL="$POOL_DETAILS"

if [[ -n "$RO_CHECK" ]]; then
    STATUS="FAIL"; SUMMARY="Read-only filesystem detected"
    DETAIL=$(echo "$RO_CHECK" | awk '{print $2}' | xargs)
elif [[ "$ZPOOL_STATUS_X" != "all pools are healthy" ]]; then
    STATUS="FAIL"; SUMMARY="ZFS pool(s) non-optimal"
elif [[ $SCRUBBING -gt 0 ]]; then
    STATUS="WARN"; SUMMARY="ZFS Maintenance in progress"
elif [[ "$MAX_CAP" -gt "$CAPACITY_THRESHOLD" ]]; then
    STATUS="WARN"; SUMMARY="Storage capacity high: ${MAX_CAP}%"
fi

# --- 3. ATOMIC WRITE (WITH QUOTES) ---
{
    echo "STATUS=\"$STATUS\""
    echo "SUMMARY=\"$SUMMARY\""
    echo "DETAIL=\"$DETAIL\""
} > "$TEMP_FILE"
mv "$TEMP_FILE" "$STATE_FILE"
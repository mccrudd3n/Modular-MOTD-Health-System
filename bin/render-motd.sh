#!/bin/bash
# /usr/local/bin/render-motd.sh

# Colors
R="\033[1;31m" G="\033[1;32m" Y="\033[1;33m" C="\033[1;36m" W="\033[1;37m" NC="\033[0m"
STATE_DIR="/run/motd-health"

# Pillars to render (Order determines display order)
# Added 'ssh-defense' immediately after Integrity
PILLARS=("integrity" "ssh-defense" "performance" "storage" "services" "network" "maintenance" "fleet")

# Helper to read KEY="VALUE" safely
get_val() {
    local key=$1
    local file=$2
    # Grep the key, grab everything after =, remove surrounding quotes
    grep "^${key}=" "$file" | cut -d'=' -f2- | sed 's/^"//;s/"$//'
}

print_status() {
    local pillar=$1
    local file="$STATE_DIR/$pillar.state"
    
    # Fail silently/gracefully if a specific state file hasn't been generated yet
    [[ ! -f "$file" ]] && return

    # Extract values
    local STATUS=$(get_val "STATUS" "$file")
    local SUMMARY=$(get_val "SUMMARY" "$file")
    local DETAIL=$(get_val "DETAIL" "$file")
    local REMEDIATE=$(get_val "REMEDIATE" "$file")

    # Determine Color
    case "$STATUS" in
        PASS) local S_COL=$G ;;
        WARN) local S_COL=$Y ;;
        FAIL) local S_COL=$R ;;
        *)    local S_COL=$W ;;
    esac

    # Pretty Labeling: Convert "ssh-defense" to "SECURITY" for cleaner UI
    local LABEL="${pillar^^}"
    if [[ "$pillar" == "ssh-defense" ]]; then LABEL="SECURITY"; fi

    # Print Header
    printf "%-12s -> [${S_COL} %-4s ${NC}] %s\n" "$LABEL" "$STATUS" "$SUMMARY"

    # Print Details (Handle '||' separator for multi-line details)
    if [[ -n "$DETAIL" ]]; then
        echo "$DETAIL" | sed 's/ || /\n/g' | while read -r line; do
            [[ -n "$line" ]] && printf "               -> %s\n" "$line"
        done
    fi

    # Print Remediation (Only if not PASS)
    if [[ "$STATUS" != "PASS" && -n "$REMEDIATE" ]]; then
        printf "               -> ${W}Run:${NC} ${C}%s${NC}\n" "$REMEDIATE"
    fi
}

echo -e "${W}SYSTEM HEALTH DASHBOARD${NC}"
for p in "${PILLARS[@]}"; do
    print_status "$p"
done
echo -e "${W}================================================${NC}"
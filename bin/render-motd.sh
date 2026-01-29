#!/bin/bash
# Colors
R="\033[1;31m" G="\033[1;32m" Y="\033[1;33m" C="\033[1;36m" W="\033[1;37m" NC="\033[0m"
STATE_DIR="/run/motd-health"
PILLARS=("integrity" "performance" "storage" "services" "network" "maintenance" "fleet")

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
    [[ ! -f "$file" ]] && return

    # Extract values
    local STATUS=$(get_val "STATUS" "$file")
    local SUMMARY=$(get_val "SUMMARY" "$file")
    local DETAIL=$(get_val "DETAIL" "$file")
    local REMEDIATE=$(get_val "REMEDIATE" "$file")

    case "$STATUS" in
        PASS) local S_COL=$G ;;
        WARN) local S_COL=$Y ;;
        FAIL) local S_COL=$R ;;
        *)    local S_COL=$W ;;
    esac

    # Print Header
    printf "%-12s -> [${S_COL} %-4s ${NC}] %s\n" "${pillar^^}" "$STATUS" "$SUMMARY"

    # Print Details (Convert '||' back to newlines)
    if [[ -n "$DETAIL" ]]; then
        echo "$DETAIL" | sed 's/ || /\n/g' | while read -r line; do
            [[ -n "$line" ]] && printf "               -> %s\n" "$line"
        done
    fi

    # Print Remediation
    if [[ "$STATUS" != "PASS" && -n "$REMEDIATE" ]]; then
        printf "               -> ${W}Run:${NC} ${C}%s${NC}\n" "$REMEDIATE"
    fi
}

echo -e "${W}SYSTEM HEALTH DASHBOARD${NC}"
for p in "${PILLARS[@]}"; do
    print_status "$p"
done
echo -e "${W}================================================${NC}"
#!/bin/bash

# Colors
R="\033[1;31m" G="\033[1;32m" Y="\033[1;33m" C="\033[1;36m" W="\033[1;37m" NC="\033[0m"
STATE_DIR="/run/motd-health"

# Pillars to render (in order)
PILLARS=("integrity" "performance" "storage" "services" "network" "maintenance" "fleet")

print_status() {
    local pillar=$1
    local file="$STATE_DIR/$pillar.state"
    
    # Fail Closed: If state file is missing
    if [[ ! -f "$file" ]]; then
        printf "%-12s -> [${Y} WARN ${NC}] State file missing\n" "${pillar^^}"
        return
    fi

    # Read state file variables
    # We use a subshell to avoid polluting the main environment
    local STATUS SUMMARY REMEDIATE
    local -a DETAILS=()
    
    while IFS='=' read -r key value; do
        case "$key" in
            STATUS) STATUS=$value ;;
            SUMMARY) SUMMARY=$value ;;
            DETAIL) DETAILS+=("$value") ;;
            REMEDIATE) REMEDIATE=$value ;;
        esac
    done < "$file"

    # Colorize Status
    case "$STATUS" in
        PASS) local S_COL=$G ;;
        WARN) local S_COL=$Y ;;
        FAIL) local S_COL=$R ;;
        *)    local S_COL=$W ;;
    esac

    # Render Header
    printf "%-12s -> [${S_COL} %-4s ${NC}] %s\n" "${pillar^^}" "$STATUS" "$SUMMARY"

    # Render Details & Remediation (only if not PASS)
    if [[ "$STATUS" != "PASS" ]]; then
        for detail in "${DETAILS[@]}"; do
            printf "               -> %s\n" "$detail"
        done
        if [[ -n "$REMEDIATE" ]]; then
            printf "               -> ${W}Run:${NC} ${C}%s${NC}\n" "$REMEDIATE"
        fi
    fi
}

echo -e "${W}SYSTEM HEALTH DASHBOARD${NC}"
for p in "${PILLARS[@]}"; do
    print_status "$p"
done
echo -e "${W}================================================${NC}"
#!/bin/bash
set -u

# --- CONFIGURATION ---
BASE_DIR="/usr/local/lib/motd-health"
BIN_DIR="/usr/local/bin"
STATE_DIR="/run/motd-health"
SYSTEMD_DIR="/etc/systemd/system"
REPO_SOURCE="$(pwd)"
SNIPPET_FILE="$REPO_SOURCE/examples/bashrc-snippet.txt"
TARGET_BASHRC="/root/.bashrc" # Or ~/.bashrc

# Colors
G="\033[1;32m" R="\033[1;31m" Y="\033[1;33m" C="\033[1;36m" W="\033[1;37m" NC="\033[0m"

echo -e "${C}Starting Modular MOTD Health System Setup & Audit...${NC}"

# 1. Privileged Access & Dependency Check
if [[ $EUID -ne 0 ]]; then
   echo -e "${R}FAIL: Root privileges required.${NC}"
   echo -e "      Please run: ${W}sudo $0${NC}"
   exit 1
fi

# Dependency check
for tool in python3 systemctl awk journalctl; do
    if ! command -v "$tool" &> /dev/null; then
        echo -e "${Y}WARN: $tool missing. Attempting install...${NC}"
        apt-get update && apt-get install -y "$tool"
    fi
done

# 2. Deployment
echo -e "${C}Deploying files...${NC}"
mkdir -p "$BASE_DIR" "$BIN_DIR" "$STATE_DIR"

if [[ -d "$REPO_SOURCE/checks" && -f "$REPO_SOURCE/bin/render-motd.sh" ]]; then
    cp "$REPO_SOURCE"/checks/check-*.sh "$BASE_DIR/"
    chmod 755 "$BASE_DIR"/check-*.sh
    cp "$REPO_SOURCE/bin/render-motd.sh" "$BIN_DIR/"
    chmod 755 "$BIN_DIR/render-motd.sh"
    echo -e "${G}PASS: Files deployed.${NC}"
else
    echo -e "${R}FAIL: Source files missing. Run from repo root.${NC}"
    exit 1
fi

# 3. Systemd Activation
echo -e "${C}Activating background timers...${NC}"
if [[ -d "$REPO_SOURCE/systemd" ]]; then
    cp "$REPO_SOURCE"/systemd/motd-health.* "$SYSTEMD_DIR/"
    systemctl daemon-reload
    systemctl enable --now motd-health.timer &> /dev/null
    systemctl start motd-health.service &> /dev/null
    echo -e "${G}PASS: Systemd timer enabled.${NC}"
else
    echo -e "${R}FAIL: Systemd unit files missing.${NC}"
    exit 1
fi

# 4. .bashrc Integration (Idempotent)
echo -ne "${C}Integrating with $TARGET_BASHRC... ${NC}"
if [[ -f "$SNIPPET_FILE" ]]; then
    if grep -q "Modular MOTD Health Integration" "$TARGET_BASHRC"; then
        echo -e "${Y}[ SKIPPED ]${NC} (Already integrated)"
    else
        echo "" >> "$TARGET_BASHRC"
        cat "$SNIPPET_FILE" >> "$TARGET_BASHRC"
        echo -e "${G}[ OK ]${NC}"
    fi
else
    echo -e "${R}[ FAIL ]${NC} (Snippet source missing)"
fi

# 5. Functional Audit
echo -e "\n${C}Performing Functional Audit:${NC}"
AUDIT_PASS=1

# Test A: State Generation
echo -n "Test A: State Generation... "
if ls "$STATE_DIR"/*.state >/dev/null 2>&1; then
    echo -e "${G}[ OK ]${NC}"
else
    echo -e "${R}[ FAIL ]${NC}"; AUDIT_PASS=0
fi

# Test B: Renderer Execution
echo -n "Test B: Renderer Logic... "
if "$BIN_DIR/render-motd.sh" | grep -q "SYSTEM HEALTH DASHBOARD"; then
    echo -e "${G}[ OK ]${NC}"
else
    echo -e "${R}[ FAIL ]${NC}"; AUDIT_PASS=0
fi

# 6. Final Report
echo -e "\n================================================"
if [ $AUDIT_PASS -eq 1 ]; then
    echo -e "${G}SUCCESS: Modular MOTD Health is fully configured.${NC}"
    echo -e "Dashboard will appear on your next login."
    echo -e "To see it now, run: ${W}source $TARGET_BASHRC${NC}"
else
    echo -e "${R}CRITICAL: Setup failed audit tests.${NC}"
    echo -e "Review logs: ${W}journalctl -u motd-health.service${NC}"
fi
echo -e "================================================\n"
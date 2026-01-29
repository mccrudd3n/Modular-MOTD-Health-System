#!/bin/bash
set -u

# --- CONFIGURATION ---
# We now use the current directory (the git repo) as the permanent home
REPO_SOURCE="$(pwd)"
BASE_DIR="/usr/local/lib/motd-health"
BIN_DIR="/usr/local/bin"
STATE_DIR="/run/motd-health"
SYSTEMD_DIR="/etc/systemd/system"
SNIPPET_FILE="$REPO_SOURCE/examples/bashrc-snippet.txt"
TARGET_BASHRC="/root/.bashrc"

# Colors
G="\033[1;32m" R="\033[1;31m" Y="\033[1;33m" C="\033[1;36m" W="\033[1;37m" NC="\033[0m"

echo -e "${C}Starting Modular MOTD Health System Setup (Symlink Mode)...${NC}"

# 1. Privileged Access Check
if [[ $EUID -ne 0 ]]; then
   echo -e "${R}FAIL: Root privileges required.${NC}"
   exit 1
fi

# 2. Cleanup & Symlinking
echo -e "${C}Linking files from $REPO_SOURCE to system paths...${NC}"
mkdir -p "$STATE_DIR"

# Link the checks folder
# This ensures that any file you add/edit in the git 'checks' folder is live
rm -rf "$BASE_DIR" # Remove old copied directory
ln -sfn "$REPO_SOURCE/checks" "$BASE_DIR"

# Link the renderer
ln -sfn "$REPO_SOURCE/bin/render-motd.sh" "$BIN_DIR/render-motd.sh"
chmod +x "$REPO_SOURCE/bin/render-motd.sh"
chmod +x "$REPO_SOURCE"/checks/*.sh

echo -e "${G}PASS: System is now linked to $REPO_SOURCE${NC}"

# 3. Systemd Activation (Updating paths in service files)
echo -e "${C}Configuring Systemd...${NC}"
if [[ -d "$REPO_SOURCE/systemd" ]]; then
    # We copy these because systemd doesn't like symlinks for unit files
    cp "$REPO_SOURCE"/systemd/motd-health.* "$SYSTEMD_DIR/"
    systemctl daemon-reload
    systemctl enable --now motd-health.timer &> /dev/null
    systemctl start motd-health.service &> /dev/null
    echo -e "${G}PASS: Systemd service active.${NC}"
else
    echo -e "${R}FAIL: Systemd unit files missing.${NC}"
    exit 1
fi

# 4. .bashrc Integration
if [[ -f "$SNIPPET_FILE" ]]; then
    if ! grep -q "Modular MOTD Health Integration" "$TARGET_BASHRC"; then
        echo "" >> "$TARGET_BASHRC"
        cat "$SNIPPET_FILE" >> "$TARGET_BASHRC"
        echo -e "${G}PASS: .bashrc integrated.${NC}"
    fi
fi

# 5. Verify
echo -e "\n${C}Verification:${NC}"
"$BIN_DIR/render-motd.sh" | grep -q "SYSTEM HEALTH DASHBOARD" && echo -e "${G}Dashboard Render: OK${NC}" || echo -e "${R}Dashboard Render: FAIL${NC}"

echo -e "\n${W}NOTE: You can now edit files in $REPO_SOURCE and they will be live!${NC}"
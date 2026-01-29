#!/bin/bash
set -u

# --- CONFIGURATION ---
REPO_SOURCE="$(pwd)"
INSTALL_DEST="/opt/motd-health"
BIN_DIR="/usr/local/bin"
STATE_DIR="/run/motd-health"
SSH_LOG_DIR="/var/log/ssh-defense"
SYSTEMD_DIR="/etc/systemd/system"
SNIPPET_FILE="$REPO_SOURCE/examples/bashrc-snippet.txt"
TARGET_BASHRC="/root/.bashrc"

# Colors
G="\033[1;32m" R="\033[1;31m" Y="\033[1;33m" C="\033[1;36m" W="\033[1;37m" NC="\033[0m"

clear
echo -e "${C}Modular MOTD & SSH Defense Setup${NC}"
echo -e "========================================"

# 1. Privileged Access Check
if [[ $EUID -ne 0 ]]; then
   echo -e "${R}FAIL: Root privileges required.${NC}"
   exit 1
fi

# 2. DECISION MENU
echo -e "Your scripts are currently in: ${Y}$REPO_SOURCE${NC}"
if [[ "$REPO_SOURCE" == /root* ]]; then
    echo -e "${R}WARNING: Systemd services cannot access /root by default.${NC}"
fi
echo -e "\nHow would you like to deploy?"
echo -e "  1) ${W}Link Mode (Dev)${NC}    - Keep files in $REPO_SOURCE. Useful for editing."
echo -e "                          - ${Y}Will modify systemd to allow access to /root.${NC}"
echo -e "  2) ${W}Install Mode (Prod)${NC} - Copy files to /opt/motd-health."
echo -e "                          - ${G}Best security (ProtectHome=yes).${NC}"
echo
read -p "Select option [1/2]: " -r MODE

# 3. STOP SERVICES
echo -e "\n${Y}Stopping existing services...${NC}"
systemctl stop motd-health.timer motd-health.service ssh-monitor.service 2>/dev/null
systemctl reset-failed motd-health.service ssh-monitor.service 2>/dev/null || true

# 4. PREPARE DIRECTORIES
mkdir -p "$STATE_DIR" "$SSH_LOG_DIR"

# 5. EXECUTE DEPLOYMENT
if [[ "$MODE" == "1" ]]; then
    # --- MODE 1: SYMLINK / DEV ---
    echo -e "${C}Configuring Link Mode...${NC}"
    TARGET_DIR="$REPO_SOURCE"
    
    # Symlink Check Scripts (Base Dir -> Repo Checks)
    rm -rf "/usr/local/lib/motd-health" 2>/dev/null
    ln -sfn "$REPO_SOURCE/checks" "/usr/local/lib/motd-health"
    
    # Symlink Binaries
    ln -sfn "$REPO_SOURCE/bin/render-motd.sh" "$BIN_DIR/render-motd.sh"
    if [[ -f "$REPO_SOURCE/bin/ssh-monitor-daemon.sh" ]]; then
        ln -sfn "$REPO_SOURCE/bin/ssh-monitor-daemon.sh" "$BIN_DIR/ssh-monitor-daemon.sh"
    fi

    # Fix Permissions
    chmod +x "$REPO_SOURCE/bin/"*.sh "$REPO_SOURCE/checks/"*.sh

elif [[ "$MODE" == "2" ]]; then
    # --- MODE 2: INSTALL / PROD ---
    echo -e "${C}Configuring Install Mode...${NC}"
    TARGET_DIR="$INSTALL_DEST"
    
    # Create /opt directory and COPY files
    mkdir -p "$INSTALL_DEST"
    cp -r "$REPO_SOURCE/"* "$INSTALL_DEST/"
    
    # Link Check Scripts (Base Dir -> Opt Checks)
    rm -rf "/usr/local/lib/motd-health" 2>/dev/null
    ln -sfn "$INSTALL_DEST/checks" "/usr/local/lib/motd-health"
    
    # Link Binaries (Point to /opt copies)
    ln -sfn "$INSTALL_DEST/bin/render-motd.sh" "$BIN_DIR/render-motd.sh"
    if [[ -f "$INSTALL_DEST/bin/ssh-monitor-daemon.sh" ]]; then
        ln -sfn "$INSTALL_DEST/bin/ssh-monitor-daemon.sh" "$BIN_DIR/ssh-monitor-daemon.sh"
    fi

    # Fix Permissions on Copies
    chmod +x "$INSTALL_DEST/bin/"*.sh "$INSTALL_DEST/checks/"*.sh

else
    echo -e "${R}Invalid option.${NC}"
    exit 1
fi

# 6. SYSTEMD CONFIGURATION
echo -e "${C}Configuring Systemd...${NC}"
if [[ -d "$TARGET_DIR/systemd" ]]; then
    cp "$TARGET_DIR"/systemd/motd-health.* "$SYSTEMD_DIR/" 2>/dev/null
    cp "$TARGET_DIR"/systemd/ssh-monitor.service "$SYSTEMD_DIR/" 2>/dev/null
    
    # --- CRITICAL FIX FOR MODE 1 ---
    if [[ "$MODE" == "1" && "$TARGET_DIR" == /root* ]]; then
        echo -e "${Y}Applying ProtectHome fix for Root directory...${NC}"
        # Modify the service file in /etc/ (not the source)
        sed -i 's/ProtectHome=yes/ProtectHome=read-only/' "$SYSTEMD_DIR/ssh-monitor.service"
        sed -i 's/ProtectHome=yes/ProtectHome=read-only/' "$SYSTEMD_DIR/motd-health.service" 2>/dev/null
    fi

    systemctl daemon-reload
    
    # Enable & Start
    systemctl enable --now motd-health.timer &> /dev/null
    systemctl start motd-health.service &> /dev/null
    
    if [[ -f "$SYSTEMD_DIR/ssh-monitor.service" ]]; then
        systemctl enable --now ssh-monitor.service &> /dev/null
        echo -e "${G}PASS: Services started.${NC}"
    fi
else
    echo -e "${R}FAIL: Systemd files missing.${NC}"
fi

# 7. BASHRC INTEGRATION
if [[ -f "$SNIPPET_FILE" ]]; then
    if ! grep -q "Modular MOTD Health Integration" "$TARGET_BASHRC"; then
        echo "" >> "$TARGET_BASHRC"
        cat "$SNIPPET_FILE" >> "$TARGET_BASHRC"
        echo -e "${G}PASS: .bashrc integrated.${NC}"
    else
        echo -e "${Y}SKIP: .bashrc already integrated.${NC}"
    fi
fi

# 8. VERIFICATION
echo -e "\n${C}Final Verification:${NC}"
"$BIN_DIR/render-motd.sh" | grep -q "SYSTEM HEALTH DASHBOARD" && echo -e "${G}Dashboard: OK${NC}" || echo -e "${R}Dashboard: FAIL${NC}"
systemctl is-active --quiet ssh-monitor.service && echo -e "${G}SSH Defense: ACTIVE${NC}" || echo -e "${R}SSH Defense: INACTIVE (Check: systemctl status ssh-monitor.service)${NC}"

echo -e "\n${W}Setup Complete.${NC}"
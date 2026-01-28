#!/bin/bash
set -u

# Configuration
STATE_DIR="/run/motd-health"
STATE_FILE="$STATE_DIR/network.state"
TEMP_FILE="$STATE_FILE.tmp"
PRIMARY_IFACE="enp4s0"

mkdir -p "$STATE_DIR"

# 1. Check Interface Existence and Link
IF_PATH="/sys/class/net/$PRIMARY_IFACE"
STATUS="PASS"
SUMMARY="Network interfaces are stable"
DETAIL=""
REMEDIATE=""

if [[ ! -d "$IF_PATH" ]]; then
    STATUS="FAIL"
    SUMMARY="Interface $PRIMARY_IFACE missing"
    REMEDIATE="/usr/sbin/ip link show"
else
    OPERSTATE=$(cat "$IF_PATH/operstate")
    RX_ERRORS=$(cat "$IF_PATH/statistics/rx_errors")
    TX_ERRORS=$(cat "$IF_PATH/statistics/tx_errors")

    if [[ "$OPERSTATE" != "up" ]]; then
        STATUS="FAIL"
        SUMMARY="Interface $PRIMARY_IFACE is $OPERSTATE"
        REMEDIATE="/usr/sbin/ip link set $PRIMARY_IFACE up"
    elif [[ "$RX_ERRORS" -gt 0 || "$TX_ERRORS" -gt 0 ]]; then
        STATUS="WARN"
        SUMMARY="Hardware packet errors detected"
        DETAIL="RX: $RX_ERRORS | TX: $TX_ERRORS"
        REMEDIATE="/usr/sbin/ethtool -S $PRIMARY_IFACE | grep error"
    fi
fi

# Atomic Write
{
    echo "STATUS=$STATUS"
    echo "SUMMARY=$SUMMARY"
    [[ -n "$DETAIL" ]] && echo "DETAIL=$DETAIL"
    [[ -n "$REMEDIATE" ]] && echo "REMEDIATE=$REMEDIATE"
} > "$TEMP_FILE"

mv "$TEMP_FILE" "$STATE_FILE"
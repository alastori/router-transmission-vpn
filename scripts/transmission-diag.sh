#!/bin/sh
# /etc/transmission-diag.sh — One-command diagnostic for Transmission VPN setup
# Run: /etc/transmission-diag.sh
# Review: logread | grep watchdog  (for watchdog history)

TR="192.168.8.1:9091"
PASS="✓ PASS"
FAIL="✗ FAIL"
WARN="⚠ WARN"

divider() { echo ""; echo "═══════════════════════════════════════════════════"; echo "  $1"; echo "═══════════════════════════════════════════════════"; }

# -------------------------------------------------------------------
divider "1. VPN INTERFACE"
# -------------------------------------------------------------------
VPN_IF="$(ip -o -4 addr show | awk '{print $2}' | grep -m1 -E '^(ovpn|tun|wg)')"
if [ -n "$VPN_IF" ]; then
    VPN_IP="$(ip -o -4 addr show dev "$VPN_IF" 2>/dev/null | awk '/inet /{print $4}' | cut -d/ -f1)"
    echo "  Interface: $VPN_IF"
    echo "  IP:        $VPN_IP"
    echo "  Status:    $PASS — VPN tunnel is up"

    # TX/RX counters
    TX=$(cat /sys/class/net/"$VPN_IF"/statistics/tx_bytes 2>/dev/null || echo 0)
    RX=$(cat /sys/class/net/"$VPN_IF"/statistics/rx_bytes 2>/dev/null || echo 0)
    echo "  TX bytes:  $TX"
    echo "  RX bytes:  $RX"
else
    echo "  Status:    $FAIL — No VPN interface found"
    VPN_IF="ovpnclient1"
    VPN_IP=""
fi

# -------------------------------------------------------------------
divider "2. TRANSMISSION DAEMON"
# -------------------------------------------------------------------
PID=$(pgrep -x transmission-da 2>/dev/null)
if [ -n "$PID" ]; then
    echo "  PID:       $PID"
    echo "  Status:    $PASS — daemon is running"

    # Check bind address
    BIND_ADDR="$(uci -q get transmission.@transmission[0].bind_address_ipv4)"
    echo "  Bind addr: $BIND_ADDR"
    if [ "$BIND_ADDR" = "$VPN_IP" ]; then
        echo "  Bind:      $PASS — matches VPN IP"
    elif [ -n "$VPN_IP" ]; then
        echo "  Bind:      $FAIL — bind ($BIND_ADDR) != VPN IP ($VPN_IP)"
    fi

    # Check listening sockets
    echo ""
    echo "  Listening sockets:"
    netstat -ltn 2>/dev/null | grep -E ":(9091|51413)" | while read line; do
        echo "    $line"
    done
else
    echo "  Status:    $FAIL — daemon is NOT running"
fi

# -------------------------------------------------------------------
divider "3. NFT FIREWALL CHAIN"
# -------------------------------------------------------------------
if nft list chain inet fw4 transmission_vpn >/dev/null 2>&1; then
    echo "  Chain:     $PASS — transmission_vpn exists"
    echo ""
    echo "  Rules & counters:"
    nft -n list chain inet fw4 transmission_vpn 2>/dev/null | grep -E "counter|accept|reject" | while read line; do
        echo "    $line"
    done

    # Check for reject counter > 0 (indicates blocked traffic)
    REJECT_COUNT=$(nft -n list chain inet fw4 transmission_vpn 2>/dev/null | grep "counter.*reject" | sed 's/.*counter packets \([0-9]*\).*/\1/')
    if [ "${REJECT_COUNT:-0}" -gt 0 ]; then
        echo ""
        echo "  Reject:    $WARN — $REJECT_COUNT packets rejected (check for leaks or misconfig)"
    else
        echo ""
        echo "  Reject:    $PASS — no rejected packets"
    fi

    # Check OUTPUT jump
    if nft list chain inet fw4 output 2>/dev/null | grep -q "meta skuid.*jump transmission_vpn"; then
        echo "  Jump:      $PASS — OUTPUT jump rule present"
    else
        echo "  Jump:      $FAIL — OUTPUT jump rule MISSING"
    fi
else
    echo "  Chain:     $FAIL — transmission_vpn chain not found"
fi

# -------------------------------------------------------------------
divider "4. TORRENT STATUS"
# -------------------------------------------------------------------
if [ -n "$PID" ]; then
    TORRENT_LIST=$(transmission-remote "$TR" --list 2>/dev/null)
    if [ -n "$TORRENT_LIST" ]; then
        TOTAL=$(echo "$TORRENT_LIST" | awk 'NR>1 && $1 ~ /^[0-9]+/' | wc -l)
        ACTIVE=$(echo "$TORRENT_LIST" | awk 'NR>1 && $1 ~ /^[0-9]+/' | grep -cv 'Stopped')
        echo "  Total:     $TOTAL torrents ($ACTIVE active)"
        echo ""

        # Show first active torrent's tracker status
        FIRST_ID=$(echo "$TORRENT_LIST" | awk 'NR>1 && $1 ~ /^[0-9]+/ && $0 !~ /Stopped/ {print $1; exit}')
        if [ -n "$FIRST_ID" ]; then
            echo "  First active torrent (#$FIRST_ID) tracker status:"
            transmission-remote "$TR" --torrent "$FIRST_ID" --info-trackers 2>/dev/null | \
            grep -E "(Tracker [0-9]|Got a|Asking|announce|error|Connection)" | head -20 | \
            while read line; do
                echo "    $line"
            done

            # Check for connection failures
            FAILURES=$(transmission-remote "$TR" --torrent "$FIRST_ID" --info-trackers 2>/dev/null | grep -c "Connection failed")
            if [ "$FAILURES" -gt 0 ]; then
                echo ""
                echo "  Trackers:  $WARN — $FAILURES tracker(s) showing 'Connection failed'"
            else
                echo "  Trackers:  $PASS — no connection failures"
            fi
        fi

        # Session peer count
        PEERS=$(transmission-remote "$TR" --session-stats 2>/dev/null | awk -F: '/peers/{gsub(/[^0-9]/,"",$2); print $2}')
        echo ""
        echo "  Peers:     ${PEERS:-unknown}"
        if [ "${PEERS:-0}" -eq 0 ] && [ "$ACTIVE" -gt 0 ]; then
            echo "  Peers:     $WARN — 0 peers with $ACTIVE active torrents"
        elif [ "${PEERS:-0}" -gt 0 ]; then
            echo "  Peers:     $PASS — connected"
        fi
    else
        echo "  Status:    $WARN — cannot reach Transmission RPC"
    fi
else
    echo "  Status:    $FAIL — daemon not running, skipping"
fi

# -------------------------------------------------------------------
divider "5. ROUTING & IP RULES"
# -------------------------------------------------------------------
echo "  VPN-related routes:"
ip route show | grep -E "(ovpn|tun|wg)" | head -10 | while read line; do
    echo "    $line"
done

echo ""
echo "  IP rules:"
ip rule show 2>/dev/null | head -20 | while read line; do
    echo "    $line"
done

# -------------------------------------------------------------------
divider "6. VPN CONNECTIVITY"
# -------------------------------------------------------------------
if [ -n "$VPN_IF" ] && [ -n "$VPN_IP" ]; then
    # Ping through VPN
    if ping -c 2 -W 3 -I "$VPN_IF" 1.1.1.1 >/dev/null 2>&1; then
        echo "  Ping:      $PASS — VPN tunnel can reach 1.1.1.1"
    else
        echo "  Ping:      $FAIL — cannot ping 1.1.1.1 via $VPN_IF"
    fi
else
    echo "  Ping:      $FAIL — VPN not available, skipping"
fi

# -------------------------------------------------------------------
divider "7. DISK SPACE"
# -------------------------------------------------------------------
DL_DIR="$(uci -q get transmission.@transmission[0].download_dir)"
DL_DIR="${DL_DIR:-/tmp/transmission}"
if [ -d "$DL_DIR" ]; then
    USAGE=$(df -h "$DL_DIR" 2>/dev/null | awk 'NR==2{print $5}')
    AVAIL=$(df -h "$DL_DIR" 2>/dev/null | awk 'NR==2{print $4}')
    echo "  Download:  $DL_DIR"
    echo "  Used:      $USAGE"
    echo "  Available: $AVAIL"
    USAGE_PCT=$(echo "$USAGE" | tr -d '%')
    if [ "${USAGE_PCT:-0}" -gt 90 ]; then
        echo "  Disk:      $WARN — over 90% full"
    else
        echo "  Disk:      $PASS — sufficient space"
    fi
else
    echo "  Download:  $FAIL — directory $DL_DIR not found"
fi

# -------------------------------------------------------------------
divider "8. WATCHDOG STATUS"
# -------------------------------------------------------------------
if crontab -l 2>/dev/null | grep -q "transmission-watchdog"; then
    echo "  Cron:      $PASS — watchdog cron is active"
else
    echo "  Cron:      $WARN — watchdog cron not found"
fi

if [ -f /tmp/transmission-watchdog.last ]; then
    LAST_TX=$(cat /tmp/transmission-watchdog.last 2>/dev/null)
    echo "  Last TX:   $LAST_TX (saved by watchdog)"
else
    echo "  Last TX:   no state file yet (watchdog hasn't run)"
fi

echo ""
echo "  Recent watchdog log entries:"
logread 2>/dev/null | grep "transmission-watchdog" | tail -5 | while read line; do
    echo "    $line"
done

echo ""
echo "═══════════════════════════════════════════════════"
echo "  Diagnostic complete"
echo "═══════════════════════════════════════════════════"

#!/bin/sh
# /etc/reboot-test.sh — Post-reboot verification for all managed services
# Run after a router reboot or firmware update to confirm everything survived.
# Usage: ssh root@192.168.8.1 /etc/reboot-test.sh
#   or:  ./deploy.sh && ssh root@192.168.8.1 /etc/reboot-test.sh

PASS=0
FAIL=0

check() {
  # $1 = test name, $2 = command (returns 0=pass), $3 = detail on pass
  if eval "$2" >/dev/null 2>&1; then
    echo "  PASS: $1 — $3"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $1"
    FAIL=$((FAIL + 1))
  fi
}

echo "===== Reboot Test — $(date) ====="
echo "Uptime: $(uptime)"
echo ""

# 1. SD card
SDPATH=$(mount | grep disk1_part1 | awk '{print $3}')
check "SD card mounted" "mount | grep -q disk1_part1" "$SDPATH"

# 2. minidlna
check "minidlna running" "pgrep -f minidlna" "$(pgrep -f minidlna | wc -l | xargs) processes"

# 3. Transmission
check "Transmission running" "pgrep -f transmission-daemon" "PID $(pgrep -f transmission-daemon | head -1)"

# 4. VPN
WG_HAND=$(wg show wgclient 2>/dev/null | grep "latest handshake" | awk -F: '{$1=""; print $0}' | xargs)
check "WireGuard connected" "wg show wgclient 2>/dev/null | grep -q 'latest handshake'" "handshake: $WG_HAND"

# 5. nft chain
NFT_RULES=$(nft list chain inet fw4 transmission_vpn 2>/dev/null | grep -c 'accept\|reject')
check "nft firewall chain" "nft list chain inet fw4 transmission_vpn" "$NFT_RULES rules"

# 6. MAC filter (UCI)
MAC_COUNT=$(uci get wireless.wifi2g.maclist 2>/dev/null | wc -w)
check "MAC filter (UCI)" "[ $MAC_COUNT -ge 1 ]" "$MAC_COUNT MACs on wifi2g"

# 7. MAC filter (hostapd_cli runtime)
HOSTAPD_COUNT=$(hostapd_cli -p /var/run/hostapd-wifi0 -i wlan0 deny_acl SHOW 2>/dev/null | grep -c ':')
check "MAC filter (hostapd_cli)" "[ $HOSTAPD_COUNT -ge 1 ]" "$HOSTAPD_COUNT MACs via deny_acl"

# 8. WiFi 7
HWMODE=$(uci get wireless.wifi1.hwmode 2>/dev/null)
check "WiFi 7 on 5 GHz" "[ '$HWMODE' = '11bea' ]" "hwmode=$HWMODE"

# 9. Watchdog cron
check "Watchdog cron" "crontab -l 2>/dev/null | grep -q transmission-watchdog" "$(crontab -l 2>/dev/null | grep watchdog | xargs)"

# 10. UID routing
check "UID 224 routing" "ip rule list | grep -q 'uidrange 224-224'" "table 1001"

# 11. DHCP static leases
LEASE_COUNT=$(uci show dhcp 2>/dev/null | grep -c '@host\[.*\]=host')
check "DHCP static leases" "[ $LEASE_COUNT -ge 1 ]" "$LEASE_COUNT leases"

# 12. dnsmasq
check "dnsmasq running" "pgrep -f dnsmasq" "$(pgrep -f dnsmasq | wc -l | xargs) processes"

echo ""
echo "===== RESULT: $PASS PASS, $FAIL FAIL out of $((PASS + FAIL)) checks ====="

exit "$FAIL"

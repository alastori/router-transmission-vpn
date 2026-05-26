#!/bin/sh
# /etc/macfilter-apply.sh — Apply 2.4 GHz MAC deny list via hostapd_cli
# Belt-and-suspenders: UCI macfilter may not be applied reliably by qcawifi driver
# on MLO virtual interfaces (wlanmld2g). This script is called from /etc/rc.local.
#
# Intent: on jows-palencia (2.4 GHz + 5 GHz share the same SSID), force listed
# devices to 5 GHz for bandwidth (e.g. 4K HDR DLNA to Samsung TV). On
# jows-palencia-vpn (wlan01), allow any band — VPN caps throughput well under
# 2.4 GHz link rate, so forcing 5 GHz there has no benefit and creates a
# connection puzzle (TV picks 2.4 GHz by signal, association gets denied).
#
# Exception (2026-05-26): the bedroom Samsung TV ("TIZEN") has weak 5 GHz
# coverage in the bedroom, so on jows-palencia-vpn it must be pinned to 2.4 GHz
# (the opposite of the main SSID). It is therefore denied on the 5 GHz guest VAP
# wlan11 (VPN5_DENY below) while still allowed on the 2.4 GHz guest VAP wlan01.
#
# Device MAC lists are read from /etc/macfilter.conf, which is NOT in version
# control so device identifiers stay out of the public repo. See the tracked
# template macfilter.conf.example for the format.
#
# To add a new device, edit /etc/macfilter.conf on the router:
#   - Force to 5 GHz on jows-palencia (bandwidth): add MAC to MACS, then
#       uci add_list wireless.wifi2g.maclist='XX:XX:XX:XX:XX:XX'
#       uci add_list wireless.wlanmld2g.maclist='XX:XX:XX:XX:XX:XX'
#       uci commit wireless
#   - Force to 2.4 GHz on jows-palencia-vpn (range): add MAC to VPN5_DENY.

TAG="macfilter"
SOCK="/var/run/hostapd-wifi0"    # 2.4 GHz radio (wlan0 main, wlan01 guest, wlan02 MLO)
SOCK5="/var/run/hostapd-wifi1"   # 5 GHz radio  (wlan1 main, wlan11 guest/VPN)
CONF="/etc/macfilter.conf"

# Load device lists:
#   MACS      = denied on jows-palencia 2.4 GHz (wlan0 + wlan02) to force 5 GHz
#   VPN5_DENY = denied on jows-palencia-vpn 5 GHz (wlan11) to force 2.4 GHz
if [ ! -f "$CONF" ]; then
  logger -t "$TAG" "No $CONF found — no MAC lists to apply"
  exit 0
fi
. "$CONF"

# Wait for hostapd to be ready after boot
sleep 30

for iface in wlan0 wlan02; do
  for mac in $MACS; do
    hostapd_cli -p "$SOCK" -i "$iface" deny_acl ADD_MAC "$mac" 2>/dev/null
  done
done

# UCI wireless.wifi2g.maclist applies radio-wide, so wlan01 (jows-palencia-vpn)
# inherits the deny list at boot. Explicitly strip it so the guest/VPN SSID
# stays open for all MACS on either band.
for mac in $MACS; do
  hostapd_cli -p "$SOCK" -i wlan01 deny_acl DEL_MAC "$mac" 2>/dev/null
done

# Force VPN5_DENY devices onto 2.4 GHz on jows-palencia-vpn by denying them on
# the 5 GHz guest VAP (wlan11). These stay allowed on the 2.4 GHz guest VAP
# (wlan01), which the strip loop above guarantees.
for mac in $VPN5_DENY; do
  hostapd_cli -p "$SOCK5" -i wlan11 deny_acl ADD_MAC "$mac" 2>/dev/null
done

logger -t "$TAG" "Applied 2.4 GHz deny for $(echo $MACS | wc -w) devices on wlan0/wlan02 (wlan01 unfiltered); 5 GHz deny for $(echo $VPN5_DENY | wc -w) device(s) on wlan11 (jows-palencia-vpn forced to 2.4 GHz)"

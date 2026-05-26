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
# To add a new device:
#   1. Add its MAC to the MACS list below
#   2. Run: uci add_list wireless.wifi2g.maclist='XX:XX:XX:XX:XX:XX'
#          uci add_list wireless.wlanmld2g.maclist='XX:XX:XX:XX:XX:XX'
#          uci commit wireless
#   3. Deploy to router: ./deploy.sh

TAG="macfilter"
SOCK="/var/run/hostapd-wifi0"

# Denied on jows-palencia 2.4 GHz (wlan0 standard + wlan02 MLO) to force 5 GHz
MACS="00:00:00:00:00:01 00:00:00:00:00:02 00:00:00:00:00:03 00:00:00:00:00:04 00:00:00:00:00:05"

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

logger -t "$TAG" "Applied 2.4 GHz deny list for $(echo $MACS | wc -w) devices on wlan0/wlan02; wlan01 (jows-palencia-vpn) unfiltered"

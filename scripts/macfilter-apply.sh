#!/bin/sh
# /etc/macfilter-apply.sh — Apply 2.4 GHz MAC deny list via hostapd_cli
# Belt-and-suspenders: UCI macfilter may not be applied reliably by qcawifi driver
# on MLO virtual interfaces (wlanmld2g). This script is called from /etc/rc.local.
#
# To add a new device:
#   1. Add its MAC to the MACS list below
#   2. Run: uci add_list wireless.wifi2g.maclist='XX:XX:XX:XX:XX:XX'
#          uci add_list wireless.wlanmld2g.maclist='XX:XX:XX:XX:XX:XX'
#          uci commit wireless
#   3. Deploy to router: ./deploy.sh

TAG="macfilter"
SOCK="/var/run/hostapd-wifi0"
MACS="B0:F2:F6:C4:53:76 42:1E:A7:5C:0E:98 78:DD:12:F6:E7:1A 24:FC:E5:24:3D:EF"

# Wait for hostapd to be ready after boot
sleep 30

for iface in wlan0 wlan01 wlan02; do
  for mac in $MACS; do
    hostapd_cli -p "$SOCK" -i "$iface" deny_acl ADD_MAC "$mac" 2>/dev/null
  done
done

logger -t "$TAG" "Applied 2.4 GHz deny list for $(echo $MACS | wc -w) devices"

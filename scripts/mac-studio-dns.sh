#!/bin/sh
# mac-studio-dns: keep al-mac7.lan pointed at the live Mac Studio IP.
#
# The Mac Studio (AL-Mac7) has two DHCP reservations and alternates
# between them with its active SSID:
#   192.168.8.138  Flint SSID jows-palencia       (MAC c2:2a:55:d5:ab:40)
#   192.168.8.218  Cudy AP SSID jows-palencia-ap  (MAC 66:b3:fd:7f:56:46)
# Only one is active at a time. This script pings both and publishes
# whichever answers as al-mac7.lan in the dnsmasq addn-hosts file
# (/etc/dnsmasq.mac-studio.hosts, wired via dhcp.@dnsmasq[0].addnhosts),
# then SIGHUPs dnsmasq when the answer changes. If neither address
# answers, the last known address is kept (no flapping while the Mac
# reassociates).
#
# Cron: * * * * * /etc/mac-studio-dns.sh   (in /etc/crontabs/root)

HOSTS_FILE=/etc/dnsmasq.mac-studio.hosts
NAME=al-mac7.lan
IPS="192.168.8.218 192.168.8.138"

live=""
for ip in $IPS; do
    if ping -q -c 1 -W 2 "$ip" >/dev/null 2>&1; then
        live="$ip"
        break
    fi
done

[ -n "$live" ] || exit 0

cur=""
[ -f "$HOSTS_FILE" ] && cur="$(awk 'NR==1{print $1}' "$HOSTS_FILE")"

if [ "$live" != "$cur" ]; then
    echo "$live $NAME" > "$HOSTS_FILE"
    kill -HUP "$(pidof dnsmasq)" 2>/dev/null
    logger -t mac-studio-dns "al-mac7.lan -> $live (was: ${cur:-none})"
fi

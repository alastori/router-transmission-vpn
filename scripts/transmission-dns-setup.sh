#!/bin/sh
# Configure a private dnsmasq instance for Transmission-only DNS.
# The firewall redirects UID 224 DNS to this instance; normal LAN/router DNS
# stays on the main dnsmasq instance.

set -eu

TAG="transmission-dns-setup"
PORT="${TRANSMISSION_DNS_PORT:-$(uci -q get dhcp.transmission_dns.port 2>/dev/null || echo 1053)}"
SERVER="${TRANSMISSION_DNS_SERVER:-$(uci -q get dhcp.transmission_dns.server 2>/dev/null || true)}"
[ -n "$SERVER" ] || SERVER="$(uci -q get network.wgclient.dns 2>/dev/null | awk 'NR==1 { print $1 }')"

case "$PORT" in
  ''|*[!0-9]*)
    logger -t "$TAG" "ERROR: invalid port '$PORT'"
    exit 1
    ;;
esac

if [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
  logger -t "$TAG" "ERROR: invalid port '$PORT'"
  exit 1
fi

case "$SERVER" in
  ''|*[!0-9.]*)
    logger -t "$TAG" "ERROR: invalid DNS server '$SERVER'"
    exit 1
    ;;
esac

uci -q delete dhcp.transmission_dns || true
uci set dhcp.transmission_dns='dnsmasq'
uci set dhcp.transmission_dns.domainneeded='1'
uci set dhcp.transmission_dns.boguspriv='1'
uci set dhcp.transmission_dns.rebind_protection='0'
uci set dhcp.transmission_dns.localservice='1'
uci set dhcp.transmission_dns.noresolv='1'
uci set dhcp.transmission_dns.nohosts='1'
uci set dhcp.transmission_dns.readethers='0'
uci set dhcp.transmission_dns.filter_aaaa='1'
uci set dhcp.transmission_dns.cachesize='1000'
uci set dhcp.transmission_dns.port="$PORT"
uci set dhcp.transmission_dns.user='dnsmasq_vpn'
uci set dhcp.transmission_dns.leasefile='/tmp/dhcp.leases.transmission_dns'
uci add_list dhcp.transmission_dns.listen_address='127.0.0.1'
uci add_list dhcp.transmission_dns.server="$SERVER"
uci commit dhcp

if [ "${RESTART_DNSMASQ:-1}" = "1" ] && [ -x /etc/init.d/dnsmasq ]; then
  /etc/init.d/dnsmasq restart
fi

logger -t "$TAG" "configured Transmission DNS resolver on 127.0.0.1:$PORT using $SERVER"

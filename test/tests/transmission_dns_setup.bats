#!/usr/bin/env bats
# Tests for /etc/transmission-dns-setup.sh

load '../helpers/setup'

SETUP_SCRIPT="/etc/transmission-dns-setup.sh"

setup() {
  clean_state
}

@test "transmission dns setup: configures private dnsmasq from environment" {
  run env RESTART_DNSMASQ=0 TRANSMISSION_DNS_SERVER=103.86.96.100 TRANSMISSION_DNS_PORT=1053 "$SETUP_SCRIPT"
  assert_success

  run grep "dhcp.transmission_dns=dnsmasq" /tmp/uci_store
  assert_success

  run grep "dhcp.transmission_dns.port=1053" /tmp/uci_store
  assert_success

  run grep "dhcp.transmission_dns.user=dnsmasq_vpn" /tmp/uci_store
  assert_success

  run grep "dhcp.transmission_dns.listen_address=127.0.0.1" /tmp/uci_store
  assert_success

  run grep "dhcp.transmission_dns.server=103.86.96.100" /tmp/uci_store
  assert_success
}

@test "transmission dns setup: derives server from wgclient DNS" {
  uci_set "network.wgclient.dns" "103.86.96.100"

  run env RESTART_DNSMASQ=0 "$SETUP_SCRIPT"
  assert_success

  run grep "dhcp.transmission_dns.server=103.86.96.100" /tmp/uci_store
  assert_success
}

@test "transmission dns setup: rejects invalid server and port" {
  run env RESTART_DNSMASQ=0 TRANSMISSION_DNS_SERVER="bad; cmd" TRANSMISSION_DNS_PORT=bad "$SETUP_SCRIPT"
  assert_failure

  refute_log_contains "configured Transmission DNS resolver"
}

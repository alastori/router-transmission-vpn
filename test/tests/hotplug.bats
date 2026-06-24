#!/usr/bin/env bats
# Tests for /etc/hotplug.d/iface/99-transmission-vpn
# Exercises: interface filtering, ifdown, ifup with IP, IP change, no IP.

load '../helpers/setup'

HOTPLUG="/etc/hotplug.d/iface/99-transmission-vpn"
DNS_HOTPLUG="/etc/hotplug.d/iface/98-vpn-dns-routes"

setup() {
  clean_state
}

teardown() {
  stop_transmission 2>/dev/null || true
  ip route del 103.86.96.100/32 dev wgclient table main 2>/dev/null || true
  ip route del blackhole 103.86.96.100/32 table main 2>/dev/null || true
  remove_vpn_interface 2>/dev/null || true
}

# ── 1. Non-VPN interface → ignored ────────────────────────────────

@test "hotplug: non-VPN interface — no action" {
  INTERFACE=eth0 ACTION=ifup run "$HOTPLUG"
  assert_success

  # Syslog should be empty (no hotplug log from our script)
  run cat /tmp/test_syslog
  refute_output --partial "transmission-vpn-hotplug"
}

# ── 2. ifdown → stops transmission ────────────────────────────────

@test "hotplug: VPN ifdown — stops transmission" {
  create_vpn_interface
  start_transmission

  INTERFACE=ovpnclient1 ACTION=ifdown run "$HOTPLUG"
  assert_success
  assert_log_contains "VPN (ovpnclient1) down"
}

# ── 3. ifup → starts and reannounces ──────────────────────────────

@test "hotplug: VPN ifup — starts and reannounces" {
  create_vpn_interface ovpnclient1 10.8.0.2/24

  INTERFACE=ovpnclient1 ACTION=ifup run "$HOTPLUG"
  assert_success
  assert_log_contains "VPN (ovpnclient1) up (10.8.0.2)"
  assert_log_contains "Reannounced"
}

# ── 4. ifup with IP change → updates uci bind address ─────────────

@test "hotplug: VPN ifup with IP change — updates bind address" {
  create_vpn_interface ovpnclient1 10.8.0.99/24
  uci_set "transmission.@transmission[0].bind_address_ipv4" "10.8.0.2"

  INTERFACE=ovpnclient1 ACTION=ifup run "$HOTPLUG"
  assert_success
  assert_log_contains "VPN IP changed"

  # Verify uci store was updated
  run grep "bind_address_ipv4" /tmp/uci_store
  assert_output --partial "10.8.0.99"
}

# ── 5. ifup but no IP assigned yet ────────────────────────────────

@test "hotplug: VPN ifup no IP — starts with current bind" {
  # Create interface but don't assign an IP
  ip link add ovpnclient1 type dummy 2>/dev/null || true
  ip link set ovpnclient1 up

  INTERFACE=ovpnclient1 ACTION=ifup run "$HOTPLUG"
  assert_success
  assert_log_contains "no IP assigned yet"
}

# ── WireGuard-specific tests ────────────────────────────────────

@test "hotplug: WireGuard ifdown — stops transmission" {
  create_vpn_interface wgclient 10.2.0.2/32
  start_transmission

  INTERFACE=wgclient ACTION=ifdown run "$HOTPLUG"
  assert_success
  assert_log_contains "VPN (wgclient) down"
}

@test "hotplug: WireGuard ifup — starts and reannounces" {
  create_vpn_interface wgclient 10.2.0.2/32

  INTERFACE=wgclient ACTION=ifup run "$HOTPLUG"
  assert_success
  assert_log_contains "VPN (wgclient) up (10.2.0.2)"
  assert_log_contains "Reannounced"
}

@test "hotplug: WireGuard ifup with IP change — updates bind address" {
  create_vpn_interface wgclient 10.2.0.99/32
  uci_set "transmission.@transmission[0].bind_address_ipv4" "10.2.0.2"

  INTERFACE=wgclient ACTION=ifup run "$HOTPLUG"
  assert_success
  assert_log_contains "VPN IP changed"

  run grep "bind_address_ipv4" /tmp/uci_store
  assert_output --partial "10.2.0.99"
}


# ── VPN DNS route hotplug tests ───────────────────────────────────

@test "vpn dns hotplug: non-wgclient interface is ignored" {
  INTERFACE=eth0 ACTION=ifup run "$DNS_HOTPLUG"
  assert_success

  run cat /tmp/test_syslog
  refute_output --partial "vpn-dns-routes"
}

@test "vpn dns hotplug: ifup routes configured DNS through wgclient" {
  create_vpn_interface wgclient 10.2.0.2/32
  uci_set "network.wgclient.dns" "103.86.96.100"

  INTERFACE=wgclient ACTION=ifup run "$DNS_HOTPLUG"
  assert_success
  assert_log_contains "routed 103.86.96.100/32 through wgclient"

  run ip route show table main
  assert_output --partial "103.86.96.100 dev wgclient"
}

@test "vpn dns hotplug: ifdown blackholes configured DNS" {
  create_vpn_interface wgclient 10.2.0.2/32
  uci_set "network.wgclient.dns" "103.86.96.100"

  INTERFACE=wgclient ACTION=ifdown run "$DNS_HOTPLUG"
  assert_success
  assert_log_contains "blackholed 103.86.96.100/32 after wgclient down"

  run ip route show table main
  assert_output --partial "blackhole 103.86.96.100"
}

@test "vpn dns hotplug: falls back to pinned dnsmasq server" {
  create_vpn_interface wgclient 10.2.0.2/32
  uci_set "dhcp.@dnsmasq[0].server" "103.86.96.100"

  INTERFACE=wgclient ACTION=ifup run "$DNS_HOTPLUG"
  assert_success
  assert_log_contains "routed 103.86.96.100/32 through wgclient"
}

@test "vpn dns hotplug: invalid DNS is ignored" {
  create_vpn_interface wgclient 10.2.0.2/32
  uci_set "network.wgclient.dns" "103.86.96.100; nft flush ruleset"

  INTERFACE=wgclient ACTION=ifup run "$DNS_HOTPLUG"
  assert_success
  assert_log_contains "invalid VPN DNS"
}

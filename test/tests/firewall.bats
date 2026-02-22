#!/usr/bin/env bats
# Tests for /etc/firewall.user
# Exercises: chain creation, VPN auto-detect, WireGuard encap rule, UID routing, fail-closed.

load '../helpers/setup'

FIREWALL="/etc/firewall.user"

setup() {
  clean_state
  rm -f /tmp/nft_calls
  echo "firewall-fresh" > /tmp/nft_mode
}

teardown() {
  remove_vpn_interface 2>/dev/null || true
  rm -f /tmp/nft_calls
}

# ── 1. Creates chain and fail-closed reject rule ───────────────────

@test "firewall: creates chain with reject rule" {
  create_vpn_interface ovpnclient1 10.8.0.2/24

  run "$FIREWALL"
  assert_success

  # Verify nft calls include chain creation and reject
  run grep "add chain inet fw4 transmission_vpn" /tmp/nft_calls
  assert_success

  run grep "counter reject" /tmp/nft_calls
  assert_success
}

# ── 2. VPN auto-detect picks up ovpnclient ─────────────────────────

@test "firewall: auto-detects OpenVPN interface" {
  create_vpn_interface ovpnclient1 10.8.0.2/24

  run "$FIREWALL"
  assert_success

  run grep "oifname.*ovpnclient1.*accept" /tmp/nft_calls
  assert_success
}

# ── 3. VPN auto-detect picks up wgclient ───────────────────────────

@test "firewall: auto-detects WireGuard interface" {
  create_vpn_interface wgclient 10.2.0.2/32

  run "$FIREWALL"
  assert_success

  run grep "oifname.*wgclient.*accept" /tmp/nft_calls
  assert_success
}

# ── 4. WireGuard encap rule uses UCI endpoint + port ───────────────

@test "firewall: WireGuard encap rule reads endpoint from UCI" {
  create_vpn_interface wgclient 10.2.0.2/32
  uci_set "network.wgpeer0.endpoint_host" "84.20.19.75"
  uci_set "network.wgpeer0.endpoint_port" "51820"

  run "$FIREWALL"
  assert_success

  run grep "udp dport.*51820.*84.20.19.75.*accept" /tmp/nft_calls
  assert_success
}

# ── 5. WireGuard encap uses custom port from UCI ──────────────────

@test "firewall: WireGuard encap rule uses custom port" {
  create_vpn_interface wgclient 10.2.0.2/32
  uci_set "network.wgpeer0.endpoint_host" "1.2.3.4"
  uci_set "network.wgpeer0.endpoint_port" "4500"

  run "$FIREWALL"
  assert_success

  run grep "udp dport.*4500.*1.2.3.4" /tmp/nft_calls
  assert_success
}

# ── 6. No VPN endpoint → no encap rule, logs warning ──────────────

@test "firewall: no VPN endpoint — skips encap rule" {
  create_vpn_interface wgclient 10.2.0.2/32
  # No endpoint_host in UCI

  run "$FIREWALL"
  assert_success

  # Should NOT have WireGuard-encap rule
  run grep "WireGuard-encap" /tmp/nft_calls
  assert_failure
}

# ── 7. Invalid endpoint is rejected ───────────────────────────────

@test "firewall: invalid endpoint_host — skips encap rule" {
  create_vpn_interface wgclient 10.2.0.2/32
  uci_set "network.wgpeer0.endpoint_host" "evil; nft flush ruleset"

  run "$FIREWALL"
  assert_success

  # Injection attempt should be blocked
  run grep "flush ruleset" /tmp/nft_calls
  assert_failure

  # Should log error
  assert_log_contains "invalid endpoint_host"
}

# ── 8. RPC accept rules for LAN ──────────────────────────────────

@test "firewall: RPC accept rules for br-lan" {
  create_vpn_interface ovpnclient1 10.8.0.2/24

  run "$FIREWALL"
  assert_success

  run grep "tcp sport.*9091.*br-lan.*accept" /tmp/nft_calls
  assert_success
}

# ── 9. DNS accept rules ─────────────────────────────────────────

@test "firewall: DNS accept rules on br-lan" {
  create_vpn_interface ovpnclient1 10.8.0.2/24

  run "$FIREWALL"
  assert_success

  run grep "br-lan.*udp dport 53.*accept" /tmp/nft_calls
  assert_success

  run grep "br-lan.*tcp dport 53.*accept" /tmp/nft_calls
  assert_success
}

# ── 10. No VPN interface → defaults to wgclient with warning ─────

@test "firewall: no VPN interface — defaults to wgclient with warning" {
  # No VPN interface created

  run "$FIREWALL"
  assert_success

  run grep "oifname.*wgclient.*accept" /tmp/nft_calls
  assert_success

  assert_log_contains "No VPN interface found"
}

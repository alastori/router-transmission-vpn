#!/usr/bin/env bats
# Tests for /etc/transmission-diag.sh
# Exercises: all-pass scenario, VPN down, daemon down, disk warning.

load '../helpers/setup'

setup() {
  clean_state
  echo "present" > /tmp/nft_mode
  echo "success" > /tmp/ping_mode
  echo "*/10 * * * * /etc/transmission-watchdog.sh" > /tmp/test_crontab
}

teardown() {
  stop_transmission 2>/dev/null || true
  remove_vpn_interface 2>/dev/null || true
  teardown_tx_counter 2>/dev/null || true
  umount /tmp/transmission 2>/dev/null || true
}

# ── 1. All checks pass ────────────────────────────────────────────

@test "diag: all checks pass" {
  create_vpn_interface ovpnclient1 10.8.0.2/24
  setup_tx_counter ovpnclient1 12345
  start_transmission

  echo "active-with-peers" > /tmp/tr_override_mode
  uci_set "transmission.@transmission[0].bind_address_ipv4" "10.8.0.2"
  uci_set "transmission.@transmission[0].download_dir" "/tmp/transmission"

  run /etc/transmission-diag.sh
  assert_success
  assert_output --partial "PASS"
}

# ── 2. VPN down → FAIL ────────────────────────────────────────────

@test "diag: VPN down — reports failure" {
  # No VPN interface
  start_transmission

  run /etc/transmission-diag.sh
  assert_success
  assert_output --partial "FAIL"
  assert_output --partial "No VPN interface found"
}

# ── 3. Daemon not running → FAIL ──────────────────────────────────

@test "diag: daemon not running — reports failure" {
  create_vpn_interface ovpnclient1 10.8.0.2/24
  setup_tx_counter ovpnclient1 12345
  # Don't start transmission

  run /etc/transmission-diag.sh
  assert_success
  assert_output --partial "FAIL"
  assert_output --partial "daemon is NOT running"
}

# ── 4. Disk over 90% → WARN ──────────────────────────────────────

@test "diag: disk over 90% — reports warning" {
  create_vpn_interface ovpnclient1 10.8.0.2/24
  setup_tx_counter ovpnclient1 12345
  start_transmission

  echo "active-with-peers" > /tmp/tr_override_mode
  uci_set "transmission.@transmission[0].bind_address_ipv4" "10.8.0.2"

  # Create a tiny tmpfs and fill it to >90%
  mkdir -p /tmp/transmission-test-dl
  mount -t tmpfs -o size=1M tmpfs /tmp/transmission-test-dl
  dd if=/dev/zero of=/tmp/transmission-test-dl/fill bs=1K count=950 2>/dev/null || true
  uci_set "transmission.@transmission[0].download_dir" "/tmp/transmission-test-dl"

  run /etc/transmission-diag.sh
  assert_success
  assert_output --partial "WARN"
  assert_output --partial "over 90%"

  # Clean up
  rm -f /tmp/transmission-test-dl/fill
  umount /tmp/transmission-test-dl 2>/dev/null || true
}

#!/usr/bin/env bats
# Tests for /etc/transmission-watchdog.sh
# Exercises: VPN detection, daemon lifecycle, stale-state recovery, baseline recording.

load '../helpers/setup'

setup() {
  clean_state
  echo "present" > /tmp/nft_mode
  echo "success" > /tmp/ping_mode
}

teardown() {
  stop_transmission 2>/dev/null || true
  remove_vpn_interface 2>/dev/null || true
  teardown_tx_counter 2>/dev/null || true
}

# ── 1. VPN absent → exit 0, log "VPN interface not found" ──────────

@test "watchdog: VPN absent — skips with log message" {
  # No VPN interface created
  run /etc/transmission-watchdog.sh
  assert_success
  assert_log_contains "VPN interface not found"
}

# ── 2. Daemon not running → starts it ──────────────────────────────

@test "watchdog: daemon not running — starts and reannounces" {
  create_vpn_interface
  setup_tx_counter

  # Daemon is not running — watchdog should start it
  run /etc/transmission-watchdog.sh
  assert_success
  assert_log_contains "started and reannounced"
}

# ── 3. Healthy with peers → silent exit ────────────────────────────

@test "watchdog: healthy with peers — exits silently" {
  create_vpn_interface
  setup_tx_counter ovpnclient1 5000
  start_transmission

  echo "active-with-peers" > /tmp/tr_override_mode

  run /etc/transmission-watchdog.sh
  assert_success
  refute_log_contains "STALE"
  refute_log_contains "Restarting"
}

# ── 4. Stale state → restart ──────────────────────────────────────

@test "watchdog: stale state — restarts transmission" {
  create_vpn_interface
  setup_tx_counter ovpnclient1 5000
  start_transmission

  echo "active-no-peers" > /tmp/tr_override_mode

  # Simulate previous run: same TX value saved, init flag exists
  echo "5000" > /tmp/transmission-watchdog.last
  touch /tmp/transmission-watchdog.last.init

  run /etc/transmission-watchdog.sh
  assert_success
  assert_log_contains "STALE DETECTED"
}

# ── 5. First run baseline → records state, no restart ──────────────

@test "watchdog: first run — records baseline without restart" {
  create_vpn_interface
  setup_tx_counter ovpnclient1 5000
  start_transmission

  echo "active-no-peers" > /tmp/tr_override_mode

  # No state file, no init flag — this is the first run
  rm -f /tmp/transmission-watchdog.last /tmp/transmission-watchdog.last.init

  run /etc/transmission-watchdog.sh
  assert_success
  assert_log_contains "recording baseline"
  refute_log_contains "STALE"

  # State file and init flag should now exist
  [ -f /tmp/transmission-watchdog.last ]
  [ -f /tmp/transmission-watchdog.last.init ]
}

# ── 6. Counter growing → no restart despite 0 peers ───────────────

@test "watchdog: counter growing — no restart despite 0 peers" {
  create_vpn_interface
  setup_tx_counter ovpnclient1 10000
  start_transmission

  echo "active-no-peers" > /tmp/tr_override_mode

  # Previous TX was 5000, current is 10000 — counter grew
  echo "5000" > /tmp/transmission-watchdog.last
  touch /tmp/transmission-watchdog.last.init

  run /etc/transmission-watchdog.sh
  assert_success
  refute_log_contains "STALE"
  refute_log_contains "Restarting"
}

# ── WireGuard-specific tests ────────────────────────────────────

@test "watchdog: WireGuard VPN — detects interface and starts daemon" {
  create_vpn_interface wgclient 10.2.0.2/32
  setup_tx_counter wgclient

  run /etc/transmission-watchdog.sh
  assert_success
  assert_log_contains "started and reannounced"
}

@test "watchdog: WireGuard VPN healthy — exits silently" {
  create_vpn_interface wgclient 10.2.0.2/32
  setup_tx_counter wgclient 5000
  start_transmission

  echo "active-with-peers" > /tmp/tr_override_mode

  run /etc/transmission-watchdog.sh
  assert_success
  refute_log_contains "STALE"
  refute_log_contains "Restarting"
}

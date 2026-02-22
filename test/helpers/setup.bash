#!/usr/bin/env bash
# Bats helper — loaded by every .bats file via: load '../helpers/setup'
# Provides reusable functions for VPN simulation, Transmission control, and assertions.

load '/opt/bats-libs/bats-support-0.3.0/load'
load '/opt/bats-libs/bats-assert-2.1.0/load'

# ── VPN interface simulation ────────────────────────────────────────

create_vpn_interface() {
  local name="${1:-ovpnclient1}"
  local ip="${2:-10.8.0.2/24}"
  ip link add "$name" type dummy 2>/dev/null || true
  ip addr add "$ip" dev "$name" 2>/dev/null || true
  ip link set "$name" up
}

remove_vpn_interface() {
  local name="${1:-ovpnclient1}"
  ip link del "$name" 2>/dev/null || true
  # Also clean up wgclient if present (tests may create either)
  [ "$name" != "wgclient" ] && ip link del wgclient 2>/dev/null || true
}

# ── sysfs tx_bytes counter simulation ───────────────────────────────

setup_tx_counter() {
  local iface="${1:-ovpnclient1}"
  local value="${2:-0}"
  local sysdir="/sys/class/net/${iface}/statistics"
  mkdir -p "$sysdir" 2>/dev/null || true
  mount -t tmpfs tmpfs "$sysdir" 2>/dev/null || true
  echo "$value" > "${sysdir}/tx_bytes"
  echo "0" > "${sysdir}/rx_bytes"
}

teardown_tx_counter() {
  local iface="${1:-ovpnclient1}"
  umount "/sys/class/net/${iface}/statistics" 2>/dev/null || true
}

set_tx_bytes() {
  local iface="${1:-ovpnclient1}"
  local value="${2:-0}"
  echo "$value" > "/sys/class/net/${iface}/statistics/tx_bytes"
}

# ── Transmission daemon control ─────────────────────────────────────

start_transmission() {
  /etc/init.d/transmission start
  # Poll RPC for up to 10 seconds
  local i=0
  while [ $i -lt 20 ]; do
    if transmission-remote-real 127.0.0.1:9091 --list >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.5
    i=$((i + 1))
  done
  echo "WARNING: Transmission RPC did not become ready in 10s" >&2
  return 1
}

stop_transmission() {
  /etc/init.d/transmission stop
  # Wait for process to actually die
  local i=0
  while pgrep -x transmission-da >/dev/null 2>&1 && [ $i -lt 10 ]; do
    sleep 0.5
    i=$((i + 1))
  done
}

# ── UCI mock helpers ────────────────────────────────────────────────

uci_reset() {
  : > /tmp/uci_store
}

uci_set() {
  local key="$1" value="$2"
  if grep -qF "${key}=" /tmp/uci_store 2>/dev/null; then
    awk -v k="$key" -v v="$value" 'BEGIN{FS="="; OFS="="} $1==k{$0=k"="v} {print}' /tmp/uci_store > /tmp/uci_store.tmp
    mv /tmp/uci_store.tmp /tmp/uci_store
  else
    echo "${key}=${value}" >> /tmp/uci_store
  fi
}

# ── Syslog assertions ──────────────────────────────────────────────

assert_log_contains() {
  local pattern="$1"
  local log
  log=$(cat /tmp/test_syslog 2>/dev/null || true)
  if ! echo "$log" | grep -q "$pattern"; then
    echo "Expected syslog to contain: $pattern"
    echo "Actual syslog contents:"
    echo "$log"
    return 1
  fi
}

refute_log_contains() {
  local pattern="$1"
  local log
  log=$(cat /tmp/test_syslog 2>/dev/null || true)
  if echo "$log" | grep -q "$pattern"; then
    echo "Expected syslog NOT to contain: $pattern"
    echo "Actual syslog contents:"
    echo "$log"
    return 1
  fi
}

# ── State cleanup ──────────────────────────────────────────────────

clean_state() {
  rm -f /tmp/test_syslog
  rm -f /tmp/uci_store
  rm -f /tmp/nft_mode
  rm -f /tmp/nft_calls
  rm -f /tmp/ping_mode
  rm -f /tmp/test_crontab
  rm -f /tmp/tr_override_mode
  rm -f /tmp/transmission-watchdog.last
  rm -f /tmp/transmission-watchdog.last.tmp
  rm -f /tmp/transmission-watchdog.last.init
  touch /tmp/uci_store
  touch /tmp/test_syslog
  # Set RPC bind to localhost for test container (scripts read from UCI dynamically)
  uci_set "transmission.@transmission[0].rpc_bind_address" "127.0.0.1"
  uci_set "transmission.@transmission[0].rpc_port" "9091"
}

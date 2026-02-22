#!/bin/sh
# /etc/transmission-watchdog.sh — Periodic health check for Transmission
# Detects "stale daemon" state (running but stuck in tracker backoff) and recovers.
# Install: crontab -e → */10 * * * * /etc/transmission-watchdog.sh
#
# Logic:
#   1. If VPN is down → skip (hotplug handles stop/start)
#   2. If Transmission is not running → start it
#   3. If active torrents exist but 0 peers AND VPN TX counter hasn't grown → restart + reannounce
#
# Works with both OpenVPN (ovpnclient1) and WireGuard (wgclient).

TAG="transmission-watchdog"
STATE_FILE="/tmp/transmission-watchdog.last"
RPC="$(uci -q get transmission.@transmission[0].rpc_bind_address || echo 192.168.8.1)"
RPC_PORT="$(uci -q get transmission.@transmission[0].rpc_port || echo 9091)"
TR="$RPC:$RPC_PORT"

log() { logger -t "$TAG" "$*"; }

# --- 1) VPN must be up (otherwise hotplug owns lifecycle) ---
VPN_IF="$(ip -o -4 addr show | awk '{print $2}' | grep -m1 -E '^(wg|ovpn|tun)')"
if [ -z "$VPN_IF" ]; then
    log "VPN interface not found — skipping (hotplug handles this)"
    exit 0
fi

# --- 2) Transmission must be running ---
# Note: pgrep -x truncates on BusyBox; use pgrep -f for reliable matching
if ! pgrep -f transmission-daemon >/dev/null 2>&1; then
    log "Transmission not running — starting"
    /etc/init.d/transmission start
    sleep 5
    # Force reannounce after start
    transmission-remote "$TR" --list 2>/dev/null | awk 'NR>1 && $1 ~ /^[0-9]+/ {print $1}' | \
    while read id; do transmission-remote "$TR" --torrent "$id" --reannounce 2>/dev/null; done
    log "Transmission started and reannounced"
    exit 0
fi

# --- 3) Check for stale state ---
# Count active (non-paused) torrents
ACTIVE=$(transmission-remote "$TR" --list 2>/dev/null | awk 'NR>1 && $1 ~ /^[0-9]+/' | grep -cv 'Stopped')
if [ "$ACTIVE" -eq 0 ] 2>/dev/null; then
    exit 0  # No active torrents — nothing to check
fi

# Use session-stats for total peer count
PEERS_SESSION=$(transmission-remote "$TR" --session-stats 2>/dev/null | awk -F: '/peers/{gsub(/[^0-9]/,"",$2); print $2}')

# Get current VPN TX bytes counter
VPN_TX=$(cat /sys/class/net/"$VPN_IF"/statistics/tx_bytes 2>/dev/null || echo 0)

# Read previous TX counter
PREV_TX=0
[ -f "$STATE_FILE" ] && PREV_TX=$(cat "$STATE_FILE" 2>/dev/null || echo 0)

# Save current counter for next run (atomic write to avoid corruption)
echo "$VPN_TX" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"

# If peers > 0 or VPN counter is growing, everything is fine
[ "${PEERS_SESSION:-0}" -gt 0 ] && exit 0
[ "$VPN_TX" != "$PREV_TX" ] && [ "$PREV_TX" != "0" ] && exit 0

# First run (no previous state) — just record baseline, don't restart yet
if [ "$PREV_TX" = "0" ] && [ ! -f "$STATE_FILE.init" ]; then
    touch "$STATE_FILE.init"
    log "First check: $ACTIVE active, 0 peers, VPN TX=$VPN_TX — recording baseline"
    exit 0
fi

# --- Stale state detected: active torrents, 0 peers, stagnant VPN counter ---
log "STALE DETECTED: $ACTIVE active torrents, 0 peers, VPN TX stagnant ($PREV_TX -> $VPN_TX)"

/etc/init.d/transmission stop
sleep 2
/etc/init.d/transmission start
sleep 5

# Force reannounce all active torrents
transmission-remote "$TR" --list 2>/dev/null | awk 'NR>1 && $1 ~ /^[0-9]+/ {print $1}' | \
while read id; do
    transmission-remote "$TR" --torrent "$id" --reannounce 2>/dev/null
done

log "Transmission restarted and reannounced all torrents"

# Reset init flag so next stale detection has a clean baseline
rm -f "$STATE_FILE.init"

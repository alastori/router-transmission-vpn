#!/bin/sh
# Deploy scripts to the router via SCP + SSH
# Usage: ./deploy.sh [router_ip]
#
# Copies all scripts to the router and installs the watchdog cron job.

ROUTER="${1:-192.168.8.1}"
SCRIPT_DIR="$(cd "$(dirname "$0")/scripts" && pwd)"

echo "Deploying to root@$ROUTER ..."

# Copy scripts to the router
scp "$SCRIPT_DIR/transmission-watchdog.sh"  "root@$ROUTER:/etc/transmission-watchdog.sh"
scp "$SCRIPT_DIR/transmission-diag.sh"      "root@$ROUTER:/etc/transmission-diag.sh"
scp "$SCRIPT_DIR/99-transmission-vpn"        "root@$ROUTER:/etc/hotplug.d/iface/99-transmission-vpn"
scp "$SCRIPT_DIR/transmission-README"        "root@$ROUTER:/etc/transmission/README"
scp "$SCRIPT_DIR/transmission-subtitles.sh"  "root@$ROUTER:/etc/transmission-subtitles.sh"
scp "$SCRIPT_DIR/oshash.lua"                 "root@$ROUTER:/etc/transmission/oshash.lua"

# Deploy config template only if not already present (preserve credentials)
ssh "root@$ROUTER" 'test -f /etc/transmission/opensubtitles.conf' 2>/dev/null || \
  scp "$SCRIPT_DIR/opensubtitles.conf.example" "root@$ROUTER:/etc/transmission/opensubtitles.conf"

# Make scripts executable, install cron, configure script-torrent-done
ssh "root@$ROUTER" '
  chmod +x /etc/transmission-watchdog.sh /etc/transmission-diag.sh /etc/hotplug.d/iface/99-transmission-vpn /etc/transmission-subtitles.sh
  # Install watchdog cron if not already present
  (crontab -l 2>/dev/null | grep -q "transmission-watchdog" || \
   (crontab -l 2>/dev/null; echo "*/10 * * * * /etc/transmission-watchdog.sh") | crontab -)
  # Configure Transmission to call subtitle script on torrent completion
  uci set transmission.@transmission[0].script_torrent_done_enabled="true"
  uci set transmission.@transmission[0].script_torrent_done_filename="/etc/transmission-subtitles.sh"
  uci commit transmission
  /etc/init.d/transmission restart
  echo "Done. Verifying..."
  echo "  Cron: $(crontab -l 2>/dev/null | grep watchdog)"
  echo "  Scripts:"
  ls -la /etc/transmission-watchdog.sh /etc/transmission-diag.sh /etc/hotplug.d/iface/99-transmission-vpn /etc/transmission/README /etc/transmission-subtitles.sh /etc/transmission/oshash.lua /etc/transmission/opensubtitles.conf
'

echo ""
echo "Deployment complete. Run diagnostics with:"
echo "  ssh root@$ROUTER /etc/transmission-diag.sh"

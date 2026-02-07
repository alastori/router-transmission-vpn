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

# Make scripts executable and install cron
ssh "root@$ROUTER" '
  chmod +x /etc/transmission-watchdog.sh /etc/transmission-diag.sh /etc/hotplug.d/iface/99-transmission-vpn
  # Install watchdog cron if not already present
  (crontab -l 2>/dev/null | grep -q "transmission-watchdog" || \
   (crontab -l 2>/dev/null; echo "*/10 * * * * /etc/transmission-watchdog.sh") | crontab -)
  echo "Done. Verifying..."
  echo "  Cron: $(crontab -l 2>/dev/null | grep watchdog)"
  echo "  Scripts:"
  ls -la /etc/transmission-watchdog.sh /etc/transmission-diag.sh /etc/hotplug.d/iface/99-transmission-vpn /etc/transmission/README
'

echo ""
echo "Deployment complete. Run diagnostics with:"
echo "  ssh root@$ROUTER /etc/transmission-diag.sh"

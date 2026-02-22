#!/bin/sh
# Backup router UCI config to local machine
# Usage: ./backup.sh [router_ip]
#
# Exports all UCI config + key files from the router and saves them in
# .backups/<timestamp>/ (gitignored — contains credentials).
#
# Restore: scp the backup to the router and run uci import / copy files back.

set -e

ROUTER="${1:-192.168.8.1}"
TIMESTAMP="$(date +%Y-%m-%d_%H%M)"
BACKUP_DIR="$(cd "$(dirname "$0")" && pwd)/.backups/$TIMESTAMP"

mkdir -p "$BACKUP_DIR"

echo "Backing up router config from root@$ROUTER ..."
echo "Destination: $BACKUP_DIR"
echo ""

# 1. Full UCI export (all packages)
echo "  [1/4] UCI export..."
ssh "root@$ROUTER" "uci export" > "$BACKUP_DIR/uci-export.txt"

# 2. Individual UCI packages (easier to read/restore selectively)
echo "  [2/4] Individual UCI packages..."
mkdir -p "$BACKUP_DIR/uci"
for pkg in network wireless dhcp firewall transmission minidlna sqm ecm system; do
  ssh "root@$ROUTER" "uci export $pkg 2>/dev/null" > "$BACKUP_DIR/uci/$pkg.txt" 2>/dev/null || true
done

# 3. Key config files not in UCI
echo "  [3/4] Config files..."
mkdir -p "$BACKUP_DIR/files"
scp -O "root@$ROUTER:/etc/rc.local" "$BACKUP_DIR/files/rc.local" 2>/dev/null || true
scp -O "root@$ROUTER:/etc/crontabs/root" "$BACKUP_DIR/files/crontab" 2>/dev/null || true
scp -O "root@$ROUTER:/etc/macfilter-apply.sh" "$BACKUP_DIR/files/macfilter-apply.sh" 2>/dev/null || true
scp -O "root@$ROUTER:/etc/transmission/opensubtitles.conf" "$BACKUP_DIR/files/opensubtitles.conf" 2>/dev/null || true

# 4. Installed packages list (for reinstalling after firmware update)
echo "  [4/4] Package list..."
ssh "root@$ROUTER" "opkg list-installed" > "$BACKUP_DIR/packages.txt"

# Summary
echo ""
echo "Backup complete:"
ls -la "$BACKUP_DIR/"
echo ""
echo "UCI packages:"
ls "$BACKUP_DIR/uci/"
echo ""
echo "Files:"
ls "$BACKUP_DIR/files/" 2>/dev/null || echo "  (none)"
echo ""

# Count
TOTAL=$(find "$BACKUP_DIR" -type f | wc -l | xargs)
SIZE=$(du -sh "$BACKUP_DIR" | awk '{print $1}')
echo "Total: $TOTAL files, $SIZE"
echo ""
echo "To list all backups: ls -la .backups/"

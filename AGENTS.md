# router-transmission-vpn

Shell scripts for managing Transmission BitTorrent daemon lifecycle on OpenWrt, ensuring all peer traffic flows exclusively through a VPN tunnel.

## Repository structure

- `scripts/` — Production scripts deployed to the router via `deploy.sh`
  - `firewall.user` → `/etc/firewall.user` (nft per-UID chain + UID routing)
  - `transmission-watchdog.sh` → `/etc/transmission-watchdog.sh` (cron, every 10 min)
  - `99-transmission-vpn` → `/etc/hotplug.d/iface/99-transmission-vpn` (hotplug event handler)
  - `transmission-diag.sh` → `/etc/transmission-diag.sh` (diagnostic tool)
  - `on-complete.sh` → `/etc/transmission/on-complete.sh` (copies to Movies for DLNA)
  - `transmission-README` → `/etc/transmission/README` (on-router quick reference)
  - `transmission-subtitles.sh` → `/etc/transmission-subtitles.sh` (script-torrent-done hook for auto subtitle downloads)
  - `oshash.lua` → `/etc/transmission/oshash.lua` (OpenSubtitles hash computation, Lua 5.1)
  - `opensubtitles.conf.example` → `/etc/transmission/opensubtitles.conf` (template, deployed only if not present)
- `deploy.sh` — SCP+SSH deployment to the router (uses `scp -O` for OpenWrt compat)
- `test/` — Docker-based test suite

## Target environment

- Device: GL-BE9300 (Flint 3), OpenWrt (also tested on GL-AXT1800)
- Firewall: fw4/nftables
- VPN: WireGuard `wgclient` or OpenVPN `ovpnclient1` (auto-detected)
- Transmission 4.x, UID 224
- RPC: `192.168.8.1:9091` (LAN-only bind)
- Subtitle dependencies: `curl`, `ca-bundle` (required); `ffprobe` (optional, for embedded sub detection)
- OpenSubtitles config: `/etc/transmission/opensubtitles.conf` (credentials + feature flags)

## Key gotchas

- `bind_address_ipv4` only affects peer sockets — UID routing (`ip rule`) needed for trackers
- WireGuard encap packets exit via `eth0` not `wgclient` — need explicit nft accept rule
- procd `respawn` races with hotplug stop — nft fail-closed protects regardless
- `pgrep -x` truncates on BusyBox — use `pgrep -f transmission-daemon`
- OpenWrt scp needs `-O` flag (no sftp-server)
- RPC binds to `192.168.8.1` not `127.0.0.1` — use LAN IP in all scripts

## Scripts use POSIX sh

All scripts use `#!/bin/sh` and must remain compatible with BusyBox `ash` (OpenWrt's default shell). Do not use bashisms.

## Testing

Tests are run in a Docker container that simulates the OpenWrt environment.

```bash
./test/run-tests.sh
```

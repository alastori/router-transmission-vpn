# router-transmission-vpn

Shell scripts for managing Transmission BitTorrent daemon lifecycle on a GL-AXT1800 OpenWrt router, ensuring all peer traffic flows exclusively through the VPN tunnel.

## Repository structure

- `scripts/` — Production scripts deployed to the router via `deploy.sh`
  - `transmission-watchdog.sh` → `/etc/transmission-watchdog.sh` (cron, every 10 min)
  - `99-transmission-vpn` → `/etc/hotplug.d/iface/99-transmission-vpn` (hotplug event handler)
  - `transmission-diag.sh` → `/etc/transmission-diag.sh` (diagnostic tool)
  - `transmission-README` → `/etc/transmission/README` (on-router quick reference)
- `deploy.sh` — SCP+SSH deployment to the router
- `test/` — Docker-based test suite (see `HANDOFF-test-suite.md` for implementation spec)

## Target environment

- Device: GL-AXT1800, OpenWrt 23.05
- Firewall: fw4/nftables
- VPN interface: `ovpnclient1` (OpenVPN)
- Transmission 4.x, UID 224
- RPC: `192.168.8.1:9091`

## Scripts use POSIX sh

All scripts use `#!/bin/sh` and must remain compatible with BusyBox `ash` (OpenWrt's default shell). Do not use bashisms.

## Testing

Tests are run in a Docker container that simulates the OpenWrt environment. See `HANDOFF-test-suite.md` for the full test plan and implementation spec.

```bash
./test/run-tests.sh
```

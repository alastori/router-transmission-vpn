# router-transmission-vpn

Shell scripts that manage the Transmission BitTorrent daemon on an OpenWrt router, ensuring **all peer traffic flows exclusively through the VPN tunnel**.

Originally built for GL-AXT1800 (OpenVPN), now updated for GL-BE9300 Flint 3 (WireGuard). Scripts auto-detect VPN type.

## What This Does

| Script | Role | Trigger |
|--------|------|---------|
| `firewall.user` | nft per-UID chain + UID routing — VPN-only egress for Transmission | Firewall reload |
| `99-transmission-vpn` | Stops Transmission on VPN down, rebinds + reannounces on VPN up | Hotplug (interface events) |
| `transmission-watchdog.sh` | Detects "stale daemon" (running but stuck in tracker backoff) and auto-recovers | Cron, every 10 min |
| `transmission-diag.sh` | One-command diagnostic with PASS/FAIL/WARN for every component | Manual |
| `on-complete.sh` | Copies completed downloads to Movies folder for DLNA serving | Transmission done-script |

## Quick Start

### Prerequisites

- OpenWrt router with `fw4`/nftables
- VPN client configured (WireGuard `wgclient` or OpenVPN `ovpnclient1`)
- Transmission 4.x installed (`opkg install transmission-daemon transmission-web transmission-remote`)
- VPN routing table 1001 with default route through VPN interface

### Deploy

```bash
git clone https://github.com/alastori/router-transmission-vpn.git
cd router-transmission-vpn
./deploy.sh                  # deploys to 192.168.8.1 (default)
./deploy.sh 192.168.8.100    # or specify a different IP
```

### Verify

```bash
ssh root@192.168.8.1 /etc/transmission-diag.sh
```

### Quick Commands

```bash
# On the router:
/etc/init.d/transmission status
/etc/init.d/transmission restart
transmission-remote 192.168.8.1:9091 --list
transmission-remote 192.168.8.1:9091 --torrent all --reannounce
/etc/transmission-diag.sh
logread | grep watchdog
logread | grep transmission-vpn-hotplug
```

## Target Environment

- **Device:** GL-BE9300 (Flint 3), OpenWrt (also tested on GL-AXT1800)
- **Firewall:** fw4 / nftables
- **VPN:** WireGuard (`wgclient`) or OpenVPN (`ovpnclient1`) — auto-detected
- **Transmission:** 4.x, UID 224
- **RPC:** `192.168.8.1:9091` (LAN-only bind)

## Repository Structure

```
scripts/
  firewall.user              → /etc/firewall.user (nft chain + UID routing)
  99-transmission-vpn        → /etc/hotplug.d/iface/99-transmission-vpn
  transmission-watchdog.sh   → /etc/transmission-watchdog.sh
  transmission-diag.sh       → /etc/transmission-diag.sh
  on-complete.sh             → /etc/transmission/on-complete.sh
  transmission-README        → /etc/transmission/README
  transmission-subtitles.sh  → /etc/transmission-subtitles.sh
  oshash.lua                 → /etc/transmission/oshash.lua
deploy.sh                    # SCP + SSH deployment
test/                        # Docker-based test suite
```

## Architecture

```
Transmission (UID 224)
    ├── ip rule: uidrange 224-224 → table 1001 (VPN)
    └── nft chain transmission_vpn (OUTPUT):
          ├── tcp sport 9091 → br-lan     ACCEPT  (RPC replies)
          ├── udp/tcp dport 53 → br-lan   ACCEPT  (DNS)
          ├── oifname lo                   ACCEPT  (loopback)
          ├── oifname wgclient             ACCEPT  (VPN peers+trackers)
          ├── udp dport 51820 → VPN EP    ACCEPT  (WireGuard encap)
          └── REJECT                               (fail-closed)
```

Key findings from deployment:
- `bind_address_ipv4` only affects peer sockets, not tracker connections — UID routing is required
- WireGuard kernel encapsulation sends encrypted packets via `eth0`, not `wgclient` — needs explicit nft rule
- procd `respawn` races with hotplug `stop` — nft fail-closed prevents leaks regardless of daemon state
- `pgrep -x` truncates on BusyBox — use `pgrep -f` for reliable matching
- OpenWrt `scp` needs `-O` flag (no sftp-server)

---

## Development

### POSIX sh Only

All scripts use `#!/bin/sh` and must remain compatible with BusyBox `ash` (OpenWrt's default shell). Do not use bashisms.

### Running Tests

```bash
./test/run-tests.sh                      # build container + run all tests

# Run a specific test file:
docker compose -f test/docker-compose.yml run --rm test bats tests/watchdog.bats

# Run a single test by name:
docker compose -f test/docker-compose.yml run --rm test bats -f "stale state" tests/watchdog.bats
```

### Test Architecture

- **Alpine 3.21** container (same `ash` shell as OpenWrt)
- **Real Transmission daemon** inside the container (avoids fragile output mocking)
- **bats-core** test runner with `bats-assert` for assertions
- **Mock tools** for OpenWrt-specific commands (`uci`, `nft`, `logger`, etc.)
- **VPN simulation** via dummy network interfaces + tmpfs-mounted sysfs counters

## License

[MIT](LICENSE)

# router-transmission-vpn

Shell scripts that manage the Transmission BitTorrent daemon on a GL-AXT1800 (Flint) OpenWrt router, ensuring **all peer traffic flows exclusively through the VPN tunnel**.

## What This Does

| Script | Role | Trigger |
|--------|------|---------|
| `transmission-watchdog.sh` | Detects "stale daemon" (running but stuck in tracker backoff) and auto-recovers | Cron, every 10 min |
| `99-transmission-vpn` | Stops Transmission on VPN down, rebinds + reannounces on VPN up | Hotplug (interface events) |
| `transmission-diag.sh` | One-command diagnostic with PASS/FAIL/WARN for every component | Manual |

## Quick Start

### Prerequisites

- GL-AXT1800 running OpenWrt 23.05 with `fw4`/nftables
- OpenVPN client configured (interface: `ovpnclient1`)
- Transmission 4.x installed (`opkg install transmission-daemon-openssl transmission-cli-openssl`)
- nftables chain `transmission_vpn` restricting UID 224 to VPN-only egress

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

- **Device:** GL-AXT1800 (Flint), OpenWrt 23.05
- **Firewall:** fw4 / nftables
- **VPN:** OpenVPN, interface `ovpnclient1`
- **Transmission:** 4.x, UID 224
- **RPC:** `192.168.8.1:9091`

## Repository Structure

```
scripts/
  transmission-watchdog.sh    → /etc/transmission-watchdog.sh
  99-transmission-vpn         → /etc/hotplug.d/iface/99-transmission-vpn
  transmission-diag.sh        → /etc/transmission-diag.sh
  transmission-README         → /etc/transmission/README
deploy.sh                     # SCP + SSH deployment
test/                         # Docker-based test suite
```

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

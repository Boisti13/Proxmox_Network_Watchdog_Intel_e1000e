# Proxmox Network Watchdog (e1000e hang mitigation / safe bridge-only edition)

This package provides a **systemd-based watchdog** that monitors the Proxmox management network
(`vmbr0` → physical NIC) and performs **non-destructive recovery** if connectivity is lost.

Unlike the legacy version, this edition **does not bounce the physical NIC or reload the `e1000e` driver**.
Instead, it:
- Pings a local target (gateway or any reliably reachable LAN host)
- Waits for consecutive failures before acting
- Cycles only the **bridge (`vmbr0`)** on failure
- Adds a **carrier-grace window** before escalating (handles Powerline/switch wake events)
- Optionally reboots the host (rate-limited, one-time) if recovery fails
- Loads the Intel hardware watchdog (`iTCO_wdt`) for redundancy

Tested on: **Lenovo M920q (Intel i219)**, Proxmox VE 8 / 9.

---

## 📁 Installed file locations

| File | Purpose |
|------|----------|
| `/usr/local/sbin/net-reboot-if-down.sh` | Main watchdog script (bridge-only recovery logic) |
| `/etc/systemd/system/net-watch.service` | Systemd service that executes the script |
| `/etc/systemd/system/net-watch.timer` | Systemd timer (default: every 2 minutes) |
| `/etc/modules-load.d/watchdog.conf` | Ensures `iTCO_wdt` loads at boot |
| `/usr/local/bin/install.sh` | Installer script (this repo) |
| `/usr/local/bin/uninstall.sh` | Uninstaller script (this repo) |
| `/var/lib/net-watch/` | Persistent state directory (fail counter, reboot flag) |

---

## ⚙️ What it does

1. Checks connectivity by pinging `TARGETS` (default: local gateway/LAN host — **no public IPs**)
2. If all targets fail × 3 in a row → brings `vmbr0` **down/up** (does *not* touch the physical NIC)
3. If still unreachable and physical carrier is up → waits an extra 10s (carrier-grace for Powerline/switch wake)
4. If still unreachable → **reboots** the host (rate-limited, cooldown = 30 min, **one reboot only** until manually cleared)

### Recovery escalation

| Stage | Trigger | Action |
|---|---|---|
| Fail 1–2 | < 3 consecutive failures | Flush ARP cache for the target, exit |
| Fail 3 | 3 consecutive failures | Bounce `vmbr0` (down → 3s → up → 7s), re-check |
| Carrier grace | Bridge bounce failed, but physical link is up | Wait 10s, re-check |
| Reboot | Everything above failed | Reboot host |

### Reboot safeguards

- **Boot grace:** No action during first 5 min after boot
- **Only-once:** After one reboot, creates `/var/lib/net-watch/rebooted.once` — no further reboots until you remove that file
- **Rate limit:** Minimum 30 min between reboots regardless

---

## 🔧 Configuration

Edit the tunables at the top of `/usr/local/sbin/net-reboot-if-down.sh`:

```bash
TARGETS=("192.168.178.150")    # set to your local gateway / reachability target
MAX_FAILS=3                    # consecutive failures before taking action
BOOT_GRACE_SEC=300             # ignore failures for first 5 minutes after boot
BRIDGE_NAME="vmbr0"
REBOOT_COOLDOWN_MIN=30         # minimum minutes between reboots
ONLY_ONE_REBOOT=1              # reboot only once until flag is manually cleared
```

> **Note:** Only local LAN targets are used by default. Public IPs (e.g. `1.1.1.1`) were intentionally removed — the watchdog should react to local network loss, not internet outages.

---

## 🚀 Quick install

```bash
# as root
./install.sh
```

This will:
1. Copy the script and systemd units into place
2. Load and persist the Intel hardware watchdog (`iTCO_wdt`)
3. Enable and start the `net-watch.timer`

---

## 🧰 Optional: NIC mitigations (recommended)

Add these lines to your `/etc/network/interfaces` to disable energy-saving features
that can cause `e1000e` link flaps:

```ini
auto eno1
iface eno1 inet manual
    pre-up  /sbin/ethtool --set-eee eno1 eee off || true
    post-up /sbin/ethtool -K eno1 tso off gso off gro off || true
```

Then reload:
```bash
ifreload -a
# or: systemctl restart networking
```

---

## 🧩 Optional: Kernel parameters

If link resets still appear in `dmesg`, add the following to `/etc/default/grub`:
```
pcie_aspm=off e1000e.SmartPowerDownEnable=0
```
Then run:
```bash
update-grub
reboot
```

---

## ✅ Verify operation

```bash
systemctl list-timers --all | grep net-watch
journalctl -t net-watch -n 50 --no-pager
systemctl status watchdog-mux --no-pager
lsmod | grep -E 'iTCO|wdt'
```

### Manually reset the one-reboot lock

```bash
rm /var/lib/net-watch/rebooted.once
```

---

## ❌ Uninstall

```bash
./uninstall.sh
```

This disables the timer, removes all installed files, and optionally removes the state directory:

- `/usr/local/sbin/net-reboot-if-down.sh`
- `/etc/systemd/system/net-watch.{service,timer}`
- `/var/lib/net-watch/` *(prompted — contains fail counter and reboot flag)*

Hardware watchdog modules (`iTCO_wdt`) and `watchdog-mux` are left untouched.

---

## 🧾 Changelog

**v2.1.0 — 2026-05-31**
- Removed public IP targets (`1.1.1.1`, `8.8.8.8`) — watchdog now monitors local LAN only
- Added `ONLY_ONE_REBOOT` policy: host reboots at most once until flag is manually cleared
- Added carrier-grace window (10s extra wait when physical link is up but bridge recovery failed)
- Moved state directory from `/run/net-watch` (volatile) to `/var/lib/net-watch` (persistent across reboots)
- Auto-detect physical NIC from bridge slaves (`/sys/class/net/vmbr0/brif`) with fallback to `eno1`
- Improved log messages including detected physical interface name

**v2.0.0 — 2025-10-09**
- Added safe bridge-only recovery logic (no `eno1` down/up)
- Multi-target IP checks (no DNS dependency)
- Boot grace period and reboot rate limiting
- Cleaner installer/uninstaller with colored output
- Updated documentation and file layout table

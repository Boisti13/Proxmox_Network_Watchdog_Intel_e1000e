# Proxmox Network Watchdog (e1000e hang mitigation / safe bridge-only edition)

This package provides a **systemd-based watchdog** that monitors the Proxmox management network
(`vmbr0` → `eno1`) and performs **non-destructive recovery** if connectivity is lost.

Unlike the legacy version, this edition **does not bounce the physical NIC or reload the `e1000e` driver**.
Instead, it:
- Pings multiple IP targets (gateway + public addresses)
- Waits for consecutive failures before acting
- Cycles only the **bridge (`vmbr0`)** on failure
- Optionally reboots the host (rate-limited) if recovery fails
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

---

## ⚙️ What it does

1. Checks connectivity to several IPs (`192.168.178.1`, `1.1.1.1`, `8.8.8.8` by default)  
2. If all fail × 3 in a row → brings `vmbr0` **down/up** (does *not* touch `eno1`)  
3. If still unreachable → **reboots** the host (rate-limited, cooldown = 30 min)  
4. Loads `iTCO_wdt` for hardware watchdog protection (if supported)

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

---

## ❌ Uninstall

```bash
./uninstall.sh
```

This disables the timer and removes:
- `/usr/local/sbin/net-reboot-if-down.sh`
- `/etc/systemd/system/net-watch.{service,timer}`

Hardware watchdog modules (`iTCO_wdt`) and `watchdog-mux` are left untouched.

---

## 🧾 Changelog Highlights

**v2.0.0 — 2025-10-09**
- Added safe bridge-only recovery logic (no `eno1` down/up)
- Multi-target IP checks (no DNS dependency)
- Boot grace period and reboot rate limiting
- Cleaner installer/uninstaller with colored output
- Updated documentation and file layout table

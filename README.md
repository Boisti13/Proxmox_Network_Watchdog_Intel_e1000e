
# Proxmox Network Watchdog (e1000e hang mitigation)

This package adds a **systemd-based watchdog** that reboots a Proxmox host if management networking
(`vmbr0` → `eno1`) is down for two consecutive checks (default: every 2 minutes). It also includes
templates to **disable EEE + TSO/GSO/GRO** on the Intel e1000e NIC, and enables the **hardware watchdog**
(iTCO_wdt) via Proxmox's `watchdog-mux`.

Tested on: Lenovo M920q (Intel i219), Proxmox VE 8/9.

## What it installs
- `/usr/local/sbin/net-reboot-if-down.sh` – network check + auto-recovery + snapshot + reboot
- `net-watch.service` + `net-watch.timer` – run every 2 minutes
- enables `watchdog-mux` (if available) and loads `iTCO_wdt` on boot

## Quick install
```bash
# as root
./install.sh
```

This will:
1. Copy the script and systemd units into place
2. Load `iTCO_wdt` now and at boot
3. Start the timer and (if present) start `watchdog-mux`

> The watchdog reboots the host only if **two consecutive** checks fail. On the **first failure** it attempts
> to recover by bouncing `eno1` and reloading `e1000e`.

## Optional: NIC mitigations (recommended)
To reduce the chance of Intel e1000e "Hardware Unit Hang", apply these lines to your `/etc/network/interfaces`:

```ini
auto eno1
iface eno1 inet manual
    pre-up  /sbin/ethtool --set-eee eno1 eee off || true
    post-up /sbin/ethtool -K eno1 tso off gso off gro off || true
```

If you want a ready-to-paste example including your current bridge config,
see: `interfaces/eno1-vmbr0-mitigations.example`

Apply and reload:
```bash
ifreload -a
# or: systemctl restart networking
```

## Optional: Kernel parameters
If hangs persist, consider adding to `/etc/default/grub`:
```
pcie_aspm=off e1000e.SmartPowerDownEnable=0
```
then `update-grub` and reboot.

## Verify
```bash
systemctl list-timers --all | grep net-watch
journalctl -t net-watch -n 50 --no-pager
systemctl status watchdog-mux --no-pager
lsmod | grep -E 'iTCO|wdt'
```

## Uninstall
```bash
./uninstall.sh
```

This disables the timer and removes the installed files (does not modify your network config).
```


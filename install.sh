
#!/usr/bin/env bash
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Please run as root"; exit 1; }

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"

# Install script
install -m 0755 "$SRC_DIR/usr_local_sbin/net-reboot-if-down.sh" /usr/local/sbin/net-reboot-if-down.sh

# Install units
install -m 0644 "$SRC_DIR/systemd/net-watch.service" /etc/systemd/system/net-watch.service
install -m 0644 "$SRC_DIR/systemd/net-watch.timer"   /etc/systemd/system/net-watch.timer

# Enable HW watchdog module now and on boot
modprobe iTCO_vendor_support || true
modprobe iTCO_wdt || true
mkdir -p /etc/modules-load.d
grep -q '^iTCO_wdt$' /etc/modules-load.d/watchdog.conf 2>/dev/null || echo iTCO_wdt >> /etc/modules-load.d/watchdog.conf

# Start watchdog-mux if present (static unit)
systemctl start watchdog-mux 2>/dev/null || true

# Activate timer
systemctl daemon-reload
systemctl enable --now net-watch.timer

echo "Installed. Verify with:"
echo "  systemctl list-timers --all | grep net-watch"
echo "  journalctl -t net-watch -n 50 --no-pager"

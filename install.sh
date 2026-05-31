#!/usr/bin/env bash
# Proxmox Network Watchdog (safe bridge-only edition)
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "❌ Please run as root"; exit 1; }

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "🔧 Installing Proxmox Network Watchdog from: $SRC_DIR"

# --------------------------------------------------------------------
# 1. Install main script
# --------------------------------------------------------------------
if [[ -f "$SRC_DIR/scripts/net-reboot-if-down.sh" ]]; then
    install -m 0755 "$SRC_DIR/scripts/net-reboot-if-down.sh" /usr/local/sbin/net-reboot-if-down.sh
else
    echo "❌ Missing scripts/net-reboot-if-down.sh"; exit 1;
fi

# --------------------------------------------------------------------
# 2. Install systemd unit files
# --------------------------------------------------------------------
install -m 0644 "$SRC_DIR/systemd/net-watch.service" /etc/systemd/system/net-watch.service
install -m 0644 "$SRC_DIR/systemd/net-watch.timer"   /etc/systemd/system/net-watch.timer

# --------------------------------------------------------------------
# 3. Create persistent state directory
# --------------------------------------------------------------------
mkdir -p /var/lib/net-watch
echo "📁 State directory: /var/lib/net-watch"

# --------------------------------------------------------------------
# 4. Optional: enable hardware watchdog kernel module (Intel ICH/TCO)
# --------------------------------------------------------------------
echo "📟 Loading optional hardware watchdog (iTCO_wdt) modules..."
modprobe iTCO_vendor_support 2>/dev/null || true
modprobe iTCO_wdt 2>/dev/null || true

mkdir -p /etc/modules-load.d
grep -q '^iTCO_wdt$' /etc/modules-load.d/watchdog.conf 2>/dev/null \
  || echo iTCO_wdt >> /etc/modules-load.d/watchdog.conf

# --------------------------------------------------------------------
# 5. Activate the timer
# --------------------------------------------------------------------
echo "🚀 Enabling and starting net-watch.timer..."
systemctl daemon-reload
systemctl enable --now net-watch.timer

# --------------------------------------------------------------------
# 6. Summary
# --------------------------------------------------------------------
echo
echo "✅ Installation complete."
echo
echo "Check status with:"
echo "  systemctl list-timers --all | grep net-watch"
echo "  journalctl -t net-watch -n 20 --no-pager"
echo
echo "Main script : /usr/local/sbin/net-reboot-if-down.sh"
echo "Unit files  : /etc/systemd/system/net-watch.{service,timer}"
echo "State dir   : /var/lib/net-watch/"
echo
echo "Adjust ping targets and timing in:"
echo "  /usr/local/sbin/net-reboot-if-down.sh"
echo
echo "To reset the one-reboot lock after a recovery reboot:"
echo "  rm /var/lib/net-watch/rebooted.once"
echo

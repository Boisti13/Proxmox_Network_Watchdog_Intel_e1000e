#!/usr/bin/env bash
# Proxmox Network Watchdog (safe bridge-only edition) — Uninstaller
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "❌ Please run as root"; exit 1; }

echo "🧹 Uninstalling Proxmox Network Watchdog..."

# --------------------------------------------------------------------
# 1. Stop and disable timer/service if active
# --------------------------------------------------------------------
if systemctl list-timers --all | grep -q net-watch.timer; then
    echo "⏹ Stopping timer..."
    systemctl disable --now net-watch.timer || true
else
    echo "ℹ️  Timer not active."
fi

if systemctl list-unit-files | grep -q net-watch.service; then
    systemctl stop net-watch.service 2>/dev/null || true
fi

# --------------------------------------------------------------------
# 2. Remove installed files
# --------------------------------------------------------------------
echo "🗑 Removing systemd unit files..."
rm -f /etc/systemd/system/net-watch.service
rm -f /etc/systemd/system/net-watch.timer

echo "🗑 Removing main script..."
rm -f /usr/local/sbin/net-reboot-if-down.sh

# --------------------------------------------------------------------
# 3. Reload systemd manager configuration
# --------------------------------------------------------------------
systemctl daemon-reload
systemctl reset-failed 2>/dev/null || true

# --------------------------------------------------------------------
# 4. Optional cleanup hint for hardware watchdog modules
# --------------------------------------------------------------------
echo
echo "⚙️  Hardware watchdog modules (iTCO_wdt) were left untouched."
echo "    If you want to disable them manually:"
echo "      systemctl stop watchdog-mux 2>/dev/null || true"
echo "      rmmod iTCO_wdt iTCO_vendor_support 2>/dev/null || true"
echo

# --------------------------------------------------------------------
# 5. Confirmation
# --------------------------------------------------------------------
echo "✅ Net-watch uninstalled."
echo
echo "You can verify removal with:"
echo "  systemctl list-timers --all | grep net-watch || true"
echo "  ls /usr/local/sbin/net-reboot-if-down.sh 2>/dev/null || echo 'Script removed'"

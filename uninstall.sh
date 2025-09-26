
#!/usr/bin/env bash
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Please run as root"; exit 1; }

systemctl disable --now net-watch.timer || true
rm -f /etc/systemd/system/net-watch.service
rm -f /etc/systemd/system/net-watch.timer
systemctl daemon-reload

rm -f /usr/local/sbin/net-reboot-if-down.sh

echo "Removed net-watch. (Leaving watchdog-mux/modules as-is.)"

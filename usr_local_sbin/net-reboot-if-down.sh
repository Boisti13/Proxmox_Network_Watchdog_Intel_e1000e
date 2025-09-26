
#!/usr/bin/env bash
# /usr/local/sbin/net-reboot-if-down.sh
# Reboot the host if management networking is down twice in a row.
# - Checks carrier on the physical NIC (eno1)
# - Pings gateway (LAN) and a 2nd target (WAN) via vmbr0
# - On first failure: try to recover by bouncing NIC + reloading e1000e
# - On second consecutive failure: capture a snapshot and reboot

set -euo pipefail

# ---- settings ----
IF_BR="vmbr0"                 # Management bridge
IF_PHY="eno1"                 # Physical NIC under the bridge
GW="192.168.178.1"            # Primary check (LAN gateway)
ALT="1.1.1.1"                 # Secondary check (WAN; adjust or remove if undesired)
FAIL_STATE="/run/net-watch.failcount"
SNAP="/var/log/net-watch.last"
BOOT_COOLDOWN_SEC=180         # Ignore checks during first N seconds after boot
PING_COUNT=1
PING_TIMEOUT=2

log(){ logger -t net-watch "$*"; }

# ---- helpers ----
carrier_ok() {
  # Prefer sysfs carrier, fallback to ip link LOWER_UP
  if [[ -r "/sys/class/net/${IF_PHY}/carrier" ]]; then
    [[ "$(cat "/sys/class/net/${IF_PHY}/carrier")" == "1" ]] && return 0 || return 1
  fi
  ip link show "$IF_PHY" | grep -q "LOWER_UP"
}

ping_one() {
  local dst=$1
  ping -I "$IF_BR" -c "$PING_COUNT" -W "$PING_TIMEOUT" "$dst" >/dev/null 2>&1
}

ping_ok() {
  # Succeeds if either primary (GW) or secondary (ALT) responds
  ping_one "$GW" && return 0
  ping_one "$ALT" && return 0
  return 1
}

# ---- early exits / cooldown ----
UPTIME_S=$(cut -d' ' -f1 /proc/uptime | cut -d. -f1)
if (( UPTIME_S < BOOT_COOLDOWN_SEC )); then
  exit 0
fi

# ---- read current fail count ----
fails=$(cat "$FAIL_STATE" 2>/dev/null || echo 0)

# ---- main checks ----
if carrier_ok && ping_ok; then
  # all good → reset counter
  if (( fails > 0 )); then log "Recovery: link+ping OK, counter -> 0"; fi
  echo 0 > "$FAIL_STATE"

  # optional: log OK at most every 30 min
  OKSTAMP="/run/net-watch.okstamp"
  NOW=$(date +%s)
  if [[ -f "$OKSTAMP" ]]; then
    LAST=$(cat "$OKSTAMP" 2>/dev/null || echo 0)
  else
    LAST=0
  fi
  # 1800s = 30 min
  if (( NOW - LAST >= 1800 )); then
    log "OK: carrier+ping healthy on ${IF_PHY}/${IF_BR}"
    echo "$NOW" > "$OKSTAMP"
  fi
  exit 0
fi

# first failure → try recovery (bounce NIC + reload e1000e)
fails=$((fails+1))
echo "$fails" > "$FAIL_STATE"

if (( fails == 1 )); then
  log "FAIL(1): check failed (carrier_ok=$(carrier_ok && echo yes || echo no), ping_ok=$(ping_ok && echo yes || echo no)) – attempting recovery"
  ip link set "$IF_PHY" down || true
  modprobe -r e1000e || true
  modprobe e1000e || true
  ip link set "$IF_PHY" up || true
  sleep 5
  if carrier_ok && ping_ok; then
    log "Recovery successful after driver reload; counter -> 0"
    echo 0 > "$FAIL_STATE"
    exit 0
  fi
  log "Recovery unsuccessful; will reboot on next consecutive failure"
  exit 0
fi

# second consecutive failure → capture snapshot and reboot
# (we only reach here if fails >= 2)
{
  echo "=== $(date -Is) net-watch triggered reboot ==="
  echo "--- ip -br a ---"
  ip -br a || true
  echo "--- ip r ---"
  ip r || true
  echo "--- ethtool ${IF_PHY} ---"
  ethtool "$IF_PHY" 2>&1 || true
  echo "--- bridge fdb/addr (if available) ---"
  command -v bridge >/dev/null 2>&1 && bridge -c fdb show 2>&1 || true
  echo "--- recent kernel messages ---"
  journalctl -k -n 200 --no-pager 2>&1 || true
} > "$SNAP" 2>&1

log "FAIL($fails): network down (carrier_ok=$(carrier_ok && echo yes || echo no), ping_ok=no) – rebooting"
systemctl reboot

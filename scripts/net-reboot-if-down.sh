#!/bin/bash
set -euo pipefail

# --- Tunables ---
TARGETS=("192.168.178.1" "1.1.1.1" "8.8.8.8")  # gateway + public IPs
MAX_FAILS=3                  # consecutive failures before taking action
BOOT_GRACE_SEC=300           # ignore failures for first 5 minutes after boot
BRIDGE_NAME="vmbr0"
REBOOT_COOLDOWN_MIN=30       # minimum minutes between reboots
STATE_DIR="/run/net-watch"
LOGTAG="net-watch"

mkdir -p "$STATE_DIR"
FAIL_FILE="$STATE_DIR/fails"
LAST_REBOOT_FILE="$STATE_DIR/last_reboot"
BOOT_TIME=$(cut -d. -f1 /proc/uptime)
[[ -f $FAIL_FILE ]] || echo 0 > "$FAIL_FILE"

log() { logger -t "$LOGTAG" -- "$*"; }

ping_any() {
  for t in "${TARGETS[@]}"; do
    if ping -c1 -W2 "$t" >/dev/null 2>&1; then
      return 0
    fi
  done
  return 1
}

# Boot grace period
if (( BOOT_TIME < BOOT_GRACE_SEC )); then
  log "Boot grace ($BOOT_TIME/${BOOT_GRACE_SEC}s): skipping checks."
  exit 0
fi

if ping_any; then
  echo 0 > "$FAIL_FILE"
  log "OK: reachability restored."
  exit 0
fi

# record failure
fails=$(<"$FAIL_FILE")
fails=$((fails + 1))
echo "$fails" > "$FAIL_FILE"
log "FAIL $fails/${MAX_FAILS}: no reachability to ${TARGETS[*]} (bridge=$BRIDGE_NAME)."

if (( fails < MAX_FAILS )); then
  # Try light-touch refresh: clear ARP to gateway (if present)
  ip neigh flush to "${TARGETS[0]}" dev "$BRIDGE_NAME" 2>/dev/null || true
  exit 1
fi

# Action time: bounce the bridge once
log "Attempting recovery: cycling bridge $BRIDGE_NAME (NOT touching eno1)."
ip link set "$BRIDGE_NAME" down || true
sleep 3
ip link set "$BRIDGE_NAME" up || true
sleep 7

if ping_any; then
  echo 0 > "$FAIL_FILE"
  log "Recovery successful after bridge cycle."
  exit 0
fi

# Last resort: rate-limited reboot
now=$(date +%s)
last=0
[[ -f $LAST_REBOOT_FILE ]] && last=$(<"$LAST_REBOOT_FILE")
min_interval=$((REBOOT_COOLDOWN_MIN * 60))
if (( last > 0 && now - last < min_interval )); then
  log "Reboot suppressed: last reboot ${(now-last)}s ago (< ${REBOOT_COOLDOWN_MIN}m)."
  exit 2
fi

log "Recovery failed; REBOOTING host (rate-limited)."
date +%s > "$LAST_REBOOT_FILE"
reboot

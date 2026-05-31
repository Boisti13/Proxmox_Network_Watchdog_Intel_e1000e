#!/bin/bash
set -euo pipefail

# --- Tunables ---
TARGETS=("192.168.178.150")    # set to your local gateway / reachability target
MAX_FAILS=3                    # consecutive failures before taking action
BOOT_GRACE_SEC=300             # ignore failures for first 5 minutes after boot
BRIDGE_NAME="vmbr0"
# First physical slave of the bridge (fallback to eno1 if detection fails)
PHY_IFACE="$(ls /sys/class/net/${BRIDGE_NAME}/brif 2>/dev/null | head -n1 || echo eno1)"

REBOOT_COOLDOWN_MIN=30         # minimum minutes between reboots
ONLY_ONE_REBOOT=1              # reboot only once until flag is manually cleared

STATE_DIR="/var/lib/net-watch" # persists across reboot (required for ONLY_ONE_REBOOT)
LOGTAG="net-watch"

# --- State files ---
mkdir -p "$STATE_DIR"
FAIL_FILE="$STATE_DIR/fails"
LAST_REBOOT_FILE="$STATE_DIR/last_reboot"
REBOOTED_FLAG="$STATE_DIR/rebooted.once"
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

uptime_sec() { cut -d. -f1 /proc/uptime; }

# --- Boot grace period ---
BOOT_TIME=$(uptime_sec)
if (( BOOT_TIME < BOOT_GRACE_SEC )); then
  log "Boot grace (${BOOT_TIME}/${BOOT_GRACE_SEC}s): skipping checks."
  exit 0
fi

# --- Fast path: reachability OK ---
if ping_any; then
  echo 0 > "$FAIL_FILE"
  log "OK: reachability restored."
  exit 0
fi

# --- Record failure ---
fails=$(<"$FAIL_FILE")
fails=$((fails + 1))
echo "$fails" > "$FAIL_FILE"
log "FAIL $fails/${MAX_FAILS}: no reachability to ${TARGETS[*]} (bridge=$BRIDGE_NAME, iface=$PHY_IFACE)."

# --- Light-touch recovery while under threshold ---
if (( fails < MAX_FAILS )); then
  # Flush stale ARP entry for the target to avoid neighbor-cache blackholes
  ip neigh flush to "${TARGETS[0]}" dev "$BRIDGE_NAME" 2>/dev/null || true
  exit 1
fi

# --- Action: bounce the bridge once ---
log "Attempting recovery: cycling bridge $BRIDGE_NAME (NOT touching $PHY_IFACE)."
ip link set "$BRIDGE_NAME" down || true
sleep 3
ip link set "$BRIDGE_NAME" up || true
sleep 7

if ping_any; then
  echo 0 > "$FAIL_FILE"
  log "Recovery successful after bridge cycle."
  exit 0
fi

# --- Carrier-grace: link is electrically up (Powerline wake, etc.) ---
CARRIER_PATH="/sys/class/net/${PHY_IFACE}/carrier"
if [[ -r "$CARRIER_PATH" ]] && [[ "$(cat "$CARRIER_PATH")" == "1" ]]; then
  log "Carrier is UP on ${PHY_IFACE}; waiting 10s for transient recovery."
  sleep 10
  if ping_any; then
    echo 0 > "$FAIL_FILE"
    log "Recovery successful after carrier-grace."
    exit 0
  fi
fi

# --- Only-once policy ---
if (( ONLY_ONE_REBOOT == 1 )) && [[ -f "$REBOOTED_FLAG" ]]; then
  log "Recovery failed; reboot suppressed (ONLY_ONE_REBOOT active). Remove $REBOOTED_FLAG to allow another reboot."
  exit 2
fi

# --- Rate-limit by last reboot timestamp ---
now=$(date +%s)
last=0
[[ -f $LAST_REBOOT_FILE ]] && last=$(<"$LAST_REBOOT_FILE")
min_interval=$((REBOOT_COOLDOWN_MIN * 60))
if (( last > 0 && now - last < min_interval )); then
  log "Reboot suppressed: last reboot $((now-last))s ago (< ${REBOOT_COOLDOWN_MIN}m)."
  exit 2
fi

# --- Reboot ---
log "Recovery failed; REBOOTING host (rate-limited, only-once policy)."
date +%s > "$LAST_REBOOT_FILE"
if (( ONLY_ONE_REBOOT == 1 )); then : > "$REBOOTED_FLAG"; fi
reboot

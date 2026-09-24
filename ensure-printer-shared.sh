#!/bin/bash
# ensure-printer-shared.sh — keep the Brother queue shared for AirPrint.
#
# Why this exists
# ---------------
# macOS keeps resetting `printer-is-shared` to false on the Brother queue
# (observed three times, most recently after the macOS 27 update). When that
# happens CUPS accepts Validate-Job but rejects Create-Job with
# client-error-not-authorized, so an iPhone just shows "Waiting" forever and
# nothing explains why.
#
# This script re-asserts the flag. It must run as root (lpadmin needs admin
# rights), so it is installed as a LaunchDaemon rather than a LaunchAgent --
# see install-printer-share-daemon.sh.
#
# It is deliberately idempotent and quiet: it only calls lpadmin when the flag
# is actually false, so the periodic run costs nothing and the log only grows
# when something really changed.

set -uo pipefail

QUEUE="${PRINTER_QUEUE:-Brother_HL_2250DN_series}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# Read the current sharing state straight from CUPS.
current_shared() {
  lpoptions -p "$QUEUE" 2>/dev/null | tr ' ' '\n' \
    | awk -F= '/^printer-is-shared=/{print $2}'
}

# The queue may not exist yet right after boot while cupsd starts up.
for _ in $(seq 1 10); do
  if lpstat -p "$QUEUE" >/dev/null 2>&1; then
    break
  fi
  sleep 3
done

if ! lpstat -p "$QUEUE" >/dev/null 2>&1; then
  log "queue $QUEUE not found - nothing to do"
  exit 0
fi

shared="$(current_shared)"

if [ "$shared" = "true" ]; then
  # Nothing to do. Stay silent so the log stays meaningful.
  exit 0
fi

log "printer-is-shared=$shared on $QUEUE - re-asserting true (AirPrint would be broken)"
if lpadmin -p "$QUEUE" -o printer-is-shared=true 2>&1; then
  log "restored printer-is-shared=true on $QUEUE"
else
  log "ERROR: lpadmin failed to restore sharing on $QUEUE"
  exit 1
fi

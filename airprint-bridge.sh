#!/bin/bash
# airprint-bridge.sh — advertise the shared CUPS Brother queue as an AirPrint
# printer by registering a Bonjour _ipp._tcp service WITH the "_universal"
# subtype and a URF key. macOS/CUPS does the actual rasterization; this just
# adds the AirPrint flags that Apple's cupsd omits for Generic-PPD queues.
#
# Runs in the foreground (dns-sd -R holds the registration open), so it is
# meant to be supervised by launchd with KeepAlive.

set -uo pipefail

QUEUE="Brother_HL_2250DN_series"
NAME="Brother HL-2250DN (AirPrint)"
PORT=631
UUID="ac200b95-e304-35bf-61ce-50f01a1f877b"

# Pull the queue's UUID live if available (falls back to the constant above).
live_uuid="$(lpstat -l -p "$QUEUE" 2>/dev/null | awk -F= '/uuid/{print $2}' | tr -d ' ')"
[ -n "$live_uuid" ] && UUID="${live_uuid#urn:uuid:}"

echo "[$(date)] Registering AirPrint bridge for $QUEUE as \"$NAME\" ..."

# -R registers a service. Appending ",_universal" puts it in the AirPrint
# browse domain that iOS/iPadOS scans. This call blocks until killed.
#
# NOTE: do NOT advertise a "TLS=" key here. This is a plaintext _ipp service on
# port 631 with no _ipps endpoint; advertising TLS makes iOS attempt the job
# over encryption that doesn't exist, and cupsd rejects Create-Job with
# client-error-not-authorized (Validate-Job still passes — confusing to debug).
exec dns-sd -R "$NAME" "_ipp._tcp,_universal" local "$PORT" \
  txtvers=1 \
  qtotal=1 \
  rp="printers/$QUEUE" \
  ty="Brother HL-2250DN series" \
  product="(Brother HL-2250DN series)" \
  note="Mac mini" \
  adminurl="http://localhost:631/printers/$QUEUE" \
  priority=0 \
  pdl="application/pdf,image/urf,image/pwg-raster,image/jpeg" \
  URF="W8,SRGB24,CP1,RS300,DM1,IS1,MT1-3-4-5-8,OB10,PQ4,V1.4" \
  UUID="$UUID" \
  Color=F \
  Duplex=T \
  Scan=F \
  kind=document \
  PaperMax=legal-A4 \
  mopria-certified=1.3

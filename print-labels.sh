#!/bin/bash
# print-labels.sh — print shipping labels WITHOUT the macOS print dialog.
#
# Uses CUPS `lp`:
#   * label-sized PDFs (Warenpost / Kleinpaket) -> inateck label printer, 100x200 mm
#   * A4 PDFs           (US / DHL Paket)         -> Brother printer, A4
#
# Usage:
#   ./print-labels.sh --list                       # show printers + their PageSize options
#   ./print-labels.sh label FILE.pdf [FILE2.pdf …] # print on the inateck (label) printer
#   ./print-labels.sh a4    FILE.pdf [FILE2.pdf …] # print on the Brother (A4) printer
#
# If the label comes out the wrong size, run `--list`, find the exact 100x200
# PageSize name, and set it, e.g.:
#   LABEL_MEDIA="w283h567" ./print-labels.sh label FILE.pdf

set -euo pipefail

# --- auto-detect the printer queue names from CUPS ---
INATECK_QUEUE="$(lpstat -p 2>/dev/null | awk '/^printer/{print $2}' | grep -i -m1 -E 'inateck|PRO2001' || true)"
BROTHER_QUEUE="$(lpstat -p 2>/dev/null | awk '/^printer/{print $2}' | grep -i -m1 -E 'brother|HL.?2250' || true)"

# Label media size. Override with the LABEL_MEDIA env var if the name differs (see --list).
LABEL_MEDIA="${LABEL_MEDIA:-Custom.100x200mm}"

list() {
  echo "== Printers detected by CUPS =="
  lpstat -p || true
  echo
  echo "inateck (label) queue : ${INATECK_QUEUE:-NOT FOUND}"
  echo "Brother (A4)    queue : ${BROTHER_QUEUE:-NOT FOUND}"
  if [ -n "${INATECK_QUEUE:-}" ]; then
    echo
    echo "== PageSize choices for $INATECK_QUEUE (pick the 100x200 one for LABEL_MEDIA) =="
    lpoptions -p "$INATECK_QUEUE" -l 2>/dev/null | tr '/' '\n' | grep -i pagesize -A1 || \
      lpoptions -p "$INATECK_QUEUE" -l 2>/dev/null | grep -i pagesize || true
  fi
}

print_to() {
  local queue="$1" media="$2"; shift 2
  if [ -z "$queue" ]; then
    echo "ERROR: printer queue not found. Run:  $0 --list" >&2; exit 1
  fi
  if [ "$#" -eq 0 ]; then
    echo "ERROR: no PDF files given." >&2; exit 1
  fi
  for f in "$@"; do
    if [ ! -f "$f" ]; then echo "SKIP (not found): $f" >&2; continue; fi
    echo "Printing: $f  ->  $queue  (media=$media)"
    lp -d "$queue" -o media="$media" -o fit-to-page "$f"
  done
}

case "${1:-}" in
  --list|list) list ;;
  label) shift; print_to "$INATECK_QUEUE" "$LABEL_MEDIA" "$@" ;;
  a4)    shift; print_to "$BROTHER_QUEUE" "A4" "$@" ;;
  *) echo "Usage: $0 --list | label FILE.pdf … | a4 FILE.pdf …" >&2; exit 1 ;;
esac

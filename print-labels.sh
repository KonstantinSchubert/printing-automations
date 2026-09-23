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
#
# LABELS DO NOT USE THE INATECK CUPS DRIVER.
# Inateck only ships an x86_64 filter; macOS 27 dropped Rosetta support for it,
# so CUPS fails with com.apple.badarch-error. Instead we convert the PDF to
# TSPL ourselves (pdf-to-tspl.py, native arm64) and send it with `lp -o raw`,
# which bypasses the filter chain entirely. Set LABEL_USE_DRIVER=1 to fall back
# to the old driver path.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TSPL_SCRIPT="$SCRIPT_DIR/pdf-to-tspl.py"

# launchd runs the watcher with a minimal PATH that omits ~/.local/bin, so
# resolve `uv` explicitly (same reasoning as in watch-and-print.sh).
UV="$(command -v uv || true)"
[ -z "$UV" ] && [ -x "$HOME/.local/bin/uv" ] && UV="$HOME/.local/bin/uv"
[ -z "$UV" ] && UV="uv"

# --- auto-detect the printer queue names from CUPS ---
INATECK_QUEUE="$(lpstat -p 2>/dev/null | awk '/^printer/{print $2}' | grep -i -m1 -E 'inateck|PRO2001' || true)"
BROTHER_QUEUE="$(lpstat -p 2>/dev/null | awk '/^printer/{print $2}' | grep -i -m1 -E 'brother|HL.?2250' || true)"

# Label media size. Override with the LABEL_MEDIA env var if the name differs (see --list).
LABEL_MEDIA="${LABEL_MEDIA:-Custom.100x200mm}"
# Physical label stock in mm, passed to pdf-to-tspl.py as WxH.
LABEL_SIZE_MM="${LABEL_SIZE_MM:-100x200}"

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

# Print labels by converting to TSPL ourselves and sending raw, so the broken
# x86_64 Inateck filter is never invoked. See the header comment.
print_labels_tspl() {
  local queue="$INATECK_QUEUE"
  if [ -z "$queue" ]; then
    echo "ERROR: label printer queue not found. Run:  $0 --list" >&2; exit 1
  fi
  if [ "$#" -eq 0 ]; then
    echo "ERROR: no PDF files given." >&2; exit 1
  fi
  local tmp
  tmp="$(mktemp -t tspl)" || { echo "ERROR: mktemp failed" >&2; exit 1; }
  trap 'rm -f "$tmp"' RETURN
  for f in "$@"; do
    if [ ! -f "$f" ]; then echo "SKIP (not found): $f" >&2; continue; fi
    echo "Printing: $f  ->  $queue  (TSPL raw, ${LABEL_SIZE_MM}mm)"
    "$UV" run --quiet "$TSPL_SCRIPT" "$f" "$tmp" --size "$LABEL_SIZE_MM"
    lp -d "$queue" -o raw "$tmp"
  done
}

case "${1:-}" in
  --list|list) list ;;
  label)
    shift
    if [ -n "${LABEL_USE_DRIVER:-}" ]; then
      print_to "$INATECK_QUEUE" "$LABEL_MEDIA" "$@"
    else
      print_labels_tspl "$@"
    fi
    ;;
  a4)    shift; print_to "$BROTHER_QUEUE" "A4" "$@" ;;
  *) echo "Usage: $0 --list | label FILE.pdf … | a4 FILE.pdf …" >&2; exit 1 ;;
esac

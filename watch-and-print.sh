#!/bin/bash
# watch-and-print.sh — poll ~/printing/a4 and ~/printing/labels for new PDFs,
# print them via print-labels.sh, then move them to a "done" subfolder.
# Plain-bash polling: no external dependencies (no fswatch needed).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PRINT_SCRIPT="$SCRIPT_DIR/print-labels.sh"
SPLIT_SCRIPT="$SCRIPT_DIR/split-pdf.py"

# launchd runs us with a minimal PATH that omits ~/.local/bin, so `uv` (used by
# the splitter) isn't found. Resolve it explicitly: prefer PATH, else the
# standard install location.
UV="$(command -v uv || true)"
[ -z "$UV" ] && [ -x "$HOME/.local/bin/uv" ] && UV="$HOME/.local/bin/uv"
[ -z "$UV" ] && UV="uv"  # last resort; split path will error+log if truly missing
A4_DIR="$SCRIPT_DIR/a4"
LABELS_DIR="$SCRIPT_DIR/labels"
SPLIT_DIR="$SCRIPT_DIR/split-by-size"
A4_DONE="$A4_DIR/done"
LABELS_DONE="$LABELS_DIR/done"
SPLIT_DONE="$SPLIT_DIR/done"
A4_FAILED="$A4_DIR/failed"
LABELS_FAILED="$LABELS_DIR/failed"
SPLIT_FAILED="$SPLIT_DIR/failed"
POLL=3

DONE_RETENTION_DAYS=7
MAX_ATTEMPTS=3   # quarantine a file to failed/ after this many failures

mkdir -p "$A4_DONE" "$LABELS_DONE" "$SPLIT_DONE" \
         "$A4_FAILED" "$LABELS_FAILED" "$SPLIT_FAILED"

# Per-file failure count is kept in a sidecar "<file>.attempts" next to the PDF.
# A plain file (not an associative array) keeps this compatible with the
# macOS system bash 3.2 and survives watcher restarts. The *.pdf globs below
# never match these sidecars.
clear_attempts() { rm -f "$1.attempts"; }

# Delete PDFs that have sat in a done/ folder for >= DONE_RETENTION_DAYS.
# Called whenever a file is moved into that folder.
cleanup_done() {
  local done="$1"
  while IFS= read -r old; do
    rm -f "$old" && echo "[$(date)] Pruned (>= ${DONE_RETENTION_DAYS}d): $old"
  done < <(find "$done" -type f -name '*.pdf' -mtime +"$DONE_RETENTION_DAYS" 2>/dev/null)
}

# Record a failed attempt for a file. After MAX_ATTEMPTS, move it to failed/
# so it can't spin in the retry loop forever. Returns 0 if quarantined.
record_failure() {
  local f="$1" failed="$2" verb="$3"
  local prev n
  prev=$(cat "$f.attempts" 2>/dev/null); [ -n "$prev" ] || prev=0
  n=$((prev + 1))
  if [ "$n" -ge "$MAX_ATTEMPTS" ]; then
    mv "$f" "$failed/" && echo "[$(date)] GIVING UP after $n attempts, quarantined -> $failed/$(basename "$f")"
    clear_attempts "$f"
    return 0
  fi
  echo "$n" > "$f.attempts"
  echo "[$(date)] ERROR $verb $f (attempt $n/$MAX_ATTEMPTS, left in place for retry)"
  return 1
}

process_dir() {
  local dir="$1" kind="$2" done="$3" failed="$4"
  shopt -s nullglob nocaseglob
  for f in "$dir"/*.pdf; do
    [ -f "$f" ] || continue
    echo "[$(date)] Printing $kind: $f"
    if bash "$PRINT_SCRIPT" "$kind" "$f"; then
      mv "$f" "$done/" && echo "[$(date)] Done -> $done/$(basename "$f")"
      clear_attempts "$f"
      cleanup_done "$done"
    else
      record_failure "$f" "$failed" printing
    fi
  done
  shopt -u nullglob nocaseglob
}

process_split_dir() {
  shopt -s nullglob nocaseglob
  for f in "$SPLIT_DIR"/*.pdf; do
    [ -f "$f" ] || continue
    echo "[$(date)] Splitting by size: $f"
    # Splits pages into A4/label groups and drops each into the
    # a4/ and labels/ folders, which the loops below then print.
    if "$UV" run --quiet "$SPLIT_SCRIPT" "$f" "$A4_DIR" "$LABELS_DIR"; then
      mv "$f" "$SPLIT_DONE/" && echo "[$(date)] Split done -> $SPLIT_DONE/$(basename "$f")"
      clear_attempts "$f"
      cleanup_done "$SPLIT_DONE"
    else
      record_failure "$f" "$SPLIT_FAILED" splitting
    fi
  done
  shopt -u nullglob nocaseglob
}

echo "[$(date)] Polling $A4_DIR, $LABELS_DIR and $SPLIT_DIR every ${POLL}s (plain-bash watcher) ..."
while true; do
  process_split_dir
  process_dir "$A4_DIR" a4 "$A4_DONE" "$A4_FAILED"
  process_dir "$LABELS_DIR" label "$LABELS_DONE" "$LABELS_FAILED"
  sleep "$POLL"
done

#!/bin/bash
# watch-and-print.sh — poll ~/printing/a4 and ~/printing/labels for new PDFs,
# print them via print-labels.sh, then move them to a "done" subfolder.
# Plain-bash polling: no external dependencies (no fswatch needed).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PRINT_SCRIPT="$SCRIPT_DIR/print-labels.sh"
SPLIT_SCRIPT="$SCRIPT_DIR/split-pdf.py"
A4_DIR="$SCRIPT_DIR/a4"
LABELS_DIR="$SCRIPT_DIR/labels"
SPLIT_DIR="$SCRIPT_DIR/split-by-size"
A4_DONE="$A4_DIR/done"
LABELS_DONE="$LABELS_DIR/done"
SPLIT_DONE="$SPLIT_DIR/done"
POLL=3

DONE_RETENTION_DAYS=7

mkdir -p "$A4_DONE" "$LABELS_DONE" "$SPLIT_DONE"

# Delete PDFs that have sat in a done/ folder for >= DONE_RETENTION_DAYS.
# Called whenever a file is moved into that folder.
cleanup_done() {
  local done="$1"
  while IFS= read -r old; do
    rm -f "$old" && echo "[$(date)] Pruned (>= ${DONE_RETENTION_DAYS}d): $old"
  done < <(find "$done" -type f -name '*.pdf' -mtime +"$DONE_RETENTION_DAYS" 2>/dev/null)
}

process_dir() {
  local dir="$1" kind="$2" done="$3"
  shopt -s nullglob nocaseglob
  for f in "$dir"/*.pdf; do
    [ -f "$f" ] || continue
    echo "[$(date)] Printing $kind: $f"
    if bash "$PRINT_SCRIPT" "$kind" "$f"; then
      mv "$f" "$done/" && echo "[$(date)] Done -> $done/$(basename "$f")"
      cleanup_done "$done"
    else
      echo "[$(date)] ERROR printing $f (left in place for retry)"
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
    if uv run --quiet "$SPLIT_SCRIPT" "$f" "$A4_DIR" "$LABELS_DIR"; then
      mv "$f" "$SPLIT_DONE/" && echo "[$(date)] Split done -> $SPLIT_DONE/$(basename "$f")"
      cleanup_done "$SPLIT_DONE"
    else
      echo "[$(date)] ERROR splitting $f (left in place for retry)"
    fi
  done
  shopt -u nullglob nocaseglob
}

echo "[$(date)] Polling $A4_DIR, $LABELS_DIR and $SPLIT_DIR every ${POLL}s (plain-bash watcher) ..."
while true; do
  process_split_dir
  process_dir "$A4_DIR" a4 "$A4_DONE"
  process_dir "$LABELS_DIR" label "$LABELS_DONE"
  sleep "$POLL"
done

#!/usr/bin/env -S uv run --quiet --script
# /// script
# requires-python = ">=3.9"
# dependencies = ["pypdf"]
# ///
"""Split a PDF by page size into an A4 group and a label group.

Pages are classified by their short edge in millimetres:
  - A4 short edge  = 210 mm
  - Label (100x200 mm) short edge = 100 mm
A short edge wider than 150 mm is A4, otherwise a label.

Usage: split-pdf.py SOURCE.pdf A4_OUT_DIR LABELS_OUT_DIR

Writes "<stem>.pdf" (A4 pages) into A4_OUT_DIR and "<stem>.pdf"
(label pages) into LABELS_OUT_DIR, but only for groups that have pages.
Prints a short summary to stdout.
"""
import os
import sys
from pypdf import PdfReader, PdfWriter

PT_PER_MM = 72.0 / 25.4
THRESHOLD_MM = 150.0


def classify(page) -> str:
    box = page.mediabox
    short_mm = min(float(box.width), float(box.height)) / PT_PER_MM
    return "a4" if short_mm > THRESHOLD_MM else "label"


def write_group(reader, indices, out_path) -> None:
    writer = PdfWriter()
    for i in indices:
        writer.add_page(reader.pages[i])
    # Write atomically so the watcher never sees a half-written file.
    tmp = out_path + ".part"
    with open(tmp, "wb") as fh:
        writer.write(fh)
    os.replace(tmp, out_path)


def main() -> int:
    if len(sys.argv) != 4:
        print("usage: split-pdf.py SOURCE.pdf A4_OUT_DIR LABELS_OUT_DIR",
              file=sys.stderr)
        return 2
    src, a4_dir, labels_dir = sys.argv[1], sys.argv[2], sys.argv[3]
    reader = PdfReader(src)

    groups = {"a4": [], "label": []}
    for i, page in enumerate(reader.pages):
        groups[classify(page)].append(i)

    stem = os.path.splitext(os.path.basename(src))[0]
    out_dirs = {"a4": a4_dir, "label": labels_dir}
    for kind, indices in groups.items():
        if not indices:
            continue
        out_path = os.path.join(out_dirs[kind], f"{stem}.pdf")
        write_group(reader, indices, out_path)
        print(f"{kind}: {len(indices)} page(s) -> {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
# split-by-size.py IN.pdf A4_OUT_DIR LABELS_OUT_DIR
# Splits a mixed shipping PDF (e.g. US DHL Paket = A4 customs page(s) + label page(s))
# by page size: A4-ish pages -> A4_OUT_DIR/<base>-a4.pdf, label pages -> LABELS_OUT_DIR/<base>-label.pdf
# Classification: page short side > 150 mm => A4; otherwise => label.
import sys, os
from pypdf import PdfReader, PdfWriter

inp, a4_dir, lbl_dir = sys.argv[1], sys.argv[2], sys.argv[3]
base = os.path.splitext(os.path.basename(inp))[0]
reader = PdfReader(inp)
a4w, lblw = PdfWriter(), PdfWriter()
na4 = nlbl = 0
for page in reader.pages:
    w_mm = float(page.mediabox.width)  / 72 * 25.4
    h_mm = float(page.mediabox.height) / 72 * 25.4
    short = min(w_mm, h_mm)
    if short > 150:   # A4 short side ~210mm; label short side ~100mm
        a4w.add_page(page); na4 += 1
    else:
        lblw.add_page(page); nlbl += 1
if na4:
    out = os.path.join(a4_dir, f"{base}-a4.pdf")
    with open(out, "wb") as f: a4w.write(f)
    print(f"A4 pages: {na4} -> {out}")
if nlbl:
    out = os.path.join(lbl_dir, f"{base}-label.pdf")
    with open(out, "wb") as f: lblw.write(f)
    print(f"label pages: {nlbl} -> {out}")
if not na4 and not nlbl:
    print("no pages found", file=sys.stderr); sys.exit(1)

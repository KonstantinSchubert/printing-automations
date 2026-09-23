#!/usr/bin/env -S uv run --quiet --script
# /// script
# requires-python = ">=3.9"
# dependencies = ["pypdfium2", "pillow"]
# ///
"""Convert a label PDF into raw TSPL for the Inateck PR02001.

Why this exists
---------------
Inateck ships an x86_64-only CUPS filter (/Library/Printers/INATECK/Filter/
rastertolabel). On Apple Silicon that only ran under Rosetta, and macOS 27
dropped it -> CUPS reports com.apple.badarch-error and nothing prints.

That filter is a modified copy of CUPS' own rastertolabel.c with TSPL (TSC
Printer Language) support bolted on. We reimplement just the TSPL part here
in native Python, so no Intel binary is involved at all.

The emitted sequence mirrors what the original filter produced:

    SIZE <w> mm,<h> mm
    GAP 3 mm,0 mm
    DIRECTION 0,0
    REFERENCE 0,0
    DENSITY <n>
    SPEED <n>
    CLS
    BITMAP 0,0,<width_bytes>,<height_dots>,1,<packed 1bpp data>
    PRINT 1,1

TSPL bitmap bit convention is inverted: bit 0 = burn a dot (black),
bit 1 = leave blank (white).

Usage:
    pdf-to-tspl.py IN.pdf OUT.bin [--density N] [--speed N] [--dpi N]
"""

import argparse
import sys

import pypdfium2 as pdfium
from PIL import Image

DPI = 203          # PR02001 print head resolution
PT_PER_INCH = 72.0
MM_PER_INCH = 25.4


def render_page(page, dpi: int) -> Image.Image:
    """Render one PDF page to a 1-bit PIL image at the given dpi."""
    scale = dpi / PT_PER_INCH
    bitmap = page.render(scale=scale, grayscale=True)
    img = bitmap.to_pil().convert("L")
    # Threshold to pure black/white. point() keeps this dependency-light
    # (no numpy); 128 is a sane midpoint for label artwork.
    return img.point(lambda p: 255 if p >= 128 else 0, mode="1")


def pack_tspl_bitmap(img: Image.Image) -> tuple[bytes, int, int]:
    """Pack a 1-bit image into TSPL BITMAP bytes.

    Returns (data, width_bytes, height_dots). The image is padded on the
    right to a whole byte; padding is white so it never prints.
    """
    width, height = img.size
    width_bytes = (width + 7) // 8
    padded_width = width_bytes * 8

    if padded_width != width:
        padded = Image.new("1", (padded_width, height), 1)  # 1 = white
        padded.paste(img, (0, 0))
        img = padded

    # Pillow mode "1" packs 8 px per byte already, MSB first, where a set
    # bit means white. TSPL wants 0 = black, 1 = white -- the same
    # convention -- so the raw buffer can be used directly.
    data = img.tobytes()
    expected = width_bytes * height
    if len(data) != expected:
        raise RuntimeError(f"packed {len(data)} bytes, expected {expected}")
    return data, width_bytes, height


def parse_size(text: str) -> tuple[int, int]:
    """Parse a 'WxH' label size in mm."""
    w, _, h = text.lower().partition("x")
    return int(w), int(h)


def build_tspl(
    pdf_path: str,
    density: int,
    speed: int,
    dpi: int,
    size_mm: "tuple[int, int] | None" = None,
) -> bytes:
    pdf = pdfium.PdfDocument(pdf_path)
    out = bytearray()

    for index in range(len(pdf)):
        page = pdf[index]
        img = render_page(page, dpi)
        data, width_bytes, height = pack_tspl_bitmap(img)

        # SIZE must describe the physical label stock, not the artwork. The
        # PDF is often marginally smaller (e.g. 99 mm art on a 100 mm roll),
        # so allow pinning it explicitly and fall back to the page box.
        if size_mm:
            w_mm, h_mm = size_mm
        else:
            w_mm = round(page.get_width() / PT_PER_INCH * MM_PER_INCH)
            h_mm = round(page.get_height() / PT_PER_INCH * MM_PER_INCH)

        cmds = (
            f"SIZE {w_mm} mm,{h_mm} mm\r\n"
            f"GAP 3 mm,0 mm\r\n"
            f"DIRECTION 0,0\r\n"
            f"REFERENCE 0,0\r\n"
            f"DENSITY {density}\r\n"
            f"SPEED {speed}\r\n"
            f"CLS\r\n"
            f"BITMAP 0,0,{width_bytes},{height},1,"
        )
        out += cmds.encode("ascii")
        out += data
        out += b"\r\nPRINT 1,1\r\n"

        print(
            f"page {index + 1}: {img.size[0]}x{height} dots "
            f"({w_mm}x{h_mm} mm), {len(data)} bytes bitmap",
            file=sys.stderr,
        )

    return bytes(out)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("pdf")
    ap.add_argument("out")
    ap.add_argument("--density", type=int, default=8, help="burn darkness 0-15")
    ap.add_argument("--speed", type=int, default=4, help="print speed in ips")
    ap.add_argument("--dpi", type=int, default=DPI)
    ap.add_argument(
        "--size",
        help="physical label size in mm as WxH (e.g. 100x200); "
        "defaults to the PDF page size",
    )
    args = ap.parse_args()

    size_mm = parse_size(args.size) if args.size else None
    payload = build_tspl(args.pdf, args.density, args.speed, args.dpi, size_mm)
    with open(args.out, "wb") as fh:
        fh.write(payload)
    print(f"wrote {len(payload)} bytes -> {args.out}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

# Printing

Drop a PDF into a folder and it prints automatically — no print dialog.

A background watcher (`watch-and-print.sh`, started at login via launchd) polls
the folders below every 3 seconds.

## Folders

| Drop a PDF here     | What happens                                                        |
|---------------------|--------------------------------------------------------------------|
| `a4/`               | Prints on the **Brother** A4 printer                               |
| `labels/`           | Prints on the **Inateck** label printer (100×200 mm)              |
| `split-by-size/`    | Splits the PDF by page size, then routes each part to `a4/` and `labels/` |

After a file is handled it moves into a `done/` subfolder of wherever it landed
(`a4/done/`, `labels/done/`, `split-by-size/done/`).

### split-by-size

Each page is classified by its **short edge**:

- short edge wider than **150 mm** → A4 (handles portrait *and* landscape)
- otherwise → label

A PDF with mixed page sizes is separated into two PDFs (one A4, one label); a
single-size PDF just produces one. The split files are dropped into `a4/` and
`labels/`, where the watcher prints them on the next pass.

## Manual printing

Bypass the watcher and print directly:

```sh
./print-labels.sh --list                 # show printers + page sizes
./print-labels.sh a4    FILE.pdf [...]    # print on the Brother (A4)
./print-labels.sh label FILE.pdf [...]    # print on the Inateck (label)
```

If a label comes out the wrong size, run `--list`, find the exact 100×200 mm
`PageSize` name, and set it:

```sh
LABEL_MEDIA="w283h567" ./print-labels.sh label FILE.pdf
```

## Files

- `watch-and-print.sh` — the folder watcher (plain-bash polling, no deps)
- `print-labels.sh` — sends a PDF to the right CUPS queue via `lp`
- `split-pdf.py` — splits a PDF by page size; run via `uv` with `pypdf`
- `pdf-to-tspl.py` — converts a label PDF to raw TSPL (see below)
- `airprint-bridge.sh` — advertises the Brother as an AirPrint printer (see below)
- `watcher.log` — activity log (`tail -f watcher.log` to watch live)
- `~/Library/LaunchAgents/com.konstantinschubert.print-watcher.plist` — runs the
  watcher at login and restarts it if it crashes
- `~/Library/LaunchAgents/com.konstantinschubert.airprint-bridge.plist` — runs the
  AirPrint bridge at login

## Label printer: no Inateck driver, no Rosetta

Inateck only ever shipped an **x86_64** CUPS filter
(`/Library/Printers/INATECK/Filter/rastertolabel`, 2020). On Apple Silicon that
ran under Rosetta; macOS 27 dropped it, so CUPS fails with
`com.apple.badarch-error` and nothing prints.

That filter turned out to be a modified copy of CUPS' own `rastertolabel.c`
with **TSPL** (TSC Printer Language) support added. So instead of depending on
an Intel binary, `pdf-to-tspl.py` generates the TSPL itself — natively — and
`print-labels.sh` sends it with `lp -o raw`, which bypasses the CUPS filter
chain completely. Nothing Intel is involved, and it survives OS updates.

The emitted sequence (extracted from the original filter):

```
SIZE <w> mm,<h> mm / GAP 3 mm,0 mm / DIRECTION 0,0 / REFERENCE 0,0
DENSITY 8 / SPEED 4 / CLS
BITMAP 0,0,<width_bytes>,<height_dots>,1,<packed 1bpp data>
PRINT 1,1
```

Tuning knobs (env vars for `print-labels.sh`):

- `LABEL_SIZE_MM` — physical stock size, default `100x200`. The PDF artwork is
  often slightly smaller (99 mm), so this is pinned to the roll, not the page.
- `LABEL_USE_DRIVER=1` — fall back to the old Inateck driver path (only works
  if Rosetta is installed).

Darkness/speed default to `DENSITY 8` / `SPEED 4`; change via `--density` /
`--speed` on `pdf-to-tspl.py`.

## AirPrint (Brother printer on iPhone/iPad)

The Brother HL-2250DN has no AirPrint firmware, so the Mac shares it. Two pieces:

1. The CUPS queue is shared: global sharing on (`cupsctl` → `_share_printers=1`)
   plus `sudo lpadmin -p Brother_HL_2250DN_series -o printer-is-shared=true`.
2. `airprint-bridge.sh` registers a Bonjour `_ipp._tcp` service **with the
   `_universal` AirPrint subtype and a `URF` key** — the flags Apple's `cupsd`
   omits for a Generic-PCL queue. Your Mac does the actual rasterization.

The Mac must be **awake** for iOS devices to print through it (it's the
rasterizer). Disable sleep / enable wake-for-network if you want it always
reachable.

Verify it's being advertised:

```sh
dns-sd -B _universal._sub._ipp._tcp   # should list "Brother HL-2250DN (AirPrint)"
```

## Managing the watcher

```sh
# stop
launchctl unload ~/Library/LaunchAgents/com.konstantinschubert.print-watcher.plist
# start
launchctl load   ~/Library/LaunchAgents/com.konstantinschubert.print-watcher.plist
# restart after editing watch-and-print.sh (it's a long-running loop)
launchctl unload ~/Library/LaunchAgents/com.konstantinschubert.print-watcher.plist && \
launchctl load   ~/Library/LaunchAgents/com.konstantinschubert.print-watcher.plist
```

## Notes

- Only `*.pdf` files are handled (case-insensitive).
- If a print/split command fails the file is left in place and retried on the
  next poll. After `MAX_ATTEMPTS` (default 3) it's moved to a `failed/` subfolder
  so a bad PDF can't spin in the retry loop forever. Retry counts are kept in
  a `<file>.attempts` sidecar and cleared on success/quarantine.
- `split-by-size` writes its output atomically (via a `.part` temp file), so the
  watcher never grabs a half-written PDF.
- The watcher runs under the macOS system bash (3.2), so the script avoids
  bash-4 features like associative arrays.

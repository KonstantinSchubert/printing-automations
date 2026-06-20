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
- `watcher.log` — activity log (`tail -f watcher.log` to watch live)
- `~/Library/LaunchAgents/com.konstantinschubert.print-watcher.plist` — runs the
  watcher at login and restarts it if it crashes

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
- If a print command fails the file is left in place and retried on the next poll.
- `split-by-size` writes its output atomically (via a `.part` temp file), so the
  watcher never grabs a half-written PDF.

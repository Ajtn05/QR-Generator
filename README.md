# QR Generator

A small native macOS app: pick a payload type, fill it in, get a code out.

```
./build.sh                    # -> build/QR Generator.app
open "build/QR Generator.app"
```

Five Swift files in `Sources/`, compiled straight into an app bundle by
`build.sh` — no Xcode project. Requires the Xcode command line tools.

## Layout

A three-column window: payload types in the sidebar, the form for the
selected type in the middle, live preview and export options on the right.
The icon is drawn in code on the standard 1024pt macOS icon grid
(`Tools/MakeIcon.swift`) and checked in at `Resources/AppIcon.icns`;
regenerate it with `./build.sh --icon`.

## Payload types

Link · Plain Text · Wi-Fi Network · Contact Card (vCard) · Email · SMS ·
Phone · Location · Calendar Event

Links typed without a scheme are saved as `https://`. Wi-Fi and vCard
fields are escaped per spec, so semicolons and commas in a network name or
company name survive the round trip.

## Export

- **Formats** — PNG (raster), PDF and SVG (vector, for print)
- **Drag** the preview straight into Finder, Mail, Slack, Figma — it writes
  a real file in the format currently selected
- **Save…** (`⌘S`) remembers the last folder and suggests a filename from
  the contents (`example-com.pdf`, `ada-lovelace.png`)
- **Copy** (`⇧⌘C`) puts an image, PDF, or the SVG source on the clipboard
- **Batch Export…** turns a pasted list into one file per line, deduplicating
  names that collide
- **Error correction** L/M/Q/H, with the ISO 18004 recovery percentage shown
- **Quiet zone** adjustable from 0 to 16 modules (ISO 18004 specifies 4 as the
  minimum; the app says so when you go below it)

If the clipboard holds a URL when the app opens, it's prefilled.

## Details

A **Details** section under the payload form reports symbol version and module
count, correction level and recovery percentage, payload size in bytes and
characters, remaining capacity before the symbol steps up a version, dark
module count and density, quiet zone in both modules and pixels, and the
resolved output dimensions and scale. Below it, **Encoded payload** shows the
exact string written into the symbol — useful for checking how a Wi-Fi or
vCard payload was assembled. Every value is selectable.

Headroom is measured by probing (append filler, binary search on where the
version changes) rather than from capacity tables, so it stays correct
whichever encoding mode CoreImage picks.

The preview renders edge to edge with no decorative inset, so the white margin
around the code is exactly the quiet zone being exported; the hairline marks
the file's outer bounds.

## Rendering notes

CoreImage emits the symbol with its own 1-module border; that gets cropped on
read, so the grid is the bare symbol and the quiet zone is entirely yours to
set — including none at all.

Codes are rendered from the raw module grid, not by upscaling a bitmap.
Horizontal runs of dark modules are merged into a single path, so vector
output has no hairline seams between squares, and raster output snaps to
whole pixels per module — a 1024px request yields the largest crisp image
at or below that size. All three formats share the same geometry and
quiet zone.

## Files

    Sources/QR.swift           module grid, PNG/PDF/SVG rendering
    Sources/Payload.swift      payload types, encoding, filename slugs
    Sources/ContentView.swift  main window
    Sources/BatchView.swift    batch export sheet
    Sources/App.swift          app entry point
    Tools/MakeIcon.swift       app icon, drawn with CoreGraphics

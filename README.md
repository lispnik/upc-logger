# UPC Logger

<img src="res/Icon.xcassets/AppIcon.appiconset/icon-1024.png" width="128" align="right" alt="App icon: barcode bars with a wooden log lying over them.">

An iPhone app, written in Common Lisp, for counting things by their barcodes.

- **Scanning:** the top third of the screen is a live camera view that reads UPC-A, UPC-E and EAN-8/13 codes.
- **The list:** scans appear below it, newest first, each with the time it was scanned.
- **Repeat scans:** scanning the same code as the top row bumps its count rather than adding a row.
- **Setting a count:** tap a row and type how many there are on the number pad. Scan one of a case of eight, tap it, type `8`, and the row reads `8 x 012345678905`. `0` removes the row, and so does swiping left.
- **Saving:** the log is written after every change to `Documents/scans.sexp`, a readable s-expression with universal-time timestamps.

Planned: a histogram of scans over a date range, defaulting to the most recent scanning session, and a spreadsheet export.

## How it is built

- **Build:** [asdf-ios-app](https://github.com/lispnik/asdf-ios-app) compiles it with ECL into an ordinary signed `.app`; there is no Xcode project.
- **UIKit and AVFoundation:** the [objc](https://github.com/lispnik/objc) bridge reaches them from Lisp. The table's data source, the capture metadata delegate and the preview view are Objective-C classes defined in Lisp.

| Path | What |
|---|---|
| `src/core/` | The model: code normalisation and check digits, the log, saving, and the scan gate that turns a label held in view into one scan. Portable CL, no dependencies. |
| `src/ios/` | The app: camera, list, count prompt. |
| `tests/` | FiveAM tests for the core, run on the Mac. |
| `tools/icon.lisp` | Draws the icon with AppKit; `make icon` regenerates it. |

## Building

You need Xcode, [ocicl](https://github.com/ocicl/ocicl), and these checkouts side by side:

```sh
git clone https://github.com/lispnik/objc.git
git clone https://github.com/lispnik/asdf-ios-app.git
git clone https://github.com/lispnik/upc-logger.git
cd upc-logger && make deps
```

You also need an ECL toolchain for iOS:
- **Default:** run `(asdf-ios-app:bootstrap-ecl)` once.
- **Existing toolchain:** point `ECL_DIR` at a directory holding matched `ecl-native`, `ecl-iOS` and `ecl-iOS-sim` prefixes. The Makefile looks in `~/Projects/ecl` by default.

```sh
make test       # the FiveAM suite, on the host
make run-sim    # build, install and launch on the booted simulator
make demo-sim   # the same, with a few scripted scans
make device     # build, install and launch on a connected iPhone
```

A simulator has no camera, so there the preview area shows a **Simulate scan** button.

`make device` needs a development identity and a provisioning profile, set in a `local.mk` that is not committed:

```make
IOS_SIGNING_IDENTITY = Apple Development: Your Name (XXXXXXXXXX)
IOS_PROVISIONING_PROFILE = /path/to/profile.mobileprovision
```

The phone must be unlocked, with Developer Mode on.

## License

MIT

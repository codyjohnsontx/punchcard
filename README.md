# Punchcard

A macOS menu bar time tracker for contractors. Start and stop a clock per client and see
per-day, per-week and per-month totals. Hours only, no money. Your data stays on your Mac.

> Early development. The app currently shows a clock icon in the menu bar with a Quit item;
> tracking arrives in the next releases.

## Requirements

macOS 14 Sonoma or later.

## Build from source

Needs Swift 6 from the Xcode Command Line Tools (`xcode-select --install`) or Xcode.

```sh
make build   # swift build
make test    # swift test, with the flags Command Line Tools need for Swift Testing
make app     # universal, ad-hoc signed dist/Punchcard.app
make run     # swift run Punchcard, no app bundle
make zip     # dist/Punchcard-<version>-macos.zip and its .sha256
```

Set `VERSION=x.y.z` for `make app` or `make zip` to stamp the bundle version.

With only the Command Line Tools, plain `swift test` builds but runs no tests, because
SwiftPM does not put Swift Testing on the framework search path; use `make test`.
With Xcode selected, `swift test` works as usual.

Xcode can open `Package.swift` directly for previews and debugging.

## Layout

- `Sources/PunchcardCore`: models and logic, no UI
- `Sources/Punchcard`: the SwiftUI menu bar app
- `Tests/PunchcardCoreTests`: tests for the core library
- `Packaging`: `Info.plist` template and source icon
- `scripts`: app bundle and icon scripts

## Roadmap

A Tauri app for Windows and Linux, in this repository, sharing the same data format.

## License

[MIT](LICENSE)

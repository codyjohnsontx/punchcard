# Project agent memory

This file is the project's committed home for project-intrinsic agent knowledge: build, test, release, architecture, and sharp-edge notes that should travel with the code.

- Build, test and package through the `Makefile` targets; it and `scripts/build-app.sh` are the source of truth for commands.
- Run tests with `make test`, not bare `swift test`: with only the Command Line Tools, `swift test` builds but silently runs zero Swift Testing tests (SwiftPM omits the `-F`/rpath for `Testing.framework`, and its synthesized runner cannot be fixed from `Package.swift`).
- The app version comes from the `VERSION` environment variable, which `scripts/build-app.sh` stamps into `Info.plist` (default `0.0.0-dev`); `release.yml` (on `v*` tags) sets it from the tag, so `v0.1.0` builds 0.1.0, and local builds use e.g. `VERSION=0.1.0 make app`.
- `swift build --arch arm64 --arch x86_64` needs Xcode's XCBuild, so `scripts/build-app.sh` builds each `--triple` and merges with `lipo`; keep it that way so the app builds with the Command Line Tools alone.
- SwiftPM's native build system generates `Bundle.module` to look for `<Package>_<Target>.bundle` next to `Bundle.main.bundleURL` (the `.app` root), not in `Contents/Resources` where `build-app.sh` copies bundles; the first target with resources must load them from `Bundle.main.resourceURL` explicitly.
- `docs/schema.md` is the SQLite contract shared with the planned Tauri app: schema changes go in a new numbered file under `Sources/PunchcardCore/Resources/Migrations` (never edit a released one), tracked only by `PRAGMA user_version`, and update that doc.
- GRDB date strategies are `static func databaseDate{En,De}codingStrategy(for:)`; a `static let` of the same name compiles but is silently ignored and dates get stored as text instead of Unix seconds.
- `Database.defaultURL()` resolves the support folder from the account, not `$HOME`, so a launch from a shell always opens the user's real database; to validate against fixtures, point `Database.open(at:)` at a scratch file in a temporary, uncommitted edit.
- Agent shells have no Screen Recording or Accessibility, so screenshots and synthetic clicks fail. For visual evidence, host the view in an `NSWindow` from a temporary hook and render it in-process with `bitmapImageRepForCachingDisplay` + `cacheDisplay(in:to:)`; AppKit tables, forms and sheets render, while sidebars, toolbars and alerts come out as blank material.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.

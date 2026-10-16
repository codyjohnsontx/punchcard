# Project agent memory

This file is the project's committed home for project-intrinsic agent knowledge: build, test, release, architecture, and sharp-edge notes that should travel with the code.

- Build, test and package through the `Makefile` targets; it and `scripts/build-app.sh` are the source of truth for commands.
- Run tests with `make test`, not bare `swift test`: with only the Command Line Tools, `swift test` builds but silently runs zero Swift Testing tests (SwiftPM omits the `-F`/rpath for `Testing.framework`, and its synthesized runner cannot be fixed from `Package.swift`).
- `swift build --arch arm64 --arch x86_64` needs Xcode's XCBuild, so `scripts/build-app.sh` builds each `--triple` and merges with `lipo`; keep it that way so the app builds with the Command Line Tools alone.
- SwiftPM's native build system generates `Bundle.module` to look for `<Package>_<Target>.bundle` next to `Bundle.main.bundleURL` (the `.app` root), not in `Contents/Resources` where `build-app.sh` copies bundles; the first target with resources must load them from `Bundle.main.resourceURL` explicitly.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.

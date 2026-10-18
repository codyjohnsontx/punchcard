#!/usr/bin/env bash
# Builds a universal release binary and assembles dist/Punchcard.app, ad-hoc signed.
# Needs only the Command Line Tools. Usage: [VERSION=x.y.z] scripts/build-app.sh [--zip]
set -euo pipefail

cd "$(dirname "$0")/.."

name="Punchcard"
version="${VERSION:-0.0.0-dev}"
build="${version%%-*}"
zip=false
for arg in "$@"; do
  case "$arg" in
    --zip) zip=true ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

# `swift build --arch a --arch b` needs Xcode's XCBuild, so build each
# architecture separately and merge them with lipo.
bin_dirs=()
for arch in arm64 x86_64; do
  triple="$arch-apple-macosx14.0"
  swift build -c release --product "$name" --triple "$triple"
  bin_dirs+=("$(swift build -c release --triple "$triple" --show-bin-path)")
done

app="dist/$name.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

lipo -create "${bin_dirs[0]}/$name" "${bin_dirs[1]}/$name" -output "$app/Contents/MacOS/$name"

# Resource bundles are architecture independent; take them from the first build.
# The ${a[@]+...} form keeps an empty array safe under set -u in macOS bash 3.2.
shopt -s nullglob
bundles=("${bin_dirs[0]}"/*.bundle)
shopt -u nullglob
for bundle in ${bundles[@]+"${bundles[@]}"}; do
  cp -R "$bundle" "$app/Contents/Resources/"
done

scripts/make-icon.sh Packaging/icon-1024.png "$app/Contents/Resources/AppIcon.icns"

sed -e "s/__VERSION__/$version/" -e "s/__BUILD__/$build/" Packaging/Info.plist > "$app/Contents/Info.plist"
plutil -lint "$app/Contents/Info.plist" >/dev/null

# Ad-hoc signing is required: Apple silicon refuses to launch an unsigned bundle.
# SwiftPM writes an Info.plist only into bundles with processed resources; codesign
# rejects a bundle without one, and the app's own signature seals it as plain resources.
for bundle in ${bundles[@]+"${bundles[@]}"}; do
  nested="$app/Contents/Resources/$(basename "$bundle")"
  if [ -f "$nested/Info.plist" ]; then
    codesign --force --sign - "$nested"
  fi
done
codesign --force --sign - "$app"

echo "built $app ($version)"

if $zip; then
  archive="dist/$name-$version-macos.zip"
  rm -f "$archive" "$archive.sha256"
  ditto -c -k --keepParent "$app" "$archive"
  (cd dist && shasum -a 256 "$(basename "$archive")" > "$(basename "$archive").sha256")
  echo "built $archive"
fi

#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="MarkdownQuickLook"
EXT_NAME="MarkdownQuickLookExtension"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
APPEX_BUNDLE="$APP_BUNDLE/Contents/PlugIns/$EXT_NAME.appex"

echo "== Checking toolchain =="
if ! echo 'import QuickLookUI' | xcrun swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" -typecheck - >/dev/null 2>&1; then
  echo "error: 'import QuickLookUI' failed to compile with the active developer directory ($(xcode-select -p))." >&2
  echo "This almost always means Xcode is installed but not selected as the active toolchain." >&2
  echo "Fix with:" >&2
  echo "  sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer" >&2
  echo "  sudo xcodebuild -license accept" >&2
  exit 1
fi

echo "== Cleaning build directory =="
rm -rf "$BUILD_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
mkdir -p "$APPEX_BUNDLE/Contents/MacOS"
mkdir -p "$APPEX_BUNDLE/Contents/Resources"

# Keep this in sync with LSMinimumSystemVersion in Plists/*.plist. Without an
# explicit -target, swiftc builds for the *host* macOS version, so the bundle
# silently refuses to load on anything older than the machine that built it.
DEPLOYMENT_TARGET="11.0"
ARCHS=(arm64 x86_64)

# Compiles one target for every arch in $ARCHS and lipos them into a universal
# binary, so a build made on Apple silicon still runs on Intel Macs.
# usage: build_universal <output> <module-name> <sources-glob> [extra swiftc args...]
build_universal() {
  local output="$1" module="$2" sources="$3"
  shift 3
  local slices=()
  local tmpdir
  tmpdir="$(mktemp -d)"

  for arch in "${ARCHS[@]}"; do
    local slice="$tmpdir/$module.$arch"
    xcrun swiftc \
      -module-name "$module" \
      -target "$arch-apple-macos$DEPLOYMENT_TARGET" \
      -emit-executable \
      -O \
      $sources \
      -o "$slice" \
      "$@"
    slices+=("$slice")
  done

  xcrun lipo -create "${slices[@]}" -output "$output"
  rm -rf "$tmpdir"
}

echo "== Compiling extension (${ARCHS[*]}) =="
build_universal \
  "$APPEX_BUNDLE/Contents/MacOS/$EXT_NAME" \
  "$EXT_NAME" \
  "Sources/Extension/*.swift" \
  -parse-as-library \
  -application-extension \
  -Xlinker -e -Xlinker _NSExtensionMain \
  -framework Cocoa -framework QuickLookUI -framework WebKit

echo "== Compiling host app (${ARCHS[*]}) =="
build_universal \
  "$APP_BUNDLE/Contents/MacOS/$APP_NAME" \
  "$APP_NAME" \
  "Sources/App/*.swift" \
  -framework Cocoa

echo "== Copying Info.plist files =="
cp Plists/App-Info.plist "$APP_BUNDLE/Contents/Info.plist"
cp Plists/Extension-Info.plist "$APPEX_BUNDLE/Contents/Info.plist"

echo "== Copying extension resources =="
cp Resources/template.html "$APPEX_BUNDLE/Contents/Resources/"
cp Resources/marked.min.js "$APPEX_BUNDLE/Contents/Resources/"
cp Resources/github-markdown.css "$APPEX_BUNDLE/Contents/Resources/"

echo "== Code signing (ad-hoc, local use only) =="
codesign --force --sign - --timestamp=none --entitlements Plists/Extension.entitlements "$APPEX_BUNDLE"
codesign --force --sign - --timestamp=none "$APP_BUNDLE"

echo "== Verifying signatures =="
codesign --verify --verbose=2 "$APPEX_BUNDLE"
codesign --verify --verbose=2 "$APP_BUNDLE"

echo "== Done =="
echo "Built: $APP_BUNDLE"

#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="MarkdownQuickLook"
EXT_NAME="MarkdownQuickLookExtension"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
APPEX_BUNDLE="$APP_BUNDLE/Contents/PlugIns/$EXT_NAME.appex"

echo "== Cleaning build directory =="
rm -rf "$BUILD_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
mkdir -p "$APPEX_BUNDLE/Contents/MacOS"
mkdir -p "$APPEX_BUNDLE/Contents/Resources"

echo "== Compiling extension =="
xcrun swiftc \
  -module-name "$EXT_NAME" \
  -parse-as-library \
  -application-extension \
  -emit-executable \
  -O \
  Sources/Extension/*.swift \
  -o "$APPEX_BUNDLE/Contents/MacOS/$EXT_NAME" \
  -Xlinker -e -Xlinker _NSExtensionMain \
  -framework Cocoa -framework QuickLookUI -framework WebKit

echo "== Compiling host app =="
xcrun swiftc \
  -module-name "$APP_NAME" \
  -emit-executable \
  -O \
  Sources/App/*.swift \
  -o "$APP_BUNDLE/Contents/MacOS/$APP_NAME" \
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

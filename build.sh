#!/bin/bash
# Builds "Speaking Order.app" next to this script. Run on an Apple silicon Mac.
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v swiftc >/dev/null 2>&1; then
  echo "swiftc not found. Install Xcode Command Line Tools first:"
  echo "  xcode-select --install"
  exit 1
fi

APP="Speaking Order.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "Compiling…"
swiftc -O -parse-as-library -target arm64-apple-macos14.0 \
  SpeakingOrderApp.swift Meeting.swift Theme.swift SetupView.swift MeetingView.swift \
  -framework SwiftUI -framework AppKit \
  -o "$APP/Contents/MacOS/SpeakingOrder"

cp Info.plist "$APP/Contents/Info.plist"

echo "Making icon…"
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s icon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) icon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$(dirname "$ICONSET")"

echo "Signing (ad hoc)…"
codesign --force --deep --sign - "$APP"

echo
echo "Built: $(pwd)/$APP"
echo "Drag it into /Applications, or run:  mv \"$APP\" /Applications/"

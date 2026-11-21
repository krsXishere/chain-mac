#!/bin/sh
# Bundles the release build into ChainMac.app so Accessibility can be granted to
# the app itself instead of the terminal that launched it. Ad-hoc signed: enough
# for a local TCC grant, not for distribution.
set -e
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/ChainMac"

./scripts/makeiconset.sh

APP="build/ChainMac.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ChainMac"
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp packaging/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - --identifier app.chainmac "$APP"

echo "Built $APP"
echo "Run: open $APP"

#!/bin/sh
# Builds AppIcon.icns from the script that draws it, so the icon lives in source
# rather than in a binary nobody can edit.
set -e
cd "$(dirname "$0")/.."

SET="build/AppIcon.iconset"
rm -rf "$SET"
mkdir -p "$SET"

swift scripts/makeicon.swift build/icon-1024.png >/dev/null

for size in 16 32 128 256 512; do
    sips -z $size $size build/icon-1024.png --out "$SET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z $double $double build/icon-1024.png --out "$SET/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$SET" -o build/AppIcon.icns
echo "Built build/AppIcon.icns"

#!/bin/bash
# Regenerates Resources/AppIcon.icns from the Play-pane artwork.
# Only needed when the artwork changes; the .icns is committed.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ART="$REPO_ROOT/Sources/TLGLauncher/Resources/tlg-artwork.png"
OUT="$REPO_ROOT/Resources/AppIcon.icns"

TMP="$(mktemp -d /tmp/tlg-icon.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

swift "$REPO_ROOT/Scripts/MakeIcon.swift" "$ART" "$TMP/icon-1024.png"

ICONSET="$TMP/AppIcon.iconset"
mkdir "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$TMP/icon-1024.png" \
        --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$TMP/icon-1024.png" \
        --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done

mkdir -p "$(dirname "$OUT")"
iconutil -c icns "$ICONSET" -o "$OUT"
echo "Built: $OUT"

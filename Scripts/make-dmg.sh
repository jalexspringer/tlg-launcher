#!/bin/bash
# Packages dist/TLG Launcher.app into a drag-to-install DMG.
#
# Stages the app beside an /Applications symlink (the layout TLG's own DMGs
# use) and compresses with hdiutil. Rebuilds the app via make-app.sh when it
# is missing; pass --skip-guide to forward that to the app build.
#
# Usage: Scripts/make-dmg.sh [--skip-guide]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$REPO_ROOT/dist/Cataclysm TLG Launcher.app"

if [[ ! -d "$APP" ]]; then
    "$REPO_ROOT/Scripts/make-app.sh" "${1:-}"
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$REPO_ROOT/dist/Cataclysm-TLG-Launcher-$VERSION.dmg"

STAGING="$(mktemp -d /tmp/tlg-dmg.XXXXXX)"
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/Cataclysm TLG Launcher.app"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG"
hdiutil create -volname "Cataclysm TLG Launcher" -srcfolder "$STAGING" \
    -format UDZO -fs HFS+ -quiet "$DMG"
echo "Built: $DMG"

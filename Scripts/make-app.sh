#!/bin/bash
# Assembles "TLG Launcher.app" from the SwiftPM build products.
#
# This machine builds with Command Line Tools only (no Xcode), so the bundle
# is put together by hand: release binary + Info.plist + staged guide dist,
# then ad-hoc signed.
#
# Usage: Scripts/make-app.sh [--skip-guide]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Finder forbids ":" in filenames, so the bundle drops it; the display
# name in Info.plist carries the full "Cataclysm: TLG Launcher".
APP="$REPO_ROOT/dist/Cataclysm TLG Launcher.app"
SKIP_GUIDE="${1:-}"

if [[ "$SKIP_GUIDE" != "--skip-guide" && ! -f "$REPO_ROOT/GuideDist/index.html" ]]; then
    "$REPO_ROOT/Scripts/build-guide.sh"
fi

echo "Building release binary (universal)..."
# Two --triple builds joined with lipo: `swift build --arch a --arch b`
# needs Xcode's xcbuild, which Command Line Tools do not ship.
for triple in arm64-apple-macosx x86_64-apple-macosx; do
    swift build --package-path "$REPO_ROOT" -c release \
        --triple "$triple" --product TLGLauncher
done

BIN_DIR="$REPO_ROOT/.build/universal-release"
mkdir -p "$BIN_DIR"
lipo -create \
    "$REPO_ROOT/.build/arm64-apple-macosx/release/TLGLauncher" \
    "$REPO_ROOT/.build/x86_64-apple-macosx/release/TLGLauncher" \
    -output "$BIN_DIR/TLGLauncher"
# Bundled resources are arch-independent; take them from the arm64 build.
rm -rf "$BIN_DIR/TLGLauncher_TLGLauncher.bundle"
ditto "$REPO_ROOT/.build/arm64-apple-macosx/release/TLGLauncher_TLGLauncher.bundle" \
      "$BIN_DIR/TLGLauncher_TLGLauncher.bundle"
BIN="$BIN_DIR/TLGLauncher"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Cataclysm TLG Launcher"

# SwiftPM target resources (Bundle.module) — the artwork on the Play pane.
# Bundle.module traps at launch if this bundle is missing from Resources.
ditto "$BIN_DIR/TLGLauncher_TLGLauncher.bundle" \
      "$APP/Contents/Resources/TLGLauncher_TLGLauncher.bundle"

cp "$REPO_ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

if [[ -f "$REPO_ROOT/GuideDist/index.html" ]]; then
    ditto "$REPO_ROOT/GuideDist" "$APP/Contents/Resources/GuideDist"
else
    echo "warning: GuideDist missing — the Guide tab will be empty" >&2
fi

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>Cataclysm TLG Launcher</string>
	<key>CFBundleIdentifier</key>
	<string>me.alexspringer.tlg-launcher</string>
	<key>CFBundleName</key>
	<string>Cataclysm: TLG Launcher</string>
	<key>CFBundleDisplayName</key>
	<string>Cataclysm: TLG Launcher</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>0.2.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.games</string>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
	<key>NSHighResolutionCapable</key>
	<true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"
echo "Built: $APP"

#!/usr/bin/env bash
# build-dmg.sh — Build a distributable DMG from the compiled .app bundle.
# Usage: ./scripts/build-dmg.sh <version>
# Example: ./scripts/build-dmg.sh 0.1.0-alpha
#
# Expects PrivateAIMail.app to already be built. When APP_PATH is set, that
# bundle is used. Otherwise it looks in the xcodebuild DerivedData directory
# (Release config first, then Debug).
# Produces dist/PrivateAIMail-<version>.dmg + dist/PrivateAIMail-<version>.sha256
set -euo pipefail

VERSION="${1:?Usage: $0 <version>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$PROJECT_ROOT/dist"
DMG_NAME="PrivateAIMail-${VERSION}.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
APP_NAME="PrivateAIMail.app"
VOLUME_NAME="PrivateAIMail ${VERSION}"

# --- Locate the built .app ---
find_app() {
    local dd_base
    dd_base="$HOME/Library/Developer/Xcode/DerivedData"
    for config in Release Debug; do
        local candidate
        candidate=$(find "$dd_base" -maxdepth 6 -type d -name "$APP_NAME" \
            -path "*PrivateAIMail*${config}*" 2>/dev/null \
            | sort -r | head -1)
        if [ -n "$candidate" ] && [ -d "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

if [[ -n "${APP_PATH:-}" ]]; then
    if [[ ! -d "$APP_PATH" ]]; then
        echo "ERROR: APP_PATH does not point to an app bundle: $APP_PATH" >&2
        exit 1
    fi
    APP_SOURCE="$APP_PATH"
else
    APP_SOURCE=$(find_app) || {
        echo "ERROR: Could not find $APP_NAME in DerivedData. Build the app first:" >&2
        echo "  xcodebuild build -workspace PrivateAIMail.xcworkspace -scheme MacApp -configuration Release" >&2
        exit 1
    }
fi
echo "Using app bundle: $APP_SOURCE"

# --- Clean dist/ ---
mkdir -p "$DIST_DIR"
rm -f "$DMG_PATH" "$DIST_DIR/${DMG_NAME%.dmg}.sha256"

# --- Create staging area ---
STAGING="$(mktemp -d -t dmg-staging.XXXXXX)"
RW_DMG=""
trap 'rm -rf "$STAGING" "$RW_DMG"' EXIT

# Copy the .app
ditto "$APP_SOURCE" "$STAGING/$APP_NAME"

# Applications symlink
ln -s /Applications "$STAGING/Applications"

# --- Create background image (simple text-based PNG via sips + osascript) ---
BG_DIR="$STAGING/.background"
mkdir -p "$BG_DIR"

# Generate a minimal installer background with text hint.
# Uses a small Swift script to draw text onto a solid background.
/usr/bin/swift - "$BG_DIR/installer-bg.png" <<'SWIFT_EOF'
import AppKit
import Foundation

let path = CommandLine.arguments[1]
let size = NSSize(width: 500, height: 340)

let image = NSImage(size: size)
image.lockFocus()

// Citron-tinted background
NSColor(red: 0.96, green: 0.98, blue: 0.90, alpha: 1.0).setFill()
NSRect(origin: .zero, size: size).fill()

// Arrow hint
let arrowAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 64, weight: .ultraLight),
    .foregroundColor: NSColor(white: 0.55, alpha: 1.0),
]
let arrow = NSAttributedString(string: "⟶", attributes: arrowAttrs)
let arrowSize = arrow.size()
arrow.draw(at: NSPoint(x: (size.width - arrowSize.width) / 2, y: (size.height - arrowSize.height) / 2 - 20))

// Instruction text
let textAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 13, weight: .regular),
    .foregroundColor: NSColor(white: 0.45, alpha: 1.0),
]
let text = NSAttributedString(string: "Drag to Applications to install", attributes: textAttrs)
let textSize = text.size()
text.draw(at: NSPoint(x: (size.width - textSize.width) / 2, y: 40))

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:])
else {
    fputs("Failed to render background image\n", stderr)
    exit(1)
}

do {
    try png.write(to: URL(fileURLWithPath: path))
} catch {
    fputs("Failed to write background image: \(error)\n", stderr)
    exit(1)
}
SWIFT_EOF

echo "Background image generated."

# --- Create temporary read-write DMG, set window layout, convert to compressed ---
RW_DMG="$(mktemp -t rw-dmg.XXXXXX).dmg"  # cleaned up by EXIT trap
MOUNT_POINT="/Volumes/$VOLUME_NAME"

# Detach any stale mount with the same volume name
hdiutil detach "$MOUNT_POINT" 2>/dev/null || true

# Calculate required size: app size + 20 MB headroom
APP_SIZE_KB=$(du -sk "$STAGING/$APP_NAME" | awk '{print $1}')
DMG_SIZE_KB=$(( APP_SIZE_KB + 20480 ))

hdiutil create \
    -srcfolder "$STAGING" \
    -volname "$VOLUME_NAME" \
    -fs HFS+ \
    -fsargs "-c c=64,a=16,e=16" \
    -size "${DMG_SIZE_KB}k" \
    -format UDRW \
    "$RW_DMG"

# Try to set Finder window layout via AppleScript (best-effort; CI may skip this)
if hdiutil attach "$RW_DMG" -readwrite -noverify -noautoopen -mountpoint "$MOUNT_POINT"; then
    sleep 1
    osascript <<APPLESCRIPT 2>/dev/null || echo "Note: Finder layout customization skipped (headless environment)"
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 700, 460}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 80
        set background picture of viewOptions to file ".background:installer-bg.png"
        set position of item "$APP_NAME" of container window to {125, 150}
        set position of item "Applications" of container window to {375, 150}
        close
        open
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT
    sync
    hdiutil detach "$MOUNT_POINT"
fi

# --- Convert to compressed read-only DMG (UDZO) ---
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH"
rm -f "$RW_DMG"

echo ""
echo "DMG created: $DMG_PATH"
echo "Size: $(du -h "$DMG_PATH" | awk '{print $1}')"

# --- SHA-256 checksum ---
SHA256=$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')
echo "$SHA256  $DMG_NAME" > "$DIST_DIR/${DMG_NAME%.dmg}.sha256"
echo "SHA-256: $SHA256"
echo "Checksum written to: $DIST_DIR/${DMG_NAME%.dmg}.sha256"

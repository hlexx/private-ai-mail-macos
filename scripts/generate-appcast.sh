#!/usr/bin/env bash
# generate-appcast.sh — Generate appcast.xml from dist/*.dmg files.
#
# Usage: scripts/generate-appcast.sh
#
# Walks dist/*.dmg, signs each with Sparkle's sign_update tool (reads the
# EdDSA private key from the macOS login Keychain), and emits dist/appcast.xml.
#
# Release notes: if release-notes/<version>.html exists, its contents are
# inlined as CDATA in the <description> element. Otherwise a generic note
# is used.
#
# The download URL follows the GitHub Releases convention:
#   https://github.com/hlexx/private-ai-mail-macos/releases/download/v<version>/<dmg-name>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$PROJECT_ROOT/dist"
SIGN_UPDATE="$PROJECT_ROOT/tools/sparkle/sign_update"
RELEASE_NOTES_DIR="$PROJECT_ROOT/release-notes"
APPCAST_PATH="$DIST_DIR/appcast.xml"
GITHUB_REPO="hlexx/private-ai-mail-macos"

if [[ ! -x "$SIGN_UPDATE" ]]; then
  echo "Error: sign_update tool not found at $SIGN_UPDATE" >&2
  echo "Run scripts/fetch-sparkle.sh or check tools/sparkle/" >&2
  exit 1
fi

# Collect DMGs sorted by mtime (newest first)
shopt -s nullglob
DMGS=("$DIST_DIR"/PrivateAIMail-*.dmg)
shopt -u nullglob

if [[ ${#DMGS[@]} -eq 0 ]]; then
  echo "Error: no DMG files found in $DIST_DIR" >&2
  exit 1
fi

# Sort by mtime, newest first
IFS=$'\n' DMGS_SORTED=($(ls -t "${DMGS[@]}")); unset IFS

echo "==> Generating appcast.xml from ${#DMGS_SORTED[@]} DMG(s)..."

# Start the XML
cat > "$APPCAST_PATH" <<'XML_HEADER'
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Re:Box Updates</title>
    <link>https://github.com/hlexx/private-ai-mail-macos</link>
    <description>Most recent updates for Re:Box</description>
    <language>en</language>
XML_HEADER

for dmg in "${DMGS_SORTED[@]}"; do
  DMG_BASENAME="$(basename "$dmg")"

  # Extract version from filename: PrivateAIMail-<version>.dmg
  VERSION="${DMG_BASENAME#PrivateAIMail-}"
  VERSION="${VERSION%.dmg}"

  # Derive build number from version: strip non-numeric, use as integer
  # Convention: 0.1.0-alpha → 100, 0.1.1-alpha → 101, 0.2.0 → 200
  VERSION_CLEAN="${VERSION%%-*}"  # strip pre-release suffix
  IFS='.' read -r major minor patch <<< "$VERSION_CLEAN"
  BUILD_NUMBER=$(( (major * 1000 + minor * 100 + patch) ))
  # Minimum build number is 100
  if [[ $BUILD_NUMBER -lt 100 ]]; then
    BUILD_NUMBER=100
  fi

  # File size in bytes
  FILE_SIZE=$(stat -f%z "$dmg")

  # EdDSA signature via sign_update (-p prints only the raw base64 signature,
  # without the sparkle:edSignature="..." length="..." attribute wrapper)
  echo "  Signing $DMG_BASENAME..."
  ED_SIGNATURE=$("$SIGN_UPDATE" -p "$dmg" 2>/dev/null) || {
    echo "Error: sign_update failed for $dmg" >&2
    echo "Make sure the EdDSA private key is in your login Keychain." >&2
    echo "(Run tools/sparkle/generate_keys to create one if needed)" >&2
    exit 1
  }

  # Pubdate: RFC 822 from DMG mtime
  PUBDATE=$(date -r "$dmg" "+%a, %d %b %Y %H:%M:%S %z")

  # Release notes
  NOTES_HTML=""
  for ext in html htm; do
    NOTES_FILE="$RELEASE_NOTES_DIR/${VERSION}.${ext}"
    if [[ -f "$NOTES_FILE" ]]; then
      NOTES_HTML=$(cat "$NOTES_FILE")
      break
    fi
    # Also try with v prefix
    NOTES_FILE="$RELEASE_NOTES_DIR/v${VERSION}.${ext}"
    if [[ -f "$NOTES_FILE" ]]; then
      NOTES_HTML=$(cat "$NOTES_FILE")
      break
    fi
  done
  if [[ -z "$NOTES_HTML" ]]; then
    NOTES_HTML="<p>Re:Box ${VERSION}</p>"
  fi

  DOWNLOAD_URL="https://github.com/${GITHUB_REPO}/releases/download/v${VERSION}/${DMG_BASENAME}"

  cat >> "$APPCAST_PATH" <<ITEM_EOF
    <item>
      <title>Version ${VERSION}</title>
      <pubDate>${PUBDATE}</pubDate>
      <description><![CDATA[${NOTES_HTML}]]></description>
      <enclosure url="${DOWNLOAD_URL}"
                 sparkle:version="${BUILD_NUMBER}"
                 sparkle:shortVersionString="${VERSION}"
                 length="${FILE_SIZE}"
                 type="application/octet-stream"
                 sparkle:edSignature="${ED_SIGNATURE}" />
      <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
    </item>
ITEM_EOF

  echo "  Added item: $VERSION (build $BUILD_NUMBER, ${FILE_SIZE} bytes)"
done

cat >> "$APPCAST_PATH" <<'XML_FOOTER'
  </channel>
</rss>
XML_FOOTER

echo ""
echo "==> Appcast written to: $APPCAST_PATH"
echo "    Items: ${#DMGS_SORTED[@]}"

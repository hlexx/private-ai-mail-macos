#!/usr/bin/env bash
# notarize-dmg.sh — Submit a DMG to Apple's notarization service, then staple.
#
# Usage: scripts/notarize-dmg.sh path/to/PrivateAIMail-x.y.z.dmg
#
# Environment (ALL THREE required, otherwise the script exits with a warning):
#   RELEASE_DEVELOPER_TEAM  — Apple Developer Team ID
#   RELEASE_APPLE_ID        — Apple ID email for notarytool
#   RELEASE_APPLE_PW        — App-specific password for notarytool
set -euo pipefail

DMG_PATH="${1:?Usage: notarize-dmg.sh <path-to-dmg>}"

if [[ ! -f "$DMG_PATH" ]]; then
  echo "Error: $DMG_PATH does not exist" >&2
  exit 1
fi

if [[ -z "${RELEASE_DEVELOPER_TEAM:-}" || -z "${RELEASE_APPLE_ID:-}" || -z "${RELEASE_APPLE_PW:-}" ]]; then
  echo "==> Skipping notarization: one or more required env vars missing."
  echo "    Required: RELEASE_DEVELOPER_TEAM, RELEASE_APPLE_ID, RELEASE_APPLE_PW"
  echo "    Set all three to enable notarization."
  exit 0
fi

echo "==> Submitting $DMG_PATH for notarization..."
xcrun notarytool submit "$DMG_PATH" \
  --apple-id "$RELEASE_APPLE_ID" \
  --password "$RELEASE_APPLE_PW" \
  --team-id "$RELEASE_DEVELOPER_TEAM" \
  --wait

echo "==> Stapling notarization ticket to DMG..."
xcrun stapler staple "$DMG_PATH"

echo "==> Verifying Gatekeeper assessment..."
spctl -a -t open --context context:primary-signature "$DMG_PATH"

echo "==> Notarization complete. DMG is ready for distribution."

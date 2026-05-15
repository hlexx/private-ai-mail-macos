#!/usr/bin/env bash
# sign-app.sh — Codesign the .app bundle.
#
# Usage: scripts/sign-app.sh path/to/PrivateAIMail.app
#
# Environment:
#   RELEASE_DEVELOPER_TEAM  — Apple Developer Team ID (e.g. "ABCDE12345").
#                             If set, signs with Developer ID Application identity
#                             using Hardened Runtime. If empty/unset, falls back to
#                             ad-hoc signing.
set -euo pipefail

APP_PATH="${1:?Usage: sign-app.sh <path-to-app>}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Error: $APP_PATH does not exist or is not a directory" >&2
  exit 1
fi

ENTITLEMENTS_PATH="$(cd "$(dirname "$0")/.." && pwd)/Apps/MacApp/PrivateAIMail.entitlements"

if [[ -n "${RELEASE_DEVELOPER_TEAM:-}" ]]; then
  echo "==> Signing with Developer ID (team: $RELEASE_DEVELOPER_TEAM)"

  # Find the Developer ID Application identity matching the team ID
  IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | grep "$RELEASE_DEVELOPER_TEAM" | head -1 | sed 's/.*"\(.*\)"/\1/')
  if [[ -z "$IDENTITY" ]]; then
    echo "Error: No 'Developer ID Application' certificate found for team $RELEASE_DEVELOPER_TEAM" >&2
    echo "Install the certificate from the Apple Developer portal first." >&2
    exit 1
  fi
  echo "  Using identity: $IDENTITY"

  # Sign embedded frameworks and XPC services first (--deep handles this,
  # but being explicit is more reliable for nested bundles)
  codesign --deep --force \
    --options runtime \
    --timestamp \
    --entitlements "$ENTITLEMENTS_PATH" \
    --sign "$IDENTITY" \
    "$APP_PATH"

  echo "==> Verifying Developer ID signature..."
  codesign --verify --deep --strict "$APP_PATH"
  echo "==> Signature valid."
else
  echo "==> RELEASE_DEVELOPER_TEAM not set — falling back to ad-hoc signing"
  echo ""
  echo "  WARNING: Ad-hoc signed builds require right-click → Open on first"
  echo "  launch. macOS Gatekeeper will not recognize this build."
  echo "  Sparkle auto-updates still verify EdDSA signatures, but macOS may"
  echo "  refuse to replace an ad-hoc-signed app in some configurations."
  echo ""

  codesign --deep --force \
    --entitlements "$ENTITLEMENTS_PATH" \
    --sign - \
    "$APP_PATH"

  echo "==> Ad-hoc signature applied."
fi

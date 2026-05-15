#!/usr/bin/env bash
set -euo pipefail

SPARKLE_VERSION="2.9.1"
CHECKSUM="9fec2b888e6e2940b1bfbd5d3d010b9f67076b52170923549095cbb74132403b"
URL="https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-for-Swift-Package-Manager.zip"
DEST="$(cd "$(dirname "$0")/.." && pwd)/Frameworks/Sparkle.xcframework"

if [ -d "$DEST" ]; then
    echo "Sparkle.xcframework already present at $DEST"
    exit 0
fi

echo "Downloading Sparkle ${SPARKLE_VERSION}..."
TMPZIP="$(mktemp -t sparkle-spm.XXXXXX).zip"
curl -L -o "$TMPZIP" "$URL"

ACTUAL=$(shasum -a 256 "$TMPZIP" | awk '{print $1}')
if [ "$ACTUAL" != "$CHECKSUM" ]; then
    echo "ERROR: checksum mismatch (expected $CHECKSUM, got $ACTUAL)" >&2
    rm -f "$TMPZIP"
    exit 1
fi

mkdir -p "$(dirname "$DEST")"
TMPDIR_EXTRACT="$(mktemp -d)"
unzip -q -o "$TMPZIP" -d "$TMPDIR_EXTRACT"
ditto "$TMPDIR_EXTRACT/Sparkle.xcframework" "$DEST"
rm -rf "$TMPZIP" "$TMPDIR_EXTRACT"

echo "Sparkle.xcframework installed at $DEST"

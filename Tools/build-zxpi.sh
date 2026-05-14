#!/usr/bin/env bash
# Build zxPluginsInject.dylib from source in modules/zxPluginsInject.
#
# Used by GitHub Actions and local builds. Output: packages/zxPluginsInject.dylib
#
# Requires THEOS (CI installs it in a prior step). Falls back to ~/theos locally.

set -euo pipefail

REPO_DIR="$(pwd)"
OUT_DIR="$REPO_DIR/packages"
OUT_FILE="$OUT_DIR/zxPluginsInject.dylib"

# set this to the direct URL of the dylib (recommended: a GitHub Release asset URL)
URL="https://github.com/<OWNER>/<REPO>/releases/download/<TAG>/zxPluginsInject.dylib"

mkdir -p "$OUT_DIR"

# macos runners have curl by default (more reliable than wget)
curl -L --fail --retry 3 --output "$OUT_FILE" "$URL"

echo "Saved: $OUT_FILE"
ls -lh "$OUT_FILE"

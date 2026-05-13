#!/usr/bin/env bash
# Build zxPluginsInject.dylib — LC-injection sideload-compat shim.
#
# Loaded before main() in the resigned Spotify binary (and any .appex still
# present) via ipapatch. Provides keychain redirection and app-group
# fallbacks for sideloaded builds at a layer the host app can't avoid.
#
# Output: packages/zxPluginsInject.dylib

#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(pwd)"
OUT_DIR="$REPO_DIR/packages"
OUT_FILE="$OUT_DIR/zxPluginsInject.dylib"

# set this to the direct URL of the dylib (recommended: a GitHub Release asset URL)
URL="https://github.com/asdfzxcvbn/zxPluginsInject/releases/download/v1.0.1/zxPluginsInject.dylib"

mkdir -p "$OUT_DIR"

# macos runners have curl by default (more reliable than wget)
curl -L --fail --retry 3 --output "$OUT_FILE" "$URL"

echo "Saved: $OUT_FILE"
ls -lh "$OUT_FILE"


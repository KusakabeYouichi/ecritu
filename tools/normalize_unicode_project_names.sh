#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCHEME_PATH="$ROOT_DIR/écritu.xcodeproj/xcshareddata/xcschemes/écritu.xcscheme"

if [[ ! -f "$SCHEME_PATH" ]]; then
  exit 0
fi

# Keep scheme identifiers in NFC/precomposed form to avoid noisy diffs.
perl -CSDA -i -pe 's/(?:e&#x301;|e&#769;|&#x[eE]9;|&#233;|e\x{301}|Ã©|é)critu/\x{E9}critu/g' "$SCHEME_PATH"

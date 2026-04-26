#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

required_source_files=(
  "third_party/APP_STORE_OPEN_SOURCE_NOTICES.md"
  "third_party/sudachidict/LICENSE-2.0.txt"
  "third_party/sudachidict/LEGAL"
)

missing=0

for file in "${required_source_files[@]}"; do
  if [[ ! -f "$file" ]]; then
    echo "MISSING SOURCE FILE: $file" >&2
    missing=1
  fi
done

if [[ $# -ge 1 ]]; then
  app_path="$1"
  required_bundle_files=(
    "APP_STORE_OPEN_SOURCE_NOTICES.md"
    "LICENSE-2.0.txt"
    "LEGAL"
  )

  for file in "${required_bundle_files[@]}"; do
    if [[ ! -f "$app_path/$file" ]]; then
      echo "MISSING BUNDLE FILE: $app_path/$file" >&2
      missing=1
    fi
  done
fi

if [[ "$missing" -ne 0 ]]; then
  exit 1
fi

echo "Third-party license assets are present."

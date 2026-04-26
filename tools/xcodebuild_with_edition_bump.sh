#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

if [[ $# -eq 0 ]]; then
  echo "usage: xcodebuild_with_edition_bump.sh <xcodebuild args...>" >&2
  exit 2
fi

bash tools/normalize_unicode_project_names.sh

is_build_like_command=false
for arg in "$@"; do
  case "$arg" in
    build|build-for-testing|test|test-without-building|archive)
      is_build_like_command=true
      break
      ;;
  esac
done

if [[ "$is_build_like_command" == "true" ]]; then
  python3 tools/bump_edition_number.py Config/Edition.xcconfig
fi

exec xcodebuild "$@"

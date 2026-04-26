#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

has_violation=0

while IFS= read -r -d '' file; do
  matches="$(awk '
    {
      if (prev_nr > 0 && prev ~ /^}[[:space:]]*$/ && $0 !~ /^[[:space:]]*$/) {
        printf("%s:%d: missing blank line after top-level closing brace before: %s\\n", FILENAME, prev_nr, $0)
      }
      prev = $0
      prev_nr = NR
    }
  ' "$file")"

  if [[ -n "$matches" ]]; then
    printf "%s\n" "$matches"
    has_violation=1
  fi
done < <(git ls-files -z -- '*.swift')

if [[ "$has_violation" -ne 0 ]]; then
  echo "Style check failed: add one blank line after top-level closing brace (}) when another declaration follows." >&2
  exit 1
fi

#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASSET_ROOT="$ROOT/TiebaPure/Resources/Emoticons"
OUTPUT="$ROOT/ASSET_MANIFEST.sha256"
TEMP="$(mktemp)"
trap 'rm -f "$TEMP"' EXIT

{
  echo "# SHA-256 manifest for TiebaPure emoticon assets"
  echo "# source-status  sha256  repository-relative-path"
  echo "# tiebalite-exact = byte-identical to 4.0-dev@2885b2aabbbf47aba7bf12b1cd7cbc03b1f5ec15"
  echo "# unknown-license = origin and redistribution license unknown; no GPL grant is asserted"

  while IFS= read -r file; do
    name="$(basename "$file")"
    case "$name" in
      *.webp) status="tiebalite-exact" ;;
      *.png) status="unknown-license" ;;
      *) status="unclassified" ;;
    esac
    hash="$(shasum -a 256 "$file" | awk '{print $1}')"
    relative="${file#"$ROOT/"}"
    printf '%s  %s  %s\n' "$status" "$hash" "$relative"
  done < <(find "$ASSET_ROOT" -type f \( -name '*.webp' -o -name '*.png' \) | LC_ALL=C sort)
} > "$TEMP"

mv "$TEMP" "$OUTPUT"
trap - EXIT
echo "Wrote $OUTPUT"

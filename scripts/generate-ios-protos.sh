#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROTO_ROOT="$ROOT/Protos"
OUT="$ROOT/TiebaPure/Core/Protobuf/Generated"

for tool in python3 protoc protoc-gen-swift; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Required tool is not available: $tool" >&2
    exit 1
  fi
done

EXPECTED_SWIFT_PROTOBUF_VERSION="1.38.1"
ACTUAL_SWIFT_PROTOBUF_VERSION="$(protoc-gen-swift --version | awk '{print $2}')"
if [[ "$ACTUAL_SWIFT_PROTOBUF_VERSION" != "$EXPECTED_SWIFT_PROTOBUF_VERSION" ]]; then
  echo "protoc-gen-swift $EXPECTED_SWIFT_PROTOBUF_VERSION is required; found $ACTUAL_SWIFT_PROTOBUF_VERSION" >&2
  exit 1
fi

PROTO_FILE_LIST="$(mktemp)"
TEMP_OUT="$(mktemp -d)"
trap 'rm -f "$PROTO_FILE_LIST"; rm -rf "$TEMP_OUT"' EXIT

python3 - "$PROTO_ROOT" > "$PROTO_FILE_LIST" <<'PY'
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
roots = [
    "Personalized.proto",
    "FrsPage/FrsPage.proto",
    "PbPage/PbPageRequest.proto",
    "PbPage/PbPageResponse.proto",
    "PbFloor/PbFloorRequest.proto",
    "PbFloor/PbFloorResponse.proto",
    "TiebaPureProfile/UserProfile.proto",
]

import_pattern = re.compile(r'^\s*import\s+(?:public\s+|weak\s+)?"([^"]+)";', re.MULTILINE)
seen = set()
ordered = []
stack = list(reversed(roots))

while stack:
    relative = stack.pop()
    if relative in seen:
        continue
    path = root / relative
    if not path.exists():
        raise SystemExit(f"Missing imported proto: {relative}")
    seen.add(relative)
    ordered.append(relative)
    text = path.read_text(encoding="utf-8")
    imports = import_pattern.findall(text)
    for imported in reversed(imports):
        if imported not in seen:
            stack.append(imported)

all_schemas = {
    path.relative_to(root).as_posix()
    for path in root.rglob("*.proto")
}
unused = sorted(all_schemas - seen)
if unused:
    raise SystemExit("Proto schemas outside the generated closure: " + ", ".join(unused))

for relative in ordered:
    print(root / relative)
PY

PROTO_FILES=()
while IFS= read -r proto_file; do
  PROTO_FILES+=("$proto_file")
done < "$PROTO_FILE_LIST"

protoc \
  --proto_path="$PROTO_ROOT" \
  --swift_opt=FileNaming=PathToUnderscores \
  --swift_out="$TEMP_OUT" \
  "${PROTO_FILES[@]}"

mkdir -p "$OUT"
find "$OUT" -type f -name '*.pb*.swift' -delete
find "$OUT" -type f -name '* [0-9].swift' -delete
find "$TEMP_OUT" -type f -name '*.swift' -exec cp {} "$OUT"/ \;

echo "Generated ${#PROTO_FILES[@]} protobuf schemas into $OUT"

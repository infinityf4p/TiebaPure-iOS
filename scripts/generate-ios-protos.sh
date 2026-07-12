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

mkdir -p "$OUT"
find "$OUT" -type f -name '*.pb*.swift' -delete
find "$OUT" -type f -name '* [0-9].swift' -delete

PROTO_FILE_LIST="$(mktemp)"
trap 'rm -f "$PROTO_FILE_LIST"' EXIT

python3 - "$PROTO_ROOT" > "$PROTO_FILE_LIST" <<'PY'
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
roots = [
    "CommonRequest.proto",
    "AppPosInfo.proto",
    "Personalized.proto",
    "FrsPage/FrsPage.proto",
    "ThreadList/ThreadList.proto",
    "PbPage/PbPageRequest.proto",
    "PbPage/PbPageResponse.proto",
    "PbFloor/PbFloorRequest.proto",
    "PbFloor/PbFloorResponse.proto",
    "Post.proto",
    "SubPost.proto",
    "SubPostList.proto",
    "PbContent.proto",
    "ThreadInfo.proto",
    "ForumInfo.proto",
    "SimpleForum.proto",
    "User.proto",
    "Media.proto",
    "VideoInfo.proto",
    "Page.proto",
    "Anti.proto",
    "Error.proto",
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
  --swift_out="$OUT" \
  "${PROTO_FILES[@]}"

echo "Generated ${#PROTO_FILES[@]} protobuf schemas into $OUT"

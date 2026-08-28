#!/bin/bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
manifest="$root/manifest.json"

jq -e '
  .schemaVersion == 1 and
  (.id | type == "string" and length > 0 and (startswith("omarchy.") | not)) and
  (.name | type == "string" and length > 0) and
  (.version | type == "string" and length > 0) and
  (.kinds | type == "array" and length > 0) and
  (.entryPoints | type == "object") and
  ((.kinds | index("bar-widget")) == null or (.entryPoints.barWidget | type == "string" and length > 0))
' "$manifest" >/dev/null

while IFS= read -r entry; do
  [[ $entry != /* && $entry != *".."* ]] || {
    echo "Unsafe entry point: $entry" >&2
    exit 1
  }
  [[ -f "$root/$entry" ]] || {
    echo "Missing entry point: $entry" >&2
    exit 1
  }
done < <(jq -r '.entryPoints[]' "$manifest")

if find "$root" -path "$root/.git" -prune -o -type l -print -quit | grep -q .; then
  echo "Plugin trees may not contain symlinks" >&2
  exit 1
fi

echo "manifest: valid"

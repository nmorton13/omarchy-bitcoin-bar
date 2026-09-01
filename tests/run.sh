#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

node tests/model.test.js
node --check tests/model.test.js
bash tests/fetch-json.test.sh
jq empty manifest.json
bash tests/validate-manifest.sh
bash -n scripts/*.sh tests/*.sh

if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin validate .
fi

echo "validation: all checks passed"

#!/bin/bash
set -euo pipefail

# shellcheck source=scripts/fetch-json.sh
source "$(dirname "${BASH_SOURCE[0]}")/fetch-json.sh"

recommended_url="https://mempool.space/api/v1/fees/recommended"
blocks_url="https://mempool.space/api/v1/fees/mempool-blocks"

# Both fee endpoints return a handful of small objects; 64 KiB is far above a
# healthy response and well below anything that could strain jq.
max_bytes=65536
max_blocks=64

tmp=$(mktemp -t omarchy-bitcoin-bar-fees-XXXXXX)
trap 'rm -f "$tmp"' EXIT

if fetch_capped "$recommended_url" "$tmp" "$max_bytes" 15 &&
  jq -e '.fastestFee != null' "$tmp" >/dev/null 2>&1; then
  cat "$tmp"
  exit 0
fi

fetch_capped "$blocks_url" "$tmp" "$max_bytes" 15

jq -e --argjson maxBlocks "$max_blocks" '
  if type != "array" then error("unexpected fee projection")
  elif length == 0 then error("empty fee projection")
  elif length > $maxBlocks then error("fee projection too long")
  else
    (length - 1) as $last |
    (if $last < 2 then $last else 2 end) as $half |
    (if $last < 5 then $last else 5 end) as $hour |
    {
      fastestFee: ((.[0].medianFee * 10 | round) / 10),
      halfHourFee: ((.[$half].medianFee * 10 | round) / 10),
      hourFee: ((.[$hour].medianFee * 10 | round) / 10)
    }
  end
' "$tmp"

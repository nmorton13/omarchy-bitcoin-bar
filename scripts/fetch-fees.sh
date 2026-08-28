#!/bin/bash
set -euo pipefail

recommended_url="https://mempool.space/api/v1/fees/recommended"
blocks_url="https://mempool.space/api/v1/fees/mempool-blocks"

tmp=$(mktemp -t omarchy-bitcoin-bar-fees-XXXXXX)
trap 'rm -f "$tmp"' EXIT

if curl -fsS --connect-timeout 5 --max-time 15 --retry 1 --retry-delay 1 \
  "$recommended_url" >"$tmp" && jq -e '.fastestFee != null' "$tmp" >/dev/null; then
  cat "$tmp"
  exit 0
fi

curl -fsS --connect-timeout 5 --max-time 15 --retry 1 --retry-delay 1 "$blocks_url" |
  jq -e '
    if length == 0 then error("empty fee projection")
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
  '

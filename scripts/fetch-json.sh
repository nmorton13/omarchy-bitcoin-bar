#!/bin/bash
# Fetches a JSON document with a hard cap on the number of bytes accepted.
# The cap is enforced while the body is received, so an oversized or endless
# response never reaches the disk, the parser, or stdout.
set -euo pipefail

DEFAULT_MAX_BYTES=262144
DEFAULT_MAX_TIME=15

# Script-scoped so the EXIT trap can still see it after main returns.
fetch_json_tmp=""

# fetch_capped <url> <destination> <max_bytes> <max_time>
# Writes the body to destination and returns 0 only when the complete body
# arrived within the cap. Overflow leaves destination empty and returns 1.
fetch_capped() {
  local url=$1 destination=$2 max_bytes=$3 max_time=$4
  local -a pipe_status
  local received

  # head -c stops reading at the cap, so curl is killed rather than allowed to
  # keep filling the file. pipefail is relaxed for the pipeline because that
  # early exit is an expected outcome, not a transport error.
  set +o pipefail
  curl -fsS --connect-timeout 5 --max-time "$max_time" --retry 1 --retry-delay 1 \
    --max-filesize "$max_bytes" "$url" |
    head -c "$((max_bytes + 1))" >"$destination"
  pipe_status=("${PIPESTATUS[@]}")
  set -o pipefail

  received=$(wc -c <"$destination")
  if [ "$received" -gt "$max_bytes" ]; then
    printf 'fetch-json: response from %s exceeded %s bytes\n' "$url" "$max_bytes" >&2
    : >"$destination"
    return 1
  fi

  # curl also aborts on its own --max-filesize, which can trip before head
  # reaches the cap. Either way a partial body must not survive: the only way
  # head ends the transfer early is overflow, so a non-zero curl status here is
  # always either overflow or a real transport error.
  if [ "${pipe_status[0]}" -ne 0 ] || [ "$received" -eq 0 ]; then
    : >"$destination"
    return 1
  fi
  return 0
}

is_positive_integer() {
  case $1 in
  '' | *[!0-9]*) return 1 ;;
  esac
  [ "$1" -gt 0 ]
}

main() {
  local url=${1:-}
  local max_bytes=${2:-$DEFAULT_MAX_BYTES}
  local max_time=${3:-$DEFAULT_MAX_TIME}

  if [ -z "$url" ]; then
    echo "usage: fetch-json.sh <url> [max-bytes] [max-time]" >&2
    exit 2
  fi
  if ! is_positive_integer "$max_bytes" || ! is_positive_integer "$max_time"; then
    echo "fetch-json: max-bytes and max-time must be positive integers" >&2
    exit 2
  fi

  fetch_json_tmp=$(mktemp -t omarchy-bitcoin-bar-json-XXXXXX)
  trap 'rm -f "${fetch_json_tmp:-}"' EXIT

  fetch_capped "$url" "$fetch_json_tmp" "$max_bytes" "$max_time" || exit 1
  # Validate before emitting so a truncated or malformed body is never printed.
  jq -e . "$fetch_json_tmp" >/dev/null 2>&1 || exit 1
  cat "$fetch_json_tmp"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi

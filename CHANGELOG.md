# Changelog

All notable changes to this project will be documented here.

## [Unreleased]

### Security

- Bounded every remote API response at the producer: all six collectors now fetch through `scripts/fetch-json.sh`, which caps bytes while receiving and rejects overflow before parsing or output, so an oversized or endless response cannot consume disk or parser memory.
- Added matching byte, item, and string caps to the `Model.js` parsers, bounding response size, sparkline and fee-range lengths, and retained strings.

## [1.0.1] - 2026-08-28

- Fixed the popup position so the Bitcoin panel anchors to its bar icon.

## [1.0.0] - 2026-08-28

- Initial Omarchy bar-widget release.
- Added Bitcoin network, fee, difficulty, mempool, and market summaries.
- Added animated left-side block and price detail panes.
- Added the 24-hour price chart and multi-fiat sats display.
- Added persistent refresh, fiat, and bar-label preferences.
- Added stale-data handling, partial updates, retries, and backoff.

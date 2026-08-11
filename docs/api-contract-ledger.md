# Rumble Live Stream API contract ledger

This ledger records the upstream contract used by Redot Rumbler's parser and fixtures.

| Item | Value |
| --- | --- |
| Upstream API | Rumble Live Stream API v1.1 |
| Source | <https://rumble.support/help/how-to-use-rumble-s-live-stream-api> |
| Upstream page last updated | 2025-11-20 |
| Contract checked | 2026-08-11 |
| Contract file | `addons/redot-rumbler/contracts/rumble_api_contract.json` |
| Ordered-field SHA-256 | `4c93df62fb2030cecd2369d72ea5992a85868d0ab9aa2e9b77ea642c4e2e03b4` |

The fingerprint is SHA-256 over the UTF-8 encoding of the contract's ordered `fields` entries joined by a single line-feed character, with no trailing line feed. It detects reviewed field-list drift without storing an API URL or any live response data.

The full API URL is a credential and must never be placed in this ledger, fixtures, logs, project settings, or repository history. A future contract refresh must update the JSON contract, fixtures, tests, this fingerprint together.

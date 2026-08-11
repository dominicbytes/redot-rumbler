# Capability matrix

Authority: [Rumble Live Stream API v1.1](https://rumble.support/help/how-to-use-rumble-s-live-stream-api), checked 2026-08-11.

| Capability | Status | Redot Rumbler behavior |
| --- | --- | --- |
| Runtime connection | Supported | User pastes the private API URL into masked runtime UI |
| Persistent connection | Supported | Windows Credential Manager / Linux Secret Service; no plaintext fallback |
| Identity | Supported | Response type, user ID, channel ID |
| Followers | Supported | Current/total counts, latest/recent followers, deltas and reset uncertainty |
| Subscribers | Supported | Count, latest/recent subscribers and amounts |
| Gifted subscriptions | Supported | Count, purchaser, gift type, totals/remaining, video ID |
| Livestream status | Supported | Every returned stream, live state, title, categories, viewers, likes/dislikes |
| Inbound chat | Supported with source limit | Latest/recent messages, usernames, badges, timestamps; bounded dedupe |
| Rants | Supported with source limit | Latest/recent paid messages, expiry and amounts; bounded dedupe |
| Local commands | Supported | Optional local routing over newly observed chat messages |
| Unknown fields | Supported safely | Bounded field paths only; values are discarded |
| Outbound chat | Unavailable | No official route documented |
| Moderation | Unavailable | No official route documented |
| Programmable rewards/redemptions | Unavailable | Rants are paid chat, not reward CRUD |
| Raids | Unavailable | No official route documented |
| Remote media downloads | Unavailable | Official payload documents badge strings, not verified image URL fields |

The official source limits recent chat messages plus rants to 50. Saturation emits `possible_event_gap`; no lossless guarantee is made.

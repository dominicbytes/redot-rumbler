# Redot Rumbler API

## `RumbleLiveClient`

Create one node per Rumble credential. The client is not an autoload.

### Lifecycle

- `configure(config: RumbleClientConfig, session_slot: String, ...) -> RumbleApiError`
- `connect_api_url(api_url: String) -> RumbleApiError` (awaitable)
- `restore_connection() -> RumbleApiError` (awaitable)
- `start_polling() -> RumbleApiError`
- `stop_polling(reason := "requested")`
- `poll_once() -> RumbleApiError` (awaitable)
- `disconnect_and_clear() -> RumbleApiError` (awaitable)
- `diagnostic_summary() -> Dictionary`

`configure()` accepts only non-secret publisher/application/session identifiers. `connect_api_url()` validates and moves the in-memory URL into the operating-system vault. `restore_connection()` retrieves it without adding it to the descriptor or diagnostics.

### Signals

- lifecycle: `state_changed`, `credential_connected`, `credential_cleared`, `error_occurred`, `retry_scheduled`;
- snapshots: `snapshot_updated(RumbleSnapshot)`;
- native events: `chat_message_received`, `rant_received`, `follower_received`, `subscriber_received`, `gifted_subscription_received`;
- streams: `stream_started`, `stream_updated`, `stream_ended` with `RumbleStreamTransition` and its `uncertain` flag;
- counters: `counter_delta`, `counter_reset`;
- truthfulness: `possible_event_gap`, `schema_warning`.

The first good poll emits `snapshot_updated` but no historical native events by default. `RumbleClientConfig.replay_history_on_first_poll` is the explicit opt-in.

## Typed models

`RumbleSnapshot` contains top-level identity/timing, both follower totals, subscriber/gift totals, latest/recent typed records, all `RumbleLivestream` values, and bounded unknown-field paths. Each livestream contains categories, live state, reactions, viewers, messages, and rants. No model has a `stream_key` or API URL property.

Rant/subscription amounts expose both integer cents and the source dollar value. Games decide localization and display formatting.

## Local command router

`RumbleCommandRouter.register_command()` registers a callable, aliases, per-user cooldown, and required badge strings. `route(RumbleChatMessage)` invokes the callable locally. It never sends a reply to Rumble and does not imply outbound-chat capability.

## Errors and diagnostics

`RumbleApiError.category` distinguishes invalid requests, credentials, transport, rate limiting, servers, parse/schema failures, cancellation, busy state, and vault availability. URLs and response fragments are excluded from normal errors. `diagnostic_summary()` returns state/timestamps/counts and only `loaded`/`not_loaded` credential status.

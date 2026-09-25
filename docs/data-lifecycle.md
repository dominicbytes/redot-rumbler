# Credential and data lifecycle

## Stored in the OS vault

Only the complete private Rumble Live Stream API URL. Windows uses a generic Credential Manager record prefixed `RedotRumbler:`. Linux uses the `org.redotengine.redot_rumbler` Secret Service schema.

The helper receives its request over stdin. The URL is never a command-line argument, environment variable, project setting, scene/resource property, or ordinary log value. There is no plaintext fallback.

## Stored under `user://`

- `redot-rumbler/sessions/<slot>.json`: schema version, non-secret vault record target, publisher/application/slot IDs, polling preferences, and minimal last identity summary;
- `redot-rumbler/state/<slot>.json`: baseline flag, versioned SHA-256 fingerprints with observed timestamps, counter baselines, and stream-state summaries.

No API URL, stream key, raw response, chat text, username history, rant text, or monetary-event history is written there. Fingerprints are bounded per collection (default 250) and expire seven days after their last observation. At most 64 inactive per-stream chat/rant collections are retained; older inactive collections are evicted first. Reappearing streams whose collections were evicted may emit still-recent items again. State is saved when its contents change, including refreshed last-observed times, so restart deduplication remains durable; unchanged state and descriptor polls do not rewrite their files.

## Memory

The loaded URL, HTTP body, typed current snapshot, and current recent events exist in process memory. Response bytes are cleared after parsing where Redot permits. `stop_polling()` retains the URL so a user can restart during the same session.

## Disconnect and clear

`await client.disconnect_and_clear()` cancels the request, deletes the OS-vault record, descriptor, and bounded state, then clears loaded URL/snapshot references. It attempts every deletion even when one fails and returns the first typed error. It never restores local state after a partial deletion.

If a URL may have been exposed, reset it at [Rumble's Live Stream API page](https://rumble.com/account/livestream-api); local deletion cannot revoke a copied credential.

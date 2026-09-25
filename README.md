# Redot Rumbler

Redot Rumbler is a standalone typed-GDScript addon for connecting a Redot game to a consenting creator's Rumble Live Stream API. It targets Redot 26.3-rc.1 on Windows and Linux x86-64 first. Windows 26.3 runtime regression tests cover deduplication, persistence and live-state transitions; this is not editor/export certification. The independently reproduced 26.3 headless-editor crash and clean Windows/Linux exported-game checks remain release gates.

The addon is intentionally **read-only and polling-based**. It covers every field documented by Rumble Live Stream API v1.1: identity, followers, subscribers, gifted subscriptions, all returned livestreams, title/categories/live state, viewers, reactions, chat, rants, badges, timestamps, and amounts. Rumble does not document outbound chat, moderation, raids, or programmable reward routes, so Redot Rumbler identifies those capabilities as unavailable instead of emulating them with scraping or private APIs.

This repository is not a Twitcher fork and will not be merged into Twitcher. Its interaction scope was informed by [dominicbytes/redot-twitcher](https://github.com/dominicbytes/twitcher), whose original Godot project is [kanimaru/twitcher](https://github.com/kanimaru/twitcher). Rumble-specific behavior was adapted from the MIT-licensed [dominicbytes/Rumble-Bytebot](https://github.com/dominicbytes/Rumble-Bytebot). Exact lineage is recorded in [`docs/lineage/reuse-manifest.json`](docs/lineage/reuse-manifest.json).

## Current status


The source implementation is complete through the repository-ready development boundary:

- silent first-poll baselining, restart-safe bounded fingerprints, overlap/reorder deduplication, counter deltas/resets, multiple-livestream transitions, schema warnings, and explicit 50-item source-window gap diagnostics;
- persistent private API URLs in Windows Credential Manager or Linux Secret Service, with a versioned non-secret `user://` descriptor and no plaintext fallback;
- one isolated credential/session slot per `RumbleLiveClient`; multiple returned livestreams remain part of one snapshot;
- single-flight GET transport with HTTPS/official-host validation, no redirect following, timeout/body limits, cancellation, typed 4xx/429/5xx handling, retry metadata, and bounded exponential backoff;
- typed snapshots/signals for chat, rants, followers, subscriptions, gifts, counters, and stream transitions;
- optional local inbound command routing, runtime connection UI, reversible editor registration, examples, docs, MIT license, and provenance;
- Windows x86-64 helper built and tested against Credential Manager; Linux x86-64 helper built and protocol-tested.

The version remains `0.1.0-dev`. Production release certification still needs a private live Rumble URL/test stream and a Linux desktop Secret Service session. Those external checks verify current cadence, live/offline ordering, high-volume 50-item pressure, URL reset/revocation, and exported Windows/Linux games.

## Install

Copy `addons/redot-rumbler/` into the target project as `res://addons/redot-rumbler/`, then enable **Redot Rumbler** under **Project > Project Settings > Plugins**. Do not add an autoload; create one client for each independent Rumble credential.

Keep the matching helper in place:

- `res://addons/redot-rumbler/bin/windows/x86_64/redot-rumbler-credential-helper.exe`
- `res://addons/redot-rumbler/bin/linux/x86_64/redot-rumbler-credential-helper`

Linux exports must preserve the executable bit and run in a graphical user session with a Secret Service implementation such as GNOME Keyring or KWallet's Secret Service interface.

## Minimal use

```gdscript
var client := RumbleLiveClient.new()
add_child(client)

var config := RumbleClientConfig.new()
config.publisher_id = "my-studio"
config.application_id = "my-game"
config.poll_interval_seconds = 5.0

var error := client.configure(config, "primary")
if error == null:
    client.chat_message_received.connect(_on_rumble_chat)
    client.rant_received.connect(_on_rumble_rant)
    error = await client.restore_connection()
    if error == null:
        client.start_polling()
```

For a first connection, collect the URL in a masked runtime field and pass that in-memory value to `await client.connect_api_url(user_entered_url)`. Never export it from a script or Inspector. See [`examples/basic_connection.tscn`](examples/basic_connection.tscn), [`docs/api.md`](docs/api.md), and [`docs/data-lifecycle.md`](docs/data-lifecycle.md).

## Source-window semantics

Rumble documents a maximum of 50 recent chat messages and rants. Redot Rumbler prevents duplicates across overlapping/reordered polls but cannot recover events that disappear before any poll observes them. A saturated window emits `possible_event_gap`; games must not describe delivery as lossless.

The default interval is five seconds and the enforced floor is two seconds. The next poll is scheduled after the previous request completes. Network, 429, and 5xx failures back off; persistent 4xx/credential errors stop tight retrying.

## Development

Set `REDOT_BIN` to Redot `26.3.rc.1.official.704b10a8e` and verify `--version`. These script commands require an initialized class/import cache. Fresh headless-editor initialization currently hits the separately reproduced 26.3 crash; the recorded script runs used an existing generated cache, so fresh-clone import is not certified.

```powershell
& $env:REDOT_BIN --version
& $env:REDOT_BIN --headless --path . --script res://addons/redot-rumbler/tests/run_helper_export_paths.gd --quit-after 1200
& $env:REDOT_BIN --headless --path . --script res://tests/run_up03.gd --quit-after 1200
& $env:REDOT_BIN --headless --path . --script res://tests/run_ms001.gd --quit-after 1200
& $env:REDOT_BIN --headless --path . --script res://tests/run_core_suite.gd --quit-after 1200
& $env:REDOT_BIN --headless --path . --script res://tests/run_http_transport_suite.gd --quit-after 2000
& $env:REDOT_BIN --headless --path . --script res://tests/run_integration_suite.gd --quit-after 3000
& $env:REDOT_BIN --headless --path . --script res://tests/run_project_check.gd --quit-after 1200
```

The reversible Windows vault smoke test creates and deletes one Rumbler-specific synthetic record:

```powershell
& $env:REDOT_BIN --headless --path . --script res://tests/run_credential_helper_smoke.gd --quit-after 600
```

See [`docs/testing.md`](docs/testing.md) for the verified boundary.

## License and independence

Redot Rumbler is MIT licensed. It is independent of and not endorsed by Rumble, Redot Engine, Godot Engine, Twitcher, or the referenced projects. See [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).

## Notes

I vibe coded this in GPT Sol 5.6. Use at your own risk. Actual programmers are welcome to submit PR's and feedback.

## About Dominic Bytes

Greetings! I am Dominic Bytes, the synth walker. I hail from the distant future. Where brains occupy robot bodies, time travel is a trip to the corner store, and the neon glow of our attire is powered by the light of our souls. Join me on a 1.21 gigawatt powered journey of chill vibes with gaming, anime, movies, and more!

- [Website](https://dominicbytes.carrd.co/)
- [X](https://x.com/DominicBytes)
- [Twitch](https://www.twitch.tv/dominicbytes)
- [YouTube](http://www.youtube.com/@DominicBytes)
- [Kick](https://kick.com/dominicbytes)

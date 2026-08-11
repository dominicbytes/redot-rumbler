# Third-party notices

`redot-rumbler` is an independent MIT-licensed Redot addon for Rumble. It is not affiliated with or endorsed by Rumble, Redot Engine, Godot Engine, Twitch, YouTube, Kick, Twitcher, or the referenced projects.

Rumble payload behavior and capability limits are derived from the official [Rumble Live Stream API v1.1 support article](https://rumble.support/help/how-to-use-rumble-s-live-stream-api). That page is a documentation input and is not redistributed as source code.

Rumble-specific parser, baseline, fingerprint, deduplication, counter, stream-transition, and fixture behavior was adapted into new typed GDScript from `dominicbytes/Rumble-Bytebot` commit `b7655e65e3d428786d5bb90c382f1aa8692f8a98`, copyright Dominic Bytes 2026, MIT licensed.

Selected generic addon, transport, descriptor, session-slot, credential-protocol, helper-process, editor, and runtime-UI foundations were adapted from `dominicbytes/redot-kicker` commit `72a3abb747cac0e148352c04a88a53e0313bd72b`, MIT licensed. Redot Kicker preserves its own lineage to `dominicbytes/redot-tuber` commit `029c22d7d5a5a68abacd8d12aabfea0b8e6536d8`, `dominicbytes/twitcher`, and the original [`kanimaru/twitcher`](https://github.com/kanimaru/twitcher), all MIT licensed where source was adapted.

Twitcher itself was used only as product/editor inspiration for Redot Rumbler; no Twitcher source file or Twitch protocol is included directly. Per-component dispositions are recorded in `docs/lineage/reuse-manifest.json`.

The Linux helper dynamically links to the system's `libsecret-1` and GLib stack. Those libraries are not bundled in this repository.

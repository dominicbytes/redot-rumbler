# Compatibility

## Certified implementation target

- Redot `26.2.stable.official.4f5b14aba`
- typed GDScript
- Windows x86-64 helper: built with MSVC and tested against Credential Manager
- Linux x86-64 helper: built on Ubuntu 24.04 and protocol-tested against `libsecret`; graphical Secret Service certification remains open

macOS, ARM64, web, and mobile are not part of the first release. Godot compatibility is not implied by Redot verification.

The Linux executable is dynamically linked to `libsecret-1` and GLib. A desktop user session must expose a Secret Service provider. Headless/container execution is expected to return `UNAVAILABLE` rather than fall back to a file.

Live Rumble API schema/cadence and exported-game certification remain release gates because no private Rumble credential was supplied during implementation.

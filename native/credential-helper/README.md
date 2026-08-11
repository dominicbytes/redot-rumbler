# Redot Rumbler credential helper

This standalone helper persists the complete private Rumble Live Stream API URL in Windows Credential Manager or Linux Secret Service. The GDScript client communicates over the bounded `RRCH/1` stdin/stdout protocol documented in `PROTOCOL.md`.

Build with CMake 3.20+ and a native x86-64 toolchain. Linux requires `pkg-config` and `libsecret-1` development headers. No plaintext fallback is implemented.

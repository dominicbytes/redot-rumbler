# RRCH/1 credential-helper protocol

Redot Rumbler launches the helper without command-line arguments and sends exactly four newline-delimited fields over stdin:

1. `RRCH/1`
2. `ping`, `store`, `read`, or `delete`
3. base64-encoded non-secret target (maximum 512 UTF-8 bytes)
4. base64-encoded private Rumble API URL for `store`, otherwise empty (maximum 4096 UTF-8 bytes)

The helper returns four lines: protocol header, status, base64 payload, and a non-secret detail. Status is one of `OK`, `NOT_FOUND`, `UNAVAILABLE`, `LOCKED`, `DENIED`, or `PROTOCOL_ERROR`.

Secrets never use command-line arguments, environment variables, stdout diagnostics, or files. Windows records use the `RedotRumbler:` Credential Manager namespace. Linux records use the `org.redotengine.redot_rumbler` Secret Service schema.

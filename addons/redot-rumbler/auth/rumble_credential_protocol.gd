class_name RumbleCredentialProtocol
extends RefCounted

## Adapted from redot-kicker commit 72a3abb747cac0e148352c04a88a53e0313bd72b,
## whose generic protocol derives from redot-tuber (MIT).
const HEADER: String = "RRCH/1"
const MAX_TARGET_BYTES: int = 512
const MAX_SECRET_BYTES: int = 4096
const VALID_COMMANDS: Array[String] = ["ping", "store", "read", "delete"]


func encode_request(command: String, target: String = "", secret: String = "") -> String:
	if not VALID_COMMANDS.has(command):
		return ""
	var target_bytes := target.to_utf8_buffer()
	var secret_bytes := secret.to_utf8_buffer()
	if target_bytes.size() > MAX_TARGET_BYTES or secret_bytes.size() > MAX_SECRET_BYTES:
		return ""
	return "%s\n%s\n%s\n%s\n" % [HEADER, command, _base64(target_bytes), _base64(secret_bytes)]


func decode_response(wire: String) -> RumbleCredentialResult:
	var result := RumbleCredentialResult.new()
	var lines := wire.replace("\r", "").split("\n", true)
	if lines.size() < 4 or lines[0] != HEADER:
		result.status = "protocol_error"
		result.error = RumbleApiError.custom("protocol_error", "Credential helper protocol mismatch")
		return result
	result.status = lines[1].to_lower()
	result.detail = lines[3]
	if result.status == "ok" and not lines[2].is_empty():
		var decoded := Marshalls.base64_to_raw(lines[2])
		if decoded.size() > MAX_SECRET_BYTES:
			result.status = "protocol_error"
			result.error = RumbleApiError.custom("protocol_error", "Credential helper response exceeds the secret limit")
			return result
		result.secret = decoded.get_string_from_utf8()
	elif result.status not in ["ok", "not_found", "unavailable", "locked", "denied"]:
		result.status = "protocol_error"
	if result.status != "ok" and result.status != "not_found":
		result.error = RumbleApiError.custom(result.status, "OS credential store is %s" % result.status)
	return result


func decode_request_for_test(wire: String) -> Dictionary:
	var lines := wire.replace("\r", "").split("\n", true)
	if lines.size() < 4 or lines[0] != HEADER:
		return {}
	return {
		"version": 1,
		"command": lines[1],
		"target": Marshalls.base64_to_raw(lines[2]).get_string_from_utf8(),
		"secret": Marshalls.base64_to_raw(lines[3]).get_string_from_utf8(),
	}


func _base64(bytes: PackedByteArray) -> String:
	return "" if bytes.is_empty() else Marshalls.raw_to_base64(bytes)

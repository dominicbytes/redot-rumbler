class_name RumbleClientConfig
extends RefCounted

var publisher_id: String = ""
var application_id: String = ""
var poll_interval_seconds: float = 5.0
var replay_history_on_first_poll: bool = false
var response_body_limit_bytes: int = 2 * 1024 * 1024
var request_timeout_seconds: float = 20.0


func validate() -> RumbleApiError:
	if not _valid_identifier(publisher_id):
		return RumbleApiError.invalid("publisher_id must use 1-64 letters, numbers, dots, underscores, or hyphens")
	if not _valid_identifier(application_id):
		return RumbleApiError.invalid("application_id must use 1-64 letters, numbers, dots, underscores, or hyphens")
	poll_interval_seconds = maxf(2.0, poll_interval_seconds)
	response_body_limit_bytes = clampi(response_body_limit_bytes, 64 * 1024, 8 * 1024 * 1024)
	request_timeout_seconds = clampf(request_timeout_seconds, 2.0, 120.0)
	return null


func qualified_slot(session_slot: String) -> String:
	return "%s/%s/%s" % [publisher_id, application_id, session_slot]


func credential_target(session_slot: String) -> String:
	return qualified_slot(session_slot)


static func valid_session_slot(value: String) -> bool:
	return _valid_identifier(value)


static func _valid_identifier(value: String) -> bool:
	if value.is_empty() or value.length() > 64:
		return false
	for character: String in value:
		if not "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-".contains(character):
			return false
	return true

class_name RumbleSessionDescriptor
extends RefCounted

const SCHEMA_VERSION: int = 1

var session_slot: String = ""
var credential_target: String = ""
var publisher_id: String = ""
var application_id: String = ""
var response_type: String = ""
var user_id: String = ""
var channel_id: String = ""
var poll_interval_seconds: float = 5.0
var replay_history_on_first_poll: bool = false
var saved_at_unix: int = 0


func to_dictionary() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"session_slot": session_slot,
		"credential_target": credential_target,
		"publisher_id": publisher_id,
		"application_id": application_id,
		"identity": {"type": response_type, "user_id": user_id, "channel_id": channel_id},
		"poll_interval_seconds": poll_interval_seconds,
		"replay_history_on_first_poll": replay_history_on_first_poll,
		"saved_at_unix": saved_at_unix if saved_at_unix > 0 else int(Time.get_unix_time_from_system()),
	}


static func from_dictionary(source: Dictionary) -> RumbleSessionDescriptor:
	if int(source.get("schema_version", 0)) != SCHEMA_VERSION:
		return null
	var value := RumbleSessionDescriptor.new()
	value.session_slot = str(source.get("session_slot", ""))
	value.credential_target = str(source.get("credential_target", ""))
	value.publisher_id = str(source.get("publisher_id", ""))
	value.application_id = str(source.get("application_id", ""))
	var identity: Variant = source.get("identity", {})
	if identity is Dictionary:
		value.response_type = str(identity.get("type", ""))
		value.user_id = str(identity.get("user_id", ""))
		value.channel_id = str(identity.get("channel_id", ""))
	value.poll_interval_seconds = maxf(2.0, float(source.get("poll_interval_seconds", 5.0)))
	value.replay_history_on_first_poll = bool(source.get("replay_history_on_first_poll", false))
	value.saved_at_unix = int(source.get("saved_at_unix", 0))
	return value

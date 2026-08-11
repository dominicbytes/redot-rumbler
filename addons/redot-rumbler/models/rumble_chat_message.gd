class_name RumbleChatMessage
extends RefCounted

var stream_id: String = ""
var stream_title: String = ""
var username: String = ""
var badges: PackedStringArray = PackedStringArray()
var text: String = ""
var created_at: String = ""
var fingerprint: String = ""


func to_dictionary() -> Dictionary:
	return {
		"stream_id": stream_id,
		"stream_title": stream_title,
		"username": username,
		"badges": Array(badges),
		"text": text,
		"created_at": created_at,
		"fingerprint": fingerprint,
	}

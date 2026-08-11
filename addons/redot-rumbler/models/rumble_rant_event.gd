class_name RumbleRantEvent
extends RefCounted

var stream_id: String = ""
var stream_title: String = ""
var username: String = ""
var badges: PackedStringArray = PackedStringArray()
var text: String = ""
var created_at: String = ""
var expires_at: String = ""
var amount_cents: int = 0
var amount_dollars: float = 0.0
var fingerprint: String = ""


func to_dictionary() -> Dictionary:
	return {
		"stream_id": stream_id,
		"stream_title": stream_title,
		"username": username,
		"badges": Array(badges),
		"text": text,
		"created_at": created_at,
		"expires_at": expires_at,
		"amount_cents": amount_cents,
		"amount_dollars": amount_dollars,
		"fingerprint": fingerprint,
	}

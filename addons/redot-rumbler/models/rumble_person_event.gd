class_name RumblePersonEvent
extends RefCounted

var kind: String = ""
var username: String = ""
var display_name: String = ""
var created_at: String = ""
var amount_cents: int = 0
var amount_dollars: float = 0.0
var fingerprint: String = ""


func to_dictionary() -> Dictionary:
	return {
		"kind": kind,
		"username": username,
		"display_name": display_name,
		"created_at": created_at,
		"amount_cents": amount_cents,
		"amount_dollars": amount_dollars,
		"fingerprint": fingerprint,
	}

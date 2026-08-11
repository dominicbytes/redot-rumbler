class_name RumbleStreamTransition
extends RefCounted

var kind: String = "updated"
var stream: RumbleLivestream = null
var stream_id: String = ""
var uncertain: bool = false
var reason: String = ""


func to_dictionary() -> Dictionary:
	return {
		"kind": kind,
		"stream_id": stream_id,
		"uncertain": uncertain,
		"reason": reason,
		"stream": stream.state_dictionary() if stream != null else null,
	}

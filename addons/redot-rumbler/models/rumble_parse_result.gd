class_name RumbleParseResult
extends RefCounted

var snapshot: RumbleSnapshot = null
var error: RumbleApiError = null


func is_success() -> bool:
	return snapshot != null and error == null

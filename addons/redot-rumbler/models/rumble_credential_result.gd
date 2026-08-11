class_name RumbleCredentialResult
extends RefCounted

var status: String = "protocol_error"
var secret: String = ""
var detail: String = ""
var error: RumbleApiError = null


func is_success() -> bool:
	return status == "ok" and error == null


func clear_secret() -> void:
	secret = ""

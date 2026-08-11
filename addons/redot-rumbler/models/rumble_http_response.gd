class_name RumbleHttpResponse
extends RefCounted

var request_result: int = HTTPRequest.RESULT_REQUEST_FAILED
var status_code: int = 0
var headers: PackedStringArray = PackedStringArray()
var body: PackedByteArray = PackedByteArray()
var elapsed_msec: int = 0
var error: RumbleApiError = null


func is_success() -> bool:
	return request_result == HTTPRequest.RESULT_SUCCESS and status_code >= 200 and status_code < 300 and error == null


func header(name: String) -> String:
	var prefix := name.to_lower() + ":"
	for line: String in headers:
		if line.to_lower().begins_with(prefix):
			return line.substr(line.find(":") + 1).strip_edges()
	return ""


func retry_after_seconds() -> float:
	var value := header("retry-after")
	return maxf(0.0, value.to_float()) if value.is_valid_float() else 0.0


func clear_body() -> void:
	body.clear()

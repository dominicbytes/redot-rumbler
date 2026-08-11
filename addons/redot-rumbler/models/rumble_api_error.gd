class_name RumbleApiError
extends RefCounted

var category: String = "unknown"
var message: String = ""
var status_code: int = 0
var retry_after_seconds: float = 0.0
var transient: bool = false


static func custom(value_category: String, value_message: String) -> RumbleApiError:
	var value := RumbleApiError.new()
	value.category = value_category
	value.message = value_message
	return value


static func invalid(value_message: String) -> RumbleApiError:
	return custom("invalid_request", value_message)


static func from_transport(code: int, value_message: String) -> RumbleApiError:
	var value := custom("cancelled" if code == ERR_SKIP else "transport", value_message)
	value.transient = code not in [ERR_INVALID_PARAMETER, ERR_INVALID_DATA, ERR_UNAUTHORIZED, ERR_SKIP]
	return value


static func from_http(code: int, retry_after: float = 0.0) -> RumbleApiError:
	var category_name := "http"
	if code in [401, 403]:
		category_name = "credential"
	elif code == 429:
		category_name = "rate_limited"
	elif code >= 500:
		category_name = "server"
	var value := custom(category_name, "Rumble Live Stream API returned HTTP %d" % code)
	value.status_code = code
	value.retry_after_seconds = maxf(0.0, retry_after)
	value.transient = code == 429 or code >= 500
	return value

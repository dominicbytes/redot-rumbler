class_name RumbleUrlPolicy
extends RefCounted

const MANAGEMENT_URL: String = "https://rumble.com/account/livestream-api"
const MAX_URL_BYTES: int = 4096


static func validate_api_url(url: String, allow_loopback_http: bool = false) -> RumbleApiError:
	if url.is_empty() or url.to_utf8_buffer().size() > MAX_URL_BYTES:
		return RumbleApiError.invalid("Rumble Live Stream API URL is empty or exceeds the supported limit")
	var whitespace := RegEx.new()
	whitespace.compile(r"[\s\p{Z}\p{Cc}]")
	if whitespace.search(url) != null or url.contains("#"):
		return RumbleApiError.invalid("Rumble Live Stream API URL contains unsupported whitespace or a fragment")
	var pattern := RegEx.new()
	pattern.compile(r"(?i)\Ahttps://((?:[a-z0-9-]+\.)*rumble\.com)(?::([0-9]{1,5}))?(/[^\s#]*)?\z")
	var matched := pattern.search(url)
	if matched == null and allow_loopback_http:
		pattern.compile(r"(?i)\Ahttp://(127\.0\.0\.1|localhost):([0-9]{1,5})(/[^\s#]*)?\z")
		matched = pattern.search(url)
	if matched == null:
		return RumbleApiError.invalid("Rumble Live Stream API URL must use HTTPS and an official rumble.com host with a valid port")
	var port := matched.get_string(2)
	if not port.is_empty() and (port.to_int() < 1 or port.to_int() > 65535):
		return RumbleApiError.invalid("Rumble Live Stream API URL port must be between 1 and 65535")
	return null

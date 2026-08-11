class_name RumbleUrlPolicy
extends RefCounted

const MANAGEMENT_URL: String = "https://rumble.com/account/livestream-api"
const MAX_URL_BYTES: int = 4096


static func validate_api_url(url: String, allow_loopback_http: bool = false) -> RumbleApiError:
	if url.is_empty() or url.to_utf8_buffer().size() > MAX_URL_BYTES:
		return RumbleApiError.invalid("Rumble Live Stream API URL is empty or exceeds the supported limit")
	if url != url.strip_edges() or url.contains("\n") or url.contains("\r") or url.contains("#"):
		return RumbleApiError.invalid("Rumble Live Stream API URL contains unsupported whitespace or a fragment")
	var lower := url.to_lower()
	var loopback := allow_loopback_http and (lower.begins_with("http://127.0.0.1:") or lower.begins_with("http://localhost:"))
	if not lower.begins_with("https://") and not loopback:
		return RumbleApiError.invalid("Rumble Live Stream API URL must use HTTPS")
	if loopback:
		return null
	var host := _host(url)
	if host != "rumble.com" and not host.ends_with(".rumble.com"):
		return RumbleApiError.invalid("Rumble Live Stream API URL must use an official rumble.com host")
	if url.substr(url.find("//") + 2).split("/", false)[0].contains("@"):
		return RumbleApiError.invalid("Rumble Live Stream API URL must not contain user information")
	return null


static func _host(url: String) -> String:
	var separator := url.find("//")
	if separator < 0:
		return ""
	var authority := url.substr(separator + 2).split("/", false)[0]
	if authority.contains("@"):
		authority = authority.get_slice("@", authority.get_slice_count("@") - 1)
	return authority.split(":", false)[0].to_lower()

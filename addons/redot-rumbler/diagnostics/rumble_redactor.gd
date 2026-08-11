class_name RumbleRedactor
extends RefCounted

const SECRET_KEYS: Array[String] = [
	"stream_key",
	"api_url",
	"access_token",
	"refresh_token",
	"client_secret",
	"authorization",
	"password",
	"secret",
	"token",
]


static func sanitize_variant(value: Variant) -> Variant:
	if value is Dictionary:
		var safe: Dictionary = {}
		for key: Variant in value:
			var name := str(key)
			if _is_secret_key(name):
				continue
			safe[name] = sanitize_variant(value[key])
		return safe
	if value is Array:
		var safe_array: Array = []
		for item: Variant in value:
			safe_array.append(sanitize_variant(item))
		return safe_array
	return value


static func redact_text(value: String) -> String:
	if value.is_empty():
		return value
	var output := value
	var url_regex := RegEx.new()
	url_regex.compile("https?://[^\\s]+")
	output = url_regex.sub(output, "<redacted-url>", true)
	for key: String in SECRET_KEYS:
		var key_regex := RegEx.new()
		key_regex.compile("(?i)(%s\\s*[=:]\\s*)[^\\s,;]+" % key)
		output = key_regex.sub(output, "$1<redacted>", true)
	return output


static func _is_secret_key(name: String) -> bool:
	var normalized := name.to_lower()
	if SECRET_KEYS.has(normalized):
		return true
	return normalized.ends_with("_token") or normalized.ends_with("_secret") or normalized.ends_with("_key") or normalized.ends_with("_url")

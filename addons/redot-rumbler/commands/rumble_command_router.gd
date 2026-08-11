class_name RumbleCommandRouter
extends RefCounted

var prefix: String = "!"
var _commands: Dictionary = {}
var _aliases: Dictionary = {}
var _last_used_msec: Dictionary = {}


func register_command(name: String, callback: Callable, aliases: PackedStringArray = PackedStringArray(), cooldown_seconds: float = 0.0, required_badges: PackedStringArray = PackedStringArray()) -> RumbleApiError:
	var normalized := name.strip_edges().to_lower()
	if normalized.is_empty() or normalized.contains(" ") or not callback.is_valid():
		return RumbleApiError.invalid("Command name and callback must be valid")
	_commands[normalized] = {"callback": callback, "cooldown_msec": maxi(0, int(cooldown_seconds * 1000.0)), "required_badges": required_badges.duplicate()}
	for alias: String in aliases:
		var normalized_alias := alias.strip_edges().to_lower()
		if not normalized_alias.is_empty() and not normalized_alias.contains(" "):
			_aliases[normalized_alias] = normalized
	return null


func unregister_command(name: String) -> void:
	var normalized := name.to_lower()
	_commands.erase(normalized)
	for alias: Variant in _aliases.keys():
		if _aliases[alias] == normalized:
			_aliases.erase(alias)


func route(message: RumbleChatMessage) -> bool:
	if message == null or prefix.is_empty() or not message.text.begins_with(prefix):
		return false
	var content := message.text.substr(prefix.length()).strip_edges()
	if content.is_empty():
		return false
	var parts := content.split(" ", false)
	var name := parts[0].to_lower()
	name = str(_aliases.get(name, name))
	if not _commands.has(name):
		return false
	var command: Dictionary = _commands[name]
	for required: String in command.required_badges:
		if not message.badges.has(required):
			return false
	var cooldown_msec := int(command.cooldown_msec)
	var key := "%s:%s" % [name, message.username.to_lower()]
	var now := Time.get_ticks_msec()
	if now - int(_last_used_msec.get(key, -cooldown_msec)) < cooldown_msec:
		return false
	_last_used_msec[key] = now
	var arguments := PackedStringArray()
	for index: int in range(1, parts.size()):
		arguments.append(parts[index])
	(command.callback as Callable).call(arguments, message)
	return true


func clear() -> void:
	_commands.clear()
	_aliases.clear()
	_last_used_msec.clear()

class_name RumbleStateStore
extends RefCounted

const DEFAULT_DIRECTORY: String = "user://redot-rumbler/state"

var _base_directory: String


func _init(base_directory: String = DEFAULT_DIRECTORY) -> void:
	_base_directory = base_directory.trim_suffix("/")


func save(session_slot: String, state: Dictionary) -> RumbleApiError:
	var path := path_for_slot(session_slot)
	if path.is_empty():
		return RumbleApiError.invalid("Invalid Rumbler session slot")
	var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_base_directory))
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return RumbleApiError.from_transport(directory_error, "Unable to create the Rumbler state directory")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return RumbleApiError.from_transport(FileAccess.get_open_error(), "Unable to write bounded Rumbler state")
	file.store_string(JSON.stringify(state, "  ") + "\n")
	file.close()
	return null


func load_state(session_slot: String) -> Dictionary:
	var path := path_for_slot(session_slot)
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return {}
	for key: String in ["streams", "counters"]:
		if parsed.get(key) is Dictionary:
			_restore_integers(parsed[key])
	return parsed


func delete_state(session_slot: String) -> RumbleApiError:
	var path := path_for_slot(session_slot)
	if path.is_empty():
		return RumbleApiError.invalid("Invalid Rumbler session slot")
	if not FileAccess.file_exists(path):
		return null
	var remove_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return null if remove_error == OK else RumbleApiError.from_transport(remove_error, "Unable to delete bounded Rumbler state")


func path_for_slot(session_slot: String) -> String:
	return "%s/%s.json" % [_base_directory, session_slot] if RumbleClientConfig.valid_session_slot(session_slot) else ""


func _restore_integers(values: Dictionary) -> void:
	for key: Variant in values:
		var value: Variant = values[key]
		if value is Dictionary:
			_restore_integers(value)
		elif value is float and is_finite(value) and value == floorf(value):
			values[key] = int(value)

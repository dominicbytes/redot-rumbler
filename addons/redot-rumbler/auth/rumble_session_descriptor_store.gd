class_name RumbleSessionDescriptorStore
extends RefCounted

## Adapted from redot-kicker commit 72a3abb747cac0e148352c04a88a53e0313bd72b,
## whose generic descriptor store derives from redot-tuber (MIT).
const DEFAULT_DIRECTORY: String = "user://redot-rumbler/sessions"

var _base_directory: String


func _init(base_directory: String = DEFAULT_DIRECTORY) -> void:
	_base_directory = base_directory.trim_suffix("/")


func path_for_slot(session_slot: String) -> String:
	return "%s/%s.json" % [_base_directory, session_slot] if RumbleClientConfig.valid_session_slot(session_slot) else ""


func save(descriptor: RumbleSessionDescriptor) -> RumbleApiError:
	if descriptor == null:
		return RumbleApiError.invalid("Session descriptor is required")
	var path := path_for_slot(descriptor.session_slot)
	if path.is_empty() or descriptor.credential_target.is_empty():
		return RumbleApiError.invalid("Session slot and credential target are required")
	var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_base_directory))
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return RumbleApiError.from_transport(directory_error, "Unable to create the Rumbler session directory")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return RumbleApiError.from_transport(FileAccess.get_open_error(), "Unable to write the non-secret Rumbler session descriptor")
	file.store_string(JSON.stringify(descriptor.to_dictionary(), "  ") + "\n")
	file.close()
	return null


func load_descriptor(session_slot: String) -> RumbleSessionDescriptorLoadResult:
	var result := RumbleSessionDescriptorLoadResult.new()
	var path := path_for_slot(session_slot)
	if path.is_empty():
		result.error = RumbleApiError.invalid("Invalid session slot")
		return result
	if not FileAccess.file_exists(path):
		result.error = RumbleApiError.custom("not_found", "No saved Rumbler session exists for this slot")
		return result
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		result.error = RumbleApiError.custom("corrupt_state", "Saved Rumbler session descriptor is corrupt")
		return result
	result.descriptor = RumbleSessionDescriptor.from_dictionary(parsed)
	if result.descriptor == null or result.descriptor.session_slot != session_slot:
		result.descriptor = null
		result.error = RumbleApiError.custom("corrupt_state", "Saved Rumbler descriptor has an unsupported schema or slot")
	return result


func delete_descriptor(session_slot: String) -> RumbleApiError:
	var path := path_for_slot(session_slot)
	if path.is_empty():
		return RumbleApiError.invalid("Invalid session slot")
	if not FileAccess.file_exists(path):
		return null
	var remove_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return null if remove_error == OK else RumbleApiError.from_transport(remove_error, "Unable to delete the Rumbler session descriptor")

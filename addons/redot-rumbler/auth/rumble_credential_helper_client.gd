class_name RumbleCredentialHelperClient
extends RefCounted

## Adapted from redot-kicker commit 72a3abb747cac0e148352c04a88a53e0313bd72b,
## whose generic helper client derives from redot-tuber (MIT).
const DEFAULT_TIMEOUT_MSEC: int = 15000
const MAX_RESPONSE_BYTES: int = 16 * 1024
const HelperPaths = preload("res://addons/redot-rumbler/auth/credential_helper_paths.gd")

var helper_path_override: String = ""
var timeout_msec: int = DEFAULT_TIMEOUT_MSEC
var _protocol := RumbleCredentialProtocol.new()


func ping(cancellation: RumbleCancellationToken = null) -> RumbleCredentialResult:
	return await _invoke("ping", "", "", cancellation)


func store(target: String, secret: String, cancellation: RumbleCancellationToken = null) -> RumbleCredentialResult:
	if target.is_empty() or secret.is_empty():
		return _error_result("protocol_error", "Credential target and Rumble API URL are required")
	return await _invoke("store", target, secret, cancellation)


func read(target: String, cancellation: RumbleCancellationToken = null) -> RumbleCredentialResult:
	if target.is_empty():
		return _error_result("protocol_error", "Credential target is required")
	return await _invoke("read", target, "", cancellation)


func delete(target: String, cancellation: RumbleCancellationToken = null) -> RumbleCredentialResult:
	if target.is_empty():
		return _error_result("protocol_error", "Credential target is required")
	return await _invoke("delete", target, "", cancellation)


func resolved_helper_path() -> String:
	if not helper_path_override.is_empty():
		return ProjectSettings.globalize_path(helper_path_override) if helper_path_override.begins_with("res://") else helper_path_override
	return HelperPaths.runtime_path(OS.has_feature("editor"), OS.get_name(), Engine.get_architecture_name(), OS.get_executable_path())


func _invoke(command: String, target: String, secret: String, cancellation: RumbleCancellationToken) -> RumbleCredentialResult:
	var helper_path := resolved_helper_path()
	if helper_path.is_empty() or not FileAccess.file_exists(helper_path):
		return _error_result("unavailable", "Credential helper is unavailable for this operating system and architecture")
	var request_wire := _protocol.encode_request(command, target, secret)
	secret = ""
	if request_wire.is_empty():
		return _error_result("protocol_error", "Credential helper request is invalid")
	var process := OS.execute_with_pipe(helper_path, PackedStringArray(), false)
	var stdio: FileAccess = process.get("stdio", null)
	var stderr: FileAccess = process.get("stderr", null)
	var pid := int(process.get("pid", -1))
	if stdio == null or pid <= 0:
		_close_pipe(stdio)
		_close_pipe(stderr)
		return _error_result("unavailable", "Credential helper could not be started")
	stdio.store_string(request_wire)
	stdio.flush()
	request_wire = ""
	var deadline := Time.get_ticks_msec() + clampi(timeout_msec, 1000, 60000)
	while OS.is_process_running(pid):
		if cancellation != null and cancellation.is_cancelled():
			OS.kill(pid)
			_close_pipe(stdio)
			_close_pipe(stderr)
			return _error_result("cancelled", "Credential operation was cancelled")
		if Time.get_ticks_msec() >= deadline:
			OS.kill(pid)
			_close_pipe(stdio)
			_close_pipe(stderr)
			return _error_result("unavailable", "Credential helper timed out")
		await (Engine.get_main_loop() as SceneTree).process_frame
	var exit_code := OS.get_process_exit_code(pid)
	var response_wire := stdio.get_as_text()
	_close_pipe(stdio)
	_close_pipe(stderr)
	if response_wire.to_utf8_buffer().size() > MAX_RESPONSE_BYTES:
		return _error_result("protocol_error", "Credential helper response exceeded the protocol limit")
	var result := _protocol.decode_response(response_wire)
	response_wire = ""
	if result.status == "protocol_error" and exit_code != 0:
		result.detail = "helper exited without a valid response"
	return result


func _error_result(status: String, message: String) -> RumbleCredentialResult:
	var result := RumbleCredentialResult.new()
	result.status = status
	result.error = RumbleApiError.custom(status, message)
	return result


func _close_pipe(file: FileAccess) -> void:
	if file != null:
		file.close()

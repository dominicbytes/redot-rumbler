extends SceneTree

class MockCredentialClient:
	extends RefCounted
	var values: Dictionary = {}

	func store(target: String, secret: String, _cancellation: RumbleCancellationToken = null) -> RumbleCredentialResult:
		values[target] = secret
		return _result("ok")

	func read(target: String, _cancellation: RumbleCancellationToken = null) -> RumbleCredentialResult:
		if not values.has(target):
			return _result("not_found")
		var result := _result("ok")
		result.secret = str(values[target])
		return result

	func delete(target: String, _cancellation: RumbleCancellationToken = null) -> RumbleCredentialResult:
		var existed := values.erase(target)
		return _result("ok" if existed else "not_found")

	func _result(status: String) -> RumbleCredentialResult:
		var result := RumbleCredentialResult.new()
		result.status = status
		return result


var _checks: int = 0
var _failures: PackedStringArray = PackedStringArray()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	_test_contract_and_policy()
	_test_protocol_and_redaction()
	_test_command_router()
	await _test_client_persistence_and_isolation()
	_finish()


func _test_contract_and_policy() -> void:
	var contract: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://addons/redot-rumbler/contracts/rumble_api_contract.json"))
	_check(contract.platform_api_version == "1.1" and contract.fields.size() == 40, "frozen contract covers all documented v1.1 field groups")
	_check(contract.transport.recent_chat_and_rant_limit == 50 and contract.transport.read_only, "source limit and read-only boundary are frozen")
	_check(RumbleCapabilityRegistry.status("chat.read") == "SUPPORTED", "inbound chat is supported")
	_check(RumbleCapabilityRegistry.status("chat.write") == "UNAVAILABLE", "outbound chat is explicitly unavailable")
	_check(RumbleCapabilityRegistry.status("moderation") == "UNAVAILABLE" and RumbleCapabilityRegistry.status("media.download") == "UNAVAILABLE", "moderation and speculative media remain unavailable")
	_check(RumbleUrlPolicy.validate_api_url("https://rumble.com/example") == null, "official HTTPS Rumble URL passes validation")
	_check(RumbleUrlPolicy.validate_api_url("https://rumble.com.evil.example/path") != null, "lookalike host is rejected")
	_check(RumbleUrlPolicy.validate_api_url("http://rumble.com/example") != null, "plaintext platform URL is rejected")
	var malformed_urls: Array[String] = [
		"https://rumble.com:/-livestream-api/get-data?key=SECRETKEY1",
		"https://rumble.com:99999/-livestream-api/get-data?key=SECRETKEY1",
		"https://rumble.com:443 /-livestream-api/get-data?key=SECRETKEY1",
		"https://rumble.com:0/path?key=SECRETKEY1",
		"https://rumble.com:abc/path?key=SECRETKEY1",
		"https://rumble.com/path?key=SECRETKEY1 value",
		"https://rumble.com/path?key=SECRETKEY1\t",
		"https://rumble.com/path?key=SECRETKEY1" + String.chr(1),
		"https://rumble.com/path?key=SECRETKEY1" + String.chr(127),
		"https://rumble.com/path?key=SECRETKEY1" + String.chr(160),
		"https://user@rumble.com/path?key=SECRETKEY1",
	]
	for url: String in malformed_urls:
		var error := RumbleUrlPolicy.validate_api_url(url)
		_check(error != null, "malformed secret URL rejected before engine parsing")
		if error != null:
			_check(not error.message.contains("SECRETKEY1"), "validation error contains no credential")
	_check(RumbleUrlPolicy.validate_api_url("https://api.rumble.com:443/path?key=SECRETKEY1") == null, "valid explicit HTTPS port remains supported")
	_check(RumbleUrlPolicy.validate_api_url("https://rumble.com:65535/path") == null, "maximum valid port is supported")
	_check(is_equal_approx(RumblePollPolicy.interval(0.5), 2.0), "poll interval enforces the two-second floor")
	_check(is_equal_approx(RumblePollPolicy.backoff(1, 0.0), 2.0) and RumblePollPolicy.backoff(10, 1.0) <= 60.0, "backoff is exponential, jitter-bounded, and capped")
	_check(is_equal_approx(RumblePollPolicy.backoff(1, 0.0, 12.0), 12.0), "server retry metadata wins over shorter backoff")


func _test_protocol_and_redaction() -> void:
	var protocol := RumbleCredentialProtocol.new()
	var wire := protocol.encode_request("store", "publisher/app/primary", "SYNTHETIC-CREDENTIAL")
	var decoded := protocol.decode_request_for_test(wire)
	_check(decoded.command == "store" and decoded.target == "publisher/app/primary" and decoded.secret == "SYNTHETIC-CREDENTIAL", "RRCH/1 round-trips bounded UTF-8 fields over stdin")
	_check(protocol.decode_response("RKCH/1\nOK\n\nwrong\n").status == "protocol_error", "Kicker credential protocol is rejected")
	var safe: Variant = RumbleRedactor.sanitize_variant({"stream_key": "remove", "nested": {"access_token": "remove", "is_live": true}})
	_check(not safe.has("stream_key") and not safe.nested.has("access_token") and safe.nested.is_live, "recursive sanitizer removes credential fields before mapping")
	var redacted := RumbleRedactor.redact_text("request failed for https://rumble.com/example?private=value")
	_check(not redacted.contains("private=value") and redacted.contains("<redacted-url>"), "diagnostic text removes complete URLs")
	var descriptor := RumbleSessionDescriptor.new()
	descriptor.session_slot = "primary"
	descriptor.credential_target = "publisher/app/primary"
	descriptor.publisher_id = "publisher"
	descriptor.application_id = "app"
	_check(not JSON.stringify(descriptor.to_dictionary()).contains("https://"), "non-secret descriptor schema has no API URL field")


func _test_command_router() -> void:
	var calls: Array = []
	var router := RumbleCommandRouter.new()
	var registration := router.register_command("spawn", func(arguments: PackedStringArray, message: RumbleChatMessage) -> void: calls.append({"arguments": arguments, "user": message.username}), PackedStringArray(["s"]), 30.0, PackedStringArray(["premium"]))
	_check(registration == null, "local inbound command registers with alias, cooldown, and badges")
	var message := RumbleChatMessage.new()
	message.username = "Viewer"
	message.badges = PackedStringArray(["premium"])
	message.text = "!s dragon 2"
	_check(router.route(message) and calls.size() == 1 and calls[0].arguments == PackedStringArray(["dragon", "2"]), "authorized alias routes parsed arguments locally")
	_check(not router.route(message), "per-user command cooldown suppresses immediate replay")
	var denied := RumbleChatMessage.new()
	denied.username = "Other"
	denied.text = "!spawn dragon"
	_check(not router.route(denied), "required Rumble badges gate local commands")
	_check(calls.size() == 1, "command routing never fabricates an outbound response")


func _test_client_persistence_and_isolation() -> void:
	RumbleSessionSlotRegistry.clear_for_tests()
	var credentials := MockCredentialClient.new()
	var descriptors := RumbleSessionDescriptorStore.new("res://.test-output/core/sessions")
	var states := RumbleStateStore.new("res://.test-output/core/state")
	var config := RumbleClientConfig.new()
	config.publisher_id = "fixture-publisher"
	config.application_id = "fixture-app"
	config.poll_interval_seconds = 1.0
	var client := RumbleLiveClient.new()
	root.add_child(client)
	_check(client.configure(config, "primary", credentials, descriptors, states) == null, "client configures one stable application/session slot")
	_check(is_equal_approx(config.poll_interval_seconds, 2.0), "client configuration applies the polling floor")
	var conflict := RumbleLiveClient.new()
	root.add_child(conflict)
	_check(conflict.configure(config, "primary", credentials, descriptors, states) != null, "two live clients cannot acquire the same qualified slot")
	conflict.queue_free()
	var connected_error := await client.connect_api_url("https://rumble.com/example")
	_check(connected_error == null and client.has_loaded_credential(), "runtime connection stores the URL only through the credential boundary")
	var target := config.credential_target("primary")
	_check(credentials.values.has(target), "mock vault receives the credential under a namespaced target")
	var descriptor_text := FileAccess.get_file_as_string(descriptors.path_for_slot("primary"))
	_check(not descriptor_text.contains("https://") and not descriptor_text.contains("example"), "saved descriptor contains no API URL or path")
	client.queue_free()
	await process_frame

	var restored := RumbleLiveClient.new()
	root.add_child(restored)
	_check(restored.configure(config, "primary", credentials, descriptors, states) == null, "released slot can be acquired after restart")
	credentials.values[target] = "https://rumble.com:/-livestream-api/get-data?key=SECRETKEY1"
	var invalid_restore := await restored.restore_connection()
	_check(invalid_restore != null and invalid_restore.category == "corrupt_credential", "restore refuses malformed persisted URL")
	_check(not restored.has_loaded_credential() and not invalid_restore.message.contains("SECRETKEY1"), "invalid restore loads no URL and returns a redacted error")
	credentials.values[target] = "https://rumble.com/example"
	var restore_error := await restored.restore_connection()
	_check(restore_error == null and restored.has_loaded_credential(), "saved vault credential restores without exposing it through the descriptor")
	var clear_error := await restored.clear_local_data()
	_check(clear_error == null and not restored.has_loaded_credential(), "clear-data removes loaded credential and state")
	_check(not credentials.values.has(target) and not FileAccess.file_exists(descriptors.path_for_slot("primary")) and not FileAccess.file_exists(states.path_for_slot("primary")), "clear-data deletes vault, descriptor, and bounded hash state")
	restored.queue_free()
	await process_frame


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS: " + label)
	else:
		_failures.append(label)


func _finish() -> void:
	if _failures.is_empty():
		print("REDOT RUMBLER CORE SUITE PASS: %d checks" % _checks)
		quit(0)
		return
	for failure: String in _failures:
		push_error("REDOT RUMBLER CORE SUITE FAIL: " + failure)
	print("REDOT RUMBLER CORE SUITE FAILED: %d of %d checks" % [_failures.size(), _checks])
	quit(1)

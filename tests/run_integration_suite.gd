extends SceneTree

var _checks: int = 0
var _failures: PackedStringArray = PackedStringArray()
var _server: TCPServer = null
var _peers: Array[Dictionary] = []
var _serving: bool = false
var _status_code: int = 200
var _body: String = "{}"
var _extra_headers: PackedStringArray = PackedStringArray()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	_server = TCPServer.new()
	var listen_error := _server.listen(0, "127.0.0.1")
	_check(listen_error == OK, "client integration loopback server binds")
	if listen_error != OK:
		_finish()
		return
	_serving = true
	call_deferred("_server_loop")
	var config := RumbleClientConfig.new()
	config.publisher_id = "integration-publisher"
	config.application_id = "integration-app"
	var transport := RumbleHttpTransport.new()
	transport.allow_loopback_http_for_tests = true
	var client := RumbleLiveClient.new()
	root.add_child(client)
	var descriptors := RumbleSessionDescriptorStore.new("res://.test-output/integration/sessions")
	var states := RumbleStateStore.new("res://.test-output/integration/state")
	_check(client.configure(config, "primary", null, descriptors, states, transport) == null, "client configures with deterministic transport injection")
	client.connected_descriptor = RumbleSessionDescriptor.new()
	client.connected_descriptor.session_slot = "primary"
	client.connected_descriptor.credential_target = config.credential_target("primary")
	client.connected_descriptor.publisher_id = config.publisher_id
	client.connected_descriptor.application_id = config.application_id
	client._api_url = _url()
	var snapshots: Array[RumbleSnapshot] = []
	var chats: Array[RumbleChatMessage] = []
	var rants: Array[RumbleRantEvent] = []
	var transitions: Array[RumbleStreamTransition] = []
	client.snapshot_updated.connect(func(value: RumbleSnapshot) -> void: snapshots.append(value))
	client.chat_message_received.connect(func(value: RumbleChatMessage) -> void: chats.append(value))
	client.rant_received.connect(func(value: RumbleRantEvent) -> void: rants.append(value))
	client.stream_started.connect(func(value: RumbleStreamTransition) -> void: transitions.append(value))
	client.stream_updated.connect(func(value: RumbleStreamTransition) -> void: transitions.append(value))
	client.stream_ended.connect(func(value: RumbleStreamTransition) -> void: transitions.append(value))

	_set_response(200, FileAccess.get_file_as_string("res://tests/fixtures/ms001/baseline.json"))
	_check(await client.poll_once() == null, "client accepts first valid loopback poll")
	_check(snapshots.size() == 1 and chats.is_empty() and rants.is_empty(), "client emits snapshot but no historical events on baseline")
	_set_response(200, FileAccess.get_file_as_string("res://tests/fixtures/ms001/update.json"))
	_check(await client.poll_once() == null, "client accepts overlapping update poll")
	_check(chats.size() == 1 and chats[0].text == "new" and rants.size() == 1, "client emits each new chat and rant exactly once")
	_check(transitions.size() == 2, "client emits new and updated livestream transitions")
	var last_good := client.last_snapshot
	_set_response(503, "{\"error\":\"synthetic\"}", PackedStringArray(["Retry-After: 4"]))
	var server_error := await client.poll_once()
	_check(server_error != null and server_error.category == "server" and server_error.transient, "client classifies 5xx response for bounded backoff")
	_check(client.last_snapshot == last_good, "HTTP failure does not replace the last good snapshot")
	_set_response(200, FileAccess.get_file_as_string("res://tests/fixtures/ms001/malformed.json"))
	var parse_error := await client.poll_once()
	_check(parse_error != null and parse_error.category == "parse" and parse_error.transient, "client classifies malformed JSON for bounded backoff")
	_check(client.last_snapshot == last_good, "parse failure does not replace the last good snapshot")
	_set_response(200, FileAccess.get_file_as_string("res://tests/fixtures/ms001/update.json"))
	_check(await client.poll_once() == null and chats.size() == 1 and rants.size() == 1, "recovery poll emits no duplicates")
	_set_response(200, FileAccess.get_file_as_string("res://tests/fixtures/ms001/offline.json"))
	_check(await client.poll_once() == null, "client accepts documented offline shape")
	_check(transitions.size() == 4 and transitions[-1].kind == "ended" and transitions[-1].uncertain, "offline disappearance remains explicit and uncertain")
	_check(client.diagnostic_summary().fingerprint_count > 0 and client.diagnostic_summary().credential == "loaded", "safe diagnostics expose health and bounded counts without URL material")

	client.stop_polling("integration_complete")
	client.queue_free()
	await process_frame
	states.delete_state("primary")
	descriptors.delete_descriptor("primary")
	_serving = false
	_close_server()
	_finish()


func _server_loop() -> void:
	while _serving:
		_service_server()
		await process_frame


func _set_response(status_code: int, body: String, extra_headers: PackedStringArray = PackedStringArray()) -> void:
	_status_code = status_code
	_body = body
	_extra_headers = extra_headers


func _service_server() -> void:
	while _server != null and _server.is_connection_available():
		_peers.append({"peer": _server.take_connection(), "request": "", "responded": false})
	for item: Dictionary in _peers:
		if bool(item.responded):
			continue
		var peer: StreamPeerTCP = item.peer
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			continue
		var available := peer.get_available_bytes()
		if available > 0:
			item.request = str(item.request) + peer.get_utf8_string(available)
		if not str(item.request).contains("\r\n\r\n"):
			continue
		var body_bytes := _body.to_utf8_buffer()
		var reason := "OK" if _status_code == 200 else "Service Unavailable"
		var header := "HTTP/1.1 %d %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\n" % [_status_code, reason, body_bytes.size()]
		for line: String in _extra_headers:
			header += line + "\r\n"
		header += "Connection: close\r\n\r\n"
		peer.put_data(header.to_utf8_buffer())
		peer.put_data(body_bytes)
		peer.disconnect_from_host()
		item.responded = true


func _url() -> String:
	return "http://127.0.0.1:%d/fixture" % _server.get_local_port()


func _close_server() -> void:
	for item: Dictionary in _peers:
		var peer: StreamPeerTCP = item.peer
		if peer != null:
			peer.disconnect_from_host()
	_peers.clear()
	if _server != null:
		_server.stop()
	_server = null


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS: " + label)
	else:
		_failures.append(label)


func _finish() -> void:
	if _failures.is_empty():
		print("REDOT RUMBLER INTEGRATION SUITE PASS: %d checks" % _checks)
		quit(0)
		return
	for failure: String in _failures:
		push_error("REDOT RUMBLER INTEGRATION SUITE FAIL: " + failure)
	quit(1)

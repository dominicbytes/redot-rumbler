extends SceneTree

const MAX_FRAMES: int = 800

var _checks: int = 0
var _failures: PackedStringArray = PackedStringArray()
var _server: TCPServer = null
var _peers: Array[Dictionary] = []
var _path_counts: Dictionary = {}
var _release_slow: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	_server = TCPServer.new()
	var listen_error := _server.listen(0, "127.0.0.1")
	_check(listen_error == OK, "loopback HTTP fixture binds IPv4")
	if listen_error != OK:
		_finish()
		return
	var transport := RumbleHttpTransport.new()
	transport.allow_loopback_http_for_tests = true
	transport.timeout_seconds = 1.0
	transport.response_body_limit_bytes = 64 * 1024
	root.add_child(transport)
	await _test_success(transport)
	await _test_single_flight(transport)
	await _test_status_and_redirect_policy(transport)
	await _test_cancellation(transport)
	await _test_limits(transport)
	transport.queue_free()
	_close_server()
	await process_frame
	_finish()


func _test_success(transport: RumbleHttpTransport) -> void:
	var starts: Array[int] = []
	var capture := func(ticket_id: int) -> void: starts.append(ticket_id)
	transport.request_started.connect(capture)
	var ticket := transport.request(_url("/ok"))
	await _drive_until_completed([ticket])
	transport.request_started.disconnect(capture)
	_check(ticket.response != null and ticket.response.is_success(), "single-flight transport completes a JSON GET")
	_check(ticket.response.body.get_string_from_utf8().contains("\"ok\":true"), "successful response preserves bounded body bytes")
	_check(starts == [ticket.id], "request diagnostics expose only a ticket ID, never the credential URL")
	_check(ticket.response.header("x-fixture") == "yes", "typed response exposes safe header metadata")


func _test_single_flight(transport: RumbleHttpTransport) -> void:
	_release_slow = false
	var first := transport.request(_url("/slow"))
	for _frame: int in 10:
		_service_server()
		await process_frame
	var second := transport.request(_url("/ok"))
	_check(transport.active_count() == 1, "one client permits only one in-flight request")
	_check(second.is_completed and second.response.error.category == "busy", "overlapping poll fails immediately with a typed busy error")
	_release_slow = true
	await _drive_until_completed([first])
	_check(first.response.is_success() and transport.active_count() == 0, "active slot is released after completion")


func _test_status_and_redirect_policy(transport: RumbleHttpTransport) -> void:
	var limited := transport.request(_url("/rate"))
	await _drive_until_completed([limited])
	_check(limited.response.status_code == 429 and limited.response.error.category == "rate_limited", "HTTP 429 maps to a typed transient rate-limit error")
	_check(is_equal_approx(limited.response.error.retry_after_seconds, 7.0), "Retry-After metadata reaches the poll policy")
	var redirect := transport.request(_url("/redirect"))
	await _drive_until_completed([redirect])
	_check(redirect.response.status_code == 302 and redirect.response.error != null, "redirects are returned as errors instead of being followed")
	_check(int(_path_counts.get("/redirect", 0)) == 1, "redirect fixture receives exactly one request")


func _test_cancellation(transport: RumbleHttpTransport) -> void:
	_release_slow = false
	var cancellation := RumbleCancellationToken.new()
	var ticket := transport.request(_url("/slow"), cancellation)
	for _frame: int in 10:
		_service_server()
		await process_frame
	cancellation.cancel("fixture stop")
	await _drive_until_completed([ticket])
	_check(ticket.is_cancelled and ticket.cancellation_reason == "fixture stop", "active cancellation is typed and keeps a safe reason")
	_check(ticket.response.error.category == "cancelled" and transport.active_count() == 0, "cancelled request releases the single-flight slot")
	_release_slow = true


func _test_limits(transport: RumbleHttpTransport) -> void:
	var oversized := transport.request(_url("/oversized"))
	await _drive_until_completed([oversized])
	_check(oversized.response.request_result == HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED, "oversized response is rejected by the engine body limit")
	var insecure := transport.request("http://example.com/unsafe")
	_check(insecure.is_completed and insecure.response.error.category == "invalid_request", "non-loopback plaintext HTTP is rejected before network access")
	var offsite := transport.request("https://example.com/unsafe")
	_check(offsite.is_completed and offsite.response.error.category == "invalid_request", "non-Rumble HTTPS host is rejected before network access")


func _drive_until_completed(tickets: Array, max_frames: int = MAX_FRAMES) -> void:
	for _frame: int in max_frames:
		_service_server()
		var complete := true
		for ticket: RumbleHttpTicket in tickets:
			if not ticket.is_completed:
				complete = false
				break
		if complete:
			return
		await process_frame
	_failures.append("timed out waiting for HTTP fixture")


func _service_server() -> void:
	while _server != null and _server.is_connection_available():
		_peers.append({"peer": _server.take_connection(), "request": "", "responded": false, "path": ""})
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
		if str(item.path).is_empty():
			var first_line := str(item.request).split("\r\n", false)[0]
			var parts := first_line.split(" ", false)
			var target := parts[1] if parts.size() >= 2 else "/invalid"
			item.path = target.split("?", false)[0]
			_path_counts[item.path] = int(_path_counts.get(item.path, 0)) + 1
		var path: String = item.path
		if path == "/slow" and not _release_slow:
			continue
		match path:
			"/rate": _send(peer, 429, "Too Many Requests", "application/json", "{\"error\":\"rate\"}".to_utf8_buffer(), PackedStringArray(["Retry-After: 7"]))
			"/redirect": _send(peer, 302, "Found", "text/plain", PackedByteArray(), PackedStringArray(["Location: https://example.com/forbidden"]))
			"/oversized":
				var body := PackedByteArray()
				body.resize(128 * 1024)
				body.fill(65)
				_send(peer, 200, "OK", "application/octet-stream", body)
			_: _send(peer, 200, "OK", "application/json", "{\"ok\":true}".to_utf8_buffer())
		item.responded = true


func _send(peer: StreamPeerTCP, status: int, reason: String, content_type: String, body: PackedByteArray, extra_headers: PackedStringArray = PackedStringArray()) -> void:
	var header := "HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nX-Fixture: yes\r\n" % [status, reason, content_type, body.size()]
	for line: String in extra_headers:
		header += line + "\r\n"
	header += "Connection: close\r\n\r\n"
	peer.put_data(header.to_utf8_buffer())
	if not body.is_empty():
		peer.put_data(body)
	peer.disconnect_from_host()


func _url(path: String) -> String:
	return "http://127.0.0.1:%d%s" % [_server.get_local_port(), path]


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
		print("REDOT RUMBLER HTTP TRANSPORT SUITE PASS: %d checks" % _checks)
		quit(0)
		return
	for failure: String in _failures:
		push_error("REDOT RUMBLER HTTP TRANSPORT SUITE FAIL: " + failure)
	print("REDOT RUMBLER HTTP TRANSPORT SUITE FAILED: %d of %d checks" % [_failures.size(), _checks])
	quit(1)

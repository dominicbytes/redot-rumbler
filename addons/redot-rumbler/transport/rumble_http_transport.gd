class_name RumbleHttpTransport
extends Node

signal request_started(ticket_id: int)
signal became_idle()

@export_range(2.0, 120.0, 0.5) var timeout_seconds: float = 20.0
@export_range(65536, 8388608, 1024) var response_body_limit_bytes: int = 2 * 1024 * 1024

var allow_loopback_http_for_tests: bool = false
var _next_ticket_id: int = 1
var _active: Dictionary = {}


func request(url: String, cancellation: RumbleCancellationToken = null) -> RumbleHttpTicket:
	var ticket := RumbleHttpTicket.new()
	ticket.id = _next_ticket_id
	_next_ticket_id += 1
	var validation_error := RumbleUrlPolicy.validate_api_url(url, allow_loopback_http_for_tests)
	if validation_error != null:
		_complete_immediate(ticket, validation_error)
		return ticket
	if not _active.is_empty():
		_complete_immediate(ticket, RumbleApiError.custom("busy", "Only one Rumble poll may be in flight per client"))
		return ticket
	var http := HTTPRequest.new()
	http.name = "RumbleHttpRequest%d" % ticket.id
	http.timeout = clampf(timeout_seconds, 2.0, 120.0)
	http.body_size_limit = clampi(response_body_limit_bytes, 64 * 1024, 8 * 1024 * 1024)
	http.max_redirects = 0
	http.accept_gzip = true
	http.use_threads = false
	add_child(http)
	_active[ticket.id] = {"ticket": ticket, "http": http, "started_at": Time.get_ticks_msec(), "cancellation": cancellation}
	http.request_completed.connect(_on_request_completed.bind(ticket.id), CONNECT_ONE_SHOT)
	if cancellation != null:
		cancellation.cancelled.connect(_on_cancel_requested.bind(ticket.id), CONNECT_ONE_SHOT)
		if cancellation.is_cancelled():
			_on_cancel_requested(cancellation.reason(), ticket.id)
			return ticket
	request_started.emit(ticket.id)
	var start_error := http.request(url, PackedStringArray(["Accept: application/json", "User-Agent: Redot-Rumbler/0.1"]), HTTPClient.METHOD_GET)
	if start_error != OK:
		_active.erase(ticket.id)
		http.queue_free()
		var start_failure := RumbleApiError.from_transport(start_error, "Unable to start Rumble Live Stream API request")
		start_failure.transient = true
		_complete_immediate(ticket, start_failure)
	return ticket


func cancel_active(reason: String = "transport stopped") -> void:
	for ticket_id: Variant in _active.keys():
		_on_cancel_requested(reason, int(ticket_id))


func active_count() -> int:
	return _active.size()


func _on_request_completed(result: int, status_code: int, headers: PackedStringArray, body: PackedByteArray, ticket_id: int) -> void:
	if not _active.has(ticket_id):
		return
	var item: Dictionary = _active[ticket_id]
	_active.erase(ticket_id)
	var http: HTTPRequest = item.http
	if is_instance_valid(http):
		http.queue_free()
	var ticket: RumbleHttpTicket = item.ticket
	if ticket.is_completed:
		_emit_idle()
		return
	var response := RumbleHttpResponse.new()
	response.request_result = result
	response.status_code = status_code
	response.headers = headers
	response.body = body
	response.elapsed_msec = Time.get_ticks_msec() - int(item.started_at)
	if result != HTTPRequest.RESULT_SUCCESS:
		response.error = RumbleApiError.from_transport(result, "Rumble transport failed (result %d)" % result)
		response.error.transient = true
	elif status_code < 200 or status_code >= 300:
		response.error = RumbleApiError.from_http(status_code, response.retry_after_seconds())
	ticket._complete(response)
	_emit_idle()


func _on_cancel_requested(reason: String, ticket_id: int) -> void:
	if not _active.has(ticket_id):
		return
	var item: Dictionary = _active[ticket_id]
	_active.erase(ticket_id)
	var http: HTTPRequest = item.http
	if is_instance_valid(http):
		http.cancel_request()
		http.queue_free()
	var ticket: RumbleHttpTicket = item.ticket
	ticket._mark_cancelled(reason)
	var response := RumbleHttpResponse.new()
	response.error = RumbleApiError.from_transport(ERR_SKIP, "Rumble request cancelled")
	ticket._complete(response)
	_emit_idle()


func _complete_immediate(ticket: RumbleHttpTicket, error: RumbleApiError) -> void:
	var response := RumbleHttpResponse.new()
	response.error = error
	ticket._complete(response)


func _emit_idle() -> void:
	if _active.is_empty():
		became_idle.emit()


func _exit_tree() -> void:
	cancel_active("transport freed")

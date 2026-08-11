class_name RumbleLiveClient
extends Node

signal state_changed(previous: String, current: String, reason: String)
signal credential_connected(descriptor: RumbleSessionDescriptor, restored: bool)
signal credential_cleared()
signal snapshot_updated(snapshot: RumbleSnapshot)
signal chat_message_received(message: RumbleChatMessage)
signal rant_received(rant: RumbleRantEvent)
signal follower_received(follower: RumblePersonEvent)
signal subscriber_received(subscriber: RumblePersonEvent)
signal gifted_subscription_received(gift: RumbleGiftedSubscription)
signal stream_started(transition: RumbleStreamTransition)
signal stream_updated(transition: RumbleStreamTransition)
signal stream_ended(transition: RumbleStreamTransition)
signal counter_delta(counter: String, delta: int, current: int)
signal counter_reset(counter: String, previous: int, current: int)
signal possible_event_gap(details: Dictionary)
signal schema_warning(field_path: String)
signal retry_scheduled(attempt: int, delay_seconds: float, category: String)
signal error_occurred(error: RumbleApiError)

var connection_state: String = "unconfigured"
var connected_descriptor: RumbleSessionDescriptor = null
var last_snapshot: RumbleSnapshot = null
var last_success_unix: int = 0
var next_attempt_unix: int = 0
var consecutive_failures: int = 0

var _config: RumbleClientConfig = null
var _session_slot: String = ""
var _qualified_slot: String = ""
var _api_url: String = ""
var _credential_client: Variant = null
var _descriptor_store: Variant = null
var _state_store: Variant = null
var _transport: RumbleHttpTransport = null
var _parser := RumblePayloadParser.new()
var _differ := RumbleSnapshotDiffer.new()
var _cancellation: RumbleCancellationToken = null
var _generation: int = 0


func configure(
	config: RumbleClientConfig,
	session_slot: String,
	credential_client: Variant = null,
	descriptor_store: Variant = null,
	state_store: Variant = null,
	transport: RumbleHttpTransport = null
) -> RumbleApiError:
	if _config != null:
		return RumbleApiError.invalid("RumbleLiveClient is already configured")
	if config == null:
		return RumbleApiError.invalid("Rumble client configuration is required")
	var config_error := config.validate()
	if config_error != null:
		return config_error
	if not RumbleClientConfig.valid_session_slot(session_slot):
		return RumbleApiError.invalid("session_slot must use 1-64 letters, numbers, dots, underscores, or hyphens")
	var qualified := config.qualified_slot(session_slot)
	var slot_error := RumbleSessionSlotRegistry.acquire(qualified, self)
	if slot_error != null:
		return slot_error
	_config = config
	_session_slot = session_slot
	_qualified_slot = qualified
	_credential_client = credential_client if credential_client != null else RumbleCredentialHelperClient.new()
	_descriptor_store = descriptor_store if descriptor_store != null else RumbleSessionDescriptorStore.new()
	_state_store = state_store if state_store != null else RumbleStateStore.new()
	_transport = transport if transport != null else RumbleHttpTransport.new()
	if _transport.get_parent() == null:
		_transport.name = "RumbleHttpTransport"
		add_child(_transport)
	_transport.timeout_seconds = config.request_timeout_seconds
	_transport.response_body_limit_bytes = config.response_body_limit_bytes
	_differ.replay_history_on_first_poll = config.replay_history_on_first_poll
	var saved_state: Dictionary = _state_store.load_state(_session_slot)
	if not saved_state.is_empty():
		_differ.load_state(saved_state)
	_set_state("configured", "configuration_valid")
	return null


func connect_api_url(api_url: String) -> RumbleApiError:
	if _config == null:
		return RumbleApiError.invalid("Configure RumbleLiveClient before connecting")
	var validation_error := RumbleUrlPolicy.validate_api_url(api_url)
	if validation_error != null:
		return validation_error
	var target := _config.credential_target(_session_slot)
	var stored: RumbleCredentialResult = await _credential_client.store(target, api_url)
	if not stored.is_success():
		return stored.error
	var descriptor := _new_descriptor(target)
	var save_error: RumbleApiError = _descriptor_store.save(descriptor)
	if save_error != null:
		await _credential_client.delete(target)
		return save_error
	_api_url = api_url
	connected_descriptor = descriptor
	_set_state("connected", "credential_stored")
	credential_connected.emit(connected_descriptor, false)
	return null


func restore_connection() -> RumbleApiError:
	if _config == null:
		return RumbleApiError.invalid("Configure RumbleLiveClient before restoring")
	var loaded: RumbleSessionDescriptorLoadResult = _descriptor_store.load_descriptor(_session_slot)
	if not loaded.is_success():
		return loaded.error
	var descriptor := loaded.descriptor
	var expected_target := _config.credential_target(_session_slot)
	if descriptor.publisher_id != _config.publisher_id or descriptor.application_id != _config.application_id or descriptor.credential_target != expected_target:
		return RumbleApiError.custom("corrupt_state", "Saved Rumbler descriptor does not match this application and slot")
	var read: RumbleCredentialResult = await _credential_client.read(expected_target)
	if not read.is_success():
		return read.error
	var validation_error := RumbleUrlPolicy.validate_api_url(read.secret)
	if validation_error != null:
		read.clear_secret()
		return RumbleApiError.custom("corrupt_credential", "Saved Rumble credential is invalid")
	_api_url = read.secret
	read.clear_secret()
	connected_descriptor = descriptor
	_config.poll_interval_seconds = descriptor.poll_interval_seconds
	_config.replay_history_on_first_poll = descriptor.replay_history_on_first_poll
	_differ.replay_history_on_first_poll = descriptor.replay_history_on_first_poll
	_set_state("connected", "credential_restored")
	credential_connected.emit(connected_descriptor, true)
	return null


func start_polling() -> RumbleApiError:
	if _api_url.is_empty() or connected_descriptor == null:
		return RumbleApiError.custom("credential", "Connect or restore a Rumble API credential before polling")
	if connection_state in ["polling", "backoff"]:
		return null
	_generation += 1
	_cancellation = RumbleCancellationToken.new()
	consecutive_failures = 0
	_set_state("polling", "polling_started")
	call_deferred("_poll_loop", _generation)
	return null


func stop_polling(reason: String = "requested") -> void:
	_generation += 1
	if _cancellation != null:
		_cancellation.cancel(reason)
	_cancellation = null
	if _transport != null:
		_transport.cancel_active(reason)
	next_attempt_unix = 0
	if connected_descriptor != null:
		_set_state("stopped", reason)


func poll_once() -> RumbleApiError:
	if _api_url.is_empty():
		return RumbleApiError.custom("credential", "No Rumble API credential is loaded")
	var ticket := _transport.request(_api_url, _cancellation)
	if not ticket.is_completed:
		await ticket.completed
	var response := ticket.response
	if response == null:
		return RumbleApiError.custom("transport", "Rumble request produced no response")
	if response.error != null:
		response.clear_body()
		return response.error
	var payload := response.body.get_string_from_utf8()
	response.clear_body()
	var parsed := _parser.parse_json(payload)
	payload = ""
	if not parsed.is_success():
		return parsed.error
	_apply_snapshot(parsed.snapshot)
	return null


func clear_local_data() -> RumbleApiError:
	stop_polling("clear_local_data")
	var first_error: RumbleApiError = null
	if _config != null:
		var target := _config.credential_target(_session_slot)
		var deleted: RumbleCredentialResult = await _credential_client.delete(target)
		if not deleted.is_success() and deleted.status != "not_found":
			first_error = deleted.error
		var descriptor_error: RumbleApiError = _descriptor_store.delete_descriptor(_session_slot)
		if first_error == null:
			first_error = descriptor_error
		var state_error: RumbleApiError = _state_store.delete_state(_session_slot)
		if first_error == null:
			first_error = state_error
	_api_url = ""
	connected_descriptor = null
	last_snapshot = null
	last_success_unix = 0
	consecutive_failures = 0
	_differ.clear()
	_set_state("configured", "local_data_cleared")
	credential_cleared.emit()
	return first_error


func disconnect_and_clear() -> RumbleApiError:
	return await clear_local_data()


func has_loaded_credential() -> bool:
	return not _api_url.is_empty()


func diagnostic_summary() -> Dictionary:
	return {
		"state": connection_state,
		"last_success_unix": last_success_unix,
		"next_attempt_unix": next_attempt_unix,
		"consecutive_failures": consecutive_failures,
		"fingerprint_count": _differ.fingerprint_count(),
		"credential": "loaded" if not _api_url.is_empty() else "not_loaded",
	}


func _poll_loop(generation: int) -> void:
	while generation == _generation and connection_state in ["polling", "backoff"]:
		var error := await poll_once()
		if generation != _generation:
			return
		var delay_seconds := RumblePollPolicy.interval(_config.poll_interval_seconds)
		if error == null:
			consecutive_failures = 0
			_set_state("polling", "poll_succeeded")
		else:
			consecutive_failures += 1
			error_occurred.emit(error)
			if not error.transient:
				_set_state("credential_error" if error.category in ["credential", "corrupt_credential"] else "stopped", error.category)
				return
			delay_seconds = RumblePollPolicy.backoff(consecutive_failures, randf(), error.retry_after_seconds)
			_set_state("backoff", error.category)
			retry_scheduled.emit(consecutive_failures, delay_seconds, error.category)
		next_attempt_unix = int(Time.get_unix_time_from_system() + delay_seconds)
		await get_tree().create_timer(delay_seconds).timeout
		next_attempt_unix = 0
		if generation == _generation and connection_state == "backoff":
			_set_state("polling", "retry_due")


func _apply_snapshot(snapshot: RumbleSnapshot) -> void:
	var changes := _differ.process(snapshot)
	last_snapshot = snapshot
	last_success_unix = int(Time.get_unix_time_from_system())
	var state_error: RumbleApiError = _state_store.save(_session_slot, _differ.state_dictionary())
	if state_error != null:
		error_occurred.emit(state_error)
	if connected_descriptor != null:
		connected_descriptor.response_type = snapshot.response_type
		connected_descriptor.user_id = snapshot.user_id
		connected_descriptor.channel_id = snapshot.channel_id
		connected_descriptor.poll_interval_seconds = _config.poll_interval_seconds
		connected_descriptor.replay_history_on_first_poll = _config.replay_history_on_first_poll
		var descriptor_error: RumbleApiError = _descriptor_store.save(connected_descriptor)
		if descriptor_error != null:
			error_occurred.emit(descriptor_error)
	snapshot_updated.emit(snapshot)
	for item: RumbleChatMessage in changes.chat_messages:
		chat_message_received.emit(item)
	for item: RumbleRantEvent in changes.rants:
		rant_received.emit(item)
	for item: RumblePersonEvent in changes.followers:
		follower_received.emit(item)
	for item: RumblePersonEvent in changes.subscribers:
		subscriber_received.emit(item)
	for item: RumbleGiftedSubscription in changes.gifted_subscriptions:
		gifted_subscription_received.emit(item)
	for transition: RumbleStreamTransition in changes.stream_transitions:
		match transition.kind:
			"started": stream_started.emit(transition)
			"ended": stream_ended.emit(transition)
			_: stream_updated.emit(transition)
	for counter_name: Variant in changes.counter_deltas:
		counter_delta.emit(str(counter_name), int(changes.counter_deltas[counter_name]), int(snapshot.counters().get(counter_name, 0)))
	for reset: Dictionary in changes.counter_resets:
		counter_reset.emit(str(reset.counter), int(reset.previous), int(reset.current))
	for gap: Dictionary in changes.possible_gaps:
		possible_event_gap.emit(gap)
	for path: String in changes.schema_warnings:
		schema_warning.emit(path)


func _new_descriptor(target: String) -> RumbleSessionDescriptor:
	var descriptor := RumbleSessionDescriptor.new()
	descriptor.session_slot = _session_slot
	descriptor.credential_target = target
	descriptor.publisher_id = _config.publisher_id
	descriptor.application_id = _config.application_id
	descriptor.poll_interval_seconds = _config.poll_interval_seconds
	descriptor.replay_history_on_first_poll = _config.replay_history_on_first_poll
	return descriptor


func _set_state(value: String, reason: String) -> void:
	if connection_state == value:
		return
	var previous := connection_state
	connection_state = value
	state_changed.emit(previous, connection_state, reason)


func _exit_tree() -> void:
	stop_polling("client_freed")
	if not _qualified_slot.is_empty():
		RumbleSessionSlotRegistry.release(_qualified_slot, self)

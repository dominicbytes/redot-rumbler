class_name RumbleSnapshotDiffer
extends RefCounted

const STATE_SCHEMA_VERSION: int = 1
const GIFT_FINGERPRINT_VERSION: int = 1
const MAX_INACTIVE_STREAM_COLLECTIONS: int = 64

var fingerprint_capacity: int = 250
var fingerprint_ttl_seconds: int = 7 * 24 * 60 * 60
var replay_history_on_first_poll: bool = false
var baseline_established: bool = false

var _collection_order: Dictionary = {}
var _collection_seen_at: Dictionary = {}
var _previous_counters: Dictionary = {}
var _previous_streams: Dictionary = {}
var _gift_baseline_pending: bool = false


func process(snapshot: RumbleSnapshot, observed_at_unix: int = 0) -> RumbleChangeSet:
	var changes := RumbleChangeSet.new()
	if snapshot == null:
		return changes
	var now_unix := observed_at_unix if observed_at_unix > 0 else int(Time.get_unix_time_from_system())
	var first_poll := not baseline_established
	changes.was_baseline = first_poll
	var emit_items := not first_poll or replay_history_on_first_poll

	_process_people("followers", snapshot.recent_followers, changes.followers, emit_items, now_unix)
	_process_people("subscribers", snapshot.recent_subscribers, changes.subscribers, emit_items, now_unix)
	_process_gifts(snapshot.recent_gifted_subscriptions, changes.gifted_subscriptions, emit_items and not _gift_baseline_pending, now_unix)
	_gift_baseline_pending = false
	var chat_and_rant_count := 0
	var active_collections: Dictionary = {}
	for stream: RumbleLivestream in snapshot.livestreams:
		active_collections["chat:%s" % stream.id] = true
		active_collections["rants:%s" % stream.id] = true
		chat_and_rant_count += stream.recent_messages.size() + stream.recent_rants.size()
		_process_messages("chat:%s" % stream.id, stream.recent_messages, changes.chat_messages, emit_items, now_unix)
		_process_rants("rants:%s" % stream.id, stream.recent_rants, changes.rants, emit_items, now_unix)
	_prune_inactive_collections(active_collections, now_unix)

	if chat_and_rant_count >= snapshot.max_num_results:
		changes.possible_gaps.append({
			"kind": "recent_chat_window_saturated",
			"observed_items": chat_and_rant_count,
			"source_limit": snapshot.max_num_results,
			"source_limited": true,
		})

	_compare_counters(snapshot.counters(), changes, first_poll)
	_compare_streams(snapshot.livestreams, changes, first_poll)
	changes.schema_warnings = snapshot.unknown_field_paths.duplicate()
	baseline_established = true
	return changes


func state_dictionary() -> Dictionary:
	var collections: Dictionary = {}
	for collection: Variant in _collection_order:
		var entries: Array = []
		var seen: Dictionary = _collection_seen_at.get(collection, {})
		for fingerprint: Variant in _collection_order[collection]:
			entries.append({"hash": str(fingerprint), "seen_at": int(seen.get(fingerprint, 0))})
		collections[str(collection)] = entries
	return {
		"schema_version": STATE_SCHEMA_VERSION,
		"gift_fingerprint_version": GIFT_FINGERPRINT_VERSION,
		"baseline_established": baseline_established,
		"fingerprint_capacity": fingerprint_capacity,
		"fingerprint_ttl_seconds": fingerprint_ttl_seconds,
		"collections": collections,
		"counters": _previous_counters.duplicate(true),
		"streams": _previous_streams.duplicate(true),
	}


func load_state(source: Dictionary) -> bool:
	clear()
	if int(source.get("schema_version", 0)) != STATE_SCHEMA_VERSION:
		return false
	baseline_established = bool(source.get("baseline_established", false))
	fingerprint_capacity = clampi(int(source.get("fingerprint_capacity", fingerprint_capacity)), 50, 2000)
	fingerprint_ttl_seconds = clampi(int(source.get("fingerprint_ttl_seconds", fingerprint_ttl_seconds)), 3600, 90 * 24 * 60 * 60)
	var collections: Variant = source.get("collections", {})
	if collections is Dictionary:
		for collection: Variant in collections:
			if not collections[collection] is Array:
				continue
			var order: Array[String] = []
			var seen: Dictionary = {}
			for entry: Variant in collections[collection]:
				if not entry is Dictionary:
					continue
				var fingerprint := str(entry.get("hash", ""))
				if fingerprint.is_empty():
					continue
				order.append(fingerprint)
				seen[fingerprint] = int(entry.get("seen_at", 0))
			_collection_order[str(collection)] = order
			_collection_seen_at[str(collection)] = seen
	if int(source.get("gift_fingerprint_version", 0)) != GIFT_FINGERPRINT_VERSION and _collection_order.has("gifted_subscriptions"):
		_collection_order.erase("gifted_subscriptions")
		_collection_seen_at.erase("gifted_subscriptions")
		_gift_baseline_pending = true
	_previous_counters = source.get("counters", {}).duplicate(true) if source.get("counters", {}) is Dictionary else {}
	_previous_streams = source.get("streams", {}).duplicate(true) if source.get("streams", {}) is Dictionary else {}
	return true


func clear() -> void:
	_gift_baseline_pending = false
	baseline_established = false
	_collection_order.clear()
	_collection_seen_at.clear()
	_previous_counters.clear()
	_previous_streams.clear()


func fingerprint_count() -> int:
	var count := 0
	for order: Variant in _collection_order.values():
		count += (order as Array).size()
	return count


func _process_people(collection: String, items: Array[RumblePersonEvent], output: Array[RumblePersonEvent], emit_items: bool, now_unix: int) -> void:
	var ordered := items.duplicate()
	ordered.sort_custom(func(a: RumblePersonEvent, b: RumblePersonEvent) -> bool: return _before(a.created_at, a.fingerprint, b.created_at, b.fingerprint))
	for item: RumblePersonEvent in ordered:
		if _accept(collection, item.fingerprint, now_unix) and emit_items:
			output.append(item)


func _process_gifts(items: Array[RumbleGiftedSubscription], output: Array[RumbleGiftedSubscription], emit_items: bool, now_unix: int) -> void:
	for item: RumbleGiftedSubscription in items:
		if _accept("gifted_subscriptions", item.fingerprint, now_unix) and emit_items:
			output.append(item)


func _process_messages(collection: String, items: Array[RumbleChatMessage], output: Array[RumbleChatMessage], emit_items: bool, now_unix: int) -> void:
	var ordered := items.duplicate()
	ordered.sort_custom(func(a: RumbleChatMessage, b: RumbleChatMessage) -> bool: return _before(a.created_at, a.fingerprint, b.created_at, b.fingerprint))
	for item: RumbleChatMessage in ordered:
		if _accept(collection, item.fingerprint, now_unix) and emit_items:
			output.append(item)


func _process_rants(collection: String, items: Array[RumbleRantEvent], output: Array[RumbleRantEvent], emit_items: bool, now_unix: int) -> void:
	var ordered := items.duplicate()
	ordered.sort_custom(func(a: RumbleRantEvent, b: RumbleRantEvent) -> bool: return _before(a.created_at, a.fingerprint, b.created_at, b.fingerprint))
	for item: RumbleRantEvent in ordered:
		if _accept(collection, item.fingerprint, now_unix) and emit_items:
			output.append(item)


func _accept(collection: String, fingerprint: String, now_unix: int) -> bool:
	if fingerprint.is_empty():
		return false
	_purge(collection, now_unix)
	var seen: Dictionary = _collection_seen_at.get(collection, {})
	var order: Array = _collection_order.get(collection, [])
	if seen.has(fingerprint):
		seen[fingerprint] = maxi(int(seen[fingerprint]), now_unix)
		order.erase(fingerprint)
		order.append(fingerprint)
		_collection_order[collection] = order
		_collection_seen_at[collection] = seen
		return false
	order.append(fingerprint)
	seen[fingerprint] = now_unix
	while order.size() > fingerprint_capacity:
		seen.erase(order.pop_front())
	_collection_order[collection] = order
	_collection_seen_at[collection] = seen
	return true


func _prune_inactive_collections(active: Dictionary, now_unix: int) -> void:
	var inactive: Array[Dictionary] = []
	for collection: String in _collection_order.keys():
		if not (collection.begins_with("chat:") or collection.begins_with("rants:")) or active.has(collection):
			continue
		_purge(collection, now_unix)
		if not _collection_order.has(collection):
			continue
		var order: Array = _collection_order[collection]
		var seen: Dictionary = _collection_seen_at[collection]
		inactive.append({"name": collection, "last_seen": int(seen.get(order[-1], 0))})
	inactive.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.last_seen == b.last_seen:
			return a.name < b.name
		return a.last_seen < b.last_seen)
	for index: int in maxi(0, inactive.size() - MAX_INACTIVE_STREAM_COLLECTIONS):
		_collection_order.erase(inactive[index].name)
		_collection_seen_at.erase(inactive[index].name)


func _purge(collection: String, now_unix: int) -> void:
	if not _collection_order.has(collection):
		return
	var order: Array = _collection_order[collection]
	var seen: Dictionary = _collection_seen_at.get(collection, {})
	while not order.is_empty():
		var fingerprint: String = str(order[0])
		var seen_at := int(seen.get(fingerprint, 0))
		if seen_at > 0 and now_unix - seen_at <= fingerprint_ttl_seconds:
			break
		order.pop_front()
		seen.erase(fingerprint)
	if order.is_empty():
		_collection_order.erase(collection)
		_collection_seen_at.erase(collection)
	else:
		_collection_order[collection] = order
		_collection_seen_at[collection] = seen


func _compare_counters(current: Dictionary, changes: RumbleChangeSet, first_poll: bool) -> void:
	if not first_poll:
		for name: Variant in current:
			var previous := int(_previous_counters.get(name, int(current[name])))
			var next := int(current[name])
			if next > previous:
				changes.counter_deltas[str(name)] = next - previous
			elif next < previous:
				changes.counter_resets.append({"counter": str(name), "previous": previous, "current": next, "uncertain": true})
	_previous_counters = current.duplicate(true)


func _compare_streams(streams: Array[RumbleLivestream], changes: RumbleChangeSet, first_poll: bool) -> void:
	var current: Dictionary = {}
	var models: Dictionary = {}
	for stream: RumbleLivestream in streams:
		if stream.id.is_empty():
			continue
		current[stream.id] = stream.state_dictionary()
		models[stream.id] = stream
	if not first_poll:
		for stream_id: Variant in current:
			var stream: RumbleLivestream = models[stream_id]
			if not _previous_streams.has(stream_id):
				if stream.is_live:
					changes.stream_transitions.append(_transition("started", stream, false, "new_live_stream"))
			elif _previous_streams[stream_id] != current[stream_id]:
				var previous: Dictionary = _previous_streams[stream_id]
				if bool(previous.get("is_live", false)) and not stream.is_live:
					changes.stream_transitions.append(_transition("ended", stream, false, "explicit_offline"))
				elif not bool(previous.get("is_live", false)) and stream.is_live:
					changes.stream_transitions.append(_transition("started", stream, false, "existing_stream_went_live"))
				else:
					changes.stream_transitions.append(_transition("updated", stream, false, "snapshot_changed"))
		for stream_id: Variant in _previous_streams:
			if current.has(stream_id):
				continue
			var previous: Dictionary = _previous_streams[stream_id]
			if bool(previous.get("is_live", false)):
				var transition := RumbleStreamTransition.new()
				transition.kind = "ended"
				transition.stream_id = str(stream_id)
				transition.uncertain = true
				transition.reason = "livestream_disappeared_from_live_only_payload"
				changes.stream_transitions.append(transition)
	_previous_streams = current


func _transition(kind: String, stream: RumbleLivestream, uncertain: bool, reason: String) -> RumbleStreamTransition:
	var value := RumbleStreamTransition.new()
	value.kind = kind
	value.stream = stream
	value.stream_id = stream.id
	value.uncertain = uncertain
	value.reason = reason
	return value


func _before(a_time: String, a_hash: String, b_time: String, b_hash: String) -> bool:
	return a_hash < b_hash if a_time == b_time else a_time < b_time

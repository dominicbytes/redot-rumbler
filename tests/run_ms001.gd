extends SceneTree

const FIXTURE_ROOT: String = "res://tests/fixtures/ms001"

var _checks: int = 0
var _failures: PackedStringArray = PackedStringArray()
var _parser := RumblePayloadParser.new()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_nullable_scalars()
	_test_gift_claims()
	var baseline_result := _parser.parse_json(_read("baseline.json"))
	_check(baseline_result.is_success(), "full official-shaped fixture parses")
	if not baseline_result.is_success():
		_finish()
		return
	var baseline := baseline_result.snapshot
	_check(baseline.user_id == "1001" and baseline.channel_id.is_empty(), "numeric and null identity fields normalize safely")
	_check(baseline.follower_count == 10 and baseline.follower_total_count == 20, "both documented follower counters map")
	_check(baseline.latest_follower.username == "Alice" and baseline.recent_followers.size() == 2, "latest and recent followers map")
	_check(baseline.subscriber_count == 2 and baseline.latest_subscriber.amount_cents == 500, "subscriber totals and amounts map")
	_check(baseline.gifted_subscription_count == 1 and baseline.latest_gifted_subscription.video_id == "7001", "gifted subscription fields map")
	_check(baseline.livestreams.size() == 1 and baseline.livestreams[0].watching_now == 19, "livestream viewers and identity map")
	_check(baseline.livestreams[0].primary_category.slug == "gaming" and baseline.livestreams[0].secondary_category.title == "Simulators", "both category levels map")
	_check(baseline.livestreams[0].recent_messages.size() == 2 and baseline.livestreams[0].recent_messages[0].badges == PackedStringArray(["premium"]), "chat messages and badges map")
	_check(baseline.livestreams[0].recent_rants[0].amount_cents == 250 and is_equal_approx(baseline.livestreams[0].recent_rants[0].amount_dollars, 2.5), "rant amounts map as numeric data")
	var public_json := JSON.stringify(baseline.to_dictionary())
	_check(not public_json.contains("stream_key") and not public_json.contains("SYNTHETIC_REMOVAL_MARKER"), "stream keys are stripped before typed models")
	_check(baseline.unknown_field_paths.has("future_block") and not public_json.contains("new_value"), "unknown diagnostics retain bounded paths without values")

	var differ := RumbleSnapshotDiffer.new()
	var baseline_changes := differ.process(baseline, 1000)
	_check(baseline_changes.was_baseline, "first good poll is identified as a baseline")
	_check(_event_count(baseline_changes) == 0, "first baseline replays no historical events by default")
	var update_result := _parser.parse_json(_read("update.json"))
	_check(update_result.is_success(), "overlapping update fixture parses")
	var update_changes := differ.process(update_result.snapshot, 1005)
	_check(update_changes.followers.size() == 1 and update_changes.followers[0].username == "Erin", "one new follower emits after overlap")
	_check(update_changes.subscribers.size() == 1 and update_changes.subscribers[0].username == "Frank", "one new subscriber emits after overlap")
	_check(update_changes.gifted_subscriptions.size() == 1 and update_changes.gifted_subscriptions[0].purchased_by == "Grace", "one new gift emits after overlap")
	_check(update_changes.chat_messages.size() == 1 and update_changes.chat_messages[0].text == "new", "one new chat emits after overlap")
	_check(update_changes.rants.size() == 1 and update_changes.rants[0].amount_cents == 100, "one new rant emits after overlap")
	_check(update_changes.counter_deltas.size() == 4 and int(update_changes.counter_deltas.subscribers) == 1, "all increasing documented counters emit positive deltas")
	_check(_transition_count(update_changes, "started") == 1 and _transition_count(update_changes, "updated") == 1, "new and changed livestreams emit distinct transitions")
	_check(update_changes.schema_warnings.has("livestreams[].future_metric"), "future livestream fields emit a bounded schema warning")
	var duplicate_changes := differ.process(update_result.snapshot, 1006)
	_check(_event_count(duplicate_changes) == 0 and duplicate_changes.stream_transitions.is_empty(), "identical overlap never double-fires")

	var reordered_data: Dictionary = JSON.parse_string(_read("update.json"))
	reordered_data.followers.recent_followers.reverse()
	reordered_data.subscribers.recent_subscribers.reverse()
	reordered_data.gifted_subs.recent_gifted_subs.reverse()
	reordered_data.livestreams[0].chat.recent_messages.reverse()
	reordered_data.livestreams[0].chat.recent_rants.reverse()
	var reordered := _parser.parse_json(JSON.stringify(reordered_data))
	var reorder_changes := differ.process(reordered.snapshot, 1007)
	_check(_event_count(reorder_changes) == 0, "reordered overlapping windows never double-fire")

	var saved_state := differ.state_dictionary()
	var restored := RumbleSnapshotDiffer.new()
	_check(restored.load_state(saved_state), "bounded hash/counter/stream state restores from schema v1")
	var restart_changes := restored.process(update_result.snapshot, 1008)
	_check(_event_count(restart_changes) == 0 and restart_changes.stream_transitions.is_empty(), "restart state suppresses already observed items")
	var state_after_restart := restored.state_dictionary()

	var malformed := _parser.parse_json(_read("malformed.json"))
	_check(not malformed.is_success() and malformed.error.category == "parse", "malformed JSON is rejected with a typed parse error")
	_check(restored.state_dictionary() == state_after_restart, "rejected payload does not replace last good differ state")
	var minimal := _parser.parse_json(_read("minimal.json"))
	_check(minimal.is_success() and minimal.snapshot.livestreams.is_empty(), "documented optional and offline fields may be missing")

	var offline := _parser.parse_json(_read("offline.json"))
	var offline_changes := restored.process(offline.snapshot, 1010)
	_check(offline_changes.counter_resets.size() == 1 and offline_changes.counter_resets[0].counter == "subscribers", "counter decreases update baseline and emit uncertainty, not negative people")
	_check(_transition_count(offline_changes, "ended") == 2, "live-only payload disappearance emits uncertain stream-ended transitions")
	_check(offline_changes.stream_transitions.all(func(item: RumbleStreamTransition) -> bool: return item.uncertain), "disappearance transitions remain explicitly uncertain")

	var saturated_json := _saturated_payload(50, "sat")
	var saturated := _parser.parse_json(saturated_json)
	var saturated_differ := RumbleSnapshotDiffer.new()
	var saturated_changes := saturated_differ.process(saturated.snapshot, 2000)
	_check(saturated_changes.possible_gaps.size() == 1 and saturated_changes.possible_gaps[0].source_limit == 50, "a full 50-item source window emits possible_event_gap")
	_check(saturated_changes.chat_messages.is_empty(), "saturated first poll still remains a silent baseline")

	var bounded := RumbleSnapshotDiffer.new()
	bounded.fingerprint_capacity = 3
	bounded.fingerprint_ttl_seconds = 10
	bounded.process(saturated.snapshot, 3000)
	_check(bounded.fingerprint_count() == 3, "fingerprint storage enforces per-collection capacity")
	var one_new := _parser.parse_json(_saturated_payload(1, "fresh"))
	bounded.process(one_new.snapshot, 3011)
	_check(bounded.fingerprint_count() == 1, "fingerprint storage expires entries after the explicit TTL")

	var bad_shape := _parser.parse_json("{\"livestreams\":{}}")
	_check(not bad_shape.is_success() and bad_shape.error.category == "schema", "malformed collection types are rejected without coercion")
	_finish()


func _test_nullable_scalars() -> void:
	var data: Dictionary = JSON.parse_string(_read("baseline.json"))
	data.livestreams[0].likes = null
	data.livestreams[0].is_live = null
	data.subscribers.latest_subscriber.amount_cents = null
	data.subscribers.latest_subscriber.amount_dollars = null
	data.livestreams[0].chat.recent_rants[0].amount_cents = null
	data.livestreams[0].chat.recent_rants[0].amount_dollars = null
	var result := _parser.parse_json(JSON.stringify(data))
	_check(result.is_success(), "nullable scalar payload still parses")
	if result.snapshot != null:
		_check(result.snapshot.livestreams.size() == 1 and result.snapshot.livestreams[0] != null, "null scalar cannot append a null stream")
		if result.snapshot.livestreams[0] != null:
			_check(result.snapshot.livestreams[0].likes == 0 and not result.snapshot.livestreams[0].is_live, "null numeric and boolean values default safely")
			_check(result.snapshot.livestreams[0].recent_rants[0] != null and result.snapshot.livestreams[0].recent_rants[0].amount_cents == 0, "null rant amounts preserve the event")
		_check(result.snapshot.latest_subscriber != null and result.snapshot.latest_subscriber.amount_cents == 0, "null subscriber amounts preserve the event")
		_check(result.snapshot.unknown_field_paths.has("livestreams[].likes"), "invalid scalar records a value-free schema warning path")
	data.followers.recent_followers = null
	data.subscribers.recent_subscribers = null
	data.gifted_subs.recent_gifted_subs = null
	data.livestreams[0].chat.recent_messages = null
	data.livestreams[0].chat.recent_rants = null
	result = _parser.parse_json(JSON.stringify(data))
	_check(result.is_success(), "null recent collections are accepted as empty")
	if result.is_success():
		_check(result.snapshot.recent_followers.is_empty() and result.snapshot.recent_subscribers.is_empty() and result.snapshot.recent_gifted_subscriptions.is_empty(), "null person and gift lists normalize to empty")
		_check(result.snapshot.livestreams[0].recent_messages.is_empty() and result.snapshot.livestreams[0].recent_rants.is_empty(), "null chat lists normalize to empty")
	for bad: Variant in [null, [], {}, true, "wrong"]:
		result = _parser.parse_json(JSON.stringify({"now": bad, "type": bad, "followers": {"num_followers": bad}, "livestreams": [{"id": "s", "likes": bad, "title": bad}]}))
		_check(result.is_success() and result.snapshot.livestreams[0] != null, "wrong scalar types cannot interrupt parsing")
	var numeric := _parser.parse_json('{"now":"42","followers":{"num_followers":3.0},"livestreams":[{"id":7,"likes":"12","is_live":"1"}]}')
	_check(numeric.is_success() and numeric.snapshot.now_unix == 42 and numeric.snapshot.follower_count == 3 and numeric.snapshot.livestreams[0].likes == 12 and numeric.snapshot.livestreams[0].is_live, "numeric primitives and integral strings coerce safely")


func _saturated_payload(count: int, prefix: String) -> String:
	var messages: Array = []
	for index: int in count:
		messages.append({"username": "viewer-%d" % index, "badges": [], "text": "%s-%d" % [prefix, index], "created_on": "2026-08-11T10:%02d:00Z" % (index % 60)})
	return JSON.stringify({
		"now": 1786453400,
		"type": "user",
		"user_id": "fixture",
		"max_num_results": 50,
		"followers": {},
		"subscribers": {},
		"gifted_subs": {},
		"livestreams": [{"id": "stream-1", "title": "Fixture", "is_live": true, "chat": {"recent_messages": messages, "recent_rants": []}}],
	})


func _event_count(changes: RumbleChangeSet) -> int:
	return changes.chat_messages.size() + changes.rants.size() + changes.followers.size() + changes.subscribers.size() + changes.gifted_subscriptions.size()


func _transition_count(changes: RumbleChangeSet, kind: String) -> int:
	return changes.stream_transitions.filter(func(item: RumbleStreamTransition) -> bool: return item.kind == kind).size()


func _read(name: String) -> String:
	return FileAccess.get_file_as_string("%s/%s" % [FIXTURE_ROOT, name])


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS: " + label)
	else:
		_failures.append(label)


func _finish() -> void:
	if _failures.is_empty():
		print("REDOT RUMBLER MS001 PASS: %d checks" % _checks)
		quit(0)
		return
	for failure: String in _failures:
		push_error("REDOT RUMBLER MS001 FAIL: " + failure)
	print("REDOT RUMBLER MS001 FAILED: %d of %d checks" % [_failures.size(), _checks])
	quit(1)


func _test_gift_claims() -> void:
	var differ := RumbleSnapshotDiffer.new()
	differ.process(_parser.parse_json("{}").snapshot, 1000)
	var gift: Dictionary = {"purchased_by": "buyer", "video_id": "stream", "gift_type": "rumble", "total_gifts": 1, "remaining_gifts": 1}
	var payload: Dictionary = {"gifted_subs": {"latest_gifted_sub": gift, "recent_gifted_subs": [gift]}}
	var snapshot := _parser.parse_json(JSON.stringify(payload)).snapshot
	_check(differ.process(snapshot, 1001).gifted_subscriptions.size() == 1, "new gifted purchase emits once")
	gift.remaining_gifts = 0
	snapshot = _parser.parse_json(JSON.stringify(payload)).snapshot
	_check(differ.process(snapshot, 1002).gifted_subscriptions.is_empty(), "claiming a gift does not replay its purchase")
	gift.total_gifts = 2
	snapshot = _parser.parse_json(JSON.stringify(payload)).snapshot
	_check(differ.process(snapshot, 1003).gifted_subscriptions.is_empty(), "mutable gift counts do not change purchase identity")
	var duplicates := RumbleSnapshotDiffer.new()
	duplicates.process(_parser.parse_json("{}").snapshot, 1000)
	payload.gifted_subs.recent_gifted_subs = [gift.duplicate(), gift.duplicate()]
	snapshot = _parser.parse_json(JSON.stringify(payload)).snapshot
	_check(duplicates.process(snapshot, 1001).gifted_subscriptions.size() == 2, "identical purchases in one payload each emit")
	_check(snapshot.recent_gifted_subscriptions[0].fingerprint != snapshot.recent_gifted_subscriptions[1].fingerprint, "identical purchase occurrences have distinct fingerprints")
	_check(snapshot.latest_gifted_subscription.fingerprint == snapshot.recent_gifted_subscriptions[0].fingerprint, "latest gift shares the first occurrence identity")
	_check(duplicates.process(snapshot, 1002).gifted_subscriptions.is_empty(), "repeated duplicate payload emits no purchase again")

	var legacy_state := duplicates.state_dictionary()
	legacy_state.erase("gift_fingerprint_version")
	legacy_state.collections.gifted_subscriptions = [{"hash": "legacy-count-based-hash", "seen_at": 1002}]
	var upgraded := RumbleSnapshotDiffer.new()
	upgraded.replay_history_on_first_poll = true
	_check(upgraded.load_state(legacy_state), "legacy gift hash state remains loadable")
	var new_message := RumbleChatMessage.new()
	new_message.fingerprint = "upgrade-chat"
	var stream := RumbleLivestream.new()
	stream.id = "upgrade-stream"
	stream.recent_messages.append(new_message)
	snapshot.livestreams.append(stream)
	var migrated := upgraded.process(snapshot, 1003)
	_check(migrated.gifted_subscriptions.is_empty() and migrated.chat_messages.size() == 1, "legacy hash upgrade silently baselines gifts while other event delivery continues")
	_check(upgraded.process(snapshot, 1004).gifted_subscriptions.is_empty(), "migrated gifts remain deduplicated")
	payload.gifted_subs.recent_gifted_subs.append(gift.duplicate())
	snapshot = _parser.parse_json(JSON.stringify(payload)).snapshot
	_check(upgraded.process(snapshot, 1005).gifted_subscriptions.size() == 1, "new gift occurrence emits after legacy baseline")
	var current := RumbleSnapshotDiffer.new()
	_check(current.load_state(upgraded.state_dictionary()) and current.process(snapshot, 1006).gifted_subscriptions.is_empty(), "current fingerprint version survives restart without replay")

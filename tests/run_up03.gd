extends SceneTree

class CountingStore:
	extends RefCounted
	var saves: int = 0
	var state: Dictionary = {}

	func load_state(_slot: String) -> Dictionary:
		return state.duplicate(true)

	func save(_slot: String, next_state: Dictionary) -> RumbleApiError:
		saves += 1
		state = next_state.duplicate(true)
		return null


class CountingDescriptors:
	extends RefCounted
	var saves: int = 0

	func save(_descriptor: RumbleSessionDescriptor) -> RumbleApiError:
		saves += 1
		return null


var _checks: int = 0
var _failures: PackedStringArray = PackedStringArray()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var snapshot := RumbleSnapshot.new()
	var follower := RumblePersonEvent.new()
	follower.fingerprint = "unchanged-follower"
	snapshot.recent_followers.append(follower)
	var differ := RumbleSnapshotDiffer.new()
	differ.fingerprint_ttl_seconds = 3600
	differ.process(snapshot, 1000)
	_check(differ.process(snapshot, 2800).followers.is_empty(), "overlap before TTL emits nothing")
	_check(differ.process(snapshot, 4600).followers.is_empty(), "overlap at first-seen TTL emits nothing")
	_check(differ.process(snapshot, 4601).followers.is_empty(), "continuous observation past first-seen TTL emits nothing")
	var restored := RumbleSnapshotDiffer.new()
	_check(restored.load_state(differ.state_dictionary()), "last observation restores")
	_check(restored.process(snapshot, 8000).followers.is_empty(), "restart within last-observed TTL emits nothing")
	var absent := RumbleSnapshot.new()
	restored.process(absent, 11601)
	_check(restored.process(snapshot, 11602).followers.size() == 1, "fingerprint expires after genuine absence")

	var stream := RumbleLivestream.new()
	stream.id = "known"
	stream.is_live = false
	var stream_snapshot := RumbleSnapshot.new()
	stream_snapshot.livestreams.append(stream)
	var stream_differ := RumbleSnapshotDiffer.new()
	stream_differ.process(stream_snapshot, 200)
	stream.is_live = true
	var started := stream_differ.process(stream_snapshot, 201)
	_check(started.stream_transitions.size() == 1 and started.stream_transitions[0].kind == "started", "known offline-to-live stream starts once")
	_check(stream_differ.process(stream_snapshot, 202).stream_transitions.is_empty(), "unchanged live stream does not restart")

	var collections := RumbleSnapshotDiffer.new()
	for index: int in 70:
		var one := RumbleSnapshot.new()
		var channel := RumbleLivestream.new()
		channel.id = "stream-%d" % index
		var message := RumbleChatMessage.new()
		message.fingerprint = "message-%d" % index
		channel.recent_messages.append(message)
		one.livestreams.append(channel)
		collections.process(one, 300 + index)
	var retained: Dictionary = collections.state_dictionary().collections
	_check(retained.size() == 65 and not retained.has("chat:stream-0") and retained.has("chat:stream-69"), "inactive stream collections cap at 64 plus active stream")
	collections.process(RumbleSnapshot.new(), 1000000)
	_check(collections.state_dictionary().collections.is_empty(), "inactive stream collections expire after TTL")

	var states := CountingStore.new()
	var descriptors := CountingDescriptors.new()
	var client := RumbleLiveClient.new()
	root.add_child(client)
	var config := RumbleClientConfig.new()
	config.publisher_id = "up03"
	config.application_id = "tests"
	_check(client.configure(config, "primary", null, descriptors, states) == null, "client configures with counting stores")
	client.connected_descriptor = RumbleSessionDescriptor.new()
	client._apply_snapshot(RumbleSnapshot.new())
	var initial_state_writes := states.saves
	var initial_descriptor_writes := descriptors.saves
	for index: int in 5:
		client._apply_snapshot(RumbleSnapshot.new())
	_check(initial_state_writes == 1 and states.saves == 1, "five unchanged empty polls avoid five redundant state writes")
	_check(initial_descriptor_writes == 1 and descriptors.saves == 1, "five unchanged empty polls avoid five redundant descriptor writes")
	client._apply_snapshot(snapshot)
	_check(states.saves == 2, "new fingerprint is persisted before restart")
	client.queue_free()
	await process_frame
	_finish()


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS: " + label)
	else:
		_failures.append(label)


func _finish() -> void:
	for failure: String in _failures:
		push_error("UP03 FAIL: " + failure)
	print("RUMBLER UP03 %s: %d/%d checks" % ["PASS" if _failures.is_empty() else "FAIL", _checks - _failures.size(), _checks])
	quit(0 if _failures.is_empty() else 1)

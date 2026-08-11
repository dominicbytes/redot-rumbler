class_name RumblePayloadParser
extends RefCounted

const MAX_UNKNOWN_FIELDS: int = 64
const TOP_LEVEL_FIELDS: Array[String] = ["now", "type", "user_id", "channel_id", "since", "max_num_results", "followers", "subscribers", "gifted_subs", "livestreams"]
const FOLLOWER_FIELDS: Array[String] = ["num_followers", "num_followers_total", "latest_follower", "recent_followers"]
const SUBSCRIBER_FIELDS: Array[String] = ["num_subscribers", "latest_subscriber", "recent_subscribers"]
const GIFT_COLLECTION_FIELDS: Array[String] = ["num_gifted_subs", "latest_gifted_sub", "recent_gifted_subs"]
const PERSON_FIELDS: Array[String] = ["username", "user", "display_name", "followed_on", "subscribed_on", "amount_cents", "amount_dollars"]
const GIFT_FIELDS: Array[String] = ["total_gifts", "gift_type", "remaining_gifts", "video_id", "purchased_by", "username", "user"]
const STREAM_FIELDS: Array[String] = ["id", "title", "created_on", "is_live", "categories", "stream_key", "likes", "dislikes", "watching_now", "chat"]
const CATEGORY_COLLECTION_FIELDS: Array[String] = ["primary", "secondary"]
const CATEGORY_FIELDS: Array[String] = ["slug", "title"]
const CHAT_COLLECTION_FIELDS: Array[String] = ["latest_message", "recent_messages", "latest_rant", "recent_rants"]
const MESSAGE_FIELDS: Array[String] = ["username", "badges", "text", "created_on"]
const RANT_FIELDS: Array[String] = ["username", "badges", "text", "created_on", "expires_on", "amount_cents", "amount_dollars"]


func parse_json(json_text: String) -> RumbleParseResult:
	var result := RumbleParseResult.new()
	if json_text.to_utf8_buffer().size() > 2 * 1024 * 1024:
		result.error = RumbleApiError.custom("body_limit", "Rumble response exceeds the parser limit")
		result.error.transient = true
		return result
	var json := JSON.new()
	if json.parse(json_text) != OK:
		result.error = RumbleApiError.custom("parse", "Rumble response is not valid JSON")
		result.error.transient = true
		return result
	var parsed: Variant = json.data
	if not parsed is Dictionary:
		result.error = RumbleApiError.custom("parse", "Rumble response is not a JSON object")
		result.error.transient = true
		return result
	var root: Dictionary = RumbleRedactor.sanitize_variant(parsed)
	var validation_error := _validate_collection_types(root)
	if not validation_error.is_empty():
		result.error = RumbleApiError.custom("schema", validation_error)
		result.error.transient = true
		return result

	var snapshot := RumbleSnapshot.new()
	snapshot.now_unix = int(root.get("now", 0))
	snapshot.response_type = str(root.get("type", ""))
	snapshot.user_id = _id(root.get("user_id", ""))
	snapshot.channel_id = _id(root.get("channel_id", ""))
	snapshot.since = str(root.get("since", "")) if root.get("since", null) != null else ""
	snapshot.max_num_results = clampi(int(root.get("max_num_results", 50)), 1, 50)

	var followers: Dictionary = _dictionary(root.get("followers", {}))
	snapshot.follower_count = int(followers.get("num_followers", 0))
	snapshot.follower_total_count = int(followers.get("num_followers_total", snapshot.follower_count))
	snapshot.latest_follower = _parse_person(_dictionary(followers.get("latest_follower", {})), "follow")
	snapshot.recent_followers = _parse_people(_array(followers.get("recent_followers", [])), "follow")

	var subscribers: Dictionary = _dictionary(root.get("subscribers", {}))
	snapshot.subscriber_count = int(subscribers.get("num_subscribers", 0))
	snapshot.latest_subscriber = _parse_person(_dictionary(subscribers.get("latest_subscriber", {})), "subscription")
	snapshot.recent_subscribers = _parse_people(_array(subscribers.get("recent_subscribers", [])), "subscription")

	var gifts: Dictionary = _dictionary(root.get("gifted_subs", {}))
	snapshot.gifted_subscription_count = int(gifts.get("num_gifted_subs", 0))
	snapshot.latest_gifted_subscription = _parse_gift(_dictionary(gifts.get("latest_gifted_sub", {})))
	snapshot.recent_gifted_subscriptions = _parse_gifts(_array(gifts.get("recent_gifted_subs", [])))

	for raw_stream: Variant in _array(root.get("livestreams", [])):
		if raw_stream is Dictionary:
			snapshot.livestreams.append(_parse_stream(raw_stream))

	_collect_unknowns(root, snapshot.unknown_field_paths)
	result.snapshot = snapshot
	return result


func _validate_collection_types(root: Dictionary) -> String:
	for key: String in ["followers", "subscribers", "gifted_subs"]:
		if root.has(key) and root[key] != null and not root[key] is Dictionary:
			return "Rumble field '%s' must be an object" % key
	if root.has("livestreams") and not root.livestreams is Array:
		return "Rumble field 'livestreams' must be an array"
	for collection_name: String in ["followers", "subscribers", "gifted_subs"]:
		var collection: Dictionary = _dictionary(root.get(collection_name, {}))
		for key: Variant in collection:
			if str(key).begins_with("recent_") and not collection[key] is Array:
				return "Rumble field '%s.%s' must be an array" % [collection_name, key]
	for raw_stream: Variant in _array(root.get("livestreams", [])):
		if not raw_stream is Dictionary:
			return "Every Rumble livestream entry must be an object"
		var chat: Variant = raw_stream.get("chat", {})
		if chat != null and not chat is Dictionary:
			return "Rumble livestream chat must be an object"
		if chat is Dictionary:
			for key: String in ["recent_messages", "recent_rants"]:
				if chat.has(key) and not chat[key] is Array:
					return "Rumble chat field '%s' must be an array" % key
	return ""


func _parse_people(items: Array, kind: String) -> Array[RumblePersonEvent]:
	var output: Array[RumblePersonEvent] = []
	for item: Variant in items:
		if item is Dictionary:
			var parsed := _parse_person(item, kind)
			if parsed != null:
				output.append(parsed)
	return output


func _parse_person(item: Dictionary, kind: String) -> RumblePersonEvent:
	if item.is_empty():
		return null
	var value := RumblePersonEvent.new()
	value.kind = kind
	value.username = _first(item, PackedStringArray(["username", "user"]))
	value.display_name = _first(item, PackedStringArray(["display_name", "username", "user"]))
	value.created_at = str(item.get("followed_on", item.get("subscribed_on", "")))
	value.amount_cents = int(item.get("amount_cents", 0))
	value.amount_dollars = float(item.get("amount_dollars", 0.0))
	value.fingerprint = _fingerprint([kind, value.username, value.created_at, value.amount_cents])
	return value


func _parse_gifts(items: Array) -> Array[RumbleGiftedSubscription]:
	var output: Array[RumbleGiftedSubscription] = []
	for item: Variant in items:
		if item is Dictionary:
			var parsed := _parse_gift(item)
			if parsed != null:
				output.append(parsed)
	return output


func _parse_gift(item: Dictionary) -> RumbleGiftedSubscription:
	if item.is_empty():
		return null
	var value := RumbleGiftedSubscription.new()
	value.purchased_by = _first(item, PackedStringArray(["purchased_by", "username", "user"]))
	value.total_gifts = int(item.get("total_gifts", 0))
	value.remaining_gifts = int(item.get("remaining_gifts", 0))
	value.gift_type = str(item.get("gift_type", ""))
	value.video_id = _id(item.get("video_id", ""))
	value.fingerprint = _fingerprint(["gift", value.purchased_by, value.video_id, value.gift_type, value.total_gifts, value.remaining_gifts])
	return value


func _parse_stream(item: Dictionary) -> RumbleLivestream:
	var stream := RumbleLivestream.new()
	stream.id = _id(item.get("id", ""))
	stream.title = str(item.get("title", ""))
	stream.created_at = str(item.get("created_on", ""))
	stream.is_live = bool(item.get("is_live", false))
	stream.likes = int(item.get("likes", 0))
	stream.dislikes = int(item.get("dislikes", 0))
	stream.watching_now = int(item.get("watching_now", 0))
	var categories: Dictionary = _dictionary(item.get("categories", {}))
	stream.primary_category = _parse_category(_dictionary(categories.get("primary", {})))
	stream.secondary_category = _parse_category(_dictionary(categories.get("secondary", {})))
	var chat: Dictionary = _dictionary(item.get("chat", {}))
	stream.latest_message = _parse_message(_dictionary(chat.get("latest_message", {})), stream)
	for raw_message: Variant in _array(chat.get("recent_messages", [])):
		if raw_message is Dictionary:
			stream.recent_messages.append(_parse_message(raw_message, stream))
	stream.latest_rant = _parse_rant(_dictionary(chat.get("latest_rant", {})), stream)
	for raw_rant: Variant in _array(chat.get("recent_rants", [])):
		if raw_rant is Dictionary:
			stream.recent_rants.append(_parse_rant(raw_rant, stream))
	return stream


func _parse_category(item: Dictionary) -> RumbleCategory:
	if item.is_empty():
		return null
	var value := RumbleCategory.new()
	value.slug = str(item.get("slug", ""))
	value.title = str(item.get("title", ""))
	return value


func _parse_message(item: Dictionary, stream: RumbleLivestream) -> RumbleChatMessage:
	if item.is_empty():
		return null
	var value := RumbleChatMessage.new()
	value.stream_id = stream.id
	value.stream_title = stream.title
	value.username = str(item.get("username", ""))
	value.badges = _strings(item.get("badges", []))
	value.text = str(item.get("text", ""))
	value.created_at = str(item.get("created_on", ""))
	value.fingerprint = _fingerprint(["chat", value.stream_id, value.username, value.created_at, value.text])
	return value


func _parse_rant(item: Dictionary, stream: RumbleLivestream) -> RumbleRantEvent:
	if item.is_empty():
		return null
	var value := RumbleRantEvent.new()
	value.stream_id = stream.id
	value.stream_title = stream.title
	value.username = str(item.get("username", ""))
	value.badges = _strings(item.get("badges", []))
	value.text = str(item.get("text", ""))
	value.created_at = str(item.get("created_on", ""))
	value.expires_at = str(item.get("expires_on", ""))
	value.amount_cents = int(item.get("amount_cents", 0))
	value.amount_dollars = float(item.get("amount_dollars", 0.0))
	value.fingerprint = _fingerprint(["rant", value.stream_id, value.username, value.created_at, value.text, value.amount_cents])
	return value


func _collect_unknowns(root: Dictionary, output: PackedStringArray) -> void:
	_add_unknown_keys(root, TOP_LEVEL_FIELDS, "", output)
	var followers: Dictionary = _dictionary(root.get("followers", {}))
	_add_unknown_keys(followers, FOLLOWER_FIELDS, "followers", output)
	_add_unknown_keys(_dictionary(followers.get("latest_follower", {})), PERSON_FIELDS, "followers.latest_follower", output)
	_collect_array_unknowns(_array(followers.get("recent_followers", [])), PERSON_FIELDS, "followers.recent_followers[]", output)
	var subscribers: Dictionary = _dictionary(root.get("subscribers", {}))
	_add_unknown_keys(subscribers, SUBSCRIBER_FIELDS, "subscribers", output)
	_add_unknown_keys(_dictionary(subscribers.get("latest_subscriber", {})), PERSON_FIELDS, "subscribers.latest_subscriber", output)
	_collect_array_unknowns(_array(subscribers.get("recent_subscribers", [])), PERSON_FIELDS, "subscribers.recent_subscribers[]", output)
	var gifts: Dictionary = _dictionary(root.get("gifted_subs", {}))
	_add_unknown_keys(gifts, GIFT_COLLECTION_FIELDS, "gifted_subs", output)
	_add_unknown_keys(_dictionary(gifts.get("latest_gifted_sub", {})), GIFT_FIELDS, "gifted_subs.latest_gifted_sub", output)
	_collect_array_unknowns(_array(gifts.get("recent_gifted_subs", [])), GIFT_FIELDS, "gifted_subs.recent_gifted_subs[]", output)
	for raw_stream: Variant in _array(root.get("livestreams", [])):
		if output.size() >= MAX_UNKNOWN_FIELDS:
			return
		if not raw_stream is Dictionary:
			continue
		_add_unknown_keys(raw_stream, STREAM_FIELDS, "livestreams[]", output)
		var categories: Dictionary = _dictionary(raw_stream.get("categories", {}))
		_add_unknown_keys(categories, CATEGORY_COLLECTION_FIELDS, "livestreams[].categories", output)
		_add_unknown_keys(_dictionary(categories.get("primary", {})), CATEGORY_FIELDS, "livestreams[].categories.primary", output)
		_add_unknown_keys(_dictionary(categories.get("secondary", {})), CATEGORY_FIELDS, "livestreams[].categories.secondary", output)
		var chat: Dictionary = _dictionary(raw_stream.get("chat", {}))
		_add_unknown_keys(chat, CHAT_COLLECTION_FIELDS, "livestreams[].chat", output)
		_add_unknown_keys(_dictionary(chat.get("latest_message", {})), MESSAGE_FIELDS, "livestreams[].chat.latest_message", output)
		_collect_array_unknowns(_array(chat.get("recent_messages", [])), MESSAGE_FIELDS, "livestreams[].chat.recent_messages[]", output)
		_add_unknown_keys(_dictionary(chat.get("latest_rant", {})), RANT_FIELDS, "livestreams[].chat.latest_rant", output)
		_collect_array_unknowns(_array(chat.get("recent_rants", [])), RANT_FIELDS, "livestreams[].chat.recent_rants[]", output)


func _collect_array_unknowns(items: Array, allowed: Array[String], path: String, output: PackedStringArray) -> void:
	for item: Variant in items:
		if item is Dictionary:
			_add_unknown_keys(item, allowed, path, output)


func _add_unknown_keys(item: Dictionary, allowed: Array[String], path: String, output: PackedStringArray) -> void:
	for key: Variant in item:
		if output.size() >= MAX_UNKNOWN_FIELDS:
			return
		var name := str(key)
		if not allowed.has(name) and not RumbleRedactor.SECRET_KEYS.has(name.to_lower()):
			var full_path := name if path.is_empty() else path + "." + name
			if not output.has(full_path):
				output.append(full_path)


func _fingerprint(fields: Array) -> String:
	var parts := PackedStringArray()
	for field: Variant in fields:
		parts.append(str(field))
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	context.update("\u001f".join(parts).to_utf8_buffer())
	return context.finish().hex_encode()


func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


func _array(value: Variant) -> Array:
	return value if value is Array else []


func _strings(value: Variant) -> PackedStringArray:
	var output := PackedStringArray()
	if value is Array:
		for item: Variant in value:
			output.append(str(item))
	return output


func _first(item: Dictionary, names: PackedStringArray) -> String:
	for name: String in names:
		var value := str(item.get(name, ""))
		if not value.is_empty():
			return value
	return ""


func _id(value: Variant) -> String:
	if value == null:
		return ""
	if value is float and is_equal_approx(value, floorf(value)):
		return str(int(value))
	return str(value)

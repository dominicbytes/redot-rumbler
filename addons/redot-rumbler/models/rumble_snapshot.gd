class_name RumbleSnapshot
extends RefCounted

var now_unix: int = 0
var response_type: String = ""
var user_id: String = ""
var channel_id: String = ""
var since: String = ""
var max_num_results: int = 50
var follower_count: int = 0
var follower_total_count: int = 0
var latest_follower: RumblePersonEvent = null
var recent_followers: Array[RumblePersonEvent] = []
var subscriber_count: int = 0
var latest_subscriber: RumblePersonEvent = null
var recent_subscribers: Array[RumblePersonEvent] = []
var gifted_subscription_count: int = 0
var latest_gifted_subscription: RumbleGiftedSubscription = null
var recent_gifted_subscriptions: Array[RumbleGiftedSubscription] = []
var livestreams: Array[RumbleLivestream] = []
var unknown_field_paths: PackedStringArray = PackedStringArray()


func counters() -> Dictionary:
	return {
		"followers": follower_count,
		"followers_total": follower_total_count,
		"subscribers": subscriber_count,
		"gifted_subscriptions": gifted_subscription_count,
	}


func to_dictionary() -> Dictionary:
	return {
		"now": now_unix,
		"type": response_type,
		"user_id": user_id,
		"channel_id": channel_id,
		"since": since,
		"max_num_results": max_num_results,
		"followers": {"count": follower_count, "total_count": follower_total_count, "latest": latest_follower.to_dictionary() if latest_follower != null else null, "recent": recent_followers.map(func(item: RumblePersonEvent) -> Dictionary: return item.to_dictionary())},
		"subscribers": {"count": subscriber_count, "latest": latest_subscriber.to_dictionary() if latest_subscriber != null else null, "recent": recent_subscribers.map(func(item: RumblePersonEvent) -> Dictionary: return item.to_dictionary())},
		"gifted_subscriptions": {"count": gifted_subscription_count, "latest": latest_gifted_subscription.to_dictionary() if latest_gifted_subscription != null else null, "recent": recent_gifted_subscriptions.map(func(item: RumbleGiftedSubscription) -> Dictionary: return item.to_dictionary())},
		"livestreams": livestreams.map(func(item: RumbleLivestream) -> Dictionary: return item.to_dictionary()),
		"unknown_field_paths": Array(unknown_field_paths),
	}

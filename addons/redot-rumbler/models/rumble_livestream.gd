class_name RumbleLivestream
extends RefCounted

var id: String = ""
var title: String = ""
var created_at: String = ""
var is_live: bool = false
var primary_category: RumbleCategory = null
var secondary_category: RumbleCategory = null
var likes: int = 0
var dislikes: int = 0
var watching_now: int = 0
var latest_message: RumbleChatMessage = null
var recent_messages: Array[RumbleChatMessage] = []
var latest_rant: RumbleRantEvent = null
var recent_rants: Array[RumbleRantEvent] = []


func state_dictionary() -> Dictionary:
	return {
		"id": id,
		"title": title,
		"created_at": created_at,
		"is_live": is_live,
		"primary_category": primary_category.to_dictionary() if primary_category != null else {},
		"secondary_category": secondary_category.to_dictionary() if secondary_category != null else {},
		"likes": likes,
		"dislikes": dislikes,
		"watching_now": watching_now,
	}


func to_dictionary() -> Dictionary:
	var value := state_dictionary()
	value["latest_message"] = latest_message.to_dictionary() if latest_message != null else null
	value["recent_messages"] = recent_messages.map(func(item: RumbleChatMessage) -> Dictionary: return item.to_dictionary())
	value["latest_rant"] = latest_rant.to_dictionary() if latest_rant != null else null
	value["recent_rants"] = recent_rants.map(func(item: RumbleRantEvent) -> Dictionary: return item.to_dictionary())
	return value

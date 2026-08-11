class_name RumbleCapabilityRegistry
extends RefCounted

const SUPPORTED: Array[String] = [
	"identity.read",
	"followers.read",
	"subscriptions.read",
	"gifted_subscriptions.read",
	"livestreams.read",
	"chat.read",
	"rants.read",
	"commands.local",
	"credentials.persist",
]
const UNAVAILABLE: Array[String] = [
	"chat.write",
	"moderation",
	"rewards.manage",
	"raids",
	"media.download",
]


static func status(capability: String) -> String:
	if SUPPORTED.has(capability):
		return "SUPPORTED"
	if UNAVAILABLE.has(capability):
		return "UNAVAILABLE"
	return "UNKNOWN"


static func all() -> Dictionary:
	return {"supported": Array(SUPPORTED), "unavailable": Array(UNAVAILABLE)}

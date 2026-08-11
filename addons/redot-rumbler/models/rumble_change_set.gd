class_name RumbleChangeSet
extends RefCounted

var was_baseline: bool = false
var chat_messages: Array[RumbleChatMessage] = []
var rants: Array[RumbleRantEvent] = []
var followers: Array[RumblePersonEvent] = []
var subscribers: Array[RumblePersonEvent] = []
var gifted_subscriptions: Array[RumbleGiftedSubscription] = []
var stream_transitions: Array[RumbleStreamTransition] = []
var counter_deltas: Dictionary = {}
var counter_resets: Array[Dictionary] = []
var possible_gaps: Array[Dictionary] = []
var schema_warnings: PackedStringArray = PackedStringArray()

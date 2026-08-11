class_name RumbleGiftedSubscription
extends RefCounted

var purchased_by: String = ""
var total_gifts: int = 0
var remaining_gifts: int = 0
var gift_type: String = ""
var video_id: String = ""
var fingerprint: String = ""


func to_dictionary() -> Dictionary:
	return {
		"purchased_by": purchased_by,
		"total_gifts": total_gifts,
		"remaining_gifts": remaining_gifts,
		"gift_type": gift_type,
		"video_id": video_id,
		"fingerprint": fingerprint,
	}

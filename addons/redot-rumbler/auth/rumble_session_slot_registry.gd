class_name RumbleSessionSlotRegistry
extends RefCounted

## Adapted from redot-kicker commit 72a3abb747cac0e148352c04a88a53e0313bd72b,
## whose generic weak-owner registry derives from redot-tuber (MIT).
static var _owners: Dictionary = {}


static func acquire(qualified_slot: String, owner: Object) -> RumbleApiError:
	_cleanup()
	if qualified_slot.is_empty() or owner == null:
		return RumbleApiError.invalid("A qualified Rumbler session slot and owner are required")
	if _owners.has(qualified_slot):
		var existing: Object = (_owners[qualified_slot] as WeakRef).get_ref()
		if existing != null and existing != owner:
			return RumbleApiError.invalid("Rumbler session slot is already active in another RumbleLiveClient")
	_owners[qualified_slot] = weakref(owner)
	return null


static func release(qualified_slot: String, owner: Object) -> void:
	if not _owners.has(qualified_slot):
		return
	var existing: Object = (_owners[qualified_slot] as WeakRef).get_ref()
	if existing == null or existing == owner:
		_owners.erase(qualified_slot)


static func clear_for_tests() -> void:
	_owners.clear()


static func _cleanup() -> void:
	var expired := PackedStringArray()
	for slot: Variant in _owners:
		if (_owners[slot] as WeakRef).get_ref() == null:
			expired.append(str(slot))
	for slot: String in expired:
		_owners.erase(slot)

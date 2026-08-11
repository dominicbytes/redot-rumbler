class_name RumbleCancellationToken
extends RefCounted

signal cancelled(reason: String)

var _cancelled: bool = false
var _reason: String = ""


func cancel(reason: String = "cancelled") -> void:
	if _cancelled:
		return
	_cancelled = true
	_reason = reason
	cancelled.emit(_reason)


func is_cancelled() -> bool:
	return _cancelled


func reason() -> String:
	return _reason

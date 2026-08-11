class_name RumbleHttpTicket
extends RefCounted

signal completed(response: RumbleHttpResponse)

var id: int = 0
var is_completed: bool = false
var is_cancelled: bool = false
var cancellation_reason: String = ""
var response: RumbleHttpResponse = null


func _complete(value: RumbleHttpResponse) -> void:
	if is_completed:
		return
	response = value
	is_completed = true
	completed.emit(response)


func _mark_cancelled(reason: String) -> void:
	is_cancelled = true
	cancellation_reason = reason

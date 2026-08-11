class_name RumbleSessionDescriptorLoadResult
extends RefCounted

var descriptor: RumbleSessionDescriptor = null
var error: RumbleApiError = null


func is_success() -> bool:
	return descriptor != null and error == null

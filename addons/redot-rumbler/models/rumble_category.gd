class_name RumbleCategory
extends RefCounted

var slug: String = ""
var title: String = ""


func to_dictionary() -> Dictionary:
	return {"slug": slug, "title": title}

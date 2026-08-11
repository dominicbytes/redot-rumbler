extends SceneTree

var _checks: int = 0
var _failures: PackedStringArray = PackedStringArray()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for root_path: String in ["res://addons/redot-rumbler", "res://examples", "res://tests"]:
		_scan(root_path)
	var scene := ResourceLoader.load("res://examples/basic_connection.tscn")
	_check(scene is PackedScene, "example scene loads as PackedScene")
	if _failures.is_empty():
		print("REDOT RUMBLER PROJECT CHECK PASS: %d resources" % _checks)
		quit(0)
		return
	for failure: String in _failures:
		push_error("REDOT RUMBLER PROJECT CHECK FAIL: " + failure)
	quit(1)


func _scan(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		_failures.append("unable to open " + path)
		return
	directory.list_dir_begin()
	var name := directory.get_next()
	while not name.is_empty():
		if directory.current_is_dir():
			if not name.begins_with("."):
				_scan(path + "/" + name)
		elif name.ends_with(".gd") or name.ends_with(".tscn"):
			var resource_path := path + "/" + name
			_check(ResourceLoader.load(resource_path) != null, resource_path + " loads")
		name = directory.get_next()
	directory.list_dir_end()


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)

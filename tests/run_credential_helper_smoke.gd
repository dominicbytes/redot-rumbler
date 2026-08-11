extends SceneTree

var _checks: int = 0
var _failures: PackedStringArray = PackedStringArray()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	if OS.get_name() != "Windows":
		print("REDOT RUMBLER CREDENTIAL HELPER SMOKE SKIPPED: Windows-only host check")
		quit(0)
		return
	var helper := RumbleCredentialHelperClient.new()
	var target := "smoke/%d" % Time.get_ticks_usec()
	var first := "https://rumble.com/synthetic-smoke-one"
	var second := "https://rumble.com/synthetic-smoke-two"
	var ping: RumbleCredentialResult = await helper.ping()
	_check(ping.is_success() and ping.detail == "windows-credential-manager", "helper reaches Windows Credential Manager")
	var stored: RumbleCredentialResult = await helper.store(target, first)
	_check(stored.is_success(), "helper stores a synthetic API URL")
	var read_first: RumbleCredentialResult = await helper.read(target)
	_check(read_first.is_success() and read_first.secret == first, "helper reads the stored value through stdout payload only")
	read_first.clear_secret()
	var replaced: RumbleCredentialResult = await helper.store(target, second)
	_check(replaced.is_success(), "helper atomically replaces the credential record")
	var read_second: RumbleCredentialResult = await helper.read(target)
	_check(read_second.is_success() and read_second.secret == second, "helper reads the replacement value")
	read_second.clear_secret()
	var deleted: RumbleCredentialResult = await helper.delete(target)
	_check(deleted.is_success(), "helper deletes the test record")
	var absent: RumbleCredentialResult = await helper.read(target)
	_check(absent.status == "not_found", "deleted credential cannot be restored")
	await helper.delete(target)
	first = ""
	second = ""
	_finish()


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS: " + label)
	else:
		_failures.append(label)


func _finish() -> void:
	if _failures.is_empty():
		print("REDOT RUMBLER WINDOWS CREDENTIAL HELPER PASS: %d checks" % _checks)
		quit(0)
		return
	for failure: String in _failures:
		push_error("REDOT RUMBLER CREDENTIAL HELPER FAIL: " + failure)
	quit(1)

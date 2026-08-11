class_name RumbleConnectionPanel
extends VBoxContainer

var _client: RumbleLiveClient = null
var _url_input: LineEdit = null
var _status: Label = null
var _connect_button: Button = null
var _restore_button: Button = null
var _start_button: Button = null
var _stop_button: Button = null
var _clear_button: Button = null


func _ready() -> void:
	_build_ui()
	_update_controls()


func bind_client(client: RumbleLiveClient) -> void:
	_client = client
	if not is_node_ready():
		await ready
	client.state_changed.connect(_on_state_changed)
	client.error_occurred.connect(_on_error)
	client.credential_connected.connect(_on_credential_connected)
	client.credential_cleared.connect(_on_credential_cleared)
	_on_state_changed("", client.connection_state, "bound")


func _build_ui() -> void:
	if _url_input != null:
		return
	var heading := Label.new()
	heading.text = "Rumble Live Stream API"
	heading.add_theme_font_size_override("font_size", 20)
	add_child(heading)
	var guidance := Label.new()
	guidance.text = "Paste the private API URL at runtime. It is stored only in your operating-system vault. Rumbler is read-only."
	guidance.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(guidance)
	_url_input = LineEdit.new()
	_url_input.placeholder_text = "Private HTTPS Rumble API URL"
	_url_input.secret = true
	_url_input.secret_character = "•"
	_url_input.accessibility_name = "Private Rumble Live Stream API URL"
	add_child(_url_input)
	var buttons := HBoxContainer.new()
	add_child(buttons)
	_connect_button = _button("Connect", _on_connect_pressed, buttons)
	_restore_button = _button("Restore", _on_restore_pressed, buttons)
	_start_button = _button("Start", _on_start_pressed, buttons)
	_stop_button = _button("Stop", _on_stop_pressed, buttons)
	_clear_button = _button("Disconnect and clear", _on_clear_pressed, buttons)
	var manage_button := _button("Manage API URL", _on_manage_pressed, buttons)
	manage_button.tooltip_text = "Opens Rumble's API URL management page in your browser"
	_status = Label.new()
	_status.text = "Not configured"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)


func _button(label: String, callback: Callable, parent: Control) -> Button:
	var button := Button.new()
	button.text = label
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _on_connect_pressed() -> void:
	if _client == null:
		return
	var private_url := _url_input.text
	_url_input.clear()
	var error := await _client.connect_api_url(private_url)
	private_url = ""
	if error != null:
		_on_error(error)


func _on_restore_pressed() -> void:
	if _client == null:
		return
	var error := await _client.restore_connection()
	if error != null:
		_on_error(error)


func _on_start_pressed() -> void:
	if _client == null:
		return
	var error := _client.start_polling()
	if error != null:
		_on_error(error)


func _on_stop_pressed() -> void:
	if _client != null:
		_client.stop_polling()


func _on_clear_pressed() -> void:
	if _client == null:
		return
	var error := await _client.disconnect_and_clear()
	if error != null:
		_on_error(error)


func _on_manage_pressed() -> void:
	OS.shell_open(RumbleUrlPolicy.MANAGEMENT_URL)


func _on_state_changed(_previous: String, current: String, reason: String) -> void:
	if _status != null:
		_status.text = "Status: %s (%s)" % [current, reason]
	_update_controls()


func _on_error(error: RumbleApiError) -> void:
	if _status != null and error != null:
		_status.text = "Error: %s" % RumbleRedactor.redact_text(error.message)
	_update_controls()


func _on_credential_connected(_descriptor: RumbleSessionDescriptor, restored: bool) -> void:
	if _status != null:
		_status.text = "Credential %s. Start polling when ready." % ("restored" if restored else "stored")
	_update_controls()


func _on_credential_cleared() -> void:
	if _status != null:
		_status.text = "Credential and local state cleared"
	_update_controls()


func _update_controls() -> void:
	if _connect_button == null:
		return
	var configured := _client != null and _client.connection_state != "unconfigured"
	var connected := configured and _client.has_loaded_credential()
	var polling := configured and _client.connection_state in ["polling", "backoff"]
	_url_input.editable = configured and not polling
	_connect_button.disabled = not configured or polling
	_restore_button.disabled = not configured or connected or polling
	_start_button.disabled = not connected or polling
	_stop_button.disabled = not polling
	_clear_button.disabled = not connected and not configured

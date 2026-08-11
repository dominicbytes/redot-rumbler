extends Control

@export var publisher_id: String = "example-studio"
@export var application_id: String = "example-game"
@export var session_slot: String = "primary"

@onready var rumble_client: RumbleLiveClient = $RumbleLiveClient
@onready var connection_panel: RumbleConnectionPanel = $Margin/Content/ConnectionPanel
@onready var event_log: RichTextLabel = $Margin/Content/EventLog


func _ready() -> void:
	var config := RumbleClientConfig.new()
	config.publisher_id = publisher_id
	config.application_id = application_id
	var error := rumble_client.configure(config, session_slot)
	if error != null:
		push_error("Redot Rumbler example configuration failed: %s" % error.message)
		return
	connection_panel.bind_client(rumble_client)
	rumble_client.chat_message_received.connect(_on_chat_message)
	rumble_client.rant_received.connect(_on_rant)
	rumble_client.possible_event_gap.connect(_on_possible_gap)


func _on_chat_message(message: RumbleChatMessage) -> void:
	_append("CHAT %s: %s" % [message.username, message.text])


func _on_rant(rant: RumbleRantEvent) -> void:
	_append("RANT %s (%d cents): %s" % [rant.username, rant.amount_cents, rant.text])


func _on_possible_gap(details: Dictionary) -> void:
	_append("SOURCE WINDOW SATURATED: %d/%d recent items" % [details.observed_items, details.source_limit])


func _append(message: String) -> void:
	event_log.append_text(message + "\n")

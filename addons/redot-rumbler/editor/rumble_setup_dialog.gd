@tool
class_name RumbleSetupDialog
extends AcceptDialog


func _ready() -> void:
	title = "Redot Rumbler Setup"
	min_size = Vector2i(640, 360)
	var content := VBoxContainer.new()
	add_child(content)
	var heading := Label.new()
	heading.text = "Read-only Rumble integration"
	heading.add_theme_font_size_override("font_size", 20)
	content.add_child(heading)
	var body := Label.new()
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.text = (
		"Add a RumbleLiveClient to a runtime scene and configure non-secret publisher/application IDs in code. "
		+ "Users paste their private Live Stream API URL only in runtime UI. The addon stores that URL in Windows Credential Manager or Linux Secret Service; it never belongs in this dialog, a scene, project settings, logs, or source control.\n\n"
		+ "Supported: identity, followers, subscriptions, gifted subscriptions, livestream state, chat, rants, counters, and local inbound command routing.\n"
		+ "Unavailable in the official API: outbound chat, moderation, programmable rewards, raids, and verified media URLs."
	)
	content.add_child(body)
	var open_docs := Button.new()
	open_docs.text = "Open Rumble API management"
	open_docs.pressed.connect(func() -> void: OS.shell_open(RumbleUrlPolicy.MANAGEMENT_URL))
	content.add_child(open_docs)


func show_setup() -> void:
	popup_centered()

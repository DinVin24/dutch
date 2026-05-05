extends Control

@onready var setup_panel = $LeftMargin/VBox/SetupPanel
@onready var active_lobby_panel = $LeftMargin/VBox/ActiveLobbyPanel
@onready var name_edit = $LeftMargin/VBox/SetupPanel/HBoxName/NameEdit
@onready var code_edit = $LeftMargin/VBox/SetupPanel/HBoxConnection/CodeEdit
@onready var item_list = $LeftMargin/VBox/ActiveLobbyPanel/HBoxContainer/PlayersList/ItemList
@onready var room_code_label = $LeftMargin/VBox/ActiveLobbyPanel/HBoxRoomCode/RoomCodeLabel
@onready var copy_code_button = $LeftMargin/VBox/ActiveLobbyPanel/HBoxRoomCode/CopyCodeButton
@onready var start_button = $LeftMargin/VBox/ActiveLobbyPanel/StartButton
@onready var start_hint_label = $LeftMargin/VBox/ActiveLobbyPanel/StartHintLabel
@onready var settings_container = $LeftMargin/VBox/ActiveLobbyPanel/HBoxContainer/Settings
@onready var glitch_player = $GlitchSound

@onready var abilities_check = $LeftMargin/VBox/ActiveLobbyPanel/HBoxContainer/Settings/AbilitiesCheck
@onready var fill_bots_check = $LeftMargin/VBox/ActiveLobbyPanel/HBoxContainer/Settings/FillBotsCheck
@onready var beers_spinbox = $LeftMargin/VBox/ActiveLobbyPanel/HBoxContainer/Settings/HBoxBeers/BeersSpinBox
@onready var visibility_option = $LeftMargin/VBox/ActiveLobbyPanel/HBoxContainer/Settings/HBoxVisibility/VisibilityOption

var _btn_original: Dictionary = {}
var _btn_hover: Dictionary = {}

func _ready():
	GameManager.play_menu_music()
	NetworkManager.players_updated.connect(_update_lobby_ui)
	NetworkManager.match_settings_updated.connect(_update_lobby_ui)
	NetworkManager.game_started.connect(_on_game_started)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	NetworkManager.host_lan_ip_updated.connect(_on_host_lan_ip_updated)

	var host_btn = $LeftMargin/VBox/SetupPanel/HBoxConnection/HostButton
	var join_btn = $LeftMargin/VBox/SetupPanel/HBoxConnection/JoinButton
	host_btn.pressed.connect(_on_host_pressed)
	join_btn.pressed.connect(_on_join_pressed)
	start_button.pressed.connect(_on_start_pressed)
	$LeftMargin/VBox/BackButton.pressed.connect(_on_back_pressed)
	copy_code_button.pressed.connect(_on_copy_code_pressed)
	copy_code_button.hide()

	abilities_check.toggled.connect(_on_settings_changed)
	fill_bots_check.toggled.connect(_on_settings_changed)
	beers_spinbox.value_changed.connect(_on_settings_changed)
	visibility_option.item_selected.connect(_on_settings_changed)

	_register_arcade_button(host_btn, "HOST_SESSION", "HOST_SESSION")
	_register_arcade_button(join_btn, "JOIN_SESSION", "JOIN_SESSION")
	_register_arcade_button($LeftMargin/VBox/BackButton, "[ BACK_TO_MENU ]", "[ BACK_TO_MENU ]")
	_register_arcade_button(start_button, "> START_MATCH <", "> START_MATCH <")
	_register_arcade_button(copy_code_button, "COPY_CODE", "COPY_CODE")

func _register_arcade_button(btn: Button, original: String, hover: String):
	_btn_original[btn] = original
	_btn_hover[btn] = hover
	btn.mouse_entered.connect(_on_arcade_mouse_entered.bind(btn))
	btn.mouse_exited.connect(_on_arcade_mouse_exited.bind(btn))

func _on_arcade_mouse_entered(btn: Button):
	glitch_player.play_glitch_hover()
	btn.text = "> " + _btn_hover[btn]
	var tween = create_tween()
	tween.tween_property(btn, "scale", Vector2(1.06, 1.06), 0.1).set_trans(Tween.TRANS_QUAD)

func _on_arcade_mouse_exited(btn: Button):
	btn.text = _btn_original[btn]
	var tween = create_tween()
	tween.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.1).set_trans(Tween.TRANS_QUAD)

func _play_click():
	glitch_player.play_glitch_click()

func _on_host_pressed():
	_play_click()
	if name_edit.text.strip_edges() == "":
		return
	NetworkManager.set_local_player_name(name_edit.text)
	if NetworkManager.host_game():
		_transition_to_lobby(true)

func _on_join_pressed():
	_play_click()
	if name_edit.text.strip_edges() == "":
		return
	if code_edit.text.strip_edges() == "":
		return
	NetworkManager.set_local_player_name(name_edit.text)
	if NetworkManager.join_game(code_edit.text):
		_transition_to_lobby(false)

func _transition_to_lobby(is_host: bool):
	setup_panel.hide()
	active_lobby_panel.show()

	if is_host:
		_refresh_host_room_label()
		copy_code_button.show()
		start_button.show()
		start_hint_label.show()
		_enable_settings(true)
	else:
		room_code_label.text = "Connected to Host"
		copy_code_button.hide()
		start_button.hide()
		start_hint_label.hide()
		_enable_settings(false)

	_update_lobby_ui()

func _enable_settings(enabled: bool):
	abilities_check.disabled = not enabled
	fill_bots_check.disabled = not enabled
	beers_spinbox.editable = enabled
	visibility_option.disabled = not enabled

func _human_player_count() -> int:
	return NetworkManager.players.size()

func _update_lobby_ui():
	item_list.clear()
	var players = NetworkManager.players
	for id in players:
		var info = players[id]
		var suffix = " (Host)" if info.get("is_host", false) else ""
		var text = str(info["name"]) + suffix
		if id == multiplayer.get_unique_id():
			text += " [You]"
		item_list.add_item(text)

	if not NetworkManager.local_player_info["is_host"]:
		var s = NetworkManager.match_settings
		abilities_check.button_pressed = s.get("no_abilities", false)
		fill_bots_check.button_pressed = s.get("fill_bots", false)
		beers_spinbox.value = s.get("beers", 3)
		visibility_option.selected = s.get("cards_visibility", 0)

	if NetworkManager.local_player_info["is_host"]:
		_refresh_host_room_label()
		var h = _human_player_count()
		var can_start = h >= 2
		start_button.disabled = not can_start
		if can_start:
			start_hint_label.text = "Ready: %d human(s). Toggle bots to pad to 4 seats." % h
		else:
			start_hint_label.text = "Need at least 2 human players to start."

func _on_settings_changed(_val = null):
	if NetworkManager.local_player_info["is_host"]:
		var new_settings = {
			"no_abilities": abilities_check.button_pressed,
			"fill_bots": fill_bots_check.button_pressed,
			"beers": int(beers_spinbox.value),
			"cards_visibility": visibility_option.selected
		}
		NetworkManager.sync_match_settings.rpc(new_settings)

func _on_start_pressed():
	if not NetworkManager.local_player_info["is_host"]:
		return
	var h = _human_player_count()
	if h < 2:
		return
	_play_click()
	_on_settings_changed()
	var fill = fill_bots_check.button_pressed
	var total: int = 4 if fill else h
	total = clampi(total, 2, 4)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var deck_seed: int = rng.randi()
	NetworkManager.start_match.rpc(total, deck_seed)

func _on_game_started():
	get_tree().change_scene_to_file("res://game_board_3d.tscn")

func _on_server_disconnected():
	setup_panel.show()
	active_lobby_panel.hide()
	NetworkManager.leave_game()

func _on_host_lan_ip_updated(_ip: String):
	if active_lobby_panel.visible and NetworkManager.local_player_info["is_host"]:
		_refresh_host_room_label()

func _refresh_host_room_label():
	var code = NetworkManager.get_room_code()
	var host_ip = NetworkManager.get_detected_host_lan_ip()
	room_code_label.text = "Room Code: %s | Host IP: %s" % [code, host_ip]

func _on_copy_code_pressed():
	_play_click()
	var code = NetworkManager.get_room_code()
	DisplayServer.clipboard_set(code)
	copy_code_button.text = "> COPIED <"
	await get_tree().create_timer(2.0).timeout
	copy_code_button.text = "COPY_CODE"

func _on_back_pressed():
	_play_click()
	NetworkManager.leave_game()
	get_tree().change_scene_to_file("res://main_menu.tscn")

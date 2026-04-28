extends Control

@onready var setup_panel = $MarginContainer/VBoxContainer/SetupPanel
@onready var active_lobby_panel = $MarginContainer/VBoxContainer/ActiveLobbyPanel
@onready var name_edit = $MarginContainer/VBoxContainer/SetupPanel/HBoxName/NameEdit
@onready var code_edit = $MarginContainer/VBoxContainer/SetupPanel/HBoxConnection/CodeEdit
@onready var item_list = $MarginContainer/VBoxContainer/ActiveLobbyPanel/HBoxContainer/PlayersList/ItemList
@onready var room_code_label = $MarginContainer/VBoxContainer/ActiveLobbyPanel/HBoxRoomCode/RoomCodeLabel
@onready var copy_code_button = $MarginContainer/VBoxContainer/ActiveLobbyPanel/HBoxRoomCode/CopyCodeButton
@onready var start_button = $MarginContainer/VBoxContainer/ActiveLobbyPanel/StartButton
@onready var settings_container = $MarginContainer/VBoxContainer/ActiveLobbyPanel/HBoxContainer/Settings

# Setting nodes
@onready var abilities_check = $MarginContainer/VBoxContainer/ActiveLobbyPanel/HBoxContainer/Settings/AbilitiesCheck
@onready var beers_spinbox = $MarginContainer/VBoxContainer/ActiveLobbyPanel/HBoxContainer/Settings/HBoxBeers/BeersSpinBox
@onready var visibility_option = $MarginContainer/VBoxContainer/ActiveLobbyPanel/HBoxContainer/Settings/HBoxVisibility/VisibilityOption

func _ready():
	NetworkManager.players_updated.connect(_update_lobby_ui)
	NetworkManager.match_settings_updated.connect(_update_lobby_ui)
	NetworkManager.game_started.connect(_on_game_started)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	
	$MarginContainer/VBoxContainer/SetupPanel/HBoxConnection/HostButton.pressed.connect(_on_host_pressed)
	$MarginContainer/VBoxContainer/SetupPanel/HBoxConnection/JoinButton.pressed.connect(_on_join_pressed)
	start_button.pressed.connect(_on_start_pressed)
	$MarginContainer/VBoxContainer/BackButton.pressed.connect(_on_back_pressed)
	copy_code_button.pressed.connect(_on_copy_code_pressed)
	copy_code_button.hide() # Hidden until host connects
	
	# Connect settings changed
	abilities_check.toggled.connect(_on_settings_changed)
	beers_spinbox.value_changed.connect(_on_settings_changed)
	visibility_option.item_selected.connect(_on_settings_changed)

func _on_host_pressed():
	if name_edit.text.strip_edges() == "": return
	NetworkManager.set_local_player_name(name_edit.text)
	if NetworkManager.host_game():
		_transition_to_lobby(true)

func _on_join_pressed():
	if name_edit.text.strip_edges() == "": return
	if code_edit.text.strip_edges() == "": return
	NetworkManager.set_local_player_name(name_edit.text)
	if NetworkManager.join_game(code_edit.text):
		_transition_to_lobby(false)

func _transition_to_lobby(is_host: bool):
	setup_panel.hide()
	active_lobby_panel.show()
	
	if is_host:
		var code = NetworkManager.get_room_code()
		room_code_label.text = "Room Code: " + code
		copy_code_button.show()
		start_button.show()
		_enable_settings(true)
	else:
		room_code_label.text = "Connected to Host"
		start_button.hide()
		_enable_settings(false)
	
	_update_lobby_ui()

func _enable_settings(enabled: bool):
	abilities_check.disabled = !enabled
	beers_spinbox.editable = enabled
	visibility_option.disabled = !enabled

func _update_lobby_ui():
	item_list.clear()
	var players = NetworkManager.players
	for id in players:
		var info = players[id]
		var suffix = " (Host)" if info["is_host"] else ""
		var text = str(info["name"]) + suffix
		if id == multiplayer.get_unique_id():
			text += " [You]"
		item_list.add_item(text)
		
	# If not host, sync UI with settings from NetworkManager
	if not NetworkManager.local_player_info["is_host"]:
		var s = NetworkManager.match_settings
		abilities_check.button_pressed = s["no_abilities"]
		beers_spinbox.value = s["beers"]
		visibility_option.selected = s["cards_visibility"]

func _on_settings_changed(_val = null):
	if NetworkManager.local_player_info["is_host"]:
		var new_settings = {
			"no_abilities": abilities_check.button_pressed,
			"beers": int(beers_spinbox.value),
			"cards_visibility": visibility_option.selected
		}
		NetworkManager.sync_match_settings.rpc(new_settings)

func _on_start_pressed():
	if NetworkManager.local_player_info["is_host"]:
		# Ensure settings are synced one last time before starting
		_on_settings_changed()
		NetworkManager.start_game.rpc()

func _on_game_started():
	# Transition to game board
	get_tree().change_scene_to_file("res://game_board_3d.tscn")

func _on_server_disconnected():
	setup_panel.show()
	active_lobby_panel.hide()
	NetworkManager.leave_game()

func _on_copy_code_pressed():
	var code = NetworkManager.get_room_code()
	DisplayServer.clipboard_set(code)
	# Visual feedback: temporarily change button text
	copy_code_button.text = "✔ Copied!"
	await get_tree().create_timer(2.0).timeout
	copy_code_button.text = "📋 Copy"

func _on_back_pressed():
	NetworkManager.leave_game()
	get_tree().change_scene_to_file("res://main_menu.tscn")

extends Control

@onready var setup_panel = $CenterContainer/SetupPanel
@onready var room_panel = $CenterContainer/RoomPanel

@onready var ip_line_edit = $CenterContainer/SetupPanel/IPLineEdit
@onready var player_list = $CenterContainer/RoomPanel/PlayerList
@onready var start_button = $CenterContainer/RoomPanel/StartButton

func _ready() -> void:
	# Hide room panel initially
	setup_panel.show()
	room_panel.hide()
	
	NetworkManager.lobby_roster_updated.connect(_update_lobby_ui)
	NetworkManager.connected_to_server.connect(_on_connected_ok)
	NetworkManager.connection_failed.connect(_on_connection_fail)
	GameManager.play_menu_music()

func _on_host_pressed() -> void:
	var err = NetworkManager.host_game()
	if err == OK:
		_transition_to_room()
	else:
		print("Failed to host! Error code: ", err)

func _on_join_pressed() -> void:
	var ip = ip_line_edit.text
	var err = NetworkManager.join_game(ip)
	if err != OK:
		print("Failed to start join process! Error code: ", err)
	else:
		# Wait for _on_connected_ok signal to transition
		pass

func _on_connected_ok() -> void:
	_transition_to_room()

func _on_connection_fail() -> void:
	print("Connection failed callback.")
	setup_panel.show()
	room_panel.hide()

func _transition_to_room() -> void:
	setup_panel.hide()
	room_panel.show()
	_update_lobby_ui()

func _update_lobby_ui() -> void:
	# Clear list
	for child in player_list.get_children():
		child.queue_free()
		
	# Populate list
	for id in NetworkManager.players:
		var p_info = NetworkManager.players[id]
		var label = Label.new()
		label.text = p_info.name + (" (Host)" if id == 1 else "")
		label.add_theme_font_size_override("font_size", 24)
		player_list.add_child(label)
		
	# Start button only for Host when we have players
	if multiplayer.is_server():
		start_button.show()
		# For production, we can enforce exactly 4 players:
		# start_button.disabled = NetworkManager.players.size() < 4
	else:
		start_button.hide()

func _on_start_game_pressed() -> void:
	if multiplayer.is_server():
		# Use RPC to tell everyone to start the game
		rpc("start_game_rpc")

@rpc("authority", "call_local", "reliable")
func start_game_rpc() -> void:
	# Transition to game board for everyone
	# The game manager will use NetworkManager.players to assign seats
	get_tree().change_scene_to_file("res://game_board_3d.tscn")

func _on_back_pressed() -> void:
	NetworkManager.stop_network()
	get_tree().change_scene_to_file("res://main_menu.tscn")

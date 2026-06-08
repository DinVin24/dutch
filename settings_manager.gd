extends Node

const SETTINGS_FILE_PATH = "user://settings.cfg"

const CONFIGURABLE_ACTIONS = [
	"game_end_turn",
	"game_jump_in",
	"game_call_dutch",
	"game_draw_card",
	"game_select_left",
	"game_select_right",
	"game_confirm_card",
	"game_discard_drawn",
	"game_forfeit_dutch"
]

var config = ConfigFile.new()

func _ready() -> void:
	load_and_apply_settings()

func load_and_apply_settings() -> void:
	var err = config.load(SETTINGS_FILE_PATH)
	if err != OK:
		return # No settings saved yet, use defaults

	# Audio
	if config.has_section_key("audio", "music_volume"):
		var bus_idx = AudioServer.get_bus_index("Music")
		if bus_idx >= 0:
			AudioServer.set_bus_volume_db(bus_idx, config.get_value("audio", "music_volume"))
			
	if config.has_section_key("audio", "sfx_volume"):
		var bus_idx = AudioServer.get_bus_index("SFX")
		if bus_idx >= 0:
			AudioServer.set_bus_volume_db(bus_idx, config.get_value("audio", "sfx_volume"))

	# Display
	if config.has_section_key("display", "resolution"):
		DisplayServer.window_set_size(config.get_value("display", "resolution"))
		
	if config.has_section_key("display", "window_mode"):
		DisplayServer.window_set_mode(config.get_value("display", "window_mode"))

	# Controls
	if config.has_section_key("controls", "dev_console"):
		GameManager.dev_console_enabled = config.get_value("controls", "dev_console")

	# Gameplay
	if config.has_section_key("gameplay", "show_game_assistant"):
		GameManager.show_game_assistant = bool(config.get_value("gameplay", "show_game_assistant", true))
	if config.has_section_key("gameplay", "assistant_deep_reasoning"):
		GameManager.assistant_deep_reasoning = bool(config.get_value("gameplay", "assistant_deep_reasoning", true))
	if config.has_section_key("gameplay", "assistant_lm_enabled"):
		GameManager.assistant_lm_enabled = bool(config.get_value("gameplay", "assistant_lm_enabled", true))
	if config.has_section_key("gameplay", "llm_player_enabled"):
		GameManager.llm_player_enabled = bool(config.get_value("gameplay", "llm_player_enabled", true))

	for action in CONFIGURABLE_ACTIONS:
		if config.has_section_key("keybinds", action):
			var keycode = config.get_value("keybinds", action)
			var new_event = InputEventKey.new()
			new_event.physical_keycode = keycode
			InputMap.action_erase_events(action)
			InputMap.action_add_event(action, new_event)

func save_settings() -> void:
	# Audio
	var music_idx = AudioServer.get_bus_index("Music")
	if music_idx >= 0:
		config.set_value("audio", "music_volume", AudioServer.get_bus_volume_db(music_idx))
		
	var sfx_idx = AudioServer.get_bus_index("SFX")
	if sfx_idx >= 0:
		config.set_value("audio", "sfx_volume", AudioServer.get_bus_volume_db(sfx_idx))

	# Display
	config.set_value("display", "resolution", DisplayServer.window_get_size())
	config.set_value("display", "window_mode", DisplayServer.window_get_mode())

	# Controls
	config.set_value("controls", "dev_console", GameManager.dev_console_enabled)

	# Gameplay
	config.set_value("gameplay", "show_game_assistant", GameManager.show_game_assistant)
	config.set_value("gameplay", "assistant_deep_reasoning", GameManager.assistant_deep_reasoning)
	config.set_value("gameplay", "assistant_lm_enabled", GameManager.assistant_lm_enabled)
	config.set_value("gameplay", "llm_player_enabled", GameManager.llm_player_enabled)

	for action in CONFIGURABLE_ACTIONS:
		var events = InputMap.action_get_events(action)
		for e in events:
			if e is InputEventKey:
				config.set_value("keybinds", action, e.physical_keycode)
				break

	config.save(SETTINGS_FILE_PATH)

func get_last_room_code() -> String:
	if config.has_section_key("multiplayer", "last_room_code"):
		return str(config.get_value("multiplayer", "last_room_code", ""))
	return ""

func set_last_room_code(code: String) -> void:
	var trimmed := code.strip_edges().to_upper()
	if trimmed == "":
		return
	config.set_value("multiplayer", "last_room_code", trimmed)
	config.save(SETTINGS_FILE_PATH)

func get_player_name() -> String:
	if config.has_section_key("multiplayer", "player_name"):
		return str(config.get_value("multiplayer", "player_name", ""))
	return ""

func set_player_name(name: String) -> void:
	var trimmed := name.strip_edges()
	if trimmed == "":
		return
	config.set_value("multiplayer", "player_name", trimmed)
	config.save(SETTINGS_FILE_PATH)

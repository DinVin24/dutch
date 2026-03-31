extends Control

signal back_pressed

@onready var resolution_option: OptionButton = $BackgroundTint/VBoxContainer/GridContainer/ResolutionOption
@onready var window_mode_option: OptionButton = $BackgroundTint/VBoxContainer/GridContainer/WindowModeOption
@onready var music_slider: HSlider = $BackgroundTint/VBoxContainer/GridContainer/MusicSlider
@onready var sfx_slider: HSlider = $BackgroundTint/VBoxContainer/GridContainer/SFXSlider
@onready var dev_console_check: CheckBox = $BackgroundTint/VBoxContainer/GridContainer/DevConsoleCheck
	
var resolutions = [
	Vector2i(1152, 648),
	Vector2i(1280, 720),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440)
]

func _ready() -> void:
	# Resolution Setup
	resolution_option.clear()
	for res in resolutions:
		resolution_option.add_item(str(res.x) + "x" + str(res.y))
	
	var current_size = DisplayServer.window_get_size()
	var res_index = 0
	for i in range(resolutions.size()):
		if resolutions[i] == current_size:
			res_index = i
	resolution_option.select(res_index)
	
	# Window Mode Setup
	window_mode_option.clear()
	window_mode_option.add_item("Windowed", DisplayServer.WINDOW_MODE_WINDOWED)
	window_mode_option.add_item("Fullscreen", DisplayServer.WINDOW_MODE_FULLSCREEN)
	
	var current_mode = DisplayServer.window_get_mode()
	var mode_idx = 0
	for i in range(window_mode_option.item_count):
		if window_mode_option.get_item_id(i) == current_mode:
			mode_idx = i
	window_mode_option.select(mode_idx)
	
	# Audio Setup
	var music_bus = AudioServer.get_bus_index("Music")
	var sfx_bus = AudioServer.get_bus_index("SFX")
	
	if music_bus >= 0:
		music_slider.value = db_to_linear(AudioServer.get_bus_volume_db(music_bus))
	if sfx_bus >= 0:
		sfx_slider.value = db_to_linear(AudioServer.get_bus_volume_db(sfx_bus))
	
	dev_console_check.button_pressed = GameManager.dev_console_enabled
	_populate_keybind_buttons()

func _on_resolution_selected(index: int) -> void:
	DisplayServer.window_set_size(resolutions[index])
	# Center window if windowed
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED:
		var screen_size = DisplayServer.screen_get_size()
		var window_size = DisplayServer.window_get_size()
		DisplayServer.window_set_position((screen_size - window_size) / 2.0)

func _on_window_mode_selected(index: int) -> void:
	var mode = window_mode_option.get_item_id(index)
	DisplayServer.window_set_mode(mode)

func _on_music_value_changed(value: float) -> void:
	var bus_idx = AudioServer.get_bus_index("Music")
	if bus_idx >= 0:
		AudioServer.set_bus_volume_db(bus_idx, linear_to_db(value))

func _on_sfx_value_changed(value: float) -> void:
	var bus_idx = AudioServer.get_bus_index("SFX")
	if bus_idx >= 0:
		AudioServer.set_bus_volume_db(bus_idx, linear_to_db(value))

func _on_back_button_pressed() -> void:
	back_pressed.emit()
	queue_free()

func _on_dev_console_toggled(toggled_on: bool) -> void:
	GameManager.dev_console_enabled = toggled_on

# ── KEYBINDS ──────────────────────────────────────────────────────────────────

# Maps action name -> NodePath string (relative to this node) of its bind Button
const KEYBIND_ACTIONS: Dictionary = {
	"game_end_turn":     "BackgroundTint/VBoxContainer/KeybindsGrid/EndTurnBind",
	"game_jump_in":      "BackgroundTint/VBoxContainer/KeybindsGrid/JumpInBind",
	"game_call_dutch":   "BackgroundTint/VBoxContainer/KeybindsGrid/CallDutchBind",
	"game_draw_card":    "BackgroundTint/VBoxContainer/KeybindsGrid/DrawCardBind",
	"game_select_left":  "BackgroundTint/VBoxContainer/KeybindsGrid/SelectLeftBind",
	"game_select_right": "BackgroundTint/VBoxContainer/KeybindsGrid/SelectRightBind",
	"game_confirm_card": "BackgroundTint/VBoxContainer/KeybindsGrid/ConfirmCardBind",
	"game_discard_drawn":"BackgroundTint/VBoxContainer/KeybindsGrid/DiscardDrawnBind",
}

var _listening_action: String = ""
var _listening_button: Button = null

func _populate_keybind_buttons() -> void:
	for action in KEYBIND_ACTIONS:
		var btn: Button = get_node(KEYBIND_ACTIONS[action])
		btn.text = _get_key_label(action)

func _get_key_label(action: String) -> String:
	var events = InputMap.action_get_events(action)
	for e in events:
		if e is InputEventKey:
			return OS.get_keycode_string(e.physical_keycode)
	return "—"

func _on_keybind_button_pressed(action: String, node_path: String) -> void:
	# If already listening for another key, reset that button first
	if _listening_button != null:
		_listening_button.text = _get_key_label(_listening_action)

	_listening_action = action
	_listening_button = get_node(node_path)
	_listening_button.text = "[ press a key... ]"

func _input(event: InputEvent) -> void:
	# Settings menu: Escape closes settings
	if event.is_action_pressed("ui_cancel"):
		if DevConsole and DevConsole.window.is_visible():
			return
		_on_back_button_pressed()
		get_viewport().set_input_as_handled()
		return

	# Rebind listening
	if _listening_action == "": return
	if not (event is InputEventKey and event.pressed and not event.echo): return

	# Escape cancels rebinding
	if event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE:
		_listening_button.text = _get_key_label(_listening_action)
		_listening_action = ""
		_listening_button = null
		get_viewport().set_input_as_handled()
		return

	# Apply the new binding
	var new_event = InputEventKey.new()
	new_event.physical_keycode = event.physical_keycode
	InputMap.action_erase_events(_listening_action)
	InputMap.action_add_event(_listening_action, new_event)

	_listening_button.text = _get_key_label(_listening_action)
	_listening_action = ""
	_listening_button = null
	get_viewport().set_input_as_handled()


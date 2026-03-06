extends Control

signal back_pressed

@onready var resolution_option: OptionButton = $Panel/VBoxContainer/GridContainer/ResolutionOption
@onready var window_mode_option: OptionButton = $Panel/VBoxContainer/GridContainer/WindowModeOption
@onready var music_slider: HSlider = $Panel/VBoxContainer/GridContainer/MusicSlider
@onready var sfx_slider: HSlider = $Panel/VBoxContainer/GridContainer/SFXSlider
@onready var keybinds_container: VBoxContainer = $Panel/VBoxContainer/KeybindsScroll/KeybindsContainer

var resolutions = [
	Vector2i(1152, 648),
	Vector2i(1280, 720),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440)
]

var actions_to_remap = {
	"ui_accept": "Accept / Interact",
	"ui_cancel": "Cancel",
	"ui_up": "Up",
	"ui_down": "Down",
	"ui_left": "Left",
	"ui_right": "Right"
}

var is_remapping = false
var remapping_action_name = ""
var remapping_button: Button = null

func _ready() -> void:
	# Resolution Setup
	for res in resolutions:
		resolution_option.add_item(str(res.x) + "x" + str(res.y))
	
	var current_size = DisplayServer.window_get_size()
	var res_index = 0
	for i in range(resolutions.size()):
		if resolutions[i] == current_size:
			res_index = i
	resolution_option.select(res_index)
	
	# Window Mode Setup
	window_mode_option.add_item("Windowed", DisplayServer.WINDOW_MODE_WINDOWED)
	window_mode_option.add_item("Fullscreen", DisplayServer.WINDOW_MODE_FULLSCREEN)
	window_mode_option.add_item("Exclusive Fullscreen", DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	
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
		
	# Keybinds Setup
	_create_keybind_ui()

func _create_keybind_ui() -> void:
	for child in keybinds_container.get_children():
		child.queue_free()
		
	for action in actions_to_remap:
		var hbox = HBoxContainer.new()
		
		var label = Label.new()
		label.text = actions_to_remap[action]
		label.custom_minimum_size = Vector2(150, 0)
		
		var button = Button.new()
		button.text = _get_action_key_name(action)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_on_keybind_button_pressed.bind(button, action))
		
		hbox.add_child(label)
		hbox.add_child(button)
		keybinds_container.add_child(hbox)

func _get_action_key_name(action: String) -> String:
	var events = InputMap.action_get_events(action)
	for event in events:
		if event is InputEventKey:
			return OS.get_keycode_string(event.physical_keycode if event.physical_keycode != 0 else event.keycode)
		elif event is InputEventMouseButton:
			return "Mouse Button " + str(event.button_index)
	return "Unbound"

func _on_keybind_button_pressed(button: Button, action: String) -> void:
	is_remapping = true
	remapping_action_name = action
	remapping_button = button
	button.text = "Press any key..."

func _input(event: InputEvent) -> void:
	if is_remapping:
		if event is InputEventKey or event is InputEventMouseButton:
			if event.is_pressed():
				# Remove old events and add new one
				InputMap.action_erase_events(remapping_action_name)
				InputMap.action_add_event(remapping_action_name, event)
				
				# Update UI button text
				remapping_button.text = _get_action_key_name(remapping_action_name)
				
				is_remapping = false
				remapping_action_name = ""
				remapping_button = null
				
				get_viewport().set_input_as_handled()

func _on_resolution_selected(index: int) -> void:
	DisplayServer.window_set_size(resolutions[index])
	# Center window if windowed
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED:
		var screen_size = DisplayServer.screen_get_size()
		var window_size = DisplayServer.window_get_size()
		DisplayServer.window_set_position(screen_size / 2 - window_size / 2)

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

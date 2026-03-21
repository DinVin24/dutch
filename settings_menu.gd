extends Control

signal back_pressed

@onready var GameManager = get_node("/root/GameManager")
@onready var DevConsole = get_node_or_null("/root/DevConsole")
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

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if DevConsole and DevConsole.window.is_visible():
			return
		_on_back_button_pressed()
		get_viewport().set_input_as_handled()

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

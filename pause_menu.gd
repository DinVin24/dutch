extends CanvasLayer

signal resumed
signal main_menu_requested

@onready var vbox: VBoxContainer = $CenterContainer/PanelContainer/VBoxContainer

var settings_menu_scene = preload("res://settings_menu.tscn")
var settings_instance: Node = null

func _ready() -> void:
	pass

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		# Let the developer console handle Esc if it's visible
		if is_instance_valid(DevConsole) and is_instance_valid(DevConsole.window) and DevConsole.window.visible:
			return
			
		if settings_instance != null:
			_on_settings_back()
		else:
			resumed.emit()
		get_viewport().set_input_as_handled()

func _on_resume_button_pressed() -> void:
	resumed.emit()

func _on_main_menu_button_pressed() -> void:
	main_menu_requested.emit()

# Bug 4: Open settings overlay while match stays paused.
func _on_settings_button_pressed() -> void:
	if settings_instance != null:
		return  # Already open
	settings_instance = settings_menu_scene.instantiate()
	add_child(settings_instance)
	settings_instance.back_pressed.connect(_on_settings_back)
	if vbox: vbox.hide()

func _on_settings_back() -> void:
	if settings_instance:
		settings_instance.queue_free()
		settings_instance = null
	if vbox: vbox.show()

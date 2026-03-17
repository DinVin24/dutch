extends CanvasLayer

signal resumed
signal main_menu_requested

@onready var vbox: VBoxContainer = $CenterContainer/VBoxContainer

var settings_menu_scene = preload("res://settings_menu.tscn")
var settings_instance: Node = null

func _ready() -> void:
	pass

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
	vbox.hide()

func _on_settings_back() -> void:
	if settings_instance:
		settings_instance.queue_free()
		settings_instance = null
	vbox.show()

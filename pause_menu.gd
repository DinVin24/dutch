extends CanvasLayer

signal resumed
signal main_menu_requested

func _ready() -> void:
	pass

func _on_resume_button_pressed() -> void:
	resumed.emit()

func _on_main_menu_button_pressed() -> void:
	main_menu_requested.emit()

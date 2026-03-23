extends Control

var settings_instance: Node = null

func _ready() -> void:
	GameManager.play_menu_music()

func _on_start_button_pressed() -> void:
	get_tree().change_scene_to_file("res://game_board_3d.tscn")

func _on_settings_button_pressed() -> void:
	if is_instance_valid(settings_instance):
		return
	var settings_scene = preload("res://settings_menu.tscn")
	settings_instance = settings_scene.instantiate()
	add_child(settings_instance)
	settings_instance.back_pressed.connect(_on_settings_back)
	$CenterContainer.hide()

func _on_settings_back() -> void:
	if is_instance_valid(settings_instance):
		settings_instance.queue_free()
		settings_instance = null
	$CenterContainer.show()

func _on_exit_button_pressed() -> void:
	get_tree().quit()

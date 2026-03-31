extends Control

@onready var start_button = $LeftMargin/VBox/Buttons/StartButton
@onready var settings_button = $LeftMargin/VBox/Buttons/SettingsButton
@onready var exit_button = $LeftMargin/VBox/Buttons/ExitButton
@onready var glitch_player = $GlitchSound

var original_texts = {
	"Start": "START_FILE",
	"Settings": "SYSTEM_CFG",
	"Exit": "SHUT_DOWN"
}

func _ready() -> void:
	GameManager.play_menu_music()
	
	# Connect mouse_exited for all buttons
	start_button.mouse_exited.connect(_on_button_mouse_exited.bind(start_button, "Start"))
	settings_button.mouse_exited.connect(_on_button_mouse_exited.bind(settings_button, "Settings"))
	exit_button.mouse_exited.connect(_on_button_mouse_exited.bind(exit_button, "Exit"))

func _on_button_mouse_entered(type: String) -> void:
	glitch_player.play_glitch_hover()
	var btn = get_node("LeftMargin/VBox/Buttons/" + type + "Button")
	btn.text = "> " + original_texts[type]
	
	# Subtle hover scale tween
	var tween = create_tween()
	tween.tween_property(btn, "scale", Vector2(1.1, 1.1), 0.1).set_trans(Tween.TRANS_QUAD)

func _on_button_mouse_exited(btn: Button, type: String) -> void:
	btn.text = original_texts[type]
	var tween = create_tween()
	tween.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.1).set_trans(Tween.TRANS_QUAD)

func _on_start_button_pressed() -> void:
	glitch_player.play_glitch_click()
	# Brief delay for click sound to be heard
	await get_tree().create_timer(0.2).timeout
	get_tree().change_scene_to_file("res://game_board_3d.tscn")

func _on_settings_button_pressed() -> void:
	glitch_player.play_glitch_click()
	var settings_scene = preload("res://settings_menu.tscn")
	var settings_instance = settings_scene.instantiate()
	add_child(settings_instance)
	settings_instance.back_pressed.connect(_on_settings_back)
	$LeftMargin.hide()

func _on_settings_back() -> void:
	$LeftMargin.show()

func _on_exit_button_pressed() -> void:
	glitch_player.play_glitch_click()
	await get_tree().create_timer(0.5).timeout
	get_tree().quit()

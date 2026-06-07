extends Control

@onready var start_button = $LeftMargin/VBox/Buttons/StartButton
@onready var settings_button = $LeftMargin/VBox/Buttons/SettingsButton
@onready var exit_button = $LeftMargin/VBox/Buttons/ExitButton
@onready var glitch_player = $GlitchSound
@onready var difficulty_prompt = $DifficultyPrompt

var original_texts = {
	"Start": "START_FILE",
	"Multiplayer": "MULTIPLAYER",
	"Settings": "SYSTEM_CFG",
	"Exit": "SHUT_DOWN"
}

var hover_texts = {
	"Start": "START_FILE",
	"Multiplayer": "MULTIPLAYER",
	"Settings": "SYSTEM_CFG",
	"Exit": "SHUT_DOWN"
}

func _ready() -> void:
	GameManager.play_menu_music()
	difficulty_prompt.visible = false

	# Connect mouse_exited for all buttons
	start_button.mouse_exited.connect(_on_button_mouse_exited.bind(start_button, "Start"))
	var mp_btn = $LeftMargin/VBox/Buttons/MultiplayerButton
	mp_btn.mouse_exited.connect(_on_button_mouse_exited.bind(mp_btn, "Multiplayer"))
	settings_button.mouse_exited.connect(_on_button_mouse_exited.bind(settings_button, "Settings"))
	exit_button.mouse_exited.connect(_on_button_mouse_exited.bind(exit_button, "Exit"))
	if not get_viewport().size_changed.is_connected(_apply_responsive_layout):
		get_viewport().size_changed.connect(_apply_responsive_layout)
	call_deferred("_apply_responsive_layout")

func _apply_responsive_layout() -> void:
	var left_margin: Control = $LeftMargin
	left_margin.anchor_right = 0.92 if ResponsiveUI.is_narrow_screen() else 0.42
	$LeftMargin/VBox/Title.add_theme_font_size_override("font_size", ResponsiveUI.scaled_font(86))
	for btn_name in ["StartButton", "MultiplayerButton", "SettingsButton", "ExitButton"]:
		var btn: Button = $LeftMargin/VBox/Buttons.get_node(btn_name)
		btn.add_theme_font_size_override("font_size", ResponsiveUI.scaled_font(38))
	for btn_name in ["NormalButton", "EasyButton", "TutorialButton"]:
		var btn: Button = $DifficultyPrompt/Panel.get_node(btn_name)
		btn.add_theme_font_size_override("font_size", ResponsiveUI.scaled_font(26))
	$DifficultyPrompt/Panel/TitleBar/TitleLabel.add_theme_font_size_override("font_size", ResponsiveUI.scaled_font(30))

func _on_button_mouse_entered(type: String) -> void:
	glitch_player.play_glitch_hover()
	var btn = get_node("LeftMargin/VBox/Buttons/" + type + "Button")
	btn.text = "> " + hover_texts[type]

	var tween = create_tween()
	tween.tween_property(btn, "scale", Vector2(1.1, 1.1), 0.1).set_trans(Tween.TRANS_QUAD)

func _on_button_mouse_exited(btn: Button, type: String) -> void:
	btn.text = original_texts[type]
	var tween = create_tween()
	tween.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.1).set_trans(Tween.TRANS_QUAD)

func _on_start_button_pressed() -> void:
	glitch_player.play_glitch_click()
	# Show difficulty selection instead of immediately loading the game
	difficulty_prompt.visible = true

func _on_multiplayer_button_pressed() -> void:
	glitch_player.play_glitch_click()
	await get_tree().create_timer(0.15).timeout
	get_tree().change_scene_to_file("res://lobby.tscn")

func _on_normal_pressed() -> void:
	glitch_player.play_glitch_click()
	GameManager.easy_mode = false
	GameManager.tutorial_mode = false
	await get_tree().create_timer(0.15).timeout
	SceneLoader.change_scene("res://game_board_3d.tscn")

func _on_easy_pressed() -> void:
	glitch_player.play_glitch_click()
	GameManager.easy_mode = true
	GameManager.tutorial_mode = false
	await get_tree().create_timer(0.15).timeout
	SceneLoader.change_scene("res://game_board_3d.tscn")

func _on_tutorial_pressed() -> void:
	glitch_player.play_glitch_click()
	GameManager.easy_mode = true   # Tutorial always plays with cards visible
	GameManager.tutorial_mode = true
	await get_tree().create_timer(0.15).timeout
	SceneLoader.change_scene("res://game_board_3d.tscn")

func _on_difficulty_cancel_pressed() -> void:
	glitch_player.play_glitch_click()
	difficulty_prompt.visible = false

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

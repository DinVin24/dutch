extends Control

signal back_pressed

const COLOR_MAGENTA := Color(1.0, 0.1, 0.6)
const COLOR_CYAN := Color(0.0, 1.0, 1.0)
const COLOR_PANEL_BG := Color(0.04, 0.02, 0.08, 0.96)
const COLOR_INPUT_BG := Color(0.06, 0.03, 0.1, 0.9)
const COLOR_MUTED := Color(0.6, 0.6, 0.7)

@onready var tabs: TabContainer = $Center/OuterMargin/PanelShell/InnerMargin/Panel/Tabs
@onready var resolution_option: OptionButton = $Center/OuterMargin/PanelShell/InnerMargin/Panel/Tabs/DISPLAY/DisplayMargin/DisplayVBox/DisplayGrid/ResolutionOption
@onready var window_mode_option: OptionButton = $Center/OuterMargin/PanelShell/InnerMargin/Panel/Tabs/DISPLAY/DisplayMargin/DisplayVBox/DisplayGrid/WindowModeOption
@onready var music_slider: HSlider = $Center/OuterMargin/PanelShell/InnerMargin/Panel/Tabs/AUDIO/AudioMargin/AudioVBox/AudioGrid/MusicSlider
@onready var sfx_slider: HSlider = $Center/OuterMargin/PanelShell/InnerMargin/Panel/Tabs/AUDIO/AudioMargin/AudioVBox/AudioGrid/SFXSlider
@onready var music_value_label: Label = $Center/OuterMargin/PanelShell/InnerMargin/Panel/Tabs/AUDIO/AudioMargin/AudioVBox/AudioGrid/MusicValueLabel
@onready var sfx_value_label: Label = $Center/OuterMargin/PanelShell/InnerMargin/Panel/Tabs/AUDIO/AudioMargin/AudioVBox/AudioGrid/SFXValueLabel
@onready var dev_console_check: CheckBox = $Center/OuterMargin/PanelShell/InnerMargin/Panel/Tabs/CONTROLS/ControlsMargin/ControlsVBox/DevConsoleRow/DevConsoleCheck
@onready var game_assistant_check: CheckBox = $Center/OuterMargin/PanelShell/InnerMargin/Panel/Tabs/CONTROLS/ControlsMargin/ControlsVBox/GameAssistantRow/GameAssistantCheck
@onready var deep_reasoning_check: CheckBox = $Center/OuterMargin/PanelShell/InnerMargin/Panel/Tabs/CONTROLS/ControlsMargin/ControlsVBox/DeepReasoningRow/DeepReasoningCheck
@onready var back_button: Button = $Center/OuterMargin/PanelShell/InnerMargin/Panel/FooterRow/BackButton
@onready var glitch_player: AudioStreamPlayer = $GlitchSound

var resolutions = [
	Vector2i(1152, 648),
	Vector2i(1280, 720),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440)
]

func _ready() -> void:
	# Resolution
	resolution_option.clear()
	for res in resolutions:
		resolution_option.add_item(str(res.x) + "x" + str(res.y))
	var current_size = DisplayServer.window_get_size()
	var res_index = 0
	for i in range(resolutions.size()):
		if resolutions[i] == current_size:
			res_index = i
	resolution_option.select(res_index)

	# Window Mode
	window_mode_option.clear()
	window_mode_option.add_item("Windowed", DisplayServer.WINDOW_MODE_WINDOWED)
	window_mode_option.add_item("Fullscreen", DisplayServer.WINDOW_MODE_FULLSCREEN)
	var current_mode = DisplayServer.window_get_mode()
	var mode_idx = 0
	for i in range(window_mode_option.item_count):
		if window_mode_option.get_item_id(i) == current_mode:
			mode_idx = i
	window_mode_option.select(mode_idx)

	# Audio
	var music_bus = AudioServer.get_bus_index("Music")
	var sfx_bus = AudioServer.get_bus_index("SFX")
	if music_bus >= 0:
		music_slider.value = db_to_linear(AudioServer.get_bus_volume_db(music_bus))
	if sfx_bus >= 0:
		sfx_slider.value = db_to_linear(AudioServer.get_bus_volume_db(sfx_bus))
	_update_volume_label(music_value_label, music_slider.value)
	_update_volume_label(sfx_value_label, sfx_slider.value)

	dev_console_check.button_pressed = GameManager.dev_console_enabled
	game_assistant_check.button_pressed = GameManager.show_game_assistant
	deep_reasoning_check.button_pressed = GameManager.assistant_deep_reasoning
	_populate_keybind_buttons()
	_apply_ui_theme()
	_connect_hover_sounds()

func _apply_ui_theme() -> void:
	var panel_style := _make_box(COLOR_PANEL_BG, COLOR_MAGENTA, 2, 0)
	panel_style.shadow_color = Color(COLOR_MAGENTA.r, COLOR_MAGENTA.g, COLOR_MAGENTA.b, 0.25)
	panel_style.shadow_size = 8
	$Center/OuterMargin/PanelShell.add_theme_stylebox_override("panel", panel_style)

	_style_option_button(resolution_option)
	_style_option_button(window_mode_option)
	_style_slider(music_slider)
	_style_slider(sfx_slider)
	_style_checkbox(dev_console_check)
	_style_checkbox(game_assistant_check)
	_style_checkbox(deep_reasoning_check)
	_style_tabs(tabs)
	_style_back_button(back_button)

	for action in KEYBIND_ACTIONS:
		_style_keybind_button(get_node(KEYBIND_ACTIONS[action]))

func _make_box(bg: Color, border: Color, border_w: int = 1, radius: int = 4) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_w)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style

func _style_option_button(option: OptionButton) -> void:
	option.custom_minimum_size = Vector2(180, 40)
	option.clip_text = false
	option.add_theme_font_size_override("font_size", 17)
	option.add_theme_color_override("font_color", COLOR_CYAN)
	option.add_theme_color_override("font_hover_color", Color.WHITE)
	option.add_theme_color_override("font_pressed_color", COLOR_MAGENTA)

	var normal := _make_box(COLOR_INPUT_BG, Color(COLOR_CYAN.r, COLOR_CYAN.g, COLOR_CYAN.b, 0.45), 1, 4)
	normal.content_margin_right = 28
	var hover := normal.duplicate()
	hover.bg_color = Color(0.1, 0.05, 0.14, 0.95)
	hover.border_color = COLOR_CYAN
	var pressed := hover.duplicate()
	pressed.border_color = COLOR_MAGENTA
	var disabled := normal.duplicate()
	disabled.bg_color = Color(COLOR_INPUT_BG.r, COLOR_INPUT_BG.g, COLOR_INPUT_BG.b, 0.5)

	option.add_theme_stylebox_override("normal", normal)
	option.add_theme_stylebox_override("hover", hover)
	option.add_theme_stylebox_override("pressed", pressed)
	option.add_theme_stylebox_override("focus", hover)
	option.add_theme_stylebox_override("disabled", disabled)

	var popup: PopupMenu = option.get_popup()
	popup.add_theme_font_size_override("font_size", 16)
	popup.add_theme_color_override("font_color", COLOR_CYAN)
	popup.add_theme_color_override("font_hover_color", Color.WHITE)
	popup.add_theme_color_override("font_accelerator_color", COLOR_MUTED)
	var popup_panel := _make_box(Color(0.05, 0.02, 0.08, 0.98), COLOR_MAGENTA, 1, 4)
	popup.add_theme_stylebox_override("panel", popup_panel)
	var popup_hover := _make_box(Color(0.1, 0.05, 0.14, 0.95), COLOR_CYAN, 1, 2)
	popup.add_theme_stylebox_override("hover", popup_hover)

func _style_slider(slider: HSlider) -> void:
	slider.custom_minimum_size.y = 28

	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.12, 0.06, 0.16, 0.9)
	track.set_corner_radius_all(3)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	slider.add_theme_stylebox_override("slider", track)

	var grabber_area := StyleBoxFlat.new()
	grabber_area.bg_color = Color(0.08, 0.04, 0.12, 0.4)
	grabber_area.set_corner_radius_all(3)
	slider.add_theme_stylebox_override("grabber_area", grabber_area)
	slider.add_theme_stylebox_override("grabber_area_highlight", grabber_area)

	var grabber := StyleBoxFlat.new()
	grabber.bg_color = COLOR_CYAN
	grabber.border_color = COLOR_MAGENTA
	grabber.set_border_width_all(1)
	grabber.set_corner_radius_all(8)
	grabber.set_content_margin_all(5)
	slider.add_theme_stylebox_override("grabber", grabber)

func _style_checkbox(check: CheckBox) -> void:
	check.add_theme_font_size_override("font_size", 17)
	check.add_theme_color_override("font_color", COLOR_CYAN)
	check.add_theme_color_override("font_hover_color", Color.WHITE)

	var unchecked := _make_box(COLOR_INPUT_BG, Color(COLOR_CYAN.r, COLOR_CYAN.g, COLOR_CYAN.b, 0.35), 1, 3)
	var checked := unchecked.duplicate()
	checked.border_color = COLOR_MAGENTA
	checked.bg_color = Color(COLOR_MAGENTA.r * 0.2, COLOR_MAGENTA.g * 0.2, COLOR_MAGENTA.b * 0.2, 0.85)

	check.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	check.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	check.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	check.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	check.add_theme_stylebox_override("normal_mirrored", StyleBoxEmpty.new())
	check.add_theme_stylebox_override("hover_mirrored", StyleBoxEmpty.new())
	check.add_theme_stylebox_override("pressed_mirrored", StyleBoxEmpty.new())
	check.add_theme_stylebox_override("focus_mirrored", StyleBoxEmpty.new())
	check.add_theme_stylebox_override("unchecked", unchecked)
	check.add_theme_stylebox_override("unchecked_disabled", unchecked)
	check.add_theme_stylebox_override("checked", checked)
	check.add_theme_stylebox_override("checked_disabled", checked)

func _style_keybind_button(btn: Button) -> void:
	btn.custom_minimum_size = Vector2(140, 36)
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", COLOR_CYAN)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", COLOR_MAGENTA)

	var normal := _make_box(COLOR_INPUT_BG, Color(COLOR_CYAN.r, COLOR_CYAN.g, COLOR_CYAN.b, 0.4), 1, 4)
	var hover := normal.duplicate()
	hover.bg_color = Color(0.1, 0.05, 0.14, 0.95)
	hover.border_color = COLOR_CYAN
	var pressed := hover.duplicate()
	pressed.border_color = COLOR_MAGENTA

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", hover)
	btn.flat = false

func _style_back_button(btn: Button) -> void:
	btn.custom_minimum_size.y = 42
	btn.add_theme_font_size_override("font_size", 20)
	btn.add_theme_color_override("font_color", Color(0.55, 0.55, 0.6))
	btn.add_theme_color_override("font_hover_color", COLOR_MAGENTA)
	btn.add_theme_color_override("font_pressed_color", COLOR_CYAN)

	var normal := StyleBoxEmpty.new()
	var hover := _make_box(Color(COLOR_MAGENTA.r * 0.12, COLOR_MAGENTA.g * 0.12, COLOR_MAGENTA.b * 0.12, 0.5), COLOR_MAGENTA, 1, 0)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_stylebox_override("focus", hover)
	btn.flat = false

func _style_tabs(tab_container: TabContainer) -> void:
	var content_panel := _make_box(Color(0.03, 0.01, 0.06, 0.55), Color(COLOR_MAGENTA.r, COLOR_MAGENTA.g, COLOR_MAGENTA.b, 0.25), 1, 0)
	content_panel.content_margin_left = 12
	content_panel.content_margin_right = 12
	content_panel.content_margin_top = 14
	content_panel.content_margin_bottom = 12
	tab_container.add_theme_stylebox_override("panel", content_panel)

	var tab_bar := tab_container.get_tab_bar()
	tab_bar.add_theme_font_size_override("font_size", 16)

	var tab_unselected := _make_box(Color(0.05, 0.02, 0.08, 0.75), Color(COLOR_MAGENTA.r, COLOR_MAGENTA.g, COLOR_MAGENTA.b, 0.2), 1, 0)
	var tab_hovered := tab_unselected.duplicate()
	tab_hovered.border_color = Color(COLOR_MAGENTA.r, COLOR_MAGENTA.g, COLOR_MAGENTA.b, 0.65)
	tab_hovered.bg_color = Color(0.08, 0.03, 0.12, 0.85)
	var tab_selected := tab_hovered.duplicate()
	tab_selected.border_color = COLOR_CYAN
	tab_selected.bg_color = Color(COLOR_CYAN.r * 0.12, COLOR_CYAN.g * 0.12, COLOR_CYAN.b * 0.12, 0.9)

	tab_bar.add_theme_stylebox_override("tab_unselected", tab_unselected)
	tab_bar.add_theme_stylebox_override("tab_hovered", tab_hovered)
	tab_bar.add_theme_stylebox_override("tab_selected", tab_selected)
	tab_bar.add_theme_stylebox_override("tab_disabled", tab_unselected)
	_register_tab_hovers(tab_bar)

func _connect_hover_sounds() -> void:
	_register_glitch_hover(back_button)
	_register_glitch_hover(resolution_option)
	_register_glitch_hover(window_mode_option)
	_register_glitch_hover(music_slider)
	_register_glitch_hover(sfx_slider)
	_register_glitch_hover(dev_console_check)
	_register_glitch_hover(game_assistant_check)
	_register_glitch_hover(deep_reasoning_check)
	for action in KEYBIND_ACTIONS:
		_register_glitch_hover(get_node(KEYBIND_ACTIONS[action]))

func _register_glitch_hover(control: Control) -> void:
	if control.mouse_entered.is_connected(_on_glitch_hover):
		return
	control.mouse_entered.connect(_on_glitch_hover)

func _register_tab_hovers(tab_bar: TabBar) -> void:
	for child in tab_bar.get_children():
		if child is Control:
			_register_glitch_hover(child)

func _on_glitch_hover() -> void:
	glitch_player.play_glitch_hover()

func _update_volume_label(label: Label, value: float) -> void:
	label.text = "%d%%" % int(round(value * 100.0))

func _on_resolution_selected(index: int) -> void:
	DisplayServer.window_set_size(resolutions[index])
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED:
		var screen_size = DisplayServer.screen_get_size()
		var window_size = DisplayServer.window_get_size()
		DisplayServer.window_set_position((screen_size - window_size) / 2.0)

func _on_window_mode_selected(index: int) -> void:
	DisplayServer.window_set_mode(window_mode_option.get_item_id(index))

func _on_music_value_changed(value: float) -> void:
	var bus_idx = AudioServer.get_bus_index("Music")
	if bus_idx >= 0:
		AudioServer.set_bus_volume_db(bus_idx, linear_to_db(value))
	_update_volume_label(music_value_label, value)

func _on_sfx_value_changed(value: float) -> void:
	var bus_idx = AudioServer.get_bus_index("SFX")
	if bus_idx >= 0:
		AudioServer.set_bus_volume_db(bus_idx, linear_to_db(value))
	_update_volume_label(sfx_value_label, value)

func _on_back_button_pressed() -> void:
	SettingsManager.save_settings()
	back_pressed.emit()
	queue_free()

func _on_dev_console_toggled(toggled_on: bool) -> void:
	GameManager.dev_console_enabled = toggled_on

func _on_game_assistant_toggled(toggled_on: bool) -> void:
	GameManager.show_game_assistant = toggled_on

func _on_deep_reasoning_toggled(toggled_on: bool) -> void:
	GameManager.assistant_deep_reasoning = toggled_on

# ── KEYBINDS ──────────────────────────────────────────────────────────────────

const KEYBIND_ACTIONS: Dictionary = {
	"game_end_turn":     "Center/OuterMargin/PanelShell/InnerMargin/Panel/Tabs/CONTROLS/ControlsMargin/ControlsVBox/KeybindsGrid/EndTurnBind",
	"game_jump_in":      "Center/OuterMargin/PanelShell/InnerMargin/Panel/Tabs/CONTROLS/ControlsMargin/ControlsVBox/KeybindsGrid/JumpInBind",
	"game_call_dutch":   "Center/OuterMargin/PanelShell/InnerMargin/Panel/Tabs/CONTROLS/ControlsMargin/ControlsVBox/KeybindsGrid/CallDutchBind",
	"game_draw_card":    "Center/OuterMargin/PanelShell/InnerMargin/Panel/Tabs/CONTROLS/ControlsMargin/ControlsVBox/KeybindsGrid/DrawCardBind",
	"game_select_left":  "Center/OuterMargin/PanelShell/InnerMargin/Panel/Tabs/CONTROLS/ControlsMargin/ControlsVBox/KeybindsGrid/SelectLeftBind",
	"game_select_right": "Center/OuterMargin/PanelShell/InnerMargin/Panel/Tabs/CONTROLS/ControlsMargin/ControlsVBox/KeybindsGrid/SelectRightBind",
	"game_confirm_card": "Center/OuterMargin/PanelShell/InnerMargin/Panel/Tabs/CONTROLS/ControlsMargin/ControlsVBox/KeybindsGrid/ConfirmCardBind",
	"game_discard_drawn":"Center/OuterMargin/PanelShell/InnerMargin/Panel/Tabs/CONTROLS/ControlsMargin/ControlsVBox/KeybindsGrid/DiscardDrawnBind",
	"game_forfeit_dutch":"Center/OuterMargin/PanelShell/InnerMargin/Panel/Tabs/CONTROLS/ControlsMargin/ControlsVBox/KeybindsGrid/ForfeitDutchBind",
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
	if _listening_button != null:
		_listening_button.text = _get_key_label(_listening_action)
	_listening_action = action
	_listening_button = get_node(node_path)
	_listening_button.text = "[ press a key... ]"
	_style_keybind_listening(_listening_button)

func _style_keybind_listening(btn: Button) -> void:
	var listening := _make_box(Color(COLOR_MAGENTA.r * 0.18, COLOR_MAGENTA.g * 0.18, COLOR_MAGENTA.b * 0.18, 0.9), COLOR_MAGENTA, 2, 4)
	btn.add_theme_stylebox_override("normal", listening)
	btn.add_theme_color_override("font_color", COLOR_MAGENTA)

func _input(event: InputEvent) -> void:
	# Escape: close settings (cancels rebind if active, otherwise goes back)
	if event.is_action_pressed("ui_cancel"):
		if DevConsole and DevConsole.window.is_visible():
			return
		if _listening_action != "":
			# Cancel rebind only
			_listening_button.text = _get_key_label(_listening_action)
			_style_keybind_button(_listening_button)
			_listening_action = ""
			_listening_button = null
			get_viewport().set_input_as_handled()
			return
		_on_back_button_pressed()
		get_viewport().set_input_as_handled()
		return

	# Rebind capture
	if _listening_action == "": return
	if not (event is InputEventKey and event.pressed and not event.echo): return

	var new_event = InputEventKey.new()
	new_event.physical_keycode = event.physical_keycode
	InputMap.action_erase_events(_listening_action)
	InputMap.action_add_event(_listening_action, new_event)

	_listening_button.text = _get_key_label(_listening_action)
	_style_keybind_button(_listening_button)
	_listening_action = ""
	_listening_button = null
	SettingsManager.save_settings()
	get_viewport().set_input_as_handled()

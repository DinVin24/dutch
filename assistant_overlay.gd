extends Control

## Permanent in-game assistant UI (Chippy Q&A).
## A "?" toggle button sits bottom-right, just above the EMOTE button. Clicking
## it opens a collapsible Q&A panel backed by the local LM Studio model, with
## a deterministic offline fallback. Requests never leave this computer.

signal opened
signal panel_closed

const ACCENT := Color(0.95, 0.78, 0.25)
const CYAN := Color(0.0, 1.0, 1.0)

const FACES := {
	"happy": "(ꗷ‿ꗷ)",
	"smug": "(¬‿¬)",
	"scared": "(⊙_⊙)",
	"cool": "( •_•)>⌐■-■",
	"party": "(ﾉ◕ヮ◕)ﾉ*:･ﾟ✧",
	"dead": "(x_x)",
}

const HISTORY_MAX := 3
const GREETING := "Hi, I'm Chippy! Ask me anything about the rules, or tap a question below."

var _open := false
var _history: Array = []

var _panel: PanelContainer
var _chippy_label: Label
var _answer_label: RichTextLabel
var _scroll: ScrollContainer
var _input: LineEdit
var _send_btn: Button
var _close_btn: Button
var _chips_grid: GridContainer
var _bound_help_btn: Button = null
var _thinking_label: Label
var _steps_label: Label
var _busy := false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 25
	_build_panel()
	_render_history()

func bind_help_button(btn: Button) -> void:
	_bound_help_btn = btn

func reparent_panel_to(hud: Control) -> void:
	if is_instance_valid(_panel) and is_instance_valid(hud):
		_panel.reparent(hud)
		_panel.z_index = 44

# ── Public API ───────────────────────────────────────────────────────────────

func is_open() -> bool:
	return _open

func toggle_panel() -> void:
	if _open:
		close_panel()
	else:
		open_panel()

func open_panel() -> void:
	_open = true
	if is_instance_valid(_panel):
		_panel.visible = true
		_panel.show()
	if is_instance_valid(_input):
		_input.grab_focus()
	opened.emit()

func close_panel() -> void:
	_open = false
	if is_instance_valid(_panel):
		_panel.visible = false
		_panel.hide()
	panel_closed.emit()

func bring_to_front(hud: Control, help_btn: Button) -> void:
	if not is_instance_valid(hud):
		return
	if is_instance_valid(_panel) and _panel.get_parent() == hud:
		hud.move_child(_panel, -1)
		_panel.z_index = 47
	if is_instance_valid(help_btn):
		hud.move_child(help_btn, -1)
		help_btn.z_index = 48

## Enable/disable the assistant panel (help button visibility is managed by the board).
func set_available(available: bool) -> void:
	if not available:
		close_panel()

## True if the point hits the open Q&A panel (help button is checked by the board).
func consumes_point(screen_pos: Vector2) -> bool:
	if _open and is_instance_valid(_panel) \
			and _panel.get_global_rect().has_point(screen_pos):
		return true
	return false

## Position the Q&A panel above the help button stack.
func apply_layout(scale: float, margin: float, emote_btn_h: float, help_btn_h: float, tutorial_mode: bool) -> void:
	if not is_instance_valid(_panel):
		return
	var vp := get_viewport().get_visible_rect().size
	var panel_w := 360.0 * scale
	var panel_gap := 28.0 * scale
	var help_stack_bottom := emote_btn_h + help_btn_h + margin * 3.0 + panel_gap
	if tutorial_mode:
		help_stack_bottom += 280.0 * scale
	var panel_h := minf(380.0 * scale, vp.y - help_stack_bottom - margin * 2.0)
	_panel.offset_right = -margin
	_panel.offset_left = -panel_w - margin
	_panel.offset_bottom = -help_stack_bottom
	_panel.offset_top = _panel.offset_bottom - panel_h
	_panel.custom_minimum_size = Vector2(panel_w, maxf(panel_h, 220.0 * scale))

# ── UI construction ──────────────────────────────────────────────────────────

func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.name = "AssistantPanel"
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_panel.offset_left = -360.0
	_panel.offset_top = -498.0
	_panel.offset_right = -20.0
	_panel.offset_bottom = -130.0
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.visible = false

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.02, 0.0, 0.06, 0.92)
	panel_style.border_color = Color(CYAN.r, CYAN.g, CYAN.b, 0.6)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(12)
	panel_style.shadow_color = Color(0, 0, 0, 0.4)
	panel_style.shadow_size = 8
	panel_style.set_content_margin_all(12.0)
	_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_panel.add_child(vbox)

	# Header: Chippy face + title + close
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	vbox.add_child(header)

	_chippy_label = Label.new()
	_chippy_label.text = FACES["happy"]
	_chippy_label.add_theme_font_size_override("font_size", 24)
	_chippy_label.add_theme_color_override("font_color", ACCENT)
	_chippy_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_chippy_label)

	var title := Label.new()
	title.text = "CHIPPY HELP"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", CYAN)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(title)

	_close_btn = Button.new()
	_close_btn.text = "X"
	_close_btn.custom_minimum_size = Vector2(28, 28)
	_close_btn.add_theme_font_size_override("font_size", 14)
	_close_btn.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))
	_close_btn.add_theme_color_override("font_hover_color", Color.WHITE)
	var close_normal := StyleBoxFlat.new()
	close_normal.bg_color = Color(0.18, 0.05, 0.06, 0.65)
	close_normal.set_border_width_all(1)
	close_normal.border_color = Color(1.0, 0.3, 0.4, 0.6)
	close_normal.set_corner_radius_all(6)
	var close_hover := close_normal.duplicate()
	close_hover.bg_color = Color(0.42, 0.08, 0.1, 0.85)
	_close_btn.add_theme_stylebox_override("normal", close_normal)
	_close_btn.add_theme_stylebox_override("hover", close_hover)
	_close_btn.add_theme_stylebox_override("pressed", close_hover)
	_close_btn.pressed.connect(close_panel)
	header.add_child(_close_btn)

	var rule := ColorRect.new()
	rule.color = Color(CYAN.r, CYAN.g, CYAN.b, 0.35)
	rule.custom_minimum_size = Vector2(0, 1)
	vbox.add_child(rule)

	# Thinking indicator (shown briefly while Chippy "reasons")
	_thinking_label = Label.new()
	_thinking_label.text = "Chippy is asking the local model..."
	_thinking_label.add_theme_font_size_override("font_size", 12)
	_thinking_label.add_theme_color_override("font_color", ACCENT)
	_thinking_label.visible = false
	vbox.add_child(_thinking_label)

	# Reasoning steps (last few), small + dim
	_steps_label = Label.new()
	_steps_label.add_theme_font_size_override("font_size", 10)
	_steps_label.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7))
	_steps_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_steps_label.visible = false
	vbox.add_child(_steps_label)

	# Answer / history scroll
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(0, 150)
	vbox.add_child(_scroll)

	_answer_label = RichTextLabel.new()
	_answer_label.bbcode_enabled = true
	_answer_label.fit_content = true
	_answer_label.scroll_active = false
	_answer_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_answer_label.add_theme_font_size_override("normal_font_size", 14)
	_answer_label.add_theme_color_override("default_color", Color(0.92, 0.92, 0.92))
	_scroll.add_child(_answer_label)

	# Quick chips
	var chips_label := Label.new()
	chips_label.text = "Quick questions"
	chips_label.add_theme_font_size_override("font_size", 11)
	chips_label.add_theme_color_override("font_color", Color(0.6, 0.62, 0.7))
	vbox.add_child(chips_label)

	_chips_grid = GridContainer.new()
	_chips_grid.columns = 2
	_chips_grid.add_theme_constant_override("h_separation", 6)
	_chips_grid.add_theme_constant_override("v_separation", 6)
	vbox.add_child(_chips_grid)
	_build_chips()

	# Input row
	var input_row := HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 6)
	vbox.add_child(input_row)

	_input = LineEdit.new()
	_input.placeholder_text = "Ask Chippy..."
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.add_theme_font_size_override("font_size", 14)
	_input.text_submitted.connect(_on_input_submitted)
	input_row.add_child(_input)

	_send_btn = Button.new()
	_send_btn.text = "Send"
	_send_btn.add_theme_font_size_override("font_size", 14)
	_send_btn.add_theme_color_override("font_color", ACCENT)
	_send_btn.add_theme_color_override("font_hover_color", Color.WHITE)
	var send_normal := StyleBoxFlat.new()
	send_normal.bg_color = Color(0.1, 0.08, 0.03, 0.85)
	send_normal.set_border_width_all(1)
	send_normal.border_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.6)
	send_normal.set_corner_radius_all(8)
	send_normal.set_content_margin_all(8.0)
	var send_hover := send_normal.duplicate()
	send_hover.bg_color = Color(0.2, 0.16, 0.04, 0.95)
	_send_btn.add_theme_stylebox_override("normal", send_normal)
	_send_btn.add_theme_stylebox_override("hover", send_hover)
	_send_btn.add_theme_stylebox_override("pressed", send_hover)
	_send_btn.pressed.connect(_on_send_pressed)
	input_row.add_child(_send_btn)

func _build_chips() -> void:
	for child in _chips_grid.get_children():
		child.queue_free()
	for chip in GameAssistant.quick_questions():
		var btn := Button.new()
		btn.text = str(chip.get("label", "?"))
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.clip_text = true
		btn.add_theme_font_size_override("font_size", 12)
		btn.add_theme_color_override("font_color", CYAN.lightened(0.1))
		btn.add_theme_color_override("font_hover_color", Color.WHITE)
		var chip_normal := StyleBoxFlat.new()
		chip_normal.bg_color = Color(0.04, 0.1, 0.12, 0.7)
		chip_normal.set_border_width_all(1)
		chip_normal.border_color = Color(CYAN.r, CYAN.g, CYAN.b, 0.45)
		chip_normal.set_corner_radius_all(8)
		chip_normal.set_content_margin_all(6.0)
		var chip_hover := chip_normal.duplicate()
		chip_hover.bg_color = Color(0.04, 0.16, 0.18, 0.85)
		chip_hover.border_color = CYAN
		btn.add_theme_stylebox_override("normal", chip_normal)
		btn.add_theme_stylebox_override("hover", chip_hover)
		btn.add_theme_stylebox_override("pressed", chip_hover)
		btn.pressed.connect(_on_chip_pressed.bind(str(chip.get("query", ""))))
		_chips_grid.add_child(btn)

# ── Interaction ──────────────────────────────────────────────────────────────

func _on_send_pressed() -> void:
	if is_instance_valid(_input):
		_submit(_input.text)

func _on_input_submitted(text: String) -> void:
	_submit(text)

func _on_chip_pressed(query: String) -> void:
	_submit(query)

func _submit(question: String) -> void:
	var q := question.strip_edges()
	if q == "" or _busy:
		return
	_busy = true

	# Show the "thinking" state up front so Chippy feels like it's reasoning.
	if is_instance_valid(_thinking_label):
		_thinking_label.visible = true
	if is_instance_valid(_steps_label):
		_steps_label.visible = false
	if is_instance_valid(_chippy_label):
		_chippy_label.text = _resolve_face("cool")
	if is_instance_valid(_input):
		_input.clear()
	if is_instance_valid(_send_btn):
		_send_btn.disabled = true

	var previous_answer := ""
	if not _history.is_empty():
		previous_answer = str((_history[-1].get("result", {}) as Dictionary).get("answer", ""))
	var result: Dictionary = await GameAssistant.ask_async(q, 280, previous_answer)

	if is_instance_valid(_thinking_label):
		_thinking_label.visible = false
	if is_instance_valid(_send_btn):
		_send_btn.disabled = false

	_history.append({"q": q, "result": result})
	while _history.size() > HISTORY_MAX:
		_history.pop_front()
	if is_instance_valid(_chippy_label):
		_chippy_label.text = _resolve_face(str(result.get("face", "happy")))
	_render_steps(result.get("thinking_steps", []))
	_render_history()
	_busy = false
	await get_tree().process_frame
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)

func _render_steps(steps: Array) -> void:
	if not is_instance_valid(_steps_label):
		return
	if steps.is_empty():
		_steps_label.visible = false
		return
	var shown: Array = steps.slice(maxi(0, steps.size() - 3))
	var parts: Array = []
	for s in shown:
		parts.append("> " + str(s))
	_steps_label.text = "\n".join(parts)
	_steps_label.visible = true

func _render_history() -> void:
	if not is_instance_valid(_answer_label):
		return
	if _history.is_empty():
		_answer_label.text = "[color=#cfe9ff]%s[/color]" % GREETING
		return
	var lines: Array = []
	for item in _history:
		var q: String = item.get("q", "")
		var result: Dictionary = item.get("result", {})
		lines.append("[color=#ffd34d]You:[/color] %s" % q)
		lines.append("[color=#cfe9ff]Chippy:[/color] %s" % str(result.get("answer", "")))
	_answer_label.text = "\n\n".join(lines)

func _resolve_face(keyword: String) -> String:
	return FACES.get(keyword, FACES["happy"])

extends Control

# ─────────────────────────────────────────────────────────────────────────────
# Chippy the Card Goblin — Tutorial Overlay
# Connects to GameManager FSM signals and delivers contextual tips during play.
# ─────────────────────────────────────────────────────────────────────────────

signal tutorial_finished

# ── Chippy ASCII face variants ────────────────────────────────────────────────
const FACE_HAPPY  := "(ꗷ‿ꗷ)"
const FACE_SMUG   := "(¬‿¬)"
const FACE_SCARED := "(⊙_⊙)"
const FACE_COOL   := "( •_•)>⌐■-■"
const FACE_PARTY  := "(ﾉ◕ヮ◕)ﾉ*:･ﾟ✧"
const FACE_DEAD   := "(x_x)"

# ── Tip data: maps GameManager FSM state names to arrays of tip steps ─────────
# Each entry: { "face": FACE_*, "text": "..." }
# Multiple steps per state allow the [NEXT] button to step through detail.
const TIPS: Dictionary = {
	"DEAL_CARDS": [
		{ "face": FACE_HAPPY,  "text": "Welcome! I'm Chippy, your totally reliable guide.\n4 cards each, face down. No peeking! Yet." },
		{ "face": FACE_SMUG,   "text": "Cards are worth their rank in points. Ace=1 ... King=13.\nKing of Diamonds = 0 though. He's special." },
	],
	"INITIAL_PEEK": [
		{ "face": FACE_COOL,   "text": "Click 2 of YOUR cards to secretly peek at them.\nRemember what you saw — they flip back down immediately!" },
		{ "face": FACE_SMUG,   "text": "Pro tip: memorise which of your cards are low value.\nYou want the LOWEST score to win." },
	],
	"TURN_START_DRAW": [
		{ "face": FACE_HAPPY,  "text": "Your turn! Click the DECK (top of table) to draw a card.\nYou MUST draw before doing anything else." },
	],
	"TURN_RESOLVE_DRAWN": [
		{ "face": FACE_COOL,   "text": "You drew a card. Now choose:\n• Drag it to the DISCARD PILE to throw it away, OR\n• Click one of YOUR face-down cards to SWAP." },
		{ "face": FACE_SMUG,   "text": "Swapping sends your old face-down card to the discard.\nIf you drew something low — definitely swap it in!" },
		{ "face": FACE_HAPPY,  "text": "Special ranks: Queen = peek any card, Jack = swap any two.\nDiscard them to trigger these abilities!" },
	],
	"TURN_PEEK_ABILITY": [
		{ "face": FACE_COOL,   "text": "You played a Queen!\nClick any face-down card on the table to secretly peek at it." },
		{ "face": FACE_SMUG,   "text": "Peek at an opponent's card to spot their low-value cards.\nThen you can target them with a Jack swap later. Sneaky!" },
	],
	"TURN_SWAP_ABILITY": [
		{ "face": FACE_SMUG,   "text": "You played a Jack!\nClick two face-down cards to blindly swap their positions." },
		{ "face": FACE_COOL,   "text": "Nobody sees what got swapped — not even you.\nSwap your worst card with someone else's best. Probably." },
	],
	"TURN_END_CHOICE": [
		{ "face": FACE_HAPPY,  "text": "Done with your turn? Click END TURN to pass to the next player." },
		{ "face": FACE_SCARED, "text": "Or... if the discard pile's top card matches YOUR card's rank,\nyou can JUMP IN at any time! Even on someone else's turn!" },
		{ "face": FACE_SMUG,   "text": "Think you have the lowest score? Click CALL DUTCH!\nEveryone else gets one last turn, then you confirm or bail." },
	],
	"TURN_JUMP_IN_SELECTION": [
		{ "face": FACE_SCARED, "text": "JUMP IN mode! Select one of your cards.\nIt must match the RANK of the top discard card exactly." },
		{ "face": FACE_DEAD,   "text": "Wrong rank = penalty card + you drink a beer.\nDrink all 3 beers and you're ELIMINATED. No pressure!" },
	],
	"TURN_CONFIRM_DUTCH": [
		{ "face": FACE_SCARED, "text": "You called Dutch and everyone had their last turn.\nCONFIRM to end the game, or FORFEIT to keep playing\n(but you can't call Dutch again!)." },
	],
	"GAME_OVER": [
		{ "face": FACE_PARTY,  "text": "Game over! All cards flip face-up now.\nLowest total score wins. Count carefully!" },
		{ "face": FACE_HAPPY,  "text": "That's Dutch! You're a pro now.\nClick SKIP TUTORIAL to remove me — I believe in you!" },
	],
	"STATE_PLAYING_ABILITY": [
		{ "face": FACE_COOL,   "text": "An ability is being played!\nAbility cards come from the Chicken — click its legs to buy one." },
	],
}

# ── Special one-off event tips (shown once, keyed by string tag) ──────────────
const EVENT_TIPS: Dictionary = {
	"first_beer_lost": {
		"face": FACE_DEAD,
		"text": "Oof! You drank a beer. You start with 3 lives.\nDrink all 3 and you're out. Don't Jump In recklessly!"
	},
	"ability_bought": {
		"face": FACE_PARTY,
		"text": "You bought a Chicken egg! Click the token on your turn to use it.\nEach ability has a unique effect — peek first, then decide!"
	},
	"dutch_called": {
		"face": FACE_SCARED,
		"text": "Someone called DUTCH! This triggers the final round.\nEveryone (including you) gets one last turn. Make it count!"
	},
}

# ── State ─────────────────────────────────────────────────────────────────────
var _current_tips: Array = []
var _tip_index: int = 0
var _shown_events: Dictionary = {}  # tag -> true once shown
var _is_animating: bool = false
var _last_state: String = ""

# ── Node references (set in _ready after scene is built) ─────────────────────
var _chippy_label: Label
var _speech_label: RichTextLabel
var _next_btn: Button
var _skip_btn: Button
var _panel: PanelContainer

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	_build_ui()
	_connect_signals()
	# Show the welcome tip immediately (DEAL_CARDS usually fires before overlay is ready)
	_load_tips_for_state("DEAL_CARDS")
	_display_current_tip()

# ─────────────────────────────────────────────────────────────────────────────
func _build_ui() -> void:
	# Root is a full-rect Control with IGNORE mouse so it doesn't block game clicks
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# ── Outer panel (bottom-right, fixed size) ────────────────────────────────
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_panel.offset_left   = -420.0
	_panel.offset_top    = -270.0
	_panel.offset_right  = -14.0
	_panel.offset_bottom = -14.0

	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color          = Color(0.02, 0.0, 0.06, 0.90)
	panel_style.border_color      = Color(0.0, 1.0, 1.0, 0.85)
	panel_style.set_border_width_all(2)
	panel_style.corner_radius_top_left     = 10
	panel_style.corner_radius_top_right    = 10
	panel_style.corner_radius_bottom_left  = 10
	panel_style.corner_radius_bottom_right = 10
	panel_style.set_content_margin_all(14.0)
	_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(_panel)

	# ── Inner VBox ────────────────────────────────────────────────────────────
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_panel.add_child(vbox)

	# ── Title row: Chippy label + "CHIPPY'S TIPS" header ─────────────────────
	var header_row = HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 10)
	vbox.add_child(header_row)

	_chippy_label = Label.new()
	_chippy_label.text = FACE_HAPPY
	_chippy_label.add_theme_font_size_override("font_size", 28)
	_chippy_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.0))
	_chippy_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header_row.add_child(_chippy_label)

	var title_lbl = Label.new()
	title_lbl.text = "CHIPPY'S TIPS"
	title_lbl.add_theme_font_size_override("font_size", 15)
	title_lbl.add_theme_color_override("font_color", Color(0.0, 1.0, 1.0))
	title_lbl.add_theme_color_override("font_outline_color", Color(0.0, 1.0, 1.0, 0.3))
	title_lbl.add_theme_constant_override("outline_size", 4)
	title_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header_row.add_child(title_lbl)

	# ── Horizontal rule ───────────────────────────────────────────────────────
	var rule = ColorRect.new()
	rule.color = Color(0.0, 1.0, 1.0, 0.35)
	rule.custom_minimum_size = Vector2(0, 1)
	vbox.add_child(rule)

	# ── Speech bubble ─────────────────────────────────────────────────────────
	var bubble_style = StyleBoxFlat.new()
	bubble_style.bg_color     = Color(0.05, 0.0, 0.12, 0.85)
	bubble_style.border_color = Color(1.0, 0.85, 0.0, 0.5)
	bubble_style.set_border_width_all(1)
	bubble_style.corner_radius_top_left     = 6
	bubble_style.corner_radius_top_right    = 6
	bubble_style.corner_radius_bottom_left  = 6
	bubble_style.corner_radius_bottom_right = 6
	bubble_style.set_content_margin_all(10.0)

	var bubble_container = PanelContainer.new()
	bubble_container.add_theme_stylebox_override("panel", bubble_style)
	bubble_container.custom_minimum_size = Vector2(0, 80)
	vbox.add_child(bubble_container)

	_speech_label = RichTextLabel.new()
	_speech_label.bbcode_enabled = true
	_speech_label.fit_content = true
	_speech_label.scroll_active = false
	_speech_label.add_theme_font_size_override("normal_font_size", 15)
	_speech_label.add_theme_color_override("default_color", Color(0.92, 0.92, 0.92))
	bubble_container.add_child(_speech_label)

	# ── Step counter hint ─────────────────────────────────────────────────────
	var step_lbl = Label.new()
	step_lbl.name = "StepHint"
	step_lbl.add_theme_font_size_override("font_size", 11)
	step_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
	step_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vbox.add_child(step_lbl)

	# ── Button row ────────────────────────────────────────────────────────────
	var btn_row = HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	btn_row.add_theme_constant_override("separation", 10)
	vbox.add_child(btn_row)

	_next_btn = _make_btn("[ NEXT > ]", Color(0.0, 1.0, 1.0))
	btn_row.add_child(_next_btn)
	_next_btn.pressed.connect(_on_next_pressed)

	_skip_btn = _make_btn("[ SKIP TUTORIAL ]", Color(0.55, 0.55, 0.6))
	btn_row.add_child(_skip_btn)
	_skip_btn.pressed.connect(_on_skip_pressed)


func _make_btn(label: String, color: Color) -> Button:
	var btn = Button.new()
	btn.text = label
	btn.flat = true
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color", color)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	return btn


# ─────────────────────────────────────────────────────────────────────────────
func _connect_signals() -> void:
	GameManager.game_state_changed.connect(_on_game_state_changed)
	GameManager.player_drank_beer.connect(_on_player_drank_beer)
	GameManager.ability_unlocked.connect(_on_ability_unlocked)
	GameManager.dutch_called.connect(_on_dutch_called)


# ─────────────────────────────────────────────────────────────────────────────
# Signal handlers
# ─────────────────────────────────────────────────────────────────────────────

func _on_game_state_changed(new_state: int) -> void:
	var state_name: String = GameManager.GameState.keys()[new_state]
	if state_name == _last_state:
		return  # Avoid duplicate tips for force-signal re-fires
	_last_state = state_name
	if TIPS.has(state_name):
		_load_tips_for_state(state_name)
		_animate_tip_in()


func _on_player_drank_beer(player_idx: int, _remaining: int) -> void:
	if player_idx == 0 and not _shown_events.has("first_beer_lost"):
		_shown_events["first_beer_lost"] = true
		_show_event_tip("first_beer_lost")


func _on_ability_unlocked(player_idx: int, _ability_id: String) -> void:
	if player_idx == 0 and not _shown_events.has("ability_bought"):
		_shown_events["ability_bought"] = true
		_show_event_tip("ability_bought")


func _on_dutch_called(_player_idx: int) -> void:
	if not _shown_events.has("dutch_called"):
		_shown_events["dutch_called"] = true
		_show_event_tip("dutch_called")


# ─────────────────────────────────────────────────────────────────────────────
# Tip management
# ─────────────────────────────────────────────────────────────────────────────

func _load_tips_for_state(state_name: String) -> void:
	_current_tips = TIPS.get(state_name, [])
	_tip_index = 0


func _display_current_tip() -> void:
	if _current_tips.is_empty():
		return
	var tip = _current_tips[_tip_index]
	_chippy_label.text = tip.face
	_speech_label.text = tip.text
	_update_step_hint()


func _update_step_hint() -> void:
	var step_lbl = _panel.find_child("StepHint", true, false)
	if step_lbl and _current_tips.size() > 1:
		step_lbl.text = "%d / %d" % [_tip_index + 1, _current_tips.size()]
	elif step_lbl:
		step_lbl.text = ""


func _show_event_tip(tag: String) -> void:
	if not EVENT_TIPS.has(tag):
		return
	var tip = EVENT_TIPS[tag]
	_current_tips = [tip]
	_tip_index = 0
	_animate_tip_in()


func _animate_tip_in() -> void:
	if _is_animating:
		# Snap to new content immediately if already mid-animation
		_display_current_tip()
		return
	_is_animating = true

	# Slide-out (shrink scale Y to 0)
	var tween = create_tween()
	tween.tween_property(_panel, "scale:y", 0.0, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func():
		_display_current_tip()
	)
	tween.tween_property(_panel, "scale:y", 1.0, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func():
		_is_animating = false
	)


# ─────────────────────────────────────────────────────────────────────────────
# Button handlers
# ─────────────────────────────────────────────────────────────────────────────

func _on_next_pressed() -> void:
	if _current_tips.is_empty():
		return
	if _tip_index < _current_tips.size() - 1:
		_tip_index += 1
		_animate_tip_in()
	# If already at last tip, button does nothing (waits for state change)


func _on_skip_pressed() -> void:
	# Graceful exit: animate the panel out, then remove self
	var tween = create_tween()
	tween.tween_property(_panel, "scale", Vector2(0.0, 0.0), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(func():
		tutorial_finished.emit()
		GameManager.tutorial_mode = false
		queue_free()
	)

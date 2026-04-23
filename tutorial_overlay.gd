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

# ── States that ONLY apply to the human player (player index 0) ──────────────
# Tips for these states are suppressed when it is a bot's turn.
const PLAYER_ONLY_STATES: Array = [
	"TURN_START_DRAW",
	"TURN_RESOLVE_DRAWN",
	"TURN_END_CHOICE",
	"TURN_PEEK_ABILITY",
	"TURN_SWAP_ABILITY",
	"TURN_JUMP_IN_SELECTION",
	"TURN_CONFIRM_DUTCH",
	"STATE_PLAYING_ABILITY",
]

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
		{ "face": FACE_COOL,   "text": "You drew a card. Now choose:\n• Click the DISCARD PILE to throw it away, OR\n• Click one of YOUR face-down cards to SWAP." },
		{ "face": FACE_SMUG,   "text": "Swapping replaces your face-down card with the drawn one.\nThe old card goes to the discard. If you drew low — swap it in!" },
		{ "face": FACE_HAPPY,  "text": "Special ranks: Queen = peek any card, Jack = swap any two.\nDiscard them to trigger these abilities!" },
	],
	"TURN_PEEK_ABILITY": [
		{ "face": FACE_COOL,   "text": "You played a Queen!\nClick any face-down card on the table to secretly peek at it." },
		{ "face": FACE_SMUG,   "text": "Peek an opponent's card to find their low-value ones.\nThen swap them away with a Jack later. Sneaky!" },
	],
	"TURN_SWAP_ABILITY": [
		{ "face": FACE_SMUG,   "text": "You played a Jack!\nClick any two face-down cards to blindly swap their positions." },
		{ "face": FACE_COOL,   "text": "Nobody sees what swapped — not even you.\nSwap your worst card with someone else's best. Probably." },
	],
	"TURN_END_CHOICE": [
		{ "face": FACE_HAPPY,  "text": "Done drawing? Click END TURN to pass to the next player." },
		{ "face": FACE_SMUG,   "text": "Think you have the lowest score? Click CALL DUTCH!\nEveryone gets one last turn, then you confirm or bail." },
	],
	"TURN_JUMP_IN_SELECTION": [
		{ "face": FACE_SCARED, "text": "JUMP IN mode! Select one of your cards.\nIt must match the RANK of the top discard card exactly." },
		{ "face": FACE_DEAD,   "text": "Wrong rank = penalty card + you drink a beer.\nDrink all 3 beers and you're ELIMINATED. No pressure!" },
	],
	"TURN_CONFIRM_DUTCH": [
		{ "face": FACE_SCARED, "text": "You called Dutch and everyone had their last turn.\nCONFIRM to end the game, or FORFEIT to keep playing\n(you can't call Dutch again if you forfeit!)." },
	],
	"GAME_OVER": [
		{ "face": FACE_PARTY,  "text": "Game over! All cards flip face-up now.\nLowest total score wins. Count carefully!" },
		{ "face": FACE_HAPPY,  "text": "That's Dutch! You're a pro now.\nClick SKIP TUTORIAL to remove me — I believe in you!" },
	],
	"STATE_PLAYING_ABILITY": [
		{ "face": FACE_COOL,   "text": "You're playing an ability! Good timing.\nThe effect resolves automatically." },
	],
}

# ── One-off event tips ────────────────────────────────────────────────────────
const EVENT_TIPS: Dictionary = {
	"first_beer_lost": {
		"face": FACE_DEAD,
		"text": "Oof! You drank a beer. You start with 3 lives.\nDrink all 3 and you're out. Don't Jump In recklessly!"
	},
	"dutch_called_by_other": {
		"face": FACE_SCARED,
		"text": "Someone called DUTCH! The final round just started.\nEveryone (including you) gets one last turn — make it count!"
	},
	"dutch_called_by_self": {
		"face": FACE_SCARED,
		"text": "You called Dutch! Everyone else gets one last turn.\nThen it's back to you to CONFIRM or FORFEIT."
	},
}

# ── Ability descriptions for when the player buys one ────────────────────────
const ABILITY_DESCRIPTIONS: Dictionary = {
	"bottoms_up":     "Force a chosen player to drink a beer.\nOne step closer to eliminating them!",
	"refuel":         "Gain an extra beer (max 3).\nGreat for staying in the game longer.",
	"trim_off":       "Remove your HIGHEST value card from your hand.\nInstant score reduction — very strong!",
	"boulder":        "Give a chosen player the highest card left in the deck.\nTheir problem now!",
	"uno_reverse":    "Reverse the turn order.\nUseful to make a dangerous opponent wait longer.",
	"skip":           "Block a chosen player's next turn entirely.\nThey sit it out!",
	"perfect_match":  "Reset hands — you get Ace, 2, 3, 4 (very low!).\nOthers get random cards. Everyone keeps their money.",
	"inflation":      "Double a chosen player's card values for scoring.\nUse on whoever has the most cards.",
	"half_off":       "Halve a chosen player's card values for scoring.\nUse on yourself for an instant advantage!",
	"jumpscare":      "You receive a card, but a chosen player gets JUMPSCARED.\nTheir card flips — so you learn what they're hiding!",
	"shuffle":        "Randomly shuffle all of a chosen player's cards.\nDestroy their carefully-memorised hand!",
	"polarity_shift": "Flip the win condition — suddenly HIGHEST score wins!\nA total game-changer if you're losing.",
}

# ── State ─────────────────────────────────────────────────────────────────────
var _current_tips: Array = []
var _tip_index: int = 0
var _shown_events: Dictionary = {}  # tag -> true once shown
var _is_animating: bool = false
var _last_state: String = ""
var _last_money: int = 0            # Track money to detect crossing the $50 threshold

# ── Node references (populated in _build_ui) ──────────────────────────────────
var _chippy_label: Label
var _speech_label: RichTextLabel
var _next_btn: Button
var _skip_btn: Button
var _panel: PanelContainer

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	_build_ui()
	_connect_signals()
	# DEAL_CARDS fires before the overlay is added — show the welcome tip manually.
	_load_tips_for_state("DEAL_CARDS")
	_display_current_tip()

# ─────────────────────────────────────────────────────────────────────────────
func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# ── Outer panel anchored bottom-right ─────────────────────────────────────
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_panel.offset_left   = -420.0
	_panel.offset_top    = -270.0
	_panel.offset_right  = -14.0
	_panel.offset_bottom = -14.0

	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color     = Color(0.02, 0.0, 0.06, 0.90)
	panel_style.border_color = Color(0.0, 1.0, 1.0, 0.85)
	panel_style.set_border_width_all(2)
	panel_style.corner_radius_top_left     = 10
	panel_style.corner_radius_top_right    = 10
	panel_style.corner_radius_bottom_left  = 10
	panel_style.corner_radius_bottom_right = 10
	panel_style.set_content_margin_all(14.0)
	_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(_panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_panel.add_child(vbox)

	# ── Header ────────────────────────────────────────────────────────────────
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

	# ── Step counter ──────────────────────────────────────────────────────────
	var step_lbl = Label.new()
	step_lbl.name = "StepHint"
	step_lbl.add_theme_font_size_override("font_size", 11)
	step_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
	step_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vbox.add_child(step_lbl)

	# ── Buttons ───────────────────────────────────────────────────────────────
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
	GameManager.card_discarded.connect(_on_card_discarded)
	GameManager.player_gained_money.connect(_on_player_gained_money)


# ─────────────────────────────────────────────────────────────────────────────
# Signal handlers
# ─────────────────────────────────────────────────────────────────────────────

func _on_game_state_changed(new_state: int) -> void:
	var state_name: String = GameManager.GameState.keys()[new_state]

	# FIX 1: Suppress player-specific tips when it is a bot's turn.
	# These states fire for every player — only speak to the human when it's their go.
	if state_name in PLAYER_ONLY_STATES:
		if GameManager.current_player_index != 0:
			return  # Bot's turn — Chippy stays quiet
		# Player-only states are NOT deduplicated: the player deserves a reminder each turn.
	else:
		# Global states (DEAL_CARDS, GAME_OVER, etc.) — deduplicate force-signal re-fires.
		if state_name == _last_state:
			return
		_last_state = state_name

	if TIPS.has(state_name):
		_load_tips_for_state(state_name)
		_animate_tip_in()


func _on_player_drank_beer(player_idx: int, _remaining: int) -> void:
	# Only narrate when the HUMAN drinks, not the bots.
	if player_idx != 0:
		return
	if not _shown_events.has("first_beer_lost"):
		_shown_events["first_beer_lost"] = true
		_show_event_tip("first_beer_lost")


func _on_ability_unlocked(player_idx: int, ability_id: String) -> void:
	# FIX 4: Show ability-specific description rather than a generic message.
	# Only fires for the human player.
	if player_idx != 0:
		return
	var desc = ABILITY_DESCRIPTIONS.get(ability_id, "A mysterious ability. Use it on your turn!")
	var name_clean: String = ability_id.replace("_", " ").capitalize()
	_show_transient_tip(FACE_PARTY, "You got: %s!\n%s" % [name_clean, desc])


func _on_dutch_called(caller_idx: int) -> void:
	if not _shown_events.has("dutch_called"):
		_shown_events["dutch_called"] = true
		if caller_idx == 0:
			_show_event_tip("dutch_called_by_self")
		else:
			_show_event_tip("dutch_called_by_other")


# FIX 2: Suggest Jump-In when the human has a card matching the new discard.
func _on_card_discarded(player_idx: int, card_data: CardData) -> void:
	# Only makes sense as an interrupt when someone ELSE discarded.
	if player_idx == 0:
		return
	# Don't pile a jump-in tip on top of an existing jump-in in progress.
	if GameManager.current_state == GameManager.GameState.TURN_JUMP_IN_SELECTION:
		return
	if not GameManager.can_player_start_jump_in(0):
		return
	if GameManager.players_info[0].is_eliminated:
		return

	var discarded_rank: String = card_data.rank.to_lower()
	for c: CardData in GameManager.players_info[0].hand:
		if c.rank.to_lower() == discarded_rank:
			var rank_display: String = card_data.rank.capitalize()
			_show_transient_tip(FACE_COOL,
				"Psst! You have a %s too! Click JUMP IN now!\nRight match = free discard. Wrong = penalty beer." % rank_display)
			return


# FIX 3: Suggest buying an ability when the player first crosses the $50 threshold.
func _on_player_gained_money(player_idx: int, _amount: int, total: int) -> void:
	if player_idx != 0:
		return
	# Trigger the tip every time the player crosses $50 from below
	# (e.g. after spending on an ability and earning back up to $50).
	if _last_money < 50 and total >= 50:
		_show_transient_tip(FACE_SMUG,
			"You have $%d! Click the CHICKEN on the table to buy an ability egg for $50.\nAbilities can totally change the game!" % total)
	_last_money = total


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
	"""Show a named one-off tip from the EVENT_TIPS dictionary."""
	if not EVENT_TIPS.has(tag):
		return
	var tip = EVENT_TIPS[tag]
	_current_tips = [tip]
	_tip_index = 0
	_animate_tip_in()


func _show_transient_tip(face: String, text: String) -> void:
	"""Show an ad-hoc tip (not from a dictionary). Does not affect seen-event tracking."""
	_current_tips = [{ "face": face, "text": text }]
	_tip_index = 0
	_animate_tip_in()


func _animate_tip_in() -> void:
	if _is_animating:
		# Snap to new content immediately if already mid-animation.
		_display_current_tip()
		return
	_is_animating = true

	var tween = create_tween()
	tween.tween_property(_panel, "scale:y", 0.0, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func(): _display_current_tip())
	tween.tween_property(_panel, "scale:y", 1.0, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func(): _is_animating = false)


# ─────────────────────────────────────────────────────────────────────────────
# Button handlers
# ─────────────────────────────────────────────────────────────────────────────

func _on_next_pressed() -> void:
	if _current_tips.is_empty():
		return
	if _tip_index < _current_tips.size() - 1:
		_tip_index += 1
		_animate_tip_in()
	# If already at the last tip, wait for the next state change.


func _on_skip_pressed() -> void:
	var tween = create_tween()
	tween.tween_property(_panel, "scale", Vector2(0.0, 0.0), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(func():
		tutorial_finished.emit()
		GameManager.tutorial_mode = false
		queue_free()
	)

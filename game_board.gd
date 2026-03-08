extends Control

@onready var deck_area = $CenterTable/DeckArea
@onready var discard_area = $CenterTable/DiscardArea
@onready var player_pos_bottom = $PlayerPositions/Bottom
@onready var player_pos_top = $PlayerPositions/Top
@onready var player_pos_left = $PlayerPositions/Left
@onready var player_pos_right = $PlayerPositions/Right
@onready var turn_label = $GameUI/MainHUD/TopLeft/TurnLabel
@onready var top_center = $GameUI/MainHUD/TopCenter


var bot_controller: BotController = null

var end_turn_btn: Button
var jump_in_btn: Button
var call_dutch_btn: Button
var confirm_dutch_box: HBoxContainer

var player_hands: Array = [[], [], [], []]
var card_spacing = 110.0
var padding = 20.0
var card_pivot = Vector2(50, 70)
var pending_card: Node = null
var pending_card_tween: Tween = null
var swap_sources: Array = [] # Stores [card_node, player_idx, card_idx]

# Peek Phase state
var cards_peeked: int = 0
var max_peeks: int = 2
var peeked_card_nodes: Array = []

var pause_menu_scene = preload("res://pause_menu.tscn")
var pause_menu_instance: Node = null

func _ready():
	print("Game Board: Ready. Connecting signals...")
	GameManager.stop_menu_music()
	GameManager.game_state_changed.connect(_on_game_state_changed)
	GameManager.turn_started.connect(_on_turn_started)
	GameManager.card_drawn_to_pending.connect(_on_card_drawn_to_pending)
	GameManager.card_discarded.connect(_on_card_discarded)
	GameManager.jump_in_penalty.connect(_on_jump_in_penalty)
	GameManager.deck_ready.connect(_update_deck_visual)
	GameManager.bot_action.connect(_on_bot_action)
	resized.connect(_on_resized)
	
	var deck_button = $CenterTable/DeckArea/Slotbg/Interaction
	if deck_button:
		deck_button.reparent(deck_area)
		deck_button.z_index = 10
		deck_button.pressed.connect(_on_deck_clicked)
	
	_create_dutch_ui()
	
	var discard_button = $CenterTable/DiscardArea/Slotbg/Interaction
	if discard_button:
		discard_button.reparent(discard_area)
		discard_button.z_index = 10
		discard_button.pressed.connect(_on_discard_clicked)
	
	# Instantiate and wire the BotController.
	bot_controller = BotController.new()
	bot_controller.gm = GameManager
	add_child(bot_controller)
	
	await get_tree().process_frame
	_update_deck_visual()
	
	print("Game Board: Starting game...")
	GameManager.initialize_game(4)

func _create_dutch_ui():
	# Inject standalone buttons (no containers to prevent layout crashes)
	end_turn_btn = Button.new()
	end_turn_btn.text = "END TURN"
	end_turn_btn.add_theme_font_size_override("font_size", 20)
	var style_green = StyleBoxFlat.new()
	style_green.bg_color = Color(0.2, 0.6, 0.2)
	end_turn_btn.add_theme_stylebox_override("normal", style_green)
	end_turn_btn.pressed.connect(_on_end_turn_pressed)
	$GameUI/MainHUD.add_child(end_turn_btn)
	end_turn_btn.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	end_turn_btn.offset_left = -270
	end_turn_btn.offset_right = -110
	end_turn_btn.offset_top = -250
	end_turn_btn.offset_bottom = -200
	end_turn_btn.hide()
	
	jump_in_btn = Button.new()
	jump_in_btn.text = "JUMP IN"
	jump_in_btn.add_theme_font_size_override("font_size", 20)
	var style_blue = StyleBoxFlat.new()
	style_blue.bg_color = Color(0.2, 0.4, 0.8)
	jump_in_btn.add_theme_stylebox_override("normal", style_blue)
	jump_in_btn.pressed.connect(_on_jump_in_pressed)
	$GameUI/MainHUD.add_child(jump_in_btn)
	jump_in_btn.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	jump_in_btn.offset_left = -80
	jump_in_btn.offset_right = 80
	jump_in_btn.offset_top = -250
	jump_in_btn.offset_bottom = -200
	jump_in_btn.hide() # Hidden until a card lands in the discard pile.

	call_dutch_btn = Button.new()
	call_dutch_btn.text = "CALL DUTCH!"
	call_dutch_btn.add_theme_font_size_override("font_size", 20)
	var style_red = StyleBoxFlat.new()
	style_red.bg_color = Color(0.8, 0.2, 0.2)
	call_dutch_btn.add_theme_stylebox_override("normal", style_red)
	call_dutch_btn.pressed.connect(_on_call_dutch_pressed)
	$GameUI/MainHUD.add_child(call_dutch_btn)
	call_dutch_btn.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	call_dutch_btn.offset_left = 110
	call_dutch_btn.offset_right = 270
	call_dutch_btn.offset_top = -250
	call_dutch_btn.offset_bottom = -200
	call_dutch_btn.hide()
	
	# Inject Confirm/Cancel panel at the bottom-center, replacing End Turn / Call Dutch.
	confirm_dutch_box = HBoxContainer.new()
	confirm_dutch_box.add_theme_constant_override("separation", 20)
	$GameUI/MainHUD.add_child(confirm_dutch_box)
	confirm_dutch_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	confirm_dutch_box.offset_left = -270
	confirm_dutch_box.offset_right = 270
	confirm_dutch_box.offset_top = -250
	confirm_dutch_box.offset_bottom = -200
	confirm_dutch_box.hide()
	
	var confirm_btn = Button.new()
	confirm_btn.text = "CONFIRM DUTCH"
	confirm_btn.add_theme_font_size_override("font_size", 20)
	var style_confirm = StyleBoxFlat.new()
	style_confirm.bg_color = Color(0.2, 0.6, 0.2)
	confirm_btn.add_theme_stylebox_override("normal", style_confirm)
	confirm_btn.pressed.connect(_on_confirm_dutch_pressed)
	confirm_dutch_box.add_child(confirm_btn)
	
	var cancel_btn = Button.new()
	cancel_btn.text = "FORFEIT DUTCH"
	cancel_btn.add_theme_font_size_override("font_size", 20)
	var style_cancel = StyleBoxFlat.new()
	style_cancel.bg_color = Color(0.8, 0.2, 0.2)
	cancel_btn.add_theme_stylebox_override("normal", style_cancel)
	cancel_btn.pressed.connect(_on_cancel_dutch_pressed)
	confirm_dutch_box.add_child(cancel_btn)

func _update_deck_visual():
	for child in deck_area.get_children():
		if child.name.begins_with("DeckVisual"):
			child.queue_free()
	
	var card_scene = preload("res://card.tscn")
	var stack_size = min(5, GameManager.deck_manager.deck.size())
	for i in range(stack_size):
		var card_bg = card_scene.instantiate()
		deck_area.add_child(card_bg)
		card_bg.name = "DeckVisual_" + str(i)
		card_bg.setup(CardData.new("Ace", "Clubs"))
		card_bg.position = Vector2(-i * 2, -i * 2)
		card_bg.z_index = -i
	
	if deck_area.has_node("Interaction"):
		deck_area.move_child(deck_area.get_node("Interaction"), -1)

func _on_turn_started(player_idx):
	print("Game Board: Player ", player_idx, "'s turn.")
	
	var p_info = GameManager.players_info[player_idx]
	var label_text = p_info.name + "'s Turn"
	
	if turn_label:
		turn_label.text = label_text
	
	# Show a brief message so humans can track bot turns.
	if player_idx != 0:
		_show_message(p_info.name + " is drawing…")

func _on_deck_clicked():
	if GameManager.current_player_index != 0:
		print("FSM Blocked: Not your turn to draw.")
		return
	if GameManager.current_state != GameManager.GameState.TURN_START_DRAW:
		print("Warning: FSM prevents drawing from deck right now.")
		return
	GameManager.player_draw_card()

func _on_discard_clicked():
	if GameManager.current_player_index != 0:
		print("FSM Blocked: Not your turn to discard.")
		return
	if GameManager.current_state != GameManager.GameState.TURN_RESOLVE_DRAWN:
		print("Warning: FSM prevents discarding drawn card right now.")
		return
	GameManager.player_discard_drawn_card()

func _on_player_card_clicked(card_node, _card_data):
	var p_idx = -1
	var c_idx = -1
	for i in range(player_hands.size()):
		var idx = player_hands[i].find(card_node)
		if idx != -1:
			p_idx = i
			c_idx = idx
			break
			
	if p_idx == -1: return
	
	# Guard: during jump-in selection player 0 can always interact even on a bot's turn.
	var is_jump_in_phase := GameManager.current_state == GameManager.GameState.TURN_JUMP_IN_SELECTION
	var player_0_acts := (GameManager.current_player_index == 0 or (is_jump_in_phase and GameManager.jump_in_player_idx == 0))
	if not player_0_acts and GameManager.current_state != GameManager.GameState.INITIAL_PEEK:
		print("FSM Blocked: Not your turn. Cannot interact with cards.")
		return

	match GameManager.current_state:
		GameManager.GameState.INITIAL_PEEK:
			if p_idx == 0: # Only player 0 peeks at start in this version
				_handle_initial_peek_click(card_node)
		GameManager.GameState.TURN_RESOLVE_DRAWN:
			if p_idx == GameManager.current_player_index:
				GameManager.player_swap_drawn_card(c_idx)
			else:
				print("FSM Blocked: Cannot swap drawn card into opponent's hand.")
		GameManager.GameState.TURN_JUMP_IN_SELECTION:
			# Only the current jump-in player can select a card.
			var ji := GameManager.jump_in_player_idx
			if ji == 0 and p_idx == 0:
				if GameManager.validate_jump_in(c_idx):
					print("Player successfully jumped in!")
				else:
					print("Jump in failed! Rank does not match.")
			else:
				print("Not your jump-in turn.")
		GameManager.GameState.TURN_PEEK_ABILITY:
			if card_node.data.is_face_up:
				print("FSM Blocked: Cannot peek at a card that is already face-up.")
				return
			_handle_peek_ability(card_node)
		GameManager.GameState.TURN_SWAP_ABILITY:
			_handle_swap_ability(card_node, p_idx, c_idx)

func _handle_peek_ability(card_node):
	for p_hand in player_hands:
		for card in p_hand:
			card.mouse_filter = Control.MOUSE_FILTER_IGNORE
			
	card_node.flip()
	await get_tree().create_timer(3.0).timeout
	card_node.flip()
	
	for p_hand in player_hands:
		for card in p_hand:
			card.mouse_filter = Control.MOUSE_FILTER_STOP
			
	GameManager.complete_peek_ability()
	clear_all_highlights()

func _handle_swap_ability(card_node, p_idx, c_idx):
	# Don't allow clicking the same card twice
	for s in swap_sources:
		if s.node == card_node:
			return
			
	swap_sources.append({"node": card_node, "player": p_idx, "index": c_idx})
	card_node.set_selected(true)
	
	if swap_sources.size() == 2:
		_perform_jack_swap()

func _perform_jack_swap():
	var s1 = swap_sources[0]
	var s2 = swap_sources[1]
	
	GameManager.complete_swap_ability(s1.player, s1.index, s2.player, s2.index)
	
	player_hands[s1.player][s1.index] = s2.node
	player_hands[s2.player][s2.index] = s1.node
	
	s1.node.set_selected(false)
	s2.node.set_selected(false)
	
	swap_sources.clear()
	clear_all_highlights()
	reposition_all_cards()

func _on_bot_action(message: String) -> void:
	_show_message(message)
	# Auto-hide the bot-action message after 2 seconds.
	var timer := get_tree().create_timer(2.0)
	timer.timeout.connect(func():
		# Only clear if no other message replaced it.
		_hide_message()
	)

func _show_message(text: String):
	# Clear previous messages if any
	for child in top_center.get_children():
		child.queue_free()
		
	var label = Label.new()
	label.name = "AbilityMessage"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	label.text = text
	label.add_theme_font_size_override("font_size", 24)
	top_center.add_child(label)
	# Use responsive anchors
	top_center.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top_center.offset_top = 220 # Safe distance below top player cards
	label.show()

func _hide_message():
	for child in top_center.get_children():
		child.queue_free()

func _on_card_discarded(player_idx, card_data):
	# Show the jump-in button as soon as there's something to jump into.
	if jump_in_btn and not GameManager.deck_manager.discard_pile.is_empty():
		jump_in_btn.show()
	
	var card_to_discard: Node = null
	
	if pending_card and pending_card.data == card_data:
		card_to_discard = pending_card
		pending_card = null
	elif player_idx != -1:
		var hand = player_hands[player_idx]
		for i in range(hand.size()):
			if hand[i].data == card_data:
				card_to_discard = hand[i]
				
				if pending_card:
					if pending_card_tween and pending_card_tween.is_running():
						pending_card_tween.kill()
						
					hand[i] = pending_card
					
					# Ensure card in hand IS face-down by default
					if hand[i].data.is_face_up:
						hand[i].flip() # Visual flip
					
					if not hand[i].card_clicked.is_connected(_on_player_card_clicked):
						hand[i].card_clicked.connect(_on_player_card_clicked)
					
					pending_card = null
					reposition_all_cards()
				else:
					# Pure discard (e.g. from Jump-In or a special effect). 
					# Shrink the hand array so `reposition_all_cards` gracefully recenters the remaining cards.
					hand.remove_at(i)
					reposition_all_cards()
				break
	
	if card_to_discard:
		card_to_discard.z_index = 100
		var target_pos = discard_area.global_position
		var tween = create_tween()
		tween.tween_property(card_to_discard, "global_position", target_pos, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_callback(func():
			for child in discard_area.get_children():
				if child.name.begins_with("DiscardVisual"):
					child.queue_free()
			
			card_to_discard.reparent(discard_area)
			card_to_discard.name = "DiscardVisual"
			
			# Perfectly center the 100x140 card without stretching it
			card_to_discard.set_anchors_preset(Control.PRESET_CENTER)
			card_to_discard.size = Vector2(100, 140)
			card_to_discard.offset_left = -50
			card_to_discard.offset_top = -70
			card_to_discard.offset_right = 50
			card_to_discard.offset_bottom = 70
			
			card_to_discard.rotation_degrees = 0
			card_to_discard.z_index = 0
			
			# Reveal the card to all players
			if not card_to_discard.data.is_face_up:
				card_to_discard.flip()
			
			if discard_area.has_node("Interaction"):
				discard_area.move_child(discard_area.get_node("Interaction"), -1)
		)

func _on_card_drawn_to_pending(player_idx, card_data):
	# Bots: silent draw — no card visual on the table.
	if player_idx != 0:
		_update_deck_visual()
		return
	
	# Player: spawn face-down at the deck and flip in place so it looks
	# like the top card of the deck is being turned over.
	var card_scene = preload("res://card.tscn")
	pending_card = card_scene.instantiate()
	add_child(pending_card)
	
	card_data.is_face_up = false # Start face-down…
	pending_card.setup(card_data)
	
	var deck_pos = deck_area.global_position - card_pivot
	pending_card.global_position = deck_pos
	
	_update_deck_visual()
	
	# …then flip to reveal it in place (0.3 s tween inside card.flip()).
	await get_tree().create_timer(0.1).timeout
	pending_card.flip()

func _on_jump_in_penalty(player_idx, penalty_card_data):
	var card_scene = preload("res://card.tscn")
	var new_card = card_scene.instantiate()
	add_child(new_card)
	new_card.setup(penalty_card_data)
	
	new_card.card_clicked.connect(_on_player_card_clicked)
	player_hands[player_idx].append(new_card)
	
	var spawn_pos = deck_area.global_position - card_pivot
	new_card.global_position = spawn_pos
	
	# Slide the card down into the updated hand layout
	reposition_all_cards()
	_update_deck_visual()

func _on_resized():
	reposition_all_cards()

func _on_game_state_changed(new_state):
	_hide_message()
	
	if end_turn_btn: end_turn_btn.hide()
	if call_dutch_btn: call_dutch_btn.hide()
	if confirm_dutch_box: confirm_dutch_box.hide()
	
	# ── Deck / discard interaction lockout ───────────────────────────────────
	# Deck is clickable ONLY when it's the player's draw turn.
	# Discard is clickable ONLY when the player has a pending drawn card.
	var deck_button = deck_area.get_node("Interaction")
	var discard_button = discard_area.get_node("Interaction")
	var player_can_draw: bool = (new_state == GameManager.GameState.TURN_START_DRAW
		and GameManager.current_player_index == 0)
	var player_can_discard: bool = (new_state == GameManager.GameState.TURN_RESOLVE_DRAWN
		and GameManager.current_player_index == 0)
	deck_button.mouse_default_cursor_shape = (
		Control.CURSOR_POINTING_HAND if player_can_draw else Control.CURSOR_ARROW)
	deck_button.mouse_filter = (
		Control.MOUSE_FILTER_STOP if player_can_draw else Control.MOUSE_FILTER_IGNORE)
	discard_button.mouse_filter = (
		Control.MOUSE_FILTER_STOP if player_can_discard else Control.MOUSE_FILTER_IGNORE)
	
	# ── Card click lockout — disable all hand cards during bot turns and
	#   special states that don't need card interaction from the player ──────
	var block_cards := false
	match new_state:
		GameManager.GameState.TURN_START_DRAW, \
		GameManager.GameState.TURN_RESOLVE_DRAWN, \
		GameManager.GameState.TURN_END_CHOICE, \
		GameManager.GameState.TURN_CONFIRM_DUTCH:
			# Block when it's a bot acting; player can still click their own cards
			# in RESOLVE_DRAWN to swap.
			block_cards = (GameManager.current_player_index != 0)
		GameManager.GameState.TURN_PEEK_ABILITY, \
		GameManager.GameState.TURN_SWAP_ABILITY, \
		GameManager.GameState.TURN_JUMP_IN_SELECTION:
			# Never block — player must click cards in these states.
			block_cards = false
		_:
			block_cards = true
	_set_all_cards_interactive(not block_cards)
	
	# ── Per-state UI & messages ────────────────────────────────────────────
	match new_state:
		GameManager.GameState.TURN_RESOLVE_DRAWN:
			if GameManager.current_player_index != 0:
				var name: String = GameManager.players_info[GameManager.current_player_index].name
				_show_message(name + " is deciding…")
		GameManager.GameState.TURN_END_CHOICE:
			if GameManager.current_player_index == 0:
				end_turn_btn.show()
				if GameManager.dutch_caller_index == -1 and GameManager.players_info[0].can_call_dutch:
					call_dutch_btn.show()
		GameManager.GameState.TURN_JUMP_IN_SELECTION:
			var ji_name: String = GameManager.players_info[GameManager.jump_in_player_idx].name if GameManager.jump_in_player_idx >= 0 else "Someone"
			var top_rank: String = ""
			if GameManager.deck_manager.discard_pile.size() > 0:
				top_rank = GameManager.deck_manager.discard_pile[-1].rank
			var rank_hint := (" — needs a " + top_rank) if top_rank != "" else ""
			_show_message(ji_name + ": pick a matching card%s, or cancel." % rank_hint)
			if GameManager.jump_in_player_idx == 0:
				end_turn_btn.show()
		GameManager.GameState.TURN_CONFIRM_DUTCH:
			if GameManager.current_player_index == 0:
				_show_message("You called Dutch! Confirm or Forfeit?")
				confirm_dutch_box.show()
		GameManager.GameState.DEAL_CARDS:
			_handle_initial_deal()
		GameManager.GameState.INITIAL_PEEK:
			_start_peek_phase()
		GameManager.GameState.TURN_PEEK_ABILITY:
			_show_message("Select ANY card to peek at.")
			_highlight_selectable_cards()
		GameManager.GameState.TURN_SWAP_ABILITY:
			_show_message("Select TWO cards on the board to swap.")
			_highlight_selectable_cards(true) # Pass true to highlight ALL cards
			swap_sources.clear()
func _set_all_cards_interactive(enabled: bool) -> void:
	for hand in player_hands:
		for card in hand:
			if is_instance_valid(card):
				card.mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE

func _highlight_selectable_cards(include_others: bool = false):
	if GameManager.current_state == GameManager.GameState.INITIAL_PEEK:
		# Only highlight player 0 cards at start
		for card in player_hands[0]:
			if is_instance_valid(card):
				card.set_highlighted(true)
	else:
		# Highlight based on the ability
		for hand in player_hands:
			for card in hand:
				if is_instance_valid(card):
					card.set_highlighted(include_others)

func clear_all_highlights():
	for hand in player_hands:
		for card in hand:
			if is_instance_valid(card):
				card.set_highlighted(false)

func _handle_initial_peek_click(card_node):
	if peeked_card_nodes.has(card_node):
		return
		
	if cards_peeked < max_peeks:
		print("Initial Peek: Player peeked at card ", cards_peeked + 1)
		card_node.flip()
		peeked_card_nodes.append(card_node)
		cards_peeked += 1
		
		if cards_peeked == max_peeks:
			_complete_peek_phase()

func _start_peek_phase():
	_show_message("Click 2 of your cards to peek")
	
	# Reset peek state
	cards_peeked = 0
	peeked_card_nodes.clear()
	_highlight_selectable_cards()

func _complete_peek_phase():
	_show_message("Starting game in 3 seconds...")
	clear_all_highlights() # Stop pulsing immediately
		
	await get_tree().create_timer(3.0).timeout
	
	# Flip them back
	for card in peeked_card_nodes:
		if is_instance_valid(card):
			card.flip()
	
	_hide_message()
	GameManager.complete_initial_peek()

func _handle_initial_deal():
	var card_scene = preload("res://card.tscn")
	var cards_per_player = 4
	
	for hand in player_hands:
		hand.clear()
	
	for p_idx in range(GameManager.num_players):
		for i in range(cards_per_player):
			var card_data_dict = GameManager.deck_manager.draw_card()
			if card_data_dict.is_empty():
				break
			
			var card_inst = card_scene.instantiate()
			var card_data = CardData.new(card_data_dict.rank, card_data_dict.suit)
			card_data.is_face_up = false
			
			add_child(card_inst)
			card_inst.setup(card_data)
			player_hands[p_idx].append(card_inst)
			GameManager.players_info[p_idx].hand.append(card_data)
			
			card_inst.card_clicked.connect(_on_player_card_clicked)
			
			# Get target transform
			var transform = get_card_transform(p_idx, i, cards_per_player)
			card_inst.rotation_degrees = transform.rotation
			
			var final_pos = transform.position - card_pivot.rotated(deg_to_rad(transform.rotation))
			var spawn_pos = deck_area.global_position - card_pivot
			card_inst.global_position = spawn_pos
			
			var tween = create_tween()
			tween.tween_property(card_inst, "global_position", final_pos, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			
			await get_tree().create_timer(0.05).timeout
	
	GameManager.change_state(GameManager.GameState.INITIAL_PEEK)

func reposition_all_cards():
	for p_idx in range(player_hands.size()):
		var hand = player_hands[p_idx]
		for i in range(hand.size()):
			var card = hand[i]
			if is_instance_valid(card):
				var transform = get_card_transform(p_idx, i, hand.size())
				var final_pos = transform.position - card_pivot.rotated(deg_to_rad(transform.rotation))
				
				var tween = create_tween().set_parallel(true)
				tween.tween_property(card, "rotation_degrees", transform.rotation, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				tween.tween_property(card, "global_position", final_pos, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				
				# Premium "lift" effect
				var lift_tween = create_tween()
				lift_tween.tween_property(card, "scale", Vector2(1.1, 1.1), 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				lift_tween.tween_property(card, "scale", Vector2(1.0, 1.0), 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

func get_card_transform(p_idx: int, card_idx: int, total_cards: int) -> Dictionary:
	var screen_size = get_viewport_rect().size
	var total_spread = card_spacing * (total_cards - 1)
	var half_h = 70.0
	var target_pivot = Vector2.ZERO
	var rot_deg = 0.0
	
	match p_idx:
		0:
			rot_deg = 0
			var start_x = (screen_size.x - total_spread) / 2.0
			target_pivot = Vector2(start_x + (card_idx * card_spacing), screen_size.y - padding - half_h)
		1:
			if GameManager.num_players == 2:
				rot_deg = 180
				var start_x = (screen_size.x - total_spread) / 2.0
				target_pivot = Vector2(start_x + (card_idx * card_spacing), padding + half_h)
			else:
				rot_deg = 90
				var start_y = (screen_size.y - total_spread) / 2.0
				target_pivot = Vector2(padding + half_h, start_y + (card_idx * card_spacing))
		2:
			rot_deg = 180
			var start_x = (screen_size.x - total_spread) / 2.0
			target_pivot = Vector2(start_x + (card_idx * card_spacing), padding + half_h)
		3:
			rot_deg = -90
			var start_y = (screen_size.y - total_spread) / 2.0
			target_pivot = Vector2(screen_size.x - padding - half_h, start_y + (card_idx * card_spacing))
	
	return {"position": target_pivot, "rotation": rot_deg}

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if pause_menu_instance == null:
			_pause_game()
		else:
			_resume_game()

func _pause_game() -> void:
	get_tree().paused = true
	pause_menu_instance = pause_menu_scene.instantiate()
	add_child(pause_menu_instance)
	pause_menu_instance.resumed.connect(_resume_game)
	pause_menu_instance.main_menu_requested.connect(_go_to_main_menu)

func _resume_game() -> void:
	get_tree().paused = false
	if pause_menu_instance:
		pause_menu_instance.queue_free()
		pause_menu_instance = null

func _go_to_main_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://main_menu.tscn")

func _on_end_turn_pressed():
	match GameManager.current_state:
		GameManager.GameState.TURN_END_CHOICE:
			if GameManager.current_player_index == 0:
				GameManager.end_turn()
		GameManager.GameState.TURN_JUMP_IN_SELECTION:
			# Player 0 cancels their own jump-in attempt — no penalty, no turn advance.
			if GameManager.jump_in_player_idx == 0:
				GameManager.cancel_jump_in()

func _on_jump_in_pressed():
	# Player 0 can jump in during any bot-turn state.
	# GameManager.start_jump_in handles all the guards internally.
	# Requires: it's NOT the player's own turn start/resolve, and there IS a discard pile.
	GameManager.start_jump_in(0) # 0 = human player

func _on_call_dutch_pressed():
	if GameManager.current_player_index == 0:
		GameManager.call_dutch(0)

func _on_confirm_dutch_pressed():
	if GameManager.current_player_index == 0:
		GameManager.confirm_dutch()

func _on_cancel_dutch_pressed():
	if GameManager.current_player_index == 0:
		GameManager.cancel_dutch()

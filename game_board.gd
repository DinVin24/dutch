extends Control

@onready var deck_area = $CenterTable/DeckArea
@onready var discard_area = $CenterTable/DiscardArea
@onready var turn_label = $GameUI/MainHUD/TopLeft/Panel/TurnLabel
@onready var top_center = $GameUI/MainHUD/TopCenter
@onready var dutch_button = $GameUI/MainHUD/BottomRight/Panel/DutchButton

var player_hands: Array = [[], [], [], []]
var relative_card_spacing = 0.08 # 8% of window width
var relative_padding = 0.05 # 5% safety margin for edges
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
	GameManager.deck_ready.connect(_update_deck_visual)
	resized.connect(_on_resized)
	
	var deck_button = $CenterTable/DeckArea/Slotbg/Interaction
	if deck_button:
		deck_button.reparent(deck_area)
		deck_button.z_index = 10
		deck_button.pressed.connect(_on_deck_clicked)
	
	var discard_button = $CenterTable/DiscardArea/Slotbg/Interaction
	if discard_button:
		discard_button.reparent(discard_area)
		discard_button.z_index = 10
		discard_button.pressed.connect(_on_discard_clicked)
	
	if dutch_button:
		dutch_button.pressed.connect(_on_dutch_clicked)
		dutch_button.hide()
	
	await get_tree().process_frame
	_update_deck_visual()
	
	print("Game Board: Starting game...")
	GameManager.initialize_game(4)

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
		
	# Only show Dutch button during your own turn start phase
	if player_idx == 0 and GameManager.dutch_caller_index == -1:
		dutch_button.show()
	else:
		dutch_button.hide()

func _on_deck_clicked():
	if GameManager.current_state != GameManager.GameState.TURN_START_DRAW:
		print("Warning: FSM prevents drawing from deck right now.")
		return
	GameManager.player_draw_card()

func _on_discard_clicked():
	if GameManager.current_state != GameManager.GameState.TURN_RESOLVE_DRAWN:
		print("Warning: FSM prevents discarding drawn card right now.")
		return
	dutch_button.hide()
	GameManager.player_discard_drawn_card()

func _on_dutch_clicked():
	if GameManager.current_state == GameManager.GameState.TURN_START_DRAW:
		dutch_button.hide()
		GameManager.call_dutch(0) # Player 0 is the human

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

	match GameManager.current_state:
		GameManager.GameState.INITIAL_PEEK:
			if p_idx == 0: # Only player 0 peeks at start in this version
				_handle_initial_peek_click(card_node)
		GameManager.GameState.TURN_RESOLVE_DRAWN:
			if p_idx == GameManager.current_player_index:
				dutch_button.hide()
				GameManager.player_swap_drawn_card(c_idx)
			else:
				print("FSM Blocked: Cannot swap drawn card into opponent's hand.")
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

func _show_message(text: String):
	# Clear previous messages if any
	for child in top_center.get_children():
		child.queue_free()
		
	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.75)
	style.set_corner_radius_all(10)
	style.expand_margin_left = 15
	style.expand_margin_right = 15
	panel.add_theme_stylebox_override("panel", style)
	top_center.add_child(panel)
	
	var label = Label.new()
	label.name = "AbilityMessage"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.text = text
	label.add_theme_font_size_override("font_size", 24)
	
	panel.add_child(label)
	label.show()

func _hide_message():
	for child in top_center.get_children():
		child.queue_free()

func _on_card_discarded(player_idx, card_data):
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
					
					if not hand[i].card_clicked.is_connected(_on_player_card_clicked):
						hand[i].card_clicked.connect(_on_player_card_clicked)
					
					pending_card = null
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
			card_to_discard.position = Vector2.ZERO
			card_to_discard.rotation_degrees = 0
			card_to_discard.z_index = 0
			
			if discard_area.has_node("Interaction"):
				discard_area.move_child(discard_area.get_node("Interaction"), -1)
		)

func _on_card_drawn_to_pending(player_idx, card_data):
	var card_scene = preload("res://card.tscn")
	pending_card = card_scene.instantiate()
	add_child(pending_card)
	pending_card.setup(card_data)
	pending_card.name = "PendingCard"
	
	pending_card.global_position = deck_area.global_position - card_pivot
	pending_card.z_index = 200
	
	var target_pos = deck_area.global_position + Vector2(0, 160) - card_pivot
	
	pending_card_tween = create_tween()
	pending_card_tween.tween_property(pending_card, "global_position", target_pos, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	_update_deck_visual()

func _on_resized():
	reposition_all_cards()

func _on_game_state_changed(new_state):
	_hide_message()
	
	var deck_button = deck_area.get_node("Interaction")
	if new_state == GameManager.GameState.TURN_START_DRAW:
		deck_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	else:
		deck_button.mouse_default_cursor_shape = Control.CURSOR_ARROW
		
	match new_state:
		GameManager.GameState.DEAL_CARDS:
			_handle_initial_deal()
		GameManager.GameState.INITIAL_PEEK:
			_start_peek_phase()
		GameManager.GameState.TURN_PEEK_ABILITY:
			_show_message("Select ANY card to peek at.")
			_highlight_selectable_cards()
		GameManager.GameState.TURN_SWAP_ABILITY:
			_show_message("Select TWO cards on the board to swap.")
			_highlight_selectable_cards()
			swap_sources.clear()
func _highlight_selectable_cards():
	for hand in player_hands:
		for card in hand:
			if is_instance_valid(card):
				card.set_highlighted(true)

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

func _complete_peek_phase():
	_show_message("Starting game in 3 seconds...")
		
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
	# All positions are global pixels based on the viewport
	var vp = get_viewport_rect().size
	var card_spacing = vp.x * 0.09
	var total_spread = card_spacing * (total_cards - 1)
	var target_pos = Vector2.ZERO
	var rot_deg = 0.0
	
	# Edge insets for the 4 sides (% of the viewport dimension)
	var v_inset = 0.12 # 12% from top/bottom for vertical hands
	var h_inset = 0.08 # 8% from left/right for side hands
	
	match p_idx:
		0: # Bottom player
			rot_deg = 0
			var start_x = (vp.x - total_spread) / 2.0
			target_pos = Vector2(start_x + card_idx * card_spacing, vp.y * (1.0 - v_inset))
		1: # Top or Left player
			if GameManager.num_players == 2:
				rot_deg = 180
				var start_x = (vp.x - total_spread) / 2.0
				target_pos = Vector2(start_x + card_idx * card_spacing, vp.y * v_inset)
			else:
				# Left: cards laid vertically, spread along Y
				rot_deg = 90
				var v_spacing = vp.x * 0.09
				var v_spread = v_spacing * (total_cards - 1)
				var start_y = (vp.y - v_spread) / 2.0
				target_pos = Vector2(vp.x * h_inset, start_y + card_idx * v_spacing)
		2: # Top player
			rot_deg = 180
			var start_x = (vp.x - total_spread) / 2.0
			target_pos = Vector2(start_x + card_idx * card_spacing, vp.y * v_inset)
		3: # Right player
			rot_deg = -90
			var v_spacing = vp.y * 0.09
			var v_spread = v_spacing * (total_cards - 1)
			var start_y = (vp.y - v_spread) / 2.0
			target_pos = Vector2(vp.x * (1.0 - h_inset), start_y + card_idx * v_spacing)
	
	return {"position": target_pos, "rotation": rot_deg}

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

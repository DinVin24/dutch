extends Control

@onready var deck_area = $CenterTable/DeckArea
@onready var discard_area = $CenterTable/DiscardArea
@onready var player_pos_bottom = $PlayerPositions/Bottom
@onready var player_pos_top = $PlayerPositions/Top
@onready var player_pos_left = $PlayerPositions/Left
@onready var player_pos_right = $PlayerPositions/Right

# Responsive storage: Array of Arrays [player_index][card_index] = Card node
var player_hands: Array = [[], [], [], []]
var card_spacing = 110.0
var padding = 20.0
var card_pivot = Vector2(50, 70)
var pending_card: Node = null
var pending_card_tween: Tween = null
var current_ability_type: String = ""
var swap_sources: Array = [] # Stores [card_node, player_idx, card_idx]

var pause_menu_scene = preload("res://pause_menu.tscn")
var pause_menu_instance: Node = null

func _ready():
	print("Game Board: Ready. Connecting signals...")
	GameManager.stop_menu_music()
	GameManager.game_state_changed.connect(_on_game_state_changed)
	GameManager.turn_started.connect(_on_turn_started)
	GameManager.card_drawn_to_pending.connect(_on_card_drawn_to_pending)
	GameManager.card_discarded.connect(_on_card_discarded)
	resized.connect(_on_resized)
	
	# Connect deck interaction
	var deck_button = $CenterTable/DeckArea/Slotbg/Interaction
	if deck_button:
		deck_button.pressed.connect(_on_deck_clicked)
	
	await get_tree().process_frame
	_update_deck_visual()
	
	print("Game Board: Starting game...")
	GameManager.initialize_game(4)

func _update_deck_visual():
	# Clear previous deck visuals
	for child in deck_area.get_children():
		if child.name.begins_with("DeckVisual"):
			child.queue_free()
	
	# Add a few offset cards to represent the deck
	var card_scene = preload("res://card.tscn")
	var stack_size = min(5, GameManager.deck_manager.deck.size())
	for i in range(stack_size):
		var card_bg = card_scene.instantiate()
		deck_area.add_child(card_bg)
		card_bg.name = "DeckVisual_" + str(i)
		card_bg.setup(CardData.new("Ace", "Clubs")) # Data doesn't matter for back
		card_bg.position = Vector2(-i * 2, -i * 2)
		card_bg.z_index = -i
		card_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _on_turn_started(player_idx):
	print("Game Board: Player ", player_idx, "'s turn.")
	
	# Update HUD message
	var p_info = GameManager.players_info[player_idx]
	var label_text = "YOUR TURN" if player_idx == 0 else p_info.name + "'s Turn"
	
	if not $GameUI/MainHUD.has_node("TurnLabel"):
		var label = Label.new()
		label.name = "TurnLabel"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		$GameUI/MainHUD.add_child(label)
		label.set_anchors_preset(Control.PRESET_CENTER_TOP)
		label.position.y += 10
	
	$GameUI/MainHUD.get_node("TurnLabel").text = label_text
	
	# Enable/Disable deck interaction
	var deck_button = $CenterTable/DeckArea/Slotbg/Interaction
	if player_idx == 0:
		deck_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	else:
		deck_button.mouse_default_cursor_shape = Control.CURSOR_ARROW

func _on_deck_clicked():
	if GameManager.current_state != GameManager.GameState.PLAYER_TURN:
		print("Warning: It is not your turn!")
		return
	
	print("Player drawing card...")
	GameManager.player_draw_card()

func _on_discard_clicked():
	if GameManager.current_state == GameManager.GameState.DRAWN_CARD_PENDING and GameManager.current_player_index == 0:
		print("Player discarding drawn card...")
		GameManager.player_discard_drawn_card()

func _on_player_card_clicked(card_node, _card_data):
	if GameManager.current_state == GameManager.GameState.DRAWN_CARD_PENDING and GameManager.current_player_index == 0:
		var card_idx = player_hands[0].find(card_node)
		if card_idx != -1:
			print("Player swapping drawn card with card ", card_idx)
			GameManager.player_swap_drawn_card(card_idx)

func _on_special_move_started(player_idx: int, ability_type: String):
	print("Game Board: Special move started: ", ability_type, " for player ", player_idx)
	current_ability_type = ability_type
	
	if player_idx == 0:
		# Show instruction label
		if ability_type == "PEEK":
			_show_message("Select ANY card to peek at.")
		elif ability_type == "SWAP":
			_show_message("Select TWO cards on the board to swap.")
		
		# Ensure all cards are clickable
		for p_hand in player_hands:
			for card in p_hand:
				if not card.card_clicked.is_connected(_on_card_clicked_for_ability):
					card.card_clicked.connect(_on_card_clicked_for_ability)

func _on_special_move_ended(_player_idx: int):
	print("Game Board: Special move ended.")
	current_ability_type = ""
	_hide_message()
	
	# Disconnect ability clicks from opponent cards (player 0 cards stay connected for normal play)
	for i in range(1, player_hands.size()):
		for card in player_hands[i]:
			if card.card_clicked.is_connected(_on_card_clicked_for_ability):
				card.card_clicked.disconnect(_on_card_clicked_for_ability)

func _on_card_clicked_for_ability(card_node, _card_data):
	if GameManager.current_state != GameManager.GameState.SPECIAL_MOVE_PENDING:
		return
		
	if current_ability_type == "PEEK":
		_handle_peek_ability(card_node)
	elif current_ability_type == "SWAP":
		_handle_swap_ability(card_node)

func _handle_peek_ability(card_node):
	# Disable further clicks during the peek
	for p_hand in player_hands:
		for card in p_hand:
			card.mouse_filter = Control.MOUSE_FILTER_IGNORE
			
	card_node.flip()
	await get_tree().create_timer(3.0).timeout
	card_node.flip()
	
	# Re-enable filter
	for p_hand in player_hands:
		for card in p_hand:
			card.mouse_filter = Control.MOUSE_FILTER_STOP
			
	GameManager.end_special_move()

func _handle_swap_ability(card_node):
	# Find which player/index this card belongs to
	var p_idx = -1
	var c_idx = -1
	for i in range(player_hands.size()):
		var idx = player_hands[i].find(card_node)
		if idx != -1:
			p_idx = i
			c_idx = idx
			break
	
	if p_idx == -1: return
	
	swap_sources.append({"node": card_node, "player": p_idx, "index": c_idx})
	card_node.set_selected(true)
	
	if swap_sources.size() == 2:
		_perform_jack_swap()

func _perform_jack_swap():
	var s1 = swap_sources[0]
	var s2 = swap_sources[1]
	
	# Logic swap in GameManager
	var h1 = GameManager.players_info[s1.player].hand
	var h2 = GameManager.players_info[s2.player].hand
	
	var temp_data = h1[s1.index]
	h1[s1.index] = h2[s2.index]
	h2[s2.index] = temp_data
	
	# Visual reparenting/swap in GameBoard
	player_hands[s1.player][s1.index] = s2.node
	player_hands[s2.player][s2.index] = s1.node
	
	s1.node.set_selected(false)
	s2.node.set_selected(false)
	
	swap_sources.clear()
	
	# Animate swap
	reposition_all_cards() 
	
	await get_tree().create_timer(0.5).timeout
	GameManager.end_special_move()

func _show_message(text: String):
	# Simple label for now, we can add a proper HUD element later
	var label = get_node_or_null("GameUI/MainHUD/AbilityMessage")
	if not label:
		label = Label.new()
		label.name = "AbilityMessage"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_KEEP_WIDTH, 100)
		get_node("GameUI/MainHUD").add_child(label)
		label.add_theme_font_size_override("font_size", 24)
	
	label.text = text
	label.show()

func _hide_message():
	var label = get_node_or_null("GameUI/MainHUD/AbilityMessage")
	if label:
		label.hide()

func _on_card_discarded(player_idx, card_data):
	print("Game Board: Card discarded by player ", player_idx)
	
	# If it was a swap, we need to update the hand visual
	# For now, let's just animate the card to the discard pile
	
	var card_to_discard: Node = null
	
	# Was it the pending card?
	if pending_card and pending_card.data == card_data:
		card_to_discard = pending_card
		pending_card = null
	else:
		# Was it a card from a hand? (During a swap)
		# We need to find which node it was. 
		# We use player_idx directly from the signal to avoid race conditions with next_turn()
		var hand = player_hands[player_idx]
		for i in range(hand.size()):
			if hand[i].data == card_data:
				card_to_discard = hand[i]
				
				# If it's the player's hand, disconnect signals so it doesn't click from discard
				if player_idx == 0:
					if card_to_discard.card_clicked.is_connected(_on_player_card_clicked):
						card_to_discard.card_clicked.disconnect(_on_player_card_clicked)
				
				# Replace in hand with pending card if it exists
				if pending_card:
					if pending_card_tween and pending_card_tween.is_running():
						pending_card_tween.kill()
						
					hand[i] = pending_card
					
					# Connect signal for the new card in human hand
					if player_idx == 0:
						if not hand[i].card_clicked.is_connected(_on_player_card_clicked):
							hand[i].card_clicked.connect(_on_player_card_clicked)
					
					pending_card = null
					reposition_all_cards()
				break
	
	if card_to_discard:
		card_to_discard.z_index = 100 # Move above others
		var target_pos = discard_area.global_position - card_pivot
		var tween = create_tween()
		tween.tween_property(card_to_discard, "global_position", target_pos, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_callback(func():
			# Keep a few visuals in discard? For now just free or stack.
			# Let's keep the last one visible.
			for child in discard_area.get_children():
				if child.name.begins_with("DiscardVisual"):
					child.queue_free()
			
			card_to_discard.reparent(discard_area)
			card_to_discard.name = "DiscardVisual"
			card_to_discard.position = Vector2.ZERO - card_pivot # Center in area
			card_to_discard.z_index = 0
		)

func _on_card_drawn_to_pending(player_idx, card_data):
	print("Game Board: Card drawn to pending for player ", player_idx)
	
	var card_scene = preload("res://card.tscn")
	pending_card = card_scene.instantiate()
	add_child(pending_card)
	pending_card.setup(card_data)
	
	# Start at deck
	var spawn_pos = deck_area.global_position - card_pivot
	pending_card.global_position = spawn_pos
	
	# Target position: Slightly offset from deck towards player 0 (if human)
	# Or just center it more prominently
	# Target position: Slightly offset from deck towards player 0 (if human)
	var target_pos = deck_area.global_position + Vector2(0, 160) - card_pivot
	
	pending_card_tween = create_tween()
	pending_card_tween.tween_property(pending_card, "global_position", target_pos, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	# Update deck visual (remove one card if we are tracking count)
	_update_deck_visual()

func _on_resized():
	# Reposition all cards instantly when window size changes
	reposition_all_cards()

func _on_game_state_changed(new_state):
	match new_state:
		GameManager.GameState.DEAL_CARDS:
			_handle_initial_deal()
		GameManager.GameState.INITIAL_PEEK:
			_start_peek_phase()

func _start_peek_phase():
	print("Game Board: Initial Peek - Memorize your cards!")
	
	# Visual feedback for peek phase
	var label = Label.new()
	label.name = "PeekInstructions"
	label.text = "Memorizing your cards..."
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	$GameUI/MainHUD.add_child(label)
	label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	label.position.y += 50
	
	await get_tree().create_timer(0.5).timeout
	
	# Automatically reveal the first 2 cards for the player
	if player_hands[0].size() >= 2:
		player_hands[0][0].flip()
		player_hands[0][1].flip()
		
	# Wait for 3 seconds for the player to memorize
	await get_tree().create_timer(3.0).timeout
	
	# Flip them back
	if player_hands[0].size() >= 2:
		player_hands[0][0].flip()
		player_hands[0][1].flip()
		
	# Cleanup label
	if $GameUI/MainHUD.has_node("PeekInstructions"):
		$GameUI/MainHUD.get_node("PeekInstructions").queue_free()
		
	print("Game Board: Peek phase complete. Starting Player Turn.")
	GameManager.change_state(GameManager.GameState.PLAYER_TURN)

func _handle_initial_deal():
	print("Game Board: Dealing responsive cards...")
	var card_scene = preload("res://card.tscn")
	var cards_per_player = 4
	
	# Clear previous hand references just in case
	for hand in player_hands:
		hand.clear()
	
	for p_idx in range(GameManager.num_players):
		for i in range(cards_per_player):
			var card_data_dict = GameManager.deck_manager.draw_card()
			if card_data_dict.is_empty():
				print("Deck is empty!")
				break
			
			var card_inst = card_scene.instantiate()
			var card_data = CardData.new(card_data_dict.rank, card_data_dict.suit)
			card_data.is_face_up = false # Standard Dutch Rule: Dealt face down
			
			add_child(card_inst)
			card_inst.setup(card_data)
			player_hands[p_idx].append(card_inst)
			GameManager.players_info[p_idx].hand.append(card_data)
			
			if p_idx == 0:
				card_inst.card_clicked.connect(_on_player_card_clicked)
			
			# Get target transform
			var transform = get_card_transform(p_idx, i, cards_per_player)
			card_inst.rotation_degrees = transform.rotation
			
			# Pivot-aware positioning
			var final_pos = transform.position - card_pivot.rotated(deg_to_rad(transform.rotation))
			
			# Spawn at deck
			var spawn_pos = deck_area.global_position - card_pivot
			card_inst.global_position = spawn_pos
			
			var tween = create_tween()
			tween.tween_property(card_inst, "global_position", final_pos, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			
			await get_tree().create_timer(0.05).timeout
	
	print("Game Board: Deal complete. Transitioning to Peek phase.")
	GameManager.change_state(GameManager.GameState.INITIAL_PEEK)

func reposition_all_cards():
	for p_idx in range(player_hands.size()):
		var hand = player_hands[p_idx]
		for i in range(hand.size()):
			var card = hand[i]
			if is_instance_valid(card):
				print("GameBoard: Repositioning card ", i, " for player ", p_idx, " Node: ", card.name)
				var transform = get_card_transform(p_idx, i, hand.size())
				var final_pos = transform.position - card_pivot.rotated(deg_to_rad(transform.rotation))
				
				var tween = create_tween().set_parallel(true)
				tween.tween_property(card, "rotation_degrees", transform.rotation, 0.3)
				tween.tween_property(card, "global_position", final_pos, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func get_card_transform(p_idx: int, card_idx: int, total_cards: int) -> Dictionary:
	var screen_size = get_viewport_rect().size
	var total_spread = card_spacing * (total_cards - 1)
	var half_h = 70.0
	
	var target_pivot = Vector2.ZERO
	var rot_deg = 0.0
	
	match p_idx:
		0: # BOTTOM
			rot_deg = 0
			var start_x = (screen_size.x - total_spread) / 2.0
			target_pivot = Vector2(start_x + (card_idx * card_spacing), screen_size.y - padding - half_h)
		1: # TOP (2-player) or LEFT (3-4 player)
			if GameManager.num_players == 2:
				rot_deg = 180
				var start_x = (screen_size.x - total_spread) / 2.0
				target_pivot = Vector2(start_x + (card_idx * card_spacing), padding + half_h)
			else:
				rot_deg = 90
				var start_y = (screen_size.y - total_spread) / 2.0
				target_pivot = Vector2(padding + half_h, start_y + (card_idx * card_spacing))
		2: # TOP
			rot_deg = 180
			var start_x = (screen_size.x - total_spread) / 2.0
			target_pivot = Vector2(start_x + (card_idx * card_spacing), padding + half_h)
		3: # RIGHT
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

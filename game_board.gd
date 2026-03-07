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
	var target_pos = deck_area.global_position + Vector2(0, 160) - card_pivot
	
	var tween = create_tween()
	tween.tween_property(pending_card, "global_position", target_pos, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
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
	label.text = "Click 2 of your cards to peek"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	$GameUI/MainHUD.add_child(label)
	label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	label.position.y += 50
	
	# Reset peek state
	cards_peeked = 0
	peeked_card_nodes.clear()
	
	# Log for debug
	print("Game Board: Waiting for player to select cards to peek.")

func _on_card_clicked(card_node: CardUI, _card_data: CardData):
	if GameManager.current_state != GameManager.GameState.INITIAL_PEEK:
		return
		
	# Ensure it's a player card (player index 0)
	if not player_hands[0].has(card_node):
		print("Initial Peek: You can only peek at your own cards!")
		return
		
	# Check if already peeked this card
	if peeked_card_nodes.has(card_node):
		return
		
	if cards_peeked < max_peeks:
		print("Initial Peek: Player peeked at card ", cards_peeked + 1)
		card_node.flip()
		peeked_card_nodes.append(card_node)
		cards_peeked += 1
		
		if cards_peeked == max_peeks:
			_complete_peek_phase()

func _complete_peek_phase():
	if $GameUI/MainHUD.has_node("PeekInstructions"):
		$GameUI/MainHUD.get_node("PeekInstructions").text = "Starting game in 3 seconds..."
		
	# Wait for 3 seconds for the player to memorize
	await get_tree().create_timer(3.0).timeout
	
	# Flip them back
	for card in peeked_card_nodes:
		if is_instance_valid(card):
			card.flip()
	
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
			
			# Connect click signal for interaction
			card_inst.card_clicked.connect(_on_card_clicked)
			
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
				var transform = get_card_transform(p_idx, i, hand.size())
				card.rotation_degrees = transform.rotation
				card.global_position = transform.position - card_pivot.rotated(deg_to_rad(transform.rotation))

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

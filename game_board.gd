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

func _ready():
	print("Game Board: Ready. Connecting signals...")
	GameManager.game_state_changed.connect(_on_game_state_changed)
	resized.connect(_on_resized)
	
	await get_tree().process_frame
	
	print("Game Board: Starting game...")
	GameManager.initialize_game(4)

func _on_resized():
	# Reposition all cards instantly when window size changes
	reposition_all_cards()

func _on_game_state_changed(new_state):
	match new_state:
		GameManager.GameState.DEAL_CARDS:
			_handle_initial_deal()

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
			card_data.is_face_up = true
			
			add_child(card_inst)
			card_inst.setup(card_data) # Call after add_child to be safe
			player_hands[p_idx].append(card_inst)
			
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
			
			print("Dealt ", card_data.display_name(), " to Player ", p_idx)
			await get_tree().create_timer(0.1).timeout

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

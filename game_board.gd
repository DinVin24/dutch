extends Control

@onready var deck_area = $CenterTable/DeckArea
@onready var discard_area = $CenterTable/DiscardArea
@onready var player_pos_bottom = $PlayerPositions/Bottom
@onready var player_pos_top = $PlayerPositions/Top
@onready var player_pos_left = $PlayerPositions/Left
@onready var player_pos_right = $PlayerPositions/Right

func _ready():
	print("Game Board: Ready. Connecting signals...")
	GameManager.game_state_changed.connect(_on_game_state_changed)
	
	await get_tree().process_frame
	
	print("Game Board: Starting game...")
	# For testing: Initialize with 4 players (can be 2, 3, or 4)
	GameManager.initialize_game(4)

func _on_game_state_changed(new_state):
	match new_state:
		GameManager.GameState.DEAL_CARDS:
			_handle_initial_deal()

func _handle_initial_deal():
	print("Game Board: Dealing cards to ", GameManager.num_players, " players...")
	var card_scene = preload("res://card.tscn")
	var card_spacing = 110.0
	var cards_per_player = 4
	var card_width = 100.0
	
	# Map player index to Marker2D nodes
	var positions = [player_pos_bottom]
	if GameManager.num_players == 2:
		positions.append(player_pos_top)
	elif GameManager.num_players == 3:
		positions.append(player_pos_left)
		positions.append(player_pos_top)
	elif GameManager.num_players == 4:
		positions.append(player_pos_left)
		positions.append(player_pos_top)
		positions.append(player_pos_right)
	
	for p_idx in range(GameManager.num_players):
		var marker = positions[p_idx]
		var is_vertical = (marker == player_pos_left or marker == player_pos_right)
		
		# Define spread total height/width
		var total_spread = card_spacing * (cards_per_player - 1)
		
		# Base target positions relative to marker
		var start_pos: Vector2
		if is_vertical:
			# USE THE SAME CENTER Y FOR BOTH LEFT AND RIGHT
			# (Calculated from the viewport center to avoid any marker drift)
			var center_y = get_viewport_rect().size.y / 2.0
			var start_y = center_y - (total_spread / 2.0)
			
			var x_pos = marker.global_position.x
			if marker == player_pos_right:
				# Move RIGHT player MORE right (away from center)
				x_pos += 80
			elif marker == player_pos_left:
				# Move LEFT cards to the right (closer to center)
				x_pos += 80
				
			start_pos = Vector2(x_pos, start_y)
		else:
			# For horizontal layouts (Top/Bottom), center around marker's X
			var start_x = marker.global_position.x - (total_spread / 2.0)
			# Move bottom player LOWER (changed from +20 to +100)
			var y_offset = 100 if marker == player_pos_bottom else 0
			start_pos = Vector2(start_x, marker.global_position.y + y_offset)
		
		for i in range(cards_per_player):
			var card_data_dict = GameManager.deck_manager.draw_card()
			if card_data_dict.is_empty(): break
			
			var card_inst = card_scene.instantiate()
			var card_data = CardData.new()
			card_data.suit = card_data_dict.suit
			card_data.rank = card_data_dict.rank
			card_data.value = card_data_dict.value
			card_data.is_face_up = true
			
			# IMPORTANT: Setup happens before add_child, 
			# but CardUI._ready handles the visual update now.
			card_inst.setup(card_data)
			
			# Rotation
			if marker == player_pos_left:
				card_inst.rotation_degrees = 90
			elif marker == player_pos_right:
				card_inst.rotation_degrees = -90
			
			add_child(card_inst)
			
			# Target calculations
			var spread_offset = i * card_spacing
			var final_target = start_pos
			if is_vertical:
				final_target.y += spread_offset
			else:
				final_target.x += spread_offset
			
			# COMPENSATE FOR PIVOT (center of 100x140 card is 50,70)
			# This makes the CENTER of the card match the target coordinate
			var visual_center = Vector2(50, 70)
			card_inst.global_position = final_target - visual_center
			
			# Spawn at deck
			var spawn_pos = deck_area.global_position - visual_center
			card_inst.global_position = spawn_pos
			
			var tween = create_tween()
			tween.tween_property(card_inst, "global_position", final_target - visual_center, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			
			await get_tree().create_timer(0.1).timeout

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
	print("Game Board: Dealing cards with border-based positioning...")
	var card_scene = preload("res://card.tscn")
	var card_spacing = 110.0
	var cards_per_player = 4
	var card_size = Vector2(100, 140)
	var padding = 20.0
	
	var screen_size = get_viewport_rect().size
	var total_spread = card_spacing * (cards_per_player - 1)
	
	for p_idx in range(GameManager.num_players):
		var start_pos: Vector2
		var rotation = 0.0
		var is_vertical = false
		
		match p_idx:
			0: # BOTTOM (Player)
				var start_x = (screen_size.x - total_spread) / 2.0
				var y_pos = screen_size.y - padding - card_size.y
				start_pos = Vector2(start_x, y_pos)
			1: # TOP (Bot 1)
				if GameManager.num_players == 2:
					var start_x = (screen_size.x - total_spread) / 2.0
					var y_pos = padding
					start_pos = Vector2(start_x, y_pos)
				else: # For 3/4 players, 1 is Left
					var x_pos = padding
					var start_y = (screen_size.y - total_spread) / 2.0
					start_pos = Vector2(x_pos, start_y)
					rotation = 90
					is_vertical = true
			2: # TOP or RIGHT
				if GameManager.num_players == 3:
					var start_x = (screen_size.x - total_spread) / 2.0
					var y_pos = padding
					start_pos = Vector2(start_x, y_pos)
				else: # For 4 players, 2 is Top
					var start_x = (screen_size.x - total_spread) / 2.0
					var y_pos = padding
					start_pos = Vector2(start_x, y_pos)
			3: # RIGHT
				var x_pos = screen_size.x - padding - card_size.y # card_size.y because it's rotated 90
				var start_y = (screen_size.y - total_spread) / 2.0
				start_pos = Vector2(x_pos, start_y)
				rotation = -90
				is_vertical = true

		for i in range(cards_per_player):
			var card_data_dict = GameManager.deck_manager.draw_card()
			if card_data_dict.is_empty(): break
			
			var card_inst = card_scene.instantiate()
			var card_data = CardData.new()
			card_data.suit = card_data_dict.suit
			card_data.rank = card_data_dict.rank
			card_data.value = card_data_dict.value
			card_data.is_face_up = true
			card_inst.setup(card_data)
			
			card_inst.rotation_degrees = rotation
			add_child(card_inst)
			
			# Pivot is at (50, 70). Positioning global_position means positioning the TOP-LEFT of the card.
			# But rotation happens around the pivot.
			var offset = i * card_spacing
			var target_pos = start_pos
			if is_vertical:
				target_pos.y += offset
			else:
				target_pos.x += offset
			
			# To place the card relative to its BOUNDS while it has a pivot at center:
			# target_pos is the intended Top-Left of the card hand.
			# We must set global_position so the center (pivot) lands correctly.
			card_inst.global_position = target_pos
			
			var spawn_pos = deck_area.global_position
			card_inst.global_position = spawn_pos
			
			var tween = create_tween()
			tween.tween_property(card_inst, "global_position", target_pos, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			
			await get_tree().create_timer(0.1).timeout

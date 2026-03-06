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
	print("Game Board: Dealing cards with corrected pivot-compensated positioning...")
	var card_scene = preload("res://card.tscn")
	var card_spacing = 110.0
	var cards_per_player = 4
	var padding = 20.0
	
	# Current card dimensions from card.tscn/gd
	var card_width = 100.0
	var card_height = 140.0
	var card_pivot = Vector2(50, 70) # Center of the card
	
	var screen_size = get_viewport_rect().size
	var total_spread = card_spacing * (cards_per_player - 1)
	
	for p_idx in range(GameManager.num_players):
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
			
			var target_pivot: Vector2
			var rotation = 0.0
			
			# Logic for "20 pixels away from the closest border"
			# We calculate the intended WORLD position of the card's visual center (pivot)
			match p_idx:
				0: # BOTTOM
					var start_x = (screen_size.x - total_spread) / 2.0
					target_pivot = Vector2(start_x + (i * card_spacing), screen_size.y - padding - (card_height / 2.0))
					rotation = 0
				1: # TOP or LEFT
					if GameManager.num_players == 2:
						var start_x = (screen_size.x - total_spread) / 2.0
						target_pivot = Vector2(start_x + (i * card_spacing), padding + (card_height / 2.0))
						rotation = 180
					else: # LEFT
						var start_y = (screen_size.y - total_spread) / 2.0
						target_pivot = Vector2(padding + (card_height / 2.0), start_y + (i * card_spacing))
						rotation = 90
				2: # TOP
					var start_x = (screen_size.x - total_spread) / 2.0
					target_pivot = Vector2(start_x + (i * card_spacing), padding + (card_height / 2.0))
					rotation = 180
				3: # RIGHT
					var start_y = (screen_size.y - total_spread) / 2.0
					target_pivot = Vector2(screen_size.x - padding - (card_height / 2.0), start_y + (i * card_spacing))
					rotation = -90

			card_inst.rotation_degrees = rotation
			add_child(card_inst)
			
			# CRITICAL: In Godot, for a Control node with a pivot_offset, 
			# global_position = target_pivot_position - pivot_offset.rotated(global_rotation)
			var rad_rot = deg_to_rad(rotation)
			var rotated_pivot = card_pivot.rotated(rad_rot)
			var final_global_pos = target_pivot - rotated_pivot
			
			# Initial spawn at deck (also compensated)
			var spawn_pos = deck_area.global_position - card_pivot
			card_inst.global_position = spawn_pos
			
			var tween = create_tween()
			tween.tween_property(card_inst, "global_position", final_global_pos, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			
			await get_tree().create_timer(0.1).timeout

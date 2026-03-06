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
	print("Game Board: Dealing cards with robust pivot-compensated positioning...")
	var card_scene = preload("res://card.tscn")
	var card_spacing = 110.0
	var cards_per_player = 4
	var padding = 60.0 # Increased padding slightly to ensure no clipping
	
	# Dimensions for calculations (100x140 card)
	var card_pivot = Vector2(50, 70)
	var half_h = 70.0
	var half_w = 50.0
	
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
			var rot_deg = 0.0
			
			match p_idx:
				0: # BOTTOM
					rot_deg = 0
					var start_x = (screen_size.x - total_spread) / 2.0
					target_pivot = Vector2(start_x + (i * card_spacing), screen_size.y - padding - half_h)
				1: # TOP (in 2-player) or LEFT (in 3-4 player)
					if GameManager.num_players == 2:
						rot_deg = 180
						var start_x = (screen_size.x - total_spread) / 2.0
						target_pivot = Vector2(start_x + (i * card_spacing), padding + half_h)
					else:
						rot_deg = 90
						var start_y = (screen_size.y - total_spread) / 2.0
						target_pivot = Vector2(padding + half_h, start_y + (i * card_spacing))
				2: # TOP
					rot_deg = 180
					var start_x = (screen_size.x - total_spread) / 2.0
					target_pivot = Vector2(start_x + (i * card_spacing), padding + half_h)
				3: # RIGHT
					rot_deg = -90
					var start_y = (screen_size.y - total_spread) / 2.0
					target_pivot = Vector2(screen_size.x - padding - half_h, start_y + (i * card_spacing))

			# Add to scene FIRST so global properties work correctly
			add_child(card_inst)
			card_inst.rotation_degrees = rot_deg
			
			# Pivot-aware positioning formula:
			# global_position = desired_pivot_world_pos - pivot_offset.rotated(global_rotation)
			var final_pos = target_pivot - card_pivot.rotated(deg_to_rad(rot_deg))
			
			# Spawn at deck
			var spawn_pos = deck_area.global_position - card_pivot
			card_inst.global_position = spawn_pos
			
			var tween = create_tween()
			tween.tween_property(card_inst, "global_position", final_pos, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			
			await get_tree().create_timer(0.1).timeout

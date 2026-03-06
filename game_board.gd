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
	print("Game Board: Dealing cards with center-based border positioning...")
	var card_scene = preload("res://card.tscn")
	var card_spacing = 110.0
	var cards_per_player = 4
	var padding = 20.0
	
	# Card extents (100x140 card with pivot at 50,70)
	var card_pivot = Vector2(50, 70)
	var horizontal_half_height = 70.0 # Height/2 when horizontal
	var vertical_half_width = 70.0 # height/2 when rotated 90 (becomes width)
	
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
			
			var target_center: Vector2
			var rotation = 0.0
			
			match p_idx:
				0: # BOTTOM (Player)
					var start_x = (screen_size.x - total_spread) / 2.0
					target_center = Vector2(start_x + (i * card_spacing), screen_size.y - padding - horizontal_half_height)
					rotation = 0
				1: # TOP or LEFT
					if GameManager.num_players == 2:
						var start_x = (screen_size.x - total_spread) / 2.0
						target_center = Vector2(start_x + (i * card_spacing), padding + horizontal_half_height)
						rotation = 180 # Facing player
					else:
						# LEFT
						var start_y = (screen_size.y - total_spread) / 2.0
						target_center = Vector2(padding + vertical_half_width, start_y + (i * card_spacing))
						rotation = 90
				2: # TOP
					var start_x = (screen_size.x - total_spread) / 2.0
					target_center = Vector2(start_x + (i * card_spacing), padding + horizontal_half_height)
					rotation = 180
				3: # RIGHT
					var start_y = (screen_size.y - total_spread) / 2.0
					target_center = Vector2(screen_size.x - padding - vertical_half_width, start_y + (i * card_spacing))
					rotation = -90

			card_inst.rotation_degrees = rotation
			add_child(card_inst)
			
			# Setting global_position on a Control node with a pivot_offset 
			# actually sets the position of the (0,0) corner.
			# To center the card at target_center, we subtract the pivot.
			var target_pos = target_center - card_pivot
			
			# Spawn at deck
			card_inst.global_position = deck_area.global_position - card_pivot
			
			var tween = create_tween()
			tween.tween_property(card_inst, "global_position", target_pos, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			
			await get_tree().create_timer(0.1).timeout

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
		# Perfect centering: Subtract half the total spread + half a card width
		var start_x = marker.global_position.x - (card_spacing * (cards_per_player - 1)) / 2.0 - (card_width / 2.0)
		var y_pos = marker.global_position.y - 70 # Offset for card height height/2
		
		for i in range(cards_per_player):
			var card_data_dict = GameManager.deck_manager.draw_card()
			if card_data_dict.is_empty(): break
			
			var card_inst = card_scene.instantiate()
			var card_data = CardData.new()
			card_data.suit = card_data_dict.suit
			card_data.rank = card_data_dict.rank
			card_data.value = card_data_dict.value
			
			# Only player's cards are face-up for now (debug)
			card_data.is_face_up = (p_idx == 0)
			
			card_inst.setup(card_data)
			add_child(card_inst)
			
			var target_pos = Vector2(start_x + (i * card_spacing), y_pos)
			card_inst.global_position = deck_area.global_position
			
			var tween = create_tween()
			tween.tween_property(card_inst, "global_position", target_pos, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			
			await get_tree().create_timer(0.1).timeout

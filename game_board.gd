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
	
	# Wait for a frame to ensure the UI containers have calculated their positions
	await get_tree().process_frame
	
	print("Game Board: Starting game...")
	GameManager.start_game()

func _on_game_state_changed(new_state):
	match new_state:
		GameManager.GameState.DEAL_CARDS:
			_handle_initial_deal()

func _handle_initial_deal():
	print("Game Board: Dealing 4 cards to Player (Bottom)...")
	var card_scene = preload("res://card.tscn")
	var card_spacing = 110.0
	var total_cards = 4
	
	# Start position: centered relative to the bottom marker
	var start_x = player_pos_bottom.global_position.x - (card_spacing * (total_cards - 1)) / 2.0
	var y_pos = player_pos_bottom.global_position.y
	
	for i in range(total_cards):
		var card_data_dict = GameManager.deck_manager.draw_card()
		if card_data_dict.is_empty():
			break
			
		var card_inst = card_scene.instantiate()
		var card_data = CardData.new()
		card_data.suit = card_data_dict.suit
		card_data.rank = card_data_dict.rank
		card_data.value = card_data_dict.value
		# In Dutch, you usually only see 2 of your 4 cards at the start, 
		# but for this test we'll show them all (face-up)
		card_data.is_face_up = true
		
		card_inst.setup(card_data)
		add_child(card_inst)
		
		# Position calculations
		var target_pos = Vector2(start_x + (i * card_spacing), y_pos)
		card_inst.global_position = deck_area.global_position # Spawn at deck
		
		# Simple deal animation
		var tween = create_tween()
		tween.tween_property(card_inst, "global_position", target_pos, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		
		# Add a slight delay between cards
		await get_tree().create_timer(0.15).timeout

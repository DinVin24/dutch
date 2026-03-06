extends Control

@onready var deck_area = $CenterTable/DeckArea
@onready var discard_area = $CenterTable/DiscardArea
@onready var player_pos_bottom = $PlayerPositions/Bottom
@onready var player_pos_top = $PlayerPositions/Top
@onready var player_pos_left = $PlayerPositions/Left
@onready var player_pos_right = $PlayerPositions/Right

func _ready():
	# For now, just print that we are ready
	print("Game Board ready. Waiting for state manager instructions...")
	
	# Connect to GameManager signals if needed
	GameManager.game_state_changed.connect(_on_game_state_changed)

func _on_game_state_changed(new_state):
	match new_state:
		GameManager.GameState.DEAL_CARDS:
			_handle_initial_deal()

func _handle_initial_deal():
	print("Visual dealing: NOT YET FULLY IMPLEMENTED")
	# This would spawn CardUI nodes and tween them to player positions

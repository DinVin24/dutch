extends Node

# Game States
enum GameState {
	INITIALIZING,
	DEAL_CARDS,
	PLAYER_TURN,
	CPU_TURN,
	CHECK_DUTCH,
	GAME_OVER
}

# Signals
signal game_state_changed(new_state)
signal turn_started(player_id)
signal game_over(winner_id)
signal deck_ready

var current_state: GameState = GameState.INITIALIZING
var deck_manager: DeckManager

func _ready():
	deck_manager = DeckManager.new()
	add_child(deck_manager)
	
	# Initial deck creation
	deck_manager.create_deck()
	deck_ready.emit()

func change_state(new_state: GameState):
	current_state = new_state
	game_state_changed.emit(new_state)
	
	match current_state:
		GameState.DEAL_CARDS:
			_handle_deal_cards()
		GameState.PLAYER_TURN:
			turn_started.emit(0) # 0 for Player
		GameState.CPU_TURN:
			turn_started.emit(1) # 1 for CPU (basic for now)
		GameState.GAME_OVER:
			_handle_game_over()

func _handle_deal_cards():
	# UI/Board will listen for state change and handle visual dealing
	# For now, we move to player turn after a short delay in a real scenario
	# But here we just set the state
	pass

func _handle_game_over():
	# Logic to calculate scores will go here
	game_over.emit(-1) # Placeholder

func start_game():
	change_state(GameState.DEAL_CARDS)

func call_dutch(player_id: int):
	# Handle Dutch logic
	change_state(GameState.CHECK_DUTCH)

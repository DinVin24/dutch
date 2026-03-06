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
signal card_drawn(player_id, card_data)
signal card_discarded(player_id, card_data)

var current_state: GameState = GameState.INITIALIZING
var deck_manager: DeckManager
var bg_music_player: AudioStreamPlayer

# Match Settings
var num_players: int = 4 # Default to 4 players
var players_info: Array = []

func _ready():
	deck_manager = DeckManager.new()
	add_child(deck_manager)
	
	# Background Music Setup
	bg_music_player = AudioStreamPlayer.new()
	bg_music_player.stream = preload("res://bg_music.ogg")
	if bg_music_player.stream is AudioStreamOggVorbis:
		bg_music_player.stream.loop = true
	bg_music_player.volume_db = -10.0
	bg_music_player.bus = "Music"
	bg_music_player.process_mode = Node.PROCESS_MODE_ALWAYS # Keep playing when paused
	add_child(bg_music_player)
	
	# Initial deck creation
	deck_manager.create_deck()
	deck_ready.emit()

func play_menu_music() -> void:
	if bg_music_player and not bg_music_player.playing:
		bg_music_player.play()

func stop_menu_music() -> void:
	if bg_music_player and bg_music_player.playing:
		bg_music_player.stop()

func initialize_game(p_count: int = 4):
	num_players = p_count
	players_info.clear()
	for i in range(num_players):
		players_info.append({
			"id": i,
			"name": "Player " + str(i + 1) if i == 0 else "Bot " + str(i),
			"score": 0,
			"hand": [] # CardData objects
		})
	start_game()

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

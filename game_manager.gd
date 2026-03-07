extends Node

# Game States
enum GameState {
	INITIALIZING,
	DEAL_CARDS,
	INITIAL_PEEK,
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
var current_player_index: int = 0
var dutch_caller_index: int = -1 # -1 means no one has called Dutch yet

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
	
func play_menu_music() -> void:
	if bg_music_player and not bg_music_player.playing:
		bg_music_player.play()

func stop_menu_music() -> void:
	if bg_music_player and bg_music_player.playing:
		bg_music_player.stop()

func initialize_game(p_count: int = 4):
	num_players = p_count
	players_info.clear()
	current_player_index = 0
	dutch_caller_index = -1
	for i in range(num_players):
		players_info.append({
			"id": i,
			"name": "Player " + str(i + 1) if i == 0 else "Bot " + str(i),
			"score": 0,
			"hand": [] # CardData objects
		})
	
	# Ensure a fresh deck is ready for the new match
	deck_manager.create_deck()
	deck_ready.emit()
	
	start_game()

func change_state(new_state: GameState):
	current_state = new_state
	game_state_changed.emit(new_state)
	
	match current_state:
		GameState.DEAL_CARDS:
			_handle_deal_cards()
		GameState.PLAYER_TURN, GameState.CPU_TURN:
			turn_started.emit(current_player_index)
		GameState.GAME_OVER:
			_handle_game_over()

func next_turn():
	current_player_index = (current_player_index + 1) % num_players
	
	# Check if we returned to the Dutch caller
	if current_player_index == dutch_caller_index:
		change_state(GameState.GAME_OVER)
		return

	if current_player_index == 0:
		change_state(GameState.PLAYER_TURN)
	else:
		change_state(GameState.CPU_TURN)

func _handle_deal_cards():
	pass

func _handle_game_over():
	# Logic to calculate scores will go here
	game_over.emit(-1) # Placeholder

func start_game():
	change_state(GameState.DEAL_CARDS)

func call_dutch(player_id: int):
	if dutch_caller_index == -1:
		dutch_caller_index = player_id
		print("Player ", player_id, " called DUTCH!")
		# Game continues until it returns to this player
		next_turn()

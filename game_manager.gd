extends Node

# Strict FSM Game States
enum GameState {
	INITIALIZING,
	DEAL_CARDS,
	INITIAL_PEEK,
	TURN_START_DRAW,
	TURN_RESOLVE_DRAWN,
	TURN_PEEK_ABILITY,
	TURN_SWAP_ABILITY,
	TURN_END_CHOICE,
	TURN_JUMP_IN_SELECTION,
	CHECK_DUTCH,
	TURN_CONFIRM_DUTCH,
	GAME_OVER
}

# Signals
signal game_state_changed(new_state)
signal turn_started(player_id)
signal game_over(winner_id)
signal deck_ready
signal card_drawn(player_id, card_data)
signal card_drawn_to_pending(player_id, card_data)
signal card_discarded(player_id, card_data)
signal jump_in_penalty(player_idx, penalty_card_data)
signal bot_action(message: String)
signal memory_shift_required(player_idx, removed_card_idx)

var current_state: GameState = GameState.INITIALIZING
var deck_manager: DeckManager
var bg_music_player: AudioStreamPlayer

# Match Settings
var num_players: int = 4 # Hotseat local play
var players_info: Array = []
var current_player_index: int = 0
var dutch_caller_index: int = -1 # -1 means no one has called Dutch yet
var jump_in_player_idx: int = -1 # who is currently attempting the jump-in
var drawn_card_data: CardData = null

func _ready():
	deck_manager = DeckManager.new()
	add_child(deck_manager)
	
	# Background Music Setup
	bg_music_player = AudioStreamPlayer.new()
	bg_music_player.stream = preload("res://assets/music/bg_music.ogg")
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
	jump_in_player_idx = -1
	for i in range(num_players):
		players_info.append({
			"id": i,
			"name": "Player " + str(i + 1),
			"score": 0,
			"hand": [], # CardData objects
			"can_call_dutch": true,
			# bot_memory: { player_idx: { card_idx: CardData } }
			# Populated by BotController during INITIAL_PEEK.
			"bot_memory": {}
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
		GameState.TURN_START_DRAW:
			turn_started.emit(current_player_index)
		GameState.GAME_OVER:
			_handle_game_over()

func next_turn():
	current_player_index = (current_player_index + 1) % num_players
	
	# Check if we returned to the Dutch caller
	if current_player_index == dutch_caller_index:
		change_state(GameState.TURN_CONFIRM_DUTCH)
		return

	change_state(GameState.TURN_START_DRAW)

func _handle_deal_cards():
	# The board will handle the visual instantiation in its signal handler
	print("GameManager: Handling Deal Cards state.")
	pass

func _handle_game_over():
	# Logic to calculate scores will go here
	game_over.emit(-1) # Placeholder

func start_game():
	change_state(GameState.DEAL_CARDS)

func call_dutch(player_id: int):
	if current_state != GameState.TURN_END_CHOICE:
		print("FSM Blocked: Cannot call Dutch outside of TURN_END_CHOICE state")
		return
	if dutch_caller_index == -1 and players_info[player_id].can_call_dutch:
		dutch_caller_index = player_id
		print("Player ", player_id, " called DUTCH!")
		# Game continues until it returns to this player
		next_turn()

func _prompt_turn_end():
	change_state(GameState.TURN_END_CHOICE)

func end_turn():
	if current_state != GameState.TURN_END_CHOICE and current_state != GameState.TURN_JUMP_IN_SELECTION:
		print("FSM Blocked: Cannot end turn outside of END_CHOICE or JUMP_IN state")
		return
	next_turn()

## player_idx: who is jumping in. -1 defaults to current_player_index (bot use).
func start_jump_in(player_idx: int = -1) -> void:
	if current_state != GameState.TURN_END_CHOICE:
		return
	jump_in_player_idx = player_idx if player_idx != -1 else current_player_index
	change_state(GameState.TURN_JUMP_IN_SELECTION)

func validate_jump_in(card_idx: int) -> bool:
	if current_state != GameState.TURN_JUMP_IN_SELECTION:
		return false
	if jump_in_player_idx < 0 or jump_in_player_idx >= num_players:
		return false

	var h: Array = players_info[jump_in_player_idx].hand
	if card_idx < 0 or card_idx >= h.size():
		return false

	var selected_card: CardData = h[card_idx]
	if selected_card == null:
		return false

	if deck_manager.discard_pile.size() > 0:
		var top_discard: CardData = deck_manager.discard_pile[-1]
		if selected_card.rank == top_discard.rank:
			# Build the message before clearing jump_in_player_idx.
			var msg := "Player %d: %s of %s matches the %s of %s — JUMP IN!" % [
				jump_in_player_idx,
				selected_card.rank, selected_card.suit,
				top_discard.rank, top_discard.suit
			]
			print("[JUMP-IN] Player %d jumped in with %s of %s over a %s of %s" % [
				jump_in_player_idx,
				selected_card.rank, selected_card.suit,
				top_discard.rank, top_discard.suit
			])
			h.remove_at(card_idx)
			memory_shift_required.emit(jump_in_player_idx, card_idx)
			deck_manager.discard_pile.append(selected_card)
			card_discarded.emit(jump_in_player_idx, selected_card)
			jump_in_player_idx = -1
			_resolve_discard_effects(selected_card)
			# Emit AFTER _resolve_discard_effects so the message outlasts the
			# _hide_message() call triggered by the state change above.
			bot_action.emit(msg)
			return true

	print("No match. Jump In invalid. Assigning penalty card to player ", jump_in_player_idx)
	var penalty_card_dict: Dictionary = deck_manager.draw_card()
	if not penalty_card_dict.is_empty():
		var p_card := CardData.new(penalty_card_dict.rank, penalty_card_dict.suit)
		p_card.is_face_up = false
		h.append(p_card)
		jump_in_penalty.emit(jump_in_player_idx, p_card)

	jump_in_player_idx = -1
	change_state(GameState.TURN_END_CHOICE)
	return false

## Human opted out of a jump-in: return to TURN_END_CHOICE without penalty.
func cancel_jump_in() -> void:
	if current_state != GameState.TURN_JUMP_IN_SELECTION:
		return
	jump_in_player_idx = -1
	change_state(GameState.TURN_END_CHOICE)

func confirm_dutch():
	if current_state != GameState.TURN_CONFIRM_DUTCH:
		return
	print("Player ", current_player_index, " CONFIRMED Dutch. Game Over.")
	change_state(GameState.GAME_OVER)

func cancel_dutch():
	if current_state != GameState.TURN_CONFIRM_DUTCH:
		return
	print("Player ", current_player_index, " CANCELLED Dutch. Forfeiting right to call again.")
	players_info[current_player_index].can_call_dutch = false
	dutch_caller_index = -1
	# Give them their normal turn back
	change_state(GameState.TURN_START_DRAW)

func player_draw_card():
	if current_state != GameState.TURN_START_DRAW:
		print("FSM Blocked: Cannot draw card outside of TURN_START_DRAW state")
		return
	
	var card_info = deck_manager.draw_card()
	if card_info.is_empty():
		print("Deck is empty!")
		return
		
	drawn_card_data = CardData.new(card_info.rank, card_info.suit)
	drawn_card_data.is_face_up = true
	
	change_state(GameState.TURN_RESOLVE_DRAWN)
	print("GameManager: [DRAW SUCCESS] Player ", current_player_index, " state moved to RESOLVE.")
	card_drawn_to_pending.emit(current_player_index, drawn_card_data)

func player_discard_drawn_card():
	if current_state != GameState.TURN_RESOLVE_DRAWN:
		print("FSM Blocked: Cannot discard pending card outside of TURN_RESOLVE_DRAWN state")
		return
	
	print("GameManager: Discarding drawn card.")
	deck_manager.discard_pile.append(drawn_card_data)
	card_discarded.emit(current_player_index, drawn_card_data)
	
	var discarded_card = drawn_card_data
	drawn_card_data = null
	
	_resolve_discard_effects(discarded_card)

func player_swap_drawn_card(card_idx: int):
	if current_state != GameState.TURN_RESOLVE_DRAWN:
		print("FSM Blocked: Cannot swap outside of TURN_RESOLVE_DRAWN state")
		return
	
	var player_h = players_info[current_player_index].hand
	if card_idx < 0 or card_idx >= player_h.size():
		return
		
	# Swap cards
	var old_card = player_h[card_idx]
	print("GameManager: Swapping drawn card with hand card at idx ", card_idx)
	player_h[card_idx] = drawn_card_data
	
	# Old card goes to discard
	deck_manager.discard_pile.append(old_card)
	card_discarded.emit(current_player_index, old_card)
	
	drawn_card_data = null
	
	_resolve_discard_effects(old_card)

func _resolve_discard_effects(card: CardData):
	if card.rank == "Queen":
		print("Queen discarded! FSM -> TURN_PEEK_ABILITY")
		change_state(GameState.TURN_PEEK_ABILITY)
	elif card.rank == "Jack":
		print("Jack discarded! FSM -> TURN_SWAP_ABILITY")
		change_state(GameState.TURN_SWAP_ABILITY)
	else:
		_prompt_turn_end()

func complete_initial_peek():
	if current_state != GameState.INITIAL_PEEK:
		return
	change_state(GameState.TURN_START_DRAW)

func complete_peek_ability():
	if current_state != GameState.TURN_PEEK_ABILITY:
		print("FSM Blocked: Cannot complete peek outside of TURN_PEEK_ABILITY state")
		return
	_prompt_turn_end()

func complete_swap_ability(player1_idx: int, card1_idx: int, player2_idx: int, card2_idx: int):
	if current_state != GameState.TURN_SWAP_ABILITY:
		print("FSM Blocked: Cannot complete swap outside of TURN_SWAP_ABILITY state")
		return
		
	var h1 = players_info[player1_idx].hand
	var h2 = players_info[player2_idx].hand
	
	var temp_data = h1[card1_idx]
	h1[card1_idx] = h2[card2_idx]
	h2[card2_idx] = temp_data
	
	print("GameManager: Swapped card indices ", card1_idx, " and ", card2_idx, " between players ", player1_idx, " and ", player2_idx)
	
	_prompt_turn_end()

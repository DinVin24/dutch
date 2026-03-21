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
signal scores_ready(results: Array)      # Bug 3: carries sorted leaderboard
signal all_cards_revealed                 # Bug 3: tells board to flip all cards face-up
signal deck_ready
signal card_drawn_to_pending(player_id, card_data)
signal card_discarded(player_id, card_data)
signal jump_in_penalty(player_idx, penalty_card_data)
signal jump_in_failed(player_idx: int, card_idx: int, card_data: CardData) # Bug 2
signal bot_action(message: String)
signal memory_shift_required(player_idx, removed_card_idx)
signal jack_swap_resolved(p1: int, c1: int, p2: int, c2: int)
signal hand_updated(player_idx: int)
signal dutch_called(player_idx: int)

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
var jump_in_was_own_draw_phase: bool = false # true when player 0 jumps in at the start of their own turn
var pre_jump_in_state: GameState = GameState.INITIALIZING
var dev_console_enabled: bool = true

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
	players_info.clear()
	current_player_index = 0
	dutch_caller_index = -1
	jump_in_player_idx = -1
	
	if NetworkManager.peer != null:
		# Multiplayer setup
		var peer_ids = NetworkManager.players.keys()
		peer_ids.sort() # Ensure consistent order across all clients
		num_players = peer_ids.size()
		
		for i in range(num_players):
			var pid = peer_ids[i]
			players_info.append({
				"id": i,
				"peer_id": pid,
				"name": NetworkManager.players[pid].name,
				"score": 0,
				"hand": [], # CardData objects
				"can_call_dutch": true,
				"bot_memory": {}
			})
	else:
		# Local singleplayer/hotseat setup
		num_players = p_count
		for i in range(num_players):
			players_info.append({
				"id": i,
				"name": "Player_" + str(i + 1),
				"peer_id": 1 if i == 0 else 0, # 1 for human, 0 for bot
				"score": 0,
				"hand": [], # CardData objects
				"can_call_dutch": true,
				"bot_memory": {}
			})

var clients_ready_to_start = []

@rpc("any_peer", "call_local", "reliable")
func mark_client_ready() -> void:
	if multiplayer.multiplayer_peer == null:
		clients_ready_to_start.clear()
		_rpc_start_match(num_players if num_players > 0 else 4, randi())
		return
		
	var id = multiplayer.get_remote_sender_id()
	if id == 0: id = 1
	if not clients_ready_to_start.has(id):
		clients_ready_to_start.append(id)
		
	if multiplayer.is_server():
		if clients_ready_to_start.size() >= NetworkManager.players.size():
			clients_ready_to_start.clear()
			_rpc_start_match.rpc(NetworkManager.players.size(), randi())

@rpc("authority", "call_local", "reliable")
func _rpc_start_match(p_count: int, initial_seed: int) -> void:
	initialize_game(p_count)
	seed(initial_seed)
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
	# Bug 1 fix: always go to TURN_START_DRAW; the Dutch-caller check now lives
	# in _prompt_turn_end() so the caller still draws before confirming.
	change_state(GameState.TURN_START_DRAW)

func _handle_deal_cards():
	# The board will handle the visual instantiation in its signal handler
	print("GameManager: Handling Deal Cards state.")
	pass

func _handle_game_over():
	# Bug 3: flip all cards, calculate scores, emit results.
	all_cards_revealed.emit()
	var results := _calculate_scores()
	var winner_id: int = results[0].id if results.size() > 0 else -1
	game_over.emit(winner_id)
	scores_ready.emit(results)

func _calculate_scores() -> Array:
	# Build result entries.
	var entries: Array = []
	for i in range(num_players):
		var info = players_info[i]
		var hand: Array = info.hand
		# Edge case: player with 0 cards wins outright.
		if hand.size() == 0:
			entries.append({"id": i, "name": info.name, "score": -1, "card_count": 0})
			continue
		var total := 0
		for card in hand:
			total += (card as CardData).recalc_point_value()
		entries.append({"id": i, "name": info.name, "score": total, "card_count": hand.size()})
	# Sort: lowest score first; tiebreak by fewer cards.
	entries.sort_custom(func(a, b):
		if a.score != b.score:
			return a.score < b.score
		return a.card_count < b.card_count
	)
	return entries

func start_game():
	change_state(GameState.DEAL_CARDS)

func get_local_player_idx() -> int:
	if multiplayer.multiplayer_peer == null: return 0
	var my_id = multiplayer.get_unique_id()
	for i in range(players_info.size()):
		if players_info[i].peer_id == my_id: return i
	return 0

@rpc("any_peer", "call_local", "reliable")
func call_dutch(player_id: int):
	if current_state != GameState.TURN_END_CHOICE:
		print("FSM Blocked: Cannot call Dutch outside of TURN_END_CHOICE state")
		return
	if dutch_caller_index == -1 and players_info[player_id].can_call_dutch:
		dutch_caller_index = player_id
		print("Player ", player_id, " called DUTCH!")
		dutch_called.emit(player_id)
		# Game continues until it returns to this player
		next_turn()

func _prompt_turn_end():
	# If player 0 jumped in at the very start of their own draw turn, give them
	# their draw back instead of ending the turn.
	if jump_in_was_own_draw_phase:
		jump_in_was_own_draw_phase = false
		change_state(GameState.TURN_START_DRAW)
		return
	# Bug 1 fix: Dutch-caller check moved here so the caller always draws first.
	if current_player_index == dutch_caller_index:
		change_state(GameState.TURN_CONFIRM_DUTCH)
		return
	change_state(GameState.TURN_END_CHOICE)

@rpc("any_peer", "call_local", "reliable")
func end_turn():
	if current_state != GameState.TURN_END_CHOICE and current_state != GameState.TURN_JUMP_IN_SELECTION:
		print("FSM Blocked: Cannot end turn outside of END_CHOICE or JUMP_IN state")
		return
	next_turn()

## player_idx: who is jumping in. -1 defaults to current_player_index (bot use).
## Bots may only call this during TURN_END_CHOICE.
## Player 0 may call this during any bot-turn state to interrupt and select a card.
@rpc("any_peer", "call_local", "reliable")
func start_jump_in(player_idx: int = -1) -> void:
	var resolved_idx := player_idx if player_idx != -1 else current_player_index
	
	if resolved_idx == 0:
		# Human player: allow jump-in from any state EXCEPT their own active draw/resolve.
		var blocked_states := [
			GameState.INITIALIZING, GameState.DEAL_CARDS, GameState.INITIAL_PEEK,
			GameState.TURN_JUMP_IN_SELECTION, GameState.GAME_OVER,
			GameState.TURN_PEEK_ABILITY, GameState.TURN_SWAP_ABILITY
		]
		# Block if currently in a forbidden state.
		if (current_state in blocked_states):
			return
		# Require a non-empty discard pile to jump into.
		if deck_manager.discard_pile.is_empty():
			return
	else:
		# Bots may only jump in during TURN_END_CHOICE.
		if current_state != GameState.TURN_END_CHOICE:
			return
	
	# Track if player 0 is jumping in at the start of their own draw turn.
	if resolved_idx == 0 and current_state == GameState.TURN_START_DRAW:
		jump_in_was_own_draw_phase = true
	else:
		jump_in_was_own_draw_phase = false

	if current_state != GameState.TURN_JUMP_IN_SELECTION:
		pre_jump_in_state = current_state
	
	jump_in_player_idx = resolved_idx
	change_state(GameState.TURN_JUMP_IN_SELECTION)

@rpc("any_peer", "call_local", "reliable")
func validate_jump_in(card_idx: int) -> bool:
	if current_state != GameState.TURN_JUMP_IN_SELECTION:
		return false
	if jump_in_player_idx < 0 or jump_in_player_idx >= num_players:
		return false

	var h: Array = players_info[jump_in_player_idx].hand
	var selected_card: CardData = null
	
	if card_idx == -2:
		selected_card = drawn_card_data
	elif card_idx >= 0 and card_idx < h.size():
		selected_card = h[card_idx]
		
	if selected_card == null:
		return false

	if deck_manager.discard_pile.size() > 0:
		var top_discard: CardData = deck_manager.discard_pile[-1]
		# CASE-INSENSITIVE RANK MATCH
		if selected_card.rank.to_lower() == top_discard.rank.to_lower():
			var msg := "Player %d: %s of %s matches! JUMP IN!" % [
				jump_in_player_idx, selected_card.rank, selected_card.suit
			]
			if card_idx == -2:
				drawn_card_data = null
				change_state(GameState.TURN_END_CHOICE)
			else:
				h.remove_at(card_idx)
				hand_updated.emit(jump_in_player_idx)
				memory_shift_required.emit(jump_in_player_idx, card_idx)
			
			if h.size() == 0:
				change_state(GameState.GAME_OVER)
				return true
				
			deck_manager.discard_pile.append(selected_card)
			card_discarded.emit(jump_in_player_idx, selected_card)
			jump_in_player_idx = -1
			_resolve_discard_effects(selected_card)
			bot_action.emit(msg)
			return true

	print("No match. Jump In invalid.")
	jump_in_failed.emit(jump_in_player_idx, card_idx, selected_card)
	await get_tree().create_timer(1.2, false).timeout

	var penalty_card_dict: Dictionary = deck_manager.draw_card()
	if not penalty_card_dict.is_empty():
		var p_card := CardData.new(penalty_card_dict.rank, penalty_card_dict.suit)
		p_card.is_face_up = false
		h.append(p_card)
		hand_updated.emit(jump_in_player_idx)
		jump_in_penalty.emit(jump_in_player_idx, p_card)

	var was_own_draw := jump_in_was_own_draw_phase
	jump_in_player_idx = -1
	jump_in_was_own_draw_phase = false
	if was_own_draw:
		change_state(GameState.TURN_START_DRAW)
	else:
		change_state(pre_jump_in_state if pre_jump_in_state != GameState.TURN_JUMP_IN_SELECTION else GameState.TURN_END_CHOICE)
	return false

## Human opted out of a jump-in: return to TURN_END_CHOICE without penalty.
@rpc("any_peer", "call_local", "reliable")
func cancel_jump_in() -> void:
	if current_state != GameState.TURN_JUMP_IN_SELECTION:
		return
	jump_in_player_idx = -1
	change_state(pre_jump_in_state if pre_jump_in_state != GameState.TURN_JUMP_IN_SELECTION else GameState.TURN_END_CHOICE)

@rpc("any_peer", "call_local", "reliable")
func confirm_dutch():
	if current_state != GameState.TURN_CONFIRM_DUTCH:
		return
	print("Player ", current_player_index, " CONFIRMED Dutch. Game Over.")
	change_state(GameState.GAME_OVER)

@rpc("any_peer", "call_local", "reliable")
func cancel_dutch():
	if current_state != GameState.TURN_CONFIRM_DUTCH:
		return
	print("Player ", current_player_index, " CANCELLED Dutch. Forfeiting right to call again.")
	players_info[current_player_index].can_call_dutch = false
	dutch_caller_index = -1
	# Give them their normal turn back
	change_state(GameState.TURN_START_DRAW)

@rpc("any_peer", "call_local", "reliable")
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

@rpc("any_peer", "call_local", "reliable")
func player_discard_drawn_card():
	if current_state != GameState.TURN_RESOLVE_DRAWN:
		print("FSM Blocked: Cannot discard pending card outside of TURN_RESOLVE_DRAWN state")
		return
	
	print("GameManager: Discarding drawn card.")
	deck_manager.discard_pile.append(drawn_card_data)
	card_discarded.emit(current_player_index, drawn_card_data)
	
	var discarded_handled = drawn_card_data
	drawn_card_data = null
	
	_resolve_discard_effects(discarded_handled)

@rpc("any_peer", "call_local", "reliable")
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
	
	# Old card goes to discard first so board finds the node in the current hand
	deck_manager.discard_pile.append(old_card)
	card_discarded.emit(current_player_index, old_card)
	
	drawn_card_data.is_face_up = false # Must be face-down in hand
	player_h[card_idx] = drawn_card_data
	hand_updated.emit(current_player_index)
	
	drawn_card_data = null
	
	_resolve_discard_effects(old_card)

func _resolve_discard_effects(card: CardData):
	# Wait for the card discard visual tween to complete before changing state
	await get_tree().create_timer(0.4, false).timeout
	if card.rank == "Queen":
		print("Queen discarded! FSM -> TURN_PEEK_ABILITY")
		change_state(GameState.TURN_PEEK_ABILITY)
	elif card.rank == "Jack":
		print("Jack discarded! FSM -> TURN_SWAP_ABILITY")
		change_state(GameState.TURN_SWAP_ABILITY)
	else:
		_prompt_turn_end()

var _peek_ready_players = []

@rpc("any_peer", "call_local", "reliable")
func complete_initial_peek():
	if current_state != GameState.INITIAL_PEEK:
		return
		
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = 1
	
	if not _peek_ready_players.has(sender_id):
		_peek_ready_players.append(sender_id)
		
	var humans = 0
	var humans_ready = 0
	for i in range(num_players):
		var pid = players_info[i].peer_id
		if pid != 0:
			humans += 1
			if _peek_ready_players.has(pid):
				humans_ready += 1
				
	if humans_ready >= humans:
		if multiplayer.is_server() or multiplayer.multiplayer_peer == null:
			_proceed_to_first_turn.rpc()

@rpc("authority", "call_local", "reliable")
func _proceed_to_first_turn():
	_peek_ready_players.clear()
	change_state(GameState.TURN_START_DRAW)

@rpc("any_peer", "call_local", "reliable")
func complete_peek_ability():
	if current_state != GameState.TURN_PEEK_ABILITY:
		print("FSM Blocked: Cannot complete peek outside of TURN_PEEK_ABILITY state")
		return
	_prompt_turn_end()

@rpc("any_peer", "call_local", "reliable")
func complete_swap_ability(player1_idx: int, card1_idx: int, player2_idx: int, card2_idx: int):
	if current_state != GameState.TURN_SWAP_ABILITY:
		print("FSM Blocked: Cannot complete swap outside of TURN_SWAP_ABILITY state")
		return
		
	var h1 = players_info[player1_idx].hand
	var h2 = players_info[player2_idx].hand
	
	var temp_data = h1[card1_idx]
	h1[card1_idx] = h2[card2_idx]
	h2[card2_idx] = temp_data
	
	hand_updated.emit(player1_idx)
	hand_updated.emit(player2_idx)
	
	# Emit before _prompt_turn_end so the board can update visual nodes synchronously.
	jack_swap_resolved.emit(player1_idx, card1_idx, player2_idx, card2_idx)
	
	_prompt_turn_end()

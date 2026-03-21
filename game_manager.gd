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
var jump_in_resume_state: GameState = GameState.INITIALIZING
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
	num_players = p_count
	players_info.clear()
	current_state = GameState.INITIALIZING
	current_player_index = 0
	dutch_caller_index = -1
	jump_in_player_idx = -1
	jump_in_resume_state = GameState.INITIALIZING
	drawn_card_data = null
	for i in range(num_players):
		players_info.append({
			"id": i,
			"name": "Player_" + str(i + 1),
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
	if current_state == new_state:
		return
	if not _can_transition_to(new_state):
		push_warning("FSM Blocked: Illegal state transition %s -> %s" % [
			GameState.keys()[current_state],
			GameState.keys()[new_state]
		])
		return
	current_state = new_state
	game_state_changed.emit(new_state)
	
	match current_state:
		GameState.DEAL_CARDS:
			_handle_deal_cards()
		GameState.TURN_START_DRAW:
			turn_started.emit(current_player_index)
		GameState.GAME_OVER:
			_handle_game_over()

func _can_transition_to(new_state: GameState) -> bool:
	match current_state:
		GameState.INITIALIZING:
			return new_state == GameState.DEAL_CARDS
		GameState.DEAL_CARDS:
			return new_state == GameState.INITIAL_PEEK
		GameState.INITIAL_PEEK:
			return new_state == GameState.TURN_START_DRAW
		GameState.TURN_START_DRAW:
			return new_state in [GameState.TURN_RESOLVE_DRAWN, GameState.TURN_JUMP_IN_SELECTION]
		GameState.TURN_RESOLVE_DRAWN:
			return new_state in [
				GameState.TURN_PEEK_ABILITY,
				GameState.TURN_SWAP_ABILITY,
				GameState.TURN_END_CHOICE
			]
		GameState.TURN_PEEK_ABILITY, GameState.TURN_SWAP_ABILITY:
			return new_state in [
				GameState.TURN_START_DRAW,
				GameState.TURN_END_CHOICE,
				GameState.TURN_CONFIRM_DUTCH
			]
		GameState.TURN_END_CHOICE:
			return new_state in [
				GameState.TURN_START_DRAW,
				GameState.TURN_JUMP_IN_SELECTION,
				GameState.TURN_CONFIRM_DUTCH
			]
		GameState.TURN_JUMP_IN_SELECTION:
			return new_state in [
				GameState.TURN_START_DRAW,
				GameState.TURN_END_CHOICE,
				GameState.TURN_PEEK_ABILITY,
				GameState.TURN_SWAP_ABILITY,
				GameState.GAME_OVER
			]
		GameState.CHECK_DUTCH:
			return new_state == GameState.TURN_CONFIRM_DUTCH
		GameState.TURN_CONFIRM_DUTCH:
			return new_state in [GameState.TURN_START_DRAW, GameState.GAME_OVER]
		GameState.GAME_OVER:
			return new_state == GameState.DEAL_CARDS
	return false

func _is_valid_player_index(player_idx: int) -> bool:
	return player_idx >= 0 and player_idx < num_players

func _hand_has_index(player_idx: int, card_idx: int) -> bool:
	if not _is_valid_player_index(player_idx):
		return false
	var hand: Array = players_info[player_idx].hand
	return card_idx >= 0 and card_idx < hand.size()

func can_player_draw(player_idx: int) -> bool:
	return _is_valid_player_index(player_idx) 		and player_idx == current_player_index 		and current_state == GameState.TURN_START_DRAW 		and drawn_card_data == null

func can_player_discard_drawn_card(player_idx: int) -> bool:
	return _is_valid_player_index(player_idx) 		and player_idx == current_player_index 		and current_state == GameState.TURN_RESOLVE_DRAWN 		and drawn_card_data != null

func can_player_swap_drawn_card(player_idx: int, target_player_idx: int, card_idx: int) -> bool:
	return can_player_discard_drawn_card(player_idx) 		and target_player_idx == current_player_index 		and _hand_has_index(target_player_idx, card_idx)

func can_player_start_jump_in(player_idx: int) -> bool:
	if not _is_valid_player_index(player_idx):
		return false
	if deck_manager == null or deck_manager.discard_pile.is_empty():
		return false
	if current_state == GameState.TURN_START_DRAW:
		return true
	if current_state == GameState.TURN_END_CHOICE:
		return player_idx != current_player_index
	return false

func can_player_cancel_jump_in(player_idx: int) -> bool:
	return _is_valid_player_index(player_idx) 		and current_state == GameState.TURN_JUMP_IN_SELECTION 		and jump_in_player_idx == player_idx

func can_player_select_jump_in_card(player_idx: int, owner_idx: int, card_idx: int) -> bool:
	if not can_player_cancel_jump_in(player_idx):
		return false
	if owner_idx != player_idx:
		return false
	if card_idx == -2:
		return drawn_card_data != null and player_idx == current_player_index
	return _hand_has_index(owner_idx, card_idx)

func can_player_complete_peek_ability(player_idx: int) -> bool:
	return _is_valid_player_index(player_idx) and player_idx == current_player_index and current_state == GameState.TURN_PEEK_ABILITY

func can_player_use_peek_ability(player_idx: int, _owner_idx: int, card_is_face_up: bool) -> bool:
	return can_player_complete_peek_ability(player_idx) and not card_is_face_up

func can_player_complete_swap_ability(player_idx: int) -> bool:
	return _is_valid_player_index(player_idx) and player_idx == current_player_index and current_state == GameState.TURN_SWAP_ABILITY

func can_player_select_swap_card(player_idx: int, owner_idx: int, card_idx: int) -> bool:
	return can_player_complete_swap_ability(player_idx) and _hand_has_index(owner_idx, card_idx)

func can_player_end_turn(player_idx: int) -> bool:
	return _is_valid_player_index(player_idx) 		and player_idx == current_player_index 		and current_state == GameState.TURN_END_CHOICE

func can_player_call_dutch(player_idx: int) -> bool:
	return _is_valid_player_index(player_idx) 		and player_idx == current_player_index 		and current_state == GameState.TURN_END_CHOICE 		and dutch_caller_index == -1 		and players_info[player_idx].can_call_dutch

func can_player_confirm_dutch(player_idx: int) -> bool:
	return _is_valid_player_index(player_idx) 		and player_idx == current_player_index 		and current_state == GameState.TURN_CONFIRM_DUTCH

func can_player_cancel_dutch(player_idx: int) -> bool:
	return can_player_confirm_dutch(player_idx)

func should_human_show_jump_in_button(player_idx: int = 0) -> bool:
	return can_player_start_jump_in(player_idx)

func can_human_interact_with_hand_card(owner_idx: int, card_idx: int, card_is_face_up: bool = false) -> bool:
	if not _is_valid_player_index(owner_idx):
		return false
	match current_state:
		GameState.INITIAL_PEEK:
			return owner_idx == 0 and _hand_has_index(0, card_idx)
		GameState.TURN_RESOLVE_DRAWN:
			return can_player_swap_drawn_card(0, owner_idx, card_idx)
		GameState.TURN_JUMP_IN_SELECTION:
			return can_player_select_jump_in_card(0, owner_idx, card_idx)
		GameState.TURN_PEEK_ABILITY:
			return can_player_use_peek_ability(0, owner_idx, card_is_face_up) and _hand_has_index(owner_idx, card_idx)
		GameState.TURN_SWAP_ABILITY:
			return can_player_select_swap_card(0, owner_idx, card_idx)
		_:
			return false

func _consume_jump_in_resume_state() -> GameState:
	var resume_state := jump_in_resume_state
	jump_in_resume_state = GameState.INITIALIZING
	return resume_state

func _resolve_post_interrupt_state() -> GameState:
	var resume_state := _consume_jump_in_resume_state()
	if resume_state != GameState.INITIALIZING:
		return resume_state
	if current_player_index == dutch_caller_index:
		return GameState.TURN_CONFIRM_DUTCH
	return GameState.TURN_END_CHOICE

func next_turn():
	current_player_index = (current_player_index + 1) % num_players
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

func call_dutch(player_id: int):
	if not can_player_call_dutch(player_id):
		print("FSM Blocked: Cannot call Dutch outside of TURN_END_CHOICE state")
		return
	dutch_caller_index = player_id
	print("Player ", player_id, " called DUTCH!")
	dutch_called.emit(player_id)
	next_turn()

func _prompt_turn_end():
	change_state(_resolve_post_interrupt_state())

func end_turn():
	if not can_player_end_turn(current_player_index):
		print("FSM Blocked: Cannot end turn outside of TURN_END_CHOICE state")
		return
	next_turn()

## player_idx: who is jumping in. -1 defaults to current_player_index (bot use).
func start_jump_in(player_idx: int = -1) -> void:
	var resolved_idx := player_idx if player_idx != -1 else current_player_index
	if not can_player_start_jump_in(resolved_idx):
		print("FSM Blocked: Cannot start jump-in from current state")
		return
	jump_in_resume_state = current_state
	jump_in_player_idx = resolved_idx
	change_state(GameState.TURN_JUMP_IN_SELECTION)

func validate_jump_in(card_idx: int) -> bool:
	if current_state != GameState.TURN_JUMP_IN_SELECTION:
		return false
	if not can_player_select_jump_in_card(jump_in_player_idx, jump_in_player_idx, card_idx):
		return false

	var hand: Array = players_info[jump_in_player_idx].hand
	var selected_card: CardData = drawn_card_data if card_idx == -2 else hand[card_idx]
	if selected_card == null or deck_manager.discard_pile.is_empty():
		return false

	var top_discard: CardData = deck_manager.discard_pile[-1]
	if selected_card.rank.to_lower() == top_discard.rank.to_lower():
		var msg := "Player %d: %s of %s matches! JUMP IN!" % [
			jump_in_player_idx, selected_card.rank, selected_card.suit
		]
		if card_idx == -2:
			drawn_card_data = null
		else:
			hand.remove_at(card_idx)
			hand_updated.emit(jump_in_player_idx)
			memory_shift_required.emit(jump_in_player_idx, card_idx)
		
		if hand.size() == 0:
			jump_in_player_idx = -1
			_consume_jump_in_resume_state()
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
		var penalty_card := CardData.new(penalty_card_dict.rank, penalty_card_dict.suit)
		penalty_card.is_face_up = false
		hand.append(penalty_card)
		hand_updated.emit(jump_in_player_idx)
		jump_in_penalty.emit(jump_in_player_idx, penalty_card)

	jump_in_player_idx = -1
	change_state(_resolve_post_interrupt_state())
	return false

func cancel_jump_in() -> void:
	if not can_player_cancel_jump_in(jump_in_player_idx):
		return
	jump_in_player_idx = -1
	change_state(_resolve_post_interrupt_state())

func confirm_dutch():
	if not can_player_confirm_dutch(current_player_index):
		return
	print("Player ", current_player_index, " CONFIRMED Dutch. Game Over.")
	change_state(GameState.GAME_OVER)

func cancel_dutch():
	if not can_player_cancel_dutch(current_player_index):
		return
	print("Player ", current_player_index, " CANCELLED Dutch. Forfeiting right to call again.")
	players_info[current_player_index].can_call_dutch = false
	dutch_caller_index = -1
	change_state(GameState.TURN_START_DRAW)

func player_draw_card():
	if not can_player_draw(current_player_index):
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
	if not can_player_discard_drawn_card(current_player_index):
		print("FSM Blocked: Cannot discard pending card outside of TURN_RESOLVE_DRAWN state")
		return
	
	print("GameManager: Discarding drawn card.")
	deck_manager.discard_pile.append(drawn_card_data)
	card_discarded.emit(current_player_index, drawn_card_data)
	
	var discarded_handled = drawn_card_data
	drawn_card_data = null
	
	_resolve_discard_effects(discarded_handled)

func player_swap_drawn_card(card_idx: int):
	if not can_player_swap_drawn_card(current_player_index, current_player_index, card_idx):
		print("FSM Blocked: Cannot swap outside of TURN_RESOLVE_DRAWN state")
		return
	
	var player_h: Array = players_info[current_player_index].hand
	var old_card = player_h[card_idx]
	print("GameManager: Swapping drawn card with hand card at idx ", card_idx)
	
	deck_manager.discard_pile.append(old_card)
	card_discarded.emit(current_player_index, old_card)
	
	drawn_card_data.is_face_up = false # Must be face-down in hand
	player_h[card_idx] = drawn_card_data
	hand_updated.emit(current_player_index)
	
	drawn_card_data = null
	
	_resolve_discard_effects(old_card)

func _resolve_discard_effects(card: CardData):
	await get_tree().create_timer(0.4, false).timeout
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
	if not _hand_has_index(player1_idx, card1_idx) or not _hand_has_index(player2_idx, card2_idx):
		print("FSM Blocked: Cannot complete swap with invalid card indices")
		return
		
	var h1: Array = players_info[player1_idx].hand
	var h2: Array = players_info[player2_idx].hand
	
	var temp_data = h1[card1_idx]
	h1[card1_idx] = h2[card2_idx]
	h2[card2_idx] = temp_data
	
	hand_updated.emit(player1_idx)
	hand_updated.emit(player2_idx)
	
	jack_swap_resolved.emit(player1_idx, card1_idx, player2_idx, card2_idx)
	_prompt_turn_end()

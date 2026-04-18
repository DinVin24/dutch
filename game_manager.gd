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
	STATE_PLAYING_ABILITY,
	GAME_OVER
}

# Signals
signal game_state_changed(new_state)
signal turn_started(player_id)
signal game_over(winner_id)
signal scores_ready(results: Array) # Bug 3: carries sorted leaderboard
signal all_cards_revealed # Bug 3: tells board to flip all cards face-up
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
signal pending_card_consumed # Notifies board to clear the floating drawn card node

# New Economy Signals
signal player_drank_beer(player_idx, remaining)
signal player_eliminated(player_idx)
signal player_gained_money(player_idx, amount, total)
signal ability_unlocked(player_idx, ability_id)
signal polarity_shifted(new_state: bool)

var current_state: GameState = GameState.INITIALIZING
var deck_manager: DeckManager
var bg_music_player: AudioStreamPlayer
var ability_manager: AbilityManager

# Match Settings
var num_players: int = 4 # Hotseat local play
var players_info: Array = []
var current_player_index: int = 0
var turn_direction: int = 1 # 1 for clockwise, -1 for counter-clockwise (Uno Reverse)
var dutch_caller_index: int = -1 # -1 means no one has called Dutch yet
var jump_in_player_idx: int = -1 # who is currently attempting the jump-in
var drawn_card_data: CardData = null
var jump_in_resume_state: GameState = GameState.INITIALIZING
var dev_console_enabled: bool = true
var active_ability_player: int = -1
var win_condition_lowest_wins: bool = true
var jump_in_was_own_draw_phase: bool = false
var easy_mode: bool = false # Easy Mode: Player 0's cards are always visible

func _ready():
	deck_manager = DeckManager.new()
	add_child(deck_manager)
	
	ability_manager = AbilityManager.new()
	add_child(ability_manager)
	
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
	turn_direction = 1
	dutch_caller_index = -1
	jump_in_player_idx = -1
	win_condition_lowest_wins = true
	jump_in_resume_state = GameState.INITIALIZING
	drawn_card_data = null
	# Note: easy_mode is intentionally NOT reset here — it is set before
	# initialize_game() is called from the difficulty prompt in main_menu.gd.
	for i in range(num_players):
		players_info.append({
			"id": i,
			"name": "Player_" + str(i + 1),
			"score": 0,
			"hand": [], # CardData objects
			"can_call_dutch": true,
			"beers": 3,
			"money": 0,
			"abilities": [],
			"is_eliminated": false,
			"is_skipped": false,
			# bot_memory: { player_idx: { card_idx: CardData } }
			# Populated by BotController during INITIAL_PEEK.
			"bot_memory": {}
		})
	
	# Ensure a fresh deck is ready for the new match
	deck_manager.create_deck()
	deck_ready.emit()
	
	start_game()

func change_state(new_state: GameState, force_signal: bool = false):
	if current_state == new_state and not force_signal:
		# Still emit signal if we are forcing a refresh (e.g. after an interrupt)
		# but avoid redundant work if not needed.
		return
		
	# Transition validation from main
	if not force_signal and not _can_transition_to(new_state):
		push_warning("FSM Blocked: Illegal state transition %s -> %s" % [
			GameState.keys()[current_state],
			GameState.keys()[new_state]
		])
		return

	# Automatic pass-through override from HEAD: never grant an interactive turn 
	# to an eliminated player. Instantly skip to safety.
	if new_state in [GameState.TURN_START_DRAW, GameState.TURN_RESOLVE_DRAWN, GameState.TURN_END_CHOICE, GameState.TURN_CONFIRM_DUTCH]:
		if players_info[current_player_index].is_eliminated:
			print("FSM Guard: Skipping turn state for eliminated player ", current_player_index)
			next_turn()
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
			return new_state in [GameState.TURN_RESOLVE_DRAWN, GameState.TURN_JUMP_IN_SELECTION, GameState.STATE_PLAYING_ABILITY]
		GameState.TURN_RESOLVE_DRAWN:
			return new_state in [
				GameState.TURN_PEEK_ABILITY,
				GameState.TURN_SWAP_ABILITY,
				GameState.TURN_END_CHOICE,
				GameState.TURN_JUMP_IN_SELECTION,
				GameState.TURN_CONFIRM_DUTCH,
				GameState.STATE_PLAYING_ABILITY
			]
		GameState.TURN_PEEK_ABILITY, GameState.TURN_SWAP_ABILITY:
			return new_state in [
				GameState.TURN_START_DRAW,
				GameState.TURN_END_CHOICE,
				GameState.TURN_CONFIRM_DUTCH,
				GameState.STATE_PLAYING_ABILITY
			]
		GameState.TURN_END_CHOICE:
			return new_state in [
				GameState.TURN_START_DRAW,
				GameState.TURN_JUMP_IN_SELECTION,
				GameState.TURN_CONFIRM_DUTCH,
				GameState.STATE_PLAYING_ABILITY
			]
		GameState.TURN_JUMP_IN_SELECTION:
			return new_state in [
				GameState.TURN_START_DRAW,
				GameState.TURN_RESOLVE_DRAWN,
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
	if player_idx == 0:
		if current_state in [
			GameState.INITIALIZING,
			GameState.DEAL_CARDS,
			GameState.INITIAL_PEEK,
			GameState.TURN_JUMP_IN_SELECTION,
			GameState.TURN_PEEK_ABILITY,
			GameState.TURN_SWAP_ABILITY,
			GameState.TURN_CONFIRM_DUTCH,
			GameState.GAME_OVER
		]:
			return false
		if current_state == GameState.TURN_RESOLVE_DRAWN:
			return current_player_index != 0
		return true
	return current_state == GameState.TURN_END_CHOICE and player_idx != current_player_index

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
	# RECENT FIX: Use active_ability_player instead of current_player_index!
	# This allows jump-ins to correctly authorize the player who discarded the Queen.
	return _is_valid_player_index(player_idx) and player_idx == active_ability_player and current_state == GameState.TURN_PEEK_ABILITY

func can_player_use_peek_ability(player_idx: int, _owner_idx: int, card_is_face_up: bool) -> bool:
	return can_player_complete_peek_ability(player_idx) and not card_is_face_up

func can_player_complete_swap_ability(player_idx: int) -> bool:
	# RECENT FIX: Use active_ability_player instead of current_player_index!
	return _is_valid_player_index(player_idx) and player_idx == active_ability_player and current_state == GameState.TURN_SWAP_ABILITY

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
			# FALLBACK: If human can jump-in, their cards should always be interactive
			return owner_idx == 0 and can_player_start_jump_in(0)
func _consume_jump_in_resume_state() -> GameState:
	var resume_state := jump_in_resume_state
	jump_in_resume_state = GameState.INITIALIZING
	return resume_state

func _resolve_post_interrupt_state() -> GameState:
	var resume_state := _consume_jump_in_resume_state()
	if resume_state != GameState.INITIALIZING:
		# FORCE SIGNAL: This is an interrupt completion, we MUST wake up agents
		change_state(resume_state, true)
		return resume_state
	if current_player_index == dutch_caller_index:
		return GameState.TURN_CONFIRM_DUTCH
	return GameState.TURN_END_CHOICE

func next_turn():
	# Loop until we find a player who is not eliminated and not skipped
	for _i in range(num_players):
		current_player_index = (current_player_index + turn_direction + num_players) % num_players
		if not players_info[current_player_index].is_eliminated:
			if players_info[current_player_index].is_skipped:
				players_info[current_player_index].is_skipped = false
				print("Player ", current_player_index, " turn SKIPPED.")
				continue
			break
			
	# Final turn for caller: 
	# Even if current_player_index == dutch_caller_index, we allow them one 
	# final normal turn (draw/jump-in/abilities) before confirming.
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
		
		var total := 0
		if info.is_eliminated:
			# Eliminated players get a massive penalty score and cannot win
			total = 99
		elif hand.size() == 0:
			# Edge case: player with 0 cards wins outright.
			total = -1
		else:
			for card in hand:
						total += (card as CardData).recalc_point_value()
				
		entries.append({"id": i, "name": info.name, "score": total, "card_count": hand.size(), "is_eliminated": info.is_eliminated})
	# Sort entries based on score and win condition
	entries.sort_custom(func(a, b):
		# 0-card winners (-1) always come first
		if a.score == -1: return true
		if b.score == -1: return false
		
		# Eliminated players (99) always come last
		if a.score == 99: return false
		if b.score == 99: return true
		
		# For everyone else, sort based on current win condition polarity
		if a.score != b.score:
			if win_condition_lowest_wins:
				return a.score < b.score
			else:
				return a.score > b.score
				
		# Tiebreak by card count (fewer is always better)
		return a.card_count < b.card_count
	)
	return entries

func _check_elimination_win_condition() -> bool:
	var active_players = 0
	for i in range(num_players):
		if not players_info[i].is_eliminated:
			active_players += 1
	if active_players <= 1:
		print("Only one player remains! Game Over.")
		change_state(GameState.GAME_OVER)
		return true
	return false

func drink_beer(p_idx: int):
	if players_info[p_idx].is_eliminated: return
	players_info[p_idx].beers -= 1
	player_drank_beer.emit(p_idx, players_info[p_idx].beers)
	print("Player ", p_idx, " drank a beer! Remaining: ", players_info[p_idx].beers)
	
	if players_info[p_idx].beers <= 0:
		players_info[p_idx].is_eliminated = true
		player_eliminated.emit(p_idx)
		print("Player ", p_idx, " is ELIMINATED!")
		var was_game_over = _check_elimination_win_condition()
		
		# If the player died during their own active turn, instantly end it
		if not was_game_over and current_player_index == p_idx:
			print("Player died on their turn. Forcing next turn.")
			next_turn()

func gain_money_for_discard(p_idx: int, card: CardData):
	if players_info[p_idx].is_eliminated: return
	var amount = 0
	var r = card.rank
	var s = card.suit
	
	if r == "King":
		if s == "Diamonds": amount = 200
		else: amount = 10
	elif r == "Ace": amount = 100
	elif r == "Queen" or r == "Jack": amount = 80
	elif r == "10" or r == "9": amount = 70
	elif r == "8" or r == "7": amount = 50
	elif r == "6" or r == "5": amount = 40
	else: amount = 30
	
	players_info[p_idx].money += amount
	player_gained_money.emit(p_idx, amount, players_info[p_idx].money)
	print("Player ", p_idx, " gained $", amount, " for discarding ", r, " of ", s)


func start_game():
	change_state(GameState.DEAL_CARDS)

func call_dutch(player_id: int):
	if not can_player_call_dutch(player_id):
		print("FSM Blocked: Cannot call Dutch outside of TURN_END_CHOICE state")
		return
	
	_clear_interrupt_state()
	dutch_caller_index = player_id
	print("Player ", player_id, " called DUTCH!")
	dutch_called.emit(player_id)
	next_turn()

func shift_polarity():
	win_condition_lowest_wins = !win_condition_lowest_wins
	polarity_shifted.emit(win_condition_lowest_wins)
	print("Game Polarity SHIFTED! Lowest wins: ", win_condition_lowest_wins)

func _prompt_turn_end():
	# If player 0 jumped in at the very start of their own draw turn, give them
	# their draw back instead of ending the turn.
	if jump_in_was_own_draw_phase:
		_clear_interrupt_state() # Consumed
		change_state(GameState.TURN_START_DRAW)
		return
		
	var post_interrupt := _resolve_post_interrupt_state()
	change_state(post_interrupt)

func _clear_interrupt_state():
	"""Resets all flags related to jump-in interrupts to ensure state purity."""
	jump_in_resume_state = GameState.INITIALIZING
	jump_in_was_own_draw_phase = false
	jump_in_player_idx = -1
	active_ability_player = -1

## Abilities API
var state_before_ability: GameState = GameState.INITIALIZING
signal ability_played(player_idx, ability_id)
signal ability_finished

func play_ability(player_idx: int, ability_id: String, target_idx: int = -1) -> bool:
	print("[GM DEBUG] play_ability request: P", player_idx, " using ", ability_id, " on T", target_idx, " | State: ", GameState.keys()[current_state])
	
	if current_player_index != player_idx:
		print("[GM DEBUG] REJECTED: Not player's turn (Turn: ", current_player_index, ", Activator: ", player_idx, ")")
		return false
		
	var valid_states = [
		GameState.TURN_START_DRAW,
		GameState.TURN_RESOLVE_DRAWN,
		GameState.TURN_END_CHOICE,
		GameState.TURN_PEEK_ABILITY,
		GameState.TURN_SWAP_ABILITY
	]
	
	if current_state not in valid_states:
		print("[GM DEBUG] REJECTED: Game state ", GameState.keys()[current_state], " prevents playing abilities.")
		return false

	# If this is a primary turn action (not already in an ability state), clear interrupt markers
	if current_state != GameState.STATE_PLAYING_ABILITY:
		_clear_interrupt_state()

	# For targetable abilities, ensure target_idx is provided and valid
	var targeting_abilities = ["bottoms_up", "boulder", "skip", "inflation", "half_off", "shuffle", "jumpscare"]
	if ability_id in targeting_abilities and target_idx == -1:
		print("[GM DEBUG] REJECTED: Ability ", ability_id, " requires a valid target.")
		return false

	state_before_ability = current_state
	change_state(GameState.STATE_PLAYING_ABILITY)
	print("[GM DEBUG] ACCEPTED. State -> PLAYING_ABILITY. Executing manager...")
	
	# Centralized removal from inventory
	var idx = players_info[player_idx].abilities.find(ability_id)
	if idx != -1:
		players_info[player_idx].abilities.remove_at(idx)
	
	ability_played.emit(player_idx, ability_id)
	ability_manager.execute(player_idx, ability_id, target_idx)
	return true
	
func resume_from_ability():
	"""Called by AbilityManager when visual effects and internal logic are complete."""
	if current_state != GameState.STATE_PLAYING_ABILITY:
		return
	# FORCE SIGNAL: Resume from ability must always wake up bots/UI
	change_state(state_before_ability, true)
	ability_finished.emit()

func end_turn():
	if not can_player_end_turn(current_player_index):
		print("FSM Blocked: Cannot end turn outside of TURN_END_CHOICE state")
		return
		
	# If the caller just finished their final turn, prompt for confirmation
	if current_player_index == dutch_caller_index:
		change_state(GameState.TURN_CONFIRM_DUTCH)
	else:
		next_turn()

## player_idx: who is jumping in. -1 defaults to current_player_index (bot use).
func start_jump_in(player_idx: int = -1) -> void:
	var resolved_idx := player_idx if player_idx != -1 else current_player_index
	
	if players_info[resolved_idx].is_eliminated:
		print("FSM Guard: Eliminated player cannot start a jump-in.")
		return
		
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
	# CASE-INSENSITIVE RANK MATCH
	if selected_card.rank.to_lower() == top_discard.rank.to_lower():
		var msg := "Player %d: %s of %s matches! JUMP IN!" % [
			jump_in_player_idx, selected_card.rank, selected_card.suit
		]
		
		# Remove card from source
		if card_idx == -2:
			drawn_card_data = null
		else:
			hand.remove_at(card_idx)
			# NOTE: we DON'T emit hand_updated here because card_discarded 
			# will handle the surgical node removal and subsequent layout refresh.
			memory_shift_required.emit(jump_in_player_idx, card_idx)
		
		# Check for win condition (out of cards)
		if hand.size() == 0:
			jump_in_player_idx = -1
			_consume_jump_in_resume_state()
			change_state(GameState.GAME_OVER)
			return true
			
		# Successfully jumped in
		print("[GM DEBUG] JUMP-IN MATCH! Removing card at idx ", card_idx, " from P", jump_in_player_idx, " hand.")
		deck_manager.discard_pile.append(selected_card)
		
		var p_idx_for_signal = jump_in_player_idx
		card_discarded.emit(p_idx_for_signal, selected_card)
		gain_money_for_discard(p_idx_for_signal, selected_card)
		
		var played_by = p_idx_for_signal
		jump_in_player_idx = -1
		
		_resolve_discard_effects(selected_card, played_by)
		bot_action.emit(msg)
		return true

	# NO MATCH: Penalty
	print("No match. Jump In invalid.")
	jump_in_failed.emit(jump_in_player_idx, card_idx, selected_card)
	drink_beer(jump_in_player_idx)
	
	if players_info[jump_in_player_idx].is_eliminated:
		jump_in_player_idx = -1
		return false
		
	await get_tree().create_timer(1.2, false).timeout

	var p_card = deck_manager.draw_card()
	if p_card != null:
		p_card.is_face_up = false
		hand.append(p_card)
		hand_updated.emit(jump_in_player_idx)
		jump_in_penalty.emit(jump_in_player_idx, p_card)

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
	
	_clear_interrupt_state()
	
	var card_info = deck_manager.draw_card()
	if card_info == null:
		print("Deck is empty!")
		return
		
	drawn_card_data = card_info
	drawn_card_data.is_face_up = true
	
	change_state(GameState.TURN_RESOLVE_DRAWN)
	print("GameManager: [DRAW SUCCESS] Player ", current_player_index, " state moved to RESOLVE.")
	card_drawn_to_pending.emit(current_player_index, drawn_card_data)

func player_discard_drawn_card():
	if not can_player_discard_drawn_card(current_player_index):
		print("FSM Blocked: Cannot discard pending card outside of TURN_RESOLVE_DRAWN state")
		return
	
	_clear_interrupt_state()
	
	print("GameManager: Discarding drawn card.")
	deck_manager.discard_pile.append(drawn_card_data)
	card_discarded.emit(current_player_index, drawn_card_data)
	gain_money_for_discard(current_player_index, drawn_card_data)
	
	var p_idx = current_player_index
	drink_beer(p_idx)
	
	if players_info[p_idx].is_eliminated:
		drawn_card_data = null
		return
	
	var discarded_handled = drawn_card_data
	drawn_card_data = null
	pending_card_consumed.emit()
	
	_resolve_discard_effects(discarded_handled)

func player_swap_drawn_card(card_idx: int):
	if not can_player_swap_drawn_card(current_player_index, current_player_index, card_idx):
		print("FSM Blocked: Cannot swap outside of TURN_RESOLVE_DRAWN state")
		return
	
	_clear_interrupt_state()
	
	var player_h: Array = players_info[current_player_index].hand
	var old_card = player_h[card_idx]
	print("GameManager: Swapping drawn card with hand card at idx ", card_idx)
	
	deck_manager.discard_pile.append(old_card)
	card_discarded.emit(current_player_index, old_card)
	gain_money_for_discard(current_player_index, old_card)
	
	drawn_card_data.is_face_up = false # Must be face-down in hand
	player_h[card_idx] = drawn_card_data
	hand_updated.emit(current_player_index)
	
	drawn_card_data = null
	pending_card_consumed.emit()
	
	_resolve_discard_effects(old_card)

func _resolve_discard_effects(card: CardData, player_idx: int = -1):
	active_ability_player = player_idx if player_idx != -1 else current_player_index
	
	# Wait for the card discard visual tween to complete before changing state
	await get_tree().create_timer(0.4, false).timeout
	if current_state == GameState.GAME_OVER: return
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
	# SECURITY FIX: only Player 0 (human) or the system (after a global timer) 
	# should be able to end the initial peek phase.
	# For now, we assume this is called by the human board.
	change_state(GameState.TURN_START_DRAW)
	print("[FSM] INITIAL_PEEK -> TURN_START_DRAW")

func complete_peek_ability():
	if current_state != GameState.TURN_PEEK_ABILITY:
		print("FSM Blocked: Cannot complete peek outside of TURN_PEEK_ABILITY state")
		return
	_prompt_turn_end()

func complete_swap_ability(player1_idx: int, card1_idx: int, player2_idx: int, card2_idx: int):
	if current_state != GameState.TURN_SWAP_ABILITY:
		print("FSM Blocked: Cannot complete swap outside of TURN_SWAP_ABILITY state")
		return
	if player1_idx == -1 and card1_idx == -1 and player2_idx == -1 and card2_idx == -1:
		_prompt_turn_end()
		return
	if not _hand_has_index(player1_idx, card1_idx) or not _hand_has_index(player2_idx, card2_idx):
		print("FSM Blocked: Cannot complete swap with invalid card indices")
		return
		
	var h1: Array = players_info[player1_idx].hand
	var h2: Array = players_info[player2_idx].hand
	
	var temp_data = h1[card1_idx]
	h1[card1_idx] = h2[card2_idx]
	h2[card2_idx] = temp_data
	
	# SECURITY/UX FIX: Always reset face-up state after a swap.
	# In easy mode, P0's cards are always up, so if they swap with an enemy,
	# we must ensure the enemy doesn't get a face-up card.
	h1[card1_idx].is_face_up = false
	h2[card2_idx].is_face_up = false
	
	hand_updated.emit(player1_idx)
	hand_updated.emit(player2_idx)
	
	jack_swap_resolved.emit(player1_idx, card1_idx, player2_idx, card2_idx)
	_prompt_turn_end()

func buy_ability(p_idx: int) -> bool:
	"""Centralized purchase logic for both Human UI and Bot Controller."""
	var cost = 50
	
	# Hard cap: Max 8 abilities
	if players_info[p_idx].abilities.size() >= 8:
		print("GM: Player ", p_idx, " is at max capacity (8 abilities).")
		return false
		
	if players_info[p_idx].money >= cost:
		players_info[p_idx].money -= cost
		player_gained_money.emit(p_idx, -cost, players_info[p_idx].money)
		
		# Generate random ability
		var list = ["bottoms_up", "refuel", "trim_off", "boulder", "reverse", "skip", "perfect_match", "inflation", "half_off", "jumpscare", "shuffle", "polarity_shift"]
		var ab = list[randi() % list.size()]
		players_info[p_idx].abilities.append(ab)
		ability_unlocked.emit(p_idx, ab)
		print("GM: Player ", p_idx, " bought ability: ", ab)
		return true
	return false

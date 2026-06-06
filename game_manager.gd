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
signal player_emoted(player_idx: int, emote_id: String)
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
signal multiplayer_sync_applied
signal mp_connection_status_changed(lag_ms: int, status: String)

const EMOTE_IDS: Array[String] = ["laugh", "shock", "gg", "chicken"]
const EMOTE_COOLDOWN_SEC := 4.0

var current_state: GameState = GameState.INITIALIZING
var deck_manager: DeckManager
var menu_music_p1: AudioStreamPlayer
var menu_music_p2: AudioStreamPlayer
var current_menu_player: AudioStreamPlayer
var next_menu_player: AudioStreamPlayer
var is_menu_music_active: bool = false

var game_music_p1: AudioStreamPlayer
var game_music_p2: AudioStreamPlayer
var current_game_player: AudioStreamPlayer
var next_game_player: AudioStreamPlayer
var is_game_music_active: bool = false

# Audio Streams
var sfx_card_flip = preload("res://assets/sfx/card_flip.mp3")
var sfx_beer_drink = preload("res://assets/sfx/beer_drink.mp3")
var sfx_chicken = preload("res://assets/sfx/chicken.mp3")

var ability_manager: AbilityManager

# Match Settings
var num_players: int = 4 # Hotseat local play
var players_info: Array = []
var current_player_index: int = 0

# Multiplayer tracking
var is_multiplayer: bool = false
var local_player_idx: int = 0
var peer_to_idx: Dictionary = {}
var idx_to_peer: Dictionary = {}
var pending_mp_player_count: int = 0
var pending_match_seed: int = -1
var _mp_initial_peek_done: Dictionary = {}
var _mp_sync_seq: int = 0
var _mp_last_applied_sync_seq: int = -1
var _mp_game_over_scores_applied: bool = false
var _mp_sync_prev_cur: int = -1
var _emote_cooldown_until: Dictionary = {}
var mp_sync_lag_ms: int = 0
var mp_connection_status: String = "ok"
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
var tutorial_mode: bool = false # Tutorial Mode: TutorialOverlay is instantiated on the board
var global_ability_counts: Dictionary = {
	"perfect_match": 0,
	"polarity_shift": 0
}
var last_ability_event: Dictionary = {}
var last_debug_event: String = ""
var jump_in_validating: bool = false

const DEBUG_LOG_PATH := "user://game_debug.log"

func debug_log(category: String, message: String) -> void:
	var line := "[%s] [%s] %s" % [Time.get_datetime_string_from_system(), category, message]
	last_debug_event = "%s: %s" % [category, message]
	var file := FileAccess.open(DEBUG_LOG_PATH, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(DEBUG_LOG_PATH, FileAccess.WRITE)
	if file:
		file.seek_end()
		file.store_line(line)
		file.close()

func _ready():
	deck_manager = DeckManager.new()
	add_child(deck_manager)
	
	ability_manager = AbilityManager.new()
	add_child(ability_manager)
	
	NetworkManager.player_disconnected.connect(_on_peer_disconnected)
	
	# Background Music Setup (Dual Players for Seamless Loop)
	menu_music_p1 = AudioStreamPlayer.new()
	menu_music_p2 = AudioStreamPlayer.new()
	
	var menu_stream = preload("res://assets/music/main_menu.mp3")
	menu_music_p1.stream = menu_stream
	menu_music_p2.stream = menu_stream
	
	for p in [menu_music_p1, menu_music_p2]:
		p.volume_db = 0.0
		p.bus = "Music"
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(p)
	
	current_menu_player = menu_music_p1
	next_menu_player = menu_music_p2
	
	# Game Music Setup
	game_music_p1 = AudioStreamPlayer.new()
	game_music_p2 = AudioStreamPlayer.new()
	
	var game_stream = preload("res://assets/music/game_music.wav")
	game_music_p1.stream = game_stream
	game_music_p2.stream = game_stream
	
	for p in [game_music_p1, game_music_p2]:
		p.volume_db = 0.0
		p.bus = "Music"
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(p)
		
	current_game_player = game_music_p1
	next_game_player = game_music_p2

func _process(_delta: float) -> void:
	if is_menu_music_active and current_menu_player.playing:
		var pos = current_menu_player.get_playback_position()
		var length = current_menu_player.stream.get_length()
		
		# Trigger crossfade 2 seconds before the end
		if pos > length - 2.0 and not next_menu_player.playing:
			_start_menu_music_crossfade()
			
	if is_game_music_active and current_game_player.playing:
		var pos = current_game_player.get_playback_position()
		var length = current_game_player.stream.get_length()
		
		if pos > length - 2.0 and not next_game_player.playing:
			_start_game_music_crossfade()

func _start_menu_music_crossfade() -> void:
	next_menu_player.play()
	var tween = create_tween().set_parallel(true)
	tween.tween_property(current_menu_player, "volume_db", -80.0, 2.0)
	tween.tween_property(next_menu_player, "volume_db", 0.0, 2.0)
	
	# Swap roles
	var temp = current_menu_player
	current_menu_player = next_menu_player
	next_menu_player = temp

func play_menu_music() -> void:
	stop_game_music()
	is_menu_music_active = true
	if not current_menu_player.playing:
		current_menu_player.volume_db = 0.0
		current_menu_player.play()

func stop_menu_music() -> void:
	is_menu_music_active = false
	if menu_music_p1.playing: menu_music_p1.stop()
	if menu_music_p2.playing: menu_music_p2.stop()

func play_game_music() -> void:
	# Use the main-menu track in-game (game_music.wav is disabled)
	if is_menu_music_active:
		return # Already playing
	play_menu_music()

func stop_game_music() -> void:
	is_game_music_active = false
	if game_music_p1.playing: game_music_p1.stop()
	if game_music_p2.playing: game_music_p2.stop()

func stop_all_music() -> void:
	stop_menu_music()
	stop_game_music()

func play_sfx(stream: AudioStream) -> void:
	if not stream: return
	var p = AudioStreamPlayer.new()
	p.stream = stream
	p.bus = "SFX"
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)

func _start_game_music_crossfade() -> void:
	next_game_player.play()
	var tween = create_tween().set_parallel(true)
	tween.tween_property(current_game_player, "volume_db", -80.0, 2.0)
	tween.tween_property(next_game_player, "volume_db", 0.0, 2.0)
	
	# Swap roles
	var temp = current_game_player
	current_game_player = next_game_player
	next_game_player = temp

func initialize_game(p_count: int = 4):
	var count: int = p_count
	if pending_mp_player_count >= 2:
		count = pending_mp_player_count
	pending_mp_player_count = 0
	num_players = count
	peer_to_idx.clear()
	idx_to_peer.clear()
	_mp_initial_peek_done.clear()
	_mp_sync_seq = 0
	_mp_last_applied_sync_seq = -1
	_mp_game_over_scores_applied = false
	_mp_sync_prev_cur = -1
	_emote_cooldown_until.clear()
	mp_sync_lag_ms = 0
	mp_connection_status = "ok"
	players_info.clear()
	current_state = GameState.INITIALIZING
	current_player_index = 0
	turn_direction = 1
	dutch_caller_index = -1
	jump_in_player_idx = -1
	win_condition_lowest_wins = true
	global_ability_counts = {
		"perfect_match": 0,
		"polarity_shift": 0
	}
	jump_in_resume_state = GameState.INITIALIZING
	drawn_card_data = null
	jump_in_validating = false
	last_debug_event = ""
	is_multiplayer = multiplayer.multiplayer_peer != null \
		and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer) \
		and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
	var log_file := FileAccess.open(DEBUG_LOG_PATH, FileAccess.WRITE)
	if log_file:
		log_file.store_line("[%s] [init] New match (%d players, mp=%s)" % [
			Time.get_datetime_string_from_system(), count, str(is_multiplayer)
		])
		log_file.close()
	
	var networked_players = []
	if is_multiplayer:
		# Copy the dictionary values and sort by ID to ensure deterministic ordering
		var keys = NetworkManager.players.keys()
		keys.sort()
		for k in keys:
			networked_players.append({"peer_id": k, "info": NetworkManager.players[k]})
		
		# Set settings
		easy_mode = NetworkManager.match_settings["cards_visibility"] == 1
		tutorial_mode = false # Disallow tutorial in multiplayer
		
	# Note: easy_mode and tutorial_mode are intentionally NOT reset here — they are set
	# before initialize_game() is called from the difficulty prompt in main_menu.gd.
	for i in range(num_players):
		var p_name = "Player_" + str(i + 1)
		var is_bot = true
		
		if is_multiplayer:
			if i < networked_players.size():
				var p_data = networked_players[i]
				p_name = p_data["info"]["name"]
				is_bot = false
				peer_to_idx[p_data["peer_id"]] = i
				idx_to_peer[i] = p_data["peer_id"]
				if p_data["peer_id"] == multiplayer.get_unique_id():
					local_player_idx = i
			else:
				p_name = "BOT_%d" % (i + 1)
		else:
			if i == 0:
				is_bot = false
			
		players_info.append({
			"id": i,
			"name": p_name,
			"score": 0,
			"hand": [], # CardData objects
			"can_call_dutch": true,
			"beers": NetworkManager.match_settings["beers"] if is_multiplayer else 3,
			"money": 0,
			"abilities": ["", "", "", "", "", ""],
			"is_eliminated": false,
			"is_skipped": false,
			"is_bot": is_bot,
			"bot_memory": {}
		})
	
	# Ensure a fresh deck is ready for the new match
	deck_manager.create_deck()
	var use_seed: int = pending_match_seed
	pending_match_seed = -1
	if use_seed >= 0:
		deck_manager.shuffle_deck_seeded(use_seed)
	else:
		deck_manager.shuffle_deck()
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
			
	var prev_name: String = GameState.keys()[current_state]
	current_state = new_state
	debug_log("state", "%s -> %s%s" % [
		prev_name,
		GameState.keys()[new_state],
		" (forced)" if force_signal else ""
	])
	game_state_changed.emit(new_state)
	
	match current_state:
		GameState.DEAL_CARDS:
			_handle_deal_cards()
		GameState.TURN_START_DRAW:
			debug_log("turn", "start P%d" % current_player_index)
			turn_started.emit(current_player_index)
		GameState.GAME_OVER:
			_handle_game_over()
	_mp_broadcast_state_if_server()

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
		GameState.STATE_PLAYING_ABILITY:
			return new_state in [
				GameState.TURN_START_DRAW,
				GameState.TURN_RESOLVE_DRAWN,
				GameState.TURN_END_CHOICE,
				GameState.TURN_PEEK_ABILITY,
				GameState.TURN_SWAP_ABILITY,
				GameState.TURN_CONFIRM_DUTCH,
				GameState.INITIAL_PEEK,
				GameState.GAME_OVER
			]
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
	if not players_info[player_idx].is_bot:
		if current_state in [
			GameState.INITIALIZING,
			GameState.DEAL_CARDS,
			GameState.INITIAL_PEEK,
			GameState.TURN_JUMP_IN_SELECTION,
			GameState.TURN_PEEK_ABILITY,
			GameState.TURN_SWAP_ABILITY,
			GameState.GAME_OVER
		]:
			return false
		if current_state == GameState.TURN_RESOLVE_DRAWN:
			return current_player_index != player_idx
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
	var human_idx: int = local_player_idx if is_multiplayer else 0
	match current_state:
		GameState.INITIAL_PEEK:
			return owner_idx == human_idx and _hand_has_index(human_idx, card_idx)
		GameState.TURN_RESOLVE_DRAWN:
			return can_player_swap_drawn_card(human_idx, owner_idx, card_idx)
		GameState.TURN_JUMP_IN_SELECTION:
			return can_player_select_jump_in_card(human_idx, owner_idx, card_idx)
		GameState.TURN_PEEK_ABILITY:
			return can_player_use_peek_ability(human_idx, owner_idx, card_is_face_up) and _hand_has_index(owner_idx, card_idx)
		GameState.TURN_SWAP_ABILITY:
			return can_player_select_swap_card(human_idx, owner_idx, card_idx)
		_:
			# FALLBACK: If human can jump-in, their cards should always be interactive
			return owner_idx == human_idx and can_player_start_jump_in(human_idx)
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

func _on_deck_reshuffled():
	pass

# --- Multiplayer RPCs ---

@rpc("any_peer", "call_local", "reliable")
func request_action(action: String, args: Dictionary = {}):
	var player_idx = 0 # Default to 0 for local
	
	if is_multiplayer:
		if not multiplayer.is_server():
			return # Only the server processes requests
		var sender_id = multiplayer.get_remote_sender_id()
		if sender_id == 0:
			sender_id = multiplayer.get_unique_id()
		player_idx = peer_to_idx.get(sender_id, -1)
		
	if player_idx == -1 and action != "start_jump_in" and action != "validate_jump_in":
		return
		
	print("GameManager: Received request ", action, " from player ", player_idx)
	
	match action:
		"draw_card":
			if current_player_index == player_idx:
				player_draw_card()
		"discard_drawn":
			if current_player_index == player_idx:
				player_discard_drawn_card()
		"swap_drawn":
			if current_player_index == player_idx:
				player_swap_drawn_card(args.get("card_idx"))
		"start_jump_in":
			start_jump_in(player_idx)
		"cancel_jump_in":
			if jump_in_player_idx == player_idx:
				cancel_jump_in()
		"validate_jump_in":
			if jump_in_player_idx == player_idx:
				validate_jump_in(args.get("card_idx"))
		"end_turn":
			if current_player_index == player_idx:
				end_turn()
		"call_dutch":
			if current_player_index == player_idx:
				call_dutch(player_idx)
		"confirm_dutch":
			if current_player_index == player_idx:
				confirm_dutch()
		"cancel_dutch":
			if current_player_index == player_idx:
				cancel_dutch()
		"play_ability":
			play_ability(
				player_idx,
				args.get("ability_id"),
				args.get("target_idx", -1),
				args.get("slot_idx", -1)
			)
		"buy_ability":
			buy_ability(player_idx)
		"initial_peek_done":
			report_mp_initial_peek_done(player_idx)
		"drink_beer":
			drink_beer(player_idx)
		"complete_peek_ability":
			if active_ability_player == player_idx:
				complete_peek_ability()
		"complete_swap_ability":
			if active_ability_player == player_idx:
				complete_swap_ability(args.get("p1"), args.get("c1"), args.get("p2"), args.get("c2"))

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
	change_state(GameState.TURN_START_DRAW, true)

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

func _on_peer_disconnected(peer_id: int) -> void:
	if not is_multiplayer or not multiplayer.is_server():
		return
	if players_info.is_empty() or current_state == GameState.GAME_OVER:
		return
	var player_idx: int = int(peer_to_idx.get(peer_id, -1))
	if player_idx == -1:
		return
	peer_to_idx.erase(peer_id)
	idx_to_peer.erase(player_idx)
	if not _is_valid_player_index(player_idx):
		return
	if not players_info[player_idx].is_eliminated:
		players_info[player_idx].is_eliminated = true
		players_info[player_idx].is_bot = true
		debug_log("disconnect", "P%d (peer %d) rage-quit → eliminated" % [player_idx, peer_id])
		player_eliminated.emit(player_idx)

	# Count remaining active players — elimination can occur from any FSM state so
	# we force the GAME_OVER transition rather than relying on _check_elimination_win_condition
	# which uses the FSM validation table (TURN_RESOLVE_DRAWN → GAME_OVER is not listed).
	var active_count := 0
	for i in range(num_players):
		if not players_info[i].is_eliminated:
			active_count += 1
	var game_ended := active_count <= 1

	# Always clear a pending drawn card when the seat that drew it is vacated
	if current_player_index == player_idx and drawn_card_data != null:
		drawn_card_data = null
		pending_card_consumed.emit()

	if game_ended:
		print("Only one player remains after disconnect. Game Over.")
		change_state(GameState.GAME_OVER, true)
		_mp_broadcast_state_if_server()
		return

	if current_player_index == player_idx:
		if jump_in_player_idx == player_idx:
			jump_in_player_idx = -1
			jump_in_validating = false
		next_turn()
	elif jump_in_player_idx == player_idx:
		jump_in_player_idx = -1
		jump_in_validating = false
		change_state(_resolve_post_interrupt_state())
	_mp_broadcast_state_if_server()

func drink_beer(p_idx: int):
	if players_info[p_idx].is_eliminated: return
	players_info[p_idx].beers -= 1
	play_sfx(sfx_beer_drink)
	player_drank_beer.emit(p_idx, players_info[p_idx].beers)
	print("Player ", p_idx, " drank a beer! Remaining: ", players_info[p_idx].beers)
	
	if players_info[p_idx].beers <= 0:
		players_info[p_idx].is_eliminated = true
		player_eliminated.emit(p_idx)
		debug_log("eliminate", "P%d passed out (beers=0)" % p_idx)
		print("Player ", p_idx, " is ELIMINATED!")
		if not is_multiplayer and p_idx == 0:
			change_state(GameState.GAME_OVER)
			return
		var was_game_over = _check_elimination_win_condition()
		
		# If the player died during their own active turn, instantly end it
		if not was_game_over and current_player_index == p_idx:
			print("Player died on their turn. Forcing next turn.")
			next_turn()

func get_discard_money_amount(card: CardData) -> int:
	var r: String = card.rank
	var s: String = card.suit
	if r == "King":
		return 200 if s == "Diamonds" else 10
	if r == "Ace":
		return 100
	if r == "Queen" or r == "Jack":
		return 80
	if r == "10" or r == "9":
		return 70
	if r == "8" or r == "7":
		return 50
	if r == "6" or r == "5":
		return 40
	return 30

func gain_money_for_discard(p_idx: int, card: CardData):
	if players_info[p_idx].is_eliminated: return
	var amount := get_discard_money_amount(card)
	players_info[p_idx].money += amount
	player_gained_money.emit(p_idx, amount, players_info[p_idx].money)
	print("Player ", p_idx, " gained $", amount, " for discarding ", card.rank, " of ", card.suit)


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
var active_player_before_ability: int = -1
signal ability_played(player_idx, ability_id, target_idx)
signal ability_finished

func play_ability(player_idx: int, ability_id: String, target_idx: int = -1, slot_idx: int = -1) -> bool:
	print("[GM DEBUG] play_ability request: P", player_idx, " using ", ability_id, " on T", target_idx, " from slot ", slot_idx, " | State: ", GameState.keys()[current_state])
	
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

	# Preserve Queen/Jack interrupt context so cabinet abilities do not strand the FSM.
	var preserve_interrupt := current_state in [
		GameState.TURN_PEEK_ABILITY,
		GameState.TURN_SWAP_ABILITY
	]
	active_player_before_ability = active_ability_player if preserve_interrupt else -1
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
	
	# Centralized removal from inventory by slot index or first occurrence
	var idx = slot_idx
	if idx < 0 or idx >= players_info[player_idx].abilities.size() or players_info[player_idx].abilities[idx] != ability_id:
		idx = players_info[player_idx].abilities.find(ability_id)
		
	if idx != -1:
		players_info[player_idx].abilities[idx] = ""
	
	last_ability_event = {"caster": player_idx, "id": ability_id, "target": target_idx}
	debug_log("ability", "play P%d %s -> T%d" % [player_idx, ability_id, target_idx])
	ability_played.emit(player_idx, ability_id, target_idx)
	ability_manager.execute(player_idx, ability_id, target_idx)
	return true
	
func resume_from_ability():
	"""Called by AbilityManager when visual effects and internal logic are complete."""
	if current_state != GameState.STATE_PLAYING_ABILITY:
		return
	# FORCE SIGNAL: Resume from ability must always wake up bots/UI
	change_state(state_before_ability, true)
	if state_before_ability in [GameState.TURN_PEEK_ABILITY, GameState.TURN_SWAP_ABILITY] \
			and active_player_before_ability != -1:
		active_ability_player = active_player_before_ability
	active_player_before_ability = -1
	debug_log("ability", "finished (resume %s)" % GameState.keys()[state_before_ability])
	ability_finished.emit()

func end_turn():
	if not can_player_end_turn(current_player_index):
		print("FSM Blocked: Cannot end turn outside of TURN_END_CHOICE state")
		return
	debug_log("turn", "end P%d" % current_player_index)
		
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
		
	if not can_player_start_jump_in(resolved_idx):
		return
		
	# Track if player is jumping in at the start of their own draw turn.
	if current_player_index == resolved_idx and current_state == GameState.TURN_START_DRAW:
		jump_in_was_own_draw_phase = true
	else:
		jump_in_was_own_draw_phase = false

	if current_state != GameState.TURN_JUMP_IN_SELECTION:
		jump_in_resume_state = current_state
	jump_in_player_idx = resolved_idx
	debug_log("jump_in", "start P%d (resume=%s)" % [resolved_idx, GameState.keys()[jump_in_resume_state]])
	change_state(GameState.TURN_JUMP_IN_SELECTION)

func validate_jump_in(card_idx: int) -> bool:
	if current_state != GameState.TURN_JUMP_IN_SELECTION:
		return false
	if jump_in_validating:
		return false
	if not can_player_select_jump_in_card(jump_in_player_idx, jump_in_player_idx, card_idx):
		return false
	jump_in_validating = true

	var hand: Array = players_info[jump_in_player_idx].hand
	var selected_card: CardData = drawn_card_data if card_idx == -2 else hand[card_idx]
	if selected_card == null or deck_manager.discard_pile.is_empty():
		jump_in_validating = false
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
		var winning_player := jump_in_player_idx
		if hand.size() == 0:
			jump_in_player_idx = -1
			jump_in_validating = false
			_consume_jump_in_resume_state()
			debug_log("jump_in", "P%d win — out of cards" % winning_player)
			change_state(GameState.GAME_OVER)
			return true
			
		# Successfully jumped in
		print("[GM DEBUG] JUMP-IN MATCH! Removing card at idx ", card_idx, " from P", jump_in_player_idx, " hand.")
		deck_manager.discard_pile.append(selected_card)
		
		var p_idx_for_signal = jump_in_player_idx
		card_discarded.emit(p_idx_for_signal, selected_card)
		gain_money_for_discard(p_idx_for_signal, selected_card)
		_mp_broadcast_state_if_server()
		
		var played_by = p_idx_for_signal
		jump_in_player_idx = -1
		jump_in_validating = false
		debug_log("jump_in", "P%d success (card idx %d)" % [played_by, card_idx])
		change_state(_resolve_post_interrupt_state())
		_resolve_discard_effects(selected_card, played_by)
		bot_action.emit(msg)
		return true

	# NO MATCH: Penalty
	print("No match. Jump In invalid.")
	var failed_player := jump_in_player_idx
	debug_log("jump_in", "P%d fail (card idx %d)" % [failed_player, card_idx])
	jump_in_failed.emit(failed_player, card_idx, selected_card)
	drink_beer(failed_player)
	_mp_broadcast_state_if_server()
	
	jump_in_player_idx = -1
	jump_in_validating = false
	if current_state == GameState.GAME_OVER:
		return false
	change_state(_resolve_post_interrupt_state())
	
	if players_info[failed_player].is_eliminated:
		return false
		
	await get_tree().create_timer(1.2, false).timeout

	var p_card = deck_manager.draw_card()
	if p_card != null:
		p_card.is_face_up = false
		hand.append(p_card)
		hand_updated.emit(failed_player)
		jump_in_penalty.emit(failed_player, p_card)
		_mp_broadcast_state_if_server()
		debug_log("jump_in", "P%d penalty card dealt" % failed_player)

	return false

func cancel_jump_in() -> void:
	if not can_player_cancel_jump_in(jump_in_player_idx):
		return
	debug_log("jump_in", "P%d cancelled" % jump_in_player_idx)
	jump_in_player_idx = -1
	jump_in_validating = false
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
	_mp_broadcast_state_if_server()
	
	var p_idx = current_player_index
	drink_beer(p_idx)
	
	if players_info[p_idx].is_eliminated:
		drawn_card_data = null
		return
	
	var discarded_handled = drawn_card_data
	drawn_card_data = null
	pending_card_consumed.emit()
	_mp_broadcast_state_if_server()
	
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
	_mp_broadcast_state_if_server()
	
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
	if is_multiplayer and not multiplayer.is_server():
		return
	change_state(GameState.TURN_START_DRAW)
	print("[FSM] INITIAL_PEEK -> TURN_START_DRAW")

func report_mp_initial_peek_done(player_idx: int) -> void:
	if not is_multiplayer or not multiplayer.is_server():
		return
	if current_state != GameState.INITIAL_PEEK:
		return
	if not _is_valid_player_index(player_idx) or players_info[player_idx].is_bot:
		return
	_mp_initial_peek_done[player_idx] = true
	for i in range(num_players):
		if players_info[i].is_bot:
			continue
		if not _mp_initial_peek_done.get(i, false):
			return
	_mp_initial_peek_done.clear()
	change_state(GameState.TURN_START_DRAW)
	print("[FSM] INITIAL_PEEK -> TURN_START_DRAW (all humans ready)")

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
	
	# Hard cap: Max 6 active abilities
	var active_count = 0
	for ab_name in players_info[p_idx].abilities:
		if ab_name != "":
			active_count += 1
	if active_count >= 6:
		print("GM: Player ", p_idx, " is at max capacity (6 active abilities).")
		return false
		
	if players_info[p_idx].money >= cost:
		players_info[p_idx].money -= cost
		player_gained_money.emit(p_idx, -cost, players_info[p_idx].money)
		
		# Generate random ability
		var list = ["bottoms_up", "refuel", "trim_off", "boulder", "reverse", "skip", "perfect_match", "inflation", "half_off", "jumpscare", "shuffle", "polarity_shift"]
		
		# Filter limited abilities (Epic 16 feedback: Polarity Shift and Perfect Match are game-breaking)
		if global_ability_counts["perfect_match"] >= 2:
			list.erase("perfect_match")
		if global_ability_counts["polarity_shift"] >= 2:
			list.erase("polarity_shift")
			
		var ab = list[randi() % list.size()]
		
		# Update global counts for limited abilities
		if ab in global_ability_counts:
			global_ability_counts[ab] += 1
			
		# Find the first empty slot to place the ability
		var empty_slot = players_info[p_idx].abilities.find("")
		if empty_slot != -1:
			players_info[p_idx].abilities[empty_slot] = ab
		else:
			players_info[p_idx].abilities.append(ab)
			
		play_sfx(sfx_chicken)
		ability_unlocked.emit(p_idx, ab)
		print("GM: Player ", p_idx, " bought ability: ", ab, " (Limit Tracking: ", global_ability_counts, ")")
		_mp_broadcast_state_if_server()
		return true
	return false

func _card_to_dict(c: CardData) -> Dictionary:
	return {
		"r": c.rank,
		"s": c.suit,
		"u": c.is_face_up,
		"pm": c.point_modifier
	}

func _hand_card_to_public_dict(c: CardData) -> Dictionary:
	var d := _card_to_dict(c)
	# Multiplayer privacy: hand cards are private knowledge and must never replicate as face-up.
	d["u"] = false
	return d

func _dict_to_card(d: Dictionary) -> CardData:
	var c := CardData.new(str(d.get("r", "Ace")), str(d.get("s", "Clubs")))
	c.is_face_up = bool(d.get("u", false))
	c.point_modifier = float(d.get("pm", 1.0))
	c.recalc_point_value()
	return c

func _mp_broadcast_state_if_server() -> void:
	if not is_multiplayer:
		return
	if multiplayer.multiplayer_peer == null:
		return
	if not multiplayer.is_server():
		return
	if players_info.is_empty():
		return
	_mp_sync_seq += 1
	sync_match_state.rpc(_build_mp_sync_payload())

func _build_mp_sync_payload() -> Dictionary:
	var players_arr: Array = []
	for i in range(num_players):
		var p: Dictionary = players_info[i]
		var hand_arr: Array = []
		for c in p["hand"]:
			if c is CardData:
				hand_arr.append(_hand_card_to_public_dict(c))
		players_arr.append({
			"name": p["name"],
			"is_bot": p["is_bot"],
			"beers": p["beers"],
			"money": p["money"],
			"is_eliminated": p["is_eliminated"],
			"is_skipped": p["is_skipped"],
			"can_call_dutch": p["can_call_dutch"],
			"abilities": p["abilities"].duplicate(),
			"hand": hand_arr
		})
	var deck_arr: Array = []
	for c in deck_manager.deck:
		if c is CardData:
			deck_arr.append(_card_to_dict(c))
	var disc_arr: Array = []
	for c in deck_manager.discard_pile:
		if c is CardData:
			disc_arr.append(_card_to_dict(c))
	var peer_pairs: Array = []
	for k in peer_to_idx.keys():
		peer_pairs.append([int(k), int(peer_to_idx[k])])
	var drawn_d: Variant = null
	if drawn_card_data != null:
		drawn_d = _card_to_dict(drawn_card_data)
	var payload := {
		"v": 1,
		"seq": _mp_sync_seq,
		"ts": Time.get_ticks_msec(),
		"state": int(current_state),
		"cur": current_player_index,
		"td": turn_direction,
		"dutch_i": dutch_caller_index,
		"jump_i": jump_in_player_idx,
		"jump_resume": int(jump_in_resume_state),
		"jump_own_draw": jump_in_was_own_draw_phase,
		"active_ab": active_ability_player,
		"win_low": win_condition_lowest_wins,
		"global_ab": global_ability_counts.duplicate(),
		"easy": easy_mode,
		"tutorial": tutorial_mode,
		"num": num_players,
		"peers": peer_pairs,
		"players": players_arr,
		"deck": deck_arr,
		"discard": disc_arr,
		"drawn": drawn_d,
		"last_ab": last_ability_event.duplicate()
	}
	if current_state == GameState.GAME_OVER:
		payload["scores"] = _calculate_scores()
	return payload

func _apply_mp_sync_payload(payload: Dictionary) -> void:
	if payload.get("v", 0) != 1:
		return
	var incoming_seq := int(payload.get("seq", -1))
	if incoming_seq != -1:
		if incoming_seq <= _mp_last_applied_sync_seq:
			print("GameManager: Ignoring stale sync payload seq=%d last=%d" % [incoming_seq, _mp_last_applied_sync_seq])
			return
		if _mp_last_applied_sync_seq != -1 and incoming_seq > _mp_last_applied_sync_seq + 1:
			print("GameManager: Sync sequence gap detected prev=%d new=%d" % [_mp_last_applied_sync_seq, incoming_seq])
		_mp_last_applied_sync_seq = incoming_seq
	var prev_cur_before_apply := current_player_index
	var prev_state_before_apply := current_state
	num_players = int(payload.get("num", 4))
	current_state = int(payload.get("state", 0)) as GameState
	current_player_index = int(payload.get("cur", 0))
	turn_direction = int(payload.get("td", 1))
	dutch_caller_index = int(payload.get("dutch_i", -1))
	jump_in_player_idx = int(payload.get("jump_i", -1))
	jump_in_resume_state = int(payload.get("jump_resume", 0)) as GameState
	jump_in_was_own_draw_phase = bool(payload.get("jump_own_draw", false))
	active_ability_player = int(payload.get("active_ab", -1))
	win_condition_lowest_wins = bool(payload.get("win_low", true))
	global_ability_counts = (payload.get("global_ab", {}) as Dictionary).duplicate()
	easy_mode = bool(payload.get("easy", false))
	tutorial_mode = bool(payload.get("tutorial", false))
	last_ability_event = (payload.get("last_ab", {}) as Dictionary).duplicate()
	peer_to_idx.clear()
	idx_to_peer.clear()
	for pair in payload.get("peers", []):
		if pair is Array and pair.size() >= 2:
			var pid: int = int(pair[0])
			var idx: int = int(pair[1])
			peer_to_idx[pid] = idx
			idx_to_peer[idx] = pid
	# Never trust payload "local_idx" — it was the host's slot. Re-derive this peer's seat.
	local_player_idx = int(peer_to_idx.get(multiplayer.get_unique_id(), 0))
	players_info.clear()
	var _pidx := 0
	for p in payload.get("players", []):
		if p is Dictionary:
			var hand: Array = []
			for hd in p.get("hand", []):
				if hd is Dictionary:
					hand.append(_dict_to_card(hd))
			var p_abs = p.get("abilities", []) as Array
			var final_abs = []
			for k in range(6):
				if k < p_abs.size():
					final_abs.append(p_abs[k])
				else:
					final_abs.append("")
			players_info.append({
				"id": _pidx,
				"name": str(p.get("name", "Player")),
				"score": int(p.get("score", 0)),
				"hand": hand,
				"can_call_dutch": bool(p.get("can_call_dutch", true)),
				"beers": int(p.get("beers", 3)),
				"money": int(p.get("money", 0)),
				"abilities": final_abs,
				"is_eliminated": bool(p.get("is_eliminated", false)),
				"is_skipped": bool(p.get("is_skipped", false)),
				"is_bot": bool(p.get("is_bot", false)),
				"bot_memory": {}
			})
			_pidx += 1
	deck_manager.deck.clear()
	for hd in payload.get("deck", []):
		if hd is Dictionary:
			deck_manager.deck.append(_dict_to_card(hd))
	deck_manager.discard_pile.clear()
	for hd in payload.get("discard", []):
		if hd is Dictionary:
			deck_manager.discard_pile.append(_dict_to_card(hd))
	var dr = payload.get("drawn", null)
	if dr is Dictionary:
		drawn_card_data = _dict_to_card(dr)
	else:
		drawn_card_data = null
	var server_ts := int(payload.get("ts", 0))
	if server_ts > 0:
		mp_sync_lag_ms = maxi(0, Time.get_ticks_msec() - server_ts)
		_update_mp_connection_status()
	if current_state == GameState.GAME_OVER:
		var synced_scores: Array = payload.get("scores", [])
		if synced_scores.size() > 0 and not _mp_game_over_scores_applied:
			_mp_game_over_scores_applied = true
			all_cards_revealed.emit()
			var winner_id: int = synced_scores[0].get("id", -1) if synced_scores[0] is Dictionary else -1
			game_over.emit(winner_id)
			scores_ready.emit(synced_scores)
	elif current_state != GameState.GAME_OVER and (
		current_player_index != prev_cur_before_apply
		or (current_state == GameState.TURN_START_DRAW and prev_state_before_apply != GameState.TURN_START_DRAW)
	):
		turn_started.emit(current_player_index)
	_mp_sync_prev_cur = current_player_index

func _update_mp_connection_status() -> void:
	if not is_multiplayer:
		return
	var status := "ok"
	if multiplayer.multiplayer_peer == null \
			or multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		status = "disconnected"
	elif not multiplayer.is_server() and mp_sync_lag_ms >= 1500:
		status = "lagging"
	var prev_status := mp_connection_status
	var prev_lag := mp_sync_lag_ms
	mp_connection_status = status
	if status != prev_status or abs(mp_sync_lag_ms - prev_lag) >= 50:
		mp_connection_status_changed.emit(mp_sync_lag_ms, status)

func refresh_mp_connection_status() -> void:
	_update_mp_connection_status()

func is_valid_emote_id(emote_id: String) -> bool:
	return EMOTE_IDS.has(emote_id)

func get_emote_cooldown_remaining(player_idx: int) -> float:
	if not _is_valid_player_index(player_idx):
		return 0.0
	var until: float = float(_emote_cooldown_until.get(player_idx, 0.0))
	var now: float = Time.get_ticks_msec() / 1000.0
	return maxf(0.0, until - now)

func request_emote(emote_id: String) -> bool:
	if not is_valid_emote_id(emote_id):
		return false
	if is_multiplayer:
		if multiplayer.is_server():
			return emit_player_emote(local_player_idx, emote_id)
		request_player_emote.rpc_id(1, emote_id)
		return true
	return emit_player_emote(0, emote_id)

func emit_player_emote(player_idx: int, emote_id: String, respect_cooldown: bool = true) -> bool:
	if not is_valid_emote_id(emote_id) or not _is_valid_player_index(player_idx):
		return false
	if respect_cooldown and get_emote_cooldown_remaining(player_idx) > 0.0:
		return false
	if respect_cooldown:
		_emote_cooldown_until[player_idx] = Time.get_ticks_msec() / 1000.0 + EMOTE_COOLDOWN_SEC
	if is_multiplayer:
		broadcast_player_emote.rpc(player_idx, emote_id)
	else:
		player_emoted.emit(player_idx, emote_id)
	return true

@rpc("any_peer", "call_local", "reliable")
func request_player_emote(emote_id: String) -> void:
	if not is_multiplayer or not multiplayer.is_server():
		return
	if not is_valid_emote_id(emote_id):
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()
	var player_idx: int = int(peer_to_idx.get(sender_id, -1))
	if player_idx == -1:
		return
	emit_player_emote(player_idx, emote_id)

@rpc("any_peer", "call_local", "reliable")
func broadcast_player_emote(player_idx: int, emote_id: String) -> void:
	if not is_valid_emote_id(emote_id) or not _is_valid_player_index(player_idx):
		return
	if is_multiplayer and multiplayer.is_server():
		var sender_id := multiplayer.get_remote_sender_id()
		if sender_id != 0 and int(peer_to_idx.get(sender_id, -1)) != player_idx:
			return
	player_emoted.emit(player_idx, emote_id)

@rpc("authority", "call_local", "reliable")
func sync_match_state(payload: Dictionary) -> void:
	if not is_multiplayer:
		return
	if multiplayer.is_server():
		return
	_apply_mp_sync_payload(payload)
	multiplayer_sync_applied.emit()

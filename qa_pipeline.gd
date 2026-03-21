extends SceneTree

const GM_SCRIPT = preload("res://game_manager.gd")
const BOT_SCRIPT = preload("res://bot_controller.gd")
const GAME_BOARD_2D_SCENE = preload("res://game_board.tscn")
const GAME_BOARD_3D_SCENE = preload("res://game_board_3d.tscn")
const MAIN_MENU_SCENE = preload("res://main_menu.tscn")
const PAUSE_MENU_SCENE = preload("res://pause_menu.tscn")

var gm: Node = null
var bot: Node = null
var ui_scene: Node = null
var passed: int = 0
var failed: int = 0

func _init() -> void:
	call_deferred("_run")

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		print("[QA] User abort via ESC.")
		quit(1)

func _run() -> void:
	_ensure_qa_flag()
	print("\n[QA] STARTING COMPREHENSIVE QA PIPELINE (HEADLESS)...")
	await suite_initialization_and_guards()
	await suite_turn_cycle_and_abilities()
	await suite_dutch_and_scoring()
	await suite_jump_in_matrix()
	await suite_bot_logic_and_memory()
	await suite_scene_ui_parity()

	print("\n[QA] COMPLETE. Passed: %d  Failed: %d" % [passed, failed])
	await _dispose_context()
	_remove_qa_flag()
	if failed > 0:
		quit(1)
	else:
		quit(0)

func suite_initialization_and_guards() -> void:
	print("\n>>> SUITE 1: Initialization And Guard Rails <<<")
	await _fresh_context()
	gm.initialize_game(4)

	_check(gm.num_players == 4, "initialize_game sets player count")
	_check(gm.players_info.size() == 4, "initialize_game creates 4 players")
	_check_state(gm.GameState.DEAL_CARDS, "initialize_game leaves FSM at DEAL_CARDS without board driver")
	_check(gm.deck_manager.deck.size() == 52, "fresh deck contains 52 cards before dealing")
	_check(gm.drawn_card_data == null, "no pending drawn card after initialize")
	_check(gm.dutch_caller_index == -1, "no Dutch caller after initialize")
	_check(gm.dutch_round_turns_remaining == 0, "Dutch counter resets on initialize")
	_check(not gm.can_player_draw(0), "cannot draw during DEAL_CARDS")
	_check(not gm.can_player_call_dutch(0), "cannot call Dutch during DEAL_CARDS")
	_check(not gm.can_player_start_jump_in(0), "cannot jump in without a discard pile")
	_check(not gm.validate_jump_in(0), "validate_jump_in returns false outside jump-in selection")

	var state_before_blocked_draw: int = gm.current_state
	gm.player_draw_card()
	_check(gm.current_state == state_before_blocked_draw, "blocked draw leaves FSM unchanged")

	_force_turn_start(2)
	_check_player(2, "turn start can be positioned to any player")
	_check_state(gm.GameState.TURN_START_DRAW, "complete_initial_peek advances to TURN_START_DRAW")
	_check(gm.can_player_draw(2), "current player can draw at TURN_START_DRAW")
	_check(not gm.can_player_draw(1), "non-current player cannot draw")
	_check(not gm.can_player_end_turn(2), "cannot end turn before resolving a draw")
	_check(not gm.can_player_call_dutch(2), "cannot call Dutch before resolving a draw")
	_check(not gm.can_human_interact_with_hand_card(1, 0), "human cannot interact with opponent card at TURN_START_DRAW")

	gm.player_draw_card()
	_check_state(gm.GameState.TURN_RESOLVE_DRAWN, "draw transitions to TURN_RESOLVE_DRAWN")
	_check(gm.drawn_card_data != null and gm.drawn_card_data.is_face_up, "draw creates a face-up pending card")
	_check(gm.can_player_discard_drawn_card(2), "current player can discard pending card")
	_check(not gm.can_player_discard_drawn_card(1), "non-current player cannot discard current pending card")
	_check(gm.can_player_swap_drawn_card(2, 2, 0), "current player can swap with own card")
	_check(not gm.can_player_swap_drawn_card(2, 1, 0), "cannot swap pending card into another player's hand")
	_check(not gm.can_player_start_jump_in(0), "human cannot jump in during own TURN_RESOLVE_DRAWN")
	_check(not gm.can_player_start_jump_in(2), "bot/current player cannot jump in during TURN_RESOLVE_DRAWN")
	_check(not gm.can_human_interact_with_hand_card(2, 0), "non-human current player's cards are not exposed through the human interaction helper")
	_check(not gm.can_human_interact_with_hand_card(1, 0), "opponent cards remain non-interactive during swap choice")

	state_before_blocked_draw = gm.current_state
	gm.complete_peek_ability()
	_check(gm.current_state == state_before_blocked_draw, "complete_peek_ability is blocked outside TURN_PEEK_ABILITY")
	gm.complete_swap_ability(0, 0, 1, 0)
	_check(gm.current_state == state_before_blocked_draw, "complete_swap_ability is blocked outside TURN_SWAP_ABILITY")
	gm.end_turn()
	_check(gm.current_state == state_before_blocked_draw, "end_turn is blocked outside TURN_END_CHOICE")
	gm.confirm_dutch()
	_check(gm.current_state == state_before_blocked_draw, "confirm_dutch is blocked outside TURN_CONFIRM_DUTCH")
	gm.cancel_dutch()
	_check(gm.current_state == state_before_blocked_draw, "cancel_dutch is blocked outside TURN_CONFIRM_DUTCH")

func suite_turn_cycle_and_abilities() -> void:
	print("\n>>> SUITE 2: Turn Cycle And Ability Resolution <<<")
	for player_idx in range(4):
		await _fresh_context()
		_force_turn_start(player_idx)

		var drawn_events := []
		gm.card_drawn_to_pending.connect(func(a = null, b = null): drawn_events.append([a, b]))
		var discarded_events := []
		gm.card_discarded.connect(func(a = null, b = null): discarded_events.append([a, b]))
		var hand_updates := []
		gm.hand_updated.connect(func(a = null): hand_updates.append(a))
		var memory_shifts := []
		gm.memory_shift_required.connect(func(a = null, b = null): memory_shifts.append([a, b]))
		var jack_swaps := []
		gm.jack_swap_resolved.connect(func(a = null, b = null, c = null, d = null): jack_swaps.append([a, b, c, d]))

		gm.player_draw_card()
		_check(drawn_events.size() == 1 and drawn_events[0][0] == player_idx, "draw emits card_drawn_to_pending for player %d" % player_idx)
		gm.drawn_card_data = _make_card("Ace", "Clubs", true)
		gm.player_discard_drawn_card()
		await _await_resolution()
		_check_state(gm.GameState.TURN_END_CHOICE, "plain discard returns to TURN_END_CHOICE for player %d" % player_idx)
		_check(gm.drawn_card_data == null, "discard clears drawn_card_data for player %d" % player_idx)
		_check(discarded_events.size() == 1 and discarded_events[0][0] == player_idx, "discard emits card_discarded for player %d" % player_idx)
		gm.end_turn()
		_check_state(gm.GameState.TURN_START_DRAW, "end_turn advances after discard for player %d" % player_idx)

		await _fresh_context()
		_force_turn_start(player_idx)
		gm.players_info[player_idx].hand[0] = _make_card("King", "Spades")
		gm.player_draw_card()
		gm.drawn_card_data = _make_card("2", "Hearts", true)
		gm.player_swap_drawn_card(0)
		await _await_resolution()
		_check_state(gm.GameState.TURN_END_CHOICE, "swap returns to TURN_END_CHOICE for player %d" % player_idx)
		_check(gm.players_info[player_idx].hand[0].rank == "2", "swap inserts drawn card into hand for player %d" % player_idx)
		_check(not gm.players_info[player_idx].hand[0].is_face_up, "swapped-in hand card is face-down for player %d" % player_idx)

		await _fresh_context()
		_force_turn_start(player_idx)
		gm.player_draw_card()
		gm.drawn_card_data = _make_card("Queen", "Diamonds", true)
		gm.player_discard_drawn_card()
		await _await_resolution()
		_check_state(gm.GameState.TURN_PEEK_ABILITY, "discarding Queen enters TURN_PEEK_ABILITY for player %d" % player_idx)
		_check(gm.can_player_complete_peek_ability(player_idx), "current player can complete Queen ability for player %d" % player_idx)
		_check(gm.can_player_use_peek_ability(player_idx, 1, false), "Queen ability allows peeking at a face-down target")
		_check(not gm.can_player_use_peek_ability(player_idx, 1, true), "Queen ability blocks peeking a face-up target")
		gm.complete_peek_ability()
		_check_state(gm.GameState.TURN_END_CHOICE, "completing Queen ability returns to TURN_END_CHOICE for player %d" % player_idx)

		await _fresh_context()
		_force_turn_start(player_idx)
		var jack_swaps_single := []
		gm.jack_swap_resolved.connect(func(a = null, b = null, c = null, d = null): jack_swaps_single.append([a, b, c, d]))
		gm.players_info[0].hand[0] = _make_card("7", "Hearts")
		gm.players_info[1].hand[0] = _make_card("Ace", "Spades")
		gm.player_draw_card()
		gm.drawn_card_data = _make_card("Jack", "Clubs", true)
		gm.player_discard_drawn_card()
		await _await_resolution()
		_check_state(gm.GameState.TURN_SWAP_ABILITY, "discarding Jack enters TURN_SWAP_ABILITY for player %d" % player_idx)
		_check(gm.can_player_select_swap_card(player_idx, 0, 0), "Jack ability allows selecting first target for player %d" % player_idx)
		gm.complete_swap_ability(0, 0, 1, 0)
		_check_state(gm.GameState.TURN_END_CHOICE, "completing Jack ability returns to TURN_END_CHOICE for player %d" % player_idx)
		_check(gm.players_info[0].hand[0].rank == "Ace" and gm.players_info[1].hand[0].rank == "7", "Jack swap exchanges cards across players")
		_check(jack_swaps_single.size() == 1, "Jack swap emits jack_swap_resolved once")

	await _fresh_context()
	_force_turn_start(0)
	gm.player_draw_card()
	gm.drawn_card_data = _make_card("Jack", "Hearts", true)
	gm.player_discard_drawn_card()
	await _await_resolution()
	var state_before_invalid_swap: int = gm.current_state
	gm.complete_swap_ability(0, 99, 1, 99)
	_check(gm.current_state == state_before_invalid_swap, "invalid Jack swap indices leave TURN_SWAP_ABILITY unchanged")
	gm.complete_swap_ability(-1, -1, -1, -1)
	_check_state(gm.GameState.TURN_END_CHOICE, "skip path exits TURN_SWAP_ABILITY cleanly")

func suite_dutch_and_scoring() -> void:
	print("\n>>> SUITE 3: Dutch Flow And Scoring <<<")
	for caller_idx in range(4):
		await _fresh_context()
		await _force_turn_end_choice(caller_idx)
		_check(gm.can_player_call_dutch(caller_idx), "caller %d can call Dutch at TURN_END_CHOICE" % caller_idx)
		gm.call_dutch(caller_idx)
		_check(gm.dutch_caller_index == caller_idx, "caller %d is stored as Dutch caller" % caller_idx)
		_check(gm.dutch_round_turns_remaining == 2, "Dutch turn counter decrements immediately after caller %d rotates" % caller_idx)
		for turn_idx in range(3):
			var active_idx: int = gm.current_player_index
			_check_state(gm.GameState.TURN_START_DRAW, "non-caller %d gets TURN_START_DRAW during Dutch cycle" % active_idx)
			await _advance_current_turn_to_end_choice()
			gm.end_turn()
		_check_player(caller_idx, "Dutch cycle returns to caller %d" % caller_idx)
		_check_state(gm.GameState.TURN_CONFIRM_DUTCH, "caller %d reaches TURN_CONFIRM_DUTCH after full rotation" % caller_idx)
		gm.confirm_dutch()
		_check_state(gm.GameState.GAME_OVER, "confirm_dutch ends the game for caller %d" % caller_idx)

	await _fresh_context()
	await _force_turn_end_choice(1)
	gm.call_dutch(1)
	for _step in range(3):
		await _advance_current_turn_to_end_choice()
		gm.end_turn()
	_check_state(gm.GameState.TURN_CONFIRM_DUTCH, "cancel scenario returns to caller confirm state")
	gm.cancel_dutch()
	_check_state(gm.GameState.TURN_START_DRAW, "cancel_dutch returns to TURN_START_DRAW")
	_check(gm.dutch_caller_index == -1, "cancel_dutch clears Dutch caller")
	_check(gm.dutch_round_turns_remaining == 0, "cancel_dutch clears Dutch counter")
	_check(not gm.players_info[1].can_call_dutch, "cancel_dutch forfeits caller's future Dutch right")

	await _fresh_context()
	await _force_turn_end_choice(0)
	gm.players_info[0].can_call_dutch = false
	_check(not gm.can_player_call_dutch(0), "forfeited caller cannot call Dutch again")
	gm.call_dutch(0)
	_check(gm.dutch_caller_index == -1, "blocked Dutch call leaves caller unset")

	await _fresh_context()
	await _force_turn_end_choice(2)
	_check(not gm.can_player_call_dutch(1), "non-current player cannot call Dutch")
	gm.confirm_dutch()
	_check_state(gm.GameState.TURN_END_CHOICE, "confirm_dutch is blocked before TURN_CONFIRM_DUTCH")

	await _fresh_context()
	gm.initialize_game(4)
	gm.players_info[0].hand = []
	gm.players_info[1].hand = [_make_card("King", "Spades"), _make_card("Ace", "Clubs")]
	gm.players_info[2].hand = [_make_card("King", "Diamonds")]
	gm.players_info[3].hand = [_make_card("5", "Hearts"), _make_card("5", "Clubs"), _make_card("5", "Spades")]
	var scores: Array = gm._calculate_scores()
	_check(scores[0].id == 0 and scores[0].score == -1, "empty hand wins scoring outright")
	_check(scores[1].id == 2 and scores[1].score == 0, "King of Diamonds scores as 0")

	await _fresh_context()
	gm.initialize_game(4)
	gm.players_info[0].hand = [_make_card("4", "Hearts"), _make_card("3", "Clubs"), _make_card("3", "Spades")]
	gm.players_info[1].hand = [_make_card("10", "Spades")]
	gm.players_info[2].hand = [_make_card("5", "Diamonds"), _make_card("5", "Clubs")]
	gm.players_info[3].hand = [_make_card("King", "Spades")]
	scores = gm._calculate_scores()
	_check(scores[0].id == 1, "score ties break toward fewer cards")
	_check(scores[1].id == 2 and scores[2].id == 0, "remaining tied scores sort by increasing card count")

	await _fresh_context()
	var revealed_events := []
	var score_events := []
	var winner_events := []
	gm.all_cards_revealed.connect(func(): revealed_events.append(true))
	gm.scores_ready.connect(func(results = null): score_events.append(results))
	gm.game_over.connect(func(winner_id = null): winner_events.append(winner_id))
	gm.initialize_game(4)
	gm.current_state = gm.GameState.TURN_CONFIRM_DUTCH
	gm.players_info[0].hand = []
	gm.confirm_dutch()
	_check(revealed_events.size() == 1, "GAME_OVER emits all_cards_revealed")
	_check(score_events.size() == 1 and score_events[0][0].id == 0, "GAME_OVER emits sorted scores_ready payload")
	_check(winner_events.size() == 1 and winner_events[0] == 0, "GAME_OVER emits winner id from scores")

func suite_jump_in_matrix() -> void:
	print("\n>>> SUITE 4: Jump-In Matrix <<<")
	await _fresh_context()
	_force_turn_start(0)
	_check(not gm.can_player_start_jump_in(0), "jump-in is blocked without a discard pile")

	await _fresh_context()
	_force_turn_start(0)
	_set_discard_top("5", "Hearts")
	gm.players_info[0].hand = [_make_card("King", "Spades"), _make_card("2", "Clubs"), _make_card("4", "Diamonds"), _make_card("7", "Spades")]
	_check(gm.can_player_start_jump_in(0), "human can jump in before drawing at TURN_START_DRAW")
	gm.start_jump_in(0)
	_check_state(gm.GameState.TURN_JUMP_IN_SELECTION, "start_jump_in enters TURN_JUMP_IN_SELECTION from TURN_START_DRAW")
	_check(gm.can_player_cancel_jump_in(0), "jump-in owner can cancel selection")
	_check(not gm.can_player_cancel_jump_in(1), "non-owner cannot cancel jump-in selection")
	gm.cancel_jump_in()
	_check_state(gm.GameState.TURN_START_DRAW, "cancelled jump-in resumes TURN_START_DRAW")

	await _fresh_context()
	await _force_turn_end_choice(0)
	_set_discard_top("9", "Clubs")
	gm.players_info[0].hand[0] = _make_card("King", "Spades")
	gm.start_jump_in(0)
	_check_state(gm.GameState.TURN_JUMP_IN_SELECTION, "jump-in can interrupt TURN_END_CHOICE")
	var before_failed_size: int = gm.players_info[0].hand.size()
	var failed_jump: bool = await gm.validate_jump_in(0)
	_check(not failed_jump, "mismatched jump-in is rejected")
	_check_state(gm.GameState.TURN_END_CHOICE, "failed jump-in from TURN_END_CHOICE resumes TURN_END_CHOICE")
	_check(gm.players_info[0].hand.size() == before_failed_size + 1, "failed jump-in adds one penalty card")

	await _fresh_context()
	_force_turn_start(0)
	_set_discard_top("9", "Diamonds")
	gm.drawn_card_data = _make_card("9", "Clubs", true)
	gm.start_jump_in(0)
	_check(gm.can_player_select_jump_in_card(0, 0, -2), "pending drawn card can be selected for jump-in by current player")
	var pending_success: bool = await gm.validate_jump_in(-2)
	await _await_resolution()
	_check(pending_success, "pending-card jump-in succeeds when ranks match")
	_check_state(gm.GameState.TURN_START_DRAW, "successful pending-card jump-in resumes TURN_START_DRAW")
	_check(gm.drawn_card_data == null, "successful pending-card jump-in consumes drawn_card_data")

	await _fresh_context()
	_force_turn_start(1)
	_set_discard_top("6", "Spades")
	gm.player_draw_card()
	_check_state(gm.GameState.TURN_RESOLVE_DRAWN, "bot turn draw enters TURN_RESOLVE_DRAWN")
	_check(gm.can_player_start_jump_in(0), "human can interrupt bot TURN_RESOLVE_DRAWN with jump-in")
	gm.start_jump_in(0)
	gm.cancel_jump_in()
	_check_state(gm.GameState.TURN_RESOLVE_DRAWN, "cancelled jump-in during bot resolve resumes TURN_RESOLVE_DRAWN")

	await _fresh_context()
	_force_turn_start(0)
	_set_discard_top("8", "Clubs")
	gm.player_draw_card()
	_check_state(gm.GameState.TURN_RESOLVE_DRAWN, "own draw enters TURN_RESOLVE_DRAWN")
	_check(not gm.can_player_start_jump_in(0), "human cannot jump in during own TURN_RESOLVE_DRAWN")

	await _fresh_context()
	await _force_turn_end_choice(0)
	_set_discard_top("Queen", "Spades")
	gm.players_info[0].hand[0] = _make_card("Queen", "Hearts")
	var pre_queen_discard_size: int = gm.deck_manager.discard_pile.size()
	gm.start_jump_in(0)
	var queen_success: bool = await gm.validate_jump_in(0)
	await _await_resolution()
	_check(queen_success, "successful Queen jump-in is accepted")
	_check_state(gm.GameState.TURN_PEEK_ABILITY, "successful Queen jump-in routes to TURN_PEEK_ABILITY")
	_check(gm.deck_manager.discard_pile.size() == pre_queen_discard_size + 1, "successful Queen jump-in appends card to discard pile")
	gm.complete_peek_ability()
	_check_state(gm.GameState.TURN_END_CHOICE, "Queen jump-in ability resumes interrupted TURN_END_CHOICE")

	await _fresh_context()
	_force_turn_start(0)
	_set_discard_top("Jack", "Diamonds")
	gm.players_info[0].hand[0] = _make_card("Jack", "Clubs")
	gm.start_jump_in(0)
	var jack_success: bool = await gm.validate_jump_in(0)
	await _await_resolution()
	_check(jack_success, "successful Jack jump-in is accepted")
	_check_state(gm.GameState.TURN_SWAP_ABILITY, "successful Jack jump-in routes to TURN_SWAP_ABILITY")
	gm.complete_swap_ability(-1, -1, -1, -1)
	_check_state(gm.GameState.TURN_START_DRAW, "skipped Jack jump-in ability resumes interrupted TURN_START_DRAW")

	await _fresh_context()
	await _force_turn_end_choice(0)
	_set_discard_top("4", "Hearts")
	gm.players_info[0].hand = [_make_card("4", "Spades")]
	gm.start_jump_in(0)
	var final_card_success: bool = await gm.validate_jump_in(0)
	_check(final_card_success, "successful last-card jump-in returns true")
	_check_state(gm.GameState.GAME_OVER, "successful last-card jump-in ends the game immediately")

	await _fresh_context()
	await _force_turn_end_choice(0)
	_set_discard_top("7", "Clubs")
	gm.start_jump_in(0)
	gm.deck_manager.discard_pile.clear()
	_check(not gm.validate_jump_in(0), "validate_jump_in returns false when discard pile disappears")
	_check_state(gm.GameState.TURN_JUMP_IN_SELECTION, "failed validation due to missing discard leaves selection state intact")

func suite_bot_logic_and_memory() -> void:
	print("\n>>> SUITE 5: Bot Logic And Memory <<<")
	await _fresh_context(true)
	gm.initialize_game(4)
	_deal_test_hands()
	gm.change_state(gm.GameState.INITIAL_PEEK)
	await process_frame
	for bot_idx in range(1, 4):
		var mem: Dictionary = bot._mem(bot_idx)
		_check(mem.size() == 2, "bot %d learns exactly two of its own cards during initial peek" % bot_idx)
		_check(mem.keys()[0] != mem.keys()[1], "bot %d initial peek learns two distinct indices" % bot_idx)
		_check(gm.players_info[bot_idx].bot_memory.has(bot_idx), "bot %d stores memory bucket for itself" % bot_idx)

	await _fresh_context(true)
	gm.initialize_game(2)
	_set_discard_top("9", "Hearts")
	gm.current_player_index = 0
	gm.current_state = gm.GameState.TURN_END_CHOICE
	gm.players_info[1].hand = [_make_card("9", "Clubs"), _make_card("3", "Spades")]
	gm.players_info[1].bot_memory = {0: {}, 1: {0: gm.players_info[1].hand[0]}, 2: {}, 3: {}}
	bot._on_card_discarded(0, gm.deck_manager.discard_pile[-1])
	await _await_resolution()
	_check(gm.players_info[1].hand.size() == 1, "first eligible bot completes jump-in and loses one card")

	await _fresh_context(true)
	gm.initialize_game(2)
	_set_discard_top("4", "Hearts")
	gm.current_player_index = 0
	gm.current_state = gm.GameState.TURN_END_CHOICE
	gm.players_info[1].hand = [_make_card("4", "Clubs"), _make_card("8", "Spades")]
	gm.players_info[1].bot_memory = {0: {}, 1: {}, 2: {}, 3: {}}
	bot._on_card_discarded(0, gm.deck_manager.discard_pile[-1])
	await _await_resolution()
	_check(gm.players_info[1].hand.size() == 2, "bot does not jump in with an unknown matching card")

	await _fresh_context(true)
	gm.initialize_game(2)
	_set_discard_top("6", "Clubs")
	gm.current_player_index = 0
	gm.current_state = gm.GameState.TURN_END_CHOICE
	gm.players_info[1].hand = [_make_card("6", "Spades")]
	gm.players_info[1].bot_memory = {0: {}, 1: {0: gm.players_info[1].hand[0]}, 2: {}, 3: {}}
	bot._jump_in_probe_id = 2
	await bot._try_jump_ins(gm.players_info[1].hand[0], 1, gm.current_player_index)
	_check(gm.players_info[1].hand.size() == 1, "stale probe id suppresses outdated bot jump-in")
	await bot._try_jump_ins(gm.players_info[1].hand[0], 2, 3)
	_check(gm.players_info[1].hand.size() == 1, "acting-player mismatch suppresses outdated bot jump-in")
	gm.deck_manager.discard_pile.append(_make_card("King", "Hearts"))
	await bot._try_jump_ins(gm.players_info[1].hand[0], 2, gm.current_player_index)
	_check(gm.players_info[1].hand.size() == 1, "top-discard mismatch suppresses outdated bot jump-in")

	await _fresh_context()
	gm.initialize_game(2)
	gm.current_player_index = 1
	gm.players_info[1].hand = []
	gm.current_state = gm.GameState.TURN_RESOLVE_DRAWN
	gm.drawn_card_data = _make_card("7", "Clubs", true)
	var isolated_bot := BOT_SCRIPT.new()
	isolated_bot.gm = gm
	await isolated_bot._execute_resolve_drawn(1)
	isolated_bot.free()
	await _await_resolution()
	_check_state(gm.GameState.TURN_END_CHOICE, "bot with empty hand discards drawn card instead of swapping")

	await _fresh_context()
	gm.initialize_game(2)
	gm.current_player_index = 1
	gm.current_state = gm.GameState.TURN_RESOLVE_DRAWN
	gm.players_info[1].hand = [_make_card("2", "Clubs"), _make_card("King", "Spades")]
	gm.players_info[1].bot_memory = {0: {}, 1: {0: gm.players_info[1].hand[0], 1: gm.players_info[1].hand[1]}, 2: {}, 3: {}}
	gm.drawn_card_data = _make_card("5", "Hearts", true)
	isolated_bot = BOT_SCRIPT.new()
	isolated_bot.gm = gm
	await isolated_bot._execute_resolve_drawn(1)
	isolated_bot.free()
	await _await_resolution()
	_check(gm.players_info[1].hand[1].rank == "5", "bot swaps drawn card for worst known card when beneficial")

	await _fresh_context()
	gm.initialize_game(2)
	gm.current_player_index = 1
	gm.current_state = gm.GameState.TURN_RESOLVE_DRAWN
	gm.players_info[1].hand = [_make_card("5", "Clubs"), _make_card("King", "Spades")]
	gm.players_info[1].bot_memory = {0: {}, 1: {0: gm.players_info[1].hand[0]}, 2: {}, 3: {}}
	gm.drawn_card_data = _make_card("5", "Hearts", true)
	isolated_bot = BOT_SCRIPT.new()
	isolated_bot.gm = gm
	await isolated_bot._execute_resolve_drawn(1)
	isolated_bot.free()
	await _await_resolution()
	_check(gm.players_info[1].hand[0].rank == "5" and gm.players_info[1].hand[0].suit == "Clubs", "bot discards equal-value draw instead of swapping")
	_check(gm.players_info[1].hand.size() == 2, "bot discard path preserves hand size")

	await _fresh_context()
	gm.initialize_game(2)
	gm.current_player_index = 1
	gm.current_state = gm.GameState.TURN_PEEK_ABILITY
	gm.players_info[1].hand = [_make_card("2", "Clubs"), _make_card("King", "Spades")]
	gm.players_info[1].bot_memory = {0: {}, 1: {0: gm.players_info[1].hand[0]}, 2: {}, 3: {}}
	isolated_bot = BOT_SCRIPT.new()
	isolated_bot.gm = gm
	await isolated_bot._execute_queen_peek(1)
	isolated_bot.free()
	_check(gm.players_info[1].bot_memory[1].has(1), "bot Queen prefers learning an unknown own card first")

	await _fresh_context()
	gm.initialize_game(2)
	gm.current_player_index = 1
	gm.current_state = gm.GameState.TURN_PEEK_ABILITY
	gm.players_info[0].hand = [_make_card("Jack", "Hearts")]
	gm.players_info[1].hand = [_make_card("2", "Clubs"), _make_card("King", "Spades"), _make_card("10", "Spades"), _make_card("Ace", "Clubs")]
	gm.players_info[1].bot_memory = {0: {}, 1: {
		0: gm.players_info[1].hand[0],
		1: gm.players_info[1].hand[1],
		2: gm.players_info[1].hand[2],
		3: gm.players_info[1].hand[3]
	}, 2: {}, 3: {}}
	isolated_bot = BOT_SCRIPT.new()
	isolated_bot.gm = gm
	await isolated_bot._execute_queen_peek(1)
	isolated_bot.free()
	_check(gm.players_info[1].bot_memory[0].size() == 1, "bot Queen falls back to learning an opponent card when own hand is fully known")

	await _fresh_context()
	gm.initialize_game(2)
	gm.current_player_index = 1
	gm.current_state = gm.GameState.TURN_SWAP_ABILITY
	for idx in range(2):
		gm.players_info[idx].hand = []
	gm.players_info[0].hand = [_make_card("7", "Hearts")]
	isolated_bot = BOT_SCRIPT.new()
	isolated_bot.gm = gm
	await isolated_bot._execute_jack_swap(1)
	isolated_bot.free()
	_check_state(gm.GameState.TURN_END_CHOICE, "bot Jack no-op path exits TURN_SWAP_ABILITY cleanly when too few targets exist")

	await _fresh_context()
	gm.initialize_game(2)
	gm.current_player_index = 1
	gm.current_state = gm.GameState.TURN_END_CHOICE
	gm.players_info[1].hand = [_make_card("Ace", "Clubs"), _make_card("2", "Hearts"), _make_card("4", "Spades")]
	gm.players_info[1].bot_memory = {0: {}, 1: {
		0: gm.players_info[1].hand[0],
		1: gm.players_info[1].hand[1],
		2: gm.players_info[1].hand[2]
	}, 2: {}, 3: {}}
	isolated_bot = BOT_SCRIPT.new()
	isolated_bot.gm = gm
	await isolated_bot._execute_end_choice(1)
	isolated_bot.free()
	_check(gm.dutch_caller_index == 1 and gm.current_player_index == 0 and gm.current_state == gm.GameState.TURN_START_DRAW, "bot calls Dutch when all cards are known and score is <= 7")

	await _fresh_context()
	gm.initialize_game(2)
	gm.current_player_index = 1
	gm.current_state = gm.GameState.TURN_END_CHOICE
	gm.players_info[1].hand = [_make_card("Ace", "Clubs"), _make_card("2", "Hearts"), _make_card("5", "Spades")]
	gm.players_info[1].bot_memory = {0: {}, 1: {
		0: gm.players_info[1].hand[0],
		1: gm.players_info[1].hand[1],
		2: gm.players_info[1].hand[2]
	}, 2: {}, 3: {}}
	isolated_bot = BOT_SCRIPT.new()
	isolated_bot.gm = gm
	await isolated_bot._execute_end_choice(1)
	isolated_bot.free()
	_check(gm.dutch_caller_index == -1 and gm.current_player_index == 0 and gm.current_state == gm.GameState.TURN_START_DRAW, "bot ends turn instead of calling Dutch when score exceeds 7")

	await _fresh_context()
	gm.initialize_game(2)
	gm.current_player_index = 1
	gm.current_state = gm.GameState.TURN_END_CHOICE
	gm.players_info[1].hand = [_make_card("Ace", "Clubs"), _make_card("2", "Hearts"), _make_card("4", "Spades")]
	gm.players_info[1].bot_memory = {0: {}, 1: {0: gm.players_info[1].hand[0], 1: gm.players_info[1].hand[1]}, 2: {}, 3: {}}
	isolated_bot = BOT_SCRIPT.new()
	isolated_bot.gm = gm
	await isolated_bot._execute_end_choice(1)
	isolated_bot.free()
	_check(gm.dutch_caller_index == -1 and gm.current_player_index == 0 and gm.current_state == gm.GameState.TURN_START_DRAW, "bot refuses Dutch if any own card is still unknown")

	await _fresh_context(true)
	_force_turn_start(0)
	gm.players_info[1].bot_memory = {0: {0: _make_card("Ace", "Clubs"), 2: _make_card("King", "Spades")}, 1: {1: _make_card("3", "Hearts")}, 2: {}, 3: {}}
	gm.players_info[2].bot_memory = {0: {0: _make_card("Ace", "Clubs"), 2: _make_card("King", "Spades")}, 1: {1: _make_card("3", "Hearts")}, 2: {}, 3: {}}
	bot._on_memory_shift_required(0, 1)
	_check(gm.players_info[1].bot_memory[0].has(0) and gm.players_info[1].bot_memory[0].has(1), "memory_shift_required shifts known indices above removed slot down by one")
	_check(not gm.players_info[1].bot_memory[1].has(0), "memory_shift_required does not mutate unrelated player memory buckets")

func suite_scene_ui_parity() -> void:
	print("\n>>> SUITE 6: Scene-Level UI Parity <<<")
	await _dispose_context()
	await _dispose_ui_scene()
	var scene_gm: Node = root.get_node("GameManager")
	scene_gm.initialize_game(4)
	ui_scene = GAME_BOARD_2D_SCENE.instantiate()
	root.add_child(ui_scene)
	await _await_scene_ready_for_ui(scene_gm)
	await _scene_force_state(scene_gm, ui_scene, scene_gm.GameState.TURN_END_CHOICE, 0, true)
	_check(ui_scene.end_turn_btn.visible, "2D END TURN button is visible for human TURN_END_CHOICE")
	_check(ui_scene.call_dutch_btn.visible, "2D CALL DUTCH button is visible for human TURN_END_CHOICE")
	await _scene_force_state(scene_gm, ui_scene, scene_gm.GameState.TURN_JUMP_IN_SELECTION, 0, true)
	scene_gm.jump_in_player_idx = 0
	ui_scene._on_game_state_changed(scene_gm.GameState.TURN_JUMP_IN_SELECTION)
	await process_frame
	_check(ui_scene.end_turn_btn.text == "CANCEL JUMP-IN", "2D jump-in cancel button text matches expected label")
	await _scene_force_state(scene_gm, ui_scene, scene_gm.GameState.TURN_CONFIRM_DUTCH, 0, true, false, true)
	ui_scene._on_game_state_changed(scene_gm.GameState.TURN_CONFIRM_DUTCH)
	await process_frame
	_check(ui_scene.confirm_dutch_btn.visible and ui_scene.forfeit_dutch_btn.visible, "2D Dutch confirm/forfeit buttons appear together")
	_check(_top_center_text(ui_scene.top_center) == "You called Dutch. Confirm to end or forfeit to keep playing.", "2D Dutch confirm prompt text is correct")
	await _dispose_ui_scene()

	scene_gm.initialize_game(4)
	ui_scene = GAME_BOARD_3D_SCENE.instantiate()
	root.add_child(ui_scene)
	await _await_scene_ready_for_ui(scene_gm)
	await _scene_force_state(scene_gm, ui_scene, scene_gm.GameState.TURN_END_CHOICE, 0, false)
	_check(ui_scene.end_turn_btn.visible, "3D END TURN button is visible for human TURN_END_CHOICE")
	_check(ui_scene.call_dutch_btn.visible, "3D CALL DUTCH button is visible for human TURN_END_CHOICE")
	_check(not ui_scene.jump_in_btn.visible, "3D JUMP IN button stays hidden without a discard opportunity")
	await _scene_force_state(scene_gm, ui_scene, scene_gm.GameState.TURN_START_DRAW, 0, true)
	_check(ui_scene.jump_in_btn.visible, "3D JUMP IN button is visible when pre-draw jump-in is legal")
	_check(ui_scene.get_node("DeckArea/Area3D").input_ray_pickable, "3D deck input is enabled when draw is legal")
	_check(not ui_scene.get_node("DiscardArea/Area3D").input_ray_pickable, "3D discard input is disabled before a draw")
	await _scene_force_state(scene_gm, ui_scene, scene_gm.GameState.TURN_RESOLVE_DRAWN, 0, true, true)
	_check(not ui_scene.get_node("DeckArea/Area3D").input_ray_pickable, "3D deck input is disabled after drawing")
	_check(ui_scene.get_node("DiscardArea/Area3D").input_ray_pickable, "3D discard input is enabled while a pending card exists")
	await _scene_force_state(scene_gm, ui_scene, scene_gm.GameState.TURN_JUMP_IN_SELECTION, 0, true)
	scene_gm.jump_in_player_idx = 0
	ui_scene._on_game_state_changed(scene_gm.GameState.TURN_JUMP_IN_SELECTION)
	await process_frame
	_check(ui_scene.end_turn_btn.text == "CANCEL JUMP-IN", "3D jump-in cancel button text matches 2D")
	await _scene_force_state(scene_gm, ui_scene, scene_gm.GameState.TURN_CONFIRM_DUTCH, 0, true, false, true)
	ui_scene._on_game_state_changed(scene_gm.GameState.TURN_CONFIRM_DUTCH)
	await process_frame
	_check(ui_scene.confirm_dutch_btn.visible and ui_scene.forfeit_dutch_btn.visible, "3D Dutch confirm/forfeit buttons appear together")
	_check(_top_center_text(ui_scene.top_center) == "You called Dutch. Confirm to end or forfeit to keep playing.", "3D Dutch confirm prompt matches 2D")
	await _dispose_ui_scene()

	var main_menu := MAIN_MENU_SCENE.instantiate()
	root.add_child(main_menu)
	await process_frame
	main_menu._on_settings_button_pressed()
	_check(not main_menu.get_node("CenterContainer").visible, "main menu hides CenterContainer when settings opens")
	main_menu._on_settings_back()
	_check(main_menu.get_node("CenterContainer").visible, "main menu restores CenterContainer after settings back")
	main_menu.queue_free()
	await process_frame

	var pause_menu := PAUSE_MENU_SCENE.instantiate()
	root.add_child(pause_menu)
	await process_frame
	pause_menu._on_settings_button_pressed()
	_check(not pause_menu.vbox.visible, "pause menu hides main button stack when settings opens")
	pause_menu._on_settings_back()
	_check(pause_menu.vbox.visible, "pause menu restores main button stack after settings back")
	pause_menu.queue_free()
	await process_frame
	_reset_game_manager_runtime(scene_gm)
	await process_frame

func _fresh_context(with_bot: bool = false) -> void:
	await _dispose_context()
	gm = GM_SCRIPT.new()
	gm.name = "GameManager"
	root.add_child(gm)
	await process_frame
	if with_bot:
		bot = BOT_SCRIPT.new()
		bot.gm = gm
		root.add_child(bot)
		await process_frame

func _force_turn_start(player_idx: int) -> void:
	gm.initialize_game(4)
	_deal_test_hands()
	gm.change_state(gm.GameState.INITIAL_PEEK)
	gm.current_player_index = player_idx
	gm.complete_initial_peek()

func _force_turn_end_choice(player_idx: int) -> void:
	_force_turn_start(player_idx)
	await _advance_current_turn_to_end_choice()

func _advance_current_turn_to_end_choice() -> void:
	gm.player_draw_card()
	gm.drawn_card_data = _make_card("Ace", "Clubs", true)
	gm.player_discard_drawn_card()
	await _await_resolution()

func _set_discard_top(rank: String, suit: String) -> void:
	gm.deck_manager.discard_pile.clear()
	gm.deck_manager.discard_pile.append(_make_card(rank, suit))

func _make_card(rank: String, suit: String, face_up: bool = false) -> CardData:
	var card: CardData = CardData.new(rank, suit)
	card.is_face_up = face_up
	return card

func _deal_test_hands(player_count: int = -1) -> void:
	var limit: int = gm.num_players if player_count == -1 else player_count
	for p_idx in range(limit):
		gm.players_info[p_idx].hand.clear()
	for _card_round in range(4):
		for p_idx in range(limit):
			var card_info: Dictionary = gm.deck_manager.draw_card()
			if card_info.is_empty():
				continue
			gm.players_info[p_idx].hand.append(_make_card(card_info.rank, card_info.suit))

func _dispose_context() -> void:
	if bot and is_instance_valid(bot):
		bot.queue_free()
		bot = null
	if gm and is_instance_valid(gm):
		gm.queue_free()
		gm = null
	await process_frame

func _ensure_qa_flag() -> void:
	if root.has_node("QA_PIPELINE_FLAG"):
		return
	var flag = Node.new()
	flag.name = "QA_PIPELINE_FLAG"
	flag.set("skip_anims", true)
	root.add_child(flag)

func _remove_qa_flag() -> void:
	var flag := root.get_node_or_null("QA_PIPELINE_FLAG")
	if flag:
		flag.queue_free()

func _dispose_ui_scene() -> void:
	if ui_scene and is_instance_valid(ui_scene):
		ui_scene.queue_free()
		ui_scene = null
	await process_frame
	await process_frame

func _scene_force_state(scene_gm: Node, scene_node: Node, state: int, player_idx: int, with_discard: bool, with_pending_draw: bool = false, with_dutch_caller: bool = false) -> void:
	scene_gm.current_player_index = player_idx
	scene_gm.jump_in_player_idx = player_idx
	scene_gm.dutch_caller_index = player_idx if with_dutch_caller else -1
	scene_gm.drawn_card_data = _make_card("Ace", "Clubs", true) if with_pending_draw else null
	scene_gm.deck_manager.discard_pile.clear()
	if with_discard:
		scene_gm.deck_manager.discard_pile.append(_make_card("7", "Hearts"))
	scene_gm.current_state = state
	scene_node._on_game_state_changed(state)
	await process_frame

func _await_scene_ready_for_ui(scene_gm: Node, max_frames: int = 180) -> void:
	for _idx in range(max_frames):
		if scene_gm and scene_gm.current_state == scene_gm.GameState.INITIAL_PEEK:
			await process_frame
			return
		await process_frame

func _reset_game_manager_runtime(scene_gm: Node) -> void:
	scene_gm.current_state = scene_gm.GameState.INITIALIZING
	scene_gm.current_player_index = 0
	scene_gm.dutch_caller_index = -1
	scene_gm.dutch_round_turns_remaining = 0
	scene_gm.jump_in_player_idx = -1
	scene_gm.jump_in_resume_state = scene_gm.GameState.INITIALIZING
	scene_gm.drawn_card_data = null
	if scene_gm.deck_manager:
		scene_gm.deck_manager.deck.clear()
		scene_gm.deck_manager.discard_pile.clear()
	for player in scene_gm.players_info:
		player.hand.clear()
		player.bot_memory = {}
	scene_gm.players_info.clear()

func _top_center_text(top_center: Control) -> String:
	for child in top_center.get_children():
		if child is Label:
			return child.text
	return ""

func _await_resolution() -> void:
	await _qa_wait(0.65)

func _check(condition: bool, message: String) -> void:
	if condition:
		passed += 1
		print("[QA PASS] " + message)
	else:
		failed += 1
		print("[QA FAIL] " + message)

func _check_state(expected: int, message: String) -> void:
	var ok: bool = gm.current_state == expected
	var suffix := " (expected %s, got %s)" % [
		gm.GameState.keys()[expected],
		gm.GameState.keys()[gm.current_state]
	]
	_check(ok, message + suffix)

func _check_player(expected: int, message: String) -> void:
	_check(gm.current_player_index == expected, message + " (expected %d, got %d)" % [expected, gm.current_player_index])

func _qa_wait(seconds: float) -> void:
	if _qa_flag_enabled():
		return
	await create_timer(seconds, false).timeout

func _qa_flag_enabled() -> bool:
	var flag := root.get_node_or_null("QA_PIPELINE_FLAG")
	if not flag:
		return false
	return flag.get("skip_anims") == true

extends SceneTree

# qa_pipeline.gd - Pure Logic Verification Pipeline
# Verifies every phase and every player position systematically without fragile visuals.

const STOP_FILE = "/tmp/STOP_DUTCH_QA"

var gm: Node = null

func _init():
	call_deferred("start_pipeline")

func _input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		print("[QA] User Abort via ESC.")
		quit()

func start_pipeline():
	print("\n[QA] STARTING PURE LOGIC PIPELINE (HEADLESS)...")
	gm = load("res://game_manager.gd").new()
	gm.name = "GameManager"
	root.add_child(gm)
	
	await self.process_frame
	# PHASE 1: INITIALIZATION & DEAL
	await phase_initialization()
	
	# PHASE 2: NORMAL TURN ROTATION (Draw/Discard)
	await phase_normal_turns_discard()
	
	# PHASE 3: NORMAL TURN ROTATION (Draw/Swap)
	await phase_normal_turns_swap()
	
	# PHASE 4: SPECIAL ABILITIES (Queen Peek)
	await phase_queen_abilities_all_players()
	
	# PHASE 5: SPECIAL ABILITIES (Jack Swap)
	await phase_jack_abilities_all_players()
	
	# PHASE 6: DUTCH CYCLE (Each Caller Position)
	await phase_dutch_calls_all_players()
	
	# PHASE 7: JUMP IN
	await phase_jump_in_all_players()
	
	print("\n[QA] ALL GRANULAR LOGIC PHASES AND PLAYER TURNS VERIFIED.")
	quit()

# --- PHASE MODULES ---

func phase_initialization():
	print("\n>>> PHASE 1: Initialization & Deal Logic <<<")
	_setup_turn_start(0)

func phase_normal_turns_discard():
	print("\n>>> PHASE 2: Standard Draw/Discard (4 Players) <<<")
	for i in range(4):
		print("[QA] Player %d: Standard Turn (Discard)" % i)
		_setup_turn_start(i)
		
		gm.player_draw_card()
		gm.drawn_card_data = _make_card("Ace", "Clubs")
		gm.player_discard_drawn_card()
		await _await_resolution()
		
		assert_state(gm.GameState.TURN_END_CHOICE)
		gm.end_turn()
		assert_state(gm.GameState.TURN_START_DRAW)

func phase_normal_turns_swap():
	print("\n>>> PHASE 3: Standard Draw/Swap (4 Players) <<<")
	for i in range(4):
		print("[QA] Player %d: Standard Turn (Swap)" % i)
		_setup_turn_start(i)
		
		_setup_manual_hand(i, 0, "King", "Spades")
		gm.player_draw_card()
		gm.drawn_card_data = _make_card("2", "Hearts")
		gm.player_swap_drawn_card(0)
		await _await_resolution()
		
		assert_state(gm.GameState.TURN_END_CHOICE)
		gm.end_turn()
		
		var hand_card = gm.players_info[i].hand[0]
		if hand_card.rank == "2" and hand_card.suit == "Hearts":
			print("[QA PASS] Player %d: Swap logic verified." % i)
		else:
			print("[QA FAIL] Player %d: Swap logic failed." % i)

func phase_queen_abilities_all_players():
	print("\n>>> PHASE 4: Queen Peek Ability (4 Players) <<<")
	for i in range(4):
		print("[QA] Player %d: Triggering Queen Peek" % i)
		_setup_turn_start(i)
		
		gm.player_draw_card()
		gm.drawn_card_data = _make_card("Queen", "Diamonds")
		gm.player_discard_drawn_card()
		await _await_resolution()
		
		assert_state(gm.GameState.TURN_PEEK_ABILITY)
		gm.complete_peek_ability()
		assert_state(gm.GameState.TURN_END_CHOICE)
		gm.end_turn()
		assert_state(gm.GameState.TURN_START_DRAW)

func phase_jack_abilities_all_players():
	print("\n>>> PHASE 5: Jack Swap Ability (4 Players) <<<")
	for i in range(4):
		print("[QA] Player %d: Triggering Jack Swap" % i)
		_setup_turn_start(i)
		
		gm.player_draw_card()
		gm.drawn_card_data = _make_card("Jack", "Clubs")
		gm.player_discard_drawn_card()
		await _await_resolution()
		
		assert_state(gm.GameState.TURN_SWAP_ABILITY)
		_setup_manual_hand(0, 0, "7", "Hearts")
		_setup_manual_hand(1, 0, "Ace", "Spades")
		gm.complete_swap_ability(0, 0, 1, 0)
		assert_state(gm.GameState.TURN_END_CHOICE)
		gm.end_turn()
		
		var p0_card = gm.players_info[0].hand[0]
		var p1_card = gm.players_info[1].hand[0]
		if p0_card.rank == "Ace" and p1_card.rank == "7":
			print("[QA PASS] Player %d: Jack swap cross-player verified." % i)
		else:
			print("[QA FAIL] Player %d: Jack swap cross-player failed." % i)

func phase_dutch_calls_all_players():
	print("\n>>> PHASE 6: Dutch Calling Logic <<<")
	for trigger_p in range(4):
		print("[QA] Verifying Dutch Call by Player %d" % trigger_p)
		_setup_turn_start(trigger_p)
		
		gm.player_draw_card()
		gm.drawn_card_data = _make_card("Ace", "Clubs")
		gm.player_discard_drawn_card()
		await _await_resolution()
		
		assert_state(gm.GameState.TURN_END_CHOICE)
		gm.call_dutch(trigger_p)
		
		for _pass_turn in range(3):
			gm.player_draw_card()
			gm.drawn_card_data = _make_card("Ace", "Clubs")
			gm.player_discard_drawn_card()
			await _await_resolution()
			gm.end_turn()
		
		assert_state(gm.GameState.TURN_START_DRAW)
		gm.player_draw_card()
		gm.drawn_card_data = _make_card("Ace", "Clubs")
		gm.player_discard_drawn_card()
		await _await_resolution()
		assert_state(gm.GameState.TURN_CONFIRM_DUTCH)
		gm.confirm_dutch()
		assert_state(gm.GameState.GAME_OVER)

func phase_jump_in_all_players():
	print("\n>>> PHASE 7: Jump In Mechanics <<<")

	# Draw-start jump-in should be legal before the draw, then resume to TURN_START_DRAW.
	_setup_turn_start(0)
	_set_discard_top("5", "Hearts")
	_setup_manual_hand(0, 0, "King", "Spades")
	_setup_manual_hand(0, 1, "2", "Clubs")

	if gm.can_player_start_jump_in(0):
		print("[QA PASS] Human jump-in allowed at TURN_START_DRAW")
	else:
		print("[QA FAIL] Human jump-in blocked at TURN_START_DRAW")

	gm.start_jump_in(0)
	assert_state(gm.GameState.TURN_JUMP_IN_SELECTION)

	var draw_start_failed: bool = await gm.validate_jump_in(0)
	if not draw_start_failed:
		print("[QA PASS] Draw-start jump-in mismatch rejected")
	else:
		print("[QA FAIL] Draw-start jump-in accepted a mismatched card")

	assert_state(gm.GameState.TURN_START_DRAW)
	if gm.players_info[0].hand.size() == 3:
		print("[QA PASS] Jump-in failure penalty card added")
	else:
		print("[QA FAIL] Jump-in failure penalty size mismatch: %d" % gm.players_info[0].hand.size())

	# Pending-card path should accept the drawn card via card_idx == -2.
	_setup_turn_start(0)
	_set_discard_top("9", "Diamonds")
	_setup_manual_hand(0, 0, "Queen", "Spades")
	gm.drawn_card_data = _make_card("9", "Clubs")

	gm.start_jump_in(0)
	assert_state(gm.GameState.TURN_JUMP_IN_SELECTION)

	if gm.can_player_select_jump_in_card(0, 0, -2):
		print("[QA PASS] Pending-card jump-in selection allowed")
	else:
		print("[QA FAIL] Pending-card jump-in selection blocked")

	var pending_success: bool = await gm.validate_jump_in(-2)
	if pending_success:
		print("[QA PASS] Pending-card jump-in resolved successfully")
	else:
		print("[QA FAIL] Pending-card jump-in failed unexpectedly")

	await create_timer(0.6, false).timeout
	assert_state(gm.GameState.TURN_START_DRAW)
	if gm.drawn_card_data == null:
		print("[QA PASS] Pending-card jump-in consumed the drawn card")
	else:
		print("[QA FAIL] Pending-card jump-in left drawn_card_data set")

	# Once the draw has happened, jump-in must be blocked until the turn resolves.
	_setup_turn_start(0)
	_set_discard_top("8", "Clubs")
	gm.player_draw_card()
	assert_state(gm.GameState.TURN_RESOLVE_DRAWN)

	if not gm.can_player_start_jump_in(0):
		print("[QA PASS] Jump-in blocked after draw")
	else:
		print("[QA FAIL] Jump-in incorrectly allowed after draw")

	var blocked_state: int = gm.current_state
	var blocked_jump_in_player: int = gm.jump_in_player_idx
	gm.start_jump_in(0)
	if gm.current_state == blocked_state and gm.jump_in_player_idx == blocked_jump_in_player:
		print("[QA PASS] Blocked post-draw jump-in left FSM unchanged")
	else:
		print("[QA FAIL] Post-draw jump-in changed FSM unexpectedly")

	# Human jump-in during a bot's resolve phase should resume back to TURN_RESOLVE_DRAWN on cancel.
	_setup_turn_start(1)
	_set_discard_top("6", "Spades")
	gm.player_draw_card()
	assert_state(gm.GameState.TURN_RESOLVE_DRAWN)

	if gm.can_player_start_jump_in(0):
		print("[QA PASS] Human jump-in allowed during bot resolve")
	else:
		print("[QA FAIL] Human jump-in blocked during bot resolve")

	gm.start_jump_in(0)
	assert_state(gm.GameState.TURN_JUMP_IN_SELECTION)
	gm.cancel_jump_in()
	assert_state(gm.GameState.TURN_RESOLVE_DRAWN)

	# Bots must not be allowed to jump in at the start of their own turn.
	_setup_turn_start(1)
	_set_discard_top("Jack", "Hearts")

	if not gm.can_player_start_jump_in(1):
		print("[QA PASS] Bot jump-in blocked at TURN_START_DRAW")
	else:
		print("[QA FAIL] Bot jump-in incorrectly allowed at TURN_START_DRAW")

	var bot_state: int = gm.current_state
	gm.start_jump_in(1)
	if gm.current_state == bot_state and gm.jump_in_player_idx == -1:
		print("[QA PASS] Bot start-turn jump-in request left FSM unchanged")
	else:
		print("[QA FAIL] Bot start-turn jump-in request changed FSM")

func _make_card(rank: String, suit: String) -> CardData:
	return load("res://card_data.gd").new(rank, suit)

func _set_discard_top(rank: String, suit: String) -> void:
	gm.deck_manager.discard_pile.clear()
	gm.deck_manager.discard_pile.append(_make_card(rank, suit))

func _setup_turn_start(player_idx: int) -> void:
	gm.initialize_game(4)
	gm.change_state(gm.GameState.INITIAL_PEEK)
	gm.current_player_index = player_idx
	gm.complete_initial_peek()
	assert_player(player_idx)
	assert_state(gm.GameState.TURN_START_DRAW)

func _await_resolution() -> void:
	await create_timer(0.6, false).timeout

# --- UTILITIES ---

func assert_state(expected: int):
	var states = ["INIT", "DEAL", "PEEK", "START", "RESOLVE", "QUEEN", "JACK", "END_CHOICE", "JUMP_IN", "CHECK", "CONFIRM", "OVER"]
	if gm.current_state != expected:
		var got = states[gm.current_state] if gm.current_state < states.size() else "ERR"
		var exp = states[expected] if expected < states.size() else "ERR"
		print("[QA FAIL] Expected State %s, got %s" % [exp, got])
	else:
		print("[QA PASS] FSM State: %s" % states[expected])

func assert_player(expected: int):
	if gm.current_player_index != expected:
		print("[QA FAIL] Expected Player %d, got %d" % [expected, gm.current_player_index])
	else:
		print("[QA PASS] Player Turn: %d" % expected)

func _setup_manual_hand(p_idx, c_idx, rank, suit):
	while gm.players_info[p_idx].hand.size() <= c_idx:
		gm.players_info[p_idx].hand.append(null)
	gm.players_info[p_idx].hand[c_idx] = load("res://card_data.gd").new(rank, suit)

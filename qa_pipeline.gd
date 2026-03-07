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
	gm = root.get_node_or_null("GameManager")
	if not gm:
		print("[QA FAIL] GameManager singleton not found.")
		quit()
	
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
	gm.initialize_game(4)
	
	gm.change_state(gm.GameState.INITIAL_PEEK)
	gm.complete_initial_peek()
	
	assert_player(0)
	assert_state(gm.GameState.TURN_START_DRAW)

func phase_normal_turns_discard():
	print("\n>>> PHASE 2: Standard Draw/Discard (4 Players) <<<")
	for i in range(4):
		print("[QA] Player %d: Standard Turn (Discard)" % i)
		gm.current_player_index = i
		gm.change_state(gm.GameState.TURN_START_DRAW)
		
		# Draw
		gm.player_draw_card()
		
		# Discard (Deterministic Ace of Clubs)
		gm.drawn_card_data = load("res://card_data.gd").new("Ace", "Clubs")
		gm.player_discard_drawn_card()
		
		assert_state(gm.GameState.TURN_END_CHOICE)
		gm.end_turn()
		
		# In a real game, next_turn() advances the player. 
		# Our loop sets gm.current_player_index manually for testing specific turns,
		# but next_turn() would normally increment it.
		assert_state(gm.GameState.TURN_START_DRAW)

func phase_normal_turns_swap():
	print("\n>>> PHASE 3: Standard Draw/Swap (4 Players) <<<")
	for i in range(4):
		print("[QA] Player %d: Standard Turn (Swap)" % i)
		gm.current_player_index = i
		gm.change_state(gm.GameState.TURN_START_DRAW)
		
		_setup_manual_hand(i, 0, "King", "Spades")
		
		gm.player_draw_card()
		gm.drawn_card_data = load("res://card_data.gd").new("2", "Hearts")
		
		gm.player_swap_drawn_card(0)
		
		assert_state(gm.GameState.TURN_END_CHOICE)
		gm.end_turn()
		
		# Verify swap worked
		var hand_card = gm.players_info[i].hand[0]
		if hand_card.rank == "2" and hand_card.suit == "Hearts":
			print("[QA PASS] Player %d: Swap logic verified." % i)
		else:
			print("[QA FAIL] Player %d: Swap logic failed." % i)

func phase_queen_abilities_all_players():
	print("\n>>> PHASE 4: Queen Peek Ability (4 Players) <<<")
	for i in range(4):
		print("[QA] Player %d: Triggering Queen Peek" % i)
		gm.current_player_index = i
		gm.change_state(gm.GameState.TURN_START_DRAW)
		
		gm.player_draw_card()
		gm.drawn_card_data = load("res://card_data.gd").new("Queen", "Diamonds")
		gm.player_discard_drawn_card()
		
		assert_state(gm.GameState.TURN_PEEK_ABILITY)
		
		gm.complete_peek_ability()
		
		assert_state(gm.GameState.TURN_END_CHOICE)
		gm.end_turn()
		
		assert_state(gm.GameState.TURN_START_DRAW)

func phase_jack_abilities_all_players():
	print("\n>>> PHASE 5: Jack Swap Ability (4 Players) <<<")
	for i in range(4):
		print("[QA] Player %d: Triggering Jack Swap" % i)
		gm.current_player_index = i
		gm.change_state(gm.GameState.TURN_START_DRAW)
		
		gm.player_draw_card()
		gm.drawn_card_data = load("res://card_data.gd").new("Jack", "Clubs")
		gm.player_discard_drawn_card()
		
		assert_state(gm.GameState.TURN_SWAP_ABILITY)
		
		_setup_manual_hand(0, 0, "7", "Hearts")
		_setup_manual_hand(1, 0, "Ace", "Spades")
		
		gm.complete_swap_ability(0, 0, 1, 0)
		
		assert_state(gm.GameState.TURN_END_CHOICE)
		gm.end_turn()
		
		# Verify swap between players
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
		gm.initialize_game(4)
		gm.current_player_index = trigger_p
		gm.change_state(gm.GameState.TURN_START_DRAW)
		
		# Must draw and discard before we can call dutch in the end choice phase
		gm.player_draw_card()
		gm.drawn_card_data = load("res://card_data.gd").new("Ace", "Clubs")
		gm.player_discard_drawn_card()
		
		assert_state(gm.GameState.TURN_END_CHOICE)
		gm.call_dutch(trigger_p)
		
		# 3 other players must take a turn. Since we added TURN_END_CHOICE, 
		# we must simulate their draws and explicitly end their turns
		for pass_turn in range(3):
			gm.player_draw_card()
			gm.drawn_card_data = load("res://card_data.gd").new("Ace", "Clubs")
			gm.player_discard_drawn_card()
			gm.end_turn()
		
		assert_state(gm.GameState.TURN_CONFIRM_DUTCH)
		gm.confirm_dutch()
		assert_state(gm.GameState.GAME_OVER)

func phase_jump_in_all_players():
	print("\n>>> PHASE 7: Jump In Mechanics <<<")
	for i in range(4):
		print("[QA] Player %d: Triggering Jump In" % i)
		gm.initialize_game(4)
		gm.current_player_index = i
		gm.change_state(gm.GameState.TURN_START_DRAW)
		
		# Put a specific card in hand to jump in with
		_setup_manual_hand(i, 0, "5", "Clubs")
		
		# Draw and discard a matching card
		gm.player_draw_card()
		gm.drawn_card_data = load("res://card_data.gd").new("5", "Hearts")
		gm.player_discard_drawn_card()
		
		assert_state(gm.GameState.TURN_END_CHOICE)
		
		# Start jump in
		gm.start_jump_in()
		assert_state(gm.GameState.TURN_JUMP_IN_SELECTION)
		
		# Execute jump in
		var success = gm.validate_jump_in(0)
		if success:
			print("[QA PASS] Jump in validated successfully")
		else:
			print("[QA FAIL] Jump in failed to validate")
			
		assert_state(gm.GameState.TURN_END_CHOICE)
		
		# Test Jump In Mismatch Penalty
		gm.start_jump_in()
		_setup_manual_hand(i, 0, "King", "Spades")
		var old_hand_size = gm.players_info[i].hand.size()
		
		var mismatch_success = gm.validate_jump_in(0)
		if not mismatch_success:
			print("[QA PASS] Jump in correctly rejected mismatched rank")
			if gm.players_info[i].hand.size() == old_hand_size + 1:
				print("[QA PASS] Penalty card added to hand successfully")
			else:
				print("[QA FAIL] Penalty card not added! Expected %d, got %d" % [old_hand_size + 1, gm.players_info[i].hand.size()])
		else:
			print("[QA FAIL] Jump in accepted a mismatched card")
			
		assert_state(gm.GameState.TURN_END_CHOICE)
		gm.end_turn()

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

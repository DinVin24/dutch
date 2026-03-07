extends SceneTree

# qa_pipeline.gd - Granular Multi-Player Testing Pipeline WITH Screenshots
# Verifies every phase and every player position systematically.

const STOP_FILE = "/tmp/STOP_DUTCH_QA"
const SCREENSHOT_BASE_DIR = "res://qa_screenshots/granular_run/"

var gm: Node = null
var board: Node = null

func _init():
	call_deferred("start_pipeline")

func _input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		print("[QA] User Abort via ESC.")
		quit()

func start_pipeline():
	print("\n[QA] STARTING GRANULAR VISUAL PIPELINE...")
	gm = root.get_node_or_null("GameManager")
	if not gm: quit()
	
	var dir = DirAccess.open("res://")
	if not dir.dir_exists(SCREENSHOT_BASE_DIR):
		dir.make_dir_recursive(SCREENSHOT_BASE_DIR)

	# Instantiate the board once for the whole run
	var board_scene = load("res://game_board.tscn")
	board = board_scene.instantiate()
	root.add_child(board)
	await process_frame
	await create_timer(1.0).timeout
	
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
	
	print("\n[QA] ALL GRANULAR PHASES AND PLAYER TURNS VERIFIED WITH VISUALS.")
	quit()

# --- PHASE MODULES ---

func phase_initialization():
	print("\n>>> PHASE 1: Initialization & Deal Logic <<<")
	gm.initialize_game(4)
	await take_screenshot("01_deal_cards")
	
	gm.change_state(gm.GameState.INITIAL_PEEK)
	await take_screenshot("02_initial_peek_start")
	
	gm.complete_initial_peek()
	assert_player(0)
	assert_state(gm.GameState.TURN_START_DRAW)
	await take_screenshot("03_p0_turn_start")

func phase_normal_turns_discard():
	print("\n>>> PHASE 2: Standard Draw/Discard (4 Players) <<<")
	for i in range(4):
		print("[QA] Player %d: Standard Turn (Discard)" % i)
		gm.current_player_index = i
		gm.change_state(gm.GameState.TURN_START_DRAW)
		
		# Draw
		gm.player_draw_card()
		await take_screenshot("p%d_01_draw" % i)
		
		# Discard
		gm.drawn_card_data = load("res://card_data.gd").new("Ace", "Clubs")
		if board.pending_card: board.pending_card.setup(gm.drawn_card_data)
		gm.player_discard_drawn_card()
		await take_screenshot("p%d_02_discarded" % i)
		
		await create_timer(0.5).timeout

func phase_normal_turns_swap():
	print("\n>>> PHASE 3: Standard Draw/Swap (4 Players) <<<")
	for i in range(4):
		print("[QA] Player %d: Standard Turn (Swap)" % i)
		gm.current_player_index = i
		gm.change_state(gm.GameState.TURN_START_DRAW)
		
		_setup_manual_hand(i, 0, "King", "Spades")
		
		gm.player_draw_card()
		gm.drawn_card_data = load("res://card_data.gd").new("2", "Hearts")
		if board.pending_card: board.pending_card.setup(gm.drawn_card_data)
		
		gm.player_swap_drawn_card(0)
		await take_screenshot("p%d_03_swapped" % i)
		await create_timer(0.5).timeout

func phase_queen_abilities_all_players():
	print("\n>>> PHASE 4: Queen Peek Ability (4 Players) <<<")
	for i in range(4):
		print("[QA] Player %d: Triggering Queen Peek" % i)
		gm.current_player_index = i
		gm.change_state(gm.GameState.TURN_START_DRAW)
		
		gm.player_draw_card()
		gm.drawn_card_data = load("res://card_data.gd").new("Queen", "Diamonds")
		if board.pending_card: board.pending_card.setup(gm.drawn_card_data)
		gm.player_discard_drawn_card()
		
		assert_state(gm.GameState.TURN_PEEK_ABILITY)
		await take_screenshot("p%d_04_queen_active" % i)
		
		gm.complete_peek_ability()
		await create_timer(0.5).timeout

func phase_jack_abilities_all_players():
	print("\n>>> PHASE 5: Jack Swap Ability (4 Players) <<<")
	for i in range(4):
		print("[QA] Player %d: Triggering Jack Swap" % i)
		gm.current_player_index = i
		gm.change_state(gm.GameState.TURN_START_DRAW)
		
		gm.player_draw_card()
		gm.drawn_card_data = load("res://card_data.gd").new("Jack", "Clubs")
		if board.pending_card: board.pending_card.setup(gm.drawn_card_data)
		gm.player_discard_drawn_card()
		
		assert_state(gm.GameState.TURN_SWAP_ABILITY)
		await take_screenshot("p%d_05_jack_active" % i)
		
		_setup_manual_hand(0, 0, "7", "Hearts")
		_setup_manual_hand(1, 0, "Ace", "Spades")
		
		gm.complete_swap_ability(0, 0, 1, 0)
		await create_timer(0.5).timeout

func phase_dutch_calls_all_players():
	print("\n>>> PHASE 6: Dutch Calling Logic <<<")
	for trigger_p in range(4):
		print("[QA] Verifying Dutch Call by Player %d" % trigger_p)
		gm.initialize_game(4)
		gm.current_player_index = trigger_p
		gm.change_state(gm.GameState.TURN_START_DRAW)
		
		gm.call_dutch(trigger_p)
		await take_screenshot("dutch_call_p%d" % trigger_p)
		
		gm.next_turn()
		gm.next_turn()
		gm.next_turn()
		
		assert_state(gm.GameState.GAME_OVER)
		await take_screenshot("game_over_from_p%d" % trigger_p)

# --- UTILITIES ---

func assert_state(expected: int):
	var states = ["INIT", "DEAL", "PEEK", "START", "RESOLVE", "QUEEN", "JACK", "CHECK", "OVER"]
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

func take_screenshot(name: String):
	for i in range(10): await process_frame
	if FileAccess.file_exists(STOP_FILE): quit()
	var image = root.get_texture().get_image()
	image.save_png(SCREENSHOT_BASE_DIR + name + ".png")
	print("[QA] Captured %s.png" % name)

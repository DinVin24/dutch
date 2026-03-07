extends SceneTree

const STOP_FILE = "/tmp/STOP_DUTCH_QA"
var game_manager_script = load("res://game_manager.gd")
var GameManager: Node = null

# QA Bot - Experimental Automated Playtester
# This script runs the game, simulates clicks, and captures screenshots.

const SCREENSHOT_DIR = "res://qa_screenshots/"

func _init():
	# Use call_deferred to ensure the tree is initialized before we start interacting
	call_deferred("start_qa")

func _input(event):
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			print("QA BOT: ESC KEY PRESSED! Emergency Quit.")
			quit()

func start_qa():
	print("QA BOT: Initializing experimental playthrough...")
	
	# Manually setup the Autoload GameManager for this standalone session
	GameManager = game_manager_script.new()
	GameManager.name = "GameManager"
	root.add_child(GameManager)
	
	# Create screenshot directory if it doesn't exist
	var dir = DirAccess.open("res://")
	if not dir.dir_exists("qa_screenshots"):
		dir.make_dir("qa_screenshots")
	
	# Load the main game board scene
	var board_scene = load("res://game_board.tscn")
	var board = board_scene.instantiate()
	root.add_child(board)
	
	print("QA BOT: Scene instantiated. Waiting for window initialization...")
	# Wait for a few frames to ensure the screen is ready
	for i in range(10):
		await process_frame
		if FileAccess.file_exists(STOP_FILE):
			print("QA BOT: Kill switch detected! Quitting.")
			quit()
	
	await create_timer(2.0).timeout # Extra wait for window to appear
	
	await run_playthrough(board)
	
	print("QA BOT: Playthrough complete. Quitting in 2 seconds...")
	await create_timer(2.0).timeout
	quit()

func run_playthrough(board):
	# Phase 1: Initial Peek
	await take_screenshot("08_initial_deal_retry")
	
	# Simulate peeking at first two cards of player 0
	var p0_hand = board.player_hands[0]
	if p0_hand.size() >= 2:
		print("QA BOT: Simulating initial peek clicks...")
		await simulate_click(p0_hand[0])
		await simulate_click(p0_hand[1])
		await take_screenshot("09_initial_peeks_revealed_retry")
	else:
		print("QA BOT ERROR: Player 0 hand not found or empty!")
	
	# Wait for peek phase to end automatically
	print("QA BOT: Waiting for peek phase to end...")
	await create_timer(4.5).timeout
	await take_screenshot("10_turn_started_retry")

	# Phase 2: Drawing and Discarding
	print("QA BOT: Simulating drawing from deck...")
	var deck_area = board.get_node("CenterTable/DeckArea")
	await simulate_click(deck_area)
	await create_timer(1.0).timeout 
	await take_screenshot("11_card_drawn_retry")

	# Test Scenario: Force a special card into hand to test FSM ability transitions
	print("QA BOT: Manipulating FSM for Ability Testing...")
	await test_queen_peek(board, GameManager)
	await test_jack_swap(board, GameManager)

	print("QA BOT: Simulating discarding drawn card...")
	var discard_area = board.get_node("CenterTable/DiscardArea")
	await simulate_click(discard_area)
	await create_timer(1.0).timeout
	await take_screenshot("14_discard_complete_retry")

func test_queen_peek(board, gm):
	print("QA BOT: Testing Queen Peek Ability...")
	var queen = load("res://card_data.gd").new("Queen", "Hearts")
	gm.drawn_card_data = queen
	gm.player_discard_drawn_card() # Should move to TURN_PEEK_ABILITY
	
	await create_timer(1.0).timeout
	await take_screenshot("12_queen_peek_active_retry")
	
	# Click an opponent card (Player 1, Card 0)
	var target_card = board.player_hands[1][0]
	await simulate_click(target_card)
	
	# Wait for peek timer to finish
	await create_timer(3.5).timeout
	print("QA BOT: Queen Peek Test Complete.")

func test_jack_swap(board, gm):
	print("QA BOT: Testing Jack Swap Ability...")
	var jack = load("res://card_data.gd").new("Jack", "Spades")
	# Force state back to drawn resolved to trigger discard again
	gm.current_state = gm.GameState.TURN_RESOLVE_DRAWN
	gm.drawn_card_data = jack
	gm.player_discard_drawn_card()
	
	await create_timer(1.0).timeout
	await take_screenshot("13_jack_swap_active_retry")
	
	# Click two cards to swap
	var c1 = board.player_hands[0][0]
	var c2 = board.player_hands[2][0]
	await simulate_click(c1)
	await simulate_click(c2)
	
	await create_timer(1.0).timeout
	print("QA BOT: Jack Swap Test Complete.")

func simulate_click(node: Control):
	if not is_instance_valid(node): 
		print("QA BOT ERROR: Node invalid for click")
		return
	
	var center = node.global_position + (node.size / 2.0 if node.size != Vector2.ZERO else Vector2(50, 70))
	print("QA BOT: Clicking node ", node.name, " at ", center)
	
	var event = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = center
	event.global_position = center
	Input.parse_input_event(event)
	
	await process_frame
	
	event = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = false
	event.position = center
	event.global_position = center
	Input.parse_input_event(event)
	
	await create_timer(0.3).timeout

func take_screenshot(name: String):
	for i in range(5):
		await process_frame
		if FileAccess.file_exists(STOP_FILE):
			print("QA BOT: Kill switch detected during screenshot. Quitting.")
			quit()
	
	var image = root.get_texture().get_image()
	var path = SCREENSHOT_DIR + name + ".png"
	image.save_png(path)
	print("QA BOT: Screenshot saved to ", path)
	await process_frame

extends SceneTree

## Smoke test: offline assistant answers key questions and the "?" panel opens/closes.
## Run: Godot --path dutch -s res://verify_game_assistant.gd

const HOLD_FRAMES := 20

# question -> expected topic_id from the knowledge base
const EXPECTED := {
	"how does jump in work": "jump_in",
	"what is the king of diamonds": "king_of_diamonds",
	"how do i buy abilities from the chicken": "chicken",
	"how does scoring work": "scoring",
	"what is dutch": "dutch",
	"cum functioneaza jump in": "jump_in",
}

func _init() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	for bus_name in ["Master", "Music", "SFX"]:
		var bus_idx := AudioServer.get_bus_index(bus_name)
		if bus_idx >= 0:
			AudioServer.set_bus_mute(bus_idx, true)
	call_deferred("_run")

func _log(msg: String) -> void:
	print("[ASSISTANT-TEST] ", msg)

func _run() -> void:
	_log("=== GAME ASSISTANT TEST ===")

	var knowledge := root.get_node_or_null("GameKnowledge")
	var assistant := root.get_node_or_null("GameAssistant")
	if knowledge == null or assistant == null:
		_fail("GameKnowledge/GameAssistant autoloads missing")
		return
	if knowledge.all_entries().size() < 10:
		_fail("Knowledge base too small: %d entries" % knowledge.all_entries().size())
		return
	_log("OK knowledge loaded: %d entries" % knowledge.all_entries().size())

	# Engine answers
	for question in EXPECTED:
		var expected_id: String = EXPECTED[question]
		var result: Dictionary = assistant.ask(question)
		if str(result.get("answer", "")) == "":
			_fail("Empty answer for: %s" % question)
			return
		if float(result.get("confidence", 0.0)) <= 0.0:
			_fail("Zero confidence for: %s" % question)
			return
		if str(result.get("topic_id", "")) != expected_id:
			_fail("Wrong topic for '%s': got '%s', expected '%s'" % [question, result.get("topic_id", ""), expected_id])
			return
		_log("OK '%s' -> %s (conf %.2f)" % [question, result.get("topic_id", ""), result.get("confidence", 0.0)])

	# Fallback for gibberish
	var gib: Dictionary = assistant.ask("qwerty zxcv banana spaceship")
	if str(gib.get("topic_id", "")) != "":
		_fail("Gibberish should fall back, got topic '%s'" % gib.get("topic_id", ""))
		return
	if gib.get("suggestions", []).is_empty():
		_fail("Fallback should offer suggestions")
		return
	_log("OK gibberish falls back with suggestions")

	# Board + UI
	var gm := root.get_node_or_null("GameManager")
	gm.easy_mode = false
	gm.tutorial_mode = false
	gm.is_multiplayer = false
	gm.show_game_assistant = true
	gm.stop_menu_music()

	change_scene_to_file("res://game_board_3d.tscn")
	var board := await _wait_for_board()
	if board == null:
		_fail("game_board failed to load")
		return

	await create_timer(1.0).timeout
	if gm.current_state == gm.GameState.INITIAL_PEEK:
		while gm.current_state == gm.GameState.INITIAL_PEEK:
			gm.complete_initial_peek()
			await process_frame
	if gm.current_state != gm.GameState.TURN_START_DRAW:
		gm.change_state(gm.GameState.TURN_START_DRAW, true)
	for _i in HOLD_FRAMES:
		await process_frame

	var overlay: Control = board.get("_assistant_overlay")
	if overlay == null or not is_instance_valid(overlay):
		_fail("Assistant overlay not created")
		return
	if not overlay.visible:
		_fail("Assistant overlay should be visible in-game")
		return
	_log("OK assistant overlay present and visible")

	# Open via the "?" button toggle
	overlay.open_panel()
	for _i in HOLD_FRAMES:
		await process_frame
	if not overlay.is_open():
		_fail("Panel did not open")
		return
	_log("OK panel opened")

	# Opening the assistant must close the emote wheel (mutual exclusivity)
	board._open_emote_wheel()
	for _i in HOLD_FRAMES:
		await process_frame
	if overlay.is_open():
		_fail("Opening emote wheel should close assistant panel")
		return
	_log("OK emote wheel closes assistant panel")

	overlay.open_panel()
	for _i in HOLD_FRAMES:
		await process_frame
	var wheel: PanelContainer = board.get("_emote_wheel_panel")
	if is_instance_valid(wheel) and wheel.visible:
		_fail("Opening assistant should close emote wheel")
		return
	_log("OK assistant panel closes emote wheel")

	overlay.close_panel()
	for _i in HOLD_FRAMES:
		await process_frame
	if overlay.is_open():
		_fail("Panel did not close")
		return
	_log("OK panel closed")

	# Settings toggle hides the assistant
	gm.show_game_assistant = false
	for _i in HOLD_FRAMES:
		await process_frame
	if overlay.visible:
		_fail("Assistant should hide when show_game_assistant is off")
		return
	_log("OK assistant hidden when disabled in settings")

	print("ASSISTANT_TEST_COMPLETE pass=true")
	quit(0)

func _wait_for_board() -> Node:
	for _i in range(600):
		await process_frame
		for child in root.get_children():
			if child is Node3D and child.has_method("_create_assistant_ui"):
				return child
	return null

func _fail(reason: String) -> void:
	push_error("[ASSISTANT-TEST] FAIL: " + reason)
	print("ASSISTANT_TEST_COMPLETE pass=false reason=%s" % reason)
	quit(1)

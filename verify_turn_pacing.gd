extends SceneTree

## Visual demo for single-player bot pacing + turn handoff VFX.
## Run from terminal:
##   .\run_godot.ps1 -GodotArgs "-s","res://verify_turn_pacing.gd"
## Or from Godot editor: Project -> Run with argument -s res://verify_turn_pacing.gd

const HOLD_AFTER_DEMO := 30.0

func _init() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	call_deferred("_run")

func _log(msg: String) -> void:
	print("[TURN-PACING] ", msg)

func _run() -> void:
	_log("=== TURN PACING DEMO ===")
	_log("Watch for: slower bot moves + cyan burst when turn changes.")
	_log("Your turns are auto-played so bots keep cycling.")

	var gm := get_root().get_node("GameManager")
	gm.easy_mode = false
	gm.tutorial_mode = false
	gm.is_multiplayer = false
	gm.stop_menu_music()

	gm.turn_started.connect(func(idx: int) -> void:
		_log("Turn handoff -> Player %d (%s)" % [idx, gm.players_info[idx].name])
	)
	gm.bot_action.connect(func(msg: String) -> void:
		_log("Bot: %s" % msg)
	)

	change_scene_to_file("res://game_board_3d.tscn")
	var board := await _wait_for_board()
	if board == null:
		_log("ERROR: game board failed to load")
		quit(1)
		return

	await create_timer(1.0).timeout
	var driver: Node = load("res://playthrough_driver.gd").new()
	board.add_child(driver)

	_log("Demo running — 3 full rounds then hold for %.0fs..." % HOLD_AFTER_DEMO)
	await driver.start(board)
	await create_timer(HOLD_AFTER_DEMO).timeout
	_log("=== DEMO FINISHED ===")
	quit(0)

func _wait_for_board() -> Node3D:
	for _i in range(600):
		await process_frame
		for child in root.get_children():
			if child is Node3D and child.has_method("_on_card_clicked"):
				return child
	return null

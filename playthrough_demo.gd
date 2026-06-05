extends SceneTree

## Full-game visual demo: press any key -> menu -> match -> victory.
## Run: D:\Godot\Godot_v4.6.2-stable_win64.exe --path dutch -s res://playthrough_demo.gd

const VICTORY_HOLD := 18.0
const PEEK_DELAY := 2.5

func _init() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	call_deferred("_run")

func _log(msg: String) -> void:
	print("[DEMO] ", msg)

func _run() -> void:
	_log("=== FULL PLAYTHROUGH — watch the Godot window ===")

	_log("1/5 Press Any Key splash...")
	change_scene_to_file("res://press_any_key.tscn")
	await create_timer(PEEK_DELAY).timeout
	var splash := root.get_child(0)
	if splash and splash.has_method("_transition_to_menu"):
		splash._transition_to_menu()
	await create_timer(2.0).timeout

	_log("2/5 Main menu — Normal mode...")
	var gm := get_root().get_node("GameManager")
	gm.easy_mode = false
	gm.tutorial_mode = false
	gm.stop_menu_music()
	change_scene_to_file("res://game_board_3d.tscn")

	var board := await _wait_for_board()
	if board == null:
		_log("ERROR: game board failed to load")
		quit(1)
		return

	await create_timer(1.0).timeout
	var driver: Node = load("res://playthrough_driver.gd").new()
	board.add_child(driver)
	driver.start(board)
	await driver.finished

	_log("Victory screen hold (%.0fs)..." % VICTORY_HOLD)
	await create_timer(VICTORY_HOLD).timeout
	_log("=== PLAYTHROUGH FINISHED ===")
	quit(0)

func _wait_for_board() -> Node3D:
	for _i in range(600):
		await process_frame
		for child in root.get_children():
			if child is Node3D and child.has_method("_on_card_clicked"):
				return child
	return null

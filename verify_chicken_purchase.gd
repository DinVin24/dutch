extends SceneTree

## Automated chicken / ability purchase smoke test (logic + UI alert).
## Run: Godot --path dutch -s res://verify_chicken_purchase.gd

const SCREENSHOT_DIR := "res://debug/test_runs"
const HOLD_FRAMES := 45

func _init() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	for bus_name in ["Master", "Music", "SFX"]:
		var bus_idx := AudioServer.get_bus_index(bus_name)
		if bus_idx >= 0:
			AudioServer.set_bus_mute(bus_idx, true)
	call_deferred("_run")

func _log(msg: String) -> void:
	print("[CHICKEN-TEST] ", msg)

func _run() -> void:
	_log("=== CHICKEN PURCHASE TEST ===")
	var gm := root.get_node_or_null("GameManager")
	if gm == null:
		_fail("GameManager autoload missing")
		return

	gm.easy_mode = false
	gm.tutorial_mode = false
	gm.is_multiplayer = false
	gm.stop_menu_music()

	change_scene_to_file("res://game_board_3d.tscn")
	var board := await _wait_for_board()
	if board == null:
		_fail("game_board_3d failed to load")
		return

	await create_timer(1.5).timeout

	if gm.current_state == gm.GameState.INITIAL_PEEK:
		while gm.current_state == gm.GameState.INITIAL_PEEK:
			gm.complete_initial_peek()
			await process_frame

	if gm.current_state != gm.GameState.TURN_START_DRAW:
		gm.change_state(gm.GameState.TURN_START_DRAW, true)

	gm.current_player_index = 0
	gm.local_player_idx = 0
	gm.players_info[0]["money"] = 100

	var before_money: int = gm.players_info[0].money
	var bought: bool = gm.buy_ability(0)
	if not bought:
		_fail("buy_ability returned false (money=%d)" % before_money)
		return

	await create_timer(0.35).timeout
	for _i in HOLD_FRAMES:
		await process_frame

	var alert := board.get_node_or_null("GameUI/MainHUD/AbilityPurchaseAlert")
	if alert == null:
		_fail("AbilityPurchaseAlert missing after purchase")
		return

	var abilities: Array = gm.players_info[0].abilities.filter(func(a): return a != "")
	if abilities.is_empty():
		_fail("No ability stored in player inventory")
		return

	var chicken: Node3D = board.get("_chicken_node")
	if not is_instance_valid(chicken):
		_fail("Chicken node missing on board")
		return

	var cab: Node3D = board.get("_cabinets").get(0)
	if not is_instance_valid(cab):
		_fail("Player cabinet missing")
		return

	var screenshot_path := _save_screenshot("chicken_purchase")
	_log("PASS ability=%s money=%d->%d alert=ok chicken=ok cabinet=ok" % [
		str(abilities[0]),
		before_money,
		gm.players_info[0].money
	])
	if screenshot_path != "":
		_log("Screenshot -> %s" % screenshot_path)
	print("CHICKEN_TEST_COMPLETE pass=true ability=%s" % str(abilities[0]))
	quit(0)

func _wait_for_board() -> Node3D:
	for _i in range(600):
		await process_frame
		for child in root.get_children():
			if child is Node3D and child.has_method("_try_buy_ability"):
				return child
	return null

func _save_screenshot(label: String) -> String:
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace(" ", "_")
	var abs_dir := ProjectSettings.globalize_path("%s/%s" % [SCREENSHOT_DIR, stamp])
	DirAccess.make_dir_recursive_absolute(abs_dir)
	var image := root.get_viewport().get_texture().get_image()
	var filename := "ChickenTest_%s_%s.png" % [label, stamp]
	var path := "%s/%s" % [abs_dir, filename]
	if image.save_png(path) == OK:
		return path
	return ""

func _fail(reason: String) -> void:
	push_error("[CHICKEN-TEST] FAIL: " + reason)
	print("CHICKEN_TEST_COMPLETE pass=false reason=%s" % reason)
	quit(1)

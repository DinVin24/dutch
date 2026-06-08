extends SceneTree

## Smoke test: emote wheel toggle, key shortcuts, close button, and SP emote dispatch.
## Run: Godot --path dutch -s res://verify_emote_wheel.gd

const HOLD_FRAMES := 30

var _emote_seen: Array[String] = []

func _init() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	for bus_name in ["Master", "Music", "SFX"]:
		var bus_idx := AudioServer.get_bus_index(bus_name)
		if bus_idx >= 0:
			AudioServer.set_bus_mute(bus_idx, true)
	call_deferred("_run")

func _log(msg: String) -> void:
	print("[EMOTE-TEST] ", msg)

func _run() -> void:
	_log("=== EMOTE WHEEL TEST ===")
	var gm := root.get_node_or_null("GameManager")
	if gm == null:
		_fail("GameManager missing")
		return

	gm.easy_mode = false
	gm.tutorial_mode = false
	gm.is_multiplayer = false
	gm.stop_menu_music()
	gm.player_emoted.connect(_on_player_emoted)

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

	var toggle_btn: Button = board.get("_emote_toggle_btn")
	if toggle_btn == null or not is_instance_valid(toggle_btn):
		_fail("Emote toggle button not created")
		return
	if not toggle_btn.visible:
		_fail("Emote toggle button is not visible")
		return

	var wheel: PanelContainer = board.get("_emote_wheel_panel")
	if wheel == null or not is_instance_valid(wheel):
		_fail("Emote wheel panel missing")
		return

	board._open_emote_wheel()
	for _i in HOLD_FRAMES:
		await process_frame
	if not wheel.visible:
		_fail("Wheel did not open via _open_emote_wheel")
		return
	_log("OK wheel opened")

	board._close_emote_wheel()
	for _i in HOLD_FRAMES:
		await process_frame
	if wheel.visible:
		_fail("Wheel did not close via _close_emote_wheel")
		return
	_log("OK wheel closed")

	# Direct emote via key shortcut (singleplayer dispatch)
	board._on_emote_wheel_pressed("laugh")
	await create_timer(0.4).timeout
	if not _emote_seen.has("laugh"):
		_fail("player_emoted signal not received for 'laugh' in SP")
		return
	_log("OK SP emote dispatched: laugh")

	# After firing, wheel must be closed
	if wheel.visible:
		_fail("Wheel did not close after selecting emote")
		return
	_log("OK wheel auto-closed after pick")

	# Cooldown should prevent immediate re-emote (cleanup ensures we don't gate the next test)
	gm._emote_cooldown_until.clear()
	await create_timer(0.1).timeout

	# Toggle via _toggle_emote_wheel (mimics T key & button click)
	board._toggle_emote_wheel()
	await create_timer(0.1).timeout
	if not wheel.visible:
		_fail("Toggle did not open wheel")
		return
	board._toggle_emote_wheel()
	await create_timer(0.1).timeout
	if wheel.visible:
		_fail("Toggle did not close wheel")
		return
	_log("OK toggle open/close works")

	# Close button reference
	var close_btn: Button = board.get("_emote_close_btn")
	if close_btn == null or not is_instance_valid(close_btn):
		_fail("Close (X) button missing from wheel")
		return
	_log("OK close X button exists")

	# MP-mode dispatch sanity (no actual peers, just verify request_emote signature)
	gm._emote_cooldown_until.clear()
	gm.is_multiplayer = false
	var dispatched: bool = gm.request_emote("gg")
	if not dispatched:
		_fail("request_emote returned false for SP")
		return
	await create_timer(0.3).timeout
	if not _emote_seen.has("gg"):
		_fail("player_emoted not received for 'gg'")
		return
	_log("OK SP request_emote dispatches: gg")

	print("EMOTE_TEST_COMPLETE pass=true emotes=%s" % str(_emote_seen))
	quit(0)

func _on_player_emoted(player_idx: int, emote_id: String) -> void:
	_emote_seen.append(emote_id)
	_log("signal: P%d -> %s" % [player_idx, emote_id])

func _wait_for_board() -> Node:
	for _i in range(600):
		await process_frame
		for child in root.get_children():
			if child is Node3D and child.has_method("_toggle_emote_wheel"):
				return child
	return null

func _fail(reason: String) -> void:
	push_error("[EMOTE-TEST] FAIL: " + reason)
	print("EMOTE_TEST_COMPLETE pass=false reason=%s" % reason)
	quit(1)

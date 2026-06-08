extends SceneTree

## Focused verification for tutorial mode.
## Run: Godot --headless --path dutch -s res://verify_tutorial_mode.gd

const HOLD_FRAMES := 8

func _init() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	for bus_name in ["Master", "Music", "SFX"]:
		var bus_idx := AudioServer.get_bus_index(bus_name)
		if bus_idx >= 0:
			AudioServer.set_bus_mute(bus_idx, true)
	call_deferred("_run")

func _log(msg: String) -> void:
	print("[TUTORIAL-TEST] ", msg)

func _run() -> void:
	var gm = root.get_node_or_null("GameManager")
	_require(gm != null, "GameManager autoload missing")

	gm.stop_menu_music()
	gm.stop_game_music()
	gm.is_multiplayer = false
	gm.llm_player_enabled = false
	gm.show_game_assistant = true
	gm.easy_mode = false
	gm.tutorial_mode = false

	var menu_scene: PackedScene = load("res://main_menu.tscn")
	_require(menu_scene != null, "main_menu.tscn missing")
	var menu: Control = menu_scene.instantiate()
	root.add_child(menu)
	menu._on_tutorial_pressed()
	_require(gm.easy_mode, "Tutorial button should enable easy mode")
	_require(gm.tutorial_mode, "Tutorial button should enable tutorial mode")
	_log("OK tutorial menu button enables Easy + Tutorial mode")
	menu.queue_free()
	await process_frame

	change_scene_to_file("res://game_board_3d.tscn")
	var board := await _wait_for_board()
	_require(board != null, "game_board_3d.tscn failed to load")
	await create_timer(0.8).timeout
	board._apply_responsive_hud_layout()
	await create_timer(0.1).timeout

	var board_tutorial: Control = board.get_node_or_null("GameUI/TutorialOverlay")
	_require(is_instance_valid(board_tutorial), "Tutorial overlay should be injected into GameUI")
	var help_btn: Button = board.get("_assistant_help_btn")
	_require(is_instance_valid(help_btn), "Tutorial mode should still create the help button")
	_require(help_btn.visible, "Help button should stay visible in tutorial mode")
	var board_panel: PanelContainer = board_tutorial.get("_panel")
	_require(is_instance_valid(board_panel), "Tutorial overlay panel missing")
	var panel_rect := board_panel.get_global_rect()
	var help_rect := help_btn.get_global_rect()
	_log("tutorial panel rect=%s help rect=%s" % [panel_rect, help_rect])
	_require(panel_rect.end.y <= help_rect.position.y - 6.0, "Tutorial overlay should not overlap the help button")
	_log("OK tutorial overlay is injected and does not collide with the help button")

	var overlay_scene: PackedScene = load("res://tutorial_overlay.tscn")
	_require(overlay_scene != null, "tutorial_overlay.tscn missing")
	var overlay: Control = overlay_scene.instantiate()
	root.add_child(overlay)
	await process_frame

	var speech: RichTextLabel = overlay.get("_speech_label")
	var next_btn: Button = overlay.get("_next_btn")
	var skip_btn: Button = overlay.get("_skip_btn")
	var step_hint: Label = overlay.get("_panel").find_child("StepHint", true, false)
	_require(is_instance_valid(speech), "Tutorial speech label missing")
	_require(is_instance_valid(next_btn), "Tutorial NEXT button missing")
	_require(is_instance_valid(skip_btn), "Tutorial SKIP button missing")
	_require(is_instance_valid(step_hint), "Tutorial step hint missing")

	_assert_tip_contains(overlay, ["Welcome!", "4 cards each"])
	_require(step_hint.text == "1 / 2", "Initial DEAL_CARDS tip should start on step 1/2")
	next_btn.emit_signal("pressed")
	await create_timer(0.25).timeout
	_assert_tip_contains(overlay, ["King of Diamonds", "Ace=1"])
	_require(step_hint.text == "2 / 2", "NEXT should advance multi-step tips")
	_log("OK multi-step welcome tip advances with NEXT")

	_set_tip_state(overlay, "INITIAL_PEEK")
	_assert_tip_contains(overlay, ["Click 2 of YOUR cards", "flip back down"])

	_set_tip_state(overlay, "TURN_START_DRAW")
	_assert_tip_contains(overlay, ["Your turn!", "MUST draw"])

	_set_tip_state(overlay, "TURN_RESOLVE_DRAWN")
	_assert_tip_contains(overlay, ["You drew a card", "SWAP"])

	_set_tip_state(overlay, "TURN_PEEK_ABILITY")
	_assert_tip_contains(overlay, ["played a Queen", "secretly peek"])

	_set_tip_state(overlay, "TURN_SWAP_ABILITY")
	_assert_tip_contains(overlay, ["played a Jack", "swap their positions"])

	_set_tip_state(overlay, "TURN_END_CHOICE")
	_assert_tip_contains(overlay, ["END TURN", "pass to the next player"])
	next_btn.emit_signal("pressed")
	await create_timer(0.25).timeout
	_assert_tip_contains(overlay, ["CALL DUTCH", "lowest score"])

	_set_tip_state(overlay, "TURN_JUMP_IN_SELECTION")
	_assert_tip_contains(overlay, ["JUMP IN mode", "match the RANK"])

	_set_tip_state(overlay, "TURN_CONFIRM_DUTCH")
	_assert_tip_contains(overlay, ["called Dutch", "CONFIRM to end the game", "can't call Dutch again"])

	_set_tip_state(overlay, "STATE_PLAYING_ABILITY")
	_assert_tip_contains(overlay, ["playing an ability", "resolves automatically"])

	_set_tip_state(overlay, "GAME_OVER")
	_assert_tip_contains(overlay, ["Game over!", "All cards flip face-up"])
	_log("OK tutorial maps the main FSM states to contextual tips")

	overlay._load_tips_for_state("DEAL_CARDS")
	overlay._display_current_tip()
	var before_bot_tip := speech.text
	gm.current_player_index = 2
	await _emit_state(overlay, gm, gm.GameState.TURN_START_DRAW)
	_require(speech.text == before_bot_tip, "Player-only tips should stay quiet during bot turns")
	_log("OK player-only tutorial tips are suppressed on bot turns")

	overlay.set("_shown_events", {})
	overlay._on_player_drank_beer(0, 2)
	await create_timer(0.25).timeout
	_assert_tip_contains(overlay, ["drank a beer", "3 lives"])
	var beer_tip := speech.text
	overlay._on_player_drank_beer(0, 1)
	await create_timer(0.25).timeout
	_require(speech.text == beer_tip, "First beer tip should only appear once")

	overlay._on_ability_unlocked(0, "bottoms_up")
	await create_timer(0.25).timeout
	_assert_tip_contains(overlay, ["Bottoms Up", "drink a beer"])

	overlay.set("_shown_events", {})
	overlay._on_dutch_called(0)
	await create_timer(0.25).timeout
	_assert_tip_contains(overlay, ["You called Dutch", "Everyone else gets one last turn"])

	overlay.set("_shown_events", {})
	overlay._on_dutch_called(2)
	await create_timer(0.25).timeout
	_assert_tip_contains(overlay, ["Someone called DUTCH", "one last turn"])

	overlay.set("_last_money", 40)
	overlay._on_player_gained_money(0, 10, 50)
	await create_timer(0.25).timeout
	_assert_tip_contains(overlay, ["$50", "CHICKEN", "ability egg"])
	_log("OK one-off tutorial events cover beer, Dutch, abilities, and chicken guidance")

	gm.tutorial_mode = true
	skip_btn.emit_signal("pressed")
	await create_timer(0.35).timeout
	await process_frame
	_require(not gm.tutorial_mode, "Skipping tutorial should disable tutorial mode")
	_require(not is_instance_valid(overlay), "Skipping tutorial should free the overlay")
	_log("OK skip dismisses the tutorial cleanly")

	print("TUTORIAL_MODE_TEST_COMPLETE pass=true")
	quit(0)

func _emit_state(overlay: Control, gm, state: int) -> void:
	gm.current_state = state
	overlay._on_game_state_changed(state)
	await _await_for_overlay()

func _set_tip_state(overlay: Control, state_name: String) -> void:
	overlay._load_tips_for_state(state_name)
	overlay._display_current_tip()

func _await_for_overlay() -> void:
	for _i in range(HOLD_FRAMES):
		await process_frame

func _assert_tip_contains(overlay: Control, fragments: Array[String]) -> void:
	var speech: RichTextLabel = overlay.get("_speech_label")
	_require(is_instance_valid(speech), "Tutorial speech label disappeared unexpectedly")
	var text := speech.text
	for fragment in fragments:
		_require(text.contains(fragment), "Tutorial tip missing '%s'. Got: %s" % [fragment, text])

func _wait_for_board() -> Node:
	for _i in range(120):
		await process_frame
		var current := current_scene
		if current != null and current.name == "game_board_3d":
			return current
	return current_scene

func _require(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("[TUTORIAL-TEST] FAIL: " + message)
	print("TUTORIAL_MODE_TEST_COMPLETE pass=false reason=%s" % message)
	quit(1)

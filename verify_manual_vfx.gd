extends SceneTree

## Automated manual verification for beer / jumpscare / victory VFX.
## Run: Godot --path dutch -s res://verify_manual_vfx.gd

const LOG := "user://verify_manual_vfx.log"

var _board: Node3D = null
var _passed := 0
var _failed := 0

func _gm() -> Node:
	return get_root().get_node("GameManager")

func _init() -> void:
	call_deferred("_run")

func _log(msg: String) -> void:
	print(msg)
	var mode := FileAccess.READ_WRITE if FileAccess.file_exists(LOG) else FileAccess.WRITE
	var f := FileAccess.open(LOG, mode)
	if f:
		if f.get_length() > 0:
			f.seek_end()
		f.store_line(msg)

func _pass(label: String) -> void:
	_passed += 1
	_log("[PASS] " + label)

func _fail(label: String, detail: String = "") -> void:
	_failed += 1
	_log("[FAIL] " + label + ((": " + detail) if detail != "" else ""))

func _run() -> void:
	_log("=== MANUAL VFX VERIFICATION START ===")
	var gm := _gm()

	var scene: PackedScene = load("res://game_board_3d.tscn")
	if scene == null:
		_fail("load_scene", "game_board_3d.tscn")
		_finish()
		return

	_board = scene.instantiate()
	root.add_child(_board)
	await process_frame
	await process_frame

	var wait_frames := 0
	var peek_state: int = gm.GameState.INITIAL_PEEK
	while gm.current_state != peek_state and wait_frames < 600:
		await process_frame
		wait_frames += 1
	if gm.current_state == peek_state:
		gm.complete_initial_peek()
		_log("[ACTION] Skipped peek phase -> TURN_START_DRAW")
	else:
		_log("[WARN] Peek phase not reached (state=%d)" % gm.current_state)

	await create_timer(1.0).timeout

	await _verify_card_mesh()
	await create_timer(0.5).timeout
	await _verify_beer()
	await create_timer(1.5).timeout
	await _verify_jumpscare()
	await create_timer(1.5).timeout
	await _verify_victory()
	await create_timer(3.0).timeout

	_finish()

func _verify_card_mesh() -> void:
	_log("--- CARD MESH TEST ---")
	var card_scene: PackedScene = load("res://card_3d.tscn")
	if card_scene == null:
		_fail("card_scene", "card_3d.tscn missing")
		return

	var card: Node3D = card_scene.instantiate()
	root.add_child(card)
	await process_frame

	var core := card.get_node_or_null("Visuals/CardCore") as MeshInstance3D
	if core and core.mesh is BoxMesh:
		var thickness: float = (core.mesh as BoxMesh).size.z
		if thickness >= 0.04:
			_pass("card core thickness %.3f" % thickness)
		else:
			_fail("card_core_thickness", "z=%.3f" % thickness)
	else:
		_fail("card_core", "CardCore BoxMesh missing")

	var trail := card.get_node_or_null("DiscardTrail") as CPUParticles3D
	if trail:
		_pass("discard trail particles ready")
		if card.has_method("set_discard_trail_active"):
			card.set_discard_trail_active(true)
			await process_frame
			if trail.emitting:
				_pass("discard trail toggles on")
			else:
				_fail("discard_trail_emit", "not emitting")
			card.set_discard_trail_active(false)
		else:
			_fail("discard_trail_api", "set_discard_trail_active missing")
	else:
		_fail("discard_trail", "DiscardTrail node missing")

	card.queue_free()

func _verify_beer() -> void:
	_log("--- BEER TEST ---")
	var gm := _gm()
	if _board == null or _board.player_beers_nodes.is_empty():
		_fail("beer_setup", "no beer nodes")
		return

	var beers_arr: Array = _board.player_beers_nodes[0]
	if beers_arr.is_empty():
		_fail("beer_setup", "player 0 has no beers")
		return

	var before_count: int = gm.players_info[0].beers
	var target_beer: Node3D = beers_arr[before_count - 1]
	var base_scale: Vector3 = target_beer.get_meta("base_scale", target_beer.scale)

	_log("[ACTION] drink_beer(player 0) — simulates penalty beer")
	gm.drink_beer(0)
	await create_timer(1.2).timeout

	var after_count: int = gm.players_info[0].beers
	if after_count != before_count - 1:
		_fail("beer_count", "expected %d got %d" % [before_count - 1, after_count])
	else:
		_pass("beer_count decremented (%d -> %d)" % [before_count, after_count])

	if is_instance_valid(target_beer):
		var emptied := not target_beer.visible or target_beer.scale.y < base_scale.y * 0.2
		if emptied:
			_pass("beer_emptying animation (hidden or drained)")
		else:
			_fail("beer_emptying", "beer still full scale/visible")
	else:
		_fail("beer_emptying", "beer node invalid")

func _verify_jumpscare() -> void:
	_log("--- JUMPSCARE TEST ---")
	var gm := _gm()
	gm.current_player_index = 0
	if not gm.players_info[0].abilities.has("jumpscare"):
		gm.players_info[0].abilities.append("jumpscare")

	_log("[ACTION] play_ability(jumpscare) on Player 2")
	var ok: bool = gm.play_ability(0, "jumpscare", 1)
	if not ok:
		_fail("jumpscare_play", "play_ability returned false")
		return
	_pass("jumpscare ability accepted")

	# Flash lasts ~0.12s — sample on the next frames, not after a long delay.
	await process_frame
	await process_frame
	if _board._shake_timer > 0.0:
		_pass("jumpscare camera shake")
	else:
		_fail("jumpscare_shake", "shake not active")

	var flash_found := false
	for c in _board.get_children():
		if c is CanvasLayer and c.layer >= 100:
			flash_found = true
			break
	if flash_found:
		_pass("jumpscare white flash overlay")
	else:
		_fail("jumpscare_flash", "no flash CanvasLayer")

	# Wait for ability FSM to finish before victory test.
	await create_timer(1.5).timeout

func _verify_victory() -> void:
	_log("--- VICTORY TEST ---")
	var gm := _gm()
	_log("[ACTION] trigger victory reveal + score overlay (game over flow)")
	var results: Array = gm._calculate_scores()
	gm.all_cards_revealed.emit()
	gm.scores_ready.emit(results)
	await create_timer(3.5).timeout

	var overlay_found := false
	var winner_label := ""
	for c in _board.get_children():
		if c is CanvasLayer and c.layer >= 110:
			overlay_found = true
			for node in _flatten_controls(c):
				if node is Label and "WINS" in node.text:
					winner_label = node.text
					break

	if overlay_found:
		_pass("victory score overlay visible")
	else:
		_fail("victory_overlay", "no CanvasLayer overlay")

	if winner_label != "":
		_pass("victory title: " + winner_label)
	else:
		_fail("victory_title", "no WINNER label")

	if _board._victory_fanfare_stream != null and not _board._victory_fanfare_stream.data.is_empty():
		_pass("victory fanfare stream ready")
	else:
		_fail("victory_fanfare", "stream missing")

	if Engine.time_scale == 1.0:
		_pass("slow-mo restored after reveal")
	else:
		_fail("slow_mo_restore", "time_scale=%s" % str(Engine.time_scale))

	var emote_found := false
	if _board._victory_overlay_layer:
		for node in _flatten_controls(_board._victory_overlay_layer):
			if node is Button and node.text == "GG":
				emote_found = true
				break
	if emote_found:
		_pass("victory emote slot visible")
	else:
		_fail("victory_emote", "no emote buttons on overlay")

func _flatten_controls(node: Node) -> Array:
	var out: Array = []
	if node is Control:
		out.append(node)
	for child in node.get_children():
		out.append_array(_flatten_controls(child))
	return out

func _finish() -> void:
	_log("=== RESULT: %d passed, %d failed ===" % [_passed, _failed])
	if _failed == 0:
		_log("ALL MANUAL VFX CHECKS PASSED")
		quit(0)
	else:
		_log("SOME CHECKS FAILED — see log above")
		quit(1)

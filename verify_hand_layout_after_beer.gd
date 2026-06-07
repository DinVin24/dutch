extends SceneTree

## Verifies hand card layout after beer penalty (discard drawn + failed jump-in).
## Run: D:\Godot\Godot_v4.6.2-stable_win64_console.exe --path dutch -s res://verify_hand_layout_after_beer.gd

const LOG := "user://verify_hand_layout_after_beer.log"
const BASE_SPACING := 1.05
const MAX_HAND_WIDTH := 4.2
const POS_TOL := 0.08

var _board: Node3D = null
var _passed := 0
var _failed := 0

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

func _gm() -> Node:
	return get_root().get_node("GameManager")

func _expected_pos(card_idx: int, total: int) -> Vector3:
	var spacing := BASE_SPACING
	if total > 5:
		spacing = MAX_HAND_WIDTH / float(total - 1)
	var offset_x := (card_idx - (total - 1) / 2.0) * spacing
	return Vector3(offset_x, 0.05 + card_idx * 0.01, 0)

func _check_hand_layout(player_idx: int, label: String) -> bool:
	var hand: Array = _board.player_hands[player_idx]
	var total := hand.size()
	var ok := true
	for i in range(total):
		var card = hand[i]
		if not is_instance_valid(card):
			_fail(label, "card %d invalid" % i)
			return false
		var expected := _expected_pos(i, total)
		var actual: Vector3 = card.position
		if actual.distance_to(expected) > POS_TOL:
			ok = false
			_fail(label, "card %d pos %s expected %s (dist %.3f)" % [i, actual, expected, actual.distance_to(expected)])
	if ok:
		_pass(label + " (%d cards aligned)" % total)
	return ok

func _run() -> void:
	_log("=== HAND LAYOUT AFTER BEER ===")
	var gm := _gm()

	var scene: PackedScene = load("res://game_board_3d.tscn")
	if scene == null:
		_fail("load_scene")
		_finish()
		return

	_board = scene.instantiate()
	root.add_child(_board)
	await process_frame
	await process_frame

	var wait_frames := 0
	while gm.current_state != gm.GameState.INITIAL_PEEK and wait_frames < 600:
		await process_frame
		wait_frames += 1
	gm.complete_initial_peek()
	await create_timer(1.5).timeout

	await _test_discard_drawn_beer(gm)
	await create_timer(1.0).timeout
	await _test_jump_in_penalty(gm)
	_finish()

func _test_discard_drawn_beer(gm: Node) -> void:
	_log("--- TEST: discard drawn + beer ---")
	gm.current_player_index = 0
	gm.change_state(gm.GameState.TURN_START_DRAW, true)

	var before: int = gm.players_info[0].hand.size()
	_check_hand_layout(0, "baseline before draw")

	gm.player_draw_card()
	await create_timer(0.6).timeout
	gm.player_discard_drawn_card()
	await create_timer(1.5).timeout

	if gm.players_info[0].hand.size() != before:
		_fail("discard_drawn_hand_size", "expected %d got %d" % [before, gm.players_info[0].hand.size()])
	else:
		_pass("discard_drawn hand size unchanged")

	_check_hand_layout(0, "after discard drawn + beer")

func _test_jump_in_penalty(gm: Node) -> void:
	_log("--- TEST: failed jump-in + beer + penalty card ---")
	gm.current_player_index = 0
	gm.change_state(gm.GameState.TURN_END_CHOICE, true)

	# Put a known card on discard pile for jump-in comparison
	var top: CardData = gm.deck_manager.draw_card()
	top.is_face_up = true
	gm.deck_manager.discard_pile.append(top)
	gm.card_discarded.emit(0, top)
	await create_timer(0.5).timeout

	var hand: Array = gm.players_info[0].hand
	if hand.is_empty():
		_fail("jump_in_setup", "empty hand")
		return

	var wrong_idx := 0
	for i in range(hand.size()):
		if hand[i].rank != top.rank:
			wrong_idx = i
			break

	var size_before_penalty: int = gm.players_info[0].hand.size()
	gm.start_jump_in(0)
	await process_frame
	await gm.validate_jump_in(wrong_idx)
	await create_timer(1.0).timeout

	var after_size: int = gm.players_info[0].hand.size()
	if after_size < size_before_penalty:
		_fail("jump_in_penalty_size", "hand shrank unexpectedly")
	elif after_size == size_before_penalty:
		_fail("jump_in_penalty_size", "penalty card not added (deck empty?)")
	else:
		_pass("penalty card added (%d -> %d)" % [size_before_penalty, after_size])

	_check_hand_layout(0, "after jump-in fail + beer + penalty")

func _finish() -> void:
	_log("=== RESULT: %d passed, %d failed ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)

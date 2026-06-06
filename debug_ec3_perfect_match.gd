extends SceneTree

## Headless EC-3: Perfect Match while pending_card is visible.
## Run: flatpak run org.godotengine.Godot --headless --path . -s res://debug_ec3_perfect_match.gd

const OUT_LOG := "res://.debug/ec3_perfect_match.log"
const PLAYER := 0

var _board: Node3D
var _gm: Node

func _init() -> void:
	call_deferred("_run")

func _release_gm_audio(gm: Node) -> void:
	if gm == null:
		return
	gm.is_menu_music_active = false
	gm.is_game_music_active = false
	if gm.has_method("stop_all_music"):
		gm.stop_all_music()
	for tw in gm.get_tree().get_processed_tweens():
		if tw.is_valid():
			tw.kill()
	var players: Array[AudioStreamPlayer] = []
	for child in gm.get_children():
		if child is AudioStreamPlayer:
			players.append(child)
	for p in players:
		p.stop()
		p.stream = null
		gm.remove_child(p)
		p.free()
	for key in [
		"menu_music_p1", "menu_music_p2", "game_music_p1", "game_music_p2",
		"current_menu_player", "next_menu_player", "current_game_player", "next_game_player",
		"sfx_card_flip", "sfx_beer_drink", "sfx_chicken",
	]:
		gm.set(key, null)

func _quit(code: int) -> void:
	_release_gm_audio(_gm)
	if _board and is_instance_valid(_board):
		root.remove_child(_board)
		_board.free()
		_board = null
	await create_timer(0.1).timeout
	quit(code)

func _log(line: String) -> void:
	print(line)
	var path := ProjectSettings.globalize_path(OUT_LOG)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var mode := FileAccess.READ_WRITE if FileAccess.file_exists(OUT_LOG) else FileAccess.WRITE
	var f := FileAccess.open(OUT_LOG, mode)
	if f:
		if f.get_length() > 0:
			f.seek_end()
		f.store_line(line)

func _pending_alive() -> bool:
	if _board == null:
		return false
	var n := _board.get_node_or_null("PendingCard")
	return n != null and is_instance_valid(n)

func _run() -> void:
	_log("=== DEBUG EC-3: Perfect Match + pending card ===")
	_gm = root.get_node_or_null("GameManager")
	if _gm == null:
		_log("[EC3 FAIL] GameManager autoload missing")
		await _quit(1)
		return

	var scene: PackedScene = load("res://game_board_3d.tscn")
	if scene == null:
		_log("[EC3 FAIL] failed to load game_board_3d.tscn")
		await _quit(1)
		return

	_board = scene.instantiate()
	root.add_child(_board)
	await process_frame
	await process_frame
	await create_timer(0.5).timeout

	while _gm.current_state != _gm.GameState.INITIAL_PEEK:
		await process_frame
	_gm.complete_initial_peek()
	_log("[ACTION] Skipped initial peek")

	await process_frame
	await create_timer(0.2).timeout

	_gm.current_player_index = PLAYER
	var slot: int = _gm.players_info[PLAYER].abilities.find("")
	if slot == -1:
		_gm.players_info[PLAYER].abilities.append("perfect_match")
	else:
		_gm.players_info[PLAYER].abilities[slot] = "perfect_match"
	_log("[ACTION] Gave perfect_match to P%d" % PLAYER)

	_gm.player_draw_card()
	await process_frame
	for _i in 10:
		await process_frame

	var had_drawn := _gm.drawn_card_data != null
	var had_pending := _pending_alive()
	_log("[CHECK] after draw | drawn_card_data=%s pending_node=%s state=%s" % [
		str(had_drawn),
		str(had_pending),
		_gm.GameState.keys()[_gm.current_state],
	])

	if not had_drawn or not had_pending:
		_log("[EC3 FAIL] setup — expected drawn card + pending node before Perfect Match")
		await _quit(1)
		return

	var ok: bool = _gm.play_ability(PLAYER, "perfect_match", PLAYER)
	_log("[ACTION] play_ability(perfect_match) returned %s" % str(ok))
	await create_timer(1.5).timeout
	for _i in 20:
		await process_frame

	var pending_after := _pending_alive()
	var drawn_after: Variant = _gm.drawn_card_data
	var state_after: String = _gm.GameState.keys()[_gm.current_state]
	_log("[CHECK] after perfect_match | drawn_card_data=%s pending_node=%s state=%s" % [
		str(drawn_after),
		str(pending_after),
		state_after,
	])

	var bug := pending_after
	if bug:
		_log("[EC3 FAIL] pending Card3D still in scene — pending_card_consumed not emitted (ability_manager.gd)")
		_log("VERDICT: BUG CONFIRMED")
		await _quit(1)
	else:
		_log("[EC3 PASS] pending node cleared")
		if state_after == "INITIAL_PEEK" and drawn_after == null:
			_log("VERDICT: EC-3 OK (round reset + no orphan pending card)")
			await _quit(0)
		else:
			_log("[EC3 WARN] pending cleared but state=%s drawn=%s" % [state_after, str(drawn_after)])
			_log("VERDICT: partial_pass")
			await _quit(0)

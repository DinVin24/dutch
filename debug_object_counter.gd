extends SceneTree

## Logs Godot Performance monitor object counts through first Draw -> Discard.
## Run: flatpak run org.godotengine.Godot --headless --path . -s res://debug_object_counter.gd

const OUT_LOG := "res://.debug/object_counter.log"
const PLAYER := 0
const SETTLE_SEC := 2.5
const AUTLOAD_WAIT_SEC := 3.0
const DRAW_WAIT_SEC := 2.0

var _board: Node3D
var _gm: Node
var _baseline: Dictionary = {}
var _baseline_digest: Dictionary = {}
var _samples: Array = []

func _init() -> void:
	call_deferred("_run")

func _stop_gm_music(gm: Node) -> void:
	if gm == null:
		return
	gm.is_menu_music_active = false
	gm.is_game_music_active = false
	if gm.has_method("stop_all_music"):
		gm.stop_all_music()

func _drain_gm_sfx_players(gm: Node) -> void:
	if gm == null:
		return
	var keep := {}
	for key in ["menu_music_p1", "menu_music_p2", "game_music_p1", "game_music_p2"]:
		var player = gm.get(key)
		if player:
			keep[player] = true
	for child in gm.get_children():
		if child is AudioStreamPlayer and not keep.has(child):
			child.stop()
			gm.remove_child(child)
			child.free()

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

func _monitors() -> Dictionary:
	return {
		"object": Performance.get_monitor(Performance.OBJECT_COUNT),
		"object_resource": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
		"object_node": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"object_orphan_node": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		"cpu_particles_on_board": _count_cpu_particles(_board),
	}

func _is_card3d(node: Node) -> bool:
	return node != null and node.has_method("setup")

func _wait_for_autoloads() -> bool:
	var deadline := Time.get_ticks_msec() + int(AUTLOAD_WAIT_SEC * 1000.0)
	while Time.get_ticks_msec() < deadline:
		_gm = root.get_node_or_null("GameManager")
		if _gm != null:
			return true
		await process_frame
	return false

func _load_board_scene() -> Node3D:
	var scene: PackedScene = load("res://game_board_3d.tscn")
	if scene == null:
		return null
	var board := scene.instantiate() as Node3D
	if board == null:
		return null
	root.add_child(board)
	await process_frame
	await process_frame
	await create_timer(0.5).timeout
	return board

func _count_cpu_particles(root_node: Node) -> int:
	if root_node == null:
		return 0
	var n := 0
	var stack: Array = [root_node]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is CPUParticles3D:
			n += 1
		for c in node.get_children():
			stack.append(c)
	return n

func _count_nodes(root_node: Node) -> int:
	if root_node == null:
		return 0
	var n := 0
	var stack: Array = [root_node]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		n += 1
		for c in node.get_children():
			stack.append(c)
	return n

func _board_digest() -> Dictionary:
	var digest := {
		"board_total_nodes": _count_nodes(_board),
		"discard_card3d": 0,
		"deck_card3d": 0,
		"pending_card": 0,
		"money_juice": 0,
		"board_direct_cpu_particles": 0,
		"card_discard_trails": 0,
		"top_center_labels": 0,
		"root_card3d_orphans": 0,
		"discard_pile_size": 0,
	}
	if _board == null:
		return digest
	var discard_area := _board.get_node_or_null("DiscardArea")
	var deck_area := _board.get_node_or_null("DeckArea")
	var top_center := _board.get_node_or_null("GameUI/MainHUD/TopCenter")
	if discard_area:
		for c in discard_area.get_children():
			if _is_card3d(c):
				digest.discard_card3d += 1
	if deck_area:
		for c in deck_area.get_children():
			if _is_card3d(c):
				digest.deck_card3d += 1
	var pending := _board.get_node_or_null("PendingCard")
	if _is_card3d(pending):
		digest.pending_card = 1
	for c in _board.get_children():
		if c is CPUParticles3D:
			digest.board_direct_cpu_particles += 1
	var stack: Array = [_board]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node.name == "MoneyJuice":
			digest.money_juice += 1
		if node.name == "DiscardTrail" and node is CPUParticles3D:
			digest.card_discard_trails += 1
		for c in node.get_children():
			stack.append(c)
	if top_center:
		for c in top_center.get_children():
			if c is Label:
				digest.top_center_labels += 1
	for c in root.get_children():
		if _is_card3d(c) and c != _board:
			digest.root_card3d_orphans += 1
	if _gm and _gm.deck_manager:
		digest.discard_pile_size = _gm.deck_manager.discard_pile.size()
	return digest

func _log_digest(label: String, digest: Dictionary) -> void:
	_log("[DIGEST] %s | board_nodes=%d discard_cards=%d deck_cards=%d pending=%d money_juice=%d board_vfx_particles=%d card_trails=%d hud_labels=%d root_card_orphans=%d pile_size=%d" % [
		label,
		int(digest.board_total_nodes),
		int(digest.discard_card3d),
		int(digest.deck_card3d),
		int(digest.pending_card),
		int(digest.money_juice),
		int(digest.board_direct_cpu_particles),
		int(digest.card_discard_trails),
		int(digest.top_center_labels),
		int(digest.root_card3d_orphans),
		int(digest.discard_pile_size),
	])

func _log_digest_delta(baseline: Dictionary, final: Dictionary) -> void:
	_log("[DIGEST DELTA vs baseline] discard_cards=%+d deck_cards=%+d pending=%+d money_juice=%+d board_vfx_particles=%+d card_trails=%+d hud_labels=%+d root_card_orphans=%+d pile_size=%+d" % [
		int(final.discard_card3d) - int(baseline.discard_card3d),
		int(final.deck_card3d) - int(baseline.deck_card3d),
		int(final.pending_card) - int(baseline.pending_card),
		int(final.money_juice) - int(baseline.money_juice),
		int(final.board_direct_cpu_particles) - int(baseline.board_direct_cpu_particles),
		int(final.card_discard_trails) - int(baseline.card_discard_trails),
		int(final.top_center_labels) - int(baseline.top_center_labels),
		int(final.root_card3d_orphans) - int(baseline.root_card3d_orphans),
		int(final.discard_pile_size) - int(baseline.discard_pile_size),
	])

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

func _sample(label: String) -> void:
	var m := _monitors()
	_samples.append({"label": label, "m": m})
	_log("[SAMPLE] %s | object=%d resource=%d node=%d orphan_node=%d board_cpu_particles=%d" % [
		label,
		int(m.object),
		int(m.object_resource),
		int(m.object_node),
		int(m.object_orphan_node),
		int(m.cpu_particles_on_board),
	])

func _delta_from_baseline(label: String, m: Dictionary) -> String:
	return "d_object=%+d d_node=%+d d_particles=%+d" % [
		int(m.object) - int(_baseline.object),
		int(m.object_node) - int(_baseline.object_node),
		int(m.cpu_particles_on_board) - int(_baseline.cpu_particles_on_board),
	]

func _run() -> void:
	_log("=== DEBUG OBJECT COUNTER (first Draw -> Discard) ===")
	if not await _wait_for_autoloads():
		_log("[ERROR] GameManager autoload missing")
		await _quit(1)
		return
	_stop_gm_music(_gm)

	_board = await _load_board_scene()
	if _board == null:
		_log("[ERROR] failed to load game_board_3d.tscn")
		await _quit(1)
		return

	var peek_state: int = _gm.GameState.INITIAL_PEEK
	var wait_frames := 0
	while _gm.current_state != peek_state and wait_frames < 600:
		await process_frame
		wait_frames += 1
	if _gm.current_state == peek_state:
		_gm.complete_initial_peek()
		_log("[ACTION] Skipped initial peek -> TURN_START_DRAW")
	else:
		_log("[WARN] Peek not reached (state=%d)" % _gm.current_state)

	await process_frame
	await create_timer(0.25).timeout

	_baseline = _monitors()
	_baseline_digest = _board_digest()
	_sample("baseline_after_peek")
	_log_digest("baseline_after_peek", _baseline_digest)

	if _gm.current_state != _gm.GameState.TURN_START_DRAW:
		_log("[WARN] Expected TURN_START_DRAW, got %d" % _gm.current_state)

	_gm.current_player_index = PLAYER
	_log("[ACTION] player_draw_card()")
	_gm.player_draw_card()
	await process_frame
	_sample("immediately_after_draw_call")

	for i in 5:
		await process_frame
	_sample("5_frames_after_draw")

	await create_timer(0.15).timeout
	_sample("during_draw_vfx_peak_estimate")

	var drawn = _gm.drawn_card_data
	var draw_deadline := Time.get_ticks_msec() + int(DRAW_WAIT_SEC * 1000.0)
	while drawn == null and Time.get_ticks_msec() < draw_deadline:
		await process_frame
		drawn = _gm.drawn_card_data
	if drawn == null:
		_log("[ERROR] drawn_card_data is null after draw")
		_summarize()
		await _quit(1)
		return

	_log("[ACTION] player_discard_drawn_card() (%s %s)" % [drawn.rank, drawn.suit])
	_gm.player_discard_drawn_card()
	await process_frame
	_sample("immediately_after_discard_call")

	for i in 8:
		await process_frame
	_sample("8_frames_after_discard_mid_tween")

	await create_timer(0.35).timeout
	_sample("mid_discard_tween")

	await create_timer(SETTLE_SEC).timeout
	for _pass in 4:
		_drain_gm_sfx_players(_gm)
		await create_timer(0.2).timeout
	_sample("after_settle_%.1fs_post_discard" % SETTLE_SEC)
	var final_digest := _board_digest()
	_log_digest("after_settle", final_digest)
	_log_digest_delta(_baseline_digest, final_digest)

	_summarize()
	await _quit(0)

func _summarize() -> void:
	if _samples.is_empty():
		return
	var last: Dictionary = _samples.back()["m"]
	var peak_obj := int(_baseline.object)
	var peak_particles := int(_baseline.cpu_particles_on_board)
	for s in _samples:
		peak_obj = max(peak_obj, int(s.m.object))
		peak_particles = max(peak_particles, int(s.m.cpu_particles_on_board))

	var final_digest := _board_digest()
	var expected_discard_nodes := int(final_digest.discard_card3d) - int(_baseline_digest.get("discard_card3d", 0))
	var expected_trail_particles := int(final_digest.card_discard_trails) - int(_baseline_digest.get("card_discard_trails", 0))
	var expected_vfx_particles := int(final_digest.board_direct_cpu_particles) - int(_baseline_digest.get("board_direct_cpu_particles", 0))
	var expected_node_delta := expected_discard_nodes * 10 + int(final_digest.top_center_labels) - int(_baseline_digest.get("top_center_labels", 0))
	var node_delta := int(last.object_node) - int(_baseline.object_node)
	var particle_delta := int(last.cpu_particles_on_board) - int(_baseline.cpu_particles_on_board)

	var recovered_obj := int(last.object) <= int(_baseline.object) + 5
	var recovered_nodes := node_delta <= expected_node_delta + 2
	var recovered_particles := particle_delta <= expected_trail_particles + expected_vfx_particles + 1

	_log("--- SUMMARY ---")
	_log("baseline object=%d node=%d board_cpu_particles=%d" % [
		int(_baseline.object), int(_baseline.object_node), int(_baseline.cpu_particles_on_board)
	])
	_log("peak object=%d board_cpu_particles=%d" % [peak_obj, peak_particles])
	_log("final %s" % _delta_from_baseline(_samples.back().label, last))
	_log("expected node delta from discard pile card (~10/card): ~+%d (discard_cards=%+d)" % [
		expected_discard_nodes * 10, expected_discard_nodes
	])
	_log("expected particle delta: card_trails=%+d board_vfx=%+d" % [expected_trail_particles, expected_vfx_particles])
	if recovered_obj and recovered_nodes and recovered_particles:
		_log("VERDICT: spike_with_recovery (counts match expected post-discard state)")
	else:
		_log("VERDICT: possible_leak (final counts exceed expected post-discard state)")
		if not recovered_particles:
			_log("  - CPUParticles3D: delta=%+d expected<=%+d" % [particle_delta, expected_trail_particles + expected_vfx_particles + 1])
		if not recovered_obj:
			_log("  - OBJECT_COUNT still elevated (+%d)" % (int(last.object) - int(_baseline.object)))
		if not recovered_nodes:
			_log("  - OBJECT_NODE_COUNT: delta=%+d expected<=%d" % [node_delta, expected_node_delta + 2])

class_name DebugMpCommon
extends RefCounted

## Shared helpers for headless MP debug scripts.

static func log_to(path: String, line: String) -> void:
	print(line)
	var abs := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(abs.get_base_dir())
	var mode := FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE
	var f := FileAccess.open(path, mode)
	if f:
		if f.get_length() > 0:
			f.seek_end()
		f.store_line(line)

static func wait_for_autoloads(tree: SceneTree) -> void:
	for _i in 30:
		if tree.root.get_node_or_null("GameManager") != null:
			return
		await tree.process_frame

static func release_gm_audio(gm: Node) -> void:
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

static func configure_mock_mp(gm: Node, local_idx: int, num_players: int = 2) -> void:
	gm.is_multiplayer = true
	gm.num_players = num_players
	gm.local_player_idx = local_idx
	gm.peer_to_idx = {1: 0, 2: 1}
	gm.idx_to_peer = {0: 1, 1: 2}
	if gm.players_info.size() >= num_players:
		for i in range(num_players):
			gm.players_info[i]["is_bot"] = false
			gm.players_info[i]["name"] = "MP_P%d" % i

static func skip_initial_peek(gm: Node, tree: SceneTree) -> void:
	var wait := 0
	while gm.current_state != gm.GameState.INITIAL_PEEK and wait < 600:
		await tree.process_frame
		wait += 1
	if gm.current_state == gm.GameState.INITIAL_PEEK:
		gm.complete_initial_peek()

static func board_digest(board: Node3D) -> Dictionary:
	var digest := {
		"pending": 0,
		"discard_cards": 0,
		"deck_cards": 0,
		"board_nodes": 0,
		"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
	}
	if board == null:
		return digest
	var discard_area := board.get_node_or_null("DiscardArea")
	var deck_area := board.get_node_or_null("DeckArea")
	if discard_area:
		for c in discard_area.get_children():
			if c.has_method("setup"):
				digest.discard_cards += 1
	if deck_area:
		for c in deck_area.get_children():
			if c.has_method("setup"):
				digest.deck_cards += 1
	if board.get_node_or_null("PendingCard"):
		digest.pending = 1
	var stack: Array = [board]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		digest.board_nodes += 1
		for c in n.get_children():
			stack.append(c)
	return digest

static func pending_alive(board: Node3D) -> bool:
	if board == null:
		return false
	var n := board.get_node_or_null("PendingCard")
	return n != null and is_instance_valid(n)

static func load_board(tree: SceneTree) -> Node3D:
	var scene: PackedScene = load("res://game_board_3d.tscn")
	if scene == null:
		return null
	var board: Node3D = scene.instantiate()
	tree.root.add_child(board)
	return board

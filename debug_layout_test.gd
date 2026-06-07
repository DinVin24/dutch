extends Node

const HOST_WINDOW_SIZE := Vector2i(1280, 720)
const CLIENT_WINDOW_SIZE := Vector2i(400, 800)
const DEFAULT_TEST_PORT := 1234
const TEST_HOST := "127.0.0.1"
const SCREENSHOT_DIR := "res://debug/test_runs"
const HANDSHAKE_WAIT_SECONDS := 5.0
const AUTO_START_PLAYER_COUNT := 2
const AUTO_START_SEED := 424242
const CHECKPOINT_DELAYS := [1.0, 1.2, 1.2]
const FULL_GAME_TURNS := 4
const MAX_FULL_GAME_TURNS := 100
const MIN_TURNS_BEFORE_DUTCH := 6
const TURN_ACTION_DELAY := 0.75
const TURN_SETTLE_DELAY := 0.5
const TEST_SCREEN_INDEX := 1
const CONSOLE_SCREEN_INDEX := 0
const LIVE_LOG_HOST := "res://.debug/mp/live_server.log"
const LIVE_LOG_CLIENT := "res://.debug/mp/live_client.log"
## Hard cap for the WebRTC handshake. If game_started never fires, quit instead of hanging forever.
const CONNECTION_TIMEOUT_SEC := 40.0

enum TestRole {
	NONE,
	HOST,
	CLIENT
}

var _role: TestRole = TestRole.NONE
var _role_label: String = "Standalone"
var _screenshot_taken: bool = false
var _run_stamp: String = ""
var _auto_match_started: bool = false
var _test_port: int = DEFAULT_TEST_PORT
var _connection_established: bool = false

func _ready() -> void:
	_role = _resolve_role()
	if _role == TestRole.NONE:
		set_process_input(false)
		return

	print("DebugLayoutTest: ===== MP VISION TEST BOOT =====")
	print("DebugLayoutTest: cmdline=%s" % str(OS.get_cmdline_user_args()))
	_role_label = "Server" if _role == TestRole.HOST else "Client"
	print("DebugLayoutTest: role=%s (host=%s client=%s)" % [_role_label, _role == TestRole.HOST, _role == TestRole.CLIENT])
	_test_port = _resolve_test_port()
	_apply_test_audio_mute()
	_clear_live_log()
	_apply_window_layout()
	NetworkManager.player_connected.connect(_on_network_connected)
	NetworkManager.game_started.connect(_on_game_started)
	if NetworkManager.has_signal("lobby_error"):
		NetworkManager.lobby_error.connect(_on_lobby_error)
	if NetworkManager.has_signal("server_disconnected"):
		NetworkManager.server_disconnected.connect(_on_server_lost)
	set_process(_role != TestRole.NONE)
	call_deferred("_bootstrap_network_role")
	call_deferred("_start_connection_watchdog")

func _on_lobby_error(message: String) -> void:
	_test_log("LOBBY ERROR: %s" % message)
	print("DebugLayoutTest: [MP TEST] lobby error — %s" % message)

func _on_server_lost() -> void:
	if _connection_established:
		return
	_test_log("SERVER LOST before game start")
	print("DebugLayoutTest: [MP TEST] server disconnected before game start")

## Quit gracefully if the WebRTC handshake never completes, so the peer never hangs forever.
func _start_connection_watchdog() -> void:
	var elapsed := 0.0
	while elapsed < CONNECTION_TIMEOUT_SEC:
		if _connection_established:
			return
		if int(elapsed) % 5 == 0:
			_test_log("waiting MP connection %.0fs peers=%d room=%s" % [
				elapsed, NetworkManager.players.size(), NetworkManager.get_room_code()
			])
		await get_tree().create_timer(1.0).timeout
		elapsed += 1.0
	if _connection_established:
		return
	var msg := "VISION_RUN_COMPLETE role=%s ABORTED — MP connection timeout after %.0fs (peers=%d)" % [
		_role_label, CONNECTION_TIMEOUT_SEC, NetworkManager.players.size()
	]
	_test_log(msg)
	push_warning("DebugLayoutTest: " + msg)
	print("DebugLayoutTest: " + msg)
	get_tree().quit(1)

func _process(_delta: float) -> void:
	if _role == TestRole.NONE:
		return
	if get_tree().paused:
		get_tree().paused = false
		print("DebugLayoutTest: [MP TEST] auto-resumed (pause blocked during vision test)")
	_ensure_test_audio_muted()

func _ensure_test_audio_muted() -> void:
	for bus_name in ["Master", "Music", "SFX"]:
		var bus_idx := AudioServer.get_bus_index(bus_name)
		if bus_idx >= 0 and not AudioServer.is_bus_mute(bus_idx):
			AudioServer.set_bus_mute(bus_idx, true)

func _input(event: InputEvent) -> void:
	if _role == TestRole.NONE:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F12:
		if multiplayer.has_multiplayer_peer():
			_trigger_synced_screenshot.rpc()
		else:
			take_test_screenshot()

func _resolve_role() -> TestRole:
	var args := OS.get_cmdline_user_args()
	if "--host" in args:
		return TestRole.HOST
	if "--client" in args:
		return TestRole.CLIENT
	return TestRole.NONE

func _apply_test_audio_mute() -> void:
	for bus_name in ["Master", "Music", "SFX"]:
		var bus_idx := AudioServer.get_bus_index(bus_name)
		if bus_idx >= 0:
			AudioServer.set_bus_mute(bus_idx, true)
	GameManager.is_menu_music_active = false
	GameManager.is_game_music_active = false
	if GameManager.has_method("stop_all_music"):
		GameManager.stop_all_music()
	print("DebugLayoutTest: [MP TEST] audio muted for all test buses")
	_test_log("audio muted")

func _live_log_path() -> String:
	return LIVE_LOG_HOST if _role == TestRole.HOST else LIVE_LOG_CLIENT

func _clear_live_log() -> void:
	var path := _live_log_path()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.debug/mp"))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string("")
	_test_log("boot role=%s" % _role_label)

func _test_log(line: String) -> void:
	var path := _live_log_path()
	var abs_dir := ProjectSettings.globalize_path(path.get_base_dir())
	DirAccess.make_dir_recursive_absolute(abs_dir)
	var mode := FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE
	var f := FileAccess.open(path, mode)
	if f:
		if f.get_length() > 0:
			f.seek_end()
		f.store_line(line)

func _resolve_test_screen_index() -> int:
	var args := OS.get_cmdline_user_args()
	var idx := args.find("--test-screen")
	if idx != -1 and idx + 1 < args.size():
		var parsed := int(String(args[idx + 1]))
		if parsed >= 0 and parsed < DisplayServer.get_screen_count():
			return parsed
	if DisplayServer.get_screen_count() > TEST_SCREEN_INDEX:
		return TEST_SCREEN_INDEX
	return 0

func _apply_window_layout() -> void:
	var game_screen := _resolve_test_screen_index()
	DisplayServer.window_set_current_screen(game_screen)

	var screen_pos := DisplayServer.screen_get_position(game_screen)
	var screen_size := DisplayServer.screen_get_size(game_screen)
	var half_w := int(screen_size.x / 2)
	var target_h := mini(screen_size.y, 720)
	var target_w := mini(half_w - 8, 1280)
	var target_size := Vector2i(target_w, target_h)
	DisplayServer.window_set_size(target_size)

	var y := screen_pos.y + maxi(0, int((screen_size.y - target_size.y) / 2))
	var x := screen_pos.x + 4 if _role == TestRole.HOST else screen_pos.x + half_w + 4
	DisplayServer.window_set_position(Vector2i(x, y))
	print("DebugLayoutTest: Window %dx%d at (%d,%d) screen=%d half=%s role=%s" % [
		target_size.x, target_size.y, x, y, game_screen,
		"left" if _role == TestRole.HOST else "right", _role_label
	])
	_test_log("window %dx%d screen=%d %s" % [target_size.x, target_size.y, game_screen, _role_label])

func _bootstrap_network_role() -> void:
	# Ensure Multiplayer peers are only auto-started in explicit test mode.
	if _role == TestRole.HOST:
		NetworkManager.set_local_player_name("TestHost")
		var started: bool = bool(NetworkManager.host_game())
		if started:
			print("DebugLayoutTest: Host started via WebRTC")
			_test_log("host_game started, awaiting room code")
			call_deferred("_wait_for_host_room_code")
		else:
			push_warning("DebugLayoutTest: Failed to start host on port %d" % _test_port)
			_test_log("FAILED to start host")
		return

	NetworkManager.set_local_player_name("TestClient")
	var room_code := _resolve_room_code()
	var connected: bool = bool(NetworkManager.join_game(room_code))
	if connected:
		print("DebugLayoutTest: Client attempting to join via WebRTC room=%s" % room_code)
		_test_log("client join_game room=%s, awaiting handshake" % room_code)
	else:
		push_warning("DebugLayoutTest: Failed to connect client to room %s" % room_code)
		_test_log("FAILED to join room=%s" % room_code)

func _resolve_room_code() -> String:
	var args := OS.get_cmdline_user_args()
	var idx := args.find("--room-code")
	if idx != -1 and idx + 1 < args.size():
		return String(args[idx + 1]).strip_edges()
	idx = args.find("--room-code-file")
	if idx != -1 and idx + 1 < args.size():
		var path := String(args[idx + 1]).strip_edges()
		if FileAccess.file_exists(path):
			return FileAccess.get_file_as_string(path).strip_edges()
	return "TEST"

func _wait_for_host_room_code() -> void:
	const MAX_WAIT_SEC := 45.0
	var elapsed := 0.0
	while NetworkManager.get_room_code().strip_edges() == "" and elapsed < MAX_WAIT_SEC:
		await get_tree().create_timer(0.25).timeout
		elapsed += 0.25
	var code := NetworkManager.get_room_code().strip_edges()
	print("DebugLayoutTest: Host Room Code: ", code)
	if code != "":
		_write_room_code_file(code)
	else:
		push_warning("DebugLayoutTest: Timed out waiting for signaling room code")

func _write_room_code_file(code: String) -> void:
	var path := ProjectSettings.globalize_path("res://.debug/mp/room_code.txt")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open("res://.debug/mp/room_code.txt", FileAccess.WRITE)
	if f:
		f.store_string(code.strip_edges())
		print("DebugLayoutTest: Wrote room code to res://.debug/mp/room_code.txt")

func _capture_after_handshake_delay() -> void:
	await get_tree().create_timer(HANDSHAKE_WAIT_SECONDS).timeout
	take_test_screenshot("lobby_handshake")

func _resolve_connect_target() -> String:
	var args := OS.get_cmdline_user_args()
	var target := TEST_HOST
	var arg_index := args.find("--connect-to")
	if arg_index != -1:
		if arg_index + 1 < args.size():
			target = String(args[arg_index + 1]).strip_edges()
			if target == "":
				target = TEST_HOST
		else:
			push_warning("DebugLayoutTest: Missing IP after --connect-to, defaulting to %s" % TEST_HOST)
	return target

func _resolve_test_port() -> int:
	var args := OS.get_cmdline_user_args()
	var default_port := DEFAULT_TEST_PORT
	var arg_index := args.find("--port")
	if arg_index == -1 or arg_index + 1 >= args.size():
		return default_port
	var candidate := String(args[arg_index + 1]).strip_edges()
	if candidate.is_valid_int():
		var parsed := int(candidate)
		if parsed >= 1 and parsed <= 65535:
			return parsed
	return default_port

@rpc("any_peer", "call_local", "reliable")
func _trigger_synced_screenshot() -> void:
	take_test_screenshot("manual")

@rpc("any_peer", "call_local", "reliable")
func _trigger_synced_checkpoint(label: String) -> void:
	take_test_screenshot(label)

var _checkpoints_seen: Dictionary = {}

func take_test_screenshot(label: String = "checkpoint") -> void:
	if _run_stamp == "":
		_run_stamp = Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace(" ", "_")
	var abs_dir := ProjectSettings.globalize_path("%s/%s" % [SCREENSHOT_DIR, _run_stamp])
	var dir_error := DirAccess.make_dir_recursive_absolute(abs_dir)
	if dir_error != OK and dir_error != ERR_ALREADY_EXISTS:
		push_warning("DebugLayoutTest: Could not create screenshot directory. Error: %d" % dir_error)
		return

	var image := get_viewport().get_texture().get_image()
	var resolution := _resolution_label()
	var timestamp := Time.get_datetime_string_from_system().replace(":", "-").replace(" ", "_")
	var filename := "%s_%s_%s_%s.png" % [_role_label, label, resolution, timestamp]
	var path := "%s/%s" % [abs_dir, filename]
	var save_error := image.save_png(path)
	if save_error != OK:
		push_warning("DebugLayoutTest: Screenshot save failed. Error: %d" % save_error)
		return
	print("DebugLayoutTest: Saved screenshot -> ", path)
	print("DebugLayoutTest: CHECKPOINT %s role=%s" % [label, _role_label])
	_checkpoints_seen[label] = true

func _resolution_label() -> String:
	var size := DisplayServer.window_get_size()
	if size.y > 0:
		return "%dp" % size.y
	return "%dx%d" % [size.x, size.y]

func _on_network_connected(_id: int = -1, _info: Dictionary = {}) -> void:
	if _role == TestRole.HOST and not _auto_match_started and NetworkManager.players.size() >= AUTO_START_PLAYER_COUNT:
		_auto_match_started = true
		print("DebugLayoutTest: Auto-starting multiplayer match players=%d seed=%d" % [AUTO_START_PLAYER_COUNT, AUTO_START_SEED])
		NetworkManager.start_match.rpc(AUTO_START_PLAYER_COUNT, AUTO_START_SEED)
	if _screenshot_taken:
		return
	_screenshot_taken = true
	call_deferred("_capture_after_handshake_delay")

func _on_game_started() -> void:
	_connection_established = true
	print("DebugLayoutTest: [MP TEST] game_started — loading board role=%s" % _role_label)
	_test_log("game_started — MP connection OK (peers=%d)" % NetworkManager.players.size())
	_apply_test_audio_mute()
	get_tree().change_scene_to_file("res://game_board_3d.tscn")
	if not GameManager.multiplayer_sync_applied.is_connected(_on_mp_sync_applied):
		GameManager.multiplayer_sync_applied.connect(_on_mp_sync_applied)
	call_deferred("_run_checkpoint_flow")

func _on_mp_sync_applied() -> void:
	print("DebugLayoutTest: [SYNC] applied role=%s state=%s cur=P%d local=P%d drawn=%s" % [
		_role_label,
		GameManager.GameState.keys()[GameManager.current_state],
		GameManager.current_player_index,
		GameManager.local_player_idx,
		GameManager.drawn_card_data != null
	])

func _request_game_action(action: String) -> void:
	if multiplayer.is_server():
		GameManager.request_action(action)
	else:
		GameManager.request_action.rpc_id(1, action)

func _run_checkpoint_flow() -> void:
	print("DebugLayoutTest: [MP TEST] checkpoint flow start role=%s" % _role_label)
	_test_log("checkpoint flow start")
	await get_tree().create_timer(2.0).timeout
	await _ensure_turn_start_draw()
	await _resolve_blocking_fsm_states()
	_log_avatar_visibility("pre_deal")
	_trigger_synced_checkpoint.rpc("cp1_deal")
	await get_tree().create_timer(0.8).timeout
	await _resolve_blocking_fsm_states()
	_log_avatar_visibility("post_deal")
	_trigger_synced_checkpoint.rpc("cp_avatars")

	for turn_idx in MAX_FULL_GAME_TURNS:
		if GameManager.current_state == GameManager.GameState.GAME_OVER:
			break
		var turn_num := turn_idx + 1
		print("DebugLayoutTest: [MP TEST] === turn %d role=%s state=%s ===" % [
			turn_num, _role_label, GameManager.GameState.keys()[GameManager.current_state]
		])
		_test_log("turn %d cur=P%d local=P%d state=%s" % [
			turn_num, GameManager.current_player_index, GameManager.local_player_idx,
			GameManager.GameState.keys()[GameManager.current_state]
		])
		await _resolve_blocking_fsm_states()
		if GameManager.current_state == GameManager.GameState.GAME_OVER:
			break
		await _maybe_auto_call_dutch(turn_num)
		await _resolve_blocking_fsm_states()
		if GameManager.current_state == GameManager.GameState.GAME_OVER:
			break
		await _wait_until_my_turn(60.0)
		await _resolve_blocking_fsm_states()
		if GameManager.current_state == GameManager.GameState.GAME_OVER:
			break
		if GameManager.current_player_index == GameManager.local_player_idx \
				and GameManager.current_state == GameManager.GameState.TURN_START_DRAW:
			await _execute_draw_discard_turn(turn_num)
		else:
			await _wait_for_remote_turn_checkpoints(turn_num, 45.0)

	await get_tree().create_timer(1.0).timeout
	_log_avatar_visibility("final")
	if GameManager.current_state == GameManager.GameState.GAME_OVER:
		_trigger_synced_checkpoint.rpc("cp_game_over")
	else:
		push_warning("DebugLayoutTest: ended before GAME_OVER state=%s" % GameManager.GameState.keys()[GameManager.current_state])
	_trigger_synced_checkpoint.rpc("cp_final")
	var done_msg := "VISION_RUN_COMPLETE role=%s game_over=%s" % [
		_role_label, GameManager.current_state == GameManager.GameState.GAME_OVER
	]
	print("DebugLayoutTest: %s" % done_msg)
	_test_log(done_msg)
	get_tree().quit()

func _maybe_auto_call_dutch(turn_num: int) -> void:
	if not multiplayer.is_server() or turn_num < MIN_TURNS_BEFORE_DUTCH:
		return
	if GameManager.current_state == GameManager.GameState.TURN_END_CHOICE \
			and GameManager.can_player_call_dutch(GameManager.current_player_index):
		print("DebugLayoutTest: [FSM] auto call_dutch P%d turn=%d" % [GameManager.current_player_index, turn_num])
		GameManager.request_action("call_dutch")
		await get_tree().create_timer(0.8).timeout
	elif GameManager.current_state == GameManager.GameState.TURN_CONFIRM_DUTCH \
			and GameManager.can_player_confirm_dutch(GameManager.current_player_index):
		print("DebugLayoutTest: [FSM] auto confirm_dutch P%d" % GameManager.current_player_index)
		GameManager.request_action("confirm_dutch")
		await get_tree().create_timer(0.8).timeout

func _get_game_board() -> Node:
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("get_avatar_visibility_report"):
		return scene
	return null

func _log_avatar_visibility(tag: String) -> void:
	var board := _get_game_board()
	if board == null:
		print("DebugLayoutTest: [AVATAR] %s — board not ready" % tag)
		return
	var report: Dictionary = board.get_avatar_visibility_report()
	var active_seats := clampi(GameManager.num_players, 1, 4) if GameManager.is_multiplayer else 4
	print("DebugLayoutTest: [AVATAR] %s role=%s report=%s" % [tag, _role_label, str(report)])
	for p_idx in report.keys():
		# Inactive seats (beyond the active player count) are correctly hidden — don't flag them.
		if int(p_idx) >= active_seats:
			continue
		var entry: Dictionary = report[p_idx]
		var mesh_count := int(entry.get("visible_mesh_count", 0))
		var node_visible := bool(entry.get("avatar_node_visible", false))
		if entry.get("is_local", false):
			if node_visible or mesh_count > 0:
				push_warning("DebugLayoutTest: [AVATAR FAIL] %s local P%d must be hidden (node=%s meshes=%d)" % [
					tag, p_idx, node_visible, mesh_count
				])
				_test_log("AVATAR FAIL %s local P%d visible (node=%s meshes=%d)" % [tag, p_idx, node_visible, mesh_count])
			else:
				print("DebugLayoutTest: [AVATAR OK] %s local P%d hidden" % [tag, p_idx])
				_test_log("AVATAR OK %s local P%d hidden" % [tag, p_idx])
			continue
		if not node_visible or mesh_count <= 0:
			push_warning("DebugLayoutTest: [AVATAR FAIL] %s remote P%d not visible (node=%s meshes=%d)" % [
				tag, p_idx, node_visible, mesh_count
			])
			_test_log("AVATAR FAIL %s remote P%d not visible (node=%s meshes=%d)" % [tag, p_idx, node_visible, mesh_count])
		else:
			print("DebugLayoutTest: [AVATAR OK] %s remote P%d meshes=%d" % [tag, p_idx, mesh_count])
			_test_log("AVATAR OK %s remote P%d meshes=%d" % [tag, p_idx, mesh_count])

func _resolve_blocking_fsm_states() -> void:
	if not GameManager.is_multiplayer or not multiplayer.is_server():
		return
	var state := GameManager.current_state
	var ap := GameManager.active_ability_player
	if state == GameManager.GameState.TURN_PEEK_ABILITY and ap >= 0:
		if GameManager.can_player_complete_peek_ability(ap):
			print("DebugLayoutTest: [FSM] auto complete_peek_ability P%d" % ap)
			GameManager.request_action("complete_peek_ability")
			await get_tree().create_timer(0.8).timeout
	elif state == GameManager.GameState.TURN_SWAP_ABILITY and ap >= 0:
		if GameManager.can_player_complete_swap_ability(ap):
			var other := (ap + 1) % GameManager.num_players
			print("DebugLayoutTest: [FSM] auto complete_swap_ability P%d <-> P%d" % [ap, other])
			GameManager.request_action("complete_swap_ability", {
				"p1": ap, "c1": 0, "p2": other, "c2": 0
			})
			await get_tree().create_timer(1.0).timeout
	elif state == GameManager.GameState.TURN_CONFIRM_DUTCH:
		if GameManager.can_player_cancel_dutch(GameManager.current_player_index):
			print("DebugLayoutTest: [FSM] auto cancel_dutch P%d" % GameManager.current_player_index)
			GameManager.request_action("cancel_dutch")
			await get_tree().create_timer(0.5).timeout

func _wait_until_my_turn(max_sec: float) -> void:
	var elapsed := 0.0
	while elapsed < max_sec:
		if GameManager.current_state == GameManager.GameState.GAME_OVER:
			return
		if GameManager.current_player_index == GameManager.local_player_idx:
			await _resolve_blocking_fsm_states()
			if GameManager.current_state == GameManager.GameState.TURN_RESOLVE_DRAWN \
					and GameManager.can_player_discard_drawn_card(GameManager.local_player_idx):
				print("DebugLayoutTest: [TURN] finish pending discard local=P%d" % GameManager.local_player_idx)
				_request_game_action("discard_drawn")
				await get_tree().create_timer(0.6).timeout
				elapsed += 0.6
				continue
			if GameManager.current_state == GameManager.GameState.TURN_END_CHOICE \
					and GameManager.can_player_end_turn(GameManager.local_player_idx):
				print("DebugLayoutTest: [TURN] end_turn local=P%d" % GameManager.local_player_idx)
				_request_game_action("end_turn")
				await get_tree().create_timer(0.6).timeout
				elapsed += 0.6
				continue
			if GameManager.current_state == GameManager.GameState.TURN_START_DRAW:
				print("DebugLayoutTest: [TURN] my turn local=P%d" % GameManager.local_player_idx)
				return
		if int(elapsed * 4) % 8 == 0:
			print("DebugLayoutTest: [SYNC] waiting my turn role=%s cur=P%d local=P%d state=%s" % [
				_role_label,
				GameManager.current_player_index,
				GameManager.local_player_idx,
				GameManager.GameState.keys()[GameManager.current_state]
			])
		await get_tree().create_timer(0.25).timeout
		elapsed += 0.25
	push_warning("DebugLayoutTest: Timed out waiting for my turn (cur=P%d local=P%d)" % [
		GameManager.current_player_index, GameManager.local_player_idx
	])

func _execute_draw_discard_turn(turn_num: int) -> void:
	if GameManager.current_player_index != GameManager.local_player_idx:
		push_warning("DebugLayoutTest: skip turn %d — not my seat (cur=P%d local=P%d)" % [
			turn_num, GameManager.current_player_index, GameManager.local_player_idx
		])
		return
	await _ensure_turn_start_draw()
	if GameManager.current_state != GameManager.GameState.TURN_START_DRAW:
		push_warning("DebugLayoutTest: skip turn %d — state=%s" % [
			turn_num, GameManager.GameState.keys()[GameManager.current_state]
		])
		return
	print("DebugLayoutTest: [TURN %d] draw role=%s" % [turn_num, _role_label])
	_request_game_action("draw_card")
	await get_tree().create_timer(TURN_ACTION_DELAY).timeout
	_trigger_synced_checkpoint.rpc("cp%d_drawn" % turn_num)
	await get_tree().create_timer(TURN_SETTLE_DELAY).timeout
	await _resolve_blocking_fsm_states()
	if GameManager.current_state == GameManager.GameState.TURN_RESOLVE_DRAWN:
		print("DebugLayoutTest: [TURN %d] discard role=%s" % [turn_num, _role_label])
		_request_game_action("discard_drawn")
	await get_tree().create_timer(TURN_ACTION_DELAY).timeout
	await _resolve_blocking_fsm_states()
	_trigger_synced_checkpoint.rpc("cp%d_discarded" % turn_num)

func _wait_for_remote_turn_checkpoints(turn_num: int, max_sec: float) -> void:
	var elapsed := 0.0
	var drawn_key := "cp%d_drawn" % turn_num
	var discarded_key := "cp%d_discarded" % turn_num
	while elapsed < max_sec:
		if _checkpoints_seen.get(discarded_key, false):
			return
		if int(elapsed * 4) % 12 == 0:
			print("DebugLayoutTest: [SYNC] remote turn %d role=%s cur=P%d state=%s" % [
				turn_num, _role_label, GameManager.current_player_index,
				GameManager.GameState.keys()[GameManager.current_state]
			])
		await get_tree().create_timer(0.25).timeout
		elapsed += 0.25
	if not _checkpoints_seen.get(drawn_key, false):
		push_warning("DebugLayoutTest: Remote turn %d — missing checkpoint %s" % [turn_num, drawn_key])

func _ensure_turn_start_draw() -> void:
	const MAX_WAIT_SEC := 45.0
	var elapsed := 0.0
	while elapsed < MAX_WAIT_SEC:
		var state := GameManager.current_state
		if state == GameManager.GameState.TURN_START_DRAW:
			print("DebugLayoutTest: Ready for draw phase (role=%s)" % _role_label)
			return
		if state == GameManager.GameState.INITIAL_PEEK:
			print("DebugLayoutTest: Auto-skipping initial peek (role=%s)" % _role_label)
			_request_game_action("initial_peek_done")
		elif state in [
			GameManager.GameState.TURN_PEEK_ABILITY,
			GameManager.GameState.TURN_SWAP_ABILITY,
			GameManager.GameState.TURN_CONFIRM_DUTCH,
		]:
			await _resolve_blocking_fsm_states()
		await get_tree().create_timer(0.5).timeout
		elapsed += 0.5
	push_warning("DebugLayoutTest: Timed out waiting for TURN_START_DRAW (state=%s)" % GameManager.GameState.keys()[GameManager.current_state])

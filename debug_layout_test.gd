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

func _ready() -> void:
	_role = _resolve_role()
	if _role == TestRole.NONE:
		set_process_input(false)
		return

	_role_label = "Server" if _role == TestRole.HOST else "Client"
	_test_port = _resolve_test_port()
	_apply_window_layout()
	NetworkManager.player_connected.connect(_on_network_connected)
	NetworkManager.game_started.connect(_on_game_started)
	call_deferred("_bootstrap_network_role")

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

func _apply_window_layout() -> void:
	var target_size := HOST_WINDOW_SIZE if _role == TestRole.HOST else CLIENT_WINDOW_SIZE
	DisplayServer.window_set_size(target_size)

	var screen_index := DisplayServer.window_get_current_screen()
	var screen_pos := DisplayServer.screen_get_position(screen_index)
	var screen_size := DisplayServer.screen_get_size(screen_index)
	var x := screen_pos.x if _role == TestRole.HOST else screen_pos.x + screen_size.x - target_size.x
	var y := screen_pos.y + maxi(0, int((screen_size.y - target_size.y) / 2))
	DisplayServer.window_set_position(Vector2i(x, y))

func _bootstrap_network_role() -> void:
	# Ensure Multiplayer peers are only auto-started in explicit test mode.
	if _role == TestRole.HOST:
		NetworkManager.set_local_player_name("TestHost")
		var started: bool = bool(NetworkManager.host_game())
		if started:
			print("DebugLayoutTest: Host started via WebRTC")
			var code := NetworkManager.get_room_code()
			print("DebugLayoutTest: Host Room Code: ", code)
			_write_room_code_file(code)
		else:
			push_warning("DebugLayoutTest: Failed to start host on port %d" % _test_port)
		return

	NetworkManager.set_local_player_name("TestClient")
	var room_code := _resolve_room_code()
	var connected: bool = bool(NetworkManager.join_game(room_code))
	if connected:
		print("DebugLayoutTest: Client attempting to join via WebRTC room=%s" % room_code)
	else:
		push_warning("DebugLayoutTest: Failed to connect client to room %s" % room_code)

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
	get_tree().change_scene_to_file("res://game_board_3d.tscn")
	call_deferred("_run_checkpoint_flow")

func _run_checkpoint_flow() -> void:
	await get_tree().create_timer(2.0).timeout
	if _role == TestRole.HOST:
		_trigger_synced_checkpoint.rpc("cp1_deal")
		await get_tree().create_timer(float(CHECKPOINT_DELAYS[0])).timeout
		GameManager.request_action("draw_card")
		await get_tree().create_timer(float(CHECKPOINT_DELAYS[1])).timeout
		_trigger_synced_checkpoint.rpc("cp2_drawn")
		GameManager.request_action("discard_drawn")
		await get_tree().create_timer(float(CHECKPOINT_DELAYS[2])).timeout
		_trigger_synced_checkpoint.rpc("cp3_discarded")

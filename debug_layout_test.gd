extends Node

const HOST_WINDOW_SIZE := Vector2i(1280, 720)
const CLIENT_WINDOW_SIZE := Vector2i(400, 800)
const TEST_PORT := 1234
const TEST_HOST := "127.0.0.1"
const SCREENSHOT_DIR := "res://debug/test_runs"
const HANDSHAKE_WAIT_SECONDS := 5.0

enum TestRole {
	NONE,
	HOST,
	CLIENT
}

var _role: TestRole = TestRole.NONE
var _role_label: String = "Standalone"
var _screenshot_taken: bool = false

func _ready() -> void:
	_role = _resolve_role()
	if _role == TestRole.NONE:
		set_process_input(false)
		return

	_role_label = "Server" if _role == TestRole.HOST else "Client"
	_apply_window_layout()
	NetworkManager.player_connected.connect(_on_network_connected)
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
	var y := screen_pos.y + int(maxi(0, (screen_size.y - target_size.y) / 2))
	DisplayServer.window_set_position(Vector2i(x, y))

func _bootstrap_network_role() -> void:
	# Ensure Multiplayer peers are only auto-started in explicit test mode.
	if _role == TestRole.HOST:
		NetworkManager.set_local_player_name("TestHost")
		var started: bool = bool(NetworkManager.host_game(TEST_PORT))
		if started:
			print("DebugLayoutTest: Host started on UDP port ", TEST_PORT)
			print("DebugLayoutTest: Host LAN IPv4 candidate: ", NetworkManager.get_detected_host_lan_ip())
		else:
			push_warning("DebugLayoutTest: Failed to start host on port %d" % TEST_PORT)
		return

	NetworkManager.set_local_player_name("TestClient")
	var target_host := _resolve_connect_target()
	var connected: bool = bool(NetworkManager.connect_to_host_direct(target_host, TEST_PORT))
	if connected:
		print("DebugLayoutTest: Client connecting to %s:%d" % [target_host, TEST_PORT])
	else:
		push_warning("DebugLayoutTest: Failed to connect client to %s:%d" % [target_host, TEST_PORT])

func _on_network_connected(_id: int = -1, _info: Dictionary = {}) -> void:
	if _screenshot_taken:
		return
	_screenshot_taken = true
	call_deferred("_capture_after_handshake_delay")

func _capture_after_handshake_delay() -> void:
	await get_tree().create_timer(HANDSHAKE_WAIT_SECONDS).timeout
	take_test_screenshot()

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

@rpc("any_peer", "call_local", "reliable")
func _trigger_synced_screenshot() -> void:
	take_test_screenshot()

func take_test_screenshot() -> void:
	var abs_dir := ProjectSettings.globalize_path(SCREENSHOT_DIR)
	var dir_error := DirAccess.make_dir_recursive_absolute(abs_dir)
	if dir_error != OK and dir_error != ERR_ALREADY_EXISTS:
		push_warning("DebugLayoutTest: Could not create screenshot directory. Error: %d" % dir_error)
		return

	var image := get_viewport().get_texture().get_image()
	var resolution := _resolution_label()
	var timestamp := Time.get_datetime_string_from_system().replace(":", "-").replace(" ", "_")
	var filename := "Test_%s_%s_%s.png" % [_role_label, resolution, timestamp]
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

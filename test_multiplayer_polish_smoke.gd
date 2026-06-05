extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var failures: Array[String] = []
	var sm: Node = load("res://settings_manager.gd").new()
	root.add_child(sm)
	await process_frame
	_test_room_code_persistence(sm, failures)
	if failures.is_empty():
		print("PASS: multiplayer polish smoke")
		quit(0)
	else:
		for f in failures:
			print("FAIL: ", f)
		quit(1)

func _test_room_code_persistence(sm: Node, failures: Array[String]) -> void:
	sm.set_last_room_code("ZZTOP9")
	sm.set_player_name("SmokeTester")
	if sm.get_last_room_code() != "ZZTOP9":
		failures.append("last_room_code round-trip failed")
	if sm.get_player_name() != "SmokeTester":
		failures.append("player_name round-trip failed")
	sm.set_last_room_code("  abcd99  ")
	if sm.get_last_room_code() != "ABCD99":
		failures.append("room code should be trimmed and uppercased on save")

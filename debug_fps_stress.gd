extends SceneTree

## Windowed FPS / process-time stress sampler (P-3 manual complement).
## Run with display: flatpak run org.godotengine.Godot --path . -s res://debug_fps_stress.gd
## Headless falls back to object-count stress only.

const OUT_LOG := "res://.debug/mp/fps_stress.log"
const CYCLES := 30

var _gm: Node
var _board: Node3D

func _init() -> void:
	call_deferred("_run")

func _log(line: String) -> void:
	print(line)
	var f := FileAccess.open(OUT_LOG, FileAccess.READ_WRITE if FileAccess.file_exists(OUT_LOG) else FileAccess.WRITE)
	if f:
		if f.get_length() > 0:
			f.seek_end()
		f.store_line(line)

func _run() -> void:
	_log("=== DEBUG FPS STRESS ===")
	_gm = root.get_node_or_null("GameManager")
	if _gm == null:
		_log("[FAIL] GameManager missing")
		quit(1)
		return

	var scene: PackedScene = load("res://game_board_3d.tscn")
	_board = scene.instantiate()
	root.add_child(_board)
	await process_frame
	await create_timer(1.0).timeout

	while _gm.current_state != _gm.GameState.INITIAL_PEEK:
		await process_frame
	_gm.complete_initial_peek()

	var min_fps := 9999.0
	var samples := 0
	var baseline_obj := int(Performance.get_monitor(Performance.OBJECT_COUNT))

	for i in CYCLES:
		_gm.current_player_index = i % 4
		_gm.change_state(_gm.GameState.TURN_START_DRAW, true)
		_gm.player_draw_card()
		if _gm.drawn_card_data != null:
			_gm.player_discard_drawn_card()
		await process_frame
		await process_frame
		var fps := Performance.get_monitor(Performance.TIME_FPS)
		if fps > 0:
			min_fps = minf(min_fps, fps)
			samples += 1

	await create_timer(1.0).timeout
	var settled_obj := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	_log("[P-3] cycles=%d min_fps=%.1f samples=%d obj_delta=%+d" % [CYCLES, min_fps, samples, settled_obj - baseline_obj])

	if DisplayServer.get_name() == "headless":
		_log("[P-3 DOC] Run windowed for real FPS; headless TIME_FPS may be 0")
		_log("VERDICT: headless object stress complete")
		quit(0)
	elif min_fps >= 55.0:
		_log("VERDICT: FPS OK min=%.1f (target >=55)" % min_fps)
		quit(0)
	else:
		_log("VERDICT: FPS LOW min=%.1f — capture Profiler V10" % min_fps)
		quit(1)

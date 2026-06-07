extends Control

const COLOR_MAGENTA := Color(1.0, 0.1, 0.6)
const COLOR_CYAN := Color(0.0, 1.0, 1.0)
const MIN_DISPLAY_SEC := 1.1
const PROGRESS_SMOOTH_SPEED := 5.5

const STATUS_LINES: Array[String] = [
	"> initializing deck...",
	"> loading table assets...",
	"> syncing card engine...",
	"> preparing match state...",
]

@onready var fade_overlay: ColorRect = $FadeOverlay
@onready var content_root: CenterContainer = $Center
@onready var progress_bar: ProgressBar = $Center/OuterMargin/PanelShell/InnerMargin/Panel/ProgressBar
@onready var percent_label: Label = $Center/OuterMargin/PanelShell/InnerMargin/Panel/PercentLabel
@onready var status_label: Label = $Center/OuterMargin/PanelShell/InnerMargin/Panel/StatusLabel

var _target_path: String = ""
var _load_ready := false
var _min_time_elapsed := false
var _transitioning := false
var _status_index := 0
var _status_timer := 0.0
var _display_progress := 0.0
var _target_progress := 0.0

func _ready() -> void:
	_target_path = SceneLoader.pending_scene_path
	if _target_path == "":
		_target_path = "res://game_board_3d.tscn"
	_apply_theme()
	_play_enter_animation()
	ResourceLoader.load_threaded_request(_target_path)
	get_tree().create_timer(MIN_DISPLAY_SEC).timeout.connect(func(): _min_time_elapsed = true)
	_update_status_line()

func _apply_theme() -> void:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.04, 0.02, 0.08, 0.96)
	panel_style.border_color = COLOR_MAGENTA
	panel_style.set_border_width_all(2)
	panel_style.shadow_color = Color(COLOR_MAGENTA.r, COLOR_MAGENTA.g, COLOR_MAGENTA.b, 0.25)
	panel_style.shadow_size = 8
	panel_style.content_margin_left = 20
	panel_style.content_margin_right = 20
	panel_style.content_margin_top = 18
	panel_style.content_margin_bottom = 16
	$Center/OuterMargin/PanelShell.add_theme_stylebox_override("panel", panel_style)

	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.1, 0.05, 0.14, 0.9)
	track.set_corner_radius_all(3)
	progress_bar.add_theme_stylebox_override("background", track)

	var fill := StyleBoxFlat.new()
	fill.bg_color = COLOR_CYAN
	fill.border_color = COLOR_MAGENTA
	fill.set_border_width_all(1)
	fill.set_corner_radius_all(3)
	progress_bar.add_theme_stylebox_override("fill", fill)

func _play_enter_animation() -> void:
	fade_overlay.color = Color(0.02, 0.0, 0.06, 1.0)
	content_root.modulate.a = 0.0
	content_root.scale = Vector2(0.96, 0.96)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(fade_overlay, "color:a", 0.0, 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(content_root, "modulate:a", 1.0, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(content_root, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _process(delta: float) -> void:
	_status_timer += delta
	if _status_timer >= 0.5:
		_status_timer = 0.0
		_status_index = (_status_index + 1) % STATUS_LINES.size()
		_update_status_line()

	var progress_arr: Array = []
	var status := ResourceLoader.load_threaded_get_status(_target_path, progress_arr)
	if progress_arr.size() > 0:
		_target_progress = float(progress_arr[0]) * 100.0
	_display_progress = lerpf(_display_progress, _target_progress, delta * PROGRESS_SMOOTH_SPEED)
	progress_bar.value = _display_progress
	percent_label.text = "%d%%" % int(round(_display_progress))

	match status:
		ResourceLoader.THREAD_LOAD_LOADED:
			_target_progress = 100.0
			_load_ready = true
			_try_transition()
		ResourceLoader.THREAD_LOAD_FAILED:
			status_label.text = "// LOAD_FAILED — retrying..."
			ResourceLoader.load_threaded_request(_target_path)

func _update_status_line() -> void:
	var tween := create_tween()
	tween.tween_property(status_label, "modulate:a", 0.35, 0.08)
	tween.tween_callback(func(): status_label.text = STATUS_LINES[_status_index])
	tween.tween_property(status_label, "modulate:a", 1.0, 0.12)

func _try_transition() -> void:
	if _transitioning or not (_load_ready and _min_time_elapsed):
		return
	if _display_progress < 99.5:
		return
	_transitioning = true
	set_process(false)
	_play_exit_animation()

func _play_exit_animation() -> void:
	status_label.text = "// MATCH_READY"
	percent_label.text = "100%"
	var tween := create_tween()
	tween.tween_property(progress_bar, "value", 100.0, 0.18)
	tween.tween_interval(0.3)
	tween.tween_property(fade_overlay, "color:a", 1.0, 0.42).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(content_root, "modulate:a", 0.0, 0.35)
	tween.tween_callback(_launch_game)

func _launch_game() -> void:
	var packed: PackedScene = ResourceLoader.load_threaded_get(_target_path) as PackedScene
	if packed == null:
		status_label.text = "// LOAD_FAILED"
		_transitioning = false
		set_process(true)
		return
	SceneLoader.pending_scene_path = ""
	get_tree().change_scene_to_packed(packed)
	SceneLoader.finish_transition()

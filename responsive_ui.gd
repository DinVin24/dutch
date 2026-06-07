extends Node

## Shared layout helpers so HUD/menus scale across window sizes and mobile.

const DESIGN_SIZE := Vector2(1280.0, 720.0)
const TOUCH_SLOP_PX := 24.0

func _ready() -> void:
	_apply_content_scale()

func _apply_content_scale() -> void:
	var root := get_tree().root
	if root == null:
		return
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND

func get_ui_scale() -> float:
	var vp := get_viewport().get_visible_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return 1.0
	return clampf(min(vp.x / DESIGN_SIZE.x, vp.y / DESIGN_SIZE.y), 0.55, 1.35)

func get_margin() -> float:
	return 16.0 * get_ui_scale()

func get_touch_slop() -> float:
	return TOUCH_SLOP_PX * get_ui_scale()

func is_touch_device() -> bool:
	return DisplayServer.is_touchscreen_available()

func is_narrow_screen() -> bool:
	return get_viewport().get_visible_rect().size.x < 900.0

func scaled_font(base: int) -> int:
	return maxi(12, int(round(float(base) * get_ui_scale())))

func scaled_size(base: Vector2) -> Vector2:
	return base * get_ui_scale()

func anchor_control_edges(control: Control, margin: float, top: float, right: float, bottom: float, left: float) -> void:
	if control == null:
		return
	control.set_anchors_preset(Control.PRESET_FULL_RECT)
	control.offset_left = left
	control.offset_top = top
	control.offset_right = -right
	control.offset_bottom = -bottom

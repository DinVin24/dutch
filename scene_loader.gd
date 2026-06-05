extends Node

const FADE_COLOR := Color(0.02, 0.0, 0.06, 1.0)
const FADE_IN_SEC := 0.38
const FADE_OUT_SEC := 0.65

var pending_scene_path: String = ""

func change_scene(scene_path: String) -> void:
	pending_scene_path = scene_path
	_fade_out_to_loading()

func finish_transition() -> void:
	call_deferred("_fade_in_new_scene")

func _fade_out_to_loading() -> void:
	var tree := get_tree()
	if tree == null:
		return
	if tree.root == null:
		tree.change_scene_to_file("res://loading_screen.tscn")
		return
	var fade := _make_fade_rect()
	fade.color = Color(FADE_COLOR.r, FADE_COLOR.g, FADE_COLOR.b, 0.0)
	tree.root.add_child(fade)
	var tween := tree.create_tween()
	tween.tween_property(fade, "color:a", 1.0, FADE_IN_SEC).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_callback(func():
		fade.queue_free()
		tree.change_scene_to_file("res://loading_screen.tscn")
	)

func _fade_in_new_scene() -> void:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return
	_remove_existing_fade(tree.root)
	var fade := _make_fade_rect()
	fade.color = FADE_COLOR
	tree.root.add_child(fade)
	var tween := tree.create_tween()
	tween.tween_property(fade, "color:a", 0.0, FADE_OUT_SEC).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_callback(fade.queue_free)

func _make_fade_rect() -> ColorRect:
	var fade := ColorRect.new()
	fade.name = "SceneTransitionFade"
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.z_index = 4096
	return fade

func _remove_existing_fade(root: Node) -> void:
	var existing := root.get_node_or_null("SceneTransitionFade")
	if existing:
		existing.queue_free()

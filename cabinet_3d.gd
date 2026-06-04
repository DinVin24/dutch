extends Node3D

# The distance (in meters) the drawer slides out along the local Z axis
const SLIDE_DISTANCE := 0.25
const SLIDE_DURATION := 0.45

## Maximum distance from camera at which this cabinet responds to interaction
const MAX_INTERACT_DISTANCE := 4.5

# Hammer hover animation constants
const HAMMER_HOVER_RISE   := 0.035  # meters to rise in Y
const HAMMER_HOVER_SHAKE  := 0.004  # shake amplitude

# References to drawer nodes
var _shelves: Array[MeshInstance3D] = []
# Cache of initial Z positions
var _initial_z: Array[float] = []
# Open/close state of drawers
var _is_open: Array[bool] = [false, false, false]
# Active Tween for each drawer
var _tweens: Array[Tween] = [null, null, null]

# Per-hammer tracking
var _hammers: Array[Node3D] = []
var _hammer_base_pos: Array[Vector3] = []
var _hammer_omnis: Array[OmniLight3D] = []
var _hammer_orig_mats: Array = []        # Array[Array[Material]] — per hammer, per mesh
var _hovered_hammer_idx: int = -1
var _hammer_shake_time: float = 0.0
var _sparkles: Array[Node3D] = []

# The player slot this cabinet belongs to (set by game_board_3d)
var player_index: int = -1

# Gold hover material (shared)
var _gold_mat: StandardMaterial3D = null

func _ready() -> void:
	_gold_mat = StandardMaterial3D.new()
	_gold_mat.albedo_color = Color(1.0, 0.75, 0.1)
	_gold_mat.emission_enabled = true
	_gold_mat.emission = Color(1.0, 0.7, 0.0)
	_gold_mat.emission_energy_multiplier = 3.0
	_gold_mat.roughness = 0.3
	_gold_mat.metallic = 0.9

	# Find the main mesh group inside the instantiated GLB
	var mesh_group = find_child("Simple Wooden Drawer Table Type B Wood 01_0", true, false)
	if not mesh_group:
		push_error("Cabinet3D: Could not find main wood mesh group!")
		return

	var r1 = mesh_group.get_node_or_null("raft1")
	var r2 = mesh_group.get_node_or_null("raft2")
	var r3 = mesh_group.get_node_or_null("raft3")

	if not (r1 and r2 and r3):
		push_error("Cabinet3D: One or more drawer mesh instances were not found!")
		return

	_shelves = [r1, r2, r3]

	for i in range(3):
		var shelf = _shelves[i]
		_initial_z.append(shelf.position.z)

		var area = Area3D.new()
		area.name = "Area3D_" + shelf.name
		area.collision_layer = 8
		area.collision_mask = 0
		shelf.add_child(area)

		var col_shape = CollisionShape3D.new()
		var box = BoxShape3D.new()
		box.size = Vector3(0.38, 0.18, 0.35)
		col_shape.shape = box
		col_shape.position = Vector3(0.0, 0.006, -0.117)
		area.add_child(col_shape)
		area.set_meta("shelf_index", i)

## Returns true if the shelf at the given index is open
func is_shelf_open(index: int) -> bool:
	if index < 0 or index >= _is_open.size():
		return false
	return _is_open[index]

## Returns the user-facing name for the shelf at the given index
func get_shelf_name(index: int) -> String:
	match index:
		0: return "Top Drawer"
		1: return "Middle Drawer"
		2: return "Bottom Drawer"
	return "Drawer"

## Check if a camera is close enough to interact with this cabinet
func is_in_range(cam_global_pos: Vector3) -> bool:
	return global_position.distance_to(cam_global_pos) <= MAX_INTERACT_DISTANCE

## Animates opening or closing of the drawer at the given index
func toggle_shelf(index: int) -> void:
	if index < 0 or index >= _shelves.size():
		return
	var shelf = _shelves[index]
	var current_open_state = _is_open[index]
	var target_z = _initial_z[index]
	if not current_open_state:
		target_z += SLIDE_DISTANCE
	_is_open[index] = not current_open_state
	if _tweens[index] and _tweens[index].is_running():
		_tweens[index].kill()
	var tween = create_tween()
	_tweens[index] = tween
	tween.tween_property(shelf, "position:z", target_z, SLIDE_DURATION)\
		.set_trans(Tween.TRANS_CUBIC)\
		.set_ease(Tween.EASE_OUT)

## Shake + rise applied every frame while a hammer is hovered
func _process(delta: float) -> void:
	if _hovered_hammer_idx < 0 or _hovered_hammer_idx >= _hammers.size():
		return
	var h = _hammers[_hovered_hammer_idx]
	if not is_instance_valid(h):
		return
	_hammer_shake_time += delta * 30.0
	var s = HAMMER_HOVER_SHAKE
	var base = _hammer_base_pos[_hovered_hammer_idx]
	h.position = base + Vector3(
		sin(_hammer_shake_time * 1.7) * s,
		HAMMER_HOVER_RISE + sin(_hammer_shake_time * 2.5) * s * 0.5,
		cos(_hammer_shake_time * 1.3) * s
	)

## Applies hover effect: rise, gold material, intensified light
func hover_hammer(i: int) -> void:
	if i < 0 or i >= _hammers.size():
		return
	if _hovered_hammer_idx == i:
		return
	if _hovered_hammer_idx >= 0:
		unhover_hammer(_hovered_hammer_idx)
	_hovered_hammer_idx = i
	_hammer_shake_time = 0.0
	# Intensify OmniLight
	if i < _hammer_omnis.size() and is_instance_valid(_hammer_omnis[i]):
		var tw = create_tween()
		tw.tween_property(_hammer_omnis[i], "light_energy", 10.0, 0.15)
	# Apply gold material to all MeshInstance3D children
	var h = _hammers[i]
	if not is_instance_valid(h):
		return
	var meshes = _collect_meshes(h)
	if i < _hammer_orig_mats.size():
		_hammer_orig_mats[i] = _collect_orig_mats(meshes)
	for mesh in meshes:
		for surf in range(mesh.get_surface_override_material_count()):
			mesh.set_surface_override_material(surf, _gold_mat)

## Removes hover effect: restores original materials and light
func unhover_hammer(i: int) -> void:
	if i < 0 or i >= _hammers.size():
		return
	if _hovered_hammer_idx == i:
		_hovered_hammer_idx = -1
	# Restore position
	if i < _hammer_base_pos.size() and is_instance_valid(_hammers[i]):
		var tw = create_tween()
		tw.tween_property(_hammers[i], "position", _hammer_base_pos[i], 0.15)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Dim OmniLight
	if i < _hammer_omnis.size() and is_instance_valid(_hammer_omnis[i]):
		var tw2 = create_tween()
		tw2.tween_property(_hammer_omnis[i], "light_energy", 3.5, 0.2)
	# Restore original materials
	var h = _hammers[i]
	if not is_instance_valid(h):
		return
	var meshes = _collect_meshes(h)
	if i < _hammer_orig_mats.size():
		var orig_arr = _hammer_orig_mats[i]
		for m_idx in range(min(meshes.size(), orig_arr.size())):
			var mesh = meshes[m_idx]
			var mats = orig_arr[m_idx]
			for surf in range(min(mesh.get_surface_override_material_count(), mats.size())):
				mesh.set_surface_override_material(surf, mats[surf])

func _collect_meshes(root: Node3D) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for child in root.get_children():
		if child is MeshInstance3D:
			result.append(child)
		result.append_array(_collect_meshes(child))
	return result

func _collect_orig_mats(meshes: Array[MeshInstance3D]) -> Array:
	var result := []
	for mesh in meshes:
		var surf_mats := []
		for surf in range(mesh.get_surface_override_material_count()):
			surf_mats.append(mesh.get_surface_override_material(surf))
		result.append(surf_mats)
	return result

## Returns the number of hammers currently in the cabinet
func get_hammer_count() -> int:
	return _hammers.size()

## Returns the hammer Node3D at slot index i, or null
func get_hammer_at(i: int) -> Node3D:
	if i < 0 or i >= _hammers.size():
		return null
	return _hammers[i]

## Spawns/despawns hammer models based on the player's active abilities count.
## player_idx is stored in each hammer's Area3D meta so game_board_3d can identify the owner.
func update_hammers(count: int, p_idx: int = -1) -> void:
	if p_idx >= 0:
		player_index = p_idx
	var target_count = clamp(count, 0, 6)

	# Unhover any active hammer
	if _hovered_hammer_idx >= 0:
		unhover_hammer(_hovered_hammer_idx)
	_hovered_hammer_idx = -1

	for h in _hammers:
		if is_instance_valid(h):
			h.queue_free()
	_hammers.clear()
	_hammer_base_pos.clear()
	_hammer_omnis.clear()
	_hammer_orig_mats.clear()

	for s in _sparkles:
		if is_instance_valid(s):
			s.queue_free()
	_sparkles.clear()

	if _shelves.size() < 3:
		return

	var hammer_scene = load("res://assets/models/medium_poly_hammer.glb")
	if not hammer_scene:
		push_error("Cabinet3D: Could not load hammer model!")
		return

	# 6 slot positions: 0,1 = top drawer; 2,3 = middle; 4,5 = bottom
	var slots = [
		{"shelf": 0, "pos": Vector3(-0.03, -0.07, -0.09)},
		{"shelf": 0, "pos": Vector3(0.11,  -0.07, -0.09)},
		{"shelf": 1, "pos": Vector3(-0.03, -0.07, -0.09)},
		{"shelf": 1, "pos": Vector3(0.11,  -0.07, -0.09)},
		{"shelf": 2, "pos": Vector3(-0.03, -0.07, -0.09)},
		{"shelf": 2, "pos": Vector3(0.11,  -0.07, -0.09)}
	]

	for i in range(target_count):
		var slot = slots[i]
		var shelf_node = _shelves[slot.shelf]
		if not is_instance_valid(shelf_node):
			continue

		var hammer = hammer_scene.instantiate()
		shelf_node.add_child(hammer)
		hammer.position = slot.pos

		# Scale to ~0.008 global
		var pg_scale = shelf_node.global_transform.basis.get_scale()
		var local_s = Vector3(0.008, 0.008, 0.008)
		if pg_scale.x > 0.0001: local_s.x /= pg_scale.x
		if pg_scale.y > 0.0001: local_s.y /= pg_scale.y
		if pg_scale.z > 0.0001: local_s.z /= pg_scale.z
		hammer.scale = local_s
		hammer.rotation_degrees = Vector3(90.0, -140.0, 0.0)

		_hammers.append(hammer)
		_hammer_base_pos.append(slot.pos)
		_hammer_orig_mats.append([])  # will be populated lazily on first hover

		# Golden OmniLight
		var omni = OmniLight3D.new()
		omni.light_color = Color(1.0, 0.85, 0.3)
		omni.light_energy = 3.5
		omni.omni_range = 0.5
		hammer.add_child(omni)
		_hammer_omnis.append(omni)

		# Area3D for hover/click detection on layer 8
		# The hammer scale is ~0.008 globally, so we need a large local box (40 units = 32cm)
		var hammer_area = Area3D.new()
		hammer_area.name = "HammerArea3D"
		hammer_area.collision_layer = 8
		hammer_area.collision_mask = 0
		hammer_area.set_meta("hammer_index", i)
		hammer_area.set_meta("player_index", player_index)
		hammer.add_child(hammer_area)

		var hammer_col = CollisionShape3D.new()
		var hammer_box = BoxShape3D.new()
		hammer_box.size = Vector3(40.0, 40.0, 40.0)  # Large in local space → ~32cm global
		hammer_col.shape = hammer_box
		hammer_area.add_child(hammer_col)

		# Floating sparkles
		var mat = StandardMaterial3D.new()
		mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1.0, 0.9, 0.4)

		var sphere_mesh = SphereMesh.new()
		sphere_mesh.radius = 0.003
		sphere_mesh.height = 0.006

		var sparkle_offsets = [
			{"offset": Vector3(-0.03, 0.03, 0.04), "scale": 1.2},
			{"offset": Vector3(0.02, 0.05, -0.02), "scale": 0.8},
			{"offset": Vector3(0.04, 0.04, -0.06), "scale": 1.0},
			{"offset": Vector3(-0.01, 0.06, 0.0),  "scale": 0.7}
		]

		for j in range(sparkle_offsets.size()):
			var data = sparkle_offsets[j]
			var sparkle = MeshInstance3D.new()
			sparkle.mesh = sphere_mesh
			sparkle.material_override = mat
			shelf_node.add_child(sparkle)
			sparkle.position = slot.pos + data.offset
			sparkle.scale = Vector3(data.scale, data.scale, data.scale)

			var tw = sparkle.create_tween().set_loops()
			var bp = sparkle.position
			var tp = bp + Vector3(0.0, 0.012, 0.0)
			var bs = sparkle.scale
			var ts = bs * 1.5
			var dur = 0.6 + j * 0.15
			tw.tween_property(sparkle, "position", tp, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			tw.parallel().tween_property(sparkle, "scale", ts, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			tw.tween_property(sparkle, "position", bp, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			tw.parallel().tween_property(sparkle, "scale", bs, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			_sparkles.append(sparkle)

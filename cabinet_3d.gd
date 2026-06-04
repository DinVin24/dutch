extends Node3D

# The distance (in meters) the drawer slides out along the local Z axis
const SLIDE_DISTANCE := 0.25
const SLIDE_DURATION := 0.45

# Hammer hover animation constants
const HAMMER_HOVER_RISE   := 0.035  # meters to rise in Y
const HAMMER_HOVER_SHAKE  := 0.004  # shake amplitude
const HAMMER_HOVER_DUR    := 0.18   # tween duration for rise

# References to drawer nodes
var _shelves: Array[MeshInstance3D] = []
# Cache of initial Z positions
var _initial_z: Array[float] = []
# Open/close state of drawers: false = closed, true = open
var _is_open: Array[bool] = [false, false, false]
# Active Tween for each drawer to prevent animation overlaps
var _tweens: Array[Tween] = [null, null, null]

# Per-hammer tracking
var _hammers: Array[Node3D] = []           # hammer root nodes
var _hammer_base_pos: Array[Vector3] = []  # original local positions
var _hammer_omnis: Array[OmniLight3D] = [] # golden omni lights per hammer
var _hovered_hammer_idx: int = -1          # which hammer is hovered (-1 = none)
var _hammer_shake_time: float = 0.0        # accumulated time for shake
var _sparkles: Array[Node3D] = []

func _ready() -> void:
	# Find the main mesh group inside the instantiated GLB
	var mesh_group = find_child("Simple Wooden Drawer Table Type B Wood 01_0", true, false)
	if not mesh_group:
		push_error("Cabinet3D: Could not find main wood mesh group!")
		return
	
	# Fetch references to the three drawers
	var r1 = mesh_group.get_node_or_null("raft1")
	var r2 = mesh_group.get_node_or_null("raft2")
	var r3 = mesh_group.get_node_or_null("raft3")
	
	if not (r1 and r2 and r3):
		push_error("Cabinet3D: One or more drawer mesh instances (raft1, raft2, raft3) were not found!")
		return
	
	_shelves = [r1, r2, r3]
	
	# Set up each shelf with its Area3D collision and record initial position
	for i in range(3):
		var shelf = _shelves[i]
		_initial_z.append(shelf.position.z)
		
		# Create an Area3D for drawer-level raycast interaction (shelf toggling)
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

## Called every frame by the board to apply hammer shake when hovered
func _process(delta: float) -> void:
	if _hovered_hammer_idx < 0 or _hovered_hammer_idx >= _hammers.size():
		return
	var h = _hammers[_hovered_hammer_idx]
	if not is_instance_valid(h):
		return
	_hammer_shake_time += delta * 28.0
	var s = HAMMER_HOVER_SHAKE
	var base = _hammer_base_pos[_hovered_hammer_idx]
	# Rise + shake combined
	h.position = base + Vector3(
		sin(_hammer_shake_time * 1.7) * s,
		HAMMER_HOVER_RISE + sin(_hammer_shake_time * 2.3) * s * 0.5,
		cos(_hammer_shake_time * 1.3) * s
	)

## Applies hover effect to hammer at index i
func hover_hammer(i: int) -> void:
	if i < 0 or i >= _hammers.size():
		return
	if _hovered_hammer_idx == i:
		return
	# Unhover the previous one first
	if _hovered_hammer_idx >= 0:
		unhover_hammer(_hovered_hammer_idx)
	_hovered_hammer_idx = i
	_hammer_shake_time = 0.0
	# Intensify the golden light
	if i < _hammer_omnis.size() and is_instance_valid(_hammer_omnis[i]):
		var tween = create_tween()
		tween.tween_property(_hammer_omnis[i], "light_energy", 8.0, 0.15)

## Removes hover effect from hammer at index i
func unhover_hammer(i: int) -> void:
	if i < 0 or i >= _hammers.size():
		return
	if _hovered_hammer_idx == i:
		_hovered_hammer_idx = -1
	# Restore hammer to base position
	if i < _hammer_base_pos.size() and is_instance_valid(_hammers[i]):
		var tween = create_tween()
		tween.tween_property(_hammers[i], "position", _hammer_base_pos[i], 0.15)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Dim the golden light back
	if i < _hammer_omnis.size() and is_instance_valid(_hammer_omnis[i]):
		var tween2 = create_tween()
		tween2.tween_property(_hammer_omnis[i], "light_energy", 3.5, 0.2)

## Returns the number of hammers currently in the cabinet
func get_hammer_count() -> int:
	return _hammers.size()

## Returns the hammer Node3D at slot index i, or null
func get_hammer_at(i: int) -> Node3D:
	if i < 0 or i >= _hammers.size():
		return null
	return _hammers[i]

## Spawns/despawns hammer models in the drawers based on the player's active abilities count
func update_hammers(count: int) -> void:
	# Clamp to max 6 slots
	var target_count = clamp(count, 0, 6)
	
	# Unhover if needed
	_hovered_hammer_idx = -1
	
	# Clear existing hammers, sparkles, omnis
	for h in _hammers:
		if is_instance_valid(h):
			h.queue_free()
	_hammers.clear()
	_hammer_base_pos.clear()
	_hammer_omnis.clear()
	
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
		
	# Slot positions inside drawer meshes:
	# 0, 1: raft1 (top), left and right
	# 2, 3: raft2 (middle), left and right
	# 4, 5: raft3 (bottom), left and right
	var slots = [
		{"shelf": 0, "pos": Vector3(-0.03, -0.07, -0.09)}, # top left
		{"shelf": 0, "pos": Vector3(0.11, -0.07, -0.09)},  # top right
		{"shelf": 1, "pos": Vector3(-0.03, -0.07, -0.09)}, # middle left
		{"shelf": 1, "pos": Vector3(0.11, -0.07, -0.09)},  # middle right
		{"shelf": 2, "pos": Vector3(-0.03, -0.07, -0.09)}, # bottom left
		{"shelf": 2, "pos": Vector3(0.11, -0.07, -0.09)}   # bottom right
	]
	
	for i in range(target_count):
		var slot = slots[i]
		var shelf_node = _shelves[slot.shelf]
		if not is_instance_valid(shelf_node):
			continue

		var hammer = hammer_scene.instantiate()
		shelf_node.add_child(hammer)
		hammer.position = slot.pos
		
		# Scale to global 0.008
		var parent_global_scale = shelf_node.global_transform.basis.get_scale()
		var local_s = Vector3(0.008, 0.008, 0.008)
		if parent_global_scale.x > 0.0001: local_s.x /= parent_global_scale.x
		if parent_global_scale.y > 0.0001: local_s.y /= parent_global_scale.y
		if parent_global_scale.z > 0.0001: local_s.z /= parent_global_scale.z
		hammer.scale = local_s
		hammer.rotation_degrees = Vector3(90.0, -140.0, 0.0)
		
		_hammers.append(hammer)
		_hammer_base_pos.append(slot.pos)
		
		# Golden OmniLight
		var omni = OmniLight3D.new()
		omni.light_color = Color(1.0, 0.85, 0.3)
		omni.light_energy = 3.5
		omni.omni_range = 0.5
		hammer.add_child(omni)
		_hammer_omnis.append(omni)
		
		# Add an Area3D with a collision box for hammer-level raycasting (layer 8)
		var hammer_area = Area3D.new()
		hammer_area.name = "HammerArea3D"
		hammer_area.collision_layer = 8
		hammer_area.collision_mask = 0
		hammer_area.set_meta("hammer_index", i)
		# Set cabinet owner meta so the board can find which cabinet this belongs to
		hammer_area.set_meta("cabinet_node", self)
		hammer.add_child(hammer_area)
		
		var hammer_col = CollisionShape3D.new()
		var hammer_box = BoxShape3D.new()
		# A small box around the hammer head in local hammer space
		hammer_box.size = Vector3(5.0, 5.0, 5.0)  # large in hammer-local space because of tiny scale
		hammer_col.shape = hammer_box
		hammer_area.add_child(hammer_col)
		
		# Sparkles
		var mat = StandardMaterial3D.new()
		mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1.0, 0.9, 0.4)
		
		var sphere_mesh = SphereMesh.new()
		sphere_mesh.radius = 0.003
		sphere_mesh.height = 0.006
		
		var sparkles_data = [
			{"offset": Vector3(-0.03, 0.03, 0.04), "scale": 1.2},
			{"offset": Vector3(0.02, 0.05, -0.02), "scale": 0.8},
			{"offset": Vector3(0.04, 0.04, -0.06), "scale": 1.0},
			{"offset": Vector3(-0.01, 0.06, 0.0), "scale": 0.7}
		]
		
		for j in range(sparkles_data.size()):
			var data = sparkles_data[j]
			var sparkle = MeshInstance3D.new()
			sparkle.mesh = sphere_mesh
			sparkle.material_override = mat
			shelf_node.add_child(sparkle)
			sparkle.position = slot.pos + data.offset
			sparkle.scale = Vector3(data.scale, data.scale, data.scale)
			
			var tween = sparkle.create_tween().set_loops()
			var base_pos = sparkle.position
			var target_pos = base_pos + Vector3(0.0, 0.012, 0.0)
			var base_scale = sparkle.scale
			var target_scale = base_scale * 1.5
			
			var duration = 0.6 + j * 0.15
			tween.tween_property(sparkle, "position", target_pos, duration)\
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			tween.parallel().tween_property(sparkle, "scale", target_scale, duration)\
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
				
			tween.tween_property(sparkle, "position", base_pos, duration)\
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			tween.parallel().tween_property(sparkle, "scale", base_scale, duration)\
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
				
			_sparkles.append(sparkle)

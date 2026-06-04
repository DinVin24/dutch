extends Node3D

# The distance (in meters) the drawer slides out along the local Z axis
const SLIDE_DISTANCE := 0.25
const SLIDE_DURATION := 0.45

# References to drawer nodes
var _shelves: Array[MeshInstance3D] = []
# Cache of initial Z positions
var _initial_z: Array[float] = []
# Open/close state of drawers: false = closed, true = open
var _is_open: Array[bool] = [false, false, false]
# Active Tween for each drawer to prevent animation overlaps
var _tweens: Array[Tween] = [null, null, null]
var _hammers: Array[Node3D] = []
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
		
		# Create an Area3D for raycast interaction
		var area = Area3D.new()
		area.name = "Area3D_" + shelf.name
		# We use Collision Layer 4 (value 8) to avoid interference with other game systems (cards, etc.)
		area.collision_layer = 8
		area.collision_mask = 0 # No monitoring needed
		shelf.add_child(area)
		
		# Create a Box collision shape matching the drawer's geometry
		var col_shape = CollisionShape3D.new()
		var box = BoxShape3D.new()
		
		# Drawer AABB Size is approximately: Width 0.38, Height 0.18, Depth 0.35
		box.size = Vector3(0.38, 0.18, 0.35)
		col_shape.shape = box
		
		# Center of drawer AABB relative to drawer origin is approx (0, 0.006, -0.117)
		col_shape.position = Vector3(0.0, 0.006, -0.117)
		area.add_child(col_shape)
		
		# Attach metadata to easily identify the shelf index on collision
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
	
	# Determine target Z position
	var target_z = _initial_z[index]
	if not current_open_state:
		# Slide forward along local Z
		target_z += SLIDE_DISTANCE
	
	# Toggle state
	_is_open[index] = not current_open_state
	
	# Handle active Tween cleanup
	if _tweens[index] and _tweens[index].is_running():
		_tweens[index].kill()
	
	# Create a smooth sliding Tween
	var tween = create_tween()
	_tweens[index] = tween
	tween.tween_property(shelf, "position:z", target_z, SLIDE_DURATION)\
		.set_trans(Tween.TRANS_CUBIC)\
		.set_ease(Tween.EASE_OUT)

## Spawns/despawns hammer models in the drawers based on the player's active abilities count
func update_hammers(count: int) -> void:
	# Clamp count to max 6 slots
	var target_count = clamp(count, 0, 6)
	
	# Clear existing hammers and sparkles
	for h in _hammers:
		if is_instance_valid(h):
			h.queue_free()
	_hammers.clear()
	
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
		
	# Slots positions inside drawer meshes:
	# 0, 1: raft1 (top), left and right
	# 2, 3: raft2 (middle), left and right
	# 4, 5: raft3 (bottom), left and right
	# Shifted right (-0.03 and 0.11) and forward (-0.09) and down (-0.07) relative to drawer root
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
		if is_instance_valid(shelf_node):
			var hammer = hammer_scene.instantiate()
			shelf_node.add_child(hammer)
			hammer.position = slot.pos
			
			# Calculate the local scale required to achieve a global scale of Vector3(0.008, 0.008, 0.008)
			var parent_global_scale = shelf_node.global_transform.basis.get_scale()
			var local_s = Vector3(0.008, 0.008, 0.008)
			if parent_global_scale.x > 0.0001: local_s.x /= parent_global_scale.x
			if parent_global_scale.y > 0.0001: local_s.y /= parent_global_scale.y
			if parent_global_scale.z > 0.0001: local_s.z /= parent_global_scale.z
			hammer.scale = local_s
			
			# Match rotation shown in editor manually placed reference
			hammer.rotation_degrees = Vector3(90.0, -140.0, 0.0)
			
			_hammers.append(hammer)
			
			# 1. Glowing Gold OmniLight3D (casts golden light on wooden drawer base)
			var omni = OmniLight3D.new()
			omni.light_color = Color(1.0, 0.85, 0.3)
			omni.light_energy = 3.5
			omni.omni_range = 0.5
			hammer.add_child(omni)
			
			# 2. Gold Sparkles (billboard unshaded spheres floating above hammer)
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
				
				# Animate float and scale loop
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

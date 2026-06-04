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

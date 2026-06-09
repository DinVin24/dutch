extends Node3D
class_name AbilityToken3D

signal token_clicked(token: AbilityToken3D)

const GRID_TEXTURE = preload("res://assets/images/cards/ability_grid.jpg")
const GRID_COLS = 13.0
const GRID_ROWS = 5.0

# User-defined order in Row 0
const ABILITY_ORDER = [
	"bottoms_up", "refuel", "trim_off", "boulder", 
	"reverse", "skip", "perfect_match", "inflation", 
	"half_off", "jumpscare", "shuffle", "polarity_shift"
]

@onready var front_face: MeshInstance3D = $Visuals/FrontFace
@onready var back_face: MeshInstance3D = $Visuals/BackFace
@onready var area: Area3D = $Area3D

var ability_id: String
var target_player_idx: int = -1
var is_active: bool = true
var is_face_up: bool = false
var is_animating: bool = false

func setup(p_id: String):
	ability_id = p_id
	if is_node_ready():
		_update_visuals()

func _ready():
	if area:
		area.input_event.connect(_on_input_event)
	_update_visuals()

func _update_visuals() -> void:
	if not ability_id: return
	_apply_textures()
	
	if not is_animating:
		# 0 degrees = face down (back showing), 180 degrees = face up (front showing)
		$Visuals.rotation_degrees.y = 180.0 if is_face_up else 0.0

func _apply_textures():
	if GRID_TEXTURE == null:
		push_error("AbilityToken3D: ability grid texture failed to preload")
		return

	var col = ABILITY_ORDER.find(ability_id)
	if col == -1:
		push_error("AbilityToken3D: Ability ID not found in mapping: " + ability_id)
		return

	var front_mat = StandardMaterial3D.new()
	front_mat.albedo_texture = GRID_TEXTURE
	front_mat.uv1_scale = Vector3(1.0/GRID_COLS, 1.0/GRID_ROWS, 1.0)
	front_mat.uv1_offset = Vector3(float(col)/GRID_COLS, 0.0, 0.0)
	front_mat.roughness = 0.8
	front_face.set_surface_override_material(0, front_mat)

	var back_mat = StandardMaterial3D.new()
	back_mat.albedo_texture = GRID_TEXTURE
	back_mat.uv1_scale = Vector3(1.0/GRID_COLS, 1.0/GRID_ROWS, 1.0)
	back_mat.uv1_offset = Vector3(0.0, 4.0/GRID_ROWS, 0.0)
	back_mat.roughness = 0.8
	back_face.set_surface_override_material(0, back_mat)

func set_face_up(p_up: bool):
	is_face_up = p_up
	_update_visuals()

func animate_flip(p_up: bool):
	if is_animating: return
	is_animating = true
	is_face_up = p_up
	
	if GameManager:
		GameManager.play_sfx(GameManager.sfx_card_flip)
	
	var target_y = 180.0 if p_up else 0.0
	var tween = create_tween()
	
	# Lift and roll
	tween.set_parallel(true)
	tween.tween_property($Visuals, "rotation_degrees:y", target_y, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property($Visuals, "position:y", 0.3, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	tween.chain().tween_property($Visuals, "position:y", 0.0, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	
	tween.finished.connect(func():
		is_animating = false
		_update_visuals()
	)

func _on_input_event(_camera, event, _position, _normal, _shape_idx):
	if not is_active or is_animating: return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		token_clicked.emit(self)

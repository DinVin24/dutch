extends Node3D
class_name Card3D

signal card_clicked(card_node, card_data)
signal card_flipped(card_node, card_data)

@onready var front_face: MeshInstance3D = $Visuals/FrontFace
@onready var back_face: MeshInstance3D = $Visuals/BackFace
@onready var area: Area3D = $Area3D

var data: CardData
var is_flipping: bool = false
var is_selected: bool = false
var is_highlighted: bool = false
var highlight_tween: Tween = null

const SPRITE_SHEET_PATH = "res://assets/images/cards/playing_cards.png"
const CARD_WIDTH = 100
const CARD_HEIGHT = 140
const SUIT_ORDER = ["Hearts", "Diamonds", "Clubs", "Spades"]
const RANK_ORDER = ["Ace", "2", "3", "4", "5", "6", "7", "8", "9", "10", "Jack", "Queen", "King"]

static var _master_texture: Texture2D = null

var _current_suit: String = ""
var _current_rank: String = ""

func setup(p_data: CardData) -> void:
	data = p_data
	if is_node_ready():
		_update_visuals()

func _ready():
	_update_visuals()
	if area:
		area.input_event.connect(_on_input_event)
		area.input_ray_pickable = true
	else:
		print("Card3D Error: Area3D not found!")

func _update_visuals() -> void:
	if not data: return
	_apply_atlas_textures()
	
	# In 3D, both faces are always physically there, just on opposite sides.
	# We rely on rotation to show the correct side.
	front_face.show()
	back_face.show()
	
	# Selection visuals
	if is_selected:
		# Premium glow / lift for selection
		scale = Vector3(1.1, 1.1, 1.1)
	else:
		scale = Vector3(1.0, 1.0, 1.0)

func _apply_atlas_textures():
	if _master_texture == null:
		if not FileAccess.file_exists(SPRITE_SHEET_PATH):
			return
		_master_texture = load(SPRITE_SHEET_PATH)
	
	if not _master_texture: return

	# Front Face
	# Optimization: only rebuild material if data changed
	if _current_suit == data.suit and _current_rank == data.rank:
		return
		
	_current_suit = data.suit
	_current_rank = data.rank

	var row = SUIT_ORDER.find(data.suit.capitalize())
	var col = RANK_ORDER.find(data.rank.capitalize())
	if row == -1 or col == -1: 
		print("Card3D Error: Rank/Suit not found: ", data.rank, "/", data.suit)
		return

	var front_mat = StandardMaterial3D.new()
	front_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	front_mat.albedo_texture = _master_texture
	front_mat.uv1_scale = Vector3(1.0/13.0, 1.0/5.0, 1.0)
	front_mat.uv1_offset = Vector3(float(col)/13.0, float(row)/5.0, 0.0)
	front_face.set_surface_override_material(0, front_mat)

	# Back Face (Row 4, Col 0)
	var back_mat = StandardMaterial3D.new()
	back_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	back_mat.albedo_texture = _master_texture
	back_mat.uv1_scale = Vector3(1.0/13.0, 1.0/5.0, 1.0)
	back_mat.uv1_offset = Vector3(0.0, 4.0/5.0, 0.0)
	back_face.set_surface_override_material(0, back_mat)

func _on_input_event(_camera, event, _position, _normal, _shape_idx):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		card_clicked.emit(self, data)

func set_selected(p_selected: bool):
	is_selected = p_selected
	_update_visuals()

func flip() -> void:
	animate_flip(!data.is_face_up)

func animate_flip(is_face_up: bool, target_y: float = -1.0):
	if is_flipping: return
	is_flipping = true
	
	# To flip a flat card (X=90) to its other side (X=-90 or 270)
	var target_rot_x = 90.0 if not is_face_up else 270.0
	
	var tween = create_tween()
	# Use current Y as baseline if target_y not specified
	var base_y = target_y if target_y >= 0 else position.y
	
	tween.set_parallel(true)
	tween.tween_property(self, "rotation_degrees:x", target_rot_x, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "position:y", base_y + 0.4, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	tween.chain().tween_property(self, "position:y", base_y, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	
	tween.finished.connect(func():
		is_flipping = false
		data.is_face_up = is_face_up
		_update_visuals()
		card_flipped.emit(self, data)
	)

func set_highlight(enabled: bool):
	is_highlighted = enabled
	if highlight_tween: highlight_tween.kill()
	
	if enabled:
		highlight_tween = create_tween().set_loops()
		# Pulse lift
		highlight_tween.tween_property(self, "position:y", 0.3, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		highlight_tween.tween_property(self, "position:y", 0.05, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	else:
		highlight_tween = create_tween()
		# Return to standard table/hand height
		highlight_tween.tween_property(self, "position:y", 0.05, 0.2).set_trans(Tween.TRANS_QUAD)
		highlight_tween.finished.connect(func(): highlight_tween = null)

func set_interactive(enabled: bool):
	$Area3D/CollisionShape3D.disabled = !enabled

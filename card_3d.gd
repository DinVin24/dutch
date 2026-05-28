extends Node3D
class_name Card3D

signal card_clicked(card_node, card_data)
signal card_flipped(card_node, card_data)
signal hover_state_changed(card_node, is_hovering: bool)

@onready var front_face: MeshInstance3D = $Visuals/FrontFace
@onready var back_face: MeshInstance3D = $Visuals/BackFace
@onready var area: Area3D = $Area3D

var multiplier_label: Label3D
var data: CardData
var is_flipping: bool = false
var is_selected: bool = false
var is_highlighted: bool = false
var is_being_peeked: bool = false
var is_discarding: bool = false # NEW: Deletion guard for animations
var highlight_tween: Tween = null
var _wobble_time: float = 0.0
var _base_visual_pos: Vector3

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
	_base_visual_pos = $Visuals.position
	
	# Multiplier Tag (floating above card)
	var anchor = Node3D.new()
	anchor.name = "MultiplierAnchor"
	anchor.top_level = true # Decouple from parent's 90-degree rotation
	add_child(anchor)
	
	multiplier_label = Label3D.new()
	multiplier_label.name = "MultiplierLabel"
	multiplier_label.font_size = 72
	multiplier_label.outline_size = 24
	multiplier_label.outline_modulate = Color(0, 0, 0, 1)
	# Position it at origin of anchor, process will sync anchor to card + offset
	multiplier_label.position = Vector3.ZERO
	multiplier_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	multiplier_label.no_depth_test = true
	anchor.add_child(multiplier_label)
	
	_update_visuals()
	if area:
		area.input_event.connect(_on_input_event)
		area.mouse_entered.connect(_on_mouse_entered)
		area.mouse_exited.connect(_on_mouse_exited)
		area.input_ray_pickable = true
	else:
		print("Card3D Error: Area3D not found!")

func _update_visuals() -> void:
	if not data: return
	
	# Update multiplier label - ALWAYS RUN this regardless of texture optimization
	if multiplier_label:
		if data.point_modifier > 1.0:
			multiplier_label.text = "x2"
			multiplier_label.modulate = Color(1.0, 0.0, 0.0) # Solid Red for inflation
			multiplier_label.show()
		elif data.point_modifier < 1.0:
			multiplier_label.text = "x1/2"
			multiplier_label.modulate = Color(0.0, 1.0, 0.0) # Solid Green for half-down
			multiplier_label.show()
		else:
			multiplier_label.hide()
			
	_apply_atlas_textures()
	
	# Face visibility is handled by local rotation of Visuals.
	# Do not override the rotation while mid-flip or while the card is being peeked
	# (peek is local-only and does not persist data.is_face_up, so the rotation must be
	# left alone until the peek window closes).
	var target_is_up = data.is_face_up
	if not is_flipping and not is_being_peeked:
		$Visuals.rotation_degrees.y = 180.0 if target_is_up else 0.0

	
	# Selection visuals
	if is_selected:
		# Premium glow / lift for selection
		scale = Vector3(0.95, 0.95, 0.95)
	else:
		scale = Vector3(0.85, 0.85, 0.85)

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
	
	front_mat.metallic = 0.0
	front_mat.roughness = 0.95
	# user requested removal of blue highlights, so we keep emission OFF
	
	front_face.set_surface_override_material(0, front_mat)

	# Back Face (Row 4, Col 0)
	var back_mat = StandardMaterial3D.new()
	back_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	back_mat.albedo_texture = _master_texture
	back_mat.uv1_scale = Vector3(1.0/13.0, 1.0/5.0, 1.0)
	back_mat.uv1_offset = Vector3(0.0, 4.0/5.0, 0.0)
	
	back_mat.metallic = 0.0
	back_mat.roughness = 0.95
	# user requested removal of blue highlights, so we keep emission OFF
		
	back_face.set_surface_override_material(0, back_mat)

func _on_input_event(_camera, event, _position, _normal, _shape_idx):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		card_clicked.emit(self, data)

func _on_mouse_entered():
	hover_state_changed.emit(self, true)

func _on_mouse_exited():
	hover_state_changed.emit(self, false)

func set_selected(p_selected: bool):
	is_selected = p_selected
	_update_visuals()

func flip() -> void:
	animate_flip(!data.is_face_up)

func animate_flip(is_face_up: bool, target_y: float = -1.0, persist_data_state: bool = true):
	if is_flipping: return
	is_flipping = true
	
	GameManager.play_sfx(GameManager.sfx_card_flip)
	
	if highlight_tween:
		highlight_tween.kill()
		highlight_tween = null
	
	# We rotate ONLY the 'Visuals' sub-node to flip, while the root Card3D 
	# node stays locked to the hand layout's table orientation.
	var target_basis = Basis.from_euler(Vector3.ZERO)
	if is_face_up:
		target_basis = target_basis * Basis(Vector3.UP, PI)
		
	var tween = create_tween()
	var base_y = target_y if target_y >= 0 else position.y
	
	tween.set_parallel(true)
	# Perform the barrel roll on the visuals node (local Y rotation)
	tween.tween_property($Visuals, "quaternion", target_basis.get_rotation_quaternion(), 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	# Root node still handles the lift/drop
	tween.tween_property(self, "position:y", base_y + 0.8, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	tween.chain().tween_property(self, "position:y", base_y, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	
	tween.finished.connect(func():
		is_flipping = false
		# Peek effects must be visual-only in multiplayer; callers can disable data persistence.
		if persist_data_state:
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

func _process(delta: float):
	if is_flipping:
		# Let the flip tween own the visuals transform
		return

	# While the card is being peeked, the Visuals node is owned by the peek animation.
	# _process must not override the quaternion or it will instantly snap the card face-down
	# (because data.is_face_up is intentionally kept false during a local-only peek).
	if is_being_peeked:
		# Still sync the multiplier anchor position
		var peek_anchor = get_node_or_null("MultiplierAnchor")
		if peek_anchor:
			peek_anchor.global_position = global_position + Vector3(0, 0.4, 0)
		return
		
	# Base rotation for face-up/down
	var base_rot_y = deg_to_rad(180.0 if data and data.is_face_up else 0.0)
	var base_q = Quaternion(Vector3.UP, base_rot_y)
	
	# Sync the floating multiplier tag to be 0.4 meters above the card in GLOBAL space
	var anchor = get_node_or_null("MultiplierAnchor")
	if anchor:
		anchor.global_position = global_position + Vector3(0, 0.4, 0)

	if is_highlighted or is_selected:
		_wobble_time += delta * 5.0
		var wobble_offset = Vector3(0, sin(_wobble_time) * 0.02, 0)
		var wobble_rot = Vector3(
			deg_to_rad(sin(_wobble_time * 0.8) * 2.0),
			deg_to_rad(cos(_wobble_time * 1.2) * 2.0),
			deg_to_rad(sin(_wobble_time * 0.5) * 2.0)
		)
		
		$Visuals.position = _base_visual_pos + wobble_offset
		# Combine wobble with face-up base rotation
		$Visuals.quaternion = base_q * Quaternion.from_euler(wobble_rot)
		
		# Sync Area3D transform to match Visuals
		$Area3D.position = $Visuals.position
		$Area3D.quaternion = $Visuals.quaternion
	else:
		$Visuals.position = _base_visual_pos
		$Visuals.quaternion = base_q
		$Area3D.position = _base_visual_pos
		$Area3D.quaternion = base_q

extends Control
class_name CardUI
const CardData = preload("res://card_data.gd")

signal card_clicked(card_node, card_data)
signal card_flipped(card_node, card_data)

@onready var front_face: TextureRect = $FrontFace
@onready var back_face: TextureRect = $BackFace
@onready var rank_label: Label = $FrontFace/RankLabel
@onready var suit_label: Label = $FrontFace/SuitLabel

var data: CardData
var is_flipping: bool = false
var is_selected: bool = false
var is_highlighted: bool = false
var highlight_tween: Tween = null

# Path configuration
const SPRITE_SHEET_PATH = "res://assets/images/cards/playing_cards.png"
const CARD_WIDTH = 100
const CARD_HEIGHT = 140

# Grid mapping (Matching user's exact specification)
const SUIT_ORDER = ["Hearts", "Diamonds", "Clubs", "Spades"]
const RANK_ORDER = ["Ace", "2", "3", "4", "5", "6", "7", "8", "9", "10", "Jack", "Queen", "King"]

# Static cache to avoid reloading the same file 52 times
static var _master_texture: Texture2D = null

func setup(p_data: CardData) -> void:
	data = p_data
	if is_node_ready():
		_update_visuals()

func _ready():
	_update_visuals()

func _update_visuals() -> void:
	if not data:
		return
	
	if not front_face or not back_face:
		return
		
	# Coordinate / Texture setup
	_apply_atlas_textures()
	
	# Visibility Handling
	if data.is_face_up:
		front_face.show()
		back_face.hide()
		
		# Text fallback / overlay logic
		rank_label.text = str(data.rank)
		suit_label.text = str(data.suit)
		
		var s = data.suit.capitalize()
		var is_red = (s == "Hearts" or s == "Diamonds")
		var color = Color(0.8, 0.1, 0.1) if is_red else Color(0, 0, 0)
		
		rank_label.add_theme_color_override("font_color", color)
		suit_label.add_theme_color_override("font_color", color)
		
		# Hide labels IF the texture loaded successfully
		if front_face.texture != null and front_face.texture is AtlasTexture and front_face.texture.atlas != null:
			rank_label.hide()
			suit_label.hide()
		else:
			rank_label.show()
			suit_label.show()
	else:
		front_face.hide()
		back_face.show()
		
	# Selection / Interaction visuals
	if is_selected:
		modulate = Color(1.3, 1.3, 1.3)
	else:
		modulate = Color(1, 1, 1)

func _apply_atlas_textures():
	if _master_texture == null:
		if not FileAccess.file_exists(SPRITE_SHEET_PATH):
			print("CardUI Error: Sprite sheet NOT found at ", SPRITE_SHEET_PATH)
			front_face.texture = null
			back_face.texture = null
			return
		
		_master_texture = load(SPRITE_SHEET_PATH)
		if _master_texture:
			print("CardUI: Master sprite sheet loaded successfully (", _master_texture.get_width(), "x", _master_texture.get_height(), ")")
		else:
			print("CardUI Error: Failed to load master sprite sheet as a texture!")
			return

	# Back Face Calculation (Row 4, Col 0 as per guide)
	if back_face.texture == null:
		var back_atlas = AtlasTexture.new()
		back_atlas.atlas = _master_texture
		back_atlas.region = Rect2(0, 4 * CARD_HEIGHT, CARD_WIDTH, CARD_HEIGHT)
		back_face.texture = back_atlas
	
	# Front Face Calculation
	var suit_idx = SUIT_ORDER.find(data.suit.capitalize())
	var rank_idx = RANK_ORDER.find(data.rank)
	
	if suit_idx != -1 and rank_idx != -1:
		var front_atlas = AtlasTexture.new()
		front_atlas.atlas = _master_texture
		front_atlas.region = Rect2(rank_idx * CARD_WIDTH, suit_idx * CARD_HEIGHT, CARD_WIDTH, CARD_HEIGHT)
		front_face.texture = front_atlas
	else:
		print("CardUI Error: Invalid rank/suit mapping: ", data.suit, "/", data.rank)
		front_face.texture = null

func set_interaction_enabled(enabled: bool):
	if has_node("Interaction"):
		$Interaction.mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
	mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE

func set_selected(p_selected: bool):
	is_selected = p_selected
	_update_visuals()

func set_highlighted(p_highlighted: bool):
	is_highlighted = p_highlighted
	
	if highlight_tween:
		highlight_tween.kill()
	
	if is_highlighted:
		highlight_tween = create_tween().set_loops()
		# Premium "Pulse" effect instead of shaking
		highlight_tween.tween_property(self , "scale", Vector2(1.08, 1.08), 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		highlight_tween.tween_property(self , "scale", Vector2(1.0, 1.0), 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		modulate = Color(1.5, 1.5, 1.5) # Brighten
	else:
		scale = Vector2(1.0, 1.0)
		modulate = Color(1.0, 1.0, 1.0)
	
	_update_visuals()

func flip() -> void:
	if is_flipping or not data:
		return
	is_flipping = true
	var tween = create_tween()
	tween.tween_property(self , "scale:x", 0.0, 0.15)
	tween.tween_callback(func():
		data.is_face_up = not data.is_face_up
		_update_visuals()
	)
	tween.tween_property(self , "scale:x", 1.0, 0.15)
	tween.tween_callback(func():
		is_flipping = false
		emit_signal("card_flipped", self , data)
	)

func _on_interaction_pressed():
	emit_signal("card_clicked", self , data)

func _on_gui_input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		emit_signal("card_clicked", self , data)

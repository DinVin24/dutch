extends Control
class_name CardUI

signal card_clicked(card_node, card_data)
signal card_flipped(card_node, card_data)

@onready var front_face: ColorRect = $FrontFace
@onready var back_face: ColorRect = $BackFace
@onready var rank_label: Label = $FrontFace/RankLabel
@onready var suit_label: Label = $FrontFace/SuitLabel

var data: CardData
var is_flipping: bool = false

func setup(p_data: CardData) -> void:
	if not p_data:
		push_warning("CardData not provided to CardUI")
		return
	data = p_data
	# Recalculate if needed (ensure King of Diamonds etc are right)
	data.recalc_point_value()
	
	# If we are already in the tree, update now
	if is_node_ready():
		_update_visuals()

func _ready():
	_update_visuals()

func _update_visuals() -> void:
	if not data:
		return
	
	if data.is_face_up:
		front_face.visible = true
		back_face.visible = false
		
		# Show rank and suit
		rank_label.text = str(data.rank)
		suit_label.text = str(data.suit)
		
		# Classmate's logic for color (fixing syntax error)
		var normalized_suit = data.suit.strip_edges().capitalize()
		var is_red = normalized_suit in ["Hearts", "Diamonds"]
		var text_color = Color(0.8, 0.1, 0.1) if is_red else Color(0, 0, 0)
		
		rank_label.add_theme_color_override("font_color", text_color)
		suit_label.add_theme_color_override("font_color", text_color)
		
		print("CardUI: Displaying %s of %s (Value: %d)" % [data.rank, data.suit, data.point_value])
	else:
		front_face.visible = false
		back_face.visible = true
		print("CardUI: Card is face down")

func flip() -> void:
	if is_flipping or not data:
		return
	is_flipping = true
	var tween = create_tween()
	tween.tween_property(self , "scale:x", 0.0, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func():
		data.is_face_up = not data.is_face_up
		_update_visuals()
	)
	tween.tween_property(self , "scale:x", 1.0, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func():
		is_flipping = false
		emit_signal("card_flipped", self , data)
	)

func _on_interaction_pressed() -> void:
	if not data:
		return
	emit_signal("card_clicked", self , data)

func _on_gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		emit_signal("card_clicked", self , data)

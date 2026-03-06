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
	data = p_data
	if is_node_ready():
		_update_visuals()

func _ready():
	_update_visuals()

func _update_visuals() -> void:
	if not data:
		return
	
	# Ensure nodes exist
	if not front_face or not back_face:
		return
		
	if data.is_face_up:
		front_face.show()
		back_face.hide()
		
		# Set text
		rank_label.text = str(data.rank)
		suit_label.text = str(data.suit)
		
		# Visual styling (Red for Hearts/Diamonds)
		var s = data.suit.capitalize()
		var is_red = (s == "Hearts" or s == "Diamonds")
		var color = Color(0.8, 0.1, 0.1) if is_red else Color(0, 0, 0)
		
		rank_label.add_theme_color_override("font_color", color)
		suit_label.add_theme_color_override("font_color", color)
	else:
		front_face.hide()
		back_face.show()

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

extends Control
class_name CardUI

signal card_clicked(card_node, card_data)
signal card_flipped(card_node, card_data)

@onready var front_face: TextureRect = $FrontFace
@onready var back_face: TextureRect = $BackFace
@onready var rank_label: Label = $FrontFace/Label
@onready var suit_icon: TextureRect = $FrontFace/Icon
@onready var interaction: TextureButton = $Interaction

var data: CardData
var is_flipping: bool = false

func setup(p_data: CardData) -> void:
	if not p_data:
		push_warning("CardData not provided to CardUI")
		return
	data = p_data
	data.recalc_point_value()
	_update_visuals()

func _update_visuals() -> void:
	if not data:
		return
	front_face.visible = data.is_face_up
	back_face.visible = not data.is_face_up
	var normalized_suit = data.suit.strip_edges().capitalize()
	var is_red = normalized_suit in ["Hearts", "Diamonds"]
	rank_label.text = "%s (%d)" % [data.rank, data.point_value]
	rank_label.theme_override_colors/font_color = is_red ? Color(0.8, 0.1, 0.1) : Color(0, 0, 0)
	suit_icon.modulate = is_red ? Color(0.8, 0.1, 0.1) : Color(0.15, 0.15, 0.15)

func flip() -> void:
	if is_flipping or not data:
		return
	is_flipping = true
	var tween = create_tween()
	tween.tween_property(self, "scale:x", 0.0, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func():
		data.is_face_up = not data.is_face_up
		_update_visuals()
	)
	tween.tween_property(self, "scale:x", 1.0, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func():
		is_flipping = false
		emit_signal("card_flipped", self, data)
	)

func _on_card_pressed() -> void:
	if not data:
		return
	emit_signal("card_clicked", self, data)

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
	# Recalculate if needed
	data.recalc_point_value()
	
	# If we are already in the tree (e.g. setup called after add_child), update now
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
		
		# Show rank and point value if available
		rank_label.text = str(data.rank)
		if data.point_value != int(data.rank) and data.rank != "A" and data.rank != "J" and data.rank != "Q" and data.rank != "K":
			# This is a bit complex, let's just show rank and suit
			pass
		
		# Classmate's logic for color
		var normalized_suit = data.suit.strip_edges().capitalize()
		var is_red = normalized_suit in ["Hearts", "Diamonds"]
		rank_label.theme_override_colors / font_color = Color(0.8, 0.1, 0.1) if is_red else Color(0, 0, 0)
		suit_label.text = str(data.suit)
		suit_label.theme_override_colors / font_color = Color(0.8, 0.1, 0.1) if is_red else Color(0, 0, 0)
		
		print("CardUI: Displaying ", rank_label.text, " of ", suit_label.text)
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
	# Keep this as fallback or if button doesn't cover everything
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		emit_signal("card_clicked", self , data)

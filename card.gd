extends Control
class_name CardUI

signal card_clicked(card_node)

@onready var front_face: TextureRect = $FrontFace
@onready var back_face: TextureRect = $BackFace

var data: CardData
var is_flipping: bool = false

func setup(p_data: CardData):
	data = p_data
	# In a real game, you'd load specific textures based on suit/rank
	# For now, we'll use placeholder colors or the default icon
	_update_visuals()

func _update_visuals():
	if data.is_face_up:
		front_face.show()
		back_face.hide()
	else:
		front_face.hide()
		back_face.show()

func flip():
	if is_flipping: return
	is_flipping = true
	
	var tween = create_tween()
	# Scale down to 0 to simulate edge-on
	tween.tween_property(self , "scale:x", 0.0, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func():
		data.is_face_up = !data.is_face_up
		_update_visuals()
	)
	# Scale back up
	tween.tween_property(self , "scale:x", 1.0, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func(): is_flipping = false)

func _on_gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		card_clicked.emit(self )

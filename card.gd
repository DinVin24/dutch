extends Control
class_name CardUI

signal card_clicked(card_node)

@onready var front_face: ColorRect = $FrontFace
@onready var back_face: ColorRect = $BackFace
@onready var rank_label: Label = $FrontFace/RankLabel
@onready var suit_label: Label = $FrontFace/SuitLabel

var data: CardData
var is_flipping: bool = false

func setup(p_data: CardData):
	data = p_data
	# If we are already in the tree (e.g. setup called after add_child), update now
	if is_node_ready():
		_update_visuals()

func _ready():
	_update_visuals()

func _update_visuals():
	if not data:
		return
	
	if data.is_face_up:
		front_face.visible = true
		back_face.visible = false
		rank_label.text = str(data.rank)
		suit_label.text = str(data.suit)
		print("CardUI: Displaying ", rank_label.text, " of ", suit_label.text)
	else:
		front_face.visible = false
		back_face.visible = true
		print("CardUI: Card is face down")

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

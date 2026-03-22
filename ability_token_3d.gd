extends Node3D
class_name AbilityToken3D

signal token_clicked(token: AbilityToken3D)

var ability_id: String
var target_player_idx: int = -1
var is_active: bool = true

var mesh: CSGBox3D
var area: Area3D

func setup(id: String):
	ability_id = id
	if not mesh:
		var box = CSGBox3D.new()
		box.size = Vector3(0.5, 0.1, 0.5) # small square token
		var m = StandardMaterial3D.new()
		m.albedo_color = Color(0.1, 0.3, 0.8)
		box.material = m
		add_child(box)
		mesh = box
		
		var a = Area3D.new()
		var col = CollisionShape3D.new()
		var shape = BoxShape3D.new()
		shape.size = box.size
		col.shape = shape
		a.add_child(col)
		add_child(a)
		area = a
		
	area.input_event.connect(_on_input_event)

func _on_input_event(_camera, event, _position, _normal, _shape_idx):
	if not is_active: return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		token_clicked.emit(self)

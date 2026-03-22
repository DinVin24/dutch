extends Node3D

@onready var deck_area = $DeckArea
@onready var discard_area = $DiscardArea
@onready var player_pos_nodes = {
	0: $PlayerPositions/Bottom,
	1: $PlayerPositions/Left,
	2: $PlayerPositions/Top,
	3: $PlayerPositions/Right
}
@onready var turn_label = $GameUI/MainHUD/TopLeft/TurnLabel
@onready var top_center = $GameUI/MainHUD/TopCenter
@onready var crt_overlay = $PostProcessing/CRT_Overlay
@onready var player_lights = {
	0: $PlayerPositions/Bottom/Spotlight_P0,
	1: $PlayerPositions/Left/Spotlight_P1,
	2: $PlayerPositions/Top/Spotlight_P2,
	3: $PlayerPositions/Right/Spotlight_P3
}

var bot_controller: BotController = null
var end_turn_btn: Button
var jump_in_btn: Button
var call_dutch_btn: Button
var confirm_dutch_btn: Button
var forfeit_dutch_btn: Button
var discard_indicator: MeshInstance3D

var player_hands: Array = [[], [], [], []]
var card_spacing = 1.3 # 3D meters
var pending_card: Card3D = null
var pending_card_tween: Tween = null
var swap_sources: Array = [] # Stores [card_node, player_idx, card_idx]

# Peek Phase state
var cards_peeked: int = 0
var max_peeks: int = 2
var peeked_card_nodes: Array = []

var _debug_reveal := false
var _debug_flipped_nodes: Array = []
var card_scene = preload("res://card_3d.tscn")
var pause_menu_scene = preload("res://pause_menu.tscn")
var pause_menu_instance: Node = null
var noclip_enabled: bool = false
var base_camera_transform: Transform3D
var camera_rot_x: float = 0.0
var camera_rot_y: float = 0.0

# Tavern Mechanics Visuals
var player_beers_nodes: Array = [[], [], [], []]
var money_labels: Array = []
var _chicken_node: CSGSphere3D = null
var _chicken_zoom_active: bool = false

@onready var camera = $Camera3D
var _current_ability_message: String = ""
var _shake_intensity: float = 0.0
var _shake_timer: float = 0.0
var _base_camera_pos: Vector3
var _base_camera_rotation: Vector3

# Targeting state
var _is_waiting_for_target: bool = false
var _pending_ability: Dictionary = {} # {id, token, activator}

func _ready():
	player_hands = [[], [], [], []]
	print("Game Board 3D: Ready. Connecting signals...")
	GameManager.stop_menu_music()
	GameManager.game_state_changed.connect(_on_game_state_changed)
	GameManager.turn_started.connect(_on_turn_started)
	GameManager.card_drawn_to_pending.connect(_on_card_drawn_to_pending)
	GameManager.card_discarded.connect(_on_card_discarded)
	GameManager.jump_in_penalty.connect(_on_jump_in_penalty)
	GameManager.jump_in_failed.connect(_on_jump_in_failed)
	GameManager.deck_ready.connect(_update_deck_visual)
	GameManager.bot_action.connect(_on_bot_action)
	GameManager.jack_swap_resolved.connect(_on_jack_swap_resolved)
	GameManager.all_cards_revealed.connect(_on_all_cards_revealed)
	GameManager.scores_ready.connect(_on_scores_ready)
	GameManager.deck_manager.deck_reshuffled.connect(_on_deck_reshuffled)
	GameManager.deck_manager.discard_pile_updated.connect(_update_discard_visual)
	GameManager.hand_updated.connect(_on_hand_updated)
	GameManager.dutch_called.connect(_on_dutch_called)
	
	# Tavern Hookups
	GameManager.player_drank_beer.connect(_on_player_drank_beer)
	GameManager.player_eliminated.connect(_on_player_eliminated)
	GameManager.player_gained_money.connect(_on_player_gained_money)
	GameManager.ability_played.connect(_on_ability_played)
	
	_create_hud_ui()
	_create_discard_indicator()
	_create_beer_placeholders()
	_create_chicken_placeholder()
	
	$DeckArea/Area3D.input_event.connect(_on_deck_input_event)
	$DiscardArea/Area3D.input_event.connect(_on_discard_input_event)
	
	bot_controller = BotController.new()
	bot_controller.gm = GameManager
	add_child(bot_controller)
	
	$Camera3D.current = true
	$GameUI/MainHUD.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	await get_tree().process_frame
	_update_deck_visual()
	_base_camera_pos = $Camera3D.position
	_base_camera_rotation = $Camera3D.rotation
	_setup_table_noise()
	_update_turn_lights(-1, false) # Ensure all off
	_create_player_targeting_areas()
	
	# HUD PASS-THROUGH: Ensure UI containers don't block clicks to the 3D cards
	for node_name in ["PostProcessing", "MainHUD", "TopCenter", "GameUI"]:
		var n = find_child(node_name, true, false)
		if n and n is Control:
			n.mouse_filter = Control.MOUSE_FILTER_IGNORE
			for child in n.get_children():
				if child is Control and not child is Button:
					child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	print("Game Board 3D: Starting game...")
	GameManager.initialize_game(4)
	trigger_glitch(0.4, 0.8) # Intro glitch

func _create_hud_ui():
	# Action Buttons Container
	var action_container = HBoxContainer.new()
	action_container.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	action_container.offset_left = -400
	action_container.offset_right = 400
	action_container.offset_top = -220
	action_container.offset_bottom = -170
	action_container.alignment = BoxContainer.ALIGNMENT_CENTER
	action_container.add_theme_constant_override("separation", 20)
	$GameUI/MainHUD.add_child(action_container)
	action_container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Standard HUD buttons
	end_turn_btn = _create_button(action_container, "END TURN", Color(0.2, 0.6, 0.2))
	jump_in_btn = _create_button(action_container, "JUMP IN", Color(0.2, 0.4, 0.8))
	call_dutch_btn = _create_button(action_container, "CALL DUTCH!", Color(0.8, 0.2, 0.2))
	confirm_dutch_btn = _create_button(action_container, "CONFIRM DUTCH", Color(0.2, 0.6, 0.2))
	forfeit_dutch_btn = _create_button(action_container, "FORFEIT DUTCH", Color(0.8, 0.2, 0.2))
	
	end_turn_btn.pressed.connect(_on_end_turn_pressed)
	jump_in_btn.pressed.connect(_on_jump_in_pressed)
	call_dutch_btn.pressed.connect(_on_call_dutch_pressed)
	confirm_dutch_btn.pressed.connect(_on_confirm_dutch_pressed)
	forfeit_dutch_btn.pressed.connect(_on_cancel_dutch_pressed)
	
	# Local Player Money Label (Only show P0)
	var l = Label.new()
	l.text = "$0"
	l.add_theme_font_size_override("font_size", 36)
	l.add_theme_color_override("font_color", Color.GOLD)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	$GameUI/MainHUD.add_child(l)
	l.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	l.offset_left = 40
	l.offset_top = -100
	l.offset_bottom = -60
	money_labels.append(l)

func _create_button(parent: Node, text: String, color: Color) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 20)
	
	var style = StyleBoxFlat.new()
	style.bg_color = color.darkened(0.7)
	style.bg_color.a = 0.6 # Glassmorphism
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = color.lightened(0.3)
	style.set_corner_radius_all(4)
	style.shadow_color = color
	style.shadow_size = 8
	
	var hover_style = style.duplicate()
	hover_style.bg_color = color.darkened(0.5)
	hover_style.bg_color.a = 0.8
	hover_style.border_color = Color.WHITE
	
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", hover_style)
	btn.add_theme_stylebox_override("pressed", hover_style)
	
	parent.add_child(btn)
	# Removed manual anchors so HBoxContainer takes full control of layout
	btn.custom_minimum_size = Vector2(140, 40)
	btn.hide()
	return btn

func _update_deck_visual():
	for child in deck_area.get_children():
		if child is Card3D:
			child.queue_free()
			
	var stack_size = min(5, GameManager.deck_manager.deck.size())
	for i in range(stack_size):
		var card = card_scene.instantiate()
		deck_area.add_child(card)
		card.setup(CardData.new("Ace", "Clubs"))
		card.rotation_degrees = Vector3(90, 0, 0)
		card.position = Vector3(0, i * 0.02, 0)
		card.set_interactive(false)

func _update_discard_visual():
	for child in discard_area.get_children():
		if child is Card3D:
			child.queue_free()
	
	var pile = GameManager.deck_manager.discard_pile
	if not pile.is_empty():
		var top_info = pile.back()
		var card_node = card_scene.instantiate()
		discard_area.add_child(card_node)
		card_node.setup(CardData.new(top_info.rank, top_info.suit))
		card_node.data.is_face_up = true
		card_node.rotation_degrees = Vector3(270, 0, 0)
		card_node.position = Vector3.ZERO
		card_node.set_interactive(false)
		if discard_indicator: discard_indicator.hide()
	else:
		if discard_indicator: discard_indicator.show()

func _create_discard_indicator():
	discard_indicator = MeshInstance3D.new()
	var mesh = PlaneMesh.new()
	mesh.size = Vector2(0.8, 1.1) # Slightly larger than a card
	discard_indicator.mesh = mesh
	
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1, 1, 1, 0.15) # Ghostly white/gray
	mat.emission_enabled = true
	mat.emission = Color(1, 1, 1) # Neutral white glow
	mat.emission_energy_multiplier = 0.3
	discard_indicator.material_override = mat
	
	discard_area.add_child(discard_indicator)
	discard_indicator.position = Vector3(0, 0.01, 0)

func _create_beer_placeholders():
	for i in range(4):
		var pos_node = player_pos_nodes[i]
		for b in range(5):
			var beer = CSGCylinder3D.new()
			beer.radius = 0.08
			beer.height = 0.25
			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color(0.8, 0.5, 0.1) # Beer color
			mat.roughness = 0.2
			beer.material = mat
			
			var foam = CSGCylinder3D.new()
			foam.radius = 0.082
			foam.height = 0.05
			foam.position = Vector3(0, 0.125, 0)
			var foam_mat = StandardMaterial3D.new()
			foam_mat.albedo_color = Color(1.0, 1.0, 1.0)
			foam.material = foam_mat
			beer.add_child(foam)
			
			# GRID LAYOUT: 2 rows (3 front, 2 back)
			var row = b / 3
			var col = b % 3
			var grid_x = (col - 1.0) * 0.25
			var grid_z = row * 0.25
			
			# Stationed on the RIGHT of the cards
			beer.position = Vector3(grid_x + 1.8, 0.11, -1.8 + grid_z) 
			pos_node.add_child(beer)
			player_beers_nodes[i].append(beer)

func _create_chicken_placeholder():
	var chicken = CSGSphere3D.new()
	chicken.radius = 0.4
	# Move lower and slightly closer to center of the table so camera sees it
	chicken.position = Vector3(0, 1.5, -3.5)
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.9, 0.8) # Pale chicken
	mat.emission_enabled = true
	mat.emission = Color(0.9, 0.9, 0.5)
	mat.emission_energy_multiplier = 0.5
	chicken.material = mat
	add_child(chicken)
	_chicken_node = chicken
	
	# Add beak
	var beak = CSGBox3D.new()
	beak.size = Vector3(0.2, 0.1, 0.3)
	beak.position = Vector3(0, 0, 0.45)
	var beak_mat = StandardMaterial3D.new()
	beak_mat.albedo_color = Color(1.0, 0.5, 0.0)
	beak.material = beak_mat
	chicken.add_child(beak)
	
	# Add red comb
	var comb = CSGBox3D.new()
	comb.size = Vector3(0.1, 0.2, 0.3)
	comb.position = Vector3(0, 0.4, 0.1)
	var comb_mat = StandardMaterial3D.new()
	comb_mat.albedo_color = Color(1.0, 0.1, 0.1)
	comb.material = comb_mat
	chicken.add_child(comb)
	
	var area = Area3D.new()
	var col = CollisionShape3D.new()
	var shape = SphereShape3D.new()
	shape.radius = 0.6
	col.shape = shape
	area.add_child(col)
	chicken.add_child(area)
	
	area.input_event.connect(_on_chicken_clicked)

func _on_chicken_clicked(_camera, event, _position, _normal, _shape_idx):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if GameManager.current_player_index == 0:
			_try_buy_ability(0)

func _try_buy_ability(p_idx: int):
	var cost = 50
	if GameManager.players_info[p_idx].money >= cost:
		GameManager.players_info[p_idx].money -= cost
		GameManager.player_gained_money.emit(p_idx, -cost, GameManager.players_info[p_idx].money)
		_drop_egg_for(p_idx)
	else:
		_show_message("Chicken wants $50 for an egg!")

func _drop_egg_for(p_idx: int):
	var abilities = ["bottoms_up", "refuel", "trim_off", "boulder", "reverse", "skip", "perfect_match", "inflation", "half_off", "jumpscare", "shuffle"]
	var ab = abilities[randi() % abilities.size()]
	_show_message("You got: " + ab.capitalize() + "!")
	
	if is_instance_valid(_chicken_node):
		var tween = create_tween()
		tween.tween_property(_chicken_node, "position:y", 2.0, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(_chicken_node, "position:y", 1.5, 0.2).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)

		# Camera cinematic zoom - GUARD against re-entry
		if not _chicken_zoom_active:
			_chicken_zoom_active = true
			var target_pos = _chicken_node.global_position + Vector3(0, 0.2, 1.0)
			var cam_tween = create_tween()
			var old_base = _base_camera_pos
			var original_fov = camera.fov
			var original_rot = camera.rotation_degrees
			
			cam_tween.tween_property(camera, "global_position", target_pos, 0.3).set_trans(Tween.TRANS_CUBIC)
			cam_tween.tween_property(camera, "rotation_degrees", Vector3(-10, 0, 0), 0.3).set_trans(Tween.TRANS_CUBIC)
			cam_tween.parallel().tween_property(camera, "fov", 45.0, 0.3).set_trans(Tween.TRANS_CUBIC)
			cam_tween.tween_interval(0.8)
			cam_tween.tween_property(camera, "global_position", old_base, 0.4).set_trans(Tween.TRANS_QUAD)
			cam_tween.parallel().tween_property(camera, "rotation_degrees", original_rot, 0.4).set_trans(Tween.TRANS_QUAD)
			cam_tween.parallel().tween_property(camera, "fov", original_fov, 0.4).set_trans(Tween.TRANS_QUAD)
			cam_tween.tween_callback(func():
				_base_camera_pos = old_base
				_chicken_zoom_active = false
			)
	GameManager.players_info[p_idx].abilities.append(ab)
	print("Player ", p_idx, " bought ability: ", ab)
	
	# Spawn ability token visually
	var token = load("res://ability_token_3d.gd").new()
	player_pos_nodes[p_idx].add_child(token)
	token.setup(ab)
	token.token_clicked.connect(_on_ability_token_clicked)
	
	# Spawn hovering above the table, then beautifully tween into the grid
	token.position = Vector3(2.8, 0.5, -1.2) 
	_update_ability_visuals(p_idx)
	
func _update_ability_visuals(p_idx: int):
	var tokens = []
	for c in player_pos_nodes[p_idx].get_children():
		if "ability_id" in c and not c.is_queued_for_deletion():
			tokens.append(c)
			
	for i in range(tokens.size()):
		var t = tokens[i]
		var cols = i % 4
		var rows = i / 4
		
		# Clean, perfect 4x4 matrix centered right next to the hand
		var target_pos = Vector3(2.8 + (cols * 0.7), 0.1, (rows * 0.8) - 0.6)
		
		# Snappy, satisfying placement animation
		var tween = create_tween()
		tween.tween_property(t, "position", target_pos, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
>>>>>>> c472367 (feat(ui): implement Buckshot table aesthetics, 4x4 matrix, and barrel-roll animations)
	
func _on_ability_token_clicked(token):
	var p_idx = -1
	for i in range(4):
		if token.get_parent() == player_pos_nodes[i]:
			p_idx = i; break
	
	if p_idx == GameManager.current_player_index:
		var targeting_abilities = ["bottoms_up", "boulder", "skip", "inflation", "half_off", "shuffle"]
		
		if token.ability_id in targeting_abilities:
			_is_waiting_for_target = true
			_set_targeting_areas_enabled(true)
			_highlight_selectable_cards(true)
			_update_turn_lights(-1, true) # Reveal all zones for targeting
			_pending_ability = {
				"id": token.ability_id,
				"token": token,
				"activator": p_idx
			}
			_show_message("SELECT TARGET PLAYER (click their cards or zone)")
			# Optional: highlight target zones
		else:
			# Non-targeting or self-targeting
			var target = p_idx # Default to self for things like refuel/trim_off
			if GameManager.play_ability(p_idx, token.ability_id, target):
				token.queue_free()
				var ab_idx = GameManager.players_info[p_idx].abilities.find(token.ability_id)
				if ab_idx != -1:
					GameManager.players_info[p_idx].abilities.remove_at(ab_idx)
				_update_ability_visuals(p_idx)
	else:
		_show_message("Not your turn to play abilities!")

func _create_player_targeting_areas():
	for i in range(4):
		var area = Area3D.new()
		area.name = "TargetArea"
		var col = CollisionShape3D.new()
		var shape = BoxShape3D.new()
		shape.size = Vector3(4.0, 1.0, 4.0) # Larger area
		col.shape = shape
		area.add_child(col)
		player_pos_nodes[i].add_child(area)
		# Position it slightly above table
		area.position = Vector3(0, 0.5, 0)
		
		# DEBUG FIX: non-pickable by default so we don't block cards
		area.input_ray_pickable = false
		area.collision_layer = 1
		area.collision_mask = 1
		
		area.input_event.connect(_on_player_area_input.bind(i))
		print("DEBUG: Created TargetArea for player ", i)

func _set_targeting_areas_enabled(enabled: bool):
	print("DEBUG: Setting targeting areas to: ", enabled)
	for i in range(4):
		var area = player_pos_nodes[i].find_child("TargetArea")
		if area:
			area.input_ray_pickable = enabled
			print("  - Player ", i, " area pickable: ", area.input_ray_pickable)

func _on_player_area_input(_camera, event, _position, _normal, _shape_idx, player_idx: int):
	if not _is_waiting_for_target: return
	
	# Handle both Area3D events AND direct card clicks (where event is null)
	if event == null or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		print("DEBUG: Clicked TargetArea for player ", player_idx)
		var ab_id = _pending_ability.id
		var activator = _pending_ability.activator
		var token = _pending_ability.token
		
		print("DEBUG: Executing ability '", ab_id, "' from ", activator, " on ", player_idx)
		
		if GameManager.play_ability(activator, ab_id, player_idx):
			_is_waiting_for_target = false
			_set_targeting_areas_enabled(false)
			_clear_all_highlights()
			_update_turn_lights(activator) # Reset lights to activator's turn
			_hide_message()
			if is_instance_valid(token):
				token.queue_free()
			var ab_idx = GameManager.players_info[activator].abilities.find(ab_id)
			if ab_idx != -1:
				GameManager.players_info[activator].abilities.remove_at(ab_idx)
			_pending_ability.clear()
			_update_ability_visuals(activator)

func _on_player_drank_beer(player_idx, remaining):
	if player_idx < 0 or player_idx >= 4: return
	var beers_array = player_beers_nodes[player_idx]
	for i in range(beers_array.size()):
		beers_array[i].visible = (i < remaining)
	shake(0.2, 0.3)

func _on_player_eliminated(player_idx):
	_show_message(GameManager.players_info[player_idx].name + " PASSED OUT!")
	# Turn their zone red
	player_lights[player_idx].light_color = Color(1, 0, 0)
	player_lights[player_idx].light_energy = 10.0

func _on_player_gained_money(player_idx, _amount, total):
	if player_idx == 0 and money_labels.size() > 0:
		money_labels[0].text = "$" + str(total)

func _on_ability_played(player_idx, ability_id):
	var p_name = GameManager.players_info[player_idx].name
	_show_message(p_name + " used " + ability_id.capitalize() + "!")

func _on_turn_started(player_idx):
	var p_info = GameManager.players_info[player_idx]
	turn_label.text = p_info.name + "'s Turn"
	_animate_glitch_text(turn_label)
	_update_turn_lights(player_idx)
	if player_idx != 0:
		_show_message(p_info.name + " is thinking...")

func _update_turn_lights(current_player: int, all_on: bool = false):
	# Safety: during initial ready call, players_info might not be initialized yet
	if GameManager.players_info.size() < 4:
		# Just set baseline energy for all lights if we can't check hand sizes yet
		for i in range(4):
			player_lights[i].light_energy = (6.0 if all_on else 0.0)
		return

	for i in range(4):
		var light = player_lights[i]
		var is_active = (i == current_player or all_on)
		var hand_size = GameManager.players_info[i].hand.size()
		
		var target_energy = 8.0 if is_active else 0.0
		var target_angle = 85.0
		
		var tween = create_tween().set_parallel(true)
		tween.tween_property(light, "light_energy", target_energy, 0.5).set_trans(Tween.TRANS_CUBIC)
		tween.tween_property(light, "spot_angle", target_angle, 0.5).set_trans(Tween.TRANS_CUBIC)
		tween.tween_property(light, "spot_range", 18.0, 0.5)
		tween.tween_property(light, "position:y", 6.5, 0.5)
		tween.tween_property(light, "scale", Vector3(1.0, 1.0, 1.0), 0.5)

func _setup_table_noise():
	var table_mesh = $Table as MeshInstance3D
	if not table_mesh: return
	var mat = table_mesh.get_surface_override_material(0) as StandardMaterial3D
	if not mat: return
	
	var noise = FastNoiseLite.new()
	noise.seed = randi()
	noise.frequency = 0.05
	
	var noise_tex = NoiseTexture2D.new()
	noise_tex.noise = noise
	noise_tex.as_normal_map = true
	noise_tex.bump_strength = 2.0
	
	mat.normal_enabled = true
	mat.normal_texture = noise_tex

func _animate_glitch_text(label: Label):
	var original_text = label.text
	var tween = create_tween()
	for i in range(5):
		tween.tween_callback(func(): label.text = _get_glitch_string(original_text))
		tween.tween_interval(0.05)
	tween.tween_callback(func(): label.text = original_text)

func _get_glitch_string(base: String) -> String:
	var glitch_chars = "!@#$%^&*()_+-=[]{}|;:,.<>?"
	var result = ""
	for i in range(base.length()):
		if randf() < 0.3:
			result += glitch_chars[randi() % glitch_chars.length()]
		else:
			result += base[i]
	return result

func _on_card_drawn_to_pending(player_idx, card_data):
	if pending_card: pending_card.queue_free()
	
	_update_deck_visual()
	
	if player_idx != 0:
		_show_message(GameManager.players_info[player_idx].name + " is drawing...")
		return
		
	pending_card = card_scene.instantiate()
	pending_card.name = "PendingCard"
	add_child(pending_card)
	
	card_data.is_face_up = false
	pending_card.setup(card_data)
	pending_card.card_clicked.connect(_on_card_clicked)
	# Move slightly higher and CLOSER TO CAMERA (Z offset) to ensure it's not blocked by DeckArea
	pending_card.position = deck_area.position + Vector3(0, 0.6, 0.5)
	pending_card.set_interactive(true)
	
	# Reveal animations
	await get_tree().create_timer(0.1, false).timeout
	pending_card.animate_flip(true)
	_update_deck_visual() # Refresh deck after drawing

func _on_card_discarded(player_idx, card_data):
	if jump_in_btn and not GameManager.deck_manager.discard_pile.is_empty():
		jump_in_btn.show()

	var card_to_discard: Node3D = null
	
	if pending_card and pending_card.data == card_data:
		card_to_discard = pending_card
		pending_card = null
	elif player_idx != -1:
		var hand_nodes = player_hands[player_idx]
		for i in range(hand_nodes.size()):
			var hand_card = hand_nodes[i]
			if hand_card.data == card_data or (hand_card.data.rank == card_data.rank and hand_card.data.suit == card_data.suit):
				card_to_discard = hand_card
				
				if pending_card:
					# --- SWAP PHASE ---
					var old_card_node = hand_nodes[i]
					var new_card_node = pending_card
					pending_card = null
					
					# Update persistent array: replace old node with new node at same index
					hand_nodes[i] = new_card_node
					
					var hand_global_pos = old_card_node.global_position
					var discard_global_pos = discard_area.global_position + Vector3(0, 0.05, 0)
					
					# 1. Animate Drawn Card to Hand
					new_card_node.reparent(player_pos_nodes[player_idx])
					var tween_new = create_tween().set_parallel(true)
					tween_new.tween_property(new_card_node, "global_position", hand_global_pos, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
					tween_new.tween_property(new_card_node, "rotation_degrees:x", 90.0, 0.3)
					
					# 2. Animate replaced card to Discard
					var start_global_pos = old_card_node.global_position
					old_card_node.reparent(get_tree().root) # Isolate from hand reorganization
					old_card_node.global_position = start_global_pos
					card_to_discard = old_card_node # Point directly to the node being moved
					
					var tween_old = create_tween().set_parallel(true)
					tween_old.tween_property(old_card_node, "global_position", discard_global_pos, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
					tween_old.tween_property(old_card_node, "rotation_degrees:x", 270.0, 0.3)
					
					# 3. Finalize
					tween_new.chain().tween_callback(func():
						hand_nodes[i] = new_card_node
						new_card_node.data.is_face_up = false
						new_card_node._update_visuals()
						_update_hand_visuals(player_idx)
					)
					tween_old.chain().tween_callback(func():
						_update_discard_visual()
						old_card_node.queue_free()
						shake(0.05, 0.2)
					)
					card_to_discard = null # Already handled above
				else:
					# --- JUMP-IN / PURE REMOVAL PHASE ---
					var gm_hand = GameManager.players_info[player_idx].hand
					if gm_hand.size() == hand_nodes.size():
						# Bot swap / special case: data refresh
						hand_nodes[i].setup(gm_hand[i])
						# We instantiate a temp for the discard animation
						var temp_discard = card_scene.instantiate()
						add_child(temp_discard)
						temp_discard.setup(card_data)
						temp_discard.global_position = hand_nodes[i].global_position
						card_to_discard = temp_discard
					else:
						# Pure removal (Jump-In or discard choice)
						var node_to_move = hand_nodes[i]
						hand_nodes.remove_at(i)
						
						# Isolate node for animation
						var start_pos = node_to_move.global_position
						node_to_move.reparent(get_tree().root)
						node_to_move.global_position = start_pos
						card_to_discard = node_to_move
					
					_update_hand_visuals(player_idx)
				break
	
	if card_to_discard == null and player_idx >= 0:
		# Fallback: if we can't find the node, create a temporary one for the animation
		if pending_card:
			card_to_discard = pending_card
			pending_card = null
		else:
			card_to_discard = card_scene.instantiate()
			add_child(card_to_discard)
			card_to_discard.setup(card_data)
			# Default to player's position instead of the deck if we can't find the exact card
			card_to_discard.global_position = player_pos_nodes[player_idx].global_position

	if card_to_discard:
		card_to_discard.set_highlight(false)
		
		# For discards from hand/deck, we want a smooth global motion
		var target_global_pos = discard_area.global_position + Vector3(0, 0.05, 0)
		
		var tween = create_tween().set_parallel(true)
		tween.tween_property(card_to_discard, "global_position", target_global_pos, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(card_to_discard, "rotation_degrees", Vector3(270, 0, 0), 0.4) # Face UP on table
		
		tween.chain().tween_callback(func():
			_update_discard_visual()
			_update_deck_visual()
			shake(0.05, 0.2)
			if is_instance_valid(card_to_discard) and card_to_discard.get_parent() != discard_area:
				card_to_discard.queue_free()
		)
	
	if player_idx != -1:
		_update_hand_visuals(player_idx)

func _show_message(text: String):
	_current_ability_message = text
	for child in top_center.get_children():
		child.queue_free()
	
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 32)
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 6)
	top_center.add_child(label)
	# Bug 5: responsive pos
	top_center.set_anchors_preset(Control.PRESET_CENTER_TOP)
	label.show()

func _on_end_turn_pressed(): GameManager.end_turn()
func _on_jump_in_pressed(): GameManager.start_jump_in(0)
func _on_call_dutch_pressed(): GameManager.call_dutch(0)
func _on_confirm_dutch_pressed(): GameManager.confirm_dutch()
func _on_cancel_dutch_pressed(): GameManager.cancel_dutch()

func _on_game_state_changed(new_state):
	_hide_message()
	
	# State handling for HUD buttons
	end_turn_btn.hide()
	jump_in_btn.hide()
	call_dutch_btn.hide()
	confirm_dutch_btn.hide()
	forfeit_dutch_btn.hide()
	
	# Always show Jump-In if valid (matched 2D behavior)
	if GameManager.current_state != GameManager.GameState.INITIAL_PEEK and \
	   GameManager.current_state != GameManager.GameState.DEAL_CARDS and \
	   GameManager.current_state != GameManager.GameState.GAME_OVER:
		if not GameManager.deck_manager.discard_pile.is_empty():
			if not GameManager.players_info[0].is_eliminated:
				jump_in_btn.show()
	
	# Update deck/discard highlighting based on state
	# (In 3D we can raise them or change material emission)
	
	var block_cards := false
	match new_state:
		GameManager.GameState.TURN_START_DRAW, \
		GameManager.GameState.TURN_RESOLVE_DRAWN, \
		GameManager.GameState.TURN_END_CHOICE, \
		GameManager.GameState.TURN_CONFIRM_DUTCH:
			block_cards = (GameManager.current_player_index != 0)
		GameManager.GameState.TURN_PEEK_ABILITY, \
		GameManager.GameState.TURN_SWAP_ABILITY, \
		GameManager.GameState.TURN_JUMP_IN_SELECTION, \
		GameManager.GameState.INITIAL_PEEK:
			block_cards = false
		_:
			block_cards = true
	_set_all_cards_interactive(not block_cards)
	
	if new_state == GameManager.GameState.TURN_START_DRAW or \
	   new_state == GameManager.GameState.TURN_END_CHOICE:
		_clear_all_highlights()
	
	match new_state:
		GameManager.GameState.DEAL_CARDS:
			turn_label.text = "Dealing cards..."
			_handle_initial_deal()
		GameManager.GameState.INITIAL_PEEK:
			turn_label.text = "Peeking phase"
			_start_peek_phase()
			_update_turn_lights(-1, true)
		GameManager.GameState.TURN_RESOLVE_DRAWN:
			print("GameBoard3D: UI - Showing TURN_RESOLVE_DRAWN")
			if GameManager.current_player_index == 0:
				_show_message("Click a card in your hand to swap, or the drawn card to discard.")
				_highlight_selectable_cards(false) # Highlight & enable player 0 hand
			else:
				var player_name = GameManager.players_info[GameManager.current_player_index].name
				_show_message(player_name + " is deciding...")
		GameManager.GameState.TURN_END_CHOICE:
			print("GameBoard3D: UI - Showing TURN_END_CHOICE")
			if GameManager.current_player_index == 0:
				end_turn_btn.show()
				if GameManager.dutch_caller_index == -1 and GameManager.players_info[0].can_call_dutch:
					call_dutch_btn.show()
		GameManager.GameState.TURN_JUMP_IN_SELECTION:
			print("GameBoard3D: UI - Showing TURN_JUMP_IN_SELECTION")
			var ji_idx = GameManager.jump_in_player_idx
			var ji_name = GameManager.players_info[ji_idx].name if ji_idx >= 0 else "Someone"
			_show_message(ji_name + ": pick a matching card, or end turn to cancel.")
			if ji_idx == 0:
				end_turn_btn.show()
				_highlight_selectable_cards(false) # Highlight ONLY player hand, not opponents
		GameManager.GameState.TURN_CONFIRM_DUTCH:
			print("GameBoard3D: UI - Showing TURN_CONFIRM_DUTCH")
			if GameManager.current_player_index == 0:
				_show_message("You called Dutch! Confirm or Forfeit?")
				confirm_dutch_btn.show()
				forfeit_dutch_btn.show()
		GameManager.GameState.TURN_PEEK_ABILITY:
			if GameManager.current_player_index == 0:
				_show_message("Select ANY card to peek at.")
				_highlight_selectable_cards(true)
			_update_turn_lights(-1, true) # All lights on for Queen
		GameManager.GameState.TURN_SWAP_ABILITY:
			if GameManager.current_player_index == 0:
				_show_message("Select TWO cards to swap.")
				# User specifically disabled highlighting for this phase, so just enable clicks
				_set_player_hand_interactive(0, true)
				# Also allow swapping with opponents
				for p in range(1, GameManager.num_players):
					_set_player_hand_interactive(p, true)
			_update_turn_lights(-1, true)
			swap_sources.clear()
	
	# Selection Safety: prevent Deck/Discard from blocking clicks during Jump-In
	$DeckArea/Area3D.input_ray_pickable = (new_state != GameManager.GameState.TURN_JUMP_IN_SELECTION)
	$DiscardArea/Area3D.input_ray_pickable = (new_state != GameManager.GameState.TURN_JUMP_IN_SELECTION)

	if new_state != GameManager.GameState.GAME_OVER:
		if GameManager.deck_manager.discard_pile.size() > 0:
			if not GameManager.players_info[0].is_eliminated:
				jump_in_btn.show()

func _set_all_cards_interactive(enabled: bool):
	for i in range(4):
		_set_player_hand_interactive(i, enabled)

func _set_player_hand_interactive(player_idx: int, enabled: bool):
	if player_idx < 0 or player_idx >= player_hands.size(): return
	for card in player_hands[player_idx]:
		if is_instance_valid(card):
			card.set_interactive(enabled)

func _highlight_selectable_cards(include_opponents: bool = false):
	_clear_all_highlights()
	
	# Always allow selecting pending card if it exists and it's player 0's interaction phase
	if is_instance_valid(pending_card):
		pending_card.set_highlight(true)
		pending_card.set_interactive(true)

	for i in range(4):
		if i == 0 or include_opponents:
			for card in player_pos_nodes[i].get_children():
				if card is Card3D:
					card.set_highlight(true)
					card.set_interactive(true)

func _clear_all_highlights():
	if is_instance_valid(pending_card):
		pending_card.set_highlight(false)
		pending_card.set_interactive(false)

	for i in range(4):
		# Clear from logical array
		for card in player_hands[i]:
			if is_instance_valid(card):
				card.set_highlight(false)
				card.set_interactive(false)
		
		# Heavy-duty clear from physical nodes in case they are out of sync
		for child in player_pos_nodes[i].get_children():
			if child is Card3D:
				child.set_highlight(false)
				child.set_interactive(false)

func _hide_message():
	_current_ability_message = ""
	for child in top_center.get_children():
		child.queue_free()

func _on_hand_updated(player_idx):
	_update_hand_visuals(player_idx)

func _on_card_hover_enter(card_node: Node3D):
	if not is_instance_valid(card_node): return
	if card_node.is_highlighted: return # Don't override highlight state
	var tween = create_tween().set_parallel(true)
	tween.tween_property(card_node, "scale", Vector3(1.15, 1.15, 1.15), 0.15).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(card_node, "position:y", card_node.position.y + 0.25, 0.15).set_trans(Tween.TRANS_QUAD)
	card_node.set_meta("hover_lift_y", card_node.position.y + 0.25)

func _on_card_hover_exit(card_node: Node3D):
	if not is_instance_valid(card_node): return
	if card_node.is_highlighted: return
	var tween = create_tween().set_parallel(true)
	tween.tween_property(card_node, "scale", Vector3(1.0, 1.0, 1.0), 0.15).set_trans(Tween.TRANS_QUAD)
	# Return to the base y position that _update_hand_visuals gave it
	var base_y = card_node.get_meta("hover_lift_y", card_node.position.y) - 0.25
	tween.tween_property(card_node, "position:y", base_y, 0.15).set_trans(Tween.TRANS_QUAD)

func _update_hand_visuals(player_idx: int):
	if player_idx < 0 or player_idx >= 4: return
	var hand_data = GameManager.players_info[player_idx].hand
	var nodes = player_hands[player_idx]
	
	# Sync node count with data count
	while nodes.size() < hand_data.size():
		var card_node = card_scene.instantiate()
		player_pos_nodes[player_idx].add_child(card_node)
		card_node.card_clicked.connect(_on_card_clicked)
		nodes.append(card_node)
	
	while nodes.size() > hand_data.size():
		var card = nodes.pop_back()
		if is_instance_valid(card):
			card.queue_free()
	
	# HYBRID LAYOUT: flat up to 6 cards, overlapping spread beyond 6
	var total_cards = nodes.size()
	const MAX_FLAT = 6
	const FLAT_SPACING = 1.3
	const MIN_SPACING = 0.55 # Compressed overlap spacing
	
	var spacing = FLAT_SPACING if total_cards <= MAX_FLAT else MIN_SPACING
	var total_width = (total_cards - 1) * spacing
	
	for i in range(total_cards):
		var card_node = nodes[i]
		if is_instance_valid(card_node):
			if not card_node.card_clicked.is_connected(_on_card_clicked):
				card_node.card_clicked.connect(_on_card_clicked)
			# Connect hover signals for the lift effect if not already done
			if not card_node.get_meta("hover_connected", false):
				var area = card_node.get_node_or_null("Area3D")
				if area:
					area.mouse_entered.connect(_on_card_hover_enter.bind(card_node))
					area.mouse_exited.connect(_on_card_hover_exit.bind(card_node))
					card_node.set_meta("hover_connected", true)
			
			card_node.setup(hand_data[i])
			card_node.name = "Card_%d_%d" % [player_idx, i]
			
<<<<<<< HEAD
			var target_pos = Vector3(i * spacing - total_width / 2.0, 0.05 + i * 0.002, 0)
			var target_rot_x = (270 if hand_data[i].is_face_up else 90)
=======
			var target_pos = Vector3((i - (nodes.size() - 1) / 2.0) * card_spacing, 0.05, 0)
>>>>>>> c472367 (feat(ui): implement Buckshot table aesthetics, 4x4 matrix, and barrel-roll animations)
			
			if card_node.position.distance_to(target_pos) < 0.01: continue
			
			var tween = create_tween().set_parallel(true)
<<<<<<< HEAD
			tween.tween_property(card_node, "position", target_pos, 0.3).set_trans(Tween.TRANS_QUAD)
			tween.tween_property(card_node, "rotation_degrees:x", target_rot_x, 0.3)
			tween.tween_property(card_node, "rotation_degrees:y", 0.0, 0.3) # Reset fan rotation
=======
			tween.tween_property(card_node, "position:x", target_pos.x, 0.3).set_trans(Tween.TRANS_QUAD)
			tween.tween_property(card_node, "position:z", target_pos.z, 0.3).set_trans(Tween.TRANS_QUAD)
			var target_rot_y = 180.0 if (player_idx == 0 or player_idx == 2) else 0.0
			var flat_basis = Basis.from_euler(Vector3(deg_to_rad(90), deg_to_rad(target_rot_y), 0))
			
			if hand_data[i].is_face_up:
				flat_basis = flat_basis * Basis(Vector3.UP, PI) # Barrel roll 180 degrees instead of pitching
				
			tween.tween_property(card_node, "quaternion", flat_basis.get_rotation_quaternion(), 0.3)
>>>>>>> c472367 (feat(ui): implement Buckshot table aesthetics, 4x4 matrix, and barrel-roll animations)
			
			var lift_tween = create_tween()
			lift_tween.tween_property(card_node, "scale", Vector3(1.05, 1.05, 1.05), 0.1)
			lift_tween.tween_property(card_node, "scale", Vector3(1.0, 1.0, 1.0), 0.2)

func _handle_initial_deal():
	print("GameBoard3D: _handle_initial_deal started")
	_show_message("Dealing cards...")
	for i in range(4): # 4 cards each
		for p_idx in range(GameManager.num_players):
			var card_data_dict = GameManager.deck_manager.draw_card()
			if card_data_dict.is_empty():
				break
			
			var card_data = CardData.new(card_data_dict.rank, card_data_dict.suit)
			card_data.is_face_up = false
			GameManager.players_info[p_idx].hand.append(card_data)
			
			# Create the node and animate it from deck to hand
			var card_node = card_scene.instantiate()
			add_child(card_node)
			card_node.setup(card_data)
			card_node.card_clicked.connect(_on_card_clicked)
			player_hands[p_idx].append(card_node)
			
			# Spawn at deck
			card_node.global_position = deck_area.global_position
			card_node.rotation_degrees = Vector3(90, 0, 0) # Face down
			
			# Reparent to player pos node
			card_node.reparent(player_pos_nodes[p_idx])
			
			_update_hand_visuals(p_idx)
			await get_tree().create_timer(0.08, false).timeout
	
	GameManager.change_state(GameManager.GameState.INITIAL_PEEK)

func _start_peek_phase():
	print("GameBoard3D: _start_peek_phase started")
	_show_message("Select TWO cards to peek at.")
	# In 3D, we can highlight them by raising them slightly
	for c3d in player_pos_nodes[0].get_children():
		if c3d is Card3D:
			c3d.set_highlight(true)

var peeked_cards: Array = []
func _on_card_clicked(node, data):
	print("[INPUT] Card clicked: ", node.name, " (", data.rank, " of ", data.suit, ") in state: ", GameManager.GameState.keys()[GameManager.current_state])
	var p_idx = -1
	for i in range(4):
		if player_hands[i].has(node):
			p_idx = i; break
	
	if _is_waiting_for_target:
		if p_idx != -1:
			_on_player_area_input(null, null, Vector3.ZERO, Vector3.ZERO, 0, p_idx)
			return
			
	match GameManager.current_state:
		GameManager.GameState.INITIAL_PEEK:
			if node.get_parent() == player_pos_nodes[0] and not data.is_face_up:
				if peeked_cards.size() >= 2: return # Strict limit
				if node in peeked_cards: return
				node.animate_flip(true)
				peeked_cards.append(node)
				if peeked_cards.size() >= 2:
					await get_tree().create_timer(1.5, false).timeout
					_clear_all_highlights() # Clear highlights BEFORE flipping back
					for c in peeked_cards:
						c.animate_flip(false)
						c.set_interactive(false)
					peeked_cards.clear()
					_clear_all_highlights()
					GameManager.complete_initial_peek()
		
		GameManager.GameState.TURN_RESOLVE_DRAWN:
			if p_idx == 0:
				GameManager.player_swap_drawn_card(player_hands[0].find(node))
		
		GameManager.GameState.TURN_JUMP_IN_SELECTION:
			# JUMP-IN SELECTION: Use simple persistent-array index
			var is_drawn = (node == pending_card or node.name == "PendingCard")
			var c_idx = -2 if is_drawn else player_hands[0].find(node)
			
			if c_idx != -1 or is_drawn:
				_clear_all_highlights()
				if await GameManager.validate_jump_in(c_idx):
					print("[JUMP-IN] SUCCESS")
				else:
					print("[JUMP-IN] FAILED")
					_on_jump_in_failed(0, c_idx, data)
				
		GameManager.GameState.TURN_PEEK_ABILITY:
			if node.data.is_face_up: return
			_set_all_cards_interactive(false)
			node.animate_flip(true)
			await get_tree().create_timer(3.0, false).timeout
			_clear_all_highlights() # Clear highlights BEFORE flipping back
			node.animate_flip(false)
			_set_all_cards_interactive(true)
			GameManager.complete_peek_ability()
			_clear_all_highlights()
			
		GameManager.GameState.TURN_SWAP_ABILITY:
			if swap_sources.any(func(s): return s.node == node): return
			
			p_idx = -1
			for i in range(4):
				if node.get_parent() == player_pos_nodes[i]:
					p_idx = i; break
			var c_idx = player_hands[p_idx].find(node)
			
			swap_sources.append({"node": node, "player": p_idx, "index": c_idx})
			# User requested NO highlighting/selection visuals for Jack
			
			if swap_sources.size() == 2:
				var s1 = swap_sources[0]
				var s2 = swap_sources[1]
				GameManager.complete_swap_ability(s1.player, s1.index, s2.player, s2.index)
				swap_sources.clear()
				_clear_all_highlights()

func _on_memory_shift_required(p_idx, _c_idx):
	_update_hand_visuals(p_idx)

func _on_deck_input_event(_camera, event, _position, _normal, _shape_idx):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_deck_clicked()

func _on_discard_input_event(_camera, event, _position, _normal, _shape_idx):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_discard_clicked()

func _on_deck_clicked():
	if GameManager.current_player_index == 0:
		GameManager.player_draw_card()

func _on_discard_clicked():
	if GameManager.current_player_index == 0:
		GameManager.player_discard_drawn_card()

func _on_scores_ready(results):
	var overlay = CanvasLayer.new()
	add_child(overlay)
	
	var bg = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.85)
	overlay.add_child(bg)
	
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	center.add_child(vbox)
	
	var title = Label.new()
	title.text = "GAME OVER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	vbox.add_child(title)
	
	for i in range(results.size()):
		var entry = results[i]
		var l = Label.new()
		l.text = "%d. %s: %d pts" % [i + 1, entry.name, entry.score]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 32)
		if i == 0: l.add_theme_color_override("font_color", Color.YELLOW)
		vbox.add_child(l)
	
	var btn_h = HBoxContainer.new()
	btn_h.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_h)
	
	var play_again = Button.new()
	play_again.text = "Play Again"
	play_again.pressed.connect(func(): get_tree().reload_current_scene())
	btn_h.add_child(play_again)
	
	var main_menu = Button.new()
	main_menu.text = "Main Menu"
	main_menu.pressed.connect(_on_pause_main_menu)
	btn_h.add_child(main_menu)

func _unhandled_input(event):
	if event.is_action_pressed("ui_cancel"):
		if DevConsole.window.is_visible():
			return
			
		if pause_menu_instance == null:
			_pause_game()
		else:
			_on_pause_resumed()
		get_viewport().set_input_as_handled()
	
	# DEBUG: Press L to toggle all face-down cards face-up.
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_L:
			_toggle_debug_reveal()

func _pause_game():
	if pause_menu_instance == null:
		pause_menu_instance = pause_menu_scene.instantiate()
		add_child(pause_menu_instance)
		pause_menu_instance.resumed.connect(_on_pause_resumed)
		pause_menu_instance.main_menu_requested.connect(_on_pause_main_menu)
		get_tree().paused = true

func _on_pause_resumed():
	if pause_menu_instance:
		pause_menu_instance.queue_free()
		pause_menu_instance = null
	get_tree().paused = false

func _on_pause_main_menu():
	get_tree().paused = false
	get_tree().change_scene_to_file("res://main_menu.tscn")

func _toggle_debug_reveal():
	if not _debug_reveal:
		_debug_flipped_nodes.clear()
		for i in range(4):
			for card in player_pos_nodes[i].get_children():
				if card is Card3D and not card.data.is_face_up:
					card.animate_flip(true)
					_debug_flipped_nodes.append(card)
		_debug_reveal = true
		_show_message("[DEBUG] All cards revealed")
	else:
		for card in _debug_flipped_nodes:
			if is_instance_valid(card):
				card.animate_flip(false)
		_debug_flipped_nodes.clear()
		_debug_reveal = false
		_hide_message()

# Signal Handlers
func _on_jump_in_penalty(player_idx, _card):
	_update_hand_visuals(player_idx)

func _on_jump_in_failed(player_idx, card_idx, _card_data):
	if player_idx < 0 or player_idx >= 4: return
	
	var card_node = null
	if card_idx == -2:
		card_node = pending_card
	else:
		var hand = player_hands[player_idx]
		if card_idx >= 0 and card_idx < hand.size():
			card_node = hand[card_idx]
			
	if card_node is Card3D:
		print("GameBoard3D: Atomic reveal for card index ", card_idx)
		# Use a dedicated tween sequence on the mesh directly to bypass guards
		var reveal_tween = create_tween()
		
		# Flip UP
		reveal_tween.tween_property(card_node, "rotation_degrees:x", 270.0, 0.3).set_trans(Tween.TRANS_QUAD)
		reveal_tween.parallel().tween_property(card_node, "position:y", 0.8, 0.2).set_trans(Tween.TRANS_QUAD) # Extra lift
		
		reveal_tween.tween_interval(1.5)
		
		# Flip DOWN
		reveal_tween.tween_property(card_node, "rotation_degrees:x", 90.0, 0.3).set_trans(Tween.TRANS_QUAD)
		reveal_tween.parallel().tween_property(card_node, "position:y", 0.05, 0.2).set_trans(Tween.TRANS_QUAD)
		
		reveal_tween.tween_callback(func():
			trigger_glitch(0.3, 0.4)
			shake(0.2, 0.3)
			card_node.data.is_face_up = false
		)

func _on_bot_action(message):
	_show_message(message)

func _process(delta: float) -> void:
	if _shake_timer > 0:
		_shake_timer -= delta
		var offset = Vector3(
			randf_range(-1, 1) * _shake_intensity,
			randf_range(-1, 1) * _shake_intensity,
			0
		)
		camera.position = _base_camera_pos + offset
		if _shake_timer <= 0:
			camera.position = _base_camera_pos

	if noclip_enabled and not DevConsole.window.visible:
		_handle_noclip_movement(delta)
	elif not noclip_enabled:
		var mouse_pos = get_viewport().get_mouse_position()
		var vp_size = get_viewport().get_visible_rect().size
		var nx = mouse_pos.x / float(vp_size.x)
		var target_yaw = 0.0
		
		if nx < 0.2:
			target_yaw = deg_to_rad(12.0) * (0.2 - nx) / 0.2
		elif nx > 0.8:
			target_yaw = -deg_to_rad(12.0) * (nx - 0.8) / 0.2
			
		camera.rotation.y = lerp_angle(camera.rotation.y, _base_camera_rotation.y + target_yaw, delta * 4.0)

func shake(intensity: float, duration: float):
	_shake_intensity = intensity
	_shake_timer = duration

func trigger_glitch(intensity: float, duration: float):
	if not crt_overlay: return
	var mat = crt_overlay.material as ShaderMaterial
	if not mat: return
	
	var tween = create_tween()
	tween.tween_property(mat, "shader_parameter/glitch_intensity", intensity, duration * 0.2)
	tween.tween_property(mat, "shader_parameter/glitch_intensity", 0.0, duration * 0.8)

func _process_shader_time(_delta: float):
	if crt_overlay:
		var mat = crt_overlay.material as ShaderMaterial
		if mat:
			mat.set_shader_parameter("time", Time.get_ticks_msec() / 1000.0)

# Replace the existing _process if it was simple, but I added more above

func _handle_noclip_movement(delta: float) -> void:
	var move_dir = Vector3.ZERO
	if Input.is_key_pressed(KEY_W): move_dir -= camera.global_transform.basis.z
	if Input.is_key_pressed(KEY_S): move_dir += camera.global_transform.basis.z
	if Input.is_key_pressed(KEY_A): move_dir -= camera.global_transform.basis.x
	if Input.is_key_pressed(KEY_D): move_dir += camera.global_transform.basis.x
	if Input.is_key_pressed(KEY_E): move_dir += Vector3.UP
	if Input.is_key_pressed(KEY_Q): move_dir += Vector3.DOWN
	
	camera.global_position += move_dir.normalized() * 10.0 * delta
	_process_shader_time(delta)

func _input(event: InputEvent) -> void:
	if noclip_enabled and not DevConsole.window.visible and event is InputEventMouseMotion:
		camera_rot_y -= event.relative.x * 0.005
		camera_rot_x -= event.relative.y * 0.005
		camera_rot_x = clamp(camera_rot_x, -PI / 2, PI / 2)
		
		camera.basis = Basis() # Reset
		camera.rotate_y(camera_rot_y)
		camera.rotate_object_local(Vector3.RIGHT, camera_rot_x)

func _on_jack_swap_resolved(p1: int, c1: int, p2: int, c2: int) -> void:
	if c1 >= player_hands[p1].size() or c2 >= player_hands[p2].size():
		return
	var node1 = player_hands[p1][c1]
	var node2 = player_hands[p2][c2]
	
	player_hands[p1][c1] = node2
	player_hands[p2][c2] = node1
	
	node1.reparent(player_pos_nodes[p2])
	node2.reparent(player_pos_nodes[p1])
	
	_update_hand_visuals(p1)
	_update_hand_visuals(p2)


func _on_all_cards_revealed():
	# Flip all cards face-up for game over
	_update_turn_lights(-1, true)
	for pos_node in player_pos_nodes.values():
		for c3d in pos_node.get_children():
			if c3d is Card3D:
				c3d.animate_flip(true)

func _on_dutch_called(player_idx: int):
	var player_name = GameManager.players_info[player_idx].name
	_show_message(player_name + " called DUTCH!")
	trigger_glitch(0.5, 0.6)
	shake(0.4, 0.5)
	
	# Turn on all lights for the drama
	_update_turn_lights(-1, true)

func _on_deck_reshuffled():
	_update_deck_visual()
	_show_message("Deck reshuffled!")

func toggle_noclip() -> bool:
	noclip_enabled = !noclip_enabled
	if noclip_enabled:
		base_camera_transform = camera.global_transform
		camera_rot_x = camera.rotation.x
		camera_rot_y = camera.rotation.y
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		camera.global_transform = base_camera_transform
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	return noclip_enabled

func is_noclip_active() -> bool:
	return noclip_enabled

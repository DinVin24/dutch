@tool
extends Node3D

@onready var deck_area = $DeckArea
@onready var discard_area = $DiscardArea
@onready var player_positions_root = $PlayerPositions
@onready var player_pos_nodes = {
	0: $PlayerPositions/Bottom,
	1: $PlayerPositions/Left,
	2: $PlayerPositions/Top,
	3: $PlayerPositions/Right
}
@onready var turn_label = $GameUI/MainHUD/TopLeft/TurnLabel
@onready var top_center = $GameUI/MainHUD/TopCenter
@onready var crt_overlay = $PostProcessing/CRT_Overlay
@onready var turn_indicator_circle = $PlayerPositions/TurnIndicatorCircle
@onready var draw_arrow = $DeckArea/DrawIndicatorArrow
var player_lights = {}
var _bell_stream: AudioStreamWAV = null

var bot_controller: BotController = null
var action_panel: PanelContainer
var end_turn_btn: Button
var jump_in_btn: Button
var call_dutch_btn: Button
var confirm_dutch_btn: Button
var forfeit_dutch_btn: Button
var play_again_btn: Button
var discard_indicator: MeshInstance3D

var player_hands: Array = [[], [], [], []]
var card_spacing = 1.3 # 3D meters
var pending_card: Card3D = null
var pending_card_tween: Tween = null
var swap_sources: Array = [] # Stores [card_node, player_idx, card_idx]
var _keyboard_selected_card_idx: int = -1 # Index into player_hands[0] for keyboard navigation
var _hovered_card_node: Card3D = null # Track hovered card for spreading effect

# Peek Phase state
var cards_peeked: int = 0
var max_peeks: int = 2
var peeked_card_nodes: Array = []

var _debug_reveal := false
var _debug_flipped_nodes: Array = []
var card_scene = preload("res://card_3d.tscn")
var pause_menu_scene = preload("res://pause_menu.tscn")
var beer_scene = preload("res://assets/models/bere.glb")
var pause_menu_instance: Node = null
var noclip_enabled: bool = false
var base_camera_transform: Transform3D
var camera_rot_x: float = 0.0
var camera_rot_y: float = 0.0

# Tavern Visuals
@export_group("Tavern Visuals")
@export var beer_scale: Vector3 = Vector3(3.0, 3.0, 3.0):
	set(value):
		beer_scale = value
		if Engine.is_editor_hint() and is_inside_tree(): _create_beer_placeholders()
@export var beer_spacing: float = 0.25:
	set(value):
		beer_spacing = value
		if Engine.is_editor_hint() and is_inside_tree(): _create_beer_placeholders()
@export var beer_y_offset: float = 0.12:
	set(value):
		beer_y_offset = value
		if Engine.is_editor_hint() and is_inside_tree(): _create_beer_placeholders()
@export var beer_emission: float = 0.08: # Much softer default
	set(value):
		beer_emission = value
		if Engine.is_editor_hint() and is_inside_tree(): _create_beer_placeholders()

var player_beers_nodes: Array = [[], [], [], []]
var money_labels: Array = []
var _chicken_node: Node3D = null
var _chicken_zoom_active: bool = false
var _hovered_shelf_index: int = -1
var _cabinet_prompt_label: Label = null

@onready var camera = $Camera3D
var _current_ability_message: String = ""
var _shake_intensity: float = 0.0
var _shake_timer: float = 0.0
var _base_camera_pos: Vector3
var _base_camera_rotation: Vector3
## Extra shift on top of scene default camera position (e.g. multiplayer seat framing).
var _mp_camera_offset: Vector3 = Vector3.ZERO

# Targeting state
var _is_waiting_for_target: bool = false
var _is_preparing_ability: bool = false # Interaction guard for reveals
var _pending_ability: Dictionary = {} # {id, token, activator}
var _last_sync_diag := {
	"state": -1,
	"cur": -1,
	"deck": -1,
	"discard": -1,
	"pending": false,
	"dutch_i": -1,
	"abilities": [[], [], [], []],
	"beers": [3, 3, 3, 3]
}

func _ready():
	if Engine.is_editor_hint():
		_create_beer_placeholders()
		return

	player_hands = [[], [], [], []]
	_bell_stream = _generate_bell_stream()
	print("Game Board 3D: Ready. Connecting signals...")
	GameManager.stop_menu_music()
	GameManager.play_game_music()
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
	GameManager.polarity_shifted.connect(_on_polarity_shifted)
	GameManager.pending_card_consumed.connect(_on_pending_card_consumed)
	GameManager.multiplayer_sync_applied.connect(_on_multiplayer_sync_applied)
	NetworkManager.play_again_votes_updated.connect(_on_play_again_votes_updated)
	
	# Dynamic Tavern Ambient & Spotlight Lighting
	var center_light = OmniLight3D.new()
	center_light.name = "TavernCenterLight"
	center_light.position = Vector3(0, 3.5, 0)
	center_light.light_color = Color(1.0, 0.85, 0.65)
	center_light.light_energy = 2.0
	center_light.shadow_enabled = true
	center_light.omni_range = 10.0
	add_child(center_light)

	# Dynamic Player Turn Lights
	# P0 bottom, P1 left, P2 top, P3 right
	var light_positions = {
		0: Vector3(0, 2.0, 3.0),
		1: Vector3(-4.5, 2.0, 0),
		2: Vector3(0, 2.0, -3.0),
		3: Vector3(4.5, 2.0, 0)
	}
	var light_colors = {
		0: Color(0.2, 0.6, 1.0), # Neon Blue for local player
		1: Color(1.0, 0.2, 0.2), # Cyber Red for bot/peer 1
		2: Color(0.2, 1.0, 0.4), # Lime Green for bot/peer 2
		3: Color(1.0, 0.8, 0.2)  # Amber Gold for bot/peer 3
	}
	for i in range(4):
		var pl = OmniLight3D.new()
		pl.name = "PlayerTurnLight_" + str(i)
		pl.position = light_positions[i]
		pl.light_color = light_colors[i]
		pl.light_energy = 0.0 # Start off!
		pl.omni_range = 6.0
		pl.shadow_enabled = true
		add_child(pl)
		player_lights[i] = pl

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
	_configure_visible_player_seats(GameManager.num_players)
	_apply_local_player_seat_rotation()
	trigger_glitch(0.4, 0.8) # Intro glitch

	# Tutorial Mode: Inject Chippy's overlay into the UI layer
	if GameManager.tutorial_mode:
		var tut_scene = preload("res://tutorial_overlay.tscn")
		var tut = tut_scene.instantiate()
		$GameUI.add_child(tut)

func _send_action(action: String, args: Dictionary = {}):
	if GameManager.is_multiplayer:
		GameManager.request_action.rpc_id(1, action, args)
	else:
		GameManager.request_action(action, args)

func _human_ui_idx() -> int:
	return GameManager.local_player_idx if GameManager.is_multiplayer else 0

func _effective_camera_base_local() -> Vector3:
	return _base_camera_pos + _mp_camera_offset

## Rotates the four seats around the table so the local peer's hand sits at the bottom (camera-near),
## matching physical \"your cards in front of you\" in multiplayer. Single-player / hotseat: no rotation.
func _apply_local_player_seat_rotation() -> void:
	if not is_instance_valid(player_positions_root):
		return
	if GameManager.is_multiplayer:
		player_positions_root.rotation.y = GameManager.local_player_idx * (TAU / 4.0)
		# Same +Z dolly in board space for every seat so the local hand stays fully in frame after seat rotation.
		const MP_CAMERA_DOLLY_Z := 1.55
		_mp_camera_offset = Vector3(0, 0, MP_CAMERA_DOLLY_Z)
	else:
		player_positions_root.rotation.y = 0.0
		_mp_camera_offset = Vector3.ZERO
	if is_instance_valid(camera):
		camera.position = _effective_camera_base_local()

func _configure_visible_player_seats(n: int) -> void:
	for seat in range(4):
		if player_pos_nodes.has(seat):
			player_pos_nodes[seat].visible = seat < clampi(n, 1, 4)

func _on_multiplayer_sync_applied() -> void:
	var new_state: int = int(GameManager.current_state)
	var new_cur: int = GameManager.current_player_index
	var new_deck: int = GameManager.deck_manager.deck.size()
	var new_discard: int = GameManager.deck_manager.discard_pile.size()
	var new_pending: bool = GameManager.drawn_card_data != null
	var new_dutch_i: int = GameManager.dutch_caller_index
	var state_changed: bool = _last_sync_diag["state"] != new_state or _last_sync_diag["cur"] != new_cur
	var deck_changed: bool = _last_sync_diag["deck"] != new_deck or _last_sync_diag["discard"] != new_discard
	var pending_changed: bool = _last_sync_diag["pending"] != new_pending

	if pending_changed and not new_pending and is_instance_valid(pending_card):
		pending_card.queue_free()
		pending_card = null
	_apply_local_player_seat_rotation()
	_configure_visible_player_seats(GameManager.num_players)
	
	# Snapshot abilities BEFORE _update_hand_visuals so we diff correctly
	var prev_abilities: Array = (_last_sync_diag["abilities"] as Array).duplicate(true)
	
	for i in range(GameManager.num_players):
		_update_hand_visuals(i)
	for j in range(GameManager.num_players, 4):
		for c in player_hands[j].duplicate():
			if is_instance_valid(c):
				c.queue_free()
		player_hands[j].clear()
	if deck_changed:
		_update_deck_visual()
		_update_discard_visual()
	if GameManager.drawn_card_data != null \
			and GameManager.current_state == GameManager.GameState.TURN_RESOLVE_DRAWN \
			and GameManager.current_player_index == GameManager.local_player_idx \
			and pending_card == null:
		var d = GameManager.drawn_card_data
		pending_card = card_scene.instantiate()
		pending_card.name = "PendingCard"
		add_child(pending_card)
		d.is_face_up = true
		pending_card.setup(d)
		pending_card.card_clicked.connect(_on_card_clicked)
		pending_card.position = deck_area.position + Vector3(0, 0.6, 0.5)
		pending_card.rotation_degrees = Vector3(90, 0, 0)
		pending_card.set_interactive(true)
	
	# --- Bug 5: Detect Dutch call and show feedback on client ---
	if new_dutch_i != -1 and _last_sync_diag["dutch_i"] == -1:
		_on_dutch_called(new_dutch_i)
	
	# --- Bug 3: Refresh local player money label from synced data ---
	var local_idx := GameManager.local_player_idx
	if local_idx >= 0 and local_idx < GameManager.players_info.size():
		if money_labels.size() > 0:
			money_labels[0].text = "$" + str(GameManager.players_info[local_idx].money)
	
	# --- Bug fix: Synchronize beers and play drinking effect if decreased ---
	var prev_beers: Array = _last_sync_diag.get("beers", [3, 3, 3, 3])
	for pi in range(GameManager.num_players):
		var cur_beers = GameManager.players_info[pi].beers
		var old_b = prev_beers[pi] if pi < prev_beers.size() else 3
		if old_b != -1 and cur_beers < old_b:
			_on_player_drank_beer(pi, cur_beers)
		else:
			# Just silently update visibility
			if pi < player_beers_nodes.size():
				var beers_array = player_beers_nodes[pi]
				for k in range(beers_array.size()):
					beers_array[k].visible = (k < cur_beers)
	
	# --- Bug 4: Detect ability changes and fire local visual feedback ---
	# Only diff if we have a prior snapshot (skip the very first sync to avoid spurious events)
	if not prev_abilities.is_empty() and prev_abilities.any(func(a): return a is Array):
		for pi in range(GameManager.num_players):
			var new_abs: Array = GameManager.players_info[pi].abilities
			var old_abs: Array = prev_abilities[pi] if pi < prev_abilities.size() else []
			# Ability appeared in the new list — player gained it
			for ab in new_abs:
				if not ab in old_abs:
					_on_ability_unlocked(pi, ab)
			# Ability disappeared from the list — player used it
			for ab in old_abs:
				if not ab in new_abs:
					_on_ability_played(pi, ab)
	
	if state_changed:
		_on_game_state_changed(GameManager.current_state)
	_last_sync_diag["state"] = new_state
	_last_sync_diag["cur"] = new_cur
	_last_sync_diag["deck"] = new_deck
	_last_sync_diag["discard"] = new_discard
	_last_sync_diag["pending"] = new_pending
	_last_sync_diag["dutch_i"] = new_dutch_i
	# Snapshot abilities for next sync comparison
	var abilities_snapshot: Array = []
	for pi in range(4):
		if pi < GameManager.players_info.size():
			abilities_snapshot.append(GameManager.players_info[pi].abilities.duplicate())
		else:
			abilities_snapshot.append([])
	_last_sync_diag["abilities"] = abilities_snapshot
	
	# Snapshot beers for next sync comparison
	var beers_snapshot: Array = []
	for pi in range(4):
		if pi < GameManager.players_info.size():
			beers_snapshot.append(GameManager.players_info[pi].beers)
		else:
			beers_snapshot.append(3)
	_last_sync_diag["beers"] = beers_snapshot
	_update_draw_arrow_visibility()

func _create_hud_ui():
	# Action Panel: Style Box Flat with 20% opacity dark background, rounded corners and subtle border
	action_panel = PanelContainer.new()
	action_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	action_panel.offset_left = 20
	action_panel.offset_right = 260
	action_panel.offset_top = -220
	action_panel.offset_bottom = -20
	action_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.04, 0.04, 0.06, 0.20)
	panel_style.border_width_left = 3
	panel_style.border_width_right = 3
	panel_style.border_width_top = 3
	panel_style.border_width_bottom = 3
	panel_style.border_color = Color(0.15, 0.18, 0.22, 0.4)
	panel_style.corner_radius_top_left = 10
	panel_style.corner_radius_top_right = 10
	panel_style.corner_radius_bottom_left = 10
	panel_style.corner_radius_bottom_right = 10
	
	# Content margins to pad the buttons inside
	panel_style.content_margin_left = 15
	panel_style.content_margin_right = 15
	panel_style.content_margin_top = 15
	panel_style.content_margin_bottom = 15
	
	action_panel.add_theme_stylebox_override("panel", panel_style)
	$GameUI/MainHUD.add_child(action_panel)

	# Action Buttons Container: Nested inside the Action Panel
	var action_container = VBoxContainer.new()
	action_container.alignment = BoxContainer.ALIGNMENT_END
	action_container.add_theme_constant_override("separation", 15)
	action_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	action_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	action_panel.add_child(action_container)

	# Standard HUD buttons
	end_turn_btn = _create_button(action_container, "> END_TURN <", Color(0.0, 1.0, 1.0))
	jump_in_btn = _create_button(action_container, "> JUMP_IN <", Color(0.0, 1.0, 1.0))
	call_dutch_btn = _create_button(action_container, "> CALL_DUTCH <", Color(1.0, 0.0, 0.8))
	confirm_dutch_btn = _create_button(action_container, "> CONFIRM_DUTCH <", Color(0.0, 1.0, 1.0))
	forfeit_dutch_btn = _create_button(action_container, "> FORFEIT_DUTCH <", Color(1.0, 0.0, 0.8))
	end_turn_btn.pressed.connect(_on_end_turn_pressed)
	jump_in_btn.pressed.connect(_on_jump_in_pressed)
	call_dutch_btn.pressed.connect(_on_call_dutch_pressed)
	confirm_dutch_btn.pressed.connect(_on_confirm_dutch_pressed)
	forfeit_dutch_btn.pressed.connect(_on_cancel_dutch_pressed)
	
	# Restyle the TurnLabel
	turn_label.add_theme_color_override("font_color", Color(0.0, 1.0, 1.0))
	turn_label.add_theme_color_override("font_shadow_color", Color(0.0, 1.0, 1.0, 0.3))
	turn_label.add_theme_constant_override("shadow_offset_x", 0)
	turn_label.add_theme_constant_override("shadow_offset_y", 2)
	
	# Local Player Money Label (Only show P0)
	var l = Label.new()
	l.text = "$0"
	l.add_theme_font_size_override("font_size", 24)
	l.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2))
	l.add_theme_color_override("font_shadow_color", Color(1.0, 0.9, 0.2, 0.3))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 2)
	$GameUI/MainHUD/TopLeft.add_child(l)
	money_labels.append(l)

	# Cabinet Interaction HUD Prompt
	_cabinet_prompt_label = Label.new()
	_cabinet_prompt_label.name = "CabinetPrompt"
	_cabinet_prompt_label.add_theme_font_size_override("font_size", 28)
	_cabinet_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cabinet_prompt_label.add_theme_color_override("font_color", Color(1.0, 0.0, 0.8))
	_cabinet_prompt_label.add_theme_color_override("font_shadow_color", Color(1.0, 0.0, 0.8, 0.5))
	_cabinet_prompt_label.add_theme_constant_override("shadow_offset_x", 0)
	_cabinet_prompt_label.add_theme_constant_override("shadow_offset_y", 2)
	_cabinet_prompt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_cabinet_prompt_label.offset_left = -300
	_cabinet_prompt_label.offset_right = 300
	_cabinet_prompt_label.offset_top = -100
	_cabinet_prompt_label.offset_bottom = -50
	_cabinet_prompt_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_cabinet_prompt_label.text = ""
	_cabinet_prompt_label.hide()
	$GameUI/MainHUD.add_child(_cabinet_prompt_label)

func _create_button(parent: Node, text: String, color: Color) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 24)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_width_left = 4
	style.border_color = color

	var hover_style = StyleBoxFlat.new()
	hover_style.bg_color = color
	hover_style.border_width_left = 4
	hover_style.border_color = color.lightened(0.5)

	# Disabled state style: faded border (25% opacity)
	var disabled_style = StyleBoxFlat.new()
	disabled_style.bg_color = Color(0, 0, 0, 0)
	disabled_style.border_width_left = 4
	disabled_style.border_color = Color(color.r, color.g, color.b, 0.25)

	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", hover_style)
	btn.add_theme_stylebox_override("pressed", hover_style)
	btn.add_theme_stylebox_override("disabled", disabled_style)
	
	btn.add_theme_color_override("font_color", color)
	btn.add_theme_color_override("font_hover_color", Color.BLACK)
	btn.add_theme_color_override("font_pressed_color", Color.BLACK)
	# Disabled text color: faded font color (25% opacity)
	btn.add_theme_color_override("font_disabled_color", Color(color.r, color.g, color.b, 0.25))
	
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	
	parent.add_child(btn)
	
	# Explicitly set mouse filter to STOP for the button so it can still be clicked,
	# but its PARENT (action_container) is IGNORE so clicks pass through the spacing.
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	
	btn.custom_minimum_size = Vector2(240, 45)
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
		var top_info: CardData = pile.back()
		var card_node = card_scene.instantiate()
		discard_area.add_child(card_node)
		card_node.setup(top_info.duplicate())
		card_node.data.is_face_up = true
		card_node.rotation_degrees = Vector3(90, 0, 0)
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
	# Clear existing editor-only or placeholder nodes first
	for i in range(4):
		var pos_node = _get_safe_player_pos(i)
		if not pos_node: continue
		for child in pos_node.get_children():
			if child.is_in_group("beer_placeholders"):
				child.queue_free()
	
	player_beers_nodes = [[], [], [], []]
	
	for i in range(4):
		var pos_node = _get_safe_player_pos(i)
		if not pos_node: continue
		for b in range(3):
			var beer = beer_scene.instantiate()
			beer.add_to_group("beer_placeholders")
			beer.scale = beer_scale
			
			# Apply emission energy if requested to clear up "dark sides"
			# We recursively look for any MeshInstance3D inside the imported GLB
			_apply_emission_to_meshes(beer, beer_emission)
			
			# Keep all beers on the RIGHT side, slightly in front of the hand.
			# This avoids mirrored/left placement in multiplayer seat rotations.
			var right_x_base := 1.8
			var front_z := 1.35
			var right_offset := b * beer_spacing
			beer.position = Vector3(right_x_base + right_offset, beer_y_offset, front_z)
			pos_node.add_child(beer)
			player_beers_nodes[i].append(beer)

func _get_safe_player_pos(idx: int) -> Node3D:
	# In tool mode, @onready vars might not be available, so fallback to direct get_node
	if player_pos_nodes and player_pos_nodes.has(idx) and is_instance_valid(player_pos_nodes[idx]):
		return player_pos_nodes[idx]
	
	var paths = {
		0: "PlayerPositions/Bottom",
		1: "PlayerPositions/Left",
		2: "PlayerPositions/Top",
		3: "PlayerPositions/Right"
	}
	return get_node_or_null(paths[idx])

func _apply_emission_to_meshes(node: Node, energy: float):
	for child in node.get_children():
		if child is MeshInstance3D and child.mesh:
			for surface in range(child.mesh.get_surface_count()):
				var mat = child.get_active_material(surface)
				if mat is StandardMaterial3D:
					# Subtle emission fill using the model's own colors
					mat.emission_enabled = (energy > 0)
					mat.emission_energy_multiplier = energy
					mat.emission_texture = mat.albedo_texture
					mat.emission = mat.albedo_color
					
					# BALANCED lighting interaction:
					# Reset to realistic matte-plastic values (not wax, not void)
					mat.roughness = 0.8
					mat.metallic = 0.0
					# Godot 4 uses metallic_specular instead of legacy specular.
					mat.metallic_specular = 0.5
					
					# Force the material to be unique per beer instance
					child.set_surface_override_material(surface, mat)
		_apply_emission_to_meshes(child, energy)

func _create_chicken_placeholder():
	var chicken = preload("res://assets/models/chick.glb").instantiate()
	chicken.position = Vector3(4.0, 1.2, -3.5)
	# Scale down the model (GLBs can be very large)
	chicken.scale = Vector3(0.05, 0.05, 0.05)
	# Rotate 180 on Y to face player
	chicken.rotation_degrees = Vector3(90, 180, 0)
	add_child(chicken)
	_chicken_node = chicken	
	
	# Apply texture
	var tex = load("res://assets/models/chicken.bmp")
	if tex:
		var mat = StandardMaterial3D.new()
		mat.albedo_texture = tex
		# Recursively apply to all meshes in the GLB
		var meshes = chicken.find_children("*", "MeshInstance3D", true, false)
		for m in meshes:
			for i in range(m.mesh.get_surface_count()):
				m.set_surface_override_material(i, mat)

	var area = Area3D.new()
	var col = CollisionShape3D.new()
	var shape = SphereShape3D.new()
	# Compensate for chicken scaling to keep a clickable area of ~0.6m radius
	shape.radius = 12.0 
	col.shape = shape
	area.add_child(col)
	chicken.add_child(area)
	
	area.input_event.connect(_on_chicken_clicked)
	GameManager.ability_unlocked.connect(_on_ability_unlocked)

func _on_ability_unlocked(p_idx: int, ab: String):
	_drop_egg_for(p_idx, ab)

func _on_chicken_clicked(_camera, event, _position, _normal, _shape_idx):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if GameManager.current_player_index == GameManager.local_player_idx:
			_try_buy_ability(GameManager.local_player_idx)

func _try_buy_ability(p_idx: int):
	if GameManager.players_info[p_idx].abilities.size() >= 8:
		_show_message("Inventory Full! (Max 8)")
		return
		
	_send_action("buy_ability")

func _drop_egg_for(p_idx: int, ab: String):
	if p_idx == _human_ui_idx():
		_show_message("You got: " + ab.capitalize() + "!")
	else:
		_show_message(GameManager.players_info[p_idx].name + " got an egg!")
	
	if is_instance_valid(_chicken_node):
		spawn_particles("ability_buy", _chicken_node.global_position)
		var tween = create_tween()
		tween.tween_property(_chicken_node, "position:y", 2.0, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(_chicken_node, "position:y", 1.2, 0.2).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)

		# Camera cinematic zoom - GUARD against re-entry
		if not _chicken_zoom_active:
			_chicken_zoom_active = true
			var target_pos = _chicken_node.global_position + Vector3(0, 1.5, 2.5)
			var cam_tween = create_tween()
			var restore_cam_local = _effective_camera_base_local()
			var original_fov = camera.fov
			var original_rot = camera.rotation_degrees
			
			cam_tween.tween_property(camera, "global_position", target_pos, 0.3).set_trans(Tween.TRANS_CUBIC)
			cam_tween.parallel().tween_property(camera, "rotation_degrees", Vector3(-20, 0, 0), 0.3).set_trans(Tween.TRANS_CUBIC)
			cam_tween.parallel().tween_property(camera, "fov", 45.0, 0.3).set_trans(Tween.TRANS_CUBIC)
			cam_tween.tween_interval(0.8)
			cam_tween.tween_property(camera, "position", restore_cam_local, 0.4).set_trans(Tween.TRANS_QUAD)
			cam_tween.parallel().tween_property(camera, "rotation_degrees", original_rot, 0.4).set_trans(Tween.TRANS_QUAD)
			cam_tween.parallel().tween_property(camera, "fov", original_fov, 0.4).set_trans(Tween.TRANS_QUAD)
			cam_tween.tween_callback(func():
				camera.position = restore_cam_local
				_chicken_zoom_active = false
			)
	# authoritative inventory is now managed in GameManager.buy_ability
	print("BOARD: sync ability visuals for P", p_idx)
	_update_ability_visuals(p_idx)
	
	# Spawn ability token visually
	var token_scene = load("res://ability_token_3d.tscn")
	var token = token_scene.instantiate()
	player_pos_nodes[p_idx].add_child(token)
	token.setup(ab)
	token.token_clicked.connect(_on_ability_token_clicked)
	
	# Spawn at the chicken's global position, then beautifully tween into the grid
	# Rotation 180 on Y fixes the upside-down question mark
	token.rotation_degrees = Vector3(90, 180, 0) 
	token.global_position = Vector3(0, 2.0, 0) 
	
	# REVEAL ON RECEIPT: Show for 2 seconds then flip down
	token.set_face_up(true)
	get_tree().create_timer(2.0, false).timeout.connect(func():
		if is_instance_valid(token):
			token.animate_flip(false)
	)
	
	_update_ability_visuals(p_idx)
	
func _update_ability_visuals(p_idx: int):
	var tokens = []
	for c in player_pos_nodes[p_idx].get_children():
		if "ability_id" in c and not c.is_queued_for_deletion():
			tokens.append(c)
			
	for i in range(tokens.size()):
		var t = tokens[i]
		var cols = i % 4
		var rows = floori(i / 4.0)
		
		# Clean, perfect 4x4 matrix centered right next to the hand
		# x spacing: 0.8, z spacing: 0.8 (for 0.65m tokens)
		var target_pos = Vector3(3.5 + (cols * 0.8), 0.1, (rows * 0.8) - 0.4)
		
		# Snappy, satisfying placement animation
		var tween = create_tween()
		tween.tween_property(t, "position", target_pos, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
func _on_ability_token_clicked(token):
	var p_idx = -1
	for i in range(4):
		if token.get_parent() == player_pos_nodes[i]:
			p_idx = i; break
	
	if p_idx == GameManager.current_player_index:
		if _is_preparing_ability or _is_waiting_for_target: return
		
		# REVEAL ON USE: Flip up and wait 2 seconds
		_is_preparing_ability = true
		token.animate_flip(true)
		await get_tree().create_timer(2.0, false).timeout
		_is_preparing_ability = false
		
		if not is_instance_valid(token): return
		
		var targeting_abilities = ["bottoms_up", "boulder", "skip", "inflation", "half_off", "shuffle", "jumpscare"]
		
		if token.ability_id in targeting_abilities:
			print("BOARD: Ability ", token.ability_id, " requires target selection.")
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
			_send_action("play_ability", {"ability_id": token.ability_id, "target_idx": target})
			# Visual cleanup now handled by _on_ability_played signal for all players
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
		print("[BOARD DEBUG] TARGET RESOLVED: Player ", player_idx, " was chosen as target for ", _pending_ability.get("id", "UNKNOWN"))
		
		# Validation: ensure we aren't targeting an already eliminated player
		if GameManager.players_info[player_idx].is_eliminated:
			_show_message("Target is already out!")
			return

		var ab_id = _pending_ability.id
		var activator = _pending_ability.activator

		print("[DEBUG] Requesting play_ability: ", ab_id, " by P", activator, " on P", player_idx)
		
		_send_action("play_ability", {"ability_id": ab_id, "target_idx": player_idx})
		_is_waiting_for_target = false
		_set_targeting_areas_enabled(false)
		_clear_all_highlights()
		_update_turn_lights(activator) # Reset lights to activator's turn
		_hide_message()
		
		# Visual cleanup: token itself is already removed by play_ability signal callback
		# but we clear the pending data here
		_pending_ability.clear()
		_update_ability_visuals(activator)

func _on_player_drank_beer(player_idx, remaining):
	if player_idx < 0 or player_idx >= 4: return
	var beers_array = player_beers_nodes[player_idx]
	for i in range(beers_array.size()):
		var is_drinking = beers_array[i].visible and (i >= remaining)
		if is_drinking:
			spawn_particles("beer_drink", beers_array[i].global_position + Vector3(0, 0.2, 0))
		beers_array[i].visible = (i < remaining)
	shake(0.2, 0.3)

func _on_player_eliminated(player_idx):
	_show_message(GameManager.players_info[player_idx].name + " PASSED OUT!")

func _on_player_gained_money(player_idx, _amount, total):
	if player_idx == _human_ui_idx() and money_labels.size() > 0:
		money_labels[0].text = "$" + str(total)

func _on_ability_played(player_idx, ability_id):
	var p_name = GameManager.players_info[player_idx].name
	_show_message(p_name + " used " + ability_id.capitalize() + "!")
	
	# CENTRALIZED VISUAL CLEANUP: Find and remove the 3D token
	var pos_node = player_pos_nodes[player_idx]
	var token_node: AbilityToken3D = null
	for child in pos_node.get_children():
		if "ability_id" in child and child.ability_id == ability_id:
			token_node = child
			break
	
	if token_node:
		spawn_particles("ability_use", token_node.global_position)
		# If it's a bot (p_idx != 0), we want to reveal the card for 2s too
		# if it's not already face up (the human reveal handles p_idx=0)
		if player_idx != _human_ui_idx():
			token_node.animate_flip(true)
			await get_tree().create_timer(2.0, false).timeout
		
		if is_instance_valid(token_node):
			token_node.queue_free()
	
	# Re-layout remaining tokens for this player
	await get_tree().process_frame
	_update_ability_visuals(player_idx)

func _on_turn_started(player_idx):
	var p_info = GameManager.players_info[player_idx]
	turn_label.text = "> " + p_info.name.to_upper() + "'S TURN"
	_animate_glitch_text(turn_label)
	_update_turn_lights(player_idx)
	
	if is_instance_valid(turn_indicator_circle):
		var mat = turn_indicator_circle.get_active_material(0)
		if mat is ShaderMaterial:
			mat.set_shader_parameter("active_player_index", player_idx)
			
	if player_idx == _human_ui_idx():
		GameManager.play_sfx(_bell_stream)
	else:
		_show_message(p_info.name + " is thinking...")
	_update_draw_arrow_visibility()

func _update_draw_arrow_visibility():
	if is_instance_valid(draw_arrow):
		draw_arrow.visible = GameManager.can_player_draw(_human_ui_idx())

func _update_turn_lights(current_player: int, all_on: bool = false):
	for i in range(4):
		var pl = player_lights.get(i)
		if is_instance_valid(pl):
			var target_energy = 0.0
			if all_on:
				target_energy = 1.2
			elif i == current_player:
				target_energy = 2.5 # High energy active glow
			else:
				target_energy = 0.15 # Softer background neon ambience
			
			var tween = create_tween()
			tween.tween_property(pl, "light_energy", target_energy, 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
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

	if player_idx != _human_ui_idx():
		_show_message(GameManager.players_info[player_idx].name + " is drawing...")

	pending_card = card_scene.instantiate()
	pending_card.name = "PendingCard"
	add_child(pending_card)

	card_data.is_face_up = false
	pending_card.setup(card_data)
	pending_card.card_clicked.connect(_on_card_clicked)
	# Move slightly higher and CLOSER TO CAMERA (Z offset) to ensure it's not blocked by DeckArea
	pending_card.position = deck_area.position + Vector3(0, 0.6, 0.5)
	pending_card.rotation_degrees = Vector3(90, 0, 0) # Start face down on the table
	pending_card.set_interactive(player_idx == _human_ui_idx())
	spawn_particles("default", deck_area.global_position)

	# Reveal animations
	await get_tree().create_timer(0.1, false).timeout
	pending_card.animate_flip(player_idx == _human_ui_idx())
	_update_deck_visual() # Refresh deck after drawing

func _on_card_discarded(player_idx, card_data):
	_update_action_buttons_state()
	
	print("GameBoard3D: Card Discarded. Player: ", player_idx, " Data: ", card_data.rank, " of ", card_data.suit)
	
	var card_to_discard: Node3D = null

	# 1. CHECK PENDING CARD (from deck draw)
	if is_instance_valid(pending_card) and (pending_card.data == card_data or (pending_card.data.rank == card_data.rank and pending_card.data.suit == card_data.suit)):
		card_to_discard = pending_card
		pending_card = null
	
	# 2. CHECK PLAYER HANDS
	elif player_idx != -1:
		var hand_nodes = player_hands[player_idx]
		for i in range(hand_nodes.size()):
			var node = hand_nodes[i]
			if is_instance_valid(node) and (node.data == card_data or (node.data.rank == card_data.rank and node.data.suit == card_data.suit)):
				card_to_discard = node
				break

	# 3. FALLBACK
	if card_to_discard == null and player_idx >= 0:
		card_to_discard = card_scene.instantiate()
		add_child(card_to_discard)
		card_to_discard.setup(card_data)
		card_to_discard.global_position = player_pos_nodes[player_idx].global_position

	# 4. ANIMATE DISCARD
	if card_to_discard:
		card_to_discard.is_discarding = true # SET FLAG IMMEDIATELY
		card_to_discard.set_highlight(false)
		card_to_discard.set_interactive(false)
		
		# Move to root scene for clean global animation
		var start_global_pos = card_to_discard.global_position
		if card_to_discard.get_parent() != get_tree().root:
			card_to_discard.reparent(get_tree().root)
		card_to_discard.global_position = start_global_pos
		
		var target_global_pos = discard_area.global_position + Vector3(0, 0.05, 0)
		var tween = create_tween().set_parallel(true)
		tween.tween_property(card_to_discard, "global_position", target_global_pos, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(card_to_discard, "rotation_degrees:x", 90.0, 0.45) # Keep horizontal, let animate_flip roll it
		card_to_discard.animate_flip(true)
		tween.chain().tween_callback(func():
			_update_discard_visual()
			_update_deck_visual()
			shake(0.05, 0.2)
			spawn_particles("default", target_global_pos)
			if is_instance_valid(card_to_discard):
				card_to_discard.queue_free()
		)

	# 5. REFRESH HAND (Always refresh, even if node wasn't found, to sync parity)
	if player_idx != -1:
		_update_hand_visuals(player_idx)

func _show_message(text: String):
	_current_ability_message = text
	for child in top_center.get_children():
		child.queue_free()

	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 32)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color(0.0, 1.0, 1.0))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 3)
	label.add_theme_constant_override("shadow_offset_y", 3)
	top_center.add_child(label)
	# Bug 5: responsive pos
	top_center.set_anchors_preset(Control.PRESET_CENTER_TOP)
	label.show()

func _on_end_turn_pressed():
	if GameManager.can_player_end_turn(GameManager.local_player_idx):
		_send_action("end_turn")
	elif GameManager.can_player_cancel_jump_in(GameManager.local_player_idx):
		_send_action("cancel_jump_in")

func _on_jump_in_pressed():
	if GameManager.can_player_start_jump_in(GameManager.local_player_idx):
		_send_action("start_jump_in")

func _on_call_dutch_pressed():
	if GameManager.can_player_call_dutch(GameManager.local_player_idx):
		_send_action("call_dutch")

func _on_confirm_dutch_pressed():
	if GameManager.can_player_confirm_dutch(GameManager.local_player_idx):
		_send_action("confirm_dutch")

func _on_cancel_dutch_pressed():
	if GameManager.can_player_cancel_dutch(GameManager.local_player_idx):
		_send_action("cancel_dutch")

func _update_action_buttons_state():
	if not is_instance_valid(end_turn_btn) or not is_instance_valid(jump_in_btn) or not is_instance_valid(call_dutch_btn):
		return

	var local_idx = _human_ui_idx()
	
	# Determine if each action is allowed right now
	var can_end_turn = GameManager.can_player_end_turn(local_idx) or GameManager.can_player_cancel_jump_in(local_idx)
	var can_jump_in = GameManager.can_player_start_jump_in(local_idx) or GameManager.should_human_show_jump_in_button(local_idx)
	var can_call_dutch = GameManager.can_player_call_dutch(local_idx)

	# Set button disabled states (disabled = not allowed)
	end_turn_btn.disabled = not can_end_turn
	jump_in_btn.disabled = not can_jump_in
	call_dutch_btn.disabled = not can_call_dutch

	# The three core actions are always visible inside the action panel
	end_turn_btn.visible = true
	jump_in_btn.visible = true
	call_dutch_btn.visible = true

	# Confirm Dutch and Forfeit Dutch are only shown in TURN_CONFIRM_DUTCH state
	var is_confirm_dutch_state = GameManager.current_state == GameManager.GameState.TURN_CONFIRM_DUTCH
	var can_confirm = GameManager.can_player_confirm_dutch(local_idx)
	
	confirm_dutch_btn.visible = is_confirm_dutch_state
	confirm_dutch_btn.disabled = not can_confirm
	
	forfeit_dutch_btn.visible = is_confirm_dutch_state
	forfeit_dutch_btn.disabled = not can_confirm

	# Update the action panel's pulsing/glowing style
	_update_action_panel_style()

func _update_action_panel_style():
	if not is_instance_valid(action_panel):
		return
	
	var local_idx = _human_ui_idx()
	# It is the player's turn to act if it's their current player index and state is an active playing state
	var is_my_turn = (GameManager.current_player_index == local_idx) and not (
		GameManager.current_state in [
			GameManager.GameState.INITIALIZING, 
			GameManager.GameState.DEAL_CARDS, 
			GameManager.GameState.GAME_OVER
		]
	)
	
	var style = action_panel.get_theme_stylebox("panel") as StyleBoxFlat
	if not style:
		return
		
	if is_my_turn:
		# Static neon cyan border when it's our turn
		style.border_color = Color(0.0, 1.0, 1.0, 0.85)
		style.bg_color = Color(0.04, 0.04, 0.06, 0.20)
	else:
		# Static dim grey-blue when not our turn
		style.border_color = Color(0.15, 0.18, 0.22, 0.4)
		style.bg_color = Color(0.04, 0.04, 0.06, 0.20)

func _on_game_state_changed(new_state):
	_hide_message()
	_update_draw_arrow_visibility()

	var is_active_turn_state = new_state in [
		GameManager.GameState.TURN_START_DRAW,
		GameManager.GameState.TURN_RESOLVE_DRAWN,
		GameManager.GameState.TURN_PEEK_ABILITY,
		GameManager.GameState.TURN_SWAP_ABILITY,
		GameManager.GameState.TURN_END_CHOICE,
		GameManager.GameState.TURN_JUMP_IN_SELECTION,
		GameManager.GameState.TURN_CONFIRM_DUTCH
	]
	if not is_active_turn_state and is_instance_valid(turn_indicator_circle):
		var mat = turn_indicator_circle.get_active_material(0)
		if mat is ShaderMaterial:
			mat.set_shader_parameter("active_player_index", -1)

	_update_action_buttons_state()
	_refresh_human_interactivity()
	if new_state == GameManager.GameState.TURN_START_DRAW or \
	   new_state == GameManager.GameState.TURN_END_CHOICE:
		_clear_all_highlights()

	match new_state:
		GameManager.GameState.DEAL_CARDS:
			turn_label.text = "> DEALING CARDS"
			# Clients receive the dealt state via sync from the host — never deal locally.
			if not GameManager.is_multiplayer or multiplayer.is_server():
				_handle_initial_deal()
		GameManager.GameState.INITIAL_PEEK:
			turn_label.text = "> PEEKING PHASE"
			_start_peek_phase()
			_update_turn_lights(-1, true)
		GameManager.GameState.TURN_RESOLVE_DRAWN:
			print("GameBoard3D: UI - Showing TURN_RESOLVE_DRAWN")
			if GameManager.can_player_discard_drawn_card(_human_ui_idx()):
				_show_message("Click a card in your hand to swap, or the drawn card to discard.")
				_highlight_selectable_cards(false)
			else:
				var player_name = GameManager.players_info[GameManager.current_player_index].name
				_show_message(player_name + " is deciding...")
		GameManager.GameState.TURN_END_CHOICE:
			print("GameBoard3D: UI - Showing TURN_END_CHOICE")
		GameManager.GameState.TURN_JUMP_IN_SELECTION:
			print("GameBoard3D: UI - Showing TURN_JUMP_IN_SELECTION")
			var ji_idx = GameManager.jump_in_player_idx
			var ji_name = GameManager.players_info[ji_idx].name if ji_idx >= 0 else "Someone"
			_show_message(ji_name + ": pick a matching card, or end turn to cancel.")
			_highlight_selectable_cards(false)
		GameManager.GameState.TURN_CONFIRM_DUTCH:
			print("GameBoard3D: UI - Showing TURN_CONFIRM_DUTCH")
			if GameManager.can_player_confirm_dutch(_human_ui_idx()):
				_show_message("You called Dutch! Confirm or Forfeit?")
		GameManager.GameState.TURN_PEEK_ABILITY:
			if GameManager.active_ability_player == _human_ui_idx():
				_show_message("Select ANY card to peek at.")
				_highlight_selectable_cards(true)
			_update_turn_lights(-1, true)
		GameManager.GameState.TURN_SWAP_ABILITY:
			if GameManager.active_ability_player == _human_ui_idx():
				_show_message("Select TWO cards to swap.")
				_highlight_selectable_cards(true)
			_update_turn_lights(-1, true)
			swap_sources.clear()
		GameManager.GameState.GAME_OVER:
			# Bug 6: On multiplayer client, _handle_game_over() never runs here.
			# Detect GAME_OVER from the sync and calculate/show scores from local synced data.
			if GameManager.is_multiplayer and not multiplayer.is_server():
				_on_scores_ready(GameManager._calculate_scores())

	$DeckArea/Area3D.input_ray_pickable = GameManager.can_player_draw(_human_ui_idx())
	$DiscardArea/Area3D.input_ray_pickable = GameManager.can_player_discard_drawn_card(_human_ui_idx())

func _set_all_cards_interactive(enabled: bool):
	for i in range(4):
		_set_player_hand_interactive(i, enabled)

func _refresh_human_interactivity() -> void:
	_set_all_cards_interactive(false)
	if is_instance_valid(pending_card):
		pending_card.set_interactive(
			GameManager.can_player_discard_drawn_card(_human_ui_idx()) or GameManager.can_player_select_jump_in_card(_human_ui_idx(), _human_ui_idx(), -2)
		)
	for p_idx in range(player_hands.size()):
		for c_idx in range(player_hands[p_idx].size()):
			var card = player_hands[p_idx][c_idx]
			if is_instance_valid(card) and GameManager.can_human_interact_with_hand_card(p_idx, c_idx, card.data.is_face_up):
				card.set_interactive(true)

func _set_player_hand_interactive(player_idx: int, enabled: bool):
	if player_idx < 0 or player_idx >= player_hands.size(): return
	for card in player_hands[player_idx]:
		if is_instance_valid(card):
			card.set_interactive(enabled)

func _highlight_selectable_cards(is_target_phase: bool = false):
	_clear_all_highlights()
	
	# Handle pending card highlighting
	if is_instance_valid(pending_card) and (
		GameManager.can_player_discard_drawn_card(_human_ui_idx()) or GameManager.can_player_select_jump_in_card(_human_ui_idx(), _human_ui_idx(), -2)
	):
		pending_card.set_highlight(true)
		pending_card.set_interactive(true)

	for p_idx in range(player_hands.size()):
		# During regular play, we usually only care about human's hand (p_idx=0)
		# EXCEPT for swap abilities (which allow cross-player selection)
		var is_swap_state = GameManager.current_state == GameManager.GameState.TURN_SWAP_ABILITY
		if not is_target_phase and not is_swap_state and p_idx != _human_ui_idx():
			continue
			
		for c_idx in range(player_hands[p_idx].size()):
			var card = player_hands[p_idx][c_idx]
			if is_instance_valid(card):
				var allowed := false
				if is_target_phase:
					# Targeting phase: any non-eliminated player is a valid target
					allowed = not GameManager.players_info[p_idx].is_eliminated
				else:
					# Regular interaction: check FSM rules (peek, swap, draw-resolve)
					allowed = GameManager.can_human_interact_with_hand_card(p_idx, c_idx, card.data.is_face_up)
				
				card.set_highlight(allowed)
				card.set_interactive(allowed)

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
	# Easy mode: handle card visibility persistence
	if GameManager.easy_mode:
		if player_idx == _human_ui_idx():
			# Keep all of local human's cards face-up
			for card in player_hands[_human_ui_idx()]:
				if is_instance_valid(card) and not card.data.is_face_up:
					card.data.is_face_up = true
					card.animate_flip(true)
		else:
			# Defensive: Force enemy cards face-down if they leaked (e.g. swapped from P0)
			# EXCEPT if they are currently being peeked by an ability.
			for card in player_hands[player_idx]:
				if is_instance_valid(card) and card.data.is_face_up and not card.is_being_peeked:
					card.data.is_face_up = false
					card.animate_flip(false)

func _on_card_hover_enter(card_node: Node3D):
	if not is_instance_valid(card_node): return
	_hovered_card_node = card_node as Card3D
	
	if card_node.has_method("set_hovered"):
		card_node.set_hovered(true)
	
	# Trigger layout refresh for neighbor spreading
	for i in range(4):
		if card_node in player_hands[i]:
			_update_hand_visuals(i)
			break

func _on_card_hover_exit(card_node: Node3D):
	if not is_instance_valid(card_node): return
	if _hovered_card_node == card_node:
		_hovered_card_node = null
	
	if card_node.has_method("set_hovered"):
		card_node.set_hovered(false)
	
	for i in range(4):
		if card_node in player_hands[i]:
			_update_hand_visuals(i)
			break

func _update_hand_visuals(player_idx: int):
	if player_idx < 0 or player_idx >= 4: return
	var hand_data = GameManager.players_info[player_idx].hand
	var current_nodes = player_hands[player_idx]

	# STRICT SYNC: Reconstruct player_hands[player_idx] to match hand_data exactly by index.
	# In multiplayer, every sync creates new CardData objects so reference equality fails.
	# We fall back to rank+suit value matching so existing nodes are reused across syncs,
	# preserving their visual state (is_being_peeked, is_flipping, animation progress).
	var new_node_list = []
	var pool = current_nodes.duplicate()
	
	for data in hand_data:
		var found_node = null
		for node in pool:
			if not is_instance_valid(node):
				continue
			# Primary: reference match (singleplayer / host)
			if node.data == data:
				found_node = node
				pool.erase(node)
				break
			# Fallback: value match by rank+suit (multiplayer client — data is rebuilt each sync)
			if node.data != null and node.data.rank == data.rank and node.data.suit == data.suit:
				found_node = node
				# Update the node's data reference so future reference checks work
				node.data = data
				pool.erase(node)
				break
		
		if found_node:
			new_node_list.append(found_node)
		else:
			# Check if we can reuse the pending card
			if is_instance_valid(pending_card) and (
				pending_card.data == data or 
				(pending_card.data != null and pending_card.data.rank == data.rank and pending_card.data.suit == data.suit)
			):
				var card_node = pending_card
				var start_global_pos = card_node.global_position
				var start_global_rot = card_node.global_rotation
				
				card_node.reparent(player_pos_nodes[player_idx], true)
				card_node.global_position = start_global_pos
				card_node.global_rotation = start_global_rot
				
				# Ensure it is set to face-down in the hand (drawn card is face down in hand)
				# unless easy mode is enabled
				var should_be_face_up = GameManager.easy_mode and (player_idx == _human_ui_idx())
				card_node.data.is_face_up = should_be_face_up
				
				card_node.set_interactive(false)
				card_node.set_meta("is_swapping_in", true)
				new_node_list.append(card_node)
				pending_card = null # Consume it!
			else:
				var card_node = card_scene.instantiate()
				player_pos_nodes[player_idx].add_child(card_node)
				card_node.card_clicked.connect(_on_card_clicked)
				new_node_list.append(card_node)
		
	# Cleanup orphans — spare nodes that are mid-animation (discarding or being peeked)
	for node in pool:
		if is_instance_valid(node):
			if node.is_discarding or node.is_being_peeked:
				print("GameBoard3D: Sparing node from cleanup (is_discarding/is_being_peeked)")
				continue
			node.queue_free()
			
	player_hands[player_idx] = new_node_list
	var nodes = new_node_list
	# REFINED HAND LAYOUT: Aggressive bundling and conditional spreading
	var total_cards = nodes.size()
	const BASE_SPACING = 1.05 # Near-touching spacing
	const MAX_HAND_WIDTH = 4.2 # (5-1) * 1.05 = center-to-center distance for 5 cards
	
	# If > 5 cards, compress spacing so they fit in the same 5-card width
	var spacing = BASE_SPACING
	if total_cards > 5:
		spacing = MAX_HAND_WIDTH / (total_cards - 1)
	
	var hovered_idx = nodes.find(_hovered_card_node)
	var spread_amount = 0.0
	# Only spread if bundled (>5) and actually hovered
	if total_cards > 5 and hovered_idx != -1:
		# Shift neighbors just enough to touch but not overlap the hovered card
		spread_amount = (BASE_SPACING - spacing) 
	
	for i in range(total_cards):
		var card_node = nodes[i]
		if is_instance_valid(card_node):
			# Ensure connections
			if not card_node.get_meta("hover_connected", false):
				var area = card_node.get_node_or_null("Area3D")
				if area:
					area.mouse_entered.connect(_on_card_hover_enter.bind(card_node))
					area.mouse_exited.connect(_on_card_hover_exit.bind(card_node))
					card_node.set_meta("hover_connected", true)
			
			# Don't call setup() while the card is mid-peek or mid-flip:
			# setup() reads CardData.is_face_up which is always false for private hand cards,
			# and would instantly snap the card back down, cancelling the peek animation.
			if not card_node.is_being_peeked and not card_node.is_flipping:
				card_node.setup(hand_data[i])
			
			# CALCULATE POSITION with spread logic
			var offset_x = (i - (total_cards - 1) / 2.0) * spacing
			if spread_amount > 0:
				if i < hovered_idx:
					offset_x -= spread_amount
				elif i > hovered_idx:
					offset_x += spread_amount
					
			# Vertical stacking (Y) based on index to ensure correct visual layering
			# Slightly higher Y step (0.01) to prevent Z-fighting in tight spots
			var target_pos = Vector3(offset_x, 0.05 + i * 0.01, 0)
			
			# Skip if mid-flip or already there (performance)
			if card_node.is_being_peeked or (card_node.is_flipping and not card_node.has_meta("is_swapping_in")): continue
			
			# Special handling for hovered card Y (lift is handled locally in Card3D)
			if card_node == _hovered_card_node:
				pass 
			
			var target_rot_y = 180.0 if (player_idx == 0 or player_idx == 2) else 0.0
			var target_basis = Basis.from_euler(Vector3(deg_to_rad(90), deg_to_rad(target_rot_y), 0))
			var target_quat = target_basis.get_rotation_quaternion()
			
			var delay = 0.0
			var duration = 0.25
			if card_node.has_meta("is_swapping_in"):
				delay = 0.45 # Wait for the discard visual tween (0.4s) to complete first
				duration = 0.5 # Smooth travel speed
				card_node.remove_meta("is_swapping_in")
				
				# Call animate_flip after the delay so it flips as it moves
				var should_be_face_up = GameManager.easy_mode and (player_idx == _human_ui_idx())
				get_tree().create_timer(delay, false).timeout.connect(func():
					if is_instance_valid(card_node):
						card_node.animate_flip(should_be_face_up)
				)

			var pos_close: bool = card_node.position.distance_to(target_pos) <= 0.02
			var rot_close: bool = card_node.quaternion.dot(target_quat) >= 0.999
			if pos_close and rot_close and delay == 0.0:
				continue
			var tween = create_tween().set_parallel(true)
			tween.tween_property(card_node, "position", target_pos, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT).set_delay(delay)
			tween.tween_property(card_node, "quaternion", target_quat, duration).set_delay(delay)

func _handle_initial_deal():
	print("GameBoard3D: _handle_initial_deal started")
	_show_message("Dealing cards...")
	for i in range(4): # 4 cards each
		for p_idx in range(GameManager.num_players):
			var card_data = GameManager.deck_manager.draw_card()
			if card_data == null:
				break
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

	if GameManager.easy_mode:
		# Transition through INITIAL_PEEK (required by FSM), then skip it immediately.
		# Flip all local human cards face-up before the state completes.
		for card in player_hands[_human_ui_idx()]:
			if is_instance_valid(card):
				card.data.is_face_up = true
				card.animate_flip(true)
		GameManager.change_state(GameManager.GameState.INITIAL_PEEK)
		# Skip the peek immediately — bypasses the click-to-peek flow
		if GameManager.is_multiplayer:
			_send_action("initial_peek_done")
		else:
			GameManager.complete_initial_peek()
	else:
		GameManager.change_state(GameManager.GameState.INITIAL_PEEK)

func _start_peek_phase():
	print("GameBoard3D: _start_peek_phase started")
	peeked_cards.clear()
	_show_message("Select TWO cards to peek at.")
	# In 3D, we can highlight them by raising them slightly
	for c3d in player_pos_nodes[_human_ui_idx()].get_children():
		if c3d is Card3D:
			c3d.set_highlight(true)

var peeked_cards: Array = []
func _on_card_clicked(node, data):
	if not is_instance_valid(node): return
	
	var is_pending: bool = (node == pending_card or node.name == "PendingCard")
	var p_idx = -1
	for i in range(4):
		if node in player_hands[i]:
			p_idx = i
			break
	
	# DEBUG TRACING
	print("[CLICK DEBUG] Node: ", node.name, " | Data: ", data.rank, " of ", data.suit, " | IsPending: ", is_pending, " | PIdx: ", p_idx, " | State: ", GameManager.GameState.keys()[GameManager.current_state])
	
	if _is_waiting_for_target:
		if p_idx != -1:
			print("[BOARD DEBUG] Card-based targeting: delegating P", p_idx, " click to area input handler.")
			_on_player_area_input(null, null, Vector3.ZERO, Vector3.ZERO, 0, p_idx)
			return
		else:
			print("[BOARD DEBUG] Clicked something while waiting for target, but couldn't resolve player index.")
			
	# JUMP-IN SHORTCUT: If user clicks their card and can jump in, start it implicitly
	if p_idx == GameManager.local_player_idx and GameManager.can_player_start_jump_in(GameManager.local_player_idx) and GameManager.current_state != GameManager.GameState.TURN_JUMP_IN_SELECTION:
		print("[BOARD DEBUG] Implicit Jump-In started by card click.")
		_send_action("start_jump_in")
		# Flow now falls through to the TURN_JUMP_IN_SELECTION case below because start_jump_in updated the state.

	match GameManager.current_state:
		GameManager.GameState.INITIAL_PEEK:
			if node.get_parent() == player_pos_nodes[GameManager.local_player_idx] and not data.is_face_up:
				if peeked_cards.size() >= 2: return # Strict limit
				if node in peeked_cards: return
				node.is_being_peeked = true
				# Keep peek local-only; do not mutate authoritative CardData face-up state.
				node.animate_flip(true, -1.0, false)
				peeked_cards.append(node)
				if peeked_cards.size() >= 2:
					await get_tree().create_timer(2.0, false).timeout
					_clear_all_highlights()
					for c in peeked_cards:
						if is_instance_valid(c):
							c.is_being_peeked = false
							c.animate_flip(false, 0.05, false)
							c.set_interactive(false)
					peeked_cards.clear()
					if GameManager.is_multiplayer:
						_send_action("initial_peek_done")
					else:
						GameManager.complete_initial_peek()
		
		GameManager.GameState.TURN_RESOLVE_DRAWN:
			if p_idx == GameManager.local_player_idx:
				_send_action("swap_drawn", {"card_idx": player_hands[GameManager.local_player_idx].find(node)})
			elif is_pending:
				if GameManager.can_player_discard_drawn_card(GameManager.local_player_idx):
					_send_action("discard_drawn")
		
		GameManager.GameState.TURN_JUMP_IN_SELECTION:
			# Bug 2: Only allow selecting cards from the LOCAL player's own hand
			if not is_pending and p_idx != GameManager.local_player_idx:
				return
			var c_idx = -2 if is_pending else player_hands[GameManager.local_player_idx].find(node)
			if c_idx != -1 or is_pending:
				# VISUAL FEEDBACK: keep ONLY the clicked card highlighted while validating
				_clear_all_highlights()
				node.set_highlight(true)
				node.set_interactive(false) # Prevent clicking again during 'await'
				
				_send_action("validate_jump_in", {"card_idx": c_idx})
				print("[JUMP-IN] VALIDATION SENT")

		GameManager.GameState.TURN_PEEK_ABILITY:
			if is_pending or not GameManager.can_human_interact_with_hand_card(p_idx, -2 if is_pending else player_hands[p_idx].find(node), data.is_face_up):
				return
			_set_all_cards_interactive(false)
			node.is_being_peeked = true
			# Queen peek is temporary information; never replicate it via CardData.
			node.animate_flip(true, -1.0, false)
			await get_tree().create_timer(3.5, false).timeout
			_clear_all_highlights()
			node.is_being_peeked = false
			node.animate_flip(false, -1.0, false)
			_refresh_human_interactivity()
			_send_action("complete_peek_ability")

		GameManager.GameState.TURN_SWAP_ABILITY:
			var c_idx = -2 if is_pending else (player_hands[p_idx].find(node) if p_idx != -1 else -1)
			if is_pending or not GameManager.can_human_interact_with_hand_card(p_idx, c_idx, data.is_face_up):
				return
			if swap_sources.any(func(s): return s.node == node):
				return
			swap_sources.append({"node": node, "player": p_idx, "index": c_idx})
			if swap_sources.size() == 2:
				var s1 = swap_sources[0]
				var s2 = swap_sources[1]
				_send_action("complete_swap_ability", {"p1": s1.player, "c1": s1.index, "p2": s2.player, "c2": s2.index})
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
	if GameManager.can_player_draw(GameManager.local_player_idx):
		_send_action("draw_card")

func _on_discard_clicked():
	if GameManager.can_player_discard_drawn_card(GameManager.local_player_idx):
		_send_action("discard_drawn")

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
	var win_mode = Label.new()
	var mode_text = "Lowest Score Wins" if GameManager.win_condition_lowest_wins else "Highest Score Wins"
	win_mode.text = "(" + mode_text + ")"
	win_mode.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	win_mode.add_theme_font_size_override("font_size", 32)
	win_mode.modulate = Color(1.0, 0.8, 0.0) # Golden yellow
	vbox.add_child(win_mode)
	for i in range(results.size()):
		var entry = results[i]
		var l = Label.new()
		
		var score_text = str(entry.score) + " pts"
		if entry.is_eliminated:
			score_text = "Passed Out"
		elif entry.score == -1:
			score_text = "0 cards (WINNER)"
			
		l.text = "%d. %s: %s" % [i + 1, entry.name, score_text]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 32)
		if i == 0: l.add_theme_color_override("font_color", Color.YELLOW)
		vbox.add_child(l)

	var btn_h = HBoxContainer.new()
	btn_h.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_h)

	play_again_btn = Button.new()
	play_again_btn.text = "Play Again"
	play_again_btn.pressed.connect(func():
		if GameManager.is_multiplayer:
			play_again_btn.disabled = true
			play_again_btn.text = "Voted!"
			NetworkManager.vote_play_again.rpc()
		else:
			get_tree().reload_current_scene()
	)
	btn_h.add_child(play_again_btn)

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

	# --- GAME KEYBOARD CONTROLS ---
	# Priority Guard 2: Dev console is open — keys belong to the text input, not the game.
	if DevConsole and DevConsole.window.is_visible():
		return

	# Cabinet Drawer Interaction (intercept keypress if hovered)
	if _hovered_shelf_index != -1 and event.is_pressed() and not event.is_echo():
		if (event is InputEventKey and event.keycode == KEY_E) or event.is_action("game_call_dutch") or event.is_action("game_forfeit_dutch"):
			if is_instance_valid($Cabinet):
				$Cabinet.toggle_shelf(_hovered_shelf_index)
				_update_cabinet_prompt()
				get_viewport().set_input_as_handled()
				return

	# Priority Guard 1: Noclip is active — keys belong to the camera, not the game.
	if noclip_enabled:
		return

	if not (event is InputEventKey and event.pressed and not event.echo):
		return

	_handle_game_keyboard_input(event)

func _handle_game_keyboard_input(event: InputEvent) -> void:
	# Q — end turn OR confirm dutch (states are mutually exclusive)
	if event.is_action("game_end_turn") and end_turn_btn.visible and not end_turn_btn.disabled:
		_on_end_turn_pressed()
		get_viewport().set_input_as_handled()

	elif event.is_action("game_confirm_dutch") and confirm_dutch_btn.visible and not confirm_dutch_btn.disabled:
		_on_confirm_dutch_pressed()
		get_viewport().set_input_as_handled()

	# E — call dutch OR forfeit dutch (states are mutually exclusive)
	elif event.is_action("game_forfeit_dutch") and forfeit_dutch_btn.visible and not forfeit_dutch_btn.disabled:
		_on_cancel_dutch_pressed()
		get_viewport().set_input_as_handled()

	elif event.is_action("game_call_dutch") and call_dutch_btn.visible and not call_dutch_btn.disabled:
		_on_call_dutch_pressed()
		get_viewport().set_input_as_handled()

	elif event.is_action("game_jump_in") and jump_in_btn.visible and not jump_in_btn.disabled:
		_on_jump_in_pressed()
		get_viewport().set_input_as_handled()

	# DECK / DISCARD
	elif event.is_action("game_draw_card"):
		_on_deck_clicked()
		get_viewport().set_input_as_handled()

	elif event.is_action("game_discard_drawn"):
		_on_discard_clicked()
		get_viewport().set_input_as_handled()

	# CARD SELECTION (A / D)
	elif event.is_action("game_select_left"):
		_keyboard_navigate_hand(-1)
		get_viewport().set_input_as_handled()

	elif event.is_action("game_select_right"):
		_keyboard_navigate_hand(1)
		get_viewport().set_input_as_handled()

	# CONFIRM SELECTED CARD (Enter)
	elif event.is_action("game_confirm_card"):
		_keyboard_confirm_card()
		get_viewport().set_input_as_handled()

func _keyboard_navigate_hand(direction: int) -> void:
	var hand = player_hands[_human_ui_idx()]
	if hand.is_empty(): return

	# Deselect previous card (fire hover_exit to restore visual state)
	if _keyboard_selected_card_idx >= 0 and _keyboard_selected_card_idx < hand.size():
		var prev = hand[_keyboard_selected_card_idx]
		if is_instance_valid(prev):
			_on_card_hover_exit(prev)

	_keyboard_selected_card_idx = wrapi(
		_keyboard_selected_card_idx + direction,
		0, hand.size()
	)

	var card = hand[_keyboard_selected_card_idx]
	if is_instance_valid(card):
		_on_card_hover_enter(card)

func _keyboard_confirm_card() -> void:
	if _keyboard_selected_card_idx < 0: return
	var hand = player_hands[_human_ui_idx()]
	if _keyboard_selected_card_idx >= hand.size(): return
	var card = hand[_keyboard_selected_card_idx]
	if is_instance_valid(card) and card.data != null:
		_on_card_clicked(card, card.data)
		# Deselect after confirm
		_keyboard_selected_card_idx = -1

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
		# Bug 1: Mark as being peeked so _update_visuals() and _process() don't snap it back
		card_node.is_being_peeked = true
		# Flip UP with barrel roll
		card_node.animate_flip(true)
		
		# Wait for reveal duration
		await get_tree().create_timer(1.5, false).timeout
		
		# Release peek lock before flipping back
		card_node.is_being_peeked = false
		# Flip BACK — but not in Easy Mode for the human player (cards stay visible)
		if not (GameManager.easy_mode and player_idx == _human_ui_idx()):
			card_node.animate_flip(false)
		
		trigger_glitch(0.3, 0.4)
		shake(0.2, 0.3)


func _on_bot_action(message):
	_show_message(message)

func _process(delta: float) -> void:
	if Engine.is_editor_hint(): return
	
	_update_cabinet_hover()
	_update_action_buttons_state()
	
	if is_instance_valid(draw_arrow) and draw_arrow.visible:
		draw_arrow.position.y = 1.2 + sin(Time.get_ticks_msec() * 0.005) * 0.15
	
	if _shake_timer > 0:
		_shake_timer -= delta
		var offset = Vector3(
			randf_range(-1, 1) * _shake_intensity,
			randf_range(-1, 1) * _shake_intensity,
			0
		)
		camera.position = _effective_camera_base_local() + offset
		if _shake_timer <= 0:
			camera.position = _effective_camera_base_local()

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

func _update_cabinet_hover() -> void:
	if not is_instance_valid(camera):
		return
	
	var ray_origin := Vector3.ZERO
	var ray_normal := Vector3.ZERO
	
	if noclip_enabled:
		var viewport_size := get_viewport().get_visible_rect().size
		var center := viewport_size / 2.0
		ray_origin = camera.project_ray_origin(center)
		ray_normal = camera.project_ray_normal(center)
	else:
		var mouse_pos := get_viewport().get_mouse_position()
		ray_origin = camera.project_ray_origin(mouse_pos)
		ray_normal = camera.project_ray_normal(mouse_pos)
	
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_normal * 100.0)
	query.collision_mask = 8 # Layer 4 only
	query.collide_with_areas = true
	query.collide_with_bodies = false
	
	var result := space_state.intersect_ray(query)
	var new_hover_idx := -1
	
	if result and result.collider:
		var collider = result.collider
		if collider.has_meta("shelf_index"):
			new_hover_idx = collider.get_meta("shelf_index")
	
	if new_hover_idx != _hovered_shelf_index:
		_hovered_shelf_index = new_hover_idx
		_update_cabinet_prompt()

func _update_cabinet_prompt() -> void:
	if not is_instance_valid(_cabinet_prompt_label):
		return
		
	if _hovered_shelf_index == -1 or not is_instance_valid($Cabinet):
		_cabinet_prompt_label.hide()
		return
		
	var is_open = $Cabinet.is_shelf_open(_hovered_shelf_index)
	var shelf_name = $Cabinet.get_shelf_name(_hovered_shelf_index)
	var action_text = "Close" if is_open else "Open"
	_cabinet_prompt_label.text = "[E] %s %s" % [action_text, shelf_name]
	
	_cabinet_prompt_label.show()
	_cabinet_prompt_label.modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(_cabinet_prompt_label, "modulate:a", 1.0, 0.15)

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
	if Input.is_key_pressed(KEY_E) and _hovered_shelf_index == -1: move_dir += Vector3.UP
	if Input.is_key_pressed(KEY_Q): move_dir += Vector3.DOWN

	camera.global_position += move_dir.normalized() * 10.0 * delta

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

	if is_instance_valid(node1):
		spawn_particles("default", node1.global_position)
	if is_instance_valid(node2):
		spawn_particles("default", node2.global_position)

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
	_show_dutch_alert(player_name)
	spawn_particles("dutch", player_pos_nodes[player_idx].global_position)

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

func _on_polarity_shifted(new_state: bool):
	var msg = "POLARITY SHIFTED: LOWEST WINS!" if new_state else "POLARITY SHIFTED: HIGHEST WINS!"
	_show_message(msg)
	shake(0.5, 0.5)
	trigger_glitch(0.3, 1.2)
	print("UI: ", msg)

func _on_pending_card_consumed():
	if is_instance_valid(pending_card):
		print("GameBoard3D: Clearing pending card node.")
		pending_card.queue_free()
	pending_card = null

func _on_play_again_votes_updated(voted: int, total: int) -> void:
	if is_instance_valid(play_again_btn):
		play_again_btn.text = "Play Again (%d/%d)" % [voted, total]

func _show_dutch_alert(caller_name: String):
	var old_alert = $GameUI/MainHUD.get_node_or_null("DutchAlert")
	if old_alert:
		old_alert.queue_free()
		
	var center = CenterContainer.new()
	center.name = "DutchAlert"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$GameUI/MainHUD.add_child(center)
	
	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.0, 0.05, 0.85)
	style.border_width_left = 6
	style.border_width_right = 6
	style.border_width_top = 6
	style.border_width_bottom = 6
	style.border_color = Color(1.0, 0.0, 0.8)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.shadow_color = Color(1.0, 0.0, 0.8, 0.3)
	style.shadow_size = 20
	style.content_margin_left = 40
	style.content_margin_right = 40
	style.content_margin_top = 25
	style.content_margin_bottom = 25
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 5)
	panel.add_child(vbox)
	
	var alert_title = Label.new()
	alert_title.text = "⚠️ WARNING ⚠️"
	alert_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	alert_title.add_theme_font_size_override("font_size", 28)
	alert_title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.0))
	vbox.add_child(alert_title)
	
	var label = Label.new()
	label.text = caller_name.to_upper() + " CALLED DUTCH!"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 42)
	label.add_theme_color_override("font_color", Color(1.0, 0.0, 0.8))
	label.add_theme_color_override("font_shadow_color", Color(1.0, 0.0, 0.8, 0.5))
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 3)
	vbox.add_child(label)
	
	shake(0.4, 0.5)
	trigger_glitch(0.5, 0.6)
	
	center.scale = Vector2(0.5, 0.5)
	center.resized.connect(func():
		center.pivot_offset = center.size / 2.0
	)
	
	var tween = create_tween().set_parallel(true)
	tween.tween_property(center, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(center, "modulate:a", 1.0, 0.4).from(0.0)
	
	var fade_tween = create_tween()
	fade_tween.tween_interval(3.5)
	fade_tween.tween_property(center, "modulate:a", 0.0, 0.6)
	fade_tween.tween_callback(center.queue_free)

func spawn_particles(type: String, global_pos: Vector3):
	var particles = CPUParticles3D.new()
	add_child(particles)
	particles.global_position = global_pos
	
	particles.emitting = false
	particles.one_shot = true
	particles.explosiveness = 0.8
	
	var mesh = QuadMesh.new()
	mesh.size = Vector2(0.08, 0.08)
	particles.mesh = mesh
	
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	particles.material_override = mat
	
	var grad = Gradient.new()
	particles.color_ramp = grad
	
	match type:
		"card_flip":
			particles.amount = 25
			particles.lifetime = 0.4
			particles.spread = 180.0
			particles.gravity = Vector3(0, -1.0, 0)
			particles.initial_velocity_min = 1.5
			particles.initial_velocity_max = 3.0
			particles.color = Color(1.0, 0.85, 0.3) # Golden spark
			grad.set_color(0, Color(1.0, 0.9, 0.4, 1.0))
			grad.set_color(1, Color(1.0, 0.5, 0.0, 0.0))
			
		"beer_drink":
			particles.amount = 30
			particles.lifetime = 0.8
			particles.spread = 45.0
			particles.direction = Vector3.UP
			particles.gravity = Vector3(0, 0.5, 0)
			particles.initial_velocity_min = 0.5
			particles.initial_velocity_max = 1.5
			particles.color = Color(0.95, 0.95, 0.9, 0.9) # White foam
			grad.set_color(0, Color(0.95, 0.9, 0.7, 0.9))
			grad.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
			mesh.size = Vector2(0.12, 0.12)
			
		"ability_buy":
			particles.amount = 20
			particles.lifetime = 0.6
			particles.spread = 120.0
			particles.direction = Vector3.UP
			particles.gravity = Vector3(0, -3.0, 0) # Coins fall down
			particles.initial_velocity_min = 2.0
			particles.initial_velocity_max = 4.0
			particles.color = Color(1.0, 0.9, 0.0) # Gold coins
			grad.set_color(0, Color(1.0, 0.95, 0.2, 1.0))
			grad.set_color(1, Color(0.8, 0.5, 0.0, 0.0))
			
		"ability_use":
			particles.amount = 40
			particles.lifetime = 0.7
			particles.spread = 180.0
			particles.gravity = Vector3(0, -0.5, 0)
			particles.initial_velocity_min = 2.5
			particles.initial_velocity_max = 4.5
			particles.color = Color(0.6, 0.1, 1.0) # Violet magical glow
			grad.set_color(0, Color(0.7, 0.3, 1.0, 1.0))
			grad.set_color(1, Color(0.2, 0.0, 0.5, 0.0))
			mesh.size = Vector2(0.1, 0.1)
			
		"dutch":
			particles.amount = 35
			particles.lifetime = 0.8
			particles.spread = 180.0
			particles.gravity = Vector3(0, 0, 0)
			particles.initial_velocity_min = 3.0
			particles.initial_velocity_max = 6.0
			particles.color = Color(1.0, 0.1, 0.1) # Glowing red cyber-sparks
			grad.set_color(0, Color(1.0, 0.1, 0.2, 1.0))
			grad.set_color(1, Color(0.1, 0.0, 0.0, 0.0))
			mesh.size = Vector2(0.14, 0.14)
			
		_: # Default card trail spark
			particles.amount = 15
			particles.lifetime = 0.5
			particles.spread = 90.0
			particles.direction = Vector3.UP
			particles.gravity = Vector3(0, -0.8, 0)
			particles.initial_velocity_min = 1.0
			particles.initial_velocity_max = 2.0
			particles.color = Color(0.3, 0.8, 1.0) # Cyan-blue
			grad.set_color(0, Color(0.4, 0.9, 1.0, 1.0))
			grad.set_color(1, Color(0.0, 0.2, 0.5, 0.0))
			
	particles.emitting = true
	
	var cleanup_timer = get_tree().create_timer(particles.lifetime + 0.1)
	cleanup_timer.timeout.connect(particles.queue_free)

func _generate_bell_stream() -> AudioStreamWAV:
	var stream = AudioStreamWAV.new()
	stream.mix_rate = 44100
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.stereo = false
	
	var mix_rate = 44100.0
	var duration = 1.2
	var total_samples = int(mix_rate * duration)
	var byte_array = PackedByteArray()
	byte_array.resize(total_samples * 2) # 16-bit = 2 bytes per sample
	
	var f0 = 784.0 # G5 note frequency
	var harmonics = [
		{"freq": f0, "amp": 0.45, "decay": 2.5},
		{"freq": f0 * 1.5, "amp": 0.25, "decay": 4.0},
		{"freq": f0 * 2.0, "amp": 0.2, "decay": 5.0},
		{"freq": f0 * 2.63, "amp": 0.15, "decay": 6.5},
		{"freq": f0 * 3.0, "amp": 0.1, "decay": 8.0},
		{"freq": f0 * 4.0, "amp": 0.05, "decay": 10.0}
	]
	
	for s in range(total_samples):
		var t = s / mix_rate
		var sample = 0.0
		for h in harmonics:
			sample += h.amp * sin(2.0 * PI * h.freq * t) * exp(-h.decay * t)
		
		# Prevent clipping
		sample = clamp(sample, -1.0, 1.0)
		
		# Fade out at the very end
		if t > duration - 0.15:
			var fade = (duration - t) / 0.15
			sample *= fade
			
		var val = int(sample * 32767.0)
		byte_array.encode_s16(s * 2, val)
		
	stream.data = byte_array
	return stream

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
var _victory_fanfare_stream: AudioStreamWAV = null
var _victory_results_pending: Array = []
var _victory_cinematic_active: bool = false
var _victory_overlay_layer: CanvasLayer = null

const GAME_EMOTES := [
	{"id": "laugh", "label": "Laugh", "glyph": ":)", "color": Color(1.0, 0.92, 0.35)},
	{"id": "shock", "label": "Shock", "glyph": ":O", "color": Color(0.35, 0.9, 1.0)},
	{"id": "gg", "label": "GG", "glyph": "GG", "color": Color(0.45, 1.0, 0.55)},
	{"id": "chicken", "label": "Chicken", "glyph": "BOK", "color": Color(1.0, 0.65, 0.2)},
]
const EMOTE_WHEEL_ACCENT := Color(0.95, 0.78, 0.25)
const COLLISION_LAYER_CHICKEN := 32  # Layer 6 — separate from cards/deck so clicks are not blocked
const CHICKEN_HITBOX_RADIUS := 15.0  # Local units; ~0.75m at 0.05 model scale

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

# Initial peek phase (toggle: click to reveal, click again to hide)
const INITIAL_PEEK_MAX := 2
const INITIAL_PEEK_DEBUG := true
const CABINET_DEBUG := false
var _initial_peek_open: Array = [] # Card3D nodes currently face-up from peek
var _initial_peek_memorized: Array = [] # unique cards already peeked this phase

var _debug_reveal := false
var _debug_flipped_nodes: Array = []
var _cabinet_debug_nodes: Array[Node3D] = []
var card_scene = preload("res://card_3d.tscn")
var pause_menu_scene = preload("res://pause_menu.tscn")
var beer_scene = preload("res://assets/models/bere.glb")
var pause_menu_instance: Node = null
var _emote_wheel_panel: PanelContainer = null
var _emote_wheel_open: bool = false
var _emote_cooldown_label: Label = null
var _emote_buttons: Array[Button] = []
var _emote_toggle_btn: Button = null
var _emote_close_btn: Button = null
var _assistant_overlay: Control = null
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

enum BeerVisualState { FULL, HALF, EMPTY }

const BEER_LIQUID_FILL := {
	BeerVisualState.FULL: 1.0,
	BeerVisualState.HALF: 0.5,
	BeerVisualState.EMPTY: 0.04,
}

var player_beers_nodes: Array = [[], [], [], []]
var money_labels: Array = []
var _chicken_node: Node3D = null
var _chicken_area: Area3D = null
var _hovered_chicken: bool = false
var _hovered_shelf_index: int = -1
var _hovered_cabinet_node: Node = null
var _hovered_hammer_idx_board: int = -1
var _hovered_hammer_cabinet: Node = null
var _cabinets: Dictionary = {}
var _cabinet_prompt_label: Label = null
var _ability_desc_panel: PanelContainer = null
var _jack_swap_banner: Label = null
var _touch_hint_label: Label = null
var _touch_positions: Dictionary = {}
var _touch_tap_starts: Dictionary = {}
var _touch_look_active: bool = false
var player_avatars: Dictionary = {}
var avatar_arm_weights: Dictionary = {}
var _camera_initialized: bool = false
var _base_head_y: float = 0.0
const FP_EYE_HEIGHT_OFFSET: float = 2.10  # meters above hips anchor (raised from 1.85)
var _look_yaw: float = 0.0
var _look_pitch: float = 0.0

@onready var camera = $Camera3D
var _current_ability_message: String = ""
const DRAW_STATUS_HOLD_SEC := 2.8
var _status_message_hold_until_msec: int = 0
var _status_message_pending: String = ""
var _status_message_hide_pending: bool = false
var _shake_intensity: float = 0.0
var _shake_timer: float = 0.0
var _base_camera_pos: Vector3
var _base_camera_rotation: Vector3
## Extra shift on top of scene default camera position (e.g. multiplayer seat framing).
var _mp_camera_offset: Vector3 = Vector3.ZERO
var _mp_connection_label: Label = null
var _mp_status_poll_timer: float = 0.0
var _last_turn_player_idx: int = -1
var _turn_vfx_tween: Tween = null

# Targeting state
var _is_waiting_for_target: bool = false
var _is_preparing_ability: bool = false # Interaction guard for reveals
var _pending_ability: Dictionary = {} # {id, token, activator}
var _debug_overlay_visible: bool = false
var _debug_overlay_layer: CanvasLayer = null
var _debug_overlay_label: Label = null

var _last_sync_diag := {
	"state": -1,
	"cur": -1,
	"deck": -1,
	"discard": -1,
	"pending": false,
	"dutch_i": -1,
	"abilities": [[], [], [], []],
	"beers": [3, 3, 3, 3],
	"hand_sizes": [0, 0, 0, 0],
	"money": [0, 0, 0, 0]
}

func _ready():
	if Engine.is_editor_hint():
		_create_beer_placeholders()
		return

	player_hands = [[], [], [], []]

	# Map cabinet nodes to player indices dynamically
	_cabinets = {
		0: get_node_or_null("dulapu_la_proiect"),
		1: get_node_or_null("dulapu_la_proiect4"),
		2: get_node_or_null("dulapu_la_proiect3"),
		3: get_node_or_null("dulapu_la_proiect2")
	}
	for p_idx in _cabinets:
		var cab = _cabinets[p_idx]
		if is_instance_valid(cab):
			cab.set_meta("player_index", p_idx)
	_bell_stream = _generate_bell_stream()
	_victory_fanfare_stream = _generate_victory_fanfare_stream()
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
	GameManager.ability_finished.connect(_on_ability_finished)
	GameManager.polarity_shifted.connect(_on_polarity_shifted)
	GameManager.pending_card_consumed.connect(_on_pending_card_consumed)
	GameManager.multiplayer_sync_applied.connect(_on_multiplayer_sync_applied)
	GameManager.mp_connection_status_changed.connect(_on_mp_connection_status_changed)
	GameManager.player_emoted.connect(_on_player_emoted)
	NetworkManager.play_again_votes_updated.connect(_on_play_again_votes_updated)
	NetworkManager.server_disconnected.connect(_on_host_disconnected)
	
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
	_create_crosshair()
	$DeckArea/Area3D.input_event.connect(_on_deck_input_event)
	$DiscardArea/Area3D.input_event.connect(_on_discard_input_event)
	
	_apply_gameplay_mouse_mode()

	_spawn_player_avatars()
	_attach_cabinets_to_seats()

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

func _send_action(action: String, args: Dictionary = {}) -> bool:
	if GameManager.is_multiplayer:
		GameManager.request_action.rpc_id(1, action, args)
		return true
	if action == "play_ability":
		return GameManager.play_ability(
			_human_ui_idx(),
			str(args.get("ability_id", "")),
			int(args.get("target_idx", -1)),
			int(args.get("slot_idx", -1))
		)
	GameManager.request_action(action, args)
	return true

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
		if GameManager.is_multiplayer:
			# Table cam (not avatar FP): rotate with seat so the deck stays centered for every peer.
			camera.rotation.y = _base_camera_rotation.y + GameManager.local_player_idx * (TAU / 4.0)
			_look_yaw = 0.0
			_look_pitch = 0.0
		else:
			camera.rotation.y = _base_camera_rotation.y
		camera.position = _effective_camera_base_local()

func _attach_cabinets_to_seats() -> void:
	# World offsets from each chair: left of the seat, same depth as the player (not behind them).
	var chair_nodes := {
		0: get_node_or_null("Sketchfab_Scene"),
		1: get_node_or_null("Sketchfab_Scene4"),
		2: get_node_or_null("Sketchfab_Scene3"),
		3: get_node_or_null("Sketchfab_Scene2"),
	}
	const WORLD_OFFSETS := {
		0: Vector3(-3.2, 0.46, -0.82),
		1: Vector3(0.80, 0.46, -3.23),
		2: Vector3(3.09, 0.46, 1.58),
		3: Vector3(-0.85, 0.46, 3.23),
	}
	const LOCAL_SCALE := Vector3(0.11, 0.11, 0.11)

	for p_idx in _cabinets:
		var cab: Node3D = _cabinets[p_idx]
		var anchor: Node3D = chair_nodes.get(p_idx) as Node3D
		if not is_instance_valid(anchor):
			anchor = player_pos_nodes.get(p_idx)
		if not is_instance_valid(cab):
			push_warning("GameBoard3D: cabinet missing for P%d" % p_idx)
			continue
		if not is_instance_valid(anchor):
			continue
		if cab.get_parent() != anchor:
			cab.reparent(anchor)
		var world_offset: Vector3 = WORLD_OFFSETS.get(p_idx, Vector3.ZERO)
		cab.position = anchor.to_local(anchor.global_position + world_offset)
		cab.scale = LOCAL_SCALE
		# Drawer fronts face the seated player, not the table center.
		cab.look_at(anchor.global_position, Vector3.UP)
		cab.rotate_object_local(Vector3.UP, PI)
		cab.visible = true

	if CABINET_DEBUG:
		call_deferred("_debug_setup_cabinets")

func _debug_setup_cabinets() -> void:
	for n in _cabinet_debug_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_cabinet_debug_nodes.clear()

	var cam: Camera3D = $Camera3D
	var local_idx := _human_ui_idx()
	var marker_colors := {
		0: Color(0.1, 0.9, 1.0),
		1: Color(1.0, 0.25, 0.25),
		2: Color(0.25, 1.0, 0.35),
		3: Color(1.0, 0.85, 0.2),
	}

	print("========== CABINET DEBUG REPORT ==========")
	for p_idx in _cabinets:
		var cab: Node3D = _cabinets[p_idx]
		if not is_instance_valid(cab):
			print("[CABINET DEBUG] P%d MISSING" % p_idx)
			continue

		var parent_name: String = "null"
		var cab_parent: Node = cab.get_parent()
		if cab_parent != null:
			parent_name = cab_parent.name
		var mesh_count: int = _debug_count_meshes(cab)
		var shelves_ok: bool = false
		if cab.has_method("_resolve_shelves"):
			shelves_ok = cab._resolve_shelves().size() == 3

		var dist_to_cam: float = -1.0
		var blocks_view: bool = false
		if is_instance_valid(cam):
			dist_to_cam = cam.global_position.distance_to(cab.global_position)
			var to_cab: Vector3 = (cab.global_position - cam.global_position).normalized()
			var forward: Vector3 = -cam.global_transform.basis.z.normalized()
			blocks_view = to_cab.dot(forward) > 0.85

		print(
			"[CABINET DEBUG] P%d parent=%s visible=%s global_pos=%s global_scale=%s mesh_count=%d shelves_ok=%s dist_cam=%.2f blocks_view=%s local_player=%s"
			% [
				p_idx,
				parent_name,
				cab.visible,
				cab.global_position,
				cab.global_transform.basis.get_scale(),
				mesh_count,
				shelves_ok,
				dist_to_cam,
				blocks_view,
				p_idx == local_idx
			]
		)

		var marker := MeshInstance3D.new()
		marker.name = "CabinetDebugMarker_P%d" % p_idx
		var box := BoxMesh.new()
		box.size = Vector3(0.35, 0.55, 0.28)
		marker.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = marker_colors.get(p_idx, Color.MAGENTA)
		mat.emission_enabled = true
		mat.emission = marker_colors.get(p_idx, Color.MAGENTA)
		mat.emission_energy_multiplier = 2.5
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		marker.material_override = mat
		add_child(marker)
		marker.global_position = cab.global_position + Vector3(0.0, 0.45, 0.0)
		_cabinet_debug_nodes.append(marker)

		var label := Label3D.new()
		label.name = "CabinetDebugLabel_P%d" % p_idx
		label.text = "CAB P%d" % p_idx
		label.font_size = 48
		label.modulate = marker_colors.get(p_idx, Color.WHITE)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = Vector3(0.0, 0.55, 0.0)
		marker.add_child(label)
		_cabinet_debug_nodes.append(label)

	print("========== END CABINET DEBUG ==========")

func _debug_count_meshes(node: Node) -> int:
	var count := 0
	if node is MeshInstance3D and node.visible:
		count += 1
	for child in node.get_children():
		count += _debug_count_meshes(child)
	return count

func _configure_visible_player_seats(n: int) -> void:
	var visible_count := clampi(n, 1, 4)
	for seat in range(4):
		var is_active := seat < visible_count
		if player_pos_nodes.has(seat):
			player_pos_nodes[seat].visible = is_active
		# MP avatar visibility is owned by _refresh_avatar_body_visibility (local hidden, remotes shown).
		if not GameManager.is_multiplayer:
			if player_avatars.has(seat) and is_instance_valid(player_avatars[seat]):
				player_avatars[seat].visible = is_active
		var cab: Node3D = _cabinets.get(seat)
		if is_instance_valid(cab):
			cab.visible = is_active
	if GameManager.is_multiplayer:
		_refresh_avatar_body_visibility()

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
	_refresh_avatar_body_visibility()
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
		var prev_discard: int = int(_last_sync_diag["discard"])
		if new_discard > prev_discard \
				and GameManager.is_multiplayer \
				and not multiplayer.is_server() \
				and GameManager.deck_manager.discard_pile.size() > 0:
			# Server already got card_discarded; clients only see the sync diff.
			var top_card: CardData = GameManager.deck_manager.discard_pile.back()
			if top_card != null:
				var actor_idx: int = int(_last_sync_diag["cur"])
				_on_card_discarded(actor_idx, top_card)
			else:
				_update_discard_visual()
		else:
			_update_discard_visual()
	if GameManager.drawn_card_data != null \
			and GameManager.current_state == GameManager.GameState.TURN_RESOLVE_DRAWN \
			and pending_card == null:
		var actor_idx: int = GameManager.current_player_index
		var is_local_turn := actor_idx == GameManager.local_player_idx
		var d = GameManager.drawn_card_data
		pending_card = card_scene.instantiate()
		pending_card.name = "PendingCard"
		add_child(pending_card)
		d.is_face_up = false
		pending_card.setup(d)
		pending_card.card_clicked.connect(_on_card_clicked)
		pending_card.position = deck_area.position + Vector3(0, 0.6, 0.5)
		pending_card.rotation_degrees = Vector3(90, 0, 0)
		pending_card.scale = Vector3(1.5, 1.5, 1.5)
		pending_card.set_interactive(is_local_turn)
		if not is_local_turn and actor_idx >= 0 and actor_idx < GameManager.players_info.size():
			_show_message(GameManager.players_info[actor_idx].name + " is drawing...", DRAW_STATUS_HOLD_SEC)
		call_deferred("_reveal_synced_pending_card", is_local_turn)
	
	# --- Bug 5: Detect Dutch call and show feedback on client ---
	if new_dutch_i != -1 and _last_sync_diag["dutch_i"] == -1:
		_on_dutch_called(new_dutch_i)
	
	# --- Money juice on MP clients (server already gets player_gained_money) ---
	var prev_money: Array = _last_sync_diag.get("money", [0, 0, 0, 0])
	for pi in range(GameManager.num_players):
		var cur_money: int = GameManager.players_info[pi].money
		var old_money: int = int(prev_money[pi]) if pi < prev_money.size() else 0
		if cur_money > old_money:
			var gained: int = cur_money - old_money
			var is_kod := _is_king_of_diamonds_on_discard_pile()
			_show_money_juice_popup(pi, gained, is_kod)

	# --- Bug 3: Refresh local player money label from synced data ---
	var local_idx := GameManager.local_player_idx
	if local_idx >= 0 and local_idx < GameManager.players_info.size():
		if money_labels.size() > 0:
			money_labels[0].text = "$" + str(GameManager.players_info[local_idx].money)
	
	# --- Synchronize beers: drink / refill animations on all peers ---
	var prev_beers: Array = _last_sync_diag.get("beers", [3, 3, 3, 3])
	for pi in range(GameManager.num_players):
		var cur_beers = GameManager.players_info[pi].beers
		var old_b = prev_beers[pi] if pi < prev_beers.size() else 3
		if old_b != -1 and cur_beers < old_b:
			_on_player_drank_beer(pi, cur_beers)
		elif old_b != -1 and cur_beers > old_b:
			var beers_array = player_beers_nodes[pi] if pi < player_beers_nodes.size() else []
			_animate_beer_refill(beers_array, cur_beers)
		else:
			_sync_beer_visuals(pi, cur_beers)

	# --- Penalty/jump-in hand growth: force relayout on clients ---
	var prev_hand_sizes: Array = _last_sync_diag.get("hand_sizes", [0, 0, 0, 0])
	for pi in range(GameManager.num_players):
		var new_size: int = GameManager.players_info[pi].hand.size()
		var old_size: int = prev_hand_sizes[pi] if pi < prev_hand_sizes.size() else 0
		if new_size > old_size and old_size > 0:
			_schedule_hand_relayout(pi)
	
	# --- Bug 4: Detect ability changes and fire local visual feedback ---
	# Only diff if we have a prior snapshot (skip the very first sync to avoid spurious events)
	if not prev_abilities.is_empty() and prev_abilities.any(func(a): return a is Array):
		for pi in range(GameManager.num_players):
			var new_abs: Array = GameManager.players_info[pi].abilities
			var old_abs: Array = prev_abilities[pi] if pi < prev_abilities.size() else []
			
			var new_filtered = new_abs.filter(func(a): return a != "")
			var old_filtered = old_abs.filter(func(a): return a != "")
			
			# Ability appeared in the new list — player gained it
			for ab in new_filtered:
				if not ab in old_filtered:
					_on_ability_unlocked(pi, ab)
			# Ability disappeared from the list — player used it
			for ab in old_filtered:
				if not ab in new_filtered:
					var target_idx := -1
					var evt = GameManager.last_ability_event
					if evt.get("caster") == pi and evt.get("id") == ab:
						target_idx = int(evt.get("target", -1))
					_on_ability_played(pi, ab, target_idx)
	
	# Sync all player cabinets with their actual abilities
	for pi in range(GameManager.num_players):
		_update_ability_visuals(pi)
	
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
	var hand_sizes_snapshot: Array = []
	for pi in range(4):
		if pi < GameManager.players_info.size():
			hand_sizes_snapshot.append(GameManager.players_info[pi].hand.size())
		else:
			hand_sizes_snapshot.append(0)
	_last_sync_diag["hand_sizes"] = hand_sizes_snapshot
	var money_snapshot: Array = []
	for pi in range(4):
		if pi < GameManager.players_info.size():
			money_snapshot.append(GameManager.players_info[pi].money)
		else:
			money_snapshot.append(0)
	_last_sync_diag["money"] = money_snapshot
	_update_draw_arrow_visibility()

func _create_hud_ui():
	# Action Panel: Style Box Flat with 20% opacity dark background, rounded corners and subtle border
	action_panel = PanelContainer.new()
	action_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	action_panel.offset_left = 20
	action_panel.offset_top = -240
	action_panel.offset_bottom = -20
	action_panel.offset_right = 320
	action_panel.grow_horizontal = Control.GROW_DIRECTION_END
	action_panel.custom_minimum_size = Vector2(300, 200)
	action_panel.mouse_filter = Control.MOUSE_FILTER_STOP

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
	panel_style.content_margin_left = 15
	panel_style.content_margin_right = 15
	panel_style.content_margin_top = 15
	panel_style.content_margin_bottom = 15
	
	action_panel.add_theme_stylebox_override("panel", panel_style)
	$GameUI/MainHUD.add_child(action_panel)

	# Action Buttons Container: Nested inside the Action Panel
	var action_container = VBoxContainer.new()
	action_container.alignment = BoxContainer.ALIGNMENT_BEGIN
	action_container.add_theme_constant_override("separation", 12)
	action_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_container.size_flags_vertical = Control.SIZE_SHRINK_END
	action_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	action_panel.add_child(action_container)

	# Standard HUD buttons — labels are dynamically populated from InputMap keybinds
	end_turn_btn = _create_button(action_container, "", Color(0.0, 1.0, 1.0))
	jump_in_btn = _create_button(action_container, "", Color(0.0, 1.0, 1.0))
	call_dutch_btn = _create_button(action_container, "", Color(1.0, 0.0, 0.8))
	confirm_dutch_btn = _create_button(action_container, "", Color(0.0, 1.0, 1.0))
	forfeit_dutch_btn = _create_button(action_container, "", Color(1.0, 0.0, 0.8))
	end_turn_btn.pressed.connect(_on_end_turn_pressed)
	jump_in_btn.pressed.connect(_on_jump_in_pressed)
	call_dutch_btn.pressed.connect(_on_call_dutch_pressed)
	confirm_dutch_btn.pressed.connect(_on_confirm_dutch_pressed)
	forfeit_dutch_btn.pressed.connect(_on_cancel_dutch_pressed)
	_update_action_button_labels()
	_setup_debug_overlay()
	
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

	_mp_connection_label = Label.new()
	_mp_connection_label.name = "MpConnectionLabel"
	_mp_connection_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_mp_connection_label.offset_left = -280.0
	_mp_connection_label.offset_top = 20.0
	_mp_connection_label.offset_right = -20.0
	_mp_connection_label.offset_bottom = 56.0
	_mp_connection_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_mp_connection_label.add_theme_font_size_override("font_size", 18)
	_mp_connection_label.visible = false
	$GameUI/MainHUD.add_child(_mp_connection_label)
	if GameManager.is_multiplayer:
		_mp_connection_label.visible = true
		_update_mp_connection_label(GameManager.mp_sync_lag_ms, GameManager.mp_connection_status)

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

	# Cabinet Ability Description HUD (Bottom-Right corner)
	_ability_desc_panel = PanelContainer.new()
	_ability_desc_panel.name = "AbilityDescPanel"
	_ability_desc_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_ability_desc_panel.offset_left = -350
	_ability_desc_panel.offset_right = -20
	_ability_desc_panel.offset_top = -180
	_ability_desc_panel.offset_bottom = -20
	_ability_desc_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var desc_style = StyleBoxFlat.new()
	desc_style.bg_color = Color(0.04, 0.04, 0.06, 0.75)
	desc_style.border_width_left = 2
	desc_style.border_width_right = 2
	desc_style.border_width_top = 2
	desc_style.border_width_bottom = 2
	desc_style.border_color = Color(1.0, 0.75, 0.1, 0.6)
	desc_style.corner_radius_top_left = 8
	desc_style.corner_radius_top_right = 8
	desc_style.corner_radius_bottom_left = 8
	desc_style.corner_radius_bottom_right = 8
	desc_style.content_margin_left = 12
	desc_style.content_margin_right = 12
	desc_style.content_margin_top = 12
	desc_style.content_margin_bottom = 12
	
	_ability_desc_panel.add_theme_stylebox_override("panel", desc_style)
	$GameUI/MainHUD.add_child(_ability_desc_panel)
	
	var desc_label = Label.new()
	desc_label.name = "DescLabel"
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.add_theme_font_size_override("font_size", 18)
	desc_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95))
	_ability_desc_panel.add_child(desc_label)
	_ability_desc_panel.hide()

	_create_emote_wheel_ui()
	_create_assistant_ui()
	_create_touch_hint()
	_apply_responsive_hud_layout()
	if not get_viewport().size_changed.is_connected(_apply_responsive_hud_layout):
		get_viewport().size_changed.connect(_apply_responsive_hud_layout)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_SIZE_CHANGED:
		call_deferred("_apply_responsive_hud_layout")

func _create_touch_hint() -> void:
	if not ResponsiveUI.is_touch_device():
		return
	_touch_hint_label = Label.new()
	_touch_hint_label.name = "TouchHint"
	_touch_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_touch_hint_label.add_theme_font_size_override("font_size", ResponsiveUI.scaled_font(16))
	_touch_hint_label.add_theme_color_override("font_color", Color(0.72, 0.95, 1.0))
	_touch_hint_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.75))
	_touch_hint_label.text = "1 finger: tap to play  |  2 fingers: drag to look around"
	_touch_hint_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_touch_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$GameUI/MainHUD.add_child(_touch_hint_label)

func _apply_responsive_hud_layout() -> void:
	var scale := ResponsiveUI.get_ui_scale()
	var margin := ResponsiveUI.get_margin()
	var vp := get_viewport().get_visible_rect().size

	var top_left := $GameUI/MainHUD/TopLeft
	top_left.offset_left = margin
	top_left.offset_top = margin
	top_left.offset_right = margin + 280.0 * scale

	if is_instance_valid(turn_label):
		turn_label.add_theme_font_size_override("font_size", ResponsiveUI.scaled_font(32))
	for ml in money_labels:
		if is_instance_valid(ml):
			ml.add_theme_font_size_override("font_size", ResponsiveUI.scaled_font(24))

	if is_instance_valid(action_panel):
		var panel_h := 200.0 * scale
		action_panel.offset_left = margin
		action_panel.offset_bottom = -margin
		action_panel.offset_top = -margin - panel_h
		action_panel.offset_right = margin + 300.0 * scale
		action_panel.custom_minimum_size = Vector2(260.0 * scale, panel_h)

	if is_instance_valid(_mp_connection_label):
		_mp_connection_label.offset_left = -280.0 * scale
		_mp_connection_label.offset_top = margin
		_mp_connection_label.offset_right = -margin
		_mp_connection_label.add_theme_font_size_override("font_size", ResponsiveUI.scaled_font(18))

	if is_instance_valid(_cabinet_prompt_label):
		var half_w := minf(vp.x * 0.42, 360.0 * scale)
		_cabinet_prompt_label.offset_left = -half_w
		_cabinet_prompt_label.offset_right = half_w
		_cabinet_prompt_label.offset_top = -110.0 * scale
		_cabinet_prompt_label.offset_bottom = -50.0 * scale
		_cabinet_prompt_label.add_theme_font_size_override("font_size", ResponsiveUI.scaled_font(28))

	if is_instance_valid(_ability_desc_panel):
		var desc_w := 330.0 * scale
		_ability_desc_panel.offset_left = -desc_w - margin
		_ability_desc_panel.offset_right = -margin
		_ability_desc_panel.offset_top = -180.0 * scale
		_ability_desc_panel.offset_bottom = -margin
		var desc_label := _ability_desc_panel.get_node_or_null("DescLabel")
		if desc_label:
			desc_label.add_theme_font_size_override("font_size", ResponsiveUI.scaled_font(18))

	var emote_btn_w := 150.0 * scale
	var emote_btn_h := 48.0 * scale
	if is_instance_valid(_emote_toggle_btn):
		_emote_toggle_btn.offset_left = -emote_btn_w - margin
		_emote_toggle_btn.offset_right = -margin
		_emote_toggle_btn.offset_top = -emote_btn_h - margin
		_emote_toggle_btn.offset_bottom = -margin
		_emote_toggle_btn.add_theme_font_size_override("font_size", ResponsiveUI.scaled_font(18))
		_emote_toggle_btn.custom_minimum_size = Vector2(emote_btn_w, emote_btn_h)
	# The permanent "?" button sits between EMOTE and the emote wheel, so the
	# wheel opens above both. Keep this in sync with assistant_overlay.apply_layout.
	var help_btn_h := 40.0 * scale
	if is_instance_valid(_emote_wheel_panel):
		var wheel_w := 268.0 * scale
		var wheel_h := 268.0 * scale
		_emote_wheel_panel.offset_left = -wheel_w - margin
		_emote_wheel_panel.offset_right = -margin
		_emote_wheel_panel.offset_bottom = -emote_btn_h - help_btn_h - margin * 3.0
		_emote_wheel_panel.offset_top = _emote_wheel_panel.offset_bottom - wheel_h
	if is_instance_valid(_assistant_overlay):
		_assistant_overlay.apply_layout(scale, margin, emote_btn_h)

	if is_instance_valid(_jack_swap_banner):
		_jack_swap_banner.offset_top = 100.0 * scale
		_jack_swap_banner.add_theme_font_size_override("font_size", ResponsiveUI.scaled_font(26))

	if is_instance_valid(_touch_hint_label):
		_touch_hint_label.offset_top = -36.0 * scale
		_touch_hint_label.offset_bottom = -8.0 * scale
		_touch_hint_label.offset_left = -vp.x * 0.45
		_touch_hint_label.offset_right = vp.x * 0.45
		_touch_hint_label.add_theme_font_size_override("font_size", ResponsiveUI.scaled_font(16))

	for btn in [end_turn_btn, jump_in_btn, call_dutch_btn, confirm_dutch_btn, forfeit_dutch_btn]:
		if is_instance_valid(btn):
			btn.custom_minimum_size = Vector2(260.0 * scale, 45.0 * scale)
			btn.add_theme_font_size_override("font_size", ResponsiveUI.scaled_font(22))

	if is_instance_valid(top_center):
		top_center.offset_top = 72.0 * scale
		top_center.offset_left = -vp.x * 0.45
		top_center.offset_right = vp.x * 0.45

func _create_emote_toggle_button() -> void:
	_emote_toggle_btn = Button.new()
	_emote_toggle_btn.name = "EmoteToggleButton"
	_emote_toggle_btn.text = "EMOTE [T]"
	_emote_toggle_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_emote_toggle_btn.offset_left = -170.0
	_emote_toggle_btn.offset_top = -68.0
	_emote_toggle_btn.offset_right = -20.0
	_emote_toggle_btn.offset_bottom = -20.0
	_emote_toggle_btn.custom_minimum_size = Vector2(150, 48)
	_emote_toggle_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_emote_toggle_btn.add_theme_font_size_override("font_size", 18)
	_emote_toggle_btn.add_theme_color_override("font_color", EMOTE_WHEEL_ACCENT)
	_emote_toggle_btn.add_theme_color_override("font_hover_color", Color.WHITE)
	_emote_toggle_btn.add_theme_color_override("font_pressed_color", EMOTE_WHEEL_ACCENT.lightened(0.25))

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.05, 0.06, 0.1, 0.85)
	normal.border_width_left = 2
	normal.border_width_right = 2
	normal.border_width_top = 2
	normal.border_width_bottom = 2
	normal.border_color = Color(EMOTE_WHEEL_ACCENT.r, EMOTE_WHEEL_ACCENT.g, EMOTE_WHEEL_ACCENT.b, 0.7)
	normal.corner_radius_top_left = 10
	normal.corner_radius_top_right = 10
	normal.corner_radius_bottom_left = 10
	normal.corner_radius_bottom_right = 10
	normal.shadow_color = Color(0, 0, 0, 0.45)
	normal.shadow_size = 6

	var hover := normal.duplicate()
	hover.bg_color = Color(0.12, 0.1, 0.04, 0.95)
	hover.border_color = EMOTE_WHEEL_ACCENT

	var pressed := hover.duplicate()
	pressed.bg_color = Color(0.2, 0.16, 0.04, 0.95)

	var disabled := normal.duplicate()
	disabled.bg_color = Color(0.05, 0.06, 0.1, 0.45)
	disabled.border_color = Color(EMOTE_WHEEL_ACCENT.r, EMOTE_WHEEL_ACCENT.g, EMOTE_WHEEL_ACCENT.b, 0.2)

	_emote_toggle_btn.add_theme_stylebox_override("normal", normal)
	_emote_toggle_btn.add_theme_stylebox_override("hover", hover)
	_emote_toggle_btn.add_theme_stylebox_override("pressed", pressed)
	_emote_toggle_btn.add_theme_stylebox_override("disabled", disabled)

	_emote_toggle_btn.pressed.connect(_toggle_emote_wheel)
	$GameUI/MainHUD.add_child(_emote_toggle_btn)

func _create_assistant_ui() -> void:
	var overlay_script := preload("res://assistant_overlay.gd")
	_assistant_overlay = overlay_script.new()
	_assistant_overlay.name = "AssistantOverlay"
	$GameUI/MainHUD.add_child(_assistant_overlay)
	_assistant_overlay.opened.connect(_close_emote_wheel)

func _create_emote_wheel_ui() -> void:
	_create_emote_toggle_button()
	_emote_wheel_panel = PanelContainer.new()
	_emote_wheel_panel.name = "EmoteWheel"
	_emote_wheel_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_emote_wheel_panel.offset_left = -268.0
	_emote_wheel_panel.offset_top = -258.0
	_emote_wheel_panel.offset_right = -20.0
	_emote_wheel_panel.offset_bottom = -20.0
	_emote_wheel_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_emote_wheel_panel.visible = false

	var wheel_style := StyleBoxFlat.new()
	wheel_style.bg_color = Color(0.03, 0.04, 0.07, 0.9)
	wheel_style.border_width_left = 1
	wheel_style.border_width_right = 1
	wheel_style.border_width_top = 1
	wheel_style.border_width_bottom = 1
	wheel_style.border_color = Color(EMOTE_WHEEL_ACCENT.r, EMOTE_WHEEL_ACCENT.g, EMOTE_WHEEL_ACCENT.b, 0.45)
	wheel_style.corner_radius_top_left = 14
	wheel_style.corner_radius_top_right = 14
	wheel_style.corner_radius_bottom_left = 14
	wheel_style.corner_radius_bottom_right = 14
	wheel_style.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
	wheel_style.shadow_size = 6
	wheel_style.content_margin_left = 14
	wheel_style.content_margin_right = 14
	wheel_style.content_margin_top = 12
	wheel_style.content_margin_bottom = 10
	_emote_wheel_panel.add_theme_stylebox_override("panel", wheel_style)
	$GameUI/MainHUD.add_child(_emote_wheel_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_emote_wheel_panel.add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	vbox.add_child(header)

	var title := Label.new()
	title.text = "> EMOTES <"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", EMOTE_WHEEL_ACCENT)
	title.add_theme_color_override("font_shadow_color", Color(EMOTE_WHEEL_ACCENT.r, EMOTE_WHEEL_ACCENT.g, EMOTE_WHEEL_ACCENT.b, 0.25))
	title.add_theme_constant_override("shadow_offset_y", 1)
	header.add_child(title)

	_emote_close_btn = Button.new()
	_emote_close_btn.text = "X"
	_emote_close_btn.custom_minimum_size = Vector2(28, 28)
	_emote_close_btn.add_theme_font_size_override("font_size", 14)
	_emote_close_btn.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))
	_emote_close_btn.add_theme_color_override("font_hover_color", Color.WHITE)
	var close_normal := StyleBoxFlat.new()
	close_normal.bg_color = Color(0.18, 0.05, 0.06, 0.65)
	close_normal.border_width_left = 1
	close_normal.border_width_right = 1
	close_normal.border_width_top = 1
	close_normal.border_width_bottom = 1
	close_normal.border_color = Color(1.0, 0.3, 0.4, 0.6)
	close_normal.corner_radius_top_left = 6
	close_normal.corner_radius_top_right = 6
	close_normal.corner_radius_bottom_left = 6
	close_normal.corner_radius_bottom_right = 6
	var close_hover := close_normal.duplicate()
	close_hover.bg_color = Color(0.42, 0.08, 0.1, 0.85)
	close_hover.border_color = Color(1.0, 0.5, 0.55, 0.95)
	_emote_close_btn.add_theme_stylebox_override("normal", close_normal)
	_emote_close_btn.add_theme_stylebox_override("hover", close_hover)
	_emote_close_btn.add_theme_stylebox_override("pressed", close_hover)
	_emote_close_btn.pressed.connect(_close_emote_wheel)
	header.add_child(_emote_close_btn)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	vbox.add_child(grid)

	_emote_buttons.clear()
	for i in range(GAME_EMOTES.size()):
		var emote: Dictionary = GAME_EMOTES[i]
		var btn := _create_emote_tile_button(grid, emote, i + 1)
		btn.pressed.connect(_on_emote_wheel_pressed.bind(emote.id))
		_emote_buttons.append(btn)

	_emote_cooldown_label = Label.new()
	_emote_cooldown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_emote_cooldown_label.add_theme_font_size_override("font_size", 12)
	_emote_cooldown_label.add_theme_color_override("font_color", Color(0.62, 0.66, 0.72))
	_emote_cooldown_label.text = ""
	vbox.add_child(_emote_cooldown_label)

func _create_emote_tile_button(parent: Node, emote: Dictionary, key_num: int) -> Button:
	var accent: Color = emote.color
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(108, 74)
	btn.text = "[%d]\n%s\n%s" % [key_num, emote.glyph, emote.label]
	btn.add_theme_font_size_override("font_size", 15)
	btn.add_theme_color_override("font_color", accent.lightened(0.15))
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", accent)
	btn.add_theme_color_override("font_disabled_color", Color(accent.r, accent.g, accent.b, 0.35))

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(accent.r * 0.12, accent.g * 0.12, accent.b * 0.12, 0.55)
	normal.border_width_left = 1
	normal.border_width_right = 1
	normal.border_width_top = 1
	normal.border_width_bottom = 1
	normal.border_color = Color(accent.r, accent.g, accent.b, 0.55)
	normal.corner_radius_top_left = 10
	normal.corner_radius_top_right = 10
	normal.corner_radius_bottom_left = 10
	normal.corner_radius_bottom_right = 10
	normal.content_margin_left = 4
	normal.content_margin_right = 4
	normal.content_margin_top = 6
	normal.content_margin_bottom = 6

	var hover := normal.duplicate()
	hover.bg_color = Color(accent.r * 0.22, accent.g * 0.22, accent.b * 0.22, 0.75)
	hover.border_color = accent.lightened(0.2)

	var pressed := hover.duplicate()
	pressed.bg_color = Color(accent.r * 0.3, accent.g * 0.3, accent.b * 0.3, 0.85)

	var disabled := normal.duplicate()
	disabled.bg_color = Color(0.05, 0.05, 0.07, 0.35)
	disabled.border_color = Color(accent.r, accent.g, accent.b, 0.18)

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("disabled", disabled)
	parent.add_child(btn)
	return btn

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
	btn.add_theme_color_override("font_disabled_color", Color(color.r, color.g, color.b, 0.25))
	
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.clip_text = false
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	parent.add_child(btn)

	# Explicitly set mouse filter to STOP for the button so it can still be clicked,
	# but its PARENT (action_container) is IGNORE so clicks pass through the spacing.
	btn.mouse_filter = Control.MOUSE_FILTER_STOP

	btn.custom_minimum_size = Vector2(260, 45)
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
		card.scale = Vector3(1.5, 1.5, 1.5)
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
		card_node.scale = Vector3(1.5, 1.5, 1.5)
		card_node.set_interactive(false)
		if discard_indicator: discard_indicator.hide()
	else:
		if discard_indicator: discard_indicator.show()

func _create_discard_indicator():
	discard_indicator = MeshInstance3D.new()
	var mesh = PlaneMesh.new()
	mesh.size = Vector2(0.8, 1.1) * 1.5 # Scaled to match 1.5x card size
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
			beer.set_meta("base_scale", beer.scale)
			beer.set_meta("base_y", beer_y_offset)
			_apply_beer_visual_state(beer, BeerVisualState.FULL, false)
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
	chicken.position = Vector3(3.2, 0.58, -2.8)
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
	area.name = "ChickenArea3D"
	area.collision_layer = COLLISION_LAYER_CHICKEN
	area.collision_mask = 0
	var col = CollisionShape3D.new()
	var shape = SphereShape3D.new()
	shape.radius = CHICKEN_HITBOX_RADIUS
	col.shape = shape
	area.add_child(col)
	chicken.add_child(area)
	_chicken_area = area
	
	area.input_event.connect(_on_chicken_clicked)
	GameManager.ability_unlocked.connect(_on_ability_unlocked)

func _create_crosshair() -> void:
	var dot = PanelContainer.new()
	dot.name = "CrosshairDot"
	dot.set_anchors_preset(Control.PRESET_CENTER)
	dot.grow_horizontal = Control.GROW_DIRECTION_BOTH
	dot.grow_vertical = Control.GROW_DIRECTION_BOTH
	dot.custom_minimum_size = Vector2(6, 6)
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.4, 0.4, 0.4, 0.9) # more opaque gray
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	style.shadow_size = 0
	dot.add_theme_stylebox_override("panel", style)
	
	$GameUI/MainHUD.add_child(dot)

func _on_ability_unlocked(p_idx: int, ab: String):
	_drop_egg_for(p_idx, ab)

func _on_chicken_clicked(_camera, event, _position, _normal, _shape_idx):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if GameManager.current_player_index == GameManager.local_player_idx:
			_try_buy_ability(GameManager.local_player_idx)

func _try_buy_ability(p_idx: int):
	var active_abilities = GameManager.players_info[p_idx].abilities.filter(func(a): return a != "")
	if active_abilities.size() >= 6:
		_show_message("Inventory Full! (Max 6)")
		return
		
	_send_action("buy_ability")

func _drop_egg_for(p_idx: int, ab: String) -> void:
	var ab_name := _format_ability_name(ab)
	if p_idx == _human_ui_idx():
		_show_ability_purchase_alert(ab_name, ab)
	else:
		_show_message(GameManager.players_info[p_idx].name + " bought " + ab_name + "!")
	
	if is_instance_valid(_chicken_node):
		spawn_particles("ability_buy", _chicken_node.global_position + Vector3(0, 0.35, 0))
		var tween = create_tween()
		tween.tween_property(_chicken_node, "position:y", 1.38, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(_chicken_node, "position:y", 0.58, 0.2).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)

	# Spawn hammer in the player's cabinet
	print("BOARD: syncing ability hammers for P", p_idx)
	_update_ability_visuals(p_idx)
	var cab: Node3D = _cabinets.get(p_idx)
	if is_instance_valid(cab):
		spawn_particles("ability_buy", cab.global_position + Vector3(0, 0.55, 0))
		if p_idx == _human_ui_idx():
			_play_ability_purchase_flash()
	
func _update_ability_visuals(p_idx: int):
	# Abilities are now represented exclusively by hammers in the cabinet.
	# Use the authoritative GameManager abilities array as the source of truth.
	var cab = _cabinets.get(p_idx)
	if is_instance_valid(cab):
		var abilities = GameManager.players_info[p_idx].abilities
		cab.update_hammers(abilities, p_idx)
	
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

## Called when the player clicks on a hammer in their cabinet drawer.
func _use_hovered_hammer() -> void:
	if _hovered_hammer_idx_board < 0 or not is_instance_valid(_hovered_hammer_cabinet):
		return
	var p_idx := _human_ui_idx()
	# Only the current player may use abilities
	if p_idx != GameManager.current_player_index:
		_show_message("Not your turn to play abilities!")
		return
	if _is_preparing_ability or _is_waiting_for_target:
		return
	var h_idx: int = _hovered_hammer_idx_board
	var abilities: Array = GameManager.players_info[p_idx].abilities
	if h_idx < 0 or h_idx >= abilities.size():
		_show_message("Invalid ability slot!")
		return
	var ability_id: String = abilities[h_idx]
	if ability_id == "":
		return
	var targeting_abilities = ["bottoms_up", "boulder", "skip", "inflation", "half_off", "shuffle", "jumpscare"]
	if ability_id in targeting_abilities:
		print("BOARD: Hammer ability ", ability_id, " requires target selection.")
		_is_waiting_for_target = true
		_set_targeting_areas_enabled(true)
		_highlight_selectable_cards(true)
		_update_turn_lights(-1, true)
		_pending_ability = {
			"id": ability_id,
			"token": null,
			"activator": p_idx,
			"slot_idx": h_idx
		}
		_show_message("SELECT TARGET PLAYER (click their cards or zone)")
	else:
		if not _send_action("play_ability", {"ability_id": ability_id, "target_idx": p_idx, "slot_idx": h_idx}):
			_show_message("Cannot use ability right now!")
			return

## hammer_collider: the Area3D Area3D that was clicked (has "hammer_index" meta).
func _on_hammer_clicked(hammer_collider: Area3D) -> void:
	var owner_idx: int = hammer_collider.get_meta("player_index", -1)
	if owner_idx != _human_ui_idx():
		return
	var h_idx: int = hammer_collider.get_meta("hammer_index", -1)
	if h_idx >= 0:
		_hovered_hammer_idx_board = h_idx
		_hovered_hammer_cabinet = _cabinets.get(_human_ui_idx())
		_use_hovered_hammer()

func _create_player_targeting_areas():
	for i in range(4):

		var area = Area3D.new()
		area.name = "TargetArea"
		var col = CollisionShape3D.new()
		col.name = "CollisionShape3D"
		var shape = BoxShape3D.new()
		shape.size = Vector3(4.0, 1.0, 4.0) # Larger area
		col.shape = shape
		area.add_child(col)
		player_pos_nodes[i].add_child(area)
		# Position it slightly above table
		area.position = Vector3(0, 0.5, 0)
		
		# DEBUG FIX: non-pickable by default so we don't block cards
		area.input_ray_pickable = false
		col.disabled = true
		area.collision_layer = 1
		area.collision_mask = 1
		
		area.input_event.connect(_on_player_area_input.bind(i))
		area.set_meta("player_index", i)
		print("DEBUG: Created TargetArea for player ", i)

func _set_targeting_areas_enabled(enabled: bool):
	print("DEBUG: Setting targeting areas to: ", enabled)
	for i in range(4):
		var area = player_pos_nodes[i].find_child("TargetArea")
		if area:
			area.input_ray_pickable = enabled
			var col = area.find_child("CollisionShape3D")
			if col:
				col.disabled = !enabled
			print("  - Player ", i, " area pickable: ", area.input_ray_pickable, " shape disabled: ", col.disabled if col else "no shape")

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
		var slot_idx = _pending_ability.get("slot_idx", -1)

		print("[DEBUG] Requesting play_ability: ", ab_id, " by P", activator, " on P", player_idx, " from slot ", slot_idx)
		
		if not _send_action("play_ability", {"ability_id": ab_id, "target_idx": player_idx, "slot_idx": slot_idx}):
			_show_message("Cannot play ability right now!")
			return

		_clear_ability_targeting_state(true)
		_hide_message()
		_update_ability_visuals(activator)

func _clear_ability_targeting_state(restore_turn_lights: bool = true) -> void:
	if not _is_waiting_for_target and not _is_preparing_ability and _pending_ability.is_empty():
		return
	var activator: int = int(_pending_ability.get("activator", GameManager.current_player_index))
	_is_waiting_for_target = false
	_is_preparing_ability = false
	_pending_ability.clear()
	_set_targeting_areas_enabled(false)
	_clear_all_highlights()
	if restore_turn_lights:
		_update_turn_lights(activator)
	_refresh_human_interactivity()

func _on_ability_finished() -> void:
	_clear_ability_targeting_state()
	_update_turn_lights(GameManager.current_player_index)
	_refresh_human_interactivity()
	_update_action_buttons_state()
	_update_draw_arrow_visibility()
	$DeckArea/Area3D.input_ray_pickable = GameManager.can_player_draw(_human_ui_idx())
	$DiscardArea/Area3D.input_ray_pickable = GameManager.can_player_discard_drawn_card(_human_ui_idx())

func _on_player_drank_beer(player_idx, remaining):
	play_take_animation(player_idx)
	if player_idx < 0 or player_idx >= 4:
		return
	var beers_array = player_beers_nodes[player_idx]
	var prev_remaining = _last_sync_diag.get("beers", [3, 3, 3, 3])[player_idx] if player_idx < _last_sync_diag.get("beers", []).size() else 3
	for i in range(beers_array.size()):
		if i < remaining:
			beers_array[i].visible = true
			_apply_beer_visual_state(beers_array[i], BeerVisualState.FULL, false)
		elif beers_array[i].visible and i >= remaining:
			_animate_beer_emptying(beers_array[i])
		else:
			beers_array[i].visible = false
	if remaining < prev_remaining:
		shake(0.2, 0.3)
	elif remaining > prev_remaining:
		_animate_beer_refill(beers_array, remaining)

func _sync_beer_visuals(player_idx: int, remaining: int) -> void:
	if player_idx < 0 or player_idx >= player_beers_nodes.size():
		return
	var beers_array = player_beers_nodes[player_idx]
	for i in range(beers_array.size()):
		if i < remaining:
			beers_array[i].visible = true
			_apply_beer_visual_state(beers_array[i], BeerVisualState.FULL, false)
		else:
			beers_array[i].visible = false

func _remove_legacy_liquid_fill(beer_node: Node3D) -> void:
	var legacy := beer_node.get_node_or_null("LiquidFill")
	if is_instance_valid(legacy):
		legacy.queue_free()

func _reset_beer_mug_transform(beer_node: Node3D) -> void:
	if not is_instance_valid(beer_node):
		return
	_remove_legacy_liquid_fill(beer_node)
	beer_node.scale = beer_node.get_meta("base_scale", beer_scale)
	beer_node.position.y = beer_node.get_meta("base_y", beer_y_offset)
	beer_node.rotation_degrees.z = 0.0

func _apply_beer_visual_state(beer_node: Node3D, state: BeerVisualState, animate: bool) -> void:
	if not is_instance_valid(beer_node):
		return
	_remove_legacy_liquid_fill(beer_node)
	beer_node.rotation_degrees.z = 0.0
	beer_node.set_meta("beer_state", state)
	var fill: float = BEER_LIQUID_FILL[state]
	var base_scale: Vector3 = beer_node.get_meta("base_scale", beer_scale)
	var base_y: float = beer_node.get_meta("base_y", beer_y_offset)
	var target_scale := Vector3(base_scale.x, base_scale.y * fill, base_scale.z)
	var target_y := base_y - (base_scale.y * (1.0 - fill) * 0.35)
	if animate:
		var tween := create_tween().set_parallel(true)
		tween.tween_property(beer_node, "scale", target_scale, 0.28).set_trans(Tween.TRANS_QUAD)
		tween.tween_property(beer_node, "position:y", target_y, 0.28).set_trans(Tween.TRANS_QUAD)
	else:
		beer_node.scale = target_scale
		beer_node.position.y = target_y

func _animate_beer_emptying(beer_node: Node3D) -> void:
	if not is_instance_valid(beer_node):
		return
	beer_node.visible = true
	_reset_beer_mug_transform(beer_node)
	_apply_beer_visual_state(beer_node, BeerVisualState.FULL, false)

	var foam_pos := beer_node.global_position + Vector3(0, 0.22, 0)
	var spill_pos := beer_node.global_position + Vector3(0, 0.05, 0.1)
	spawn_particles("beer_drink", foam_pos)

	var tween := create_tween()
	# State 1 -> 2: full mug to half
	tween.tween_callback(func() -> void:
		if is_instance_valid(beer_node):
			_apply_beer_visual_state(beer_node, BeerVisualState.HALF, true)
	)
	tween.tween_interval(0.32)
	tween.tween_callback(func() -> void:
		if is_instance_valid(beer_node):
			spawn_particles("beer_drink", foam_pos)
	)
	tween.tween_interval(0.12)
	# State 2 -> 3: half to empty with spill
	tween.tween_callback(func() -> void:
		if is_instance_valid(beer_node):
			_apply_beer_visual_state(beer_node, BeerVisualState.EMPTY, true)
			spawn_particles("beer_spill", spill_pos)
	)
	tween.tween_interval(0.08)
	tween.tween_property(beer_node, "rotation_degrees:z", -20.0, 0.18).set_trans(Tween.TRANS_QUAD)
	tween.tween_interval(0.22)
	tween.tween_callback(func() -> void:
		if is_instance_valid(beer_node):
			beer_node.visible = false
			_reset_beer_mug_transform(beer_node)
			_apply_beer_visual_state(beer_node, BeerVisualState.FULL, false)
	)

func _animate_beer_refill(beers_array: Array, remaining: int) -> void:
	if remaining <= 0 or remaining > beers_array.size():
		return
	var beer_node: Node3D = beers_array[remaining - 1]
	if not is_instance_valid(beer_node):
		return
	beer_node.visible = true
	_reset_beer_mug_transform(beer_node)
	_apply_beer_visual_state(beer_node, BeerVisualState.EMPTY, false)
	var tween := create_tween()
	tween.tween_callback(func() -> void:
		if is_instance_valid(beer_node):
			_apply_beer_visual_state(beer_node, BeerVisualState.HALF, true)
	)
	tween.tween_interval(0.22)
	tween.tween_callback(func() -> void:
		if is_instance_valid(beer_node):
			_apply_beer_visual_state(beer_node, BeerVisualState.FULL, true)
			spawn_particles("beer_drink", beer_node.global_position + Vector3(0, 0.2, 0))
	)

func _on_player_eliminated(player_idx):
	_show_message(GameManager.players_info[player_idx].name + " PASSED OUT!")
	if not GameManager.is_multiplayer and player_idx == _human_ui_idx():
		trigger_glitch(0.5, 0.8)
		shake(0.35, 0.6)

func _on_player_gained_money(player_idx, amount, total):
	if player_idx == _human_ui_idx() and money_labels.size() > 0:
		money_labels[0].text = "$" + str(total)
	if amount > 0:
		var is_kod := _is_king_of_diamonds_on_discard_pile()
		_show_money_juice_popup(player_idx, amount, is_kod)

func _is_king_of_diamonds_on_discard_pile() -> bool:
	var pile = GameManager.deck_manager.discard_pile
	if pile.is_empty():
		return false
	var top: CardData = pile.back()
	return top.rank == "King" and top.suit == "Diamonds"

func _show_money_juice_popup(player_idx: int, amount: int, is_king_of_diamonds: bool = false) -> void:
	var seat := _get_safe_player_pos(player_idx)
	if not seat:
		return
	var label := Label3D.new()
	label.name = "MoneyJuice"
	label.text = "+$%d" % amount
	label.font_size = 118 if is_king_of_diamonds else 76
	label.outline_size = 16 if is_king_of_diamonds else 12
	label.outline_modulate = Color(0.05, 0.05, 0.08, 0.95)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(1.0, 0.88, 0.12) if is_king_of_diamonds else Color(0.3, 1.0, 0.5)
	var side: float = 0.42 if player_idx in [0, 2] else -0.42
	label.position = Vector3(side, 1.2, 0.15)
	seat.add_child(label)
	label.scale = Vector3(0.35, 0.35, 0.35)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(label, "scale", Vector3.ONE * (1.15 if is_king_of_diamonds else 1.0), 0.24) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(label, "position:y", label.position.y + 0.75, 0.95) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(label, "modulate:a", 0.0, 0.5).set_delay(0.7)
	tw.chain().tween_callback(label.queue_free)
	var burst_pos := seat.global_position + Vector3(0, 1.05, 0)
	if is_king_of_diamonds:
		spawn_particles("turn_change", burst_pos)
		spawn_particles("card_flip", burst_pos + Vector3(0, 0.15, 0))
		shake(0.1, 0.18)
	else:
		spawn_particles("card_flip", burst_pos)

func _on_ability_played(player_idx, ability_id, target_idx: int = -1):
	play_take_animation(player_idx)
	var p_name = GameManager.players_info[player_idx].name
	_show_message(p_name + " used " + ability_id.capitalize() + "!")
	if ability_id == "jumpscare" and target_idx >= 0:
		_on_jumpscare_triggered(player_idx, target_idx)
	# Reset any hammer hover state when an ability is consumed
	if _hovered_hammer_cabinet != null and _hovered_hammer_idx_board >= 0:
		if is_instance_valid(_hovered_hammer_cabinet):
			_hovered_hammer_cabinet.unhover_hammer(_hovered_hammer_idx_board)
		_hovered_hammer_idx_board = -1
		_hovered_hammer_cabinet = null
	spawn_particles("ability_use", player_pos_nodes[player_idx].global_position + Vector3(0, 0.5, 0))
	# Wait one frame so GameManager has already removed the ability from the array
	await get_tree().process_frame
	_update_ability_visuals(player_idx)

func _on_turn_started(player_idx):
	var p_info = GameManager.players_info[player_idx]
	var is_handoff: bool = _last_turn_player_idx != -1 and _last_turn_player_idx != player_idx
	_last_turn_player_idx = player_idx

	turn_label.text = "> " + p_info.name.to_upper() + "'S TURN"
	_animate_glitch_text(turn_label)

	if is_instance_valid(turn_indicator_circle):
		var mat = turn_indicator_circle.get_active_material(0)
		if mat is ShaderMaterial:
			mat.set_shader_parameter("active_player_index", player_idx)

	if is_handoff:
		_play_turn_transition_vfx(player_idx)
		_update_turn_lights(player_idx, false, 0.65)
	else:
		_update_turn_lights(player_idx)

	if player_idx == _human_ui_idx():
		GameManager.play_sfx(_bell_stream)
	else:
		_show_message(p_info.name + " is thinking...")
	_update_draw_arrow_visibility()

func _play_turn_transition_vfx(player_idx: int) -> void:
	var seat := _get_safe_player_pos(player_idx)
	if seat:
		spawn_particles("turn_change", seat.global_position + Vector3(0, 0.75, 0))

	if is_instance_valid(turn_indicator_circle):
		if _turn_vfx_tween and _turn_vfx_tween.is_valid():
			_turn_vfx_tween.kill()
		var base_scale: Vector3 = turn_indicator_circle.scale
		_turn_vfx_tween = create_tween()
		_turn_vfx_tween.tween_property(
			turn_indicator_circle, "scale", base_scale * 1.1, 0.22
		).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_turn_vfx_tween.tween_property(
			turn_indicator_circle, "scale", base_scale, 0.4
		).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

	if player_avatars.has(player_idx) and is_instance_valid(player_avatars[player_idx]):
		var avatar: Node3D = player_avatars[player_idx]
		var av_scale := avatar.scale
		var av_tween := create_tween()
		av_tween.tween_property(avatar, "scale", av_scale * 1.05, 0.18).set_trans(Tween.TRANS_BACK)
		av_tween.tween_property(avatar, "scale", av_scale, 0.35).set_trans(Tween.TRANS_ELASTIC)

	trigger_glitch(0.2, 0.45)
	var shake_amp := 0.06 if GameManager.is_multiplayer else 0.08
	shake(shake_amp, 0.25)

func _update_draw_arrow_visibility():
	if is_instance_valid(draw_arrow):
		draw_arrow.visible = GameManager.can_player_draw(_human_ui_idx())

func _update_turn_lights(current_player: int, all_on: bool = false, duration: float = 0.35):
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
			tween.tween_property(pl, "light_energy", target_energy, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
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
	play_take_animation(player_idx)
	if pending_card: pending_card.queue_free()

	_update_deck_visual()

	if player_idx != _human_ui_idx():
		_show_message(GameManager.players_info[player_idx].name + " is drawing...", DRAW_STATUS_HOLD_SEC)
	else:
		_show_message("You drew a card — choose swap or discard.", DRAW_STATUS_HOLD_SEC)

	pending_card = card_scene.instantiate()
	pending_card.name = "PendingCard"
	add_child(pending_card)

	card_data.is_face_up = false
	pending_card.setup(card_data)
	pending_card.card_clicked.connect(_on_card_clicked)
	# Move slightly higher and CLOSER TO CAMERA (Z offset) to ensure it's not blocked by DeckArea
	pending_card.position = deck_area.position + Vector3(0, 0.6, 0.5)
	pending_card.rotation_degrees = Vector3(90, 0, 0) # Start face down on the table
	pending_card.scale = Vector3(1.5, 1.5, 1.5)
	pending_card.set_interactive(player_idx == _human_ui_idx())
	spawn_particles("default", deck_area.global_position)

	# Reveal animations
	await get_tree().create_timer(0.1, false).timeout
	pending_card.animate_flip(player_idx == _human_ui_idx())
	_update_deck_visual() # Refresh deck after drawing

func _reveal_synced_pending_card(is_local_turn: bool) -> void:
	if not is_instance_valid(pending_card):
		return
	await get_tree().create_timer(0.1, false).timeout
	if is_instance_valid(pending_card):
		pending_card.animate_flip(is_local_turn)
	_update_deck_visual()

func _on_card_discarded(player_idx, card_data):
	play_take_animation(player_idx)
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
		if card_to_discard is Card3D:
			card_to_discard.set_discard_trail_active(true)
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
			if card_to_discard is Card3D:
				card_to_discard.set_discard_trail_active(false)
			_update_discard_visual()
			_update_deck_visual()
			shake(0.05, 0.2)
			spawn_particles("card_trail", target_global_pos)
			if is_instance_valid(card_to_discard):
				card_to_discard.queue_free()
		)

	# 5. REFRESH HAND after discard tween so remaining cards settle correctly
	if player_idx != -1:
		get_tree().create_timer(0.5, false).timeout.connect(
			func() -> void: _update_hand_visuals(player_idx),
			CONNECT_ONE_SHOT
		)

func _show_message(text: String, hold_seconds: float = 0.0) -> void:
	if hold_seconds <= 0.0 and Time.get_ticks_msec() < _status_message_hold_until_msec:
		_status_message_pending = text
		return
	if hold_seconds > 0.0:
		_status_message_hold_until_msec = Time.get_ticks_msec() + int(hold_seconds * 1000.0)
	else:
		_status_message_hold_until_msec = 0
	_status_message_pending = ""
	_status_message_hide_pending = false
	_apply_status_message(text)

func _apply_status_message(text: String) -> void:
	_current_ability_message = text
	for child in top_center.get_children():
		child.queue_free()

	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", ResponsiveUI.scaled_font(32))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color(0.0, 1.0, 1.0))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 3)
	label.add_theme_constant_override("shadow_offset_y", 3)
	top_center.add_child(label)
	top_center.set_anchors_preset(Control.PRESET_CENTER_TOP)
	label.show()

func _flush_status_message_hold() -> void:
	if Time.get_ticks_msec() < _status_message_hold_until_msec:
		return
	if _status_message_pending != "":
		var pending := _status_message_pending
		_status_message_pending = ""
		_status_message_hold_until_msec = 0
		_status_message_hide_pending = false
		_apply_status_message(pending)
	elif _status_message_hide_pending:
		_hide_message(true)

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

	# Confirm Dutch and Forfeit Dutch are only shown in TURN_CONFIRM_DUTCH state
	var is_confirm_dutch_state = GameManager.current_state == GameManager.GameState.TURN_CONFIRM_DUTCH
	var can_confirm = GameManager.can_player_confirm_dutch(local_idx)

	# Set button disabled states (disabled = not allowed)
	end_turn_btn.disabled = not can_end_turn
	if is_instance_valid(end_turn_btn):
		if GameManager.can_player_cancel_jump_in(local_idx):
			end_turn_btn.text = "> CANCEL <"
		else:
			end_turn_btn.text = "> END_TURN <"
	jump_in_btn.disabled = not can_jump_in
	call_dutch_btn.disabled = not can_call_dutch

	# The core actions: end_turn is replaced by confirm_dutch in confirm state.
	# call_dutch and jump_in are still visible.
	end_turn_btn.visible = not is_confirm_dutch_state
	jump_in_btn.visible = true
	call_dutch_btn.visible = true
	
	confirm_dutch_btn.visible = is_confirm_dutch_state
	confirm_dutch_btn.disabled = not can_confirm
	
	forfeit_dutch_btn.visible = is_confirm_dutch_state
	forfeit_dutch_btn.disabled = not can_confirm

	# Size action panel taller if forfeit_dutch is visible
	if is_confirm_dutch_state:
		action_panel.offset_top = -280
	else:
		action_panel.offset_top = -220

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
	if new_state != GameManager.GameState.TURN_SWAP_ABILITY:
		_hide_jack_swap_ui()
	_update_draw_arrow_visibility()

	_apply_gameplay_mouse_mode()


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
				_show_jack_swap_alert()
				_update_jack_swap_banner(swap_sources.size())
				_highlight_selectable_cards(true)
			else:
				var swapper_name: String = GameManager.players_info[GameManager.active_ability_player].name
				_show_message(swapper_name + " played a Jack — swapping cards...")
			_update_turn_lights(-1, true)
			swap_sources.clear()
		GameManager.GameState.GAME_OVER:
			pass

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

func _hide_message(force: bool = false) -> void:
	if not force and Time.get_ticks_msec() < _status_message_hold_until_msec:
		_status_message_hide_pending = true
		return
	_status_message_hold_until_msec = 0
	_status_message_pending = ""
	_status_message_hide_pending = false
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
	
	# Relayout during initial peek cancels is_being_peeked via deferred force_layout.
	if GameManager.current_state == GameManager.GameState.INITIAL_PEEK:
		return
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
	
	if GameManager.current_state == GameManager.GameState.INITIAL_PEEK:
		return
	for i in range(4):
		if card_node in player_hands[i]:
			_update_hand_visuals(i)
			break

func _update_hand_visuals(player_idx: int, force_layout: bool = false):
	if player_idx < 0 or player_idx >= 4: return
	if force_layout \
			and GameManager.current_state == GameManager.GameState.INITIAL_PEEK \
			and player_idx == _human_ui_idx():
		_initial_peek_log("blocked force_layout during peek phase")
		force_layout = false
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
	var skipped_relayout := false
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
			
			# Skip if mid-flip/peek unless we are forcing a post-penalty relayout.
			if not force_layout and (card_node.is_being_peeked or (card_node.is_flipping and not card_node.has_meta("is_swapping_in"))):
				skipped_relayout = true
				continue
			if force_layout:
				card_node.is_being_peeked = false
				card_node.is_flipping = false
				card_node.set_highlight(false)
				if card_node.hover_tween and card_node.hover_tween.is_valid():
					card_node.hover_tween.kill()
				card_node.hover_lift = 0.0
				card_node.hover_scale = 1.0
			
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
			# Shrink back to normal hand size if the card came from the draw pile (1.5x)
			if card_node.scale != Vector3.ONE:
				tween.tween_property(card_node, "scale", Vector3.ONE, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT).set_delay(delay)
			# After a swap-in tween completes, re-evaluate interactivity so the
			# card can immediately be clicked/jumped-in (it was set_interactive(false)
			# when consumed from pending_card, before the state-change highlight
			# refresh fired).
			if delay > 0.0:
				tween.chain().tween_callback(_refresh_human_interactivity)

	if skipped_relayout:
		_schedule_hand_relayout(player_idx)

func _schedule_hand_relayout(player_idx: int) -> void:
	if GameManager.current_state == GameManager.GameState.INITIAL_PEEK \
			and player_idx == _human_ui_idx():
		_initial_peek_log("skipped deferred relayout during peek phase")
		return
	var key := "hand_relayout_%d" % player_idx
	if has_meta(key):
		return
	set_meta(key, true)
	get_tree().create_timer(0.4, false).timeout.connect(func() -> void:
		remove_meta(key)
		if is_instance_valid(self):
			_update_hand_visuals(player_idx, true)
	, CONNECT_ONE_SHOT)

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

func _initial_peek_log(msg: String) -> void:
	if INITIAL_PEEK_DEBUG:
		print("[PEEK DEBUG] %s | open=%d mem=%d state=%s" % [
			msg, _initial_peek_open.size(), _initial_peek_memorized.size(),
			GameManager.GameState.keys()[GameManager.current_state]
		])

func _start_peek_phase() -> void:
	_initial_peek_log("phase started")
	_initial_peek_open.clear()
	_initial_peek_memorized.clear()
	_show_message("Peek 2 cards: click to reveal, click again to hide.")
	for c3d in player_hands[_human_ui_idx()]:
		if is_instance_valid(c3d) and c3d is Card3D:
			c3d.set_highlight(true)
			c3d.set_interactive(true)

func _initial_peek_is_local_card(node: Node) -> bool:
	return node in player_hands[_human_ui_idx()]

func _initial_peek_show_card(card: Card3D) -> void:
	_initial_peek_log("OPEN %s %s" % [card.data.rank, card.data.suit])
	card.is_being_peeked = true
	card.animate_flip(true, -1.0, false)
	if card not in _initial_peek_open:
		_initial_peek_open.append(card)
	if card not in _initial_peek_memorized:
		_initial_peek_memorized.append(card)
	_show_message("Peek %d/%d — click card again to hide." % [
		_initial_peek_memorized.size(), INITIAL_PEEK_MAX
	])

func _initial_peek_hide_card(card: Card3D) -> void:
	_initial_peek_log("CLOSE %s %s (held face-up until click)" % [card.data.rank, card.data.suit])
	card.is_being_peeked = false
	card.animate_flip(false, -1.0, false)
	_initial_peek_open.erase(card)
	_try_finish_initial_peek()

func _try_finish_initial_peek() -> void:
	if _initial_peek_memorized.size() < INITIAL_PEEK_MAX:
		_initial_peek_log("need %d memorized, have %d" % [INITIAL_PEEK_MAX, _initial_peek_memorized.size()])
		return
	if not _initial_peek_open.is_empty():
		_initial_peek_log("waiting — %d card(s) still face-up" % _initial_peek_open.size())
		_show_message("Hide all peeked cards (click each again) to continue.")
		return
	_initial_peek_log("complete — all %d cards memorized and face-down" % INITIAL_PEEK_MAX)
	_clear_all_highlights()
	for c3d in player_hands[_human_ui_idx()]:
		if is_instance_valid(c3d) and c3d is Card3D:
			c3d.set_interactive(false)
	_initial_peek_open.clear()
	_initial_peek_memorized.clear()
	if GameManager.is_multiplayer:
		_send_action("initial_peek_done")
	else:
		GameManager.complete_initial_peek()

func _on_card_clicked(node, data):
	play_take_animation(_human_ui_idx())
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
			
	# JUMP-IN SHORTCUT: card click enters selection only — validate on a second click
	if p_idx == GameManager.local_player_idx and GameManager.can_player_start_jump_in(GameManager.local_player_idx) and GameManager.current_state != GameManager.GameState.TURN_JUMP_IN_SELECTION:
		print("[BOARD DEBUG] Implicit Jump-In started by card click.")
		_send_action("start_jump_in")
		return

	match GameManager.current_state:
		GameManager.GameState.INITIAL_PEEK:
			if not _initial_peek_is_local_card(node) or not node is Card3D:
				_initial_peek_log("ignored click — not local hand card")
				return
			var peek_card := node as Card3D
			if peek_card in _initial_peek_open:
				_initial_peek_hide_card(peek_card)
				return
			if peek_card in _initial_peek_memorized:
				_initial_peek_log("ignored — already memorized %s %s" % [data.rank, data.suit])
				_show_message("You already peeked that card.")
				return
			if _initial_peek_memorized.size() >= INITIAL_PEEK_MAX:
				_initial_peek_log("ignored — max memorized, hide open cards first")
				_show_message("Hide peeked cards first (click them again).")
				return
			_initial_peek_show_card(peek_card)
		
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
			_update_jack_swap_banner(swap_sources.size())
			if swap_sources.size() == 2:
				var s1 = swap_sources[0]
				var s2 = swap_sources[1]
				_send_action("complete_swap_ability", {"p1": s1.player, "c1": s1.index, "p2": s2.player, "c2": s2.index})
				swap_sources.clear()
				_hide_jack_swap_ui()
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
		play_take_animation(GameManager.local_player_idx)
		_send_action("draw_card")

func _on_discard_clicked():
	if GameManager.can_player_discard_drawn_card(GameManager.local_player_idx):
		play_take_animation(GameManager.local_player_idx)
		_send_action("discard_drawn")

func _is_local_human_defeat() -> bool:
	if GameManager.is_multiplayer:
		return false
	var human_idx := _human_ui_idx()
	if human_idx < 0 or human_idx >= GameManager.players_info.size():
		return false
	return GameManager.players_info[human_idx].is_eliminated

func _on_scores_ready(results: Array) -> void:
	_victory_results_pending = results
	if not _victory_cinematic_active:
		_run_victory_cinematic()

func _run_victory_cinematic() -> void:
	if _victory_cinematic_active:
		return
	_victory_cinematic_active = true
	_victory_cinematic_async()

func _victory_cinematic_async() -> void:
	for _i in range(60):
		if not _victory_results_pending.is_empty():
			break
		await get_tree().process_frame

	# Let multiplayer_sync_applied finish hand visuals before the reveal.
	if GameManager.is_multiplayer:
		await get_tree().process_frame
		await get_tree().process_frame

	var human_defeat := _is_local_human_defeat()
	var winner_id: int = 0
	if _victory_results_pending.size() > 0:
		winner_id = int(_victory_results_pending[0].id)

	if not human_defeat:
		await _play_victory_reveal_sequence(winner_id)

	if not _victory_results_pending.is_empty():
		if human_defeat:
			_show_defeat_overlay(_victory_results_pending)
		else:
			_show_victory_overlay(_victory_results_pending)

	_victory_cinematic_active = false

func _show_defeat_overlay(results: Array) -> void:
	if is_instance_valid(_victory_overlay_layer):
		_victory_overlay_layer.queue_free()
	_victory_overlay_layer = null

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	shake(0.45, 1.0)
	trigger_glitch(0.65, 1.4)
	GameManager.play_sfx(GameManager.sfx_beer_drink)

	var overlay = CanvasLayer.new()
	overlay.layer = 110
	_victory_overlay_layer = overlay
	add_child(overlay)

	var bg = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.08, 0.0, 0.0, 0.0)
	overlay.add_child(bg)
	var bg_tween = create_tween()
	bg_tween.tween_property(bg, "color:a", 0.9, 0.5)

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.modulate.a = 0.0
	overlay.add_child(center)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	center.add_child(vbox)

	var title = Label.new()
	title.text = "YOU PASSED OUT!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color(1.0, 0.25, 0.2))
	vbox.add_child(title)

	var subtitle = Label.new()
	subtitle.text = "All 3 beers gone — you're eliminated."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 30)
	subtitle.modulate = Color(0.9, 0.7, 0.7)
	vbox.add_child(subtitle)

	var winner_name := "Nobody"
	for entry in results:
		if not entry.is_eliminated:
			winner_name = entry.name
			break
	var outcome = Label.new()
	outcome.text = winner_name + " wins this round."
	outcome.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outcome.add_theme_font_size_override("font_size", 28)
	outcome.modulate = Color(0.75, 0.75, 0.8)
	vbox.add_child(outcome)

	var title_tween = create_tween()
	title_tween.tween_property(center, "modulate:a", 1.0, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	var btn_h = HBoxContainer.new()
	btn_h.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_h)

	var play_again = Button.new()
	play_again.text = "Try Again"
	play_again.pressed.connect(func(): get_tree().reload_current_scene())
	btn_h.add_child(play_again)

	var main_menu = Button.new()
	main_menu.text = "Main Menu"
	main_menu.pressed.connect(_on_pause_main_menu)
	btn_h.add_child(main_menu)

func _show_victory_overlay(results: Array) -> void:
	if is_instance_valid(_victory_overlay_layer):
		_victory_overlay_layer.queue_free()
	_victory_overlay_layer = null

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	shake(0.35, 0.9)
	trigger_glitch(0.45, 1.2)
	var winner_id: int = int(results[0].id) if results.size() > 0 else 0
	if player_pos_nodes.has(winner_id):
		spawn_particles("card_flip", player_pos_nodes[winner_id].global_position + Vector3(0, 1.2, 0))
		play_take_animation(winner_id)

	var overlay = CanvasLayer.new()
	overlay.layer = 110
	_victory_overlay_layer = overlay
	add_child(overlay)

	var bg = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.0)
	overlay.add_child(bg)
	var bg_tween = create_tween()
	bg_tween.tween_property(bg, "color:a", 0.85, 0.5)

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.modulate.a = 0.0
	overlay.add_child(center)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	center.add_child(vbox)

	var title = Label.new()
	var winner_name = results[0].name if results.size() > 0 else "Nobody"
	title.text = winner_name.to_upper() + " WINS!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color(1.0, 0.92, 0.2))
	vbox.add_child(title)
	var title_tween = create_tween()
	title_tween.tween_property(center, "modulate:a", 1.0, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	title.scale = Vector2(0.6, 0.6)
	title_tween.parallel().tween_property(title, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_BACK)
	var win_mode = Label.new()
	var mode_text = "Lowest Score Wins" if GameManager.win_condition_lowest_wins else "Highest Score Wins"
	win_mode.text = "(" + mode_text + ")"
	win_mode.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	win_mode.add_theme_font_size_override("font_size", 32)
	win_mode.modulate = Color(1.0, 0.8, 0.0) # Golden yellow
	vbox.add_child(win_mode)

	var emote_hint := Label.new()
	emote_hint.text = "Celebrate!"
	emote_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	emote_hint.add_theme_font_size_override("font_size", 22)
	emote_hint.modulate = Color(0.7, 0.95, 1.0)
	vbox.add_child(emote_hint)

	var emote_row := HBoxContainer.new()
	emote_row.alignment = BoxContainer.ALIGNMENT_CENTER
	emote_row.add_theme_constant_override("separation", 14)
	vbox.add_child(emote_row)
	for emote in GAME_EMOTES:
		var emote_btn := Button.new()
		emote_btn.text = emote.label
		emote_btn.pressed.connect(_on_victory_emote_pressed.bind(winner_id, emote.id))
		emote_row.add_child(emote_btn)

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
		if _emote_wheel_open:
			_close_emote_wheel()
			get_viewport().set_input_as_handled()
			return
		if GameManager.can_player_cancel_jump_in(GameManager.local_player_idx):
			_send_action("cancel_jump_in")
			_show_message("Jump-in cancelled.")
			get_viewport().set_input_as_handled()
			return
		if _is_waiting_for_target:
			_clear_ability_targeting_state()
			_hide_message()
			_show_message("Ability targeting cancelled.")
			get_viewport().set_input_as_handled()
			return

		if pause_menu_instance == null:
			_pause_game()
		else:
			_on_pause_resumed()
		get_viewport().set_input_as_handled()

	# --- BOARD CLICK (free cursor; hold RMB to look around) ---
	if not noclip_enabled and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if ResponsiveUI.is_touch_device():
			pass
		else:
			var screen_pos := _get_screen_ray_position()
			if not _is_mouse_over_hud(screen_pos) and _handle_board_click_at_screen(screen_pos):
				get_viewport().set_input_as_handled()
				return

	# DEBUG: Press L to toggle all face-down cards face-up; F3 toggles FSM debug panel.
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_L:
			_toggle_debug_reveal()
		elif event.keycode == KEY_F3:
			_toggle_debug_overlay()
			get_viewport().set_input_as_handled()

	# --- GAME KEYBOARD CONTROLS ---
	# Priority Guard 2: Dev console is open — keys belong to the text input, not the game.
	if DevConsole and DevConsole.window.is_visible():
		return

	# Cabinet Hammer Interaction (intercept KEY_E if a hammer is hovered)
	if _hovered_hammer_idx_board != -1 and is_instance_valid(_hovered_hammer_cabinet) and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_E:
			play_take_animation(_human_ui_idx())
			_use_hovered_hammer()
			get_viewport().set_input_as_handled()
			return

	# Cabinet Drawer Interaction (intercept keypress if hovered)
	if _hovered_shelf_index != -1 and is_instance_valid(_hovered_cabinet_node) and event.is_pressed() and not event.is_echo():
		if (event is InputEventKey and event.keycode == KEY_E) or event.is_action("game_call_dutch") or event.is_action("game_forfeit_dutch"):
			play_take_animation(_human_ui_idx())
			_hovered_cabinet_node.toggle_shelf(_hovered_shelf_index)
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
	# Enter — end turn; C — confirm dutch (mutually exclusive states)
	if event.is_action("game_end_turn") and end_turn_btn.visible and not end_turn_btn.disabled:
		_on_end_turn_pressed()
		get_viewport().set_input_as_handled()

	elif event.is_action("game_confirm_dutch") and confirm_dutch_btn.visible and not confirm_dutch_btn.disabled:
		_on_confirm_dutch_pressed()
		get_viewport().set_input_as_handled()

	# F — forfeit dutch; D — call dutch (mutually exclusive states)
	elif event.is_action("game_forfeit_dutch") and forfeit_dutch_btn.visible and not forfeit_dutch_btn.disabled:
		_on_cancel_dutch_pressed()
		get_viewport().set_input_as_handled()

	elif event.is_action("game_call_dutch") and call_dutch_btn.visible and not call_dutch_btn.disabled:
		_on_call_dutch_pressed()
		get_viewport().set_input_as_handled()

	# Space — jump in
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

	elif event.is_action("game_emote_wheel"):
		_toggle_emote_wheel()
		get_viewport().set_input_as_handled()

	elif event is InputEventKey and event.keycode >= KEY_1 and event.keycode <= KEY_4:
		var emote_idx: int = event.keycode - KEY_1
		if emote_idx < GAME_EMOTES.size():
			_on_emote_wheel_pressed(GAME_EMOTES[emote_idx].id)
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
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
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
	_apply_gameplay_mouse_mode()
	_update_action_button_labels()

func _on_pause_main_menu():
	get_tree().paused = false
	get_tree().change_scene_to_file("res://main_menu.tscn")

func _on_host_disconnected() -> void:
	if not GameManager.is_multiplayer:
		return
	NetworkManager.leave_game()
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
		if not (GameManager.easy_mode and player_idx == _human_ui_idx()):
			await get_tree().create_timer(0.35, false).timeout
		_update_hand_visuals(player_idx, true)


func _on_bot_action(message):
	_show_message(message)

func _setup_debug_overlay() -> void:
	if is_instance_valid(_debug_overlay_layer):
		return
	_debug_overlay_layer = CanvasLayer.new()
	_debug_overlay_layer.layer = 120
	_debug_overlay_layer.visible = false
	add_child(_debug_overlay_layer)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = 8
	panel.offset_top = 8
	panel.offset_right = 420
	panel.offset_bottom = 260
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.02, 0.05, 0.82)
	style.border_color = Color(0.2, 0.9, 0.9, 0.6)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)
	_debug_overlay_layer.add_child(panel)

	_debug_overlay_label = Label.new()
	_debug_overlay_label.add_theme_font_size_override("font_size", 14)
	_debug_overlay_label.add_theme_color_override("font_color", Color(0.75, 1.0, 1.0))
	panel.add_child(_debug_overlay_label)

func _toggle_debug_overlay() -> void:
	_debug_overlay_visible = not _debug_overlay_visible
	if is_instance_valid(_debug_overlay_layer):
		_debug_overlay_layer.visible = _debug_overlay_visible
	if _debug_overlay_visible:
		_update_debug_overlay()

func _update_debug_overlay() -> void:
	if not _debug_overlay_visible or not is_instance_valid(_debug_overlay_label):
		return
	var gm := GameManager
	var lines: PackedStringArray = PackedStringArray([
		"FSM: %s" % gm.GameState.keys()[gm.current_state],
		"Player: P%d (local P%d)" % [gm.current_player_index, _human_ui_idx()],
		"jump_in: idx=%d validating=%s" % [gm.jump_in_player_idx, str(gm.jump_in_validating)],
		"ability: active=%d state=%s" % [gm.active_ability_player, gm.GameState.keys()[gm.state_before_ability]],
		"targeting: %s prep=%s" % [str(_is_waiting_for_target), str(_is_preparing_ability)],
		"drawn: %s" % ("yes" if gm.drawn_card_data != null else "no"),
		"last: %s" % (gm.last_debug_event if gm.last_debug_event != "" else "(none)"),
		"[F3 hide | log: user://game_debug.log]"
	])
	_debug_overlay_label.text = "\n".join(lines)

func _process(delta: float) -> void:
	if Engine.is_editor_hint(): return

	if _debug_overlay_visible:
		_update_debug_overlay()

	if GameManager.is_multiplayer:
		_mp_status_poll_timer += delta
		if _mp_status_poll_timer >= 0.5:
			_mp_status_poll_timer = 0.0
			GameManager.refresh_mp_connection_status()
	
	_update_cabinet_hover()
	_update_crosshair_raycast()
	_update_action_buttons_state()
	_update_emote_wheel_state()
	_flush_status_message_hold()
	
	if is_instance_valid(draw_arrow) and draw_arrow.visible:
		draw_arrow.position.y = 1.2 + sin(Time.get_ticks_msec() * 0.005) * 0.15
	
	var shake_offset = Vector3.ZERO
	if _shake_timer > 0:
		_shake_timer -= delta
		shake_offset = Vector3(
			randf_range(-1, 1) * _shake_intensity,
			randf_range(-1, 1) * _shake_intensity,
			0
		)

	if noclip_enabled and not DevConsole.window.visible:
		_handle_noclip_movement(delta)
	elif not noclip_enabled:
		# Rotate camera smoothly towards the look angles accumulated from mouse motion
		camera.rotation.y = lerp_angle(camera.rotation.y, _base_camera_rotation.y + _look_yaw, delta * 12.0)
		camera.rotation.x = lerp_angle(camera.rotation.x, _base_camera_rotation.x + _look_pitch, delta * 12.0)

		# First-Person Camera and Head tracking for the local human player
		var first_person_active = false
		var local_p_idx = _human_ui_idx()
		
		# Ensure correct head/neck scaling and cleanup shadow attachments for all avatars
		for p_idx in player_avatars:
			var avatar = player_avatars[p_idx]
			if is_instance_valid(avatar):
				var skeleton = avatar.get_node_or_null("Armature/Skeleton3D") as Skeleton3D
				if skeleton:
					var head_idx = skeleton.find_bone("mixamorig_Head")
					var neck_idx = skeleton.find_bone("mixamorig_Neck")
					
					if head_idx != -1:
						if p_idx == local_p_idx:
							skeleton.set_bone_pose_scale(head_idx, Vector3.ZERO)
						else:
							skeleton.set_bone_pose_scale(head_idx, Vector3(1.0, 1.0, 1.0))
							var head_pos = skeleton.get_bone_pose_position(head_idx)
							head_pos.z = 3.74789
							skeleton.set_bone_pose_position(head_idx, head_pos)
					if neck_idx != -1:
						if p_idx == local_p_idx:
							skeleton.set_bone_pose_scale(neck_idx, Vector3.ZERO)
						else:
							skeleton.set_bone_pose_scale(neck_idx, Vector3(1.0, 1.0, 1.0))
					if p_idx == local_p_idx:
						_set_avatar_body_visible(avatar, false)
						if GameManager.is_multiplayer:
							avatar.visible = false
					else:
						_set_avatar_body_visible(avatar, true)
						if GameManager.is_multiplayer and p_idx < GameManager.num_players:
							avatar.visible = true
					
					# Lock hips translation completely to rest position to prevent rising/shifting during take animation
					var hips_idx = skeleton.find_bone("mixamorig_Hips")
					if hips_idx != -1:
						skeleton.set_bone_pose_position(hips_idx, Vector3(0.043546, -1.822579, -44.87878))
					
					# Clean up shadows-only mesh helpers from previous worktree versions
					var attachment = skeleton.get_node_or_null("HeadShadowAttachment")
					if attachment:
						attachment.queue_free()

		if not GameManager.is_multiplayer and player_avatars.has(local_p_idx) and is_instance_valid(player_avatars[local_p_idx]):
			var avatar = player_avatars[local_p_idx]
			var skeleton = avatar.get_node_or_null("Armature/Skeleton3D") as Skeleton3D
			if skeleton:
				var head_idx = skeleton.find_bone("mixamorig_Head")
				if head_idx != -1:
					first_person_active = true
					
					# Rotate body Y (yaw) based on camera Y rotation with 35% damping (clamped to -50 to +50 degrees)
					var smooth_yaw = camera.rotation.y - _base_camera_rotation.y
					var smooth_pitch = camera.rotation.x - _base_camera_rotation.x
					var body_yaw = clamp(smooth_yaw * 0.35, deg_to_rad(-50.0), deg_to_rad(50.0))
					avatar.rotation.y = deg_to_rad(90.0) + body_yaw
					
				# Rotate head bone to look exactly where the camera is looking in 3D world space
				var cam_basis = camera.global_transform.basis
				# Guard: skip quaternion ops when basis is degenerate (e.g. headless mode, uninitialized transforms)
				if cam_basis.determinant() != 0.0:
					var target_basis = cam_basis * Basis.from_euler(Vector3(0, PI, 0)) # Rotate 180 on Y because head faces +Z, camera looks -Z
					var target_global_quat = target_basis.get_rotation_quaternion()
					var parent_idx = skeleton.get_bone_parent(head_idx)
					if parent_idx != -1:
						var parent_global_pose = skeleton.global_transform * skeleton.get_bone_global_pose(parent_idx)
						if parent_global_pose.basis.determinant() != 0.0:
							var parent_global_quat = parent_global_pose.basis.get_rotation_quaternion()
							var local_quat = parent_global_quat.inverse() * target_global_quat
							skeleton.set_bone_pose_rotation(head_idx, local_quat)
					
					# Force skeleton update to get correct global bone pose in the same frame
					skeleton.force_update_all_bone_transforms()
					
					# Eye-level camera from hips anchor (local body mesh hidden — no head clipping).
					if is_instance_valid(camera):
						camera.near = 0.05
						var hips_idx := skeleton.find_bone("mixamorig_Hips")
						var eye_anchor: Vector3 = avatar.global_position
						if hips_idx != -1:
							eye_anchor = skeleton.global_transform * skeleton.get_bone_global_pose(hips_idx).origin
						
						if not _camera_initialized:
							_base_head_y = eye_anchor.y + FP_EYE_HEIGHT_OFFSET
							_camera_initialized = true
						
						var forward = Vector3(-sin(camera.rotation.y), 0.0, -cos(camera.rotation.y)).normalized()
						var right = Vector3(forward.z, 0.0, -forward.x).normalized()
						
						var target_camera_pos = Vector3(
							eye_anchor.x + forward.x * 0.42 + right.x * 0.06,
							_base_head_y,
							eye_anchor.z + forward.z * 0.42 + right.z * 0.06
						) + shake_offset
						
						# Direct assignment to prevent relative lag
						camera.global_position = target_camera_pos

		if not first_person_active and is_instance_valid(camera):
			camera.near = 0.05 # Restore default near clip
			camera.position = _effective_camera_base_local() + shake_offset

		# Apply idle arm adjustments (hands down) for all spawned player avatars during idle animation
		for p_idx in player_avatars:
			var avatar = player_avatars[p_idx]
			if is_instance_valid(avatar) and avatar.visible:
				var skeleton = avatar.get_node_or_null("Armature/Skeleton3D") as Skeleton3D
				var ap = avatar.get_node_or_null("AnimationPlayer") as AnimationPlayer
				if skeleton and ap:
					if not avatar_arm_weights.has(p_idx):
						avatar_arm_weights[p_idx] = 1.0
					
					var target_w = 1.0 if ap.current_animation == "idle" else 0.0
					avatar_arm_weights[p_idx] = move_toward(avatar_arm_weights[p_idx], target_w, delta * 3.33)
					
					var w = avatar_arm_weights[p_idx]
					if w > 0.0:
						var left_arm = skeleton.find_bone("mixamorig_LeftArm")
						var left_forearm = skeleton.find_bone("mixamorig_LeftForeArm")
						var right_arm = skeleton.find_bone("mixamorig_RightArm")
						var right_forearm = skeleton.find_bone("mixamorig_RightForeArm")
						
						if left_arm != -1:
							var anim_rot = skeleton.get_bone_pose_rotation(left_arm)
							var target_rot = Quaternion.from_euler(Vector3(0.0, deg_to_rad(60.0), deg_to_rad(60.0)))
							skeleton.set_bone_pose_rotation(left_arm, anim_rot.slerp(target_rot, w))
						if left_forearm != -1:
							var anim_rot = skeleton.get_bone_pose_rotation(left_forearm)
							skeleton.set_bone_pose_rotation(left_forearm, anim_rot.slerp(Quaternion.IDENTITY, w))
						if right_arm != -1:
							var anim_rot = skeleton.get_bone_pose_rotation(right_arm)
							var target_rot = Quaternion.from_euler(Vector3(0.0, deg_to_rad(-60.0), deg_to_rad(-60.0)))
							skeleton.set_bone_pose_rotation(right_arm, anim_rot.slerp(target_rot, w))
						if right_forearm != -1:
							var anim_rot = skeleton.get_bone_pose_rotation(right_forearm)
							skeleton.set_bone_pose_rotation(right_forearm, anim_rot.slerp(Quaternion.IDENTITY, w))

func _board_raycast(screen_pos: Vector2, collision_mask: int) -> Dictionary:
	if not is_instance_valid(camera):
		return {}
	var ray_origin: Vector3 = camera.project_ray_origin(screen_pos)
	var ray_normal: Vector3 = camera.project_ray_normal(screen_pos)
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_normal * 100.0)
	query.collision_mask = collision_mask
	query.collide_with_areas = true
	query.collide_with_bodies = false
	return space_state.intersect_ray(query)

func _is_chicken_collider(collider: Object) -> bool:
	if not is_instance_valid(_chicken_node) or collider == null:
		return false
	if collider == _chicken_area:
		return true
	return collider.get_parent() == _chicken_node

func _set_chicken_hover(active: bool) -> void:
	if active == _hovered_chicken:
		return
	_hovered_chicken = active
	if active and is_instance_valid(_cabinet_prompt_label):
		_cabinet_prompt_label.text = "[CLICK] Buy ability ($50)"
		_cabinet_prompt_label.show()
	elif not active and is_instance_valid(_cabinet_prompt_label) and _hovered_hammer_idx_board < 0 \
			and _hovered_shelf_index < 0:
		_cabinet_prompt_label.hide()

func _update_cabinet_hover() -> void:
	if not is_instance_valid(camera):
		return
	
	var screen_pos := _get_screen_ray_position()
	var ray_origin: Vector3 = camera.project_ray_origin(screen_pos)
	var ray_normal: Vector3 = camera.project_ray_normal(screen_pos)
	var space_state := get_world_3d().direct_space_state
	
	# --- PASS 1: Hammer detection on layer 16 ---
	# Layer 16 is ONLY for hammers. The shelf Area3D (layer 8) is invisible to this raycast,
	# so the ray passes through the shelf box and hits the hammer Area3D directly.
	var q_hammer := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_normal * 100.0)
	q_hammer.collision_mask = 16
	q_hammer.collide_with_areas = true
	q_hammer.collide_with_bodies = false
	var r_hammer := space_state.intersect_ray(q_hammer)
	
	if r_hammer and r_hammer.collider:
		var collider = r_hammer.collider
		if collider.has_meta("hammer_index"):
			var h_idx: int = collider.get_meta("hammer_index")
			var h_player_idx: int = collider.get_meta("player_index", -1)
			# Only local player can hover/click their own hammers
			if h_player_idx == _human_ui_idx():
				var cab_node = _cabinets.get(h_player_idx)
				if is_instance_valid(cab_node):
					if _hovered_hammer_idx_board != h_idx or _hovered_hammer_cabinet != cab_node:
						if _hovered_hammer_cabinet != null and is_instance_valid(_hovered_hammer_cabinet):
							_hovered_hammer_cabinet.unhover_hammer(_hovered_hammer_idx_board)
						_hovered_hammer_idx_board = h_idx
						_hovered_hammer_cabinet = cab_node
						cab_node.hover_hammer(h_idx)
					
					var abilities = GameManager.players_info[h_player_idx].abilities
					var ab_id = abilities[h_idx] if h_idx < abilities.size() else ""
					
					# Show ability name in prompt
					if is_instance_valid(_cabinet_prompt_label) and ab_id != "":
						var ab_name = ab_id.capitalize().replace("_", " ")
						_cabinet_prompt_label.text = "[E] / [CLICK] Use %s" % ab_name
						_cabinet_prompt_label.show()
						
					# Show description in the bottom-right corner
					if is_instance_valid(_ability_desc_panel) and ab_id != "":
						var desc_label = _ability_desc_panel.get_node_or_null("DescLabel")
						if desc_label:
							desc_label.text = _get_ability_desc(ab_id)
						_ability_desc_panel.show()
						
					_set_chicken_hover(false)
					return  # Hammer handled; skip drawer detection this frame
	
	# Not hovering a hammer this frame — unhover if we were before
	if _hovered_hammer_idx_board >= 0 and is_instance_valid(_hovered_hammer_cabinet):
		_hovered_hammer_cabinet.unhover_hammer(_hovered_hammer_idx_board)
		_hovered_hammer_idx_board = -1
		_hovered_hammer_cabinet = null
		if is_instance_valid(_cabinet_prompt_label):
			_cabinet_prompt_label.hide()
		if is_instance_valid(_ability_desc_panel):
			_ability_desc_panel.hide()
	
	# --- PASS 2: Chicken purchase (dedicated layer; follows mouse, not screen center) ---
	if GameManager.current_player_index == _human_ui_idx():
		var r_chicken := _board_raycast(screen_pos, COLLISION_LAYER_CHICKEN)
		if r_chicken and _is_chicken_collider(r_chicken.collider):
			_set_chicken_hover(true)
			return
	_set_chicken_hover(false)
	
	# --- PASS 3: Drawer detection on layer 8 ---
	var q_drawer := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_normal * 100.0)
	q_drawer.collision_mask = 8
	q_drawer.collide_with_areas = true
	q_drawer.collide_with_bodies = false
	var r_drawer := space_state.intersect_ray(q_drawer)
	
	var new_hover_idx := -1
	var new_hover_cabinet: Node = null
	
	if r_drawer and r_drawer.collider:
		var collider = r_drawer.collider
		var hit_dist: float = ray_origin.distance_to(r_drawer.position as Vector3)
		if collider.has_meta("shelf_index"):
			var candidate_idx: int = collider.get_meta("shelf_index")
			var candidate_cab: Node = null
			var node = collider
			while node:
				if node.has_method("toggle_shelf"):
					candidate_cab = node
					break
				node = node.get_parent()
			# Determine owner of this cabinet
			var cab_owner := -1
			for pi in _cabinets:
				if _cabinets[pi] == candidate_cab:
					cab_owner = pi
					break
			# Own cabinet: always reachable. Others: 4.5m limit.
			if cab_owner == GameManager.local_player_idx or hit_dist <= 4.5:
				new_hover_idx = candidate_idx
				new_hover_cabinet = candidate_cab
	
	if new_hover_idx != _hovered_shelf_index or new_hover_cabinet != _hovered_cabinet_node:
		_hovered_shelf_index = new_hover_idx
		_hovered_cabinet_node = new_hover_cabinet
		_update_cabinet_prompt()

func _update_cabinet_prompt() -> void:
	if not is_instance_valid(_cabinet_prompt_label):
		return
		
	if _hovered_shelf_index == -1 or not is_instance_valid(_hovered_cabinet_node):
		_cabinet_prompt_label.hide()
		return
		
	if is_instance_valid(_ability_desc_panel):
		_ability_desc_panel.hide()
		
	var is_open = _hovered_cabinet_node.is_shelf_open(_hovered_shelf_index)
	var shelf_name = _hovered_cabinet_node.get_shelf_name(_hovered_shelf_index)
	var action_text = "Close" if is_open else "Open"
	_cabinet_prompt_label.text = "[E] %s %s" % [action_text, shelf_name]
	
	_cabinet_prompt_label.show()
	_cabinet_prompt_label.modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(_cabinet_prompt_label, "modulate:a", 1.0, 0.15)

func _get_ability_desc(ab: String) -> String:
	match ab:
		"bottoms_up": return "Bottoms Up:\nForces the target player to drink a beer."
		"refuel": return "Refuel:\nGives you 1 beer back (up to max 3)."
		"trim_off": return "Trim Off:\nDiscards the highest value card from your own hand (earns money)."
		"boulder": return "Boulder:\nTakes the highest value card from the deck and adds it to the target's hand."
		"reverse": return "Reverse:\nReverses the direction of player turns."
		"skip": return "Skip:\nSkips the target player's next turn."
		"perfect_match": return "Perfect Match:\nResets the round, deals Ace, 2, 3, 4 to you, deals 4 cards to everyone else, and restarts peeking."
		"inflation": return "Inflation:\nMultiplies the point value of all cards in the target's hand by 2.0."
		"half_off": return "Half Off:\nDivides the point value of all cards in the target's hand by 2.0."
		"jumpscare": return "Jumpscare:\nDraws a card from the deck and adds it to the target's hand."
		"shuffle": return "Shuffle:\nShuffles the order of cards in the target's hand."
		"polarity_shift": return "Polarity Shift:\nFlips the win condition (toggles between Lowest Wins and Highest Wins)."
	return ""

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
	if DevConsole and DevConsole.window.visible:
		return
		
	if event is InputEventMouseMotion:
		if noclip_enabled:
			camera_rot_y -= event.relative.x * 0.005
			camera_rot_x -= event.relative.y * 0.005
			camera_rot_x = clamp(camera_rot_x, -PI / 2, PI / 2)
			camera.basis = Basis() # Reset
			camera.rotate_y(camera_rot_y)
			camera.rotate_object_local(Vector3.RIGHT, camera_rot_x)
		elif Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			_handle_touch_look(event.relative)
	elif event is InputEventScreenTouch:
		if event.pressed:
			_touch_positions[event.index] = event.position
			_touch_tap_starts[event.index] = event.position
		else:
			if event.index == 0 and not _touch_look_active:
				var start_pos: Vector2 = _touch_tap_starts.get(0, event.position)
				if start_pos.distance_to(event.position) <= ResponsiveUI.get_touch_slop():
					_handle_touch_tap(event.position)
			_touch_positions.erase(event.index)
			_touch_tap_starts.erase(event.index)
			if _touch_positions.size() < 2:
				_touch_look_active = false
	elif event is InputEventScreenDrag:
		_touch_positions[event.index] = event.position
		if _touch_positions.size() >= 2:
			_touch_look_active = true
			_handle_touch_look(event.relative)

func _on_jack_swap_resolved(p1: int, c1: int, p2: int, c2: int) -> void:
	play_take_animation(GameManager.current_player_index)
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
	_hide_jack_swap_ui()


func _jack_swap_target_hint() -> String:
	var parts: PackedStringArray = []
	var human_idx := _human_ui_idx()
	for i in range(GameManager.num_players):
		if i >= GameManager.players_info.size():
			continue
		if GameManager.players_info[i].is_eliminated:
			continue
		if i == human_idx:
			parts.append("your hand")
		else:
			parts.append(GameManager.players_info[i].name)
	if parts.is_empty():
		return "any face-down card on the table"
	return ", ".join(parts)

func _update_jack_swap_banner(selected_count: int) -> void:
	if GameManager.current_state != GameManager.GameState.TURN_SWAP_ABILITY \
			or GameManager.active_ability_player != _human_ui_idx():
		return
	if not is_instance_valid(_jack_swap_banner):
		_jack_swap_banner = Label.new()
		_jack_swap_banner.name = "JackSwapBanner"
		_jack_swap_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_jack_swap_banner.add_theme_font_size_override("font_size", 26)
		_jack_swap_banner.add_theme_color_override("font_color", Color(1.0, 0.55, 0.75))
		_jack_swap_banner.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
		_jack_swap_banner.add_theme_constant_override("shadow_offset_x", 2)
		_jack_swap_banner.add_theme_constant_override("shadow_offset_y", 2)
		_jack_swap_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_jack_swap_banner.offset_top = 118.0
		_jack_swap_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		$GameUI/MainHUD.add_child(_jack_swap_banner)
	if selected_count <= 0:
		_jack_swap_banner.text = "JACK: Click 2 face-down cards — yours OR another player's hand!"
	elif selected_count == 1 and not swap_sources.is_empty():
		var s0: Dictionary = swap_sources[0]
		var who := "your hand"
		var p0: int = int(s0.get("player", -1))
		if p0 >= 0 and p0 != _human_ui_idx() and p0 < GameManager.players_info.size():
			who = String(GameManager.players_info[p0].name)
		_jack_swap_banner.text = "JACK: 1/2 — first from %s — click another face-down card (any player)" % who
	elif selected_count == 1:
		_jack_swap_banner.text = "JACK: 1/2 selected — click a second card (any player, face-down)"
	else:
		_jack_swap_banner.text = "JACK: Swapping..."
	_jack_swap_banner.show()

func _hide_jack_swap_ui() -> void:
	var old_alert = $GameUI/MainHUD.get_node_or_null("JackSwapAlert")
	if old_alert:
		old_alert.queue_free()
	if is_instance_valid(_jack_swap_banner):
		_jack_swap_banner.queue_free()
		_jack_swap_banner = null

func _show_jack_swap_alert() -> void:
	var old_alert = $GameUI/MainHUD.get_node_or_null("JackSwapAlert")
	if old_alert:
		old_alert.queue_free()

	var targets := _jack_swap_target_hint()
	var center = CenterContainer.new()
	center.name = "JackSwapAlert"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$GameUI/MainHUD.add_child(center)

	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.02, 0.08, 0.92)
	style.border_width_left = 5
	style.border_width_right = 5
	style.border_width_top = 5
	style.border_width_bottom = 5
	style.border_color = Color(0.95, 0.25, 0.45)
	style.corner_radius_top_left = 14
	style.corner_radius_top_right = 14
	style.corner_radius_bottom_left = 14
	style.corner_radius_bottom_right = 14
	style.shadow_color = Color(0.95, 0.2, 0.4, 0.4)
	style.shadow_size = 22
	style.content_margin_left = 36
	style.content_margin_right = 36
	style.content_margin_top = 22
	style.content_margin_bottom = 22
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var title = Label.new()
	title.text = "JACK PLAYED!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	vbox.add_child(title)

	var headline = Label.new()
	headline.text = "SWAP ANY TWO FACE-DOWN CARDS"
	headline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	headline.add_theme_font_size_override("font_size", 40)
	headline.add_theme_color_override("font_color", Color(1.0, 0.45, 0.65))
	headline.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	headline.add_theme_constant_override("shadow_offset_x", 2)
	headline.add_theme_constant_override("shadow_offset_y", 2)
	vbox.add_child(headline)

	var body = Label.new()
	body.text = "Click cards on the table — including other players' hands.\nValid targets: %s" % targets
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(560, 0)
	body.add_theme_font_size_override("font_size", 22)
	body.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0))
	vbox.add_child(body)

	var hint = Label.new()
	hint.text = "Nobody sees what was swapped — pick 2 cards, then they trade places"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", Color(0.75, 1.0, 0.9))
	vbox.add_child(hint)

	_show_message("Jack: select 2 face-down cards (yours or an opponent's)")
	shake(0.2, 0.3)

	center.modulate.a = 0.0
	center.scale = Vector2(0.92, 0.92)
	var intro = create_tween().set_parallel(true)
	intro.tween_property(center, "modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	intro.tween_property(center, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	var fade = create_tween()
	fade.tween_interval(4.5)
	fade.tween_property(center, "modulate:a", 0.0, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fade.tween_callback(center.queue_free)

func _on_all_cards_revealed() -> void:
	_update_turn_lights(-1, true)
	if not _victory_cinematic_active:
		_run_victory_cinematic()

func _build_victory_reveal_queue(winner_id: int) -> Array:
	var others: Array = []
	var winner_cards: Array = []
	for p_idx in range(GameManager.num_players):
		if p_idx >= player_hands.size():
			continue
		for c3d in player_hands[p_idx]:
			if not is_instance_valid(c3d) or not (c3d is Card3D):
				continue
			if p_idx == winner_id:
				winner_cards.append(c3d)
			else:
				others.append(c3d)
	if others.is_empty() and winner_cards.is_empty():
		for pos_node in player_pos_nodes.values():
			for c3d in pos_node.get_children():
				if c3d is Card3D and (c3d.data == null or not c3d.data.is_face_up):
					others.append(c3d)
	return others + winner_cards

func _play_victory_reveal_sequence(winner_id: int = 0) -> void:
	var cards_to_flip: Array = _build_victory_reveal_queue(winner_id)
	if cards_to_flip.is_empty():
		Engine.time_scale = 1.0
		return

	Engine.time_scale = 0.4
	var last_idx: int = cards_to_flip.size() - 1
	for i in range(cards_to_flip.size()):
		var c3d: Card3D = cards_to_flip[i]
		if not is_instance_valid(c3d):
			continue
		var is_climax := i == last_idx
		if is_climax:
			Engine.time_scale = 0.12
			GameManager.play_sfx(_victory_fanfare_stream)
			shake(0.25, 0.55)
			trigger_glitch(0.35, 0.8)
			if player_pos_nodes.has(winner_id):
				spawn_particles("dutch", player_pos_nodes[winner_id].global_position + Vector3(0, 1.0, 0))
		c3d.is_being_peeked = true
		c3d.animate_flip(true)
		spawn_particles("card_flip", c3d.global_position + Vector3(0, 0.15, 0))
		var delay := 0.55 if is_climax else 0.16
		await get_tree().create_timer(delay, true, false, true).timeout
		c3d.is_being_peeked = false

	await get_tree().create_timer(0.45, true, false, true).timeout
	Engine.time_scale = 1.0

func _toggle_emote_wheel() -> void:
	if pause_menu_instance != null:
		return
	if GameManager.current_state == GameManager.GameState.GAME_OVER:
		return
	if _emote_wheel_open:
		_close_emote_wheel()
	else:
		_open_emote_wheel()

func _open_emote_wheel() -> void:
	if pause_menu_instance != null:
		return
	if GameManager.current_state == GameManager.GameState.GAME_OVER:
		return
	_emote_wheel_open = true
	if is_instance_valid(_assistant_overlay):
		_assistant_overlay.close_panel()
	if is_instance_valid(_emote_wheel_panel):
		_emote_wheel_panel.visible = true
	if is_instance_valid(_emote_toggle_btn):
		_emote_toggle_btn.text = "CLOSE [T]"
	_apply_gameplay_mouse_mode()

func _close_emote_wheel() -> void:
	_emote_wheel_open = false
	if is_instance_valid(_emote_wheel_panel):
		_emote_wheel_panel.visible = false
	if is_instance_valid(_emote_toggle_btn):
		_emote_toggle_btn.text = "EMOTE [T]"
	_apply_gameplay_mouse_mode()

func _on_emote_wheel_pressed(emote_id: String) -> void:
	if not GameManager.request_emote(emote_id):
		return
	_close_emote_wheel()

func _on_victory_emote_pressed(winner_id: int, emote_id: String) -> void:
	GameManager.emit_player_emote(winner_id, emote_id, false)

func _on_player_emoted(player_idx: int, emote_id: String) -> void:
	_play_player_emote(player_idx, emote_id)

func _update_emote_wheel_state() -> void:
	if not is_instance_valid(_emote_wheel_panel):
		return
	var in_game := GameManager.current_state != GameManager.GameState.GAME_OVER \
			and GameManager.current_state != GameManager.GameState.INITIALIZING
	var assistant_available := in_game and pause_menu_instance == null
	if is_instance_valid(_assistant_overlay):
		_assistant_overlay.set_available(assistant_available and GameManager.show_game_assistant)
	if not in_game or pause_menu_instance != null:
		if _emote_wheel_open:
			_close_emote_wheel()
		if is_instance_valid(_emote_toggle_btn):
			_emote_toggle_btn.visible = false
		return
	if is_instance_valid(_emote_toggle_btn):
		_emote_toggle_btn.visible = true

	var remaining := GameManager.get_emote_cooldown_remaining(_human_ui_idx())
	var on_cooldown := remaining > 0.0
	for btn in _emote_buttons:
		if is_instance_valid(btn):
			btn.disabled = on_cooldown
	if is_instance_valid(_emote_toggle_btn):
		_emote_toggle_btn.disabled = on_cooldown
		if on_cooldown:
			_emote_toggle_btn.text = "WAIT %.1fs" % remaining
		else:
			_emote_toggle_btn.text = "CLOSE [T]" if _emote_wheel_open else "EMOTE [T]"
	if is_instance_valid(_emote_cooldown_label):
		if on_cooldown:
			_emote_cooldown_label.text = "%.1fs" % remaining
		else:
			_emote_cooldown_label.text = ""

func _emote_glyph(emote_id: String) -> String:
	for emote in GAME_EMOTES:
		if emote.id == emote_id:
			return emote.glyph
	return "?"

func _show_emote_bubble(player_idx: int, emote_id: String) -> void:
	var seat := _get_safe_player_pos(player_idx)
	if not seat:
		return
	var bubble := Label3D.new()
	bubble.text = _emote_glyph(emote_id)
	bubble.font_size = 88
	bubble.outline_size = 12
	bubble.outline_modulate = Color(0, 0, 0, 0.85)
	bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bubble.modulate = Color(1.0, 0.95, 0.55)
	bubble.position = Vector3(0, 1.35, 0)
	seat.add_child(bubble)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(bubble, "position:y", 1.85, 0.75).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(bubble, "modulate:a", 0.0, 1.0).set_delay(0.55)
	tw.chain().tween_callback(bubble.queue_free)

func _play_player_emote(player_idx: int, emote_id: String) -> void:
	if player_idx < 0 or player_idx >= 4:
		return
	play_take_animation(player_idx)
	_show_emote_bubble(player_idx, emote_id)
	var seat := _get_safe_player_pos(player_idx)
	if seat:
		var burst_pos := seat.global_position + Vector3(0, 1.0, 0)
		match emote_id:
			"chicken":
				spawn_particles("ability_buy", burst_pos)
			"shock":
				spawn_particles("jumpscare", burst_pos)
				trigger_glitch(0.2, 0.25)
			"laugh":
				spawn_particles("beer_drink", burst_pos)
			_:
				spawn_particles("turn_change", burst_pos)
	shake(0.12, 0.2)

func _on_jumpscare_triggered(_caster_idx: int, target_idx: int) -> void:
	var target_name = GameManager.players_info[target_idx].name if target_idx < GameManager.players_info.size() else "Player"
	_show_message("JUMPSCARE! " + target_name + " got spooked!")
	_play_jumpscare_vfx(target_idx)

func _play_jumpscare_vfx(target_idx: int) -> void:
	var flash_layer = CanvasLayer.new()
	flash_layer.layer = 120
	add_child(flash_layer)
	var flash = ColorRect.new()
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.color = Color(1.0, 1.0, 1.0, 0.95)
	flash_layer.add_child(flash)
	var flash_tween = create_tween()
	flash_tween.tween_property(flash, "color:a", 0.0, 0.12).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	flash_tween.tween_callback(flash_layer.queue_free)
	shake(0.65, 0.45)
	trigger_glitch(1.0, 0.9)
	if player_pos_nodes.has(target_idx) and is_instance_valid(player_pos_nodes[target_idx]):
		spawn_particles("jumpscare", player_pos_nodes[target_idx].global_position + Vector3(0, 1.0, 0))
		var hand = player_hands[target_idx] if target_idx < player_hands.size() else []
		if not hand.is_empty():
			var scare_card = hand[randi() % hand.size()]
			if is_instance_valid(scare_card):
				scare_card.animate_flip(true)
				await get_tree().create_timer(0.6).timeout
				if is_instance_valid(scare_card):
					scare_card.animate_flip(false)

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
		if is_instance_valid(camera):
			camera.near = 0.05
	else:
		camera.global_transform = base_camera_transform
		_look_yaw = 0.0
		_look_pitch = 0.0
	_apply_gameplay_mouse_mode()
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

func _format_ability_name(ab: String) -> String:
	return ab.capitalize().replace("_", " ")

func _show_ability_purchase_alert(display_name: String, ab_id: String) -> void:
	var old_alert = $GameUI/MainHUD.get_node_or_null("AbilityPurchaseAlert")
	if old_alert:
		old_alert.queue_free()

	var center = CenterContainer.new()
	center.name = "AbilityPurchaseAlert"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$GameUI/MainHUD.add_child(center)

	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.05, 0.0, 0.92)
	style.border_width_left = 5
	style.border_width_right = 5
	style.border_width_top = 5
	style.border_width_bottom = 5
	style.border_color = Color(1.0, 0.82, 0.15)
	style.corner_radius_top_left = 14
	style.corner_radius_top_right = 14
	style.corner_radius_bottom_left = 14
	style.corner_radius_bottom_right = 14
	style.shadow_color = Color(1.0, 0.75, 0.0, 0.45)
	style.shadow_size = 24
	style.content_margin_left = 36
	style.content_margin_right = 36
	style.content_margin_top = 22
	style.content_margin_bottom = 22
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var title = Label.new()
	title.text = "NEW ABILITY!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.25))
	vbox.add_child(title)

	var name_label = Label.new()
	name_label.text = display_name.to_upper()
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 44)
	name_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.55))
	name_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	name_label.add_theme_constant_override("shadow_offset_x", 2)
	name_label.add_theme_constant_override("shadow_offset_y", 2)
	vbox.add_child(name_label)

	var desc := _get_ability_desc(ab_id)
	if desc != "":
		var desc_label = Label.new()
		desc_label.text = desc.get_slice("\n", 0)
		desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_label.custom_minimum_size = Vector2(520, 0)
		desc_label.add_theme_font_size_override("font_size", 20)
		desc_label.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
		vbox.add_child(desc_label)

	var hint = Label.new()
	hint.text = "Added to your cabinet — click the hammer to use it"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", Color(0.65, 1.0, 0.85))
	vbox.add_child(hint)

	_show_message("Purchased: " + display_name + " ($50) — check your cabinet")
	shake(0.25, 0.35)

	center.modulate.a = 0.0
	center.scale = Vector2(0.92, 0.92)
	var intro = create_tween().set_parallel(true)
	intro.tween_property(center, "modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	intro.tween_property(center, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	var fade = create_tween()
	fade.tween_interval(4.0)
	fade.tween_property(center, "modulate:a", 0.0, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fade.tween_callback(center.queue_free)

func _play_ability_purchase_flash() -> void:
	var flash_layer = CanvasLayer.new()
	flash_layer.layer = 119
	add_child(flash_layer)
	var flash = ColorRect.new()
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.color = Color(1.0, 0.82, 0.15, 0.28)
	flash_layer.add_child(flash)
	var flash_tween = create_tween()
	flash_tween.tween_property(flash, "color:a", 0.0, 0.35).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	flash_tween.tween_callback(flash_layer.queue_free)

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

		"beer_spill":
			particles.amount = 45
			particles.lifetime = 1.0
			particles.spread = 70.0
			particles.direction = Vector3(0, -0.3, 0.6)
			particles.gravity = Vector3(0, -2.5, 0)
			particles.initial_velocity_min = 0.8
			particles.initial_velocity_max = 2.2
			particles.color = Color(0.85, 0.65, 0.15, 0.85)
			grad.set_color(0, Color(0.9, 0.7, 0.2, 0.9))
			grad.set_color(1, Color(0.5, 0.35, 0.05, 0.0))
			mesh.size = Vector2(0.1, 0.1)

		"jumpscare":
			particles.amount = 55
			particles.lifetime = 0.5
			particles.spread = 180.0
			particles.gravity = Vector3(0, -1.5, 0)
			particles.initial_velocity_min = 3.0
			particles.initial_velocity_max = 7.0
			particles.color = Color(1.0, 0.15, 0.15, 1.0)
			grad.set_color(0, Color(1.0, 0.2, 0.2, 1.0))
			grad.set_color(1, Color(0.3, 0.0, 0.0, 0.0))
			mesh.size = Vector2(0.16, 0.16)
			
		"ability_buy":
			particles.amount = 48
			particles.lifetime = 0.85
			particles.spread = 140.0
			particles.direction = Vector3.UP
			particles.gravity = Vector3(0, -2.5, 0) # Coins fall down
			particles.initial_velocity_min = 2.5
			particles.initial_velocity_max = 5.0
			particles.color = Color(1.0, 0.9, 0.0) # Gold coins
			grad.set_color(0, Color(1.0, 0.95, 0.2, 1.0))
			grad.set_color(1, Color(0.8, 0.5, 0.0, 0.0))
			mesh.size = Vector2(0.11, 0.11)
			
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

		"card_trail":
			particles.amount = 22
			particles.lifetime = 0.45
			particles.spread = 70.0
			particles.direction = Vector3(0, 0.2, 0)
			particles.gravity = Vector3(0, -1.0, 0)
			particles.initial_velocity_min = 0.8
			particles.initial_velocity_max = 2.0
			particles.color = Color(0.35, 0.82, 1.0)
			grad.set_color(0, Color(0.5, 0.9, 1.0, 0.9))
			grad.set_color(1, Color(0.05, 0.15, 0.4, 0.0))
			mesh.size = Vector2(0.07, 0.1)

		"turn_change":
			particles.amount = 50
			particles.lifetime = 0.9
			particles.spread = 160.0
			particles.direction = Vector3.UP
			particles.gravity = Vector3(0, -0.4, 0)
			particles.initial_velocity_min = 1.5
			particles.initial_velocity_max = 3.5
			particles.color = Color(0.0, 1.0, 1.0)
			grad.set_color(0, Color(0.2, 1.0, 1.0, 1.0))
			grad.set_color(0.5, Color(0.9, 0.2, 1.0, 0.8))
			grad.set_color(1, Color(0.1, 0.0, 0.4, 0.0))
			mesh.size = Vector2(0.12, 0.12)
			
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

func _generate_victory_fanfare_stream() -> AudioStreamWAV:
	var stream = AudioStreamWAV.new()
	stream.mix_rate = 44100
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.stereo = false

	var mix_rate = 44100.0
	var duration = 2.4
	var total_samples = int(mix_rate * duration)
	var byte_array = PackedByteArray()
	byte_array.resize(total_samples * 2)

	var notes = [
		{"freq": 392.0, "start": 0.0, "len": 0.3, "amp": 0.28},
		{"freq": 523.25, "start": 0.0, "len": 0.35, "amp": 0.4},
		{"freq": 659.25, "start": 0.28, "len": 0.35, "amp": 0.42},
		{"freq": 783.99, "start": 0.56, "len": 0.45, "amp": 0.45},
		{"freq": 1046.5, "start": 0.95, "len": 0.95, "amp": 0.52},
		{"freq": 1318.5, "start": 1.55, "len": 0.75, "amp": 0.4},
		{"freq": 1568.0, "start": 1.85, "len": 0.45, "amp": 0.32},
	]

	for s in range(total_samples):
		var t = s / mix_rate
		var sample = 0.0
		for note in notes:
			var note_t = t - note.start
			if note_t >= 0.0 and note_t < note.len:
				var env = exp(-3.5 * note_t) * (1.0 - note_t / note.len)
				sample += note.amp * sin(2.0 * PI * note.freq * note_t) * env
				sample += note.amp * 0.25 * sin(2.0 * PI * note.freq * 2.0 * note_t) * env
		if t > duration - 0.2:
			sample *= (duration - t) / 0.2
		sample = clamp(sample, -1.0, 1.0)
		byte_array.encode_s16(s * 2, int(sample * 32767.0))

	stream.data = byte_array
	return stream

var _hovered_board_card: Card3D = null

func _apply_gameplay_mouse_mode() -> void:
	if pause_menu_instance != null or GameManager.current_state == GameManager.GameState.GAME_OVER:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if _emote_wheel_open:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if GameManager.current_state == GameManager.GameState.TURN_CONFIRM_DUTCH \
			and GameManager.can_player_confirm_dutch(_human_ui_idx()):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if noclip_enabled:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if ResponsiveUI.is_touch_device():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED

func _get_screen_ray_position() -> Vector2:
	if ResponsiveUI.is_touch_device() and _touch_positions.has(0) and not _touch_look_active:
		return _touch_positions[0]
	var viewport_size := get_viewport().get_visible_rect().size
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		return viewport_size / 2.0
	return get_viewport().get_mouse_position()

func _handle_touch_look(delta: Vector2) -> void:
	_look_yaw -= delta.x * 0.0025
	_look_pitch -= delta.y * 0.0025
	_look_yaw = clamp(_look_yaw, deg_to_rad(-105.0), deg_to_rad(105.0))
	_look_pitch = clamp(_look_pitch, deg_to_rad(-50.0), deg_to_rad(22.0))

func _handle_touch_tap(screen_pos: Vector2) -> void:
	if _is_mouse_over_hud(screen_pos):
		return
	if _handle_board_click_at_screen(screen_pos):
		return

func _is_mouse_over_hud(screen_pos: Vector2) -> bool:
	if is_instance_valid(action_panel) and action_panel.get_global_rect().has_point(screen_pos):
		return true
	if _emote_wheel_open and is_instance_valid(_emote_wheel_panel) \
			and _emote_wheel_panel.get_global_rect().has_point(screen_pos):
		return true
	if is_instance_valid(_emote_toggle_btn) and _emote_toggle_btn.visible \
			and _emote_toggle_btn.get_global_rect().has_point(screen_pos):
		return true
	if is_instance_valid(_assistant_overlay) and _assistant_overlay.consumes_point(screen_pos):
		return true
	return false

func _handle_board_click_at_screen(screen_pos: Vector2) -> bool:
	if not is_instance_valid(camera):
		return false

	# Chickens + hammers first so table cards do not steal the click.
	if GameManager.current_player_index == _human_ui_idx():
		var r_chicken := _board_raycast(screen_pos, COLLISION_LAYER_CHICKEN)
		if r_chicken and _is_chicken_collider(r_chicken.collider):
			_try_buy_ability(_human_ui_idx())
			return true

	if _hovered_hammer_idx_board >= 0 and is_instance_valid(_hovered_hammer_cabinet):
		play_take_animation(_human_ui_idx())
		_use_hovered_hammer()
		return true

	var result16 := _board_raycast(screen_pos, 16)
	if result16 and result16.collider and result16.collider.has_meta("hammer_index"):
		var owner_idx: int = result16.collider.get_meta("player_index", -1)
		if owner_idx == _human_ui_idx():
			play_take_animation(_human_ui_idx())
			_on_hammer_clicked(result16.collider)
			return true

	var result := _board_raycast(screen_pos, 1)
	if result and result.collider:
		var col = result.collider
		var parent = col.get_parent()
		if parent is Card3D:
			_on_card_clicked(parent, parent.data)
			return true
		if col.get_parent() == $DeckArea and $DeckArea/Area3D.input_ray_pickable:
			_on_deck_clicked()
			return true
		if col.get_parent() == $DiscardArea and $DiscardArea/Area3D.input_ray_pickable:
			_on_discard_clicked()
			return true
		if col.name == "TargetArea" and col.input_ray_pickable:
			var player_idx: int = col.get_meta("player_index", -1)
			if player_idx != -1:
				_on_player_area_input(null, null, Vector3.ZERO, Vector3.ZERO, 0, player_idx)
				return true
	return false

func _update_crosshair_raycast() -> void:
	if not is_instance_valid(camera) or noclip_enabled:
		if is_instance_valid(_hovered_board_card):
			_on_card_hover_exit(_hovered_board_card)
			_hovered_board_card = null
		return

	var screen_pos := _get_screen_ray_position()
	if _is_mouse_over_hud(screen_pos):
		if is_instance_valid(_hovered_board_card):
			_on_card_hover_exit(_hovered_board_card)
			_hovered_board_card = null
		return

	var ray_origin: Vector3 = camera.project_ray_origin(screen_pos)
	var ray_normal: Vector3 = camera.project_ray_normal(screen_pos)

	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_normal * 100.0)
	query.collision_mask = 1
	query.collide_with_areas = true
	query.collide_with_bodies = false

	var result := space_state.intersect_ray(query)
	var hit_card: Card3D = null
	
	if result and result.collider:
		var col = result.collider
		var parent = col.get_parent()
		if parent is Card3D:
			hit_card = parent
			
	if hit_card != _hovered_board_card:
		if is_instance_valid(_hovered_board_card):
			_on_card_hover_exit(_hovered_board_card)
		_hovered_board_card = hit_card
		if is_instance_valid(_hovered_board_card):
			_on_card_hover_enter(_hovered_board_card)

func _spawn_player_avatars() -> void:
	var char_scene = load("res://assets/models/animatii/idle.glb")
	var take_scene = load("res://assets/models/animatii/take.glb")
	if not char_scene or not take_scene:
		push_error("GameBoard3D: Could not load character/take animation model!")
		return

	var take_inst = take_scene.instantiate()
	var take_ap: AnimationPlayer = take_inst.get_node("AnimationPlayer")
	var take_anim = take_ap.get_animation("Armature|mixamo_com|Layer0_001")
	if not take_anim:
		push_error("GameBoard3D: Take animation not found in take.glb!")
		take_inst.queue_free()
		return

	var chairs = {
		0: get_node_or_null("Sketchfab_Scene"),  # Bottom (Player 0)
		1: get_node_or_null("Sketchfab_Scene4"), # Left (Player 1)
		2: get_node_or_null("Sketchfab_Scene3"), # Top (Player 2)
		3: get_node_or_null("Sketchfab_Scene2")  # Right (Player 3)
	}

	# Move the chairs slightly further back from the table to accommodate first-person view spacing
	if is_instance_valid(chairs[0]): chairs[0].position.z += 0.5
	if is_instance_valid(chairs[1]): chairs[1].position.x -= 0.5
	if is_instance_valid(chairs[2]): chairs[2].position.z -= 0.5
	if is_instance_valid(chairs[3]): chairs[3].position.x += 0.5

	var chair_rotations = {
		0: 90.0,
		1: 90.0,
		2: 90.0,
		3: 90.0
	}

	for i in range(4):
		var chair = chairs[i]
		var seat: Node3D = player_pos_nodes.get(i) as Node3D
		if not is_instance_valid(chair) or not is_instance_valid(seat):
			continue

		var char_node = char_scene.instantiate()
		chair.add_child(char_node)

		# Position character on the seat, then reparent under PlayerPositions so MP seat rotation shows opponents correctly.
		char_node.position = Vector3(0.0, 0.025, 0.0)
		char_node.scale = Vector3(4.5/43.0, 4.5/43.0, 4.5/43.0)
		char_node.rotation_degrees = Vector3(0.0, chair_rotations[i], 0.0)

		# Set up AnimationPlayer
		var ap: AnimationPlayer = char_node.get_node("AnimationPlayer")
		if ap:
			var lib = ap.get_animation_library("")
			if lib:
				lib.add_animation("take", take_anim)
				var idle_orig = "Armature|mixamo_com|Layer0"
				if lib.has_animation(idle_orig):
					var idle_anim = lib.get_animation(idle_orig)
					idle_anim.loop_mode = Animation.LOOP_LINEAR
					lib.add_animation("idle", idle_anim)
					lib.remove_animation(idle_orig)
			ap.play("idle")
			ap.set_blend_time("idle", "take", 0.3)
			ap.set_blend_time("take", "idle", 0.3)

		var avatar_global: Transform3D = char_node.global_transform
		char_node.reparent(seat)
		char_node.global_transform = avatar_global

		player_avatars[i] = char_node
		avatar_arm_weights[i] = 1.0

	take_inst.queue_free()
	_refresh_avatar_body_visibility()

func _refresh_avatar_body_visibility() -> void:
	var local_idx := _human_ui_idx()
	var seat_count := clampi(GameManager.num_players, 1, 4) if GameManager.is_multiplayer else 4
	for p_idx in player_avatars:
		var avatar: Node3D = player_avatars[p_idx]
		if not is_instance_valid(avatar):
			continue
		if p_idx >= seat_count:
			avatar.visible = false
			_set_avatar_body_visible(avatar, false)
			continue
		if GameManager.is_multiplayer and p_idx == local_idx:
			avatar.visible = false
			_set_avatar_body_visible(avatar, false)
		else:
			avatar.visible = true
			_set_avatar_body_visible(avatar, true)

func get_avatar_visibility_report() -> Dictionary:
	var local_idx := _human_ui_idx()
	var report := {}
	for p_idx in player_avatars:
		var avatar: Node3D = player_avatars[p_idx]
		if not is_instance_valid(avatar):
			continue
		var visible_meshes := 0
		for mesh in avatar.find_children("*", "MeshInstance3D", true, false):
			if mesh.visible:
				visible_meshes += 1
		report[p_idx] = {
			"is_local": p_idx == local_idx,
			"avatar_node_visible": avatar.visible,
			"visible_mesh_count": visible_meshes,
		}
	return report

func _set_avatar_body_visible(avatar: Node3D, body_visible: bool) -> void:
	if not is_instance_valid(avatar):
		return
	for mesh in avatar.find_children("*", "MeshInstance3D", true, false):
		mesh.visible = body_visible

func play_take_animation(player_idx: int) -> void:
	if GameManager.is_multiplayer and player_idx == _human_ui_idx():
		return
	if player_avatars.has(player_idx) and is_instance_valid(player_avatars[player_idx]):
		var char_node = player_avatars[player_idx]
		var ap: AnimationPlayer = char_node.get_node("AnimationPlayer")
		if ap:
			if ap.current_animation == "take":
				ap.seek(0.0, true)
			else:
				ap.play("take")
			ap.queue("idle")

func _on_mp_connection_status_changed(lag_ms: int, status: String) -> void:
	_update_mp_connection_label(lag_ms, status)

func _update_mp_connection_label(lag_ms: int, status: String) -> void:
	if not is_instance_valid(_mp_connection_label):
		return
	if not GameManager.is_multiplayer:
		_mp_connection_label.visible = false
		return
	_mp_connection_label.visible = true
	var color := Color(0.2, 1.0, 0.4)
	var text := ""
	if multiplayer.is_server():
		text = "HOST | ONLINE"
	else:
		match status:
			"disconnected":
				color = Color(1.0, 0.25, 0.25)
				text = "OFFLINE"
			"lagging":
				color = Color(1.0, 0.75, 0.2)
				text = "LAG %dms" % lag_ms
			_:
				if lag_ms <= 250:
					text = "ONLINE %dms" % lag_ms
				else:
					color = Color(1.0, 0.85, 0.2)
					text = "SYNC %dms" % lag_ms
	_mp_connection_label.text = text
	_mp_connection_label.add_theme_color_override("font_color", color)
	_mp_connection_label.add_theme_color_override("font_shadow_color", Color(color.r, color.g, color.b, 0.35))

## Updates HUD action button labels (chevron style, no keybind hints — SP and MP).
func _update_action_button_labels() -> void:
	if is_instance_valid(end_turn_btn):
		end_turn_btn.text = "> END_TURN <"
	if is_instance_valid(jump_in_btn):
		jump_in_btn.text = "> JUMP_IN <"
	if is_instance_valid(call_dutch_btn):
		call_dutch_btn.text = "> CALL_DUTCH <"
	if is_instance_valid(confirm_dutch_btn):
		confirm_dutch_btn.text = "> CONFIRM_DUTCH <"
	if is_instance_valid(forfeit_dutch_btn):
		forfeit_dutch_btn.text = "> FORFEIT_DUTCH <"

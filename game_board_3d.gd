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

var bot_controller: BotController = null
var end_turn_btn: Button
var jump_in_btn: Button
var call_dutch_btn: Button
var confirm_dutch_btn: Button
var forfeit_dutch_btn: Button
var discard_indicator: MeshInstance3D

var player_hands: Array = [[], [], [], []]
var card_spacing = 1.1 # 3D meters
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

@onready var camera = $Camera3D
var _current_ability_message: String = ""

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
	
	_create_hud_ui()
	_create_discard_indicator()
	
	$DeckArea/Area3D.input_event.connect(_on_deck_input_event)
	$DiscardArea/Area3D.input_event.connect(_on_discard_input_event)
	
	bot_controller = BotController.new()
	bot_controller.gm = GameManager
	add_child(bot_controller)
	
	$Camera3D.current = true
	$GameUI/MainHUD.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	await get_tree().process_frame
	_update_deck_visual()
	
	print("Game Board 3D: Starting game...")
	GameManager.initialize_game(4)
	print("Game Board 3D: GameManager.initialize_game called.")

func _create_hud_ui():
	# Standard HUD buttons - positioned same as 2D for consistency
	end_turn_btn = _create_button("END TURN", Color(0.2, 0.6, 0.2), -270, -110)
	jump_in_btn = _create_button("JUMP IN", Color(0.2, 0.4, 0.8), -80, 80)
	call_dutch_btn = _create_button("CALL DUTCH!", Color(0.8, 0.2, 0.2), 110, 270)
	confirm_dutch_btn = _create_button("CONFIRM DUTCH", Color(0.2, 0.6, 0.2), -270, -110)
	forfeit_dutch_btn = _create_button("FORFEIT DUTCH", Color(0.8, 0.2, 0.2), 110, 270)
	
	end_turn_btn.pressed.connect(_on_end_turn_pressed)
	jump_in_btn.pressed.connect(_on_jump_in_pressed)
	call_dutch_btn.pressed.connect(_on_call_dutch_pressed)
	confirm_dutch_btn.pressed.connect(_on_confirm_dutch_pressed)
	forfeit_dutch_btn.pressed.connect(_on_cancel_dutch_pressed)

func _create_button(text: String, color: Color, left: int, right: int) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 20)
	var style = StyleBoxFlat.new()
	style.bg_color = color
	btn.add_theme_stylebox_override("normal", style)
	$GameUI/MainHUD.add_child(btn)
	btn.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	btn.offset_left = left
	btn.offset_right = right
	btn.offset_top = -260
	btn.offset_bottom = -210
	btn.custom_minimum_size = Vector2(160, 50)
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
	mat.emission = Color(0.2, 0.4, 0.8) # Soft blue glow
	mat.emission_energy_multiplier = 0.5
	discard_indicator.material_override = mat
	
	discard_area.add_child(discard_indicator)
	discard_indicator.position = Vector3(0, 0.01, 0)

func _on_turn_started(player_idx):
	var p_info = GameManager.players_info[player_idx]
	turn_label.text = p_info.name + "'s Turn"
	if player_idx != 0:
		_show_message(p_info.name + " is thinking...")

func _on_card_drawn_to_pending(player_idx, card_data):
	if pending_card: pending_card.queue_free()
	
	_update_deck_visual()
	
	if player_idx != 0:
		_show_message(GameManager.players_info[player_idx].name + " is drawing…")
		return
		
	pending_card = card_scene.instantiate()
	add_child(pending_card)
	
	card_data.is_face_up = false
	pending_card.setup(card_data)
	pending_card.position = deck_area.position + Vector3(0, 0.4, 0)
	pending_card.set_interactive(false)
	
	# Reveal animations
	await get_tree().create_timer(0.1).timeout
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
		var hand = player_hands[player_idx]
		for i in range(hand.size()):
			if hand[i].data == card_data:
				card_to_discard = hand[i]
				
				if pending_card:
					if pending_card_tween and pending_card_tween.is_running():
						pending_card_tween.kill()
					
					# Swap: hand node is replaced by pending_card
					hand[i] = pending_card
					pending_card.reparent(player_pos_nodes[player_idx])
					if pending_card.data.is_face_up:
						pending_card.animate_flip(false)
					
					if not pending_card.card_clicked.is_connected(_on_card_clicked):
						pending_card.card_clicked.connect(_on_card_clicked)
					pending_card.set_interactive(true)
					
					pending_card = null
					_update_hand_visuals(player_idx)
				else:
					# Bot swap or pure discard
					var gm_hand = GameManager.players_info[player_idx].hand
					if gm_hand.size() == hand.size():
						# Bot swap: update visual node to match new data in hand
						var temp_discard = card_scene.instantiate()
						add_child(temp_discard)
						temp_discard.setup(card_data)
						temp_discard.global_position = hand[i].global_position
						card_to_discard = temp_discard
						
						hand[i].setup(gm_hand[i])
						if hand[i].data.is_face_up:
							hand[i].data.is_face_up = false
							hand[i]._update_visuals()
					else:
						# Pure removal
						hand.remove_at(i)
						_update_hand_visuals(player_idx)
				break
	
	if card_to_discard == null and player_idx >= 0:
		card_to_discard = card_scene.instantiate()
		add_child(card_to_discard)
		card_to_discard.setup(card_data)
		card_to_discard.position = deck_area.position

	if card_to_discard:
		card_to_discard.set_highlight(false)
		var tween = create_tween()
		var target_pos = discard_area.position + Vector3(0, 0.05, 0)
		
		# Animate to discard pile
		tween.set_parallel(true)
		tween.tween_property(card_to_discard, "position", target_pos, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(card_to_discard, "rotation_degrees", Vector3(270, 0, 0), 0.4) # Face UP on table
		
		tween.chain().tween_callback(func():
			_update_discard_visual()
			_update_deck_visual()
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
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	label.add_theme_color_override("outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 4)
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
		GameManager.GameState.TURN_RESOLVE_DRAWN:
			print("GameBoard3D: UI - Showing TURN_RESOLVE_DRAWN")
			if GameManager.current_player_index != 0:
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
		GameManager.GameState.TURN_SWAP_ABILITY:
			if GameManager.current_player_index == 0:
				_show_message("Select TWO cards to swap.")
				_highlight_selectable_cards(true)
			swap_sources.clear()
	
	if new_state != GameManager.GameState.GAME_OVER:
		if GameManager.deck_manager.discard_pile.size() > 0:
			jump_in_btn.show()

func _set_all_cards_interactive(enabled: bool):
	for i in range(4):
		for card in player_pos_nodes[i].get_children():
			if card is Card3D:
				card.set_interactive(enabled)

func _highlight_selectable_cards(include_opponents: bool = false):
	_clear_all_highlights()
	for i in range(4):
		if i == 0 or include_opponents:
			for card in player_pos_nodes[i].get_children():
				if card is Card3D:
					card.set_highlight(true)

func _clear_all_highlights():
	for i in range(4):
		# Clear from logical array
		for card in player_hands[i]:
			if is_instance_valid(card):
				card.set_highlight(false)
				card.set_selected(false)
		
		# Heavy-duty clear from physical nodes in case they are out of sync
		for child in player_pos_nodes[i].get_children():
			if child is Card3D:
				child.set_highlight(false)
				child.set_selected(false)

func _hide_message():
	_current_ability_message = ""
	for child in top_center.get_children():
		child.queue_free()

func _on_hand_updated(player_idx):
	_update_hand_visuals(player_idx)

# Implement player hand sync with animations
func _update_hand_visuals(player_idx):
	if player_idx < 0 or player_idx >= 4: return
	var pos_node = player_pos_nodes[player_idx]
	var hand_data = GameManager.players_info[player_idx].hand
	var hand_nodes = player_hands[player_idx]
	
	# Sync node array with data array size
	while hand_nodes.size() < hand_data.size():
		var card_node = card_scene.instantiate()
		pos_node.add_child(card_node)
		hand_nodes.append(card_node)
		card_node.card_clicked.connect(_on_card_clicked)
	
	while hand_nodes.size() > hand_data.size():
		var node = hand_nodes.pop_back()
		node.queue_free()
	
	# Position and setup nodes
	for i in range(hand_nodes.size()):
		var card_node = hand_nodes[i]
		card_node.setup(hand_data[i])
		
		# Base rotation: face DOWN (X=90)
		card_node.rotation_degrees = Vector3(90, 0, 0)
		if hand_data[i].is_face_up:
			card_node.rotation_degrees.x = 270 # Face UP
		
		var target_pos = Vector3((i - (hand_nodes.size()-1)/2.0) * card_spacing, 0.05, 0)
		var tween = create_tween().set_parallel(true)
		tween.tween_property(card_node, "position", target_pos, 0.3).set_trans(Tween.TRANS_QUAD)
		
		# Premium "lift" during movement
		var lift_tween = create_tween()
		lift_tween.tween_property(card_node, "scale", Vector3(1.1, 1.1, 1.1), 0.15)
		lift_tween.tween_property(card_node, "scale", Vector3(1.0, 1.0, 1.0), 0.15)

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
			await get_tree().create_timer(0.08).timeout
	
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
	var p_idx = -1
	for i in range(4):
		if player_hands[i].has(node):
			p_idx = i; break
			
	match GameManager.current_state:
		GameManager.GameState.INITIAL_PEEK:
			if node.get_parent() == player_pos_nodes[0] and not data.is_face_up:
				if node in peeked_cards: return
				node.animate_flip(true)
				peeked_cards.append(node)
				if peeked_cards.size() >= 2:
					await get_tree().create_timer(1.5).timeout
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
			if p_idx == 0:
				var c_idx = player_hands[0].find(node)
				if await GameManager.validate_jump_in(c_idx):
					print("Player successfully jumped in!")
				else:
					print("Jump in failed!")
				
		GameManager.GameState.TURN_PEEK_ABILITY:
			if node.data.is_face_up: return
			_set_all_cards_interactive(false)
			node.animate_flip(true)
			await get_tree().create_timer(3.0).timeout
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
			node.set_selected(true)
			
			if swap_sources.size() == 2:
				var s1 = swap_sources[0]
				var s2 = swap_sources[1]
				GameManager.complete_swap_ability(s1.player, s1.index, s2.player, s2.index)
				s1.node.set_selected(false)
				s2.node.set_selected(false)
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
	bg.color = Color(0, 0, 0, 0.75)
	overlay.add_child(bg)
	
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	
	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.05, 0.3, 0.9)
	style.set_corner_radius_all(15)
	style.set_content_margin_all(30)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)
	
	var title = Label.new()
	title.text = "Game Over!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	vbox.add_child(title)
	
	for i in range(results.size()):
		var entry = results[i]
		var row = Label.new()
		var score_str = str(entry.score) if entry.score >= 0 else "0 (wins!)"
		row.text = "%d. %s — %s pts" % [i + 1, entry.name, score_str]
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_theme_font_size_override("font_size", 28)
		if i == 0: row.add_theme_color_override("font_color", Color(1, 0.85, 0))
		vbox.add_child(row)
	
	var buttons = HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(buttons)
	
	var play_again = Button.new()
	play_again.text = "Play Again"
	play_again.pressed.connect(func(): get_tree().reload_current_scene())
	buttons.add_child(play_again)
	
	var main_menu = Button.new()
	main_menu.text = "Main Menu"
	main_menu.pressed.connect(_on_pause_main_menu)
	buttons.add_child(main_menu)

func _unhandled_input(event):
	if event.is_action_pressed("ui_cancel"):
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
	var parent = player_pos_nodes[player_idx]
	if card_idx < 0 or card_idx >= parent.get_child_count(): return
	var card_node = parent.get_child(card_idx)
	if card_node is Card3D and not card_node.data.is_face_up:
		card_node.animate_flip(true)
		await get_tree().create_timer(1.0).timeout
		if is_instance_valid(card_node) and not card_node.data.is_face_up: # Wait, if it failed it stays face down in logic
			card_node.animate_flip(false)

func _on_bot_action(message):
	_show_message(message)

func _process(delta: float) -> void:
	if noclip_enabled and not DevConsole.window.visible:
		_handle_noclip_movement(delta)

func _handle_noclip_movement(delta: float) -> void:
	var move_dir = Vector3.ZERO
	if Input.is_key_pressed(KEY_W): move_dir -= camera.global_transform.basis.z
	if Input.is_key_pressed(KEY_S): move_dir += camera.global_transform.basis.z
	if Input.is_key_pressed(KEY_A): move_dir -= camera.global_transform.basis.x
	if Input.is_key_pressed(KEY_D): move_dir += camera.global_transform.basis.x
	if Input.is_key_pressed(KEY_E): move_dir += Vector3.UP
	if Input.is_key_pressed(KEY_Q): move_dir += Vector3.DOWN
	
	camera.global_position += move_dir.normalized() * 10.0 * delta

func _input(event: InputEvent) -> void:
	if noclip_enabled and not DevConsole.window.visible and event is InputEventMouseMotion:
		camera_rot_y -= event.relative.x * 0.005
		camera_rot_x -= event.relative.y * 0.005
		camera_rot_x = clamp(camera_rot_x, -PI/2, PI/2)
		
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
	for pos_node in player_pos_nodes.values():
		for c3d in pos_node.get_children():
			if c3d is Card3D:
				c3d.animate_flip(true)

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

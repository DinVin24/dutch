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

var player_hands: Array = [[], [], [], []]
var card_spacing = 1.2 # 3D meters
var pending_card: Node3D = null
var card_scene = preload("res://card_3d.tscn")
var pause_menu_scene = preload("res://pause_menu.tscn")
var pause_menu_instance: Node = null

var _current_ability_message: String = ""

func _ready():
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
	GameManager.memory_shift_required.connect(_on_memory_shift_required)
	GameManager.hand_updated.connect(_on_hand_updated)
	GameManager.scores_ready.connect(_on_scores_ready)
	GameManager.all_cards_revealed.connect(_on_all_cards_revealed)
	
	_create_hud_ui()
	
	$DeckArea/Area3D.input_event.connect(_on_deck_input_event)
	$DiscardArea/Area3D.input_event.connect(_on_discard_input_event)
	
	bot_controller = BotController.new()
	bot_controller.gm = GameManager
	add_child(bot_controller)
	
	await get_tree().process_frame
	_update_deck_visual()
	
	print("Game Board 3D: Starting game...")
	GameManager.initialize_game(4)
	print("Game Board 3D: GameManager.initialize_game called.")

func _create_hud_ui():
	# Standard HUD buttons - positioned same as 2D for consistency
	end_turn_btn = _create_button("END TURN", Color(0.2, 0.6, 0.2), -270, 110)
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
	btn.offset_top = -250
	btn.offset_bottom = -200
	btn.hide()
	return btn

func _update_deck_visual():
	for child in deck_area.get_children():
		if child is MeshInstance3D:
			child.queue_free()
	
	var stack_size = min(5, GameManager.deck_manager.deck.size())
	for i in range(stack_size):
		var card = MeshInstance3D.new()
		var mesh = BoxMesh.new()
		mesh.size = Vector3(1, 0.02, 1.4)
		card.mesh = mesh
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.4, 0.2, 0.1) # brown back for deck
		card.set_surface_override_material(0, mat)
		deck_area.add_child(card)
		card.position = Vector3(0, i * 0.03, 0)

func _on_turn_started(player_idx):
	var p_info = GameManager.players_info[player_idx]
	turn_label.text = p_info.name + "'s Turn"
	if player_idx != 0:
		_show_message(p_info.name + " is thinking...")

func _on_card_drawn_to_pending(player_idx, card_data):
	if pending_card: pending_card.queue_free()
	
	_update_deck_visual()
	
	if player_idx != 0:
		return
		
	pending_card = card_scene.instantiate()
	add_child(pending_card)
	pending_card.setup(card_data)
	pending_card.position = deck_area.position + Vector3(0, 0.5, 0)
	
	var tween = create_tween()
	tween.tween_property(pending_card, "position", Vector3(0, 1.0, 0), 0.3).set_trans(Tween.TRANS_QUAD)
	tween.finished.connect(func(): if pending_card: pending_card.animate_flip(true))

func _on_card_discarded(player_idx, card_data):
	var card_to_discard: Node3D = null
	
	if pending_card and pending_card.data == card_data:
		card_to_discard = pending_card
		pending_card = null
	elif player_idx != -1:
		var pos_node = player_pos_nodes[player_idx]
		for child in pos_node.get_children():
			if child is Card3D and child.data == card_data:
				card_to_discard = child
				break
	
	if card_to_discard == null and player_idx >= 0:
		# Bot discarded drawn card directly
		card_to_discard = card_scene.instantiate()
		add_child(card_to_discard)
		card_to_discard.setup(card_data)
		card_to_discard.position = deck_area.position

	if card_to_discard:
		var tween = create_tween()
		var target_pos = discard_area.position + Vector3(0, 0.1, 0)
		tween.tween_property(card_to_discard, "position", target_pos, 0.4).set_trans(Tween.TRANS_QUAD)
		tween.tween_property(card_to_discard, "rotation", Vector3.ZERO, 0.4)
		tween.finished.connect(func():
			for child in discard_area.get_children():
				if child is Card3D: child.queue_free()
			card_to_discard.reparent(discard_area)
			card_to_discard.position = Vector3.ZERO
			card_to_discard.animate_flip(true)
			_update_deck_visual()
		)
	
	if player_idx != -1:
		_update_hand_visuals(player_idx)

func _show_message(text: String):
	_current_ability_message = text
	for child in top_center.get_children():
		child.queue_free()
	
	var label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 32)
	label.add_theme_color_override("shadow_color", Color(0, 0, 0, 0.8))
	top_center.add_child(label)

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
	
	match new_state:
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
		GameManager.GameState.DEAL_CARDS:
			print("GameBoard3D: UI - Entering DEAL_CARDS")
			_handle_initial_deal()
		GameManager.GameState.INITIAL_PEEK:
			print("GameBoard3D: UI - Entering INITIAL_PEEK")
			_start_peek_phase()
		GameManager.GameState.TURN_PEEK_ABILITY:
			if GameManager.current_player_index == 0:
				_show_message("Select ANY card to peek at.")
				_highlight_selectable_cards(true)
		GameManager.GameState.TURN_SWAP_ABILITY:
			if GameManager.current_player_index == 0:
				_show_message("Select TWO cards to swap.")
				_highlight_selectable_cards(true)
	
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
		for card in player_pos_nodes[i].get_children():
			if card is Card3D:
				card.set_highlight(false)

func _hide_message():
	_current_ability_message = ""
	for child in top_center.get_children():
		child.queue_free()

func _on_hand_updated(player_idx):
	_update_hand_visuals(player_idx)

# Implement player hand sync with animations
func _update_hand_visuals(player_idx):
	var pos_node = player_pos_nodes[player_idx]
	var hand = GameManager.players_info[player_idx].hand
	var current_nodes = pos_node.get_children()
	
	# Match data to nodes
	for i in range(max(hand.size(), current_nodes.size())):
		if i < hand.size():
			var card_node: Card3D
			if i < current_nodes.size():
				card_node = current_nodes[i]
			else:
				card_node = card_scene.instantiate()
				pos_node.add_child(card_node)
				card_node.card_clicked.connect(_on_card_clicked)
			
			card_node.setup(hand[i])
			# Base rotation: lie flat on table (faces point UP)
			card_node.rotation_degrees = Vector3(90, 0, 0)
			
			var target_pos = Vector3((i - (hand.size()-1)/2.0) * card_spacing, 0.5, 0)
			print("GameBoard3D: p", player_idx, " c", i, " target_pos: ", target_pos)
			var tween = create_tween()
			tween.tween_property(card_node, "position", target_pos, 0.3).set_trans(Tween.TRANS_QUAD)
		else:
			# Extra nodes to remove
			current_nodes[i].queue_free()

func _handle_initial_deal():
	print("GameBoard3D: _handle_initial_deal started")
	_show_message("Dealing cards...")
	for i in range(4): # 4 cards each
		for p_idx in range(GameManager.num_players):
			var card_data_dict = GameManager.deck_manager.draw_card()
			if card_data_dict.is_empty(): 
				print("GameBoard3D: No cards left in deck during deal!")
				break
			
			print("GameBoard3D: Dealing card ", i, " to player ", p_idx)
			var card_data = CardData.new(card_data_dict.rank, card_data_dict.suit)
			card_data.is_face_up = false
			GameManager.players_info[p_idx].hand.append(card_data)
			_update_hand_visuals(p_idx)
			await get_tree().create_timer(0.1).timeout
	
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
	match GameManager.current_state:
		GameManager.GameState.INITIAL_PEEK:
			if node.get_parent() == player_pos_nodes[0] and not data.is_face_up:
				if node in peeked_cards: return
				node.animate_flip(true)
				peeked_cards.append(node)
				if peeked_cards.size() >= 2:
					await get_tree().create_timer(1.5).timeout
					for c in peeked_cards:
						c.animate_flip(false)
						c.set_interactive(false)
					peeked_cards.clear()
					GameManager.complete_initial_peek()
		
		GameManager.GameState.TURN_RESOLVE_DRAWN:
			var p_idx = -1
			for i in range(4):
				if node.get_parent() == player_pos_nodes[i]:
					p_idx = i; break
			if p_idx == 0:
				GameManager.player_swap_drawn_card(player_pos_nodes[0].get_children().find(node))
		
		GameManager.GameState.TURN_JUMP_IN_SELECTION:
			if node.get_parent() == player_pos_nodes[0]:
				var c_idx = player_pos_nodes[0].get_children().find(node)
				GameManager.validate_jump_in(c_idx)
				
		GameManager.GameState.TURN_PEEK_ABILITY:
			node.animate_flip(true)
			await get_tree().create_timer(2.0).timeout
			node.animate_flip(false)
			GameManager.end_turn() # Basic ability resolution for now
			
		GameManager.GameState.TURN_SWAP_ABILITY:
			# Implement swap selection logic
			pass

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
	main_menu.pressed.connect(func(): get_tree().change_scene_to_file("res://main_menu.tscn"))
	buttons.add_child(main_menu)

# Signal Handlers
func _on_jump_in_penalty(player_idx, _card): 
	_update_hand_visuals(player_idx)

func _on_jump_in_failed(_player_idx, _card_idx, _card_data):
	# Optional: add visual feedback for failure in 3D
	pass

func _on_bot_action(message):
	_show_message(message)

func _on_jack_swap_resolved(_p1, _c1, _p2, _c2):
	# Refresh all hands to show swapped cards from Jack ability
	for i in range(4):
		_update_hand_visuals(i)

func _on_all_cards_revealed():
	# Flip all cards face-up for game over
	for pos_node in player_pos_nodes.values():
		for c3d in pos_node.get_children():
			if c3d is Card3D:
				c3d.animate_flip(true)

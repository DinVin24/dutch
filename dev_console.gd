extends CanvasLayer

@onready var window = $ConsoleWindow
@onready var panel = $ConsoleWindow/Panel
@onready var output = $ConsoleWindow/Panel/Output
@onready var input = $ConsoleWindow/Panel/Input

var is_dragging := false
var drag_offset := Vector2.ZERO
var is_resizing := false
var resize_start_size := Vector2.ZERO
var resize_start_pos := Vector2.ZERO

func _ready():
	window.hide()
	output.text = "Dutch Developer Console [Version 1.0]\nType 'help' for commands.\n"

func _input(event):
	# Handle toggle key
	if event.is_action_pressed("toggle_console") or (event is InputEventKey and event.pressed and event.keycode == KEY_QUOTELEFT):
		if GameManager.dev_console_enabled:
			_toggle_console()
			get_viewport().set_input_as_handled()
	
	# Handle ESC (ui_cancel) to close console
	if window.visible and event.is_action_pressed("ui_cancel"):
		window.hide()
		input.release_focus()
		# Restore captured mouse if noclip is active
		if get_tree().current_scene.has_method("is_noclip_active") and get_tree().current_scene.is_noclip_active():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()

func _toggle_console():
	if window.visible:
		window.hide()
		input.release_focus()
		# Restore captured mouse if noclip is active
		if get_tree().current_scene.has_method("is_noclip_active") and get_tree().current_scene.is_noclip_active():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		window.show()
		input.grab_focus()
		# Always show mouse when console is open
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_close_button_pressed():
	window.hide()
	input.release_focus()
	if get_tree().current_scene.has_method("is_noclip_active") and get_tree().current_scene.is_noclip_active():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _parse_args(text: String) -> Array:
	var result = []
	var current = ""
	var in_quotes = false
	var i = 0
	while i < text.length():
		var c = text[i]
		if c == "'":
			in_quotes = !in_quotes
		elif c == " " and not in_quotes:
			if current != "":
				result.append(current)
				current = ""
		else:
			current += c
		i += 1
	if current != "":
		result.append(current)
	return result

func _on_input_text_submitted(new_text):
	var line = new_text.strip_edges()
	if line == "": return
	
	output.append_text("\n> " + line)
	var all_parts = _parse_args(line)
	if all_parts.is_empty(): return
	
	var cmd = all_parts[0].to_lower()
	var args = all_parts.slice(1)
	input.clear()
	
	if cmd == "help":
		output.append_text("\n[color=yellow]Available commands: help, clear, exit, noclip, cards, give, remove, kill[/color]")
	elif cmd == "clear":
		output.clear()
	elif cmd == "exit":
		window.hide()
	elif cmd == "noclip":
		if get_tree().current_scene.has_method("toggle_noclip"):
			var result = get_tree().current_scene.toggle_noclip()
			output.append_text("\n[color=cyan]Noclip: " + str(result) + "[/color]")
		else:
			output.append_text("\n[color=red]Noclip not supported in this scene.[/color]")
	elif cmd == "cards":
		_cmd_cards(args)
	elif cmd == "give":
		_cmd_give(args)
	elif cmd == "remove":
		_cmd_remove(args)
	elif cmd == "kill":
		_cmd_kill(args)
	else:
		output.append_text("\n[color=red]command not recognized, use 'help' for all the commands[/color]")
	
	# Re-grab focus after enter
	input.grab_focus()

func _cmd_cards(args: Array):
	var players = GameManager.players_info
	if players.is_empty():
		output.append_text("\n[color=red]No active game session found.[/color]")
		return
		
	var idx = GameManager.current_player_index
	if args.size() == 0:
		# Show current player
		if idx >= 0 and idx < players.size():
			_print_player_cards(players[idx])
		else:
			output.append_text("\n[color=red]No active player index.[/color]")
	elif args[0].to_lower() == "all":
		for p in players:
			_print_player_cards(p)
	else:
		var target_name = " ".join(args).to_lower()
		var found = false
		for p in players:
			if p.name.to_lower() == target_name or str(p.id + 1) == target_name:
				_print_player_cards(p)
				found = true
				break
		if not found:
			output.append_text("\n[color=red]Player '" + target_name + "' not found.[/color]")

func _print_player_cards(player: Dictionary):
	output.append_text("\n[color=green]--- " + player.name + " ---[/color]")
	for i in range(player.hand.size()):
		var card = player.hand[i]
		if card is CardData:
			output.append_text("\n" + str(i) + ": " + card.display_name())
		else:
			output.append_text("\n" + str(i) + ": [color=gray]Unknown Card[/color]")

func _cmd_give(args: Array):
	if args.size() < 2:
		output.append_text("\n[color=red]Usage: give <PlayerName> '<Card/Ability Name>' or '$Amount'[/color]")
		return
	
	var p_name = args[0].to_lower()
	var target_name = args[1].to_lower()
	
	var player = _find_player(p_name)
	if not player: return
	
	if target_name.begins_with("$"):
		var amount_str = target_name.substr(1)
		if amount_str.is_valid_int():
			var amount = amount_str.to_int()
			player.money += amount
			GameManager.player_gained_money.emit(player.id, amount, player.money)
			output.append_text("\n[color=yellow]Gave $" + str(amount) + " to " + player.name + "![/color]")
			return
		else:
			output.append_text("\n[color=red]Invalid money amount: " + target_name + "[/color]")
			return
	
	# Mapping for human-friendly ability names to internal IDs
	var ability_map = {
		"bottoms up": "bottoms_up",
		"refuel": "refuel",
		"trim off": "trim_off",
		"boulder": "boulder",
		"reverse": "reverse",
		"skip": "skip",
		"perfect match": "perfect_match",
		"inflation": "inflation",
		"half off": "half_off",
		"jumpscare": "jumpscare",
		"shuffle": "shuffle",
		"polarity shift": "polarity_shift"
	}
	
	if ability_map.has(target_name):
		var ab_id = ability_map[target_name]
		player.abilities.append(ab_id)
		output.append_text("\n[color=cyan]Gave Ability '" + target_name.capitalize() + "' to " + player.name + "[/color]")
		
		# Visually spawn the token if we are in the 3D board scene
		var scene = get_tree().current_scene
		if scene.has_method("_on_hand_updated"): # Check if it's the board
			# We can't easily call private board methods, but we can mimic the logic
			# or just wait for the next turn. Let's try to find if there's a signal.
			# Actually, the board listens to nothing for abilities additions.
			# Let's just suggest the user restarts or wait for my next improvement.
			# BETTER: Manually spawn if we find the node.
			var pos_node = scene.player_pos_nodes[player.id]
			var token_scene = load("res://ability_token_3d.gd")
			if pos_node and token_scene:
				var token = token_scene.new()
				pos_node.add_child(token)
				token.setup(ab_id)
				token.token_clicked.connect(scene._on_ability_token_clicked)
				
				# Drop beautifully from above to notify the player they received it
				token.position = Vector3(2.8, 0.5, 0.0)
				
				if scene.has_method("_update_ability_visuals"):
					scene._update_ability_visuals(player.id)
	else:
		# Try to find card
		var card = _find_and_remove_card_globally(target_name)
		if card:
			player.hand.append(card)
			GameManager.hand_updated.emit(player.id)
			output.append_text("\n[color=cyan]Gave " + card.display_name() + " to " + player.name + "[/color]")
		else:
			output.append_text("\n[color=red]'" + target_name + "' is not a recognized ability or card.[/color]")

func _cmd_remove(args: Array):
	if args.size() < 2:
		output.append_text("\n[color=red]Usage: remove <PlayerName> <index or 'Card Name'>[/color]")
		return
		
	var p_name = args[0].to_lower()
	var target = args[1].to_lower()
	
	var player = _find_player(p_name)
	if not player: return
	
	var removed = false
	var removed_idx = -1
	if target.is_valid_int():
		var idx = target.to_int()
		if idx >= 0 and idx < player.hand.size():
			var card = player.hand[idx]
			player.hand.remove_at(idx)
			removed = true
			removed_idx = idx
			output.append_text("\n[color=cyan]Removed " + card.display_name() + " from " + player.name + "[/color]")
	else:
		for i in range(player.hand.size()):
			if player.hand[i].display_name().to_lower() == target:
				var card = player.hand[i]
				player.hand.remove_at(i)
				removed = true
				removed_idx = i
				output.append_text("\n[color=cyan]Removed " + card.display_name() + " from " + player.name + "[/color]")
				break
				
	if removed:
		GameManager.hand_updated.emit(player.id)
		GameManager.memory_shift_required.emit(player.id, removed_idx)
		# Check for game over if someone hits 0 cards
		if player.hand.is_empty():
			GameManager.change_state(GameManager.GameState.GAME_OVER)
	else:
		output.append_text("\n[color=red]Card or index '" + target + "' not found in " + player.name + "'s hand.[/color]")

func _cmd_kill(args: Array):
	if args.size() < 1:
		output.append_text("\n[color=red]Usage: kill <PlayerName>[/color]")
		return
	
	var p_name = args[0].to_lower()
	var player = _find_player(p_name)
	if not player: return
	
	output.append_text("\n[color=cyan]Killing " + player.name + "...[/color]")
	
	# Force beers to 1 and drink to properly trigger natural elimination
	GameManager.players_info[player.id].beers = 1
	GameManager.drink_beer(player.id)

func _find_player(p_name: String):
	for p in GameManager.players_info:
		if p.name.to_lower() == p_name or str(p.id + 1) == p_name:
			return p
	output.append_text("\n[color=red]Player '" + p_name + "' not found.[/color]")
	return null

func _find_and_remove_card_globally(c_name: String) -> CardData:
	# Check Deck
	var dm = GameManager.deck_manager
	for i in range(dm.deck.size()):
		var info = dm.deck[i]
		var dname = (str(info.rank) + " of " + str(info.suit)).to_lower()
		if dname == c_name:
			var card_info = dm.deck.pop_at(i)
			return CardData.new(card_info.rank, card_info.suit)
			
	# Check Discard
	for i in range(dm.discard_pile.size()):
		var info = dm.discard_pile[i]
		var dname = (str(info.rank) + " of " + str(info.suit)).to_lower()
		if dname == c_name:
			var card_info = dm.discard_pile.pop_at(i)
			dm.discard_pile_updated.emit()
			return CardData.new(card_info.rank, card_info.suit)
			
	return null

func log_message(message: String):
	output.append_text("\n" + message)

# --- Dragging Logic ---
func _on_title_bar_gui_input(event: InputEvent):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				is_dragging = true
				drag_offset = panel.position - get_viewport().get_mouse_position()
			else:
				is_dragging = false
	
	if event is InputEventMouseMotion and is_dragging:
		panel.position = get_viewport().get_mouse_position() + drag_offset

# --- Resizing Logic ---
func _on_resize_handle_gui_input(event: InputEvent):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				is_resizing = true
				resize_start_size = panel.size
				resize_start_pos = get_viewport().get_mouse_position()
			else:
				is_resizing = false
	
	if event is InputEventMouseMotion and is_resizing:
		var delta = get_viewport().get_mouse_position() - resize_start_pos
		var new_size = resize_start_size + delta
		# Minimum size constraints
		panel.size = Vector2(max(300, new_size.x), max(200, new_size.y))

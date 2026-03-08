extends Node
class_name BotController

var gm: Node = null
var rng = RandomNumberGenerator.new()

func _ready():
	rng.randomize()
	if gm:
		gm.game_state_changed.connect(_on_game_state_changed)
		gm.turn_started.connect(_on_turn_started)
		gm.card_discarded.connect(_on_card_discarded)

func is_headless() -> bool:
	return DisplayServer.get_name() == "headless"

func _wait(seconds: float):
	if is_headless(): return
	await get_tree().create_timer(seconds).timeout

func _on_game_state_changed(new_state):
	if new_state == GameManager.GameState.INITIAL_PEEK:
		_execute_bot_initial_peek()
		return

	if gm.current_player_index == 0:
		return
		
	match new_state:
		GameManager.GameState.TURN_RESOLVE_DRAWN:
			_execute_bot_resolve_drawn()
		GameManager.GameState.TURN_PEEK_ABILITY:
			_execute_bot_queen_peek()
		GameManager.GameState.TURN_SWAP_ABILITY:
			_execute_bot_jack_swap()
		GameManager.GameState.TURN_END_CHOICE:
			_execute_bot_end_choice()
		GameManager.GameState.TURN_CONFIRM_DUTCH:
			_execute_bot_dutch_confirm()

func _on_turn_started(player_idx):
	if player_idx == 0:
		return
	
	await _wait(1.0)
	
	if gm.current_state == GameManager.GameState.TURN_START_DRAW:
		gm.player_draw_card()

func _on_card_discarded(discarder_idx, card_data):
	# "even when it's not his turn, the bot will jump in if he knows he has a matching card, from his memory."
	for bot_idx in range(1, gm.num_players):
		if bot_idx == discarder_idx: continue
		
		# Only jump in if allowed by the game state
		if gm.current_state != GameManager.GameState.TURN_END_CHOICE: continue
		
		var my_memory = gm.players_info[bot_idx].bot_memory
		if not my_memory.has(bot_idx): continue
		
		var own_known = my_memory[bot_idx]
		var found_match_idx = -1
		
		for c_idx in own_known:
			if own_known[c_idx].rank == card_data.rank:
				found_match_idx = c_idx
				break
				
		if found_match_idx != -1:
			_attempt_jump_in(bot_idx, found_match_idx)
			break

# --- ACTIONS ---

func _execute_bot_initial_peek():
	# "in the beginning, the bots don't know any of their cards."
	# "in the card peeking period, which happens at the same time for all players, 
	# the bots are going to look at 2 out of the 4 cards they have and remember them."
	for i in range(1, gm.num_players):
		var bot_info = gm.players_info[i]
		bot_info.bot_memory.clear()
		for p_idx in range(gm.num_players):
			bot_info.bot_memory[p_idx] = {}
				
		var hand_size = bot_info.hand.size()
		if hand_size >= 2:
			var idx1 = rng.randi_range(0, hand_size - 1)
			var idx2 = idx1
			while idx2 == idx1:
				idx2 = rng.randi_range(0, hand_size - 1)
				
			bot_info.bot_memory[i][idx1] = bot_info.hand[idx1]
			bot_info.bot_memory[i][idx2] = bot_info.hand[idx2]

	gm.bot_action.emit("Bots are memorizing their cards...")
	await _wait(2.0)

func _execute_bot_resolve_drawn():
	var p_idx = gm.current_player_index
	var p_info = gm.players_info[p_idx]
	await _wait(1.5)
	
	var drawn_value = _get_card_value(gm.drawn_card_data)
	if not p_info.bot_memory.has(p_idx):
		p_info.bot_memory[p_idx] = {}
		
	var own_memory = p_info.bot_memory[p_idx]
	var hand_size = p_info.hand.size()
	
	if hand_size == 0:
		gm.bot_action.emit("Bot " + str(p_idx) + " discarded.")
		gm.player_discard_drawn_card()
		return
		
	var known_count = own_memory.size()
	
	if known_count < hand_size:
		# "if it doesn't know all of its cards yet, it'll prefer to replace an unknown card. now his memory will be updated."
		var unknown_indices = []
		for i in range(hand_size):
			if not own_memory.has(i):
				unknown_indices.append(i)
				
		var swap_idx = unknown_indices[rng.randi_range(0, unknown_indices.size() - 1)]
		gm.bot_action.emit("Bot " + str(p_idx) + " swapped a card.")
		p_info.bot_memory[p_idx][swap_idx] = gm.drawn_card_data
		gm.player_swap_drawn_card(swap_idx)
	else:
		# "if it knows all the cards... "
		var max_val = -1
		var max_idx = -1
		for i in range(hand_size):
			var val = _get_card_value(own_memory[i])
			if val > max_val:
				max_val = val
				max_idx = i
				
		if drawn_value >= max_val:
			# "... and the card is higher than all of his cards in hand, he discards it."
			gm.bot_action.emit("Bot " + str(p_idx) + " discarded.")
			gm.player_discard_drawn_card()
		else:
			# "... and is smaller than one of them, it will replace it, discarding the card he had in hand and updates the memory."
			gm.bot_action.emit("Bot " + str(p_idx) + " swapped a card.")
			p_info.bot_memory[p_idx][max_idx] = gm.drawn_card_data
			gm.player_swap_drawn_card(max_idx)

func _execute_bot_queen_peek():
	var p_idx = gm.current_player_index
	var p_info = gm.players_info[p_idx]
	await _wait(1.2)
	
	if not p_info.bot_memory.has(p_idx):
		p_info.bot_memory.clear()
		for i in range(gm.num_players): p_info.bot_memory[i] = {}
		
	var own_memory = p_info.bot_memory[p_idx]
	var hand_size = p_info.hand.size()
	
	var unknown_own_indices = []
	for i in range(hand_size):
		if not own_memory.has(i):
			unknown_own_indices.append(i)
			
	if unknown_own_indices.size() > 0:
		# "when using a queen, the bot will first use it to learn the cards from his hand that he doesn't know yet."
		var peek_idx = unknown_own_indices[rng.randi_range(0, unknown_own_indices.size() - 1)]
		p_info.bot_memory[p_idx][peek_idx] = p_info.hand[peek_idx]
		gm.bot_action.emit("Bot " + str(p_idx) + " peeked at its own card.")
	else:
		# "otherwise he'll pick a random card from a player to learn. (you could make it so it chooses the player with the least amount of cards as well)"
		var target_p = -1
		var min_cards = 999
		
		for i in range(gm.num_players):
			if i == p_idx: continue
			var sz = gm.players_info[i].hand.size()
			if sz > 0 and sz < min_cards:
				min_cards = sz
				
		var candidates = []
		for i in range(gm.num_players):
			if i == p_idx: continue
			if gm.players_info[i].hand.size() == min_cards:
				candidates.append(i)
				
		if candidates.size() > 0:
			target_p = candidates[rng.randi_range(0, candidates.size() - 1)]
			var target_sz = gm.players_info[target_p].hand.size()
			var target_c = rng.randi_range(0, target_sz - 1)
			
			p_info.bot_memory[target_p][target_c] = gm.players_info[target_p].hand[target_c]
			gm.bot_action.emit("Bot " + str(p_idx) + " peeked at Player " + str(target_p) + "'s card.")
	
	gm.complete_peek_ability()

func _execute_bot_jack_swap():
	var p_idx = gm.current_player_index
	var p_info = gm.players_info[p_idx]
	gm.bot_action.emit("Bot " + str(p_idx) + " is choosing cards to swap...")
	await _wait(1.5)
	
	var my_memory = p_info.bot_memory
	
	# "when using a jack, this is more complex. he can either choose 2 random cards from other players, 
	# or choose a big card from his hand and a small card from another player's hand if he knows them."
	
	# Find my highest known card
	var my_highest_val = -1
	var my_highest_c = -1
	if my_memory.has(p_idx):
		for c_idx in my_memory[p_idx]:
			var val = _get_card_value(my_memory[p_idx][c_idx])
			if val > my_highest_val:
				my_highest_val = val
				my_highest_c = c_idx
				
	# Find an opponent's lowest known card
	var opp_lowest_val = 999
	var target_p = -1
	var target_c = -1
	
	for opp_idx in my_memory:
		if opp_idx == p_idx: continue
		for opp_c_idx in my_memory[opp_idx]:
			var val = _get_card_value(my_memory[opp_idx][opp_c_idx])
			if val < opp_lowest_val:
				opp_lowest_val = val
				target_p = opp_idx
				target_c = opp_c_idx
				
	var p1 = -1
	var c1 = -1
	var p2 = -1
	var c2 = -1
	
	# "choose a big card from his hand and a small card from another player's hand if he knows them"
	if my_highest_c != -1 and target_c != -1 and my_highest_val > opp_lowest_val:
		p1 = p_idx
		c1 = my_highest_c
		p2 = target_p
		c2 = target_c
	else:
		# "choose 2 random cards from other players"
		p1 = p_idx
		while p1 == p_idx or gm.players_info[p1].hand.size() == 0:
			p1 = rng.randi_range(0, gm.num_players - 1)
		c1 = rng.randi_range(0, gm.players_info[p1].hand.size() - 1)
		
		p2 = p_idx
		while p2 == p_idx or p2 == p1 or gm.players_info[p2].hand.size() == 0:
			p2 = rng.randi_range(0, gm.num_players - 1)
			
		c2 = rng.randi_range(0, gm.players_info[p2].hand.size() - 1)
		
	_update_memory_on_swap(p1, c1, p2, c2)
	
	gm.bot_action.emit("Bot " + str(p_idx) + " swapped cards.")
	gm.complete_swap_ability(p1, c1, p2, c2)

func _execute_bot_end_choice():
	var p_idx = gm.current_player_index
	var p_info = gm.players_info[p_idx]
	await _wait(1.0)
	
	if not p_info.bot_memory.has(p_idx):
		gm.end_turn()
		return
		
	var own_memory = p_info.bot_memory[p_idx]
	var hand_size = p_info.hand.size()
	
	# "calling dutch: the bot will call dutch when he knows all his cards and the total score is less than 7."
	if own_memory.size() == hand_size and hand_size > 0:
		var total_score = 0
		for i in range(hand_size):
			total_score += _get_card_value(own_memory[i])
			
		if total_score < 7 and gm.dutch_caller_index == -1 and p_info.can_call_dutch:
			gm.bot_action.emit("Bot " + str(p_idx) + " is CALLING DUTCH!")
			gm.call_dutch(p_idx)
			return
			
	gm.end_turn()

func _execute_bot_dutch_confirm():
	var p_idx = gm.current_player_index
	await _wait(1.5)
	gm.confirm_dutch()

func _attempt_jump_in(bot_idx: int, card_idx: int):
	await _wait(1.2)
	
	if gm.current_state != GameManager.GameState.TURN_END_CHOICE:
		return
		
	var original_turn = gm.current_player_index
	gm.current_player_index = bot_idx
	
	gm.bot_action.emit("Bot " + str(bot_idx) + " is JUMPING IN!")
	gm.start_jump_in()
	gm.validate_jump_in(card_idx)
	
	if gm.current_player_index == bot_idx:
		gm.current_player_index = original_turn

# --- UTILITIES ---

func _get_card_value(card_data: CardData) -> int:
	if card_data.rank == "King" and card_data.suit == "Diamonds": return 0
	if card_data.rank == "Ace": return 1
	if card_data.rank == "Jack": return 11
	if card_data.rank == "Queen": return 12
	if card_data.rank == "King": return 13
	return card_data.rank.to_int()

func _update_memory_on_swap(p1, c1, p2, c2):
	for i in range(1, gm.num_players):
		var mem = gm.players_info[i].bot_memory
		if not mem.has(p1): mem[p1] = {}
		if not mem.has(p2): mem[p2] = {}
		
		var p1_known = null
		if mem[p1].has(c1): p1_known = mem[p1][c1]
		
		var p2_known = null
		if mem[p2].has(c2): p2_known = mem[p2][c2]
		
		if p2_known: mem[p1][c1] = p2_known
		else: mem[p1].erase(c1)
			
		if p1_known: mem[p2][c2] = p1_known
		else: mem[p2].erase(c2)

extends Node
class_name AbilityManager

var gm: Node

func _ready():
	gm = get_parent()

func execute(player_idx: int, ability_id: String, target_idx: int = -1):
	print("AbilityManager executing: ", ability_id, " by P", player_idx, " targeting P", target_idx)
	
	match ability_id:
		"bottoms_up":
			if target_idx != -1:
				gm.drink_beer(target_idx)
		"refuel":
			if not gm.players_info[player_idx].is_eliminated:
				gm.players_info[player_idx].beers = min(gm.players_info[player_idx].beers + 1, 3)
				gm.player_drank_beer.emit(player_idx, gm.players_info[player_idx].beers)
		"trim_off":
			_trim_off(player_idx)
		"boulder":
			if target_idx != -1:
				_boulder(target_idx)
		"reverse":
			gm.turn_direction *= -1
			print("Turn direction reversed!")
		"skip":
			if target_idx != -1:
				gm.players_info[target_idx].is_skipped = true
				print("Player ", target_idx, " marked for skip.")
		"perfect_match":
			_perfect_match(player_idx)
		"inflation":
			if target_idx != -1:
				_modify_values(target_idx, 2.0)
		"half_off":
			if target_idx != -1:
				_modify_values(target_idx, 0.5)
		"jumpscare":
			if target_idx != -1:
				# Give card
				var p_card = gm.deck_manager.draw_card()
				if p_card != null:
					gm.players_info[target_idx].hand.append(p_card)
					gm.hand_updated.emit(target_idx)
		"shuffle":
			if target_idx != -1:
				gm.players_info[target_idx].hand.shuffle()
				gm.hand_updated.emit(target_idx)
		"polarity_shift":
			gm.shift_polarity()

	# Return FSM to normal
	await get_tree().create_timer(1.0).timeout
	
	# Only resume if we haven't already moved to a new state (e.g. elimination next_turn)
	if gm.current_state == gm.GameState.STATE_PLAYING_ABILITY:
		print("[AM DEBUG] Resuming from ability...")
		gm.resume_from_ability()
	else:
		print("[AM DEBUG] Already changed state (", gm.GameState.keys()[gm.current_state], "), skipping resume but finishing ability signal.")
		gm.ability_finished.emit()

func _trim_off(p_idx: int):
	var hand = gm.players_info[p_idx].hand
	if hand.is_empty(): return
	var highest_val = -1
	var highest_idx = -1
	for i in range(hand.size()):
		var val = hand[i].recalc_point_value()
		if val > highest_val:
			highest_val = val
			highest_idx = i
	
	if highest_idx != -1:
		var card = hand.pop_at(highest_idx)
		gm.deck_manager.discard_pile.append(card)
		gm.hand_updated.emit(p_idx)
		gm.card_discarded.emit(p_idx, card)
		gm.gain_money_for_discard(p_idx, card)

func _boulder(t_idx: int):
	var deck = gm.deck_manager.deck
	if deck.is_empty(): return
	
	var highest_val = -1
	var highest_idx = -1
	for i in range(deck.size()):
		var c = CardData.new(deck[i].rank, deck[i].suit)
		var val = c.recalc_point_value()
		if val > highest_val:
			highest_val = val
			highest_idx = i
			
	if highest_idx != -1:
		var card = deck.pop_at(highest_idx)
		card.is_face_up = false
		gm.players_info[t_idx].hand.append(card)
		gm.hand_updated.emit(t_idx)

func _modify_values(t_idx: int, modifier: float):
	for card in gm.players_info[t_idx].hand:
		card.point_modifier *= modifier
	gm.hand_updated.emit(t_idx)

func _perfect_match(activator_idx: int):
	print("[AM DEBUG] Perfect Match triggered by P", activator_idx, ". Resetting round...")
	# 0. Clear any pending drawn card in manager
	gm.drawn_card_data = null
	
	# 1. Collect all board cards
	var all_cards = []
	for i in range(gm.num_players):
		all_cards.append_array(gm.players_info[i].hand)
		gm.players_info[i].hand.clear()
		gm.hand_updated.emit(i)
		
	all_cards.append_array(gm.deck_manager.discard_pile)
	gm.deck_manager.discard_pile.clear()
	
	# Cards are already CardData objects in our new refactored system
	for card in all_cards:
		if is_instance_valid(card):
			# Reset any temporary state on the cards
			card.point_modifier = 1.0
			card.is_face_up = false
			gm.deck_manager.deck.append(card)
		
	# Reshuffle
	gm.deck_manager.deck.shuffle()
	
	# 2. Extract [Ace, 2, 3, 4] for activator
	var needed_ranks = ["Ace", "2", "3", "4"]
	var extracted = []
	for n_rank in needed_ranks:
		for i in range(gm.deck_manager.deck.size()):
			if gm.deck_manager.deck[i].rank == n_rank:
				extracted.append(gm.deck_manager.deck.pop_at(i))
				break
				
	# If any missing due to weird deck state, fallback to draw
	while extracted.size() < 4:
		var d = gm.deck_manager.draw_card()
		if d: extracted.append(d)
		
	# Assign the 'Perfect Match' to activator
	for card in extracted:
		gm.players_info[activator_idx].hand.append(card)
	gm.hand_updated.emit(activator_idx)
		
	# 3. Give 4 random cards to everyone else
	for i in range(gm.num_players):
		if i == activator_idx or gm.players_info[i].is_eliminated: continue
		for j in range(4):
			var cd = gm.deck_manager.draw_card()
			if cd:
				gm.players_info[i].hand.append(cd)
		gm.hand_updated.emit(i)
		
	# 4. Draw one card for the new discard pile
	var discard_start = gm.deck_manager.draw_card()
	if discard_start:
		discard_start.is_face_up = true
		gm.deck_manager.discard_pile.append(discard_start)
		gm.card_discarded.emit(-1, discard_start) # -1 means dealer
	
	# 5. Reinstate peeking phase for the new cards
	# We use change_state(..., true) to ensure everyone wakes up!
	gm.change_state(gm.GameState.INITIAL_PEEK, true)
	
	# Easy Mode: immediately skip the peek — P0's cards are always visible
	if gm.easy_mode:
		gm.complete_initial_peek()

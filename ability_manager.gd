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
				gm.players_info[player_idx].beers = min(gm.players_info[player_idx].beers + 1, 5)
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
				var card_dict = gm.deck_manager.draw_card()
				if not card_dict.is_empty():
					var p_card = CardData.new(card_dict.rank, card_dict.suit)
					gm.players_info[target_idx].hand.append(p_card)
					gm.hand_updated.emit(target_idx)
				# Jumpscare signal can be added later for UI
		"shuffle":
			if target_idx != -1:
				gm.players_info[target_idx].hand.shuffle()
				gm.hand_updated.emit(target_idx)

	# Return FSM to normal
	await get_tree().create_timer(1.0).timeout
	gm.resume_from_ability()

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
		var card_dict = deck.pop_at(highest_idx)
		var p_card := CardData.new(card_dict.rank, card_dict.suit)
		p_card.is_face_up = false
		gm.players_info[t_idx].hand.append(p_card)
		gm.hand_updated.emit(t_idx)

func _modify_values(t_idx: int, modifier: float):
	for card in gm.players_info[t_idx].hand:
		card.point_modifier *= modifier
	gm.hand_updated.emit(t_idx)

func _perfect_match(activator_idx: int):
	# Collect all board cards
	var all_cards = []
	for i in range(gm.num_players):
		all_cards.append_array(gm.players_info[i].hand)
		gm.players_info[i].hand.clear()
		gm.hand_updated.emit(i)
		
	all_cards.append_array(gm.deck_manager.discard_pile)
	gm.deck_manager.discard_pile.clear()
	
	# Convert all CardData objects back to dictionaries for the deck manager
	for card in all_cards:
		gm.deck_manager.deck.append({"rank": card.rank, "suit": card.suit})
		
	# Reshuffle
	gm.deck_manager.deck.shuffle()
	
	# Extract A, 2, 3, 4 for activator
	var needed_ranks = ["Ace", "2", "3", "4"]
	var extracted = []
	for n_rank in needed_ranks:
		for i in range(gm.deck_manager.deck.size()):
			if gm.deck_manager.deck[i].rank == n_rank:
				extracted.append(gm.deck_manager.deck.pop_at(i))
				break
				
	# If any missing due to weird deck state (impossible in standard without bugs), fallback to draw
	while extracted.size() < 4:
		extracted.append(gm.deck_manager.draw_card())
		
	for card_dict in extracted:
		gm.players_info[activator_idx].hand.append(CardData.new(card_dict.rank, card_dict.suit))
	gm.hand_updated.emit(activator_idx)
		
	# Give 4 random cards to everyone else as long as they aren't eliminated
	for i in range(gm.num_players):
		if i == activator_idx or gm.players_info[i].is_eliminated: continue
		for j in range(4):
			var cd = gm.deck_manager.draw_card()
			if not cd.is_empty():
				gm.players_info[i].hand.append(CardData.new(cd.rank, cd.suit))
		gm.hand_updated.emit(i)
		
	# Draw one card for the new discard pile to keep the game going
	var start_card = gm.deck_manager.draw_card()
	if not start_card.is_empty():
		var discard_start = CardData.new(start_card.rank, start_card.suit)
		discard_start.is_face_up = true
		gm.deck_manager.discard_pile.append(discard_start)
		gm.card_discarded.emit(-1, discard_start) # -1 means dealer
	
	# Reinstate peeking phase for the new cards
	gm.change_state(gm.GameState.INITIAL_PEEK)

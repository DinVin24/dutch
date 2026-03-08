extends Node
class_name BotController

# ============================================================
# BotController — Autonomous AI for all non-human players.
#
# MEMORY STRUCTURE
#   Each bot (player index >= 1) maintains its own memory:
#   bot_memory[bot_idx][target_player_idx][card_idx] = CardData
#   e.g. bot_memory[1][0][2] = <CardData>  means:
#        bot 1 knows player 0's card at index 2.
#
# HOW MEMORY IS STORED
#   We store the memory inside game_manager.players_info[i].bot_memory
#   so that it lives alongside the canonical hand data.
#   Structure per player:  { player_idx: { card_idx: CardData } }
# ============================================================

var gm: Node = null # Reference to the GameManager autoload
var rng := RandomNumberGenerator.new()

# ─── Lifecycle ───────────────────────────────────────────────

func _ready() -> void:
	rng.randomize()

	if not gm:
		push_error("BotController: gm is null in _ready(). Assign before adding to tree.")
		return

	gm.game_state_changed.connect(_on_game_state_changed)
	gm.turn_started.connect(_on_turn_started)
	gm.card_discarded.connect(_on_card_discarded)
	gm.memory_shift_required.connect(_on_memory_shift_required)

	print("BotController: connected to GameManager signals.")

# ─── Helpers ─────────────────────────────────────────────────

## Returns true when running in headless / CI mode (skip visual waits).
func _is_headless() -> bool:
	return DisplayServer.get_name() == "headless"

## Waits [seconds] real-time seconds (skipped in headless mode).
func _wait(seconds: float) -> void:
	if _is_headless():
		return
	await gm.get_tree().create_timer(seconds).timeout

## Canonical card-value lookup (mirrors card_data.gd logic).
func _card_value(cd: CardData) -> int:
	if cd == null:
		return 0
	return cd.point_value # CardData.recalc_point_value() already handles King-of-Diamonds = 0

## Shorthand: return this bot's own memory dict  { card_idx: CardData }
func _own_memory(bot_idx: int) -> Dictionary:
	return gm.players_info[bot_idx].bot_memory.get(bot_idx, {})

## Return how many cards a bot knows about in its own hand.
func _known_count(bot_idx: int) -> int:
	return _own_memory(bot_idx).size()

## Return the total point-value of all known cards in the bot's hand.
func _known_score(bot_idx: int) -> int:
	var total := 0
	for cd in _own_memory(bot_idx).values():
		total += _card_value(cd)
	return total

## Find the index of the highest-value card the bot knows in its own hand.
## Returns -1 if the bot knows none.
func _own_highest_known_idx(bot_idx: int) -> int:
	var best_val := -1
	var best_idx := -1
	for idx in _own_memory(bot_idx):
		var v := _card_value(_own_memory(bot_idx)[idx])
		if v > best_val:
			best_val = v
			best_idx = idx
	return best_idx

## Return a list of card indices in the bot's own hand that are NOT yet known.
func _own_unknown_indices(bot_idx: int) -> Array:
	var unknown := []
	var hand_size: int = gm.players_info[bot_idx].hand.size()
	var known := _own_memory(bot_idx)
	for i in range(hand_size):
		if not known.has(i):
			unknown.append(i)
	return unknown

# ─── Signal Handlers ─────────────────────────────────────────

func _on_game_state_changed(new_state: int) -> void:
	# Initial peek is for ALL players simultaneously, handled separately.
	if new_state == GameManager.GameState.INITIAL_PEEK:
		_execute_initial_peek()
		return
	
	# If the human player is mid jump-in selection, don't interfere.
	if new_state == GameManager.GameState.TURN_JUMP_IN_SELECTION and gm.jump_in_player_idx == 0:
		return
	
	# All other states: only act when it is a bot's turn.
	var idx: int = gm.current_player_index
	if idx == 0:
		return

	match new_state:
		GameManager.GameState.TURN_RESOLVE_DRAWN:
			_execute_resolve_drawn(idx)
		GameManager.GameState.TURN_PEEK_ABILITY:
			_execute_queen_peek(idx)
		GameManager.GameState.TURN_SWAP_ABILITY:
			_execute_jack_swap(idx)
		GameManager.GameState.TURN_END_CHOICE:
			_execute_end_choice(idx)
		GameManager.GameState.TURN_CONFIRM_DUTCH:
			_execute_confirm_dutch(idx)

func _on_turn_started(player_idx: int) -> void:
	# Only bots (index >= 1) auto-draw.
	if player_idx == 0:
		return

	await _wait(1.5)

	# Guard: state may have changed during the wait.
	if gm.current_state != GameManager.GameState.TURN_START_DRAW:
		return
	if gm.current_player_index != player_idx:
		return

	gm.player_draw_card()

## Called whenever any card is discarded (by anyone).
## All bots check if they know a matching card in their own hand and jump in.
func _on_card_discarded(_discarder_idx: int, card_data: CardData) -> void:
	# Jump-in is only legal right after a discard resolves (TURN_END_CHOICE).
	# NOTE: card_discarded fires BEFORE _resolve_discard_effects(), so the state
	# has NOT yet changed to TURN_END_CHOICE at this moment. We must wait a
	# frame / small delay and then check.
	_try_bot_jump_ins(card_data)

func _on_memory_shift_required(target_player_idx: int, removed_card_idx: int) -> void:
	# A card was removed from target_player's hand at removed_card_idx.
	# Shift every bot's memory of that player accordingly.
	for bot_idx in range(1, gm.num_players):
		var mem: Dictionary = gm.players_info[bot_idx].bot_memory
		if not mem.has(target_player_idx):
			continue
		var p_mem: Dictionary = mem[target_player_idx]
		var new_mem := {}
		for c_idx in p_mem:
			if c_idx < removed_card_idx:
				new_mem[c_idx] = p_mem[c_idx]
			elif c_idx > removed_card_idx:
				new_mem[c_idx - 1] = p_mem[c_idx]
			# c_idx == removed_card_idx: the card is gone, forget it.
		mem[target_player_idx] = new_mem

# ─── Jump-In Logic ────────────────────────────────────────────

## Check every bot to see if any of them know a card that matches the
## discarded rank. The first one with a known match attempts to jump in.
## Each bot gets a staggered delay so animations fully resolve before the next one fires.
func _try_bot_jump_ins(card_data: CardData) -> void:
	# We need to wait for _resolve_discard_effects to fire and push state
	# to TURN_END_CHOICE. Give the discard animation time to land first.
	await _wait(0.6)
	
	# After the wait, verify the state is TURN_END_CHOICE before proceeding.
	if gm.current_state != GameManager.GameState.TURN_END_CHOICE:
		return
	
	for bot_idx in range(1, gm.num_players):
		# Skip if the game state already moved on (another bot jumped in, or
		# the human pressed Jump-In).
		if gm.current_state != GameManager.GameState.TURN_END_CHOICE:
			break
		
		var own_mem := _own_memory(bot_idx)
		var match_idx := -1
		for c_idx in own_mem:
			if own_mem[c_idx].rank == card_data.rank:
				match_idx = c_idx
				break
		
		if match_idx != -1:
			await _attempt_jump_in(bot_idx, match_idx)
			# After a successful jump-in a new discard fires, which starts a
			# fresh _try_bot_jump_ins chain. Stop here so only one bot acts per
			# discard event.
			break
		
		# No match for this bot — add a small gap before checking the next bot
		# so it doesn't feel instantaneous even when skipping.
		await _wait(0.5)

## Attempt a jump-in for [bot_idx] with the card at [card_idx] in its hand.
func _attempt_jump_in(bot_idx: int, card_idx: int) -> void:
	# Final guard before acting.
	if gm.current_state != GameManager.GameState.TURN_END_CHOICE:
		return
	# Validate the card_idx is still valid (memory could be stale).
	if card_idx >= gm.players_info[bot_idx].hand.size():
		return

	gm.bot_action.emit("Bot %d is JUMPING IN!" % bot_idx)

	# Use the proper start_jump_in API — no need to mutate current_player_index.
	gm.start_jump_in(bot_idx)
	# Return value intentionally ignored; outcome is handled via card_discarded / jump_in_penalty signals.
	gm.validate_jump_in(card_idx)

# ─── Bot Turn Actions ─────────────────────────────────────────

## INITIAL PEEK: All bots simultaneously memorize 2 random cards from their hand.
func _execute_initial_peek() -> void:
	for bot_idx in range(1, gm.num_players):
		var bot_info: Dictionary = gm.players_info[bot_idx]
		# Initialize an empty memory for every player.
		var mem := {}
		for p in range(gm.num_players):
			mem[p] = {}
		bot_info["bot_memory"] = mem

		var hand_size: int = (bot_info["hand"] as Array).size()
		if hand_size < 2:
			continue

		# Pick 2 distinct random indices.
		var idx1 := rng.randi_range(0, hand_size - 1)
		var idx2 := idx1
		var attempts := 0
		while idx2 == idx1 and attempts < 100:
			idx2 = rng.randi_range(0, hand_size - 1)
			attempts += 1

		if idx2 == idx1:
			# Edge case: only 1 card? Shouldn't happen in Dutch (always 4).
			idx2 = (idx1 + 1) % hand_size

		(bot_info["bot_memory"] as Dictionary)[bot_idx][idx1] = (bot_info["hand"] as Array)[idx1]
		(bot_info["bot_memory"] as Dictionary)[bot_idx][idx2] = (bot_info["hand"] as Array)[idx2]

		print("Bot %d peeked at cards %d and %d." % [bot_idx, idx1, idx2])

	gm.bot_action.emit("Bots are memorizing their cards...")
	await _wait(2.0)

## RESOLVE DRAWN CARD:
##   • Unknown cards remain → replace a random unknown card.
##   • All cards known:
##       – drawn ≥ max known → discard drawn card.
##       – drawn < max known → swap with the highest-value card.
func _execute_resolve_drawn(bot_idx: int) -> void:
	await _wait(1.5)

	# Guard after wait.
	if gm.current_state != GameManager.GameState.TURN_RESOLVE_DRAWN:
		return
	if gm.current_player_index != bot_idx:
		return

	var hand_size: int = gm.players_info[bot_idx].hand.size()
	if hand_size == 0:
		gm.player_discard_drawn_card()
		return

	var drawn: CardData = gm.drawn_card_data
	if drawn == null:
		push_error("BotController: drawn_card_data is null in RESOLVE_DRAWN state!")
		return
	var drawn_val := _card_value(drawn)

	var unknown := _own_unknown_indices(bot_idx)

	if unknown.size() > 0:
		# Prefer to replace an unknown card so the bot learns its hand.
		var swap_idx: int = unknown[rng.randi_range(0, unknown.size() - 1)]
		gm.players_info[bot_idx].bot_memory[bot_idx][swap_idx] = drawn
		gm.bot_action.emit("Bot %d swapped (unknown card → known)." % bot_idx)
		gm.player_swap_drawn_card(swap_idx)
	else:
		# All cards are known. Decide: keep or discard drawn card.
		var max_idx := _own_highest_known_idx(bot_idx)
		var max_val := _card_value(_own_memory(bot_idx).get(max_idx, null))

		if drawn_val >= max_val:
			# Drawn card is as bad or worse — discard it.
			gm.bot_action.emit("Bot %d discarded drawn card (not useful)." % bot_idx)
			gm.player_discard_drawn_card()
		else:
			# Drawn card improves the hand — swap with the worst card.
			gm.players_info[bot_idx].bot_memory[bot_idx][max_idx] = drawn
			gm.bot_action.emit("Bot %d swapped its worst card for a better one." % bot_idx)
			gm.player_swap_drawn_card(max_idx)

## QUEEN ABILITY (peek):
##   1. If the bot still has unknown cards in its own hand → peek at one.
##   2. Otherwise → peek at a card of the player with the fewest cards.
func _execute_queen_peek(bot_idx: int) -> void:
	await _wait(1.0)

	if gm.current_state != GameManager.GameState.TURN_PEEK_ABILITY:
		return
	if gm.current_player_index != bot_idx:
		return

	var unknown := _own_unknown_indices(bot_idx)

	if unknown.size() > 0:
		# Learn an unknown own card.
		var peek_idx: int = unknown[rng.randi_range(0, unknown.size() - 1)]
		var actual_card: CardData = gm.players_info[bot_idx].hand[peek_idx]
		gm.players_info[bot_idx].bot_memory[bot_idx][peek_idx] = actual_card
		gm.bot_action.emit("Bot %d peeked at its own card (now knows card %d: %s)." % [
			bot_idx, peek_idx, actual_card.display_name()])
	else:
		# All own cards known → target the player with the fewest cards.
		# Among ties, pick randomly. Skip self.
		var min_hand := 9999
		for p in range(gm.num_players):
			if p == bot_idx:
				continue
			var sz: int = gm.players_info[p].hand.size()
			if sz > 0 and sz < min_hand:
				min_hand = sz

		var candidates := []
		for p in range(gm.num_players):
			if p == bot_idx:
				continue
			if gm.players_info[p].hand.size() == min_hand:
				candidates.append(p)

		if candidates.size() == 0:
			# No valid targets (shouldn't happen in normal play).
			gm.complete_peek_ability()
			return

		var target_p: int = candidates[rng.randi_range(0, candidates.size() - 1)]
		# Pick a card the bot doesn't already know from that player.
		var target_mem: Dictionary = gm.players_info[bot_idx].bot_memory.get(target_p, {})
		var target_hand_size: int = gm.players_info[target_p].hand.size()

		var unknown_opp := []
		for i in range(target_hand_size):
			if not target_mem.has(i):
				unknown_opp.append(i)

		var peek_idx: int
		if unknown_opp.size() > 0:
			peek_idx = unknown_opp[rng.randi_range(0, unknown_opp.size() - 1)]
		else:
			# All cards of target are already known — pick any.
			peek_idx = rng.randi_range(0, target_hand_size - 1)

		var actual_card: CardData = gm.players_info[target_p].hand[peek_idx]
		if not gm.players_info[bot_idx].bot_memory.has(target_p):
			gm.players_info[bot_idx].bot_memory[target_p] = {}
		gm.players_info[bot_idx].bot_memory[target_p][peek_idx] = actual_card
		gm.bot_action.emit("Bot %d peeked at Player %d's card %d (%s)." % [
			bot_idx, target_p, peek_idx, actual_card.display_name()])

	gm.complete_peek_ability()

## JACK ABILITY (swap two cards):
##   Smart path: if bot knows a high own card AND a low opponent card,
##               swap to improve its hand (give away the bad card).
##   Fallback:   swap two random cards from different other players.
func _execute_jack_swap(bot_idx: int) -> void:
	await _wait(1.5)

	if gm.current_state != GameManager.GameState.TURN_SWAP_ABILITY:
		return
	if gm.current_player_index != bot_idx:
		return

	gm.bot_action.emit("Bot %d is choosing cards to swap (Jack)..." % bot_idx)

	# ── Smart path ──────────────────────────────────────────────
	# Find bot's highest-value known card (the one it most wants to get rid of).
	var my_high_idx := _own_highest_known_idx(bot_idx)
	var my_high_val := -1
	if my_high_idx != -1:
		my_high_val = _card_value(_own_memory(bot_idx).get(my_high_idx, null))

	# Find "best" opponent card: lowest-value card we know about from any opponent.
	var opp_low_val := 9999
	var opp_low_p := -1
	var opp_low_c := -1

	for p in range(gm.num_players):
		if p == bot_idx:
			continue
		var p_mem: Dictionary = gm.players_info[bot_idx].bot_memory.get(p, {})
		for c_idx in p_mem:
			# Make sure the index is still valid.
			if c_idx >= gm.players_info[p].hand.size():
				continue
			var v := _card_value(p_mem[c_idx])
			if v < opp_low_val:
				opp_low_val = v
				opp_low_p = p
				opp_low_c = c_idx

	# Use the smart swap only if we know BOTH cards and it genuinely helps
	# (i.e. we give away a higher card and receive a lower card).
	if my_high_idx != -1 and opp_low_p != -1 and my_high_val > opp_low_val:
		# Smart swap: p1=self (high card), p2=opponent (low card).
		_update_memory_on_swap(bot_idx, my_high_idx, opp_low_p, opp_low_c)
		gm.bot_action.emit("Bot %d swapped its card %d with Player %d's card %d (smart)." % [
			bot_idx, my_high_idx, opp_low_p, opp_low_c])
		gm.complete_swap_ability(bot_idx, my_high_idx, opp_low_p, opp_low_c)
		return

	# ── Fallback: random swap between two different other players ──
	# Build a list of (player, card_idx) for all opponents that have cards.
	var opponent_slots := []
	for p in range(gm.num_players):
		if p == bot_idx:
			continue
		var hand_size: int = gm.players_info[p].hand.size()
		for c in range(hand_size):
			opponent_slots.append({"p": p, "c": c})

	if opponent_slots.size() < 2:
		# Not enough opponent cards — just end turn without completing.
		# (This path is extremely rare.)
		gm.complete_swap_ability(0, 0, 0, 0) # Edge-case no-op.
		return

	# Shuffle and pick the first two that belong to DIFFERENT players.
	opponent_slots.shuffle()
	var slot1 = opponent_slots[0]
	var slot2 = null
	for s in opponent_slots:
		if s.p != slot1.p:
			slot2 = s
			break

	if slot2 == null:
		# All non-self cards belong to the same player — just pick any two.
		if opponent_slots.size() >= 2:
			slot2 = opponent_slots[1]
		else:
			gm.complete_swap_ability(slot1.p, slot1.c, slot1.p, slot1.c)
			return

	_update_memory_on_swap(slot1.p, slot1.c, slot2.p, slot2.c)
	gm.bot_action.emit("Bot %d swapped Player %d card %d with Player %d card %d (random)." % [
		bot_idx, slot1.p, slot1.c, slot2.p, slot2.c])
	gm.complete_swap_ability(slot1.p, slot1.c, slot2.p, slot2.c)

## END-OF-TURN CHOICE:
##   Call Dutch if: knows all own cards AND total score < 7 AND nobody else called Dutch.
##   Otherwise: end turn.
func _execute_end_choice(bot_idx: int) -> void:
	await _wait(0.9)

	if gm.current_state != GameManager.GameState.TURN_END_CHOICE:
		return
	if gm.current_player_index != bot_idx:
		return

	var hand_size: int = gm.players_info[bot_idx].hand.size()
	var known_cnt: int = _known_count(bot_idx)

	if hand_size > 0 and known_cnt == hand_size:
		var score := _known_score(bot_idx)
		if score < 7 and gm.dutch_caller_index == -1 and gm.players_info[bot_idx].can_call_dutch:
			gm.bot_action.emit("Bot %d calls DUTCH! (score: %d)" % [bot_idx, score])
			gm.call_dutch(bot_idx)
			return

	gm.end_turn()

## CONFIRM DUTCH: Bot automatically confirms (game ends).
func _execute_confirm_dutch(bot_idx: int) -> void:
	await _wait(1.5)

	if gm.current_state != GameManager.GameState.TURN_CONFIRM_DUTCH:
		return
	if gm.current_player_index != bot_idx:
		return

	gm.confirm_dutch()

# ─── Memory Helpers ───────────────────────────────────────────

## Update all bots' memories to reflect a card swap between two positions.
## Called by the bot performing a Jack swap BEFORE calling complete_swap_ability.
func _update_memory_on_swap(p1: int, c1: int, p2: int, c2: int) -> void:
	for bot_idx in range(1, gm.num_players):
		var mem: Dictionary = gm.players_info[bot_idx].bot_memory

		# Ensure sub-dicts exist.
		if not mem.has(p1): mem[p1] = {}
		if not mem.has(p2): mem[p2] = {}

		var knew_p1: CardData = mem[p1].get(c1, null)
		var knew_p2: CardData = mem[p2].get(c2, null)

		# After the swap:
		#   position (p1, c1) now holds what used to be at (p2, c2).
		#   position (p2, c2) now holds what used to be at (p1, c1).
		if knew_p2 != null:
			mem[p1][c1] = knew_p2
		else:
			mem[p1].erase(c1) # We no longer know what's here.

		if knew_p1 != null:
			mem[p2][c2] = knew_p1
		else:
			mem[p2].erase(c2) # We no longer know what's here.

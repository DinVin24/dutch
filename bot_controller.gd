extends Node
class_name BotController

# ============================================================
# BotController — Simple AI for all non-human players.
#
# MEMORY: bot_memory[bot_idx][card_idx] = CardData
#   A bot only stores what it has peeked at (2 cards at start + any abilities).
#   Unknown cards are treated as value 99 in decisions.
# ============================================================

const UNKNOWN_VALUE := 99

var gm: Node = null
var rng := RandomNumberGenerator.new()

# ─── Lifecycle ───────────────────────────────────────────────

func _ready() -> void:
	rng.randomize()
	if not gm:
		push_error("BotController: gm is null in _ready().")
		return
	gm.game_state_changed.connect(_on_game_state_changed)
	gm.turn_started.connect(_on_turn_started)
	gm.card_discarded.connect(_on_card_discarded)
	gm.memory_shift_required.connect(_on_memory_shift_required)

func _is_headless() -> bool:
	return DisplayServer.get_name() == "headless"

func _wait(seconds: float) -> void:
	if _is_headless(): return
	await gm.get_tree().create_timer(seconds, false).timeout

# ─── Memory helpers ──────────────────────────────────────────

## Returns a bot's own card memory dict { card_idx: CardData }
func _mem(bot_idx: int) -> Dictionary:
	return gm.players_info[bot_idx].bot_memory.get(bot_idx, {})

## Returns the effective value of card at index i in the bot's own hand.
## Unknown cards are treated as UNKNOWN_VALUE.
func _effective_value(bot_idx: int, card_idx: int) -> int:
	var m := _mem(bot_idx)
	if m.has(card_idx):
		return m[card_idx].point_value
	return UNKNOWN_VALUE

## Returns the hand-index with the highest effective value. -1 if hand is empty.
func _worst_card_idx(bot_idx: int) -> int:
	var hand_size: int = gm.players_info[bot_idx].hand.size()
	if hand_size == 0: return -1
	var best_val := -1
	var best_idx := -1
	for i in range(hand_size):
		var v := _effective_value(bot_idx, i)
		if v > best_val:
			best_val = v
			best_idx = i
	return best_idx

## Builds a multi-line hand summary string for console output.
## Known cards are prefixed with *, unknown with a plain name.
func _hand_summary(bot_idx: int) -> String:
	var hand: Array = gm.players_info[bot_idx].hand
	var mem := _mem(bot_idx)
	var lines := "Player %d:\n" % bot_idx
	for i in range(hand.size()):
		if mem.has(i):
			lines += "  *%s\n" % mem[i].display_name()
		else:
			lines += "  %s (unknown)\n" % hand[i].display_name()
	return lines.strip_edges()

# ─── Signal Handlers ─────────────────────────────────────────

func _on_game_state_changed(new_state: int) -> void:
	if new_state == GameManager.GameState.INITIAL_PEEK:
		_execute_initial_peek()
		return

	var idx: int
	if new_state == GameManager.GameState.TURN_PEEK_ABILITY or new_state == GameManager.GameState.TURN_SWAP_ABILITY:
		idx = gm.active_ability_player
	else:
		idx = gm.current_player_index
		
	if idx == 0: return  # Human handles their own turns

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

## Rule 2: Mandatory draw at the start of a bot's turn.
func _on_turn_started(bot_idx: int) -> void:
	if bot_idx == 0: return
	
	# Proactive buy logic: if I have money, buy an egg!
	if gm.players_info[bot_idx].money >= 50:
		await _wait(0.5)
		gm.buy_ability(bot_idx)
		await _wait(1.0) # Wait for animation
		
	await _wait(1.0)
	if gm.current_state != GameManager.GameState.TURN_START_DRAW: return
	if gm.current_player_index != bot_idx: return
	gm.player_draw_card()

## Rule 1: Constant jump-in monitoring — fires every time any card is discarded.
func _on_card_discarded(_discarder_idx: int, card_data: CardData) -> void:
	_try_jump_ins(card_data)

## Shift memory indices when a card is removed from someone's hand.
func _on_memory_shift_required(target_player_idx: int, removed_card_idx: int) -> void:
	for bot_idx in range(1, gm.num_players):
		var mem: Dictionary = gm.players_info[bot_idx].bot_memory
		if not mem.has(target_player_idx) or target_player_idx == -1: continue
		var p_mem: Dictionary = mem[target_player_idx]
		var new_mem := {}
		for c_idx in p_mem:
			if c_idx < removed_card_idx:
				new_mem[c_idx] = p_mem[c_idx]
			elif c_idx > removed_card_idx:
				new_mem[c_idx - 1] = p_mem[c_idx]
			# c_idx == removed_card_idx: card is gone, forget it
		mem[target_player_idx] = new_mem

# ─── Jump-In ─────────────────────────────────────────────────

## Check all bots — if any KNOWS a card in its hand matching the discarded rank, jump in.
func _try_jump_ins(card_data: CardData) -> void:
	await _wait(0.5)
	if gm.current_state != GameManager.GameState.TURN_END_CHOICE: return

	for bot_idx in range(1, gm.num_players):
		if gm.current_state != GameManager.GameState.TURN_END_CHOICE: break
		
		var match_idx := -1
		for c_idx in _mem(bot_idx):
			var known: CardData = _mem(bot_idx)[c_idx]
			if known != null and known.rank == card_data.rank:
				match_idx = c_idx
				break

		if match_idx != -1:
			await _wait(0.3)
			if gm.current_state != GameManager.GameState.TURN_END_CHOICE: break
			if match_idx >= gm.players_info[bot_idx].hand.size(): break
			var jumped_card: CardData = _mem(bot_idx)[match_idx]
			var top_card: CardData = gm.deck_manager.discard_pile[-1] if gm.deck_manager.discard_pile.size() > 0 else null
			var over_str: String = top_card.display_name() if top_card != null else "?"
			print("Player %d jumped in with %s over %s" % [bot_idx, jumped_card.display_name(), over_str])
			gm.bot_action.emit("Player %d jumped in with %s over %s." % [bot_idx, jumped_card.display_name(), over_str])
			gm.start_jump_in(bot_idx)
			gm.validate_jump_in(match_idx)
			break  # Only one jump-in per discard event

# ─── Bot Turn Actions ─────────────────────────────────────────

## INITIAL PEEK: each bot learns exactly 2 of its 4 dealt cards.
func _execute_initial_peek() -> void:
	for bot_idx in range(1, gm.num_players):
		var bot_info: Dictionary = gm.players_info[bot_idx]
		# Build a fresh memory structure for all players
		var mem := {}
		for p in range(gm.num_players): mem[p] = {}
		bot_info["bot_memory"] = mem

		var hand_size: int = bot_info["hand"].size()
		if hand_size < 2: continue

		var idx1 := rng.randi_range(0, hand_size - 1)
		var idx2 := idx1
		while idx2 == idx1:
			idx2 = rng.randi_range(0, hand_size - 1)

		mem[bot_idx][idx1] = bot_info["hand"][idx1]
		mem[bot_idx][idx2] = bot_info["hand"][idx2]
		print("Player %d learned cards at positions %d (*%s) and %d (*%s)." % [
			bot_idx, idx1, (bot_info["hand"] as Array)[idx1].display_name(),
			idx2, (bot_info["hand"] as Array)[idx2].display_name()])

	await _wait(2.0)

## RESOLVE DRAWN: compare drawn card against worst effective card and decide.
func _execute_resolve_drawn(bot_idx: int) -> void:
	await _wait(1.5)
	if gm.current_state != GameManager.GameState.TURN_RESOLVE_DRAWN: return
	if gm.current_player_index != bot_idx: return

	var drawn: CardData = gm.drawn_card_data
	if drawn == null: return
	var drawn_val: int = drawn.point_value

	var worst_idx := _worst_card_idx(bot_idx)
	if worst_idx == -1:
		gm.player_discard_drawn_card()
		return

	var worst_val := _effective_value(bot_idx, worst_idx)

	if drawn_val < worst_val:
		# Swap: drawn card takes the worst slot, old worst goes to discard
		var card_name: String = ("unknown" if worst_val == UNKNOWN_VALUE
			else _mem(bot_idx)[worst_idx].display_name())
		# Update memory BEFORE building summary so * reflects new state
		gm.players_info[bot_idx].bot_memory[bot_idx][worst_idx] = drawn
		var summary := _hand_summary(bot_idx)
		print("%s\nDrew %s\nDiscarded %s for %s" % [
			summary, drawn.display_name(), card_name, drawn.display_name()])
		gm.bot_action.emit("Player %d drew %s. Discarded %s." % [bot_idx, drawn.display_name(), card_name])
		gm.player_swap_drawn_card(worst_idx)
	else:
		# Drawn card is no better — just discard it
		var summary := _hand_summary(bot_idx)
		print("%s\nDrew %s\nDiscarded %s" % [summary, drawn.display_name(), drawn.display_name()])
		gm.bot_action.emit("Player %d drew %s. Discarded %s." % [bot_idx, drawn.display_name(), drawn.display_name()])
		gm.player_discard_drawn_card()

## QUEEN ABILITY: learn an unknown own card first; otherwise learn any card on the board.
func _execute_queen_peek(bot_idx: int) -> void:
	await _wait(1.0)
	if gm.current_state != GameManager.GameState.TURN_PEEK_ABILITY: return
	if gm.current_player_index != bot_idx: return

	# Priority: own unknown card
	var own_unknowns := []
	for i in range(gm.players_info[bot_idx].hand.size()):
		if _effective_value(bot_idx, i) == UNKNOWN_VALUE:
			own_unknowns.append(i)

	if own_unknowns.size() > 0:
		var peek_idx: int = own_unknowns[rng.randi_range(0, own_unknowns.size() - 1)]
		var card: CardData = gm.players_info[bot_idx].hand[peek_idx]
		if not gm.players_info[bot_idx].bot_memory.has(bot_idx):
			gm.players_info[bot_idx].bot_memory[bot_idx] = {}
		gm.players_info[bot_idx].bot_memory[bot_idx][peek_idx] = card
		print("%s\nLearned *%s (Queen ability)" % [_hand_summary(bot_idx), card.display_name()])
		gm.bot_action.emit("Player %d used a Queen to reveal %s." % [bot_idx, card.display_name()])
	else:
		# Fallback: pick any card from another player
		var candidates := []
		for p in range(gm.num_players):
			if p == bot_idx: continue
			for c in range(gm.players_info[p].hand.size()):
				candidates.append({"p": p, "c": c})
		if candidates.size() > 0:
			var pick = candidates[rng.randi_range(0, candidates.size() - 1)]
			var card: CardData = gm.players_info[pick.p].hand[pick.c]
			if not gm.players_info[bot_idx].bot_memory.has(pick.p):
				gm.players_info[bot_idx].bot_memory[pick.p] = {}
			gm.players_info[bot_idx].bot_memory[pick.p][pick.c] = card
			print("Player %d used a Queen to learn opponent card: *%s" % [bot_idx, card.display_name()])
			gm.bot_action.emit("Player %d used a Queen to reveal %s." % [bot_idx, card.display_name()])

	gm.complete_peek_ability()

## JACK ABILITY: swap 2 random cards from any two different opponent slots.
func _execute_jack_swap(bot_idx: int) -> void:
	await _wait(1.5)
	if gm.current_state != GameManager.GameState.TURN_SWAP_ABILITY: return
	if gm.current_player_index != bot_idx: return

	gm.bot_action.emit("Player %d used a Jack." % bot_idx)

	# Gather all (player, card_idx) pairs from opponents
	var slots := []
	for p in range(gm.num_players):
		if p == bot_idx: continue
		for c in range(gm.players_info[p].hand.size()):
			slots.append({"p": p, "c": c})

	if slots.size() < 2:
		gm.complete_swap_ability(0, 0, 0, 0)  # Failsafe edge case
		return

	slots.shuffle()
	var s1 = slots[0]
	var s2 = null
	for s in slots:
		if s.p != s1.p:
			s2 = s
			break
	if s2 == null: s2 = slots[1]  # fallback: same player, different card

	_update_memory_on_swap(bot_idx, s1.p, s1.c, s2.p, s2.c)
	gm.complete_swap_ability(s1.p, s1.c, s2.p, s2.c)

## END CHOICE: call Dutch if all cards are known and score < 7.
## Also proactively use abilities if I have them.
func _execute_end_choice(bot_idx: int) -> void:
	await _wait(0.9)
	if gm.current_state != GameManager.GameState.TURN_END_CHOICE: return
	if gm.current_player_index != bot_idx: return

	# 1. Use Abilities first
	var pool: Array = gm.players_info[bot_idx].abilities
	if not pool.is_empty():
		var ab = pool[0] # Just use the first one for now
		var target = _get_best_target_for(bot_idx, ab)
		print("Bot ", bot_idx, " using ability: ", ab, " on target ", target)
		gm.play_ability(bot_idx, ab, target)
		await gm.ability_finished # Wait for it to complete
		await _wait(0.5)
		if gm.current_state != GameManager.GameState.TURN_END_CHOICE: return
		
	# 2. Dutch Logic
	var hand_size: int = gm.players_info[bot_idx].hand.size()
	var all_known := true
	for i in range(hand_size):
		if _effective_value(bot_idx, i) == UNKNOWN_VALUE:
			all_known = false
			break

	if all_known and hand_size > 0:
		var score := 0
		for c in _mem(bot_idx).values(): score += c.point_value
		if score < 7 and gm.dutch_caller_index == -1 and gm.players_info[bot_idx].can_call_dutch:
			gm.bot_action.emit("Player %d calls DUTCH! (score: %d)" % [bot_idx, score])
			gm.call_dutch(bot_idx)
			return

	gm.end_turn()

func _get_best_target_for(bot_idx: int, ab: String) -> int:
	match ab:
		"refuel", "trim_off", "perfect_match", "half_off":
			return bot_idx # Self-benefit
		"bottoms_up", "boulder", "jumpscare", "inflation", "shuffle":
			return _get_leading_opponent_idx(bot_idx)
		"skip":
			# Target next player
			return (bot_idx + gm.turn_direction + gm.num_players) % gm.num_players
	return -1

func _get_leading_opponent_idx(bot_idx: int) -> int:
	var best_p = -1
	var min_score = 1000
	
	for i in range(gm.num_players):
		if i == bot_idx or gm.players_info[i].is_eliminated: continue
		
		# We estimate their score based on what we've memorized
		var estimated_score = 0
		var memories = gm.players_info[bot_idx].bot_memory.get(i, {})
		for c_idx in range(gm.players_info[i].hand.size()):
			if memories.has(c_idx):
				estimated_score += memories[c_idx].point_value
			else:
				estimated_score += 7 # Assume average value for unknown cards
		
		if estimated_score < min_score:
			min_score = estimated_score
			best_p = i
			
	return best_p if best_p != -1 else 0

## CONFIRM DUTCH: bot always confirms.
func _execute_confirm_dutch(bot_idx: int) -> void:
	await _wait(1.5)
	if gm.current_state != GameManager.GameState.TURN_CONFIRM_DUTCH: return
	if gm.current_player_index != bot_idx: return
	gm.confirm_dutch()

# ─── Memory Utility ───────────────────────────────────────────

## Update all bots' memories when two card slots are swapped (e.g. after Jack).
func _update_memory_on_swap(_acting_bot: int, p1: int, c1: int, p2: int, c2: int) -> void:
	for bot_idx in range(1, gm.num_players):
		var mem: Dictionary = gm.players_info[bot_idx].bot_memory
		if not mem.has(p1): mem[p1] = {}
		if not mem.has(p2): mem[p2] = {}
		var knew_p1: CardData = mem[p1].get(c1, null)
		var knew_p2: CardData = mem[p2].get(c2, null)
		if knew_p2 != null: mem[p1][c1] = knew_p2
		else: mem[p1].erase(c1)
		if knew_p1 != null: mem[p2][c2] = knew_p1
		else: mem[p2].erase(c2)

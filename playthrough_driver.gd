extends Node

## Drives one full local match on an already-loaded GameBoard3D.

signal finished

const HUMAN := 0
const ACTION_DELAY := 2.8
const PEEK_DELAY := 2.5

var _board: Node3D
var _gm: Node

func start(board: Node3D) -> void:
	_board = board
	_gm = get_node("/root/GameManager")
	await _run_match()
	finished.emit()

func _log(msg: String) -> void:
	print("[DEMO] ", msg)

func _run_match() -> void:
	_log("3/5 Deal + peek phase...")
	await _wait_for_state(_gm.GameState.INITIAL_PEEK, 8.0)
	await _automate_initial_peek()

	_log("4/5 Playing turns (you + 3 bots)...")
	var safety := 0
	var human_turns := 0
	while _gm.current_state != _gm.GameState.GAME_OVER and safety < 300:
		safety += 1
		await get_tree().create_timer(0.4).timeout
		if not _human_must_act():
			continue
		await get_tree().create_timer(ACTION_DELAY).timeout
		if await _human_turn(human_turns):
			human_turns += 1

	_log("5/5 Game over!")

func _wait_for_state(target: int, max_sec: float) -> void:
	var elapsed := 0.0
	while _gm.current_state != target and elapsed < max_sec:
		await get_tree().process_frame
		elapsed += get_process_delta_time()

func _automate_initial_peek() -> void:
	if _gm.current_state != _gm.GameState.INITIAL_PEEK:
		_log("Peek skipped (state=%d)" % _gm.current_state)
		return

	var hand: Array = _board.player_hands[HUMAN]
	if hand.size() >= 2:
		for i in range(2):
			var card: Card3D = hand[i]
			if is_instance_valid(card):
				card.is_being_peeked = true
				card.animate_flip(true, -1.0, false)
		await get_tree().create_timer(PEEK_DELAY).timeout
		for i in range(2):
			var card: Card3D = hand[i]
			if is_instance_valid(card):
				card.is_being_peeked = false
				card.animate_flip(false, -1.0, false)

	_gm.complete_initial_peek()
	_log("Peek done — match begins")
	await get_tree().create_timer(1.0).timeout

func _human_must_act() -> bool:
	match _gm.current_state:
		_gm.GameState.TURN_START_DRAW:
			return _gm.current_player_index == HUMAN and _gm.can_player_draw(HUMAN)
		_gm.GameState.TURN_RESOLVE_DRAWN:
			return _gm.current_player_index == HUMAN
		_gm.GameState.TURN_END_CHOICE:
			return _gm.current_player_index == HUMAN
		_gm.GameState.TURN_CONFIRM_DUTCH:
			return _gm.can_player_confirm_dutch(HUMAN)
		_gm.GameState.TURN_PEEK_ABILITY:
			return _gm.active_ability_player == HUMAN
		_gm.GameState.TURN_SWAP_ABILITY:
			return _gm.active_ability_player == HUMAN
		_gm.GameState.TURN_JUMP_IN_SELECTION:
			return _gm.jump_in_player_idx == HUMAN
	return false

func _human_turn(turn_count: int) -> bool:
	match _gm.current_state:
		_gm.GameState.TURN_START_DRAW:
			_log("Your turn — drawing card (R)")
			_gm.player_draw_card()
			return true
		_gm.GameState.TURN_RESOLVE_DRAWN:
			return _resolve_drawn()
		_gm.GameState.TURN_END_CHOICE:
			if turn_count == 2 and not _gm.players_info[HUMAN].abilities.has("jumpscare"):
				_gm.players_info[HUMAN].abilities.append("jumpscare")
				_board._update_ability_visuals(HUMAN)
				_log("Using Jumpscare on Player 2")
				if _gm.play_ability(HUMAN, "jumpscare", 1):
					await get_tree().create_timer(2.5).timeout
					return true
			if turn_count >= 4 and _gm.can_player_call_dutch(HUMAN):
				_log("Calling DUTCH (D)")
				_gm.call_dutch(HUMAN)
				return true
			_log("Ending turn (Enter)")
			_gm.end_turn()
			return true
		_gm.GameState.TURN_CONFIRM_DUTCH:
			_log("Confirming DUTCH (C)")
			_gm.confirm_dutch()
			return true
		_gm.GameState.TURN_PEEK_ABILITY:
			_log("Queen peek")
			await _auto_queen_peek()
			return true
		_gm.GameState.TURN_SWAP_ABILITY:
			_log("Jack swap")
			await _auto_jack_swap()
			return true
		_gm.GameState.TURN_JUMP_IN_SELECTION:
			_log("Jump-In cancel")
			_gm.cancel_jump_in()
			return true
	return false

func _resolve_drawn() -> bool:
	var drawn = _gm.drawn_card_data
	if drawn == null:
		return false
	var hand: Array = _gm.players_info[HUMAN].hand
	if hand.is_empty():
		_gm.player_discard_drawn_card()
		_log("Discard drawn (beer)")
		return true
	var worst_idx := 0
	var worst_val := -1
	for i in range(hand.size()):
		var v: int = (hand[i] as CardData).point_value
		if v > worst_val:
			worst_val = v
			worst_idx = i
	if drawn.point_value < worst_val:
		_log("Swap drawn %s" % drawn.display_name())
		_gm.player_swap_drawn_card(worst_idx)
	else:
		_log("Discard drawn %s (beer)" % drawn.display_name())
		_gm.player_discard_drawn_card()
	return true

func _auto_queen_peek() -> void:
	if not _gm.can_player_complete_peek_ability(HUMAN):
		return
	# Learn one opponent card into memory (same as bot fallback).
	for p in range(1, _gm.num_players):
		var hand: Array = _gm.players_info[p].hand
		if hand.is_empty():
			continue
		if not _gm.players_info[HUMAN].bot_memory.has(p):
			_gm.players_info[HUMAN].bot_memory[p] = {}
		_gm.players_info[HUMAN].bot_memory[p][0] = hand[0]
		break
	_gm.complete_peek_ability()

func _auto_jack_swap() -> void:
	if not _gm.can_player_complete_swap_ability(HUMAN):
		return
	var slots: Array = []
	for p in range(_gm.num_players):
		for c in range(_gm.players_info[p].hand.size()):
			slots.append({"p": p, "c": c})
	if slots.size() < 2:
		_gm.complete_swap_ability(-1, -1, -1, -1)
		return
	var s1: Dictionary = slots[0]
	var s2: Dictionary = slots[1]
	for s in slots:
		if s.p != s1.p:
			s2 = s
			break
	_gm.complete_swap_ability(s1.p, s1.c, s2.p, s2.c)

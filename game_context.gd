extends Node

## Live game-state snapshot for the assistant (Chippy).
## Reads GameManager FSM + can_player_* rules to build a factual, local-only
## picture of "what can this player do right now". Never synced over network.

## Returns a dictionary describing the local player's current situation.
## All booleans come straight from GameManager's authoritative rule checks,
## so the assistant can answer situational questions without guessing.
func build_snapshot(player_idx: int = -1) -> Dictionary:
	var gm := get_node_or_null("/root/GameManager")
	if gm == null:
		return _empty_snapshot()

	var idx := player_idx
	if idx < 0:
		idx = gm.local_player_idx if gm.is_multiplayer else 0

	if idx < 0 or idx >= gm.players_info.size():
		return _empty_snapshot()

	var info: Dictionary = gm.players_info[idx]
	var state_name: String = gm.GameState.keys()[gm.current_state]

	var allowed: Array = []
	if gm.can_player_draw(idx):
		allowed.append("draw")
	if gm.can_player_discard_drawn_card(idx):
		allowed.append("discard_drawn")
		allowed.append("swap_drawn")
	if gm.can_player_start_jump_in(idx):
		allowed.append("jump_in")
	if gm.can_player_end_turn(idx):
		allowed.append("end_turn")
	if gm.can_player_call_dutch(idx):
		allowed.append("call_dutch")
	if gm.can_player_confirm_dutch(idx):
		allowed.append("confirm_dutch")
		allowed.append("forfeit_dutch")
	if gm.can_player_complete_peek_ability(idx):
		allowed.append("peek_ability")
	if gm.can_player_complete_swap_ability(idx):
		allowed.append("swap_ability")

	var top_rank := ""
	if gm.deck_manager != null:
		var top: CardData = gm.deck_manager.get_top_discard()
		if top != null:
			top_rank = top.rank

	var drawn_rank := ""
	if gm.drawn_card_data != null:
		drawn_rank = gm.drawn_card_data.rank

	return {
		"valid": true,
		"player_idx": idx,
		"fsm_state": state_name,
		"is_my_turn": gm.current_player_index == idx,
		"in_game": gm.current_state != gm.GameState.GAME_OVER \
				and gm.current_state != gm.GameState.INITIALIZING,
		"beers": int(info.get("beers", 0)),
		"money": int(info.get("money", 0)),
		"hand_size": (info.get("hand", []) as Array).size(),
		"is_eliminated": bool(info.get("is_eliminated", false)),
		"dutch_called": gm.dutch_caller_index != -1,
		"dutch_caller_is_me": gm.dutch_caller_index == idx,
		"win_lowest": gm.win_condition_lowest_wins,
		"top_discard_rank": top_rank,
		"drawn_card_rank": drawn_rank,
		"allowed_actions": allowed,
		"action_hint": _action_hint(state_name, gm.current_player_index == idx, allowed),
	}

## One short, factual sentence about what the player should focus on now.
func _action_hint(state_name: String, is_my_turn: bool, allowed: Array) -> String:
	if not is_my_turn and not allowed.has("jump_in"):
		return "It's not your turn yet. Watch the discard pile for a Jump-In chance."
	match state_name:
		"INITIAL_PEEK":
			return "Peek at 2 of your own cards, then remember the low ones."
		"TURN_START_DRAW":
			return "Draw a card from the deck to start your turn."
		"TURN_RESOLVE_DRAWN":
			return "Swap the drawn card into your hand, or discard it."
		"TURN_PEEK_ABILITY":
			return "Queen ability: click any face-down card to peek at it."
		"TURN_SWAP_ABILITY":
			return "Jack ability: pick two cards to blindly swap."
		"TURN_END_CHOICE":
			return "End your turn, or call Dutch if you think you're lowest."
		"TURN_JUMP_IN_SELECTION":
			return "Pick a card that matches the discard rank exactly."
		"TURN_CONFIRM_DUTCH":
			return "Confirm Dutch to end the game, or forfeit to keep playing."
		_:
			if allowed.has("jump_in"):
				return "You can Jump-In if you hold a card matching the discard."
			return ""

func _empty_snapshot() -> Dictionary:
	return {
		"valid": false,
		"player_idx": -1,
		"fsm_state": "",
		"is_my_turn": false,
		"in_game": false,
		"beers": 0,
		"money": 0,
		"hand_size": 0,
		"is_eliminated": false,
		"dutch_called": false,
		"dutch_caller_is_me": false,
		"win_lowest": true,
		"top_discard_rank": "",
		"drawn_card_rank": "",
		"allowed_actions": [],
		"action_hint": "",
	}

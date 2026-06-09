extends Node
class_name LlmPlayerAgent

## Autonomous bot seat driven by the local LM Studio model. GameManager remains
## authoritative: every proposed action passes through AgentToolRegistry.

const UNKNOWN_VALUE := 99
const LLM_ACTION_TIMEOUT_SEC := 8.0

var gm: Node = null
var _busy := false
var _scheduled := false
var _decision_pending := false
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	if gm == null:
		push_error("LlmPlayerAgent: gm is null in _ready().")
		return
	gm.game_state_changed.connect(_on_game_state_changed)
	gm.turn_started.connect(_on_turn_started)
	gm.card_discarded.connect(_on_card_discarded)

func _on_turn_started(player_idx: int) -> void:
	if _manages_player(player_idx):
		_schedule_decision()

func _on_game_state_changed(_new_state: int) -> void:
	var player_idx := _player_idx()
	if not _manages_player(player_idx):
		return
	if gm.current_player_index == player_idx or gm.active_ability_player == player_idx:
		_schedule_decision()

func _on_card_discarded(_discarder_idx: int, card_data: CardData) -> void:
	var player_idx := _player_idx()
	if not _manages_player(player_idx):
		return
	if _known_matching_card(player_idx, card_data.rank) != -1:
		_schedule_decision()

func _schedule_decision() -> void:
	if _busy:
		_decision_pending = true
		return
	if _scheduled:
		return
	_scheduled = true
	call_deferred("_run_scheduled_decision")

func _run_scheduled_decision() -> void:
	_scheduled = false
	if _busy:
		_decision_pending = true
		return
	_busy = true
	await get_tree().create_timer(0.08, false).timeout
	var player_idx := _player_idx()
	if _manages_player(player_idx) and _has_relevant_action(player_idx):
		var acted := await _try_immediate_action(player_idx)
		if not acted:
			acted = await _request_llm_action(player_idx)
		if not acted:
			await _fallback_action(player_idx)
	_busy = false
	if _decision_pending:
		_decision_pending = false
		_schedule_decision()

func _request_llm_action(player_idx: int) -> bool:
	var messages := [
		{
			"role": "system",
			"content": _system_prompt(player_idx),
		},
		{
			"role": "user",
			"content": JSON.stringify(_decision_context(player_idx)),
		},
	]
	var tools: Array = _legal_action_tool_schemas(player_idx)
	if tools.is_empty():
		return false
	var response: Dictionary = await LmStudioClient.chat_completion(
		messages,
		tools,
		"fast",
		{
			"tool_choice": "required",
			"max_tokens": 96,
			"timeout_sec": LLM_ACTION_TIMEOUT_SEC,
		}
	)
	if not response.get("ok", false):
		gm.bot_action.emit("LM Player %d: local model slow or unavailable; using fallback." % player_idx)
		return false
	var calls: Array = response.get("tool_calls", [])
	if calls.is_empty():
		return false
	var call: Dictionary = calls[0]
	var tool_name := str(call.get("name", ""))
	var arguments: Dictionary = call.get("arguments", {})
	var result: Dictionary = await AgentToolRegistry.execute_tool(tool_name, arguments, player_idx)
	if result.get("ok", false):
		gm.bot_action.emit("LM Player %d used %s." % [player_idx, tool_name])
		if tool_name == "buy_ability":
			var data: Dictionary = result.get("data", {})
			if data.get("success", false):
				print("[LLM Agent] Bought ability, scheduling next decision in the same FSM state.")
				_schedule_decision()
		return true
	return false

func _try_immediate_action(player_idx: int) -> bool:
	if gm.can_player_draw(player_idx):
		return await _execute_fallback("draw_card", {}, player_idx)
	if gm.can_player_confirm_dutch(player_idx):
		return await _execute_fallback("confirm_dutch", {}, player_idx)
	var jump_idx := _known_matching_card(player_idx, _top_discard_rank())
	if jump_idx != -1 and gm.can_player_start_jump_in(player_idx):
		return await _execute_fallback("attempt_jump_in", {"card_index": jump_idx}, player_idx)
	if gm.can_player_end_turn(player_idx) and not _has_owned_ability(player_idx):
		if _should_call_dutch(player_idx):
			return await _execute_fallback("call_dutch", {}, player_idx)
		return await _execute_fallback("end_turn", {}, player_idx)
	return false

func _has_owned_ability(player_idx: int) -> bool:
	var abilities: Array = gm.players_info[player_idx].get("abilities", [])
	return abilities.any(func(ability): return str(ability) != "")

func _legal_action_tool_schemas(player_idx: int) -> Array:
	var allowed: Array = GameContext.build_snapshot(player_idx).get("allowed_actions", [])
	var tool_names: Array = []
	if allowed.has("discard_drawn"):
		tool_names.append_array(["discard_drawn_card", "swap_drawn_card"])
	if allowed.has("peek_ability"):
		tool_names.append("complete_queen_peek")
	if allowed.has("swap_ability"):
		tool_names.append("complete_jack_swap")
	if allowed.has("end_turn"):
		tool_names.append("end_turn")
	if allowed.has("call_dutch"):
		tool_names.append("call_dutch")
	if allowed.has("buy_ability"):
		tool_names.append("buy_ability")
	if allowed.has("use_ability"):
		tool_names.append("use_ability")
	var filtered: Array = []
	for schema in AgentToolRegistry.player_action_tool_schemas():
		if str(schema.get("function", {}).get("name", "")) in tool_names:
			filtered.append(schema)
	return filtered

func _fallback_action(player_idx: int) -> bool:
	var state: int = gm.current_state
	match state:
		gm.GameState.TURN_START_DRAW:
			return await _execute_fallback("draw_card", {}, player_idx)
		gm.GameState.TURN_RESOLVE_DRAWN:
			var worst_idx := _worst_known_card(player_idx)
			var drawn_value: int = gm.drawn_card_data.point_value if gm.drawn_card_data != null else UNKNOWN_VALUE
			if worst_idx != -1 and drawn_value < _known_value(player_idx, worst_idx):
				return await _execute_fallback("swap_drawn_card", {"card_index": worst_idx}, player_idx)
			return await _execute_fallback("discard_drawn_card", {}, player_idx)
		gm.GameState.TURN_PEEK_ABILITY:
			var peek := _peek_target(player_idx)
			if not peek.is_empty():
				return await _execute_fallback("complete_queen_peek", peek, player_idx)
		gm.GameState.TURN_SWAP_ABILITY:
			var swap := _swap_targets(player_idx)
			if not swap.is_empty():
				return await _execute_fallback("complete_jack_swap", swap, player_idx)
		gm.GameState.TURN_END_CHOICE:
			if _should_call_dutch(player_idx):
				return await _execute_fallback("call_dutch", {}, player_idx)
			return await _execute_fallback("end_turn", {}, player_idx)
		gm.GameState.TURN_CONFIRM_DUTCH:
			return await _execute_fallback("confirm_dutch", {}, player_idx)
	return false

func _execute_fallback(tool_name: String, args: Dictionary, player_idx: int) -> bool:
	var result: Dictionary = await AgentToolRegistry.execute_tool(tool_name, args, player_idx)
	if result.get("ok", false):
		gm.bot_action.emit("LM Player %d fallback used %s." % [player_idx, tool_name])
		return true
	return false

func _decision_context(player_idx: int) -> Dictionary:
	var public_players: Array = []
	for idx in range(gm.players_info.size()):
		var info: Dictionary = gm.players_info[idx]
		public_players.append({
			"player_idx": idx,
			"hand_size": (info.get("hand", []) as Array).size(),
			"beers": int(info.get("beers", 0)),
			"money": int(info.get("money", 0)),
			"is_eliminated": bool(info.get("is_eliminated", false)),
		})
	return {
		"state": GameContext.build_snapshot(player_idx),
		"memory": AgentToolRegistry.get_known_cards(player_idx),
		"public_players": public_players,
	}

func _system_prompt(player_idx: int) -> String:
	return """You are Dutch Player Agent controlling player %d in a rules-heavy card game.
Use only the supplied tools. Hidden cards are unknown; never infer or request their identities.
GameManager is authoritative, so choose an action listed in state.allowed_actions.
Call exactly one supplied gameplay action tool.
Prefer lower point totals. King of Diamonds is 0. Unknown cards are risky.
Do not expose reasoning or write prose; respond with tool calls only.""" % player_idx

func _has_relevant_action(player_idx: int) -> bool:
	if not _manages_player(player_idx):
		return false
	var snapshot: Dictionary = GameContext.build_snapshot(player_idx)
	return not (snapshot.get("allowed_actions", []) as Array).is_empty()

func _manages_player(player_idx: int) -> bool:
	if gm == null or not gm.llm_player_enabled:
		return false
	if gm.is_multiplayer and not gm.multiplayer.is_server():
		return false
	return player_idx == gm.llm_player_index \
		and player_idx >= 0 \
		and player_idx < gm.players_info.size() \
		and bool(gm.players_info[player_idx].get("is_bot", false))

func _player_idx() -> int:
	return int(gm.llm_player_index) if gm != null else -1

func _known_value(player_idx: int, card_idx: int) -> int:
	var memory: Dictionary = gm.players_info[player_idx].get("bot_memory", {}).get(player_idx, {})
	var card: Variant = memory.get(card_idx, null)
	return card.point_value if card is CardData else UNKNOWN_VALUE

func _worst_known_card(player_idx: int) -> int:
	var hand: Array = gm.players_info[player_idx].get("hand", [])
	var worst_idx := -1
	var worst_value := -1
	for idx in range(hand.size()):
		var value := _known_value(player_idx, idx)
		if value > worst_value:
			worst_value = value
			worst_idx = idx
	return worst_idx

func _known_matching_card(player_idx: int, rank: String) -> int:
	if rank == "":
		return -1
	var memory: Dictionary = gm.players_info[player_idx].get("bot_memory", {}).get(player_idx, {})
	for card_idx in memory:
		var card: Variant = memory[card_idx]
		if card is CardData and card.rank == rank:
			return int(card_idx)
	return -1

func _peek_target(player_idx: int) -> Dictionary:
	var own_memory: Dictionary = gm.players_info[player_idx].get("bot_memory", {}).get(player_idx, {})
	var own_hand: Array = gm.players_info[player_idx].get("hand", [])
	for card_idx in range(own_hand.size()):
		if not own_memory.has(card_idx):
			return {"owner_player": player_idx, "card_index": card_idx}
	for owner_idx in range(gm.players_info.size()):
		var hand: Array = gm.players_info[owner_idx].get("hand", [])
		if not hand.is_empty():
			return {"owner_player": owner_idx, "card_index": 0}
	return {}

func _swap_targets(player_idx: int) -> Dictionary:
	var slots: Array = []
	for owner_idx in range(gm.players_info.size()):
		if owner_idx == player_idx:
			continue
		for card_idx in range((gm.players_info[owner_idx].get("hand", []) as Array).size()):
			slots.append({"owner": owner_idx, "card": card_idx})
	if slots.size() < 2:
		return {}
	slots.shuffle()
	return {
		"owner_player_a": slots[0]["owner"],
		"card_index_a": slots[0]["card"],
		"owner_player_b": slots[1]["owner"],
		"card_index_b": slots[1]["card"],
	}

func _should_call_dutch(player_idx: int) -> bool:
	var hand: Array = gm.players_info[player_idx].get("hand", [])
	var memory: Dictionary = gm.players_info[player_idx].get("bot_memory", {}).get(player_idx, {})
	if hand.is_empty() or memory.size() < hand.size():
		return false
	var score := 0
	for card_idx in range(hand.size()):
		var card: Variant = memory.get(card_idx, null)
		if not (card is CardData):
			return false
		score += card.point_value
	return score < 7 and gm.can_player_call_dutch(player_idx)

func _top_discard_rank() -> String:
	if gm.deck_manager == null:
		return ""
	var top: CardData = gm.deck_manager.get_top_discard()
	return top.rank if top != null else ""

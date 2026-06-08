extends Node

## Central registry for LLM-callable tools. Agents may propose calls, but this
## registry validates every action against GameManager before touching the FSM.

const READ_ONLY_TOOLS := ["get_game_state", "get_legal_actions", "get_rules", "get_known_cards", "get_environment"]
const PLAYER_ACTION_TOOLS := [
	"draw_card",
	"discard_drawn_card",
	"swap_drawn_card",
	"attempt_jump_in",
	"end_turn",
	"call_dutch",
	"confirm_dutch",
	"forfeit_dutch",
	"buy_ability",
	"use_ability",
	"complete_queen_peek",
	"complete_jack_swap",
]

func read_only_tool_schemas() -> Array:
	return [
		_tool("get_game_state", "Return the public/local game state for the requested player.", {}),
		_tool("get_legal_actions", "Return legal action names for the requested player.", {}),
		_tool("get_known_cards", "Return only the requested player's known card memory, never hidden unknown cards.", {}),
		_tool("get_environment", "Describe a visible object or area in the authored 3D scene.", {
			"query": {"type": "string", "description": "Question about a scene object or environment detail."},
		}, ["query"]),
		_tool("get_rules", "Search the local Dutch rules knowledge base.", {
			"query": {"type": "string", "description": "Natural language rules query."},
		}, ["query"]),
	]

func player_action_tool_schemas() -> Array:
	return [
		_tool("draw_card", "Draw a card when the FSM allows the player to draw.", {}),
		_tool("discard_drawn_card", "Discard the currently drawn card.", {}),
		_tool("swap_drawn_card", "Swap the currently drawn card with one of this player's own hand cards.", {
			"card_index": {"type": "integer", "minimum": 0},
		}, ["card_index"]),
		_tool("attempt_jump_in", "Attempt a Jump-In with one own hand card, or -2 for the pending drawn card.", {
			"card_index": {"type": "integer"},
		}, ["card_index"]),
		_tool("end_turn", "End the current player's turn.", {}),
		_tool("call_dutch", "Call Dutch from TURN_END_CHOICE.", {}),
		_tool("confirm_dutch", "Confirm Dutch and end the game.", {}),
		_tool("forfeit_dutch", "Cancel Dutch and forfeit future Dutch calls.", {}),
		_tool("buy_ability", "Buy a chicken ability if the player has enough money and capacity.", {}),
		_tool("use_ability", "Use one owned ability by slot and optional target player.", {
			"slot_index": {"type": "integer", "minimum": 0},
			"target_player": {"type": "integer", "minimum": 0},
		}, ["slot_index"]),
		_tool("complete_queen_peek", "Resolve Queen by peeking at one card and adding it to agent memory.", {
			"owner_player": {"type": "integer", "minimum": 0},
			"card_index": {"type": "integer", "minimum": 0},
		}, ["owner_player", "card_index"]),
		_tool("complete_jack_swap", "Resolve Jack by blindly swapping two valid cards.", {
			"owner_player_a": {"type": "integer", "minimum": 0},
			"card_index_a": {"type": "integer", "minimum": 0},
			"owner_player_b": {"type": "integer", "minimum": 0},
			"card_index_b": {"type": "integer", "minimum": 0},
		}, ["owner_player_a", "card_index_a", "owner_player_b", "card_index_b"]),
	]

func all_tool_schemas_for_player() -> Array:
	var tools := read_only_tool_schemas()
	tools.append_array(player_action_tool_schemas())
	return tools

func execute_tool(tool_name: String, args: Dictionary, player_idx: int) -> Dictionary:
	if tool_name in READ_ONLY_TOOLS:
		return execute_read_only_tool(tool_name, args, player_idx)
	if tool_name in PLAYER_ACTION_TOOLS:
		return await execute_player_tool(tool_name, args, player_idx)
	return _fail("unknown_tool", "Unknown tool: %s" % tool_name)

func execute_read_only_tool(tool_name: String, args: Dictionary, player_idx: int) -> Dictionary:
	match tool_name:
		"get_game_state":
			return _ok({"state": GameContext.build_snapshot(player_idx)})
		"get_legal_actions":
			var snap: Dictionary = GameContext.build_snapshot(player_idx)
			return _ok({"actions": snap.get("allowed_actions", [])})
		"get_known_cards":
			return _ok({"known_cards": get_known_cards(player_idx)})
		"get_environment":
			var entry: Dictionary = EnvironmentKnowledge.lookup(str(args.get("query", "")))
			return _ok({"environment": entry if not entry.is_empty() else {"answer": EnvironmentKnowledge.inventory_summary()}})
		"get_rules":
			return _ok({"rules": _search_rules(str(args.get("query", "")))})
	return _fail("unknown_read_tool", "Unknown read-only tool: %s" % tool_name)

func execute_player_tool(tool_name: String, args: Dictionary, player_idx: int) -> Dictionary:
	var gm := _gm()
	if gm == null:
		return _fail("missing_game_manager", "GameManager is not available")
	if not _valid_player(player_idx):
		return _fail("invalid_player", "Invalid player index")
	if bool(gm.players_info[player_idx].get("is_eliminated", false)):
		return _fail("eliminated", "Eliminated players cannot act")

	match tool_name:
		"draw_card":
			if not gm.can_player_draw(player_idx):
				return _blocked("draw_card", player_idx)
			gm.player_draw_card()
			return _ok_action("draw_card", player_idx)
		"discard_drawn_card":
			if not gm.can_player_discard_drawn_card(player_idx):
				return _blocked("discard_drawn_card", player_idx)
			gm.player_discard_drawn_card()
			return _ok_action("discard_drawn_card", player_idx)
		"swap_drawn_card":
			var card_idx := int(args.get("card_index", -1))
			if not gm.can_player_swap_drawn_card(player_idx, player_idx, card_idx):
				return _blocked("swap_drawn_card", player_idx)
			remember_drawn_card(player_idx, card_idx)
			gm.player_swap_drawn_card(card_idx)
			return _ok_action("swap_drawn_card", player_idx)
		"attempt_jump_in":
			var jump_idx := int(args.get("card_index", -999))
			if not gm.can_player_start_jump_in(player_idx):
				return _blocked("attempt_jump_in", player_idx)
			if not gm.can_player_select_jump_in_card(player_idx, player_idx, jump_idx) and gm.current_state != gm.GameState.TURN_JUMP_IN_SELECTION:
				gm.start_jump_in(player_idx)
			if not gm.can_player_select_jump_in_card(player_idx, player_idx, jump_idx):
				return _blocked("attempt_jump_in", player_idx)
			var success: bool = await gm.validate_jump_in(jump_idx)
			return _ok({"action": "attempt_jump_in", "success": success, "state": GameContext.build_snapshot(player_idx)})
		"end_turn":
			if not gm.can_player_end_turn(player_idx):
				return _blocked("end_turn", player_idx)
			gm.end_turn()
			return _ok_action("end_turn", player_idx)
		"call_dutch":
			if not gm.can_player_call_dutch(player_idx):
				return _blocked("call_dutch", player_idx)
			gm.call_dutch(player_idx)
			return _ok_action("call_dutch", player_idx)
		"confirm_dutch":
			if not gm.can_player_confirm_dutch(player_idx):
				return _blocked("confirm_dutch", player_idx)
			gm.confirm_dutch()
			return _ok_action("confirm_dutch", player_idx)
		"forfeit_dutch":
			if not gm.can_player_cancel_dutch(player_idx):
				return _blocked("forfeit_dutch", player_idx)
			gm.cancel_dutch()
			return _ok_action("forfeit_dutch", player_idx)
		"buy_ability":
			if gm.current_player_index != player_idx:
				return _blocked("buy_ability", player_idx)
			return _ok({"action": "buy_ability", "success": gm.buy_ability(player_idx), "state": GameContext.build_snapshot(player_idx)})
		"use_ability":
			return _execute_use_ability(args, player_idx)
		"complete_queen_peek":
			return _execute_queen_peek(args, player_idx)
		"complete_jack_swap":
			return _execute_jack_swap(args, player_idx)
	return _fail("unknown_player_tool", "Unknown player tool: %s" % tool_name)

func get_known_cards(player_idx: int) -> Dictionary:
	var gm := _gm()
	if gm == null or not _valid_player(player_idx):
		return {}
	var info: Dictionary = gm.players_info[player_idx]
	var result := {
		"own_hand": [],
		"known_table": {},
		"drawn_card": null,
		"abilities": info.get("abilities", []),
	}
	var own_memory: Dictionary = info.get("bot_memory", {}).get(player_idx, {})
	var own_hand: Array = info.get("hand", [])
	for i in range(own_hand.size()):
		var known_card: Variant = own_memory.get(i, null)
		if known_card is CardData:
			result["own_hand"].append(_public_card_dict(known_card, i, true))
		else:
			result["own_hand"].append({"index": i, "known": false})
	for p_idx in info.get("bot_memory", {}):
		if int(p_idx) == player_idx:
			continue
		var entries: Array = []
		for c_idx in info["bot_memory"][p_idx]:
			var c: Variant = info["bot_memory"][p_idx][c_idx]
			if c is CardData:
				entries.append(_public_card_dict(c, int(c_idx), true))
		if not entries.is_empty():
			result["known_table"][str(p_idx)] = entries
	if gm.drawn_card_data != null and gm.current_player_index == player_idx:
		result["drawn_card"] = _public_card_dict(gm.drawn_card_data, -2, true)
	return result

func remember_card(observer_idx: int, owner_idx: int, card_idx: int) -> void:
	var gm := _gm()
	if gm == null or not _valid_player(observer_idx) or not _valid_player(owner_idx):
		return
	if not _hand_has_index(owner_idx, card_idx):
		return
	if not gm.players_info[observer_idx].bot_memory.has(owner_idx):
		gm.players_info[observer_idx].bot_memory[owner_idx] = {}
	gm.players_info[observer_idx].bot_memory[owner_idx][card_idx] = gm.players_info[owner_idx].hand[card_idx]

func remember_drawn_card(observer_idx: int, card_idx: int) -> void:
	var gm := _gm()
	if gm == null or gm.drawn_card_data == null or not _valid_player(observer_idx):
		return
	if not gm.players_info[observer_idx].bot_memory.has(observer_idx):
		gm.players_info[observer_idx].bot_memory[observer_idx] = {}
	gm.players_info[observer_idx].bot_memory[observer_idx][card_idx] = gm.drawn_card_data

func _execute_use_ability(args: Dictionary, player_idx: int) -> Dictionary:
	var gm := _gm()
	var slot_idx := int(args.get("slot_index", -1))
	var target_idx := int(args.get("target_player", -1))
	var abilities: Array = gm.players_info[player_idx].get("abilities", [])
	if slot_idx < 0 or slot_idx >= abilities.size():
		return _fail("invalid_ability_slot", "Ability slot is invalid")
	var ability_id := str(abilities[slot_idx])
	if ability_id == "":
		return _fail("empty_ability_slot", "Ability slot is empty")
	var targeting_abilities := ["bottoms_up", "boulder", "skip", "inflation", "half_off", "shuffle", "jumpscare"]
	if ability_id not in targeting_abilities:
		target_idx = -1
	elif not _valid_player(target_idx):
		return _fail("invalid_target", "Ability target is invalid")
	if not gm.play_ability(player_idx, ability_id, target_idx, slot_idx):
		return _blocked("use_ability", player_idx)
	return _ok({"action": "use_ability", "ability": ability_id, "state": GameContext.build_snapshot(player_idx)})

func _execute_queen_peek(args: Dictionary, player_idx: int) -> Dictionary:
	var gm := _gm()
	var owner_idx := int(args.get("owner_player", -1))
	var card_idx := int(args.get("card_index", -1))
	if not gm.can_player_complete_peek_ability(player_idx):
		return _blocked("complete_queen_peek", player_idx)
	if not _hand_has_index(owner_idx, card_idx):
		return _fail("invalid_card", "Queen target card is invalid")
	remember_card(player_idx, owner_idx, card_idx)
	gm.complete_peek_ability()
	return _ok_action("complete_queen_peek", player_idx)

func _execute_jack_swap(args: Dictionary, player_idx: int) -> Dictionary:
	var gm := _gm()
	if not gm.can_player_complete_swap_ability(player_idx):
		return _blocked("complete_jack_swap", player_idx)
	var p1 := int(args.get("owner_player_a", -1))
	var c1 := int(args.get("card_index_a", -1))
	var p2 := int(args.get("owner_player_b", -1))
	var c2 := int(args.get("card_index_b", -1))
	if not _hand_has_index(p1, c1) or not _hand_has_index(p2, c2):
		return _fail("invalid_card", "Jack swap card target is invalid")
	gm.complete_swap_ability(p1, c1, p2, c2)
	_update_memory_after_swap(p1, c1, p2, c2)
	return _ok_action("complete_jack_swap", player_idx)

func _update_memory_after_swap(p1: int, c1: int, p2: int, c2: int) -> void:
	var gm := _gm()
	for observer_idx in range(gm.players_info.size()):
		var info: Dictionary = gm.players_info[observer_idx]
		if not bool(info.get("is_bot", false)):
			continue
		var memory: Dictionary = info.get("bot_memory", {})
		if not memory.has(p1):
			memory[p1] = {}
		if not memory.has(p2):
			memory[p2] = {}
		var knew_first: Variant = memory[p1].get(c1, null)
		var knew_second: Variant = memory[p2].get(c2, null)
		if knew_second is CardData:
			memory[p1][c1] = knew_second
		else:
			memory[p1].erase(c1)
		if knew_first is CardData:
			memory[p2][c2] = knew_first
		else:
			memory[p2].erase(c2)

func _search_rules(query: String, limit: int = 4) -> Array:
	var norm := query.to_lower()
	var scored: Array = []
	for entry in GameKnowledge.all_entries():
		var score := 0
		var haystack := (str(entry.get("id", "")) + " " + str(entry.get("answer", ""))).to_lower()
		for pattern in entry.get("patterns", []):
			haystack += " " + str(pattern).to_lower()
		for token in norm.split(" ", false):
			if token.length() >= 2 and haystack.contains(token):
				score += 1
		if score > 0:
			scored.append({"score": score, "entry": entry})
	scored.sort_custom(func(a, b): return int(a["score"]) > int(b["score"]))
	var out: Array = []
	for item in scored:
		if out.size() >= limit:
			break
		var entry: Dictionary = item["entry"]
		out.append({
			"id": entry.get("id", ""),
			"answer": entry.get("answer", ""),
			"tags": entry.get("tags", []),
		})
	if out.is_empty():
		for entry in GameKnowledge.all_entries().slice(0, limit):
			out.append({"id": entry.get("id", ""), "answer": entry.get("answer", ""), "tags": entry.get("tags", [])})
	return out

func _tool(name: String, description: String, properties: Dictionary, required: Array = []) -> Dictionary:
	return {
		"type": "function",
		"function": {
			"name": name,
			"description": description,
			"parameters": {
				"type": "object",
				"properties": properties,
				"required": required,
				"additionalProperties": false,
			},
		},
	}

func _ok_action(action: String, player_idx: int) -> Dictionary:
	return _ok({"action": action, "state": GameContext.build_snapshot(player_idx)})

func _ok(data: Dictionary) -> Dictionary:
	return {"ok": true, "data": data}

func _blocked(action: String, player_idx: int) -> Dictionary:
	return _fail("fsm_blocked", "Action '%s' is not legal for player %d in the current FSM state." % [action, player_idx])

func _fail(code: String, message: String) -> Dictionary:
	return {"ok": false, "error": code, "message": message}

func _gm() -> Node:
	return get_node_or_null("/root/GameManager")

func _valid_player(player_idx: int) -> bool:
	var gm := _gm()
	return gm != null and player_idx >= 0 and player_idx < gm.players_info.size()

func _hand_has_index(player_idx: int, card_idx: int) -> bool:
	var gm := _gm()
	if gm == null or not _valid_player(player_idx):
		return false
	var hand: Array = gm.players_info[player_idx].get("hand", [])
	return card_idx >= 0 and card_idx < hand.size()

func _public_card_dict(card: CardData, index: int, known: bool) -> Dictionary:
	return {
		"index": index,
		"known": known,
		"rank": card.rank,
		"suit": card.suit,
		"points": card.point_value,
	}

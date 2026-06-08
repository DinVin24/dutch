extends SceneTree

## Offline verification for the LLM tool boundary. No LM Studio server needed.

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var gm := root.get_node_or_null("GameManager")
	var registry := root.get_node_or_null("AgentToolRegistry")
	_require(gm != null, "GameManager autoload missing")
	_require(registry != null, "AgentToolRegistry autoload missing")

	gm.llm_player_enabled = false
	gm.is_multiplayer = false
	gm.initialize_game(4)
	await process_frame
	for owner_idx in range(gm.num_players):
		for _card_idx in range(4):
			gm.players_info[owner_idx].hand.append(gm.deck_manager.draw_card())

	var player_idx := 1
	var hand: Array = gm.players_info[player_idx].hand
	_require(hand.size() == 4, "test player should start with four cards")
	var memory := {}
	for idx in range(gm.num_players):
		memory[idx] = {}
	memory[player_idx][0] = hand[0]
	memory[player_idx][2] = hand[2]
	gm.players_info[player_idx].bot_memory = memory

	var known: Dictionary = registry.get_known_cards(player_idx)
	var own_hand: Array = known.get("own_hand", [])
	_require(own_hand.size() == hand.size(), "known-card view should preserve hand slots")
	_require(own_hand[0].get("known", false), "memorized card should be visible")
	_require(not own_hand[1].get("known", true), "unknown card should remain hidden")
	_require(not own_hand[1].has("rank"), "unknown card must not expose rank")
	_require(not own_hand[1].has("points"), "unknown card must not expose points")
	print("[AGENT-TOOLS-TEST] hidden information boundary PASS")

	var environment: Dictionary = registry.execute_read_only_tool(
		"get_environment",
		{"query": "what are the drawers next to the player?"},
		player_idx
	)
	var environment_text := str(environment.get("data", {}).get("environment", {}).get("answer", "")).to_lower()
	_require(environment.get("ok", false), "environment tool should succeed")
	_require(environment_text.contains("three interactive drawers"), "environment tool should describe the player cabinet")
	_require(environment_text.contains("six ability hammers"), "environment tool should explain drawer contents")
	print("[AGENT-TOOLS-TEST] environment knowledge PASS")

	gm.current_player_index = 0
	gm.change_state(gm.GameState.TURN_START_DRAW, true)
	var blocked: Dictionary = await registry.execute_tool("draw_card", {}, player_idx)
	_require(not blocked.get("ok", true), "out-of-turn draw should be blocked")
	_require(blocked.get("error", "") == "fsm_blocked", "blocked draw should report FSM boundary")
	_require(gm.drawn_card_data == null, "blocked draw must not mutate pending card")
	print("[AGENT-TOOLS-TEST] illegal action blocking PASS")

	gm.current_player_index = player_idx
	gm.change_state(gm.GameState.TURN_START_DRAW, true)
	var drawn: Dictionary = await registry.execute_tool("draw_card", {}, player_idx)
	_require(drawn.get("ok", false), "legal draw should succeed")
	_require(gm.current_state == gm.GameState.TURN_RESOLVE_DRAWN, "legal draw should advance FSM")
	_require(gm.drawn_card_data != null, "legal draw should create pending card")
	print("[AGENT-TOOLS-TEST] legal action execution PASS")

	print("AGENT_TOOLS_TEST_COMPLETE pass=true")
	quit(0)

func _require(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("[AGENT-TOOLS-TEST] FAIL: " + message)
	print("AGENT_TOOLS_TEST_COMPLETE pass=false reason=%s" % message)
	quit(1)

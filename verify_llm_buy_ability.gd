extends SceneTree

## Verification script for LlmPlayerAgent buy_ability freeze fix.
## Run: Godot --path dutch -s res://verify_llm_buy_ability.gd

const SCREENSHOT_DIR := "res://debug/test_runs"

func _init() -> void:
	call_deferred("_run")

func _log(msg: String) -> void:
	print("[LLM-FREEZE-TEST] ", msg)

func _run() -> void:
	_log("=== STARTING LLM FREEZE TEST ===")
	var gm := root.get_node_or_null("GameManager")
	_require(gm != null, "GameManager autoload missing")

	# Mock LmStudioClient to return first buy_ability, then discard_drawn_card
	var mock_script = GDScript.new()
	mock_script.source_code = """
extends Node

var call_count = 0

func chat_completion(messages: Array, tools: Array = [], profile_name: String = "fast", extra: Dictionary = {}) -> Dictionary:
	call_count += 1
	if call_count == 1:
		return {
			"ok": true,
			"tool_calls": [{
				"id": "call_buy",
				"name": "buy_ability",
				"arguments": {}
			}]
		}
	else:
		return {
			"ok": true,
			"tool_calls": [{
				"id": "call_discard",
				"name": "discard_drawn_card",
				"arguments": {}
			}]
		}
"""
	mock_script.reload()
	
	var client = root.get_node_or_null("LmStudioClient")
	_require(client != null, "LmStudioClient autoload missing")
	client.set_script(mock_script)
	_log("LmStudioClient mocked successfully")

	# Set up game
	gm.llm_player_enabled = true
	gm.llm_player_index = 1
	gm.is_multiplayer = false
	gm.initialize_game(4)

	# Instantiate LlmPlayerAgent and add it to the tree
	var agent = load("res://llm_player_agent.gd").new()
	agent.gm = gm
	root.add_child(agent)
	_log("LlmPlayerAgent instantiated and added to root")
	
	# Deal 4 cards to everyone (similar to verify_agent_tools.gd)
	for owner_idx in range(gm.num_players):
		for _card_idx in range(4):
			gm.players_info[owner_idx].hand.append(gm.deck_manager.draw_card())

	# Ensure LLM player (P1) has money to buy ability
	gm.players_info[1]["money"] = 100
	# Ensure P1 is a bot
	gm.players_info[1]["is_bot"] = true

	# Skip initial peek phase if active
	if gm.current_state == gm.GameState.INITIAL_PEEK:
		gm.complete_initial_peek()

	_log("Initial state: " + gm.GameState.keys()[gm.current_state])
	_log("Active player index: " + str(gm.current_player_index))

	# Force transition to P1's turn start draw
	gm.current_player_index = 1
	gm.change_state(gm.GameState.TURN_START_DRAW, true)

	_log("Waiting for LLM agent to process actions...")
	
	# Wait for deferred calls and timers to process
	# The agent has an initial timer of 0.08s, plus call_deferred
	for i in range(15):
		await process_frame
	
	# Wait slightly more for the timers (including the 0.4s discard tween)
	await create_timer(0.6).timeout

	# Let's inspect what happened
	var client_calls = client.get("call_count")
	_log("LM Client chat completions called: " + str(client_calls))
	_log("Current FSM State after processing: " + gm.GameState.keys()[gm.current_state])
	_log("P1 money: " + str(gm.players_info[1].money))
	_log("P1 abilities: " + str(gm.players_info[1].abilities))

	# Verify:
	# 1. P1 has an ability in their inventory
	var abilities: Array = gm.players_info[1].abilities.filter(func(a): return a != "")
	if not _require(abilities.size() == 1, "P1 should have exactly 1 purchased ability"): return
	# 2. LmStudioClient was called at least twice (meaning it didn't freeze after buying the ability)
	if not _require(client_calls >= 2, "LmStudioClient should have been called at least twice (for buy and subsequent actions)"): return
	# 3. FSM progressed past TURN_RESOLVE_DRAWN (either TURN_END_CHOICE, TURN_PEEK_ABILITY or TURN_SWAP_ABILITY depending on discard)
	if not _require(gm.current_state != gm.GameState.TURN_RESOLVE_DRAWN, "FSM should have progressed past TURN_RESOLVE_DRAWN"): return
	# 4. P1 spent 50 money on the ability and got some back from discard (depending on discard, >= 80 money)
	if not _require(gm.players_info[1].money >= 80, "P1 money check"): return

	_log("=== LLM FREEZE TEST PASSED SUCCESSFULLY ===")
	quit(0)

func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("[LLM-FREEZE-TEST] FAIL: " + message)
	print("LLM_FREEZE_TEST_COMPLETE pass=false reason=%s" % message)
	quit(1)
	return false

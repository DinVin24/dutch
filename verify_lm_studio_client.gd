extends SceneTree

## Verifies deterministic response parsing and, when available, the real local
## LM Studio endpoint. The offline checks always run, so CI needs no model.

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var client: Node = load("res://lm_studio_client.gd").new()
	root.add_child(client)
	await process_frame

	var sample := {
		"choices": [{
			"finish_reason": "tool_calls",
			"message": {
				"role": "assistant",
				"content": "<think>private reasoning</think>\nVisible answer",
				"tool_calls": [{
					"id": "call_1",
					"type": "function",
					"function": {
						"name": "draw_card",
						"arguments": "{}",
					},
				}],
			},
		}],
		"usage": {"total_tokens": 42},
	}
	var normalized: Dictionary = client.normalize_chat_response(sample)
	if not _require(normalized.get("ok", false), "sample response should parse"): return
	if not _require(normalized.get("content", "") == "Visible answer", "thinking text should be removed"): return
	if not _require(normalized.get("tool_calls", []).size() == 1, "tool call should parse"): return
	if not _require(normalized["tool_calls"][0]["name"] == "draw_card", "tool name mismatch"): return
	if not _require(normalized["tool_calls"][0]["arguments"].is_empty(), "tool arguments mismatch"): return
	print("[LM-CLIENT-TEST] offline parsing PASS")

	var models: Dictionary = await client.list_models()
	if not models.get("ok", false):
		print("[LM-CLIENT-TEST] live server unavailable; offline checks PASS")
		quit(0)
		return
	if not _require(await client.is_available(), "configured model missing from LM Studio"): return
	var completion: Dictionary = await client.chat_completion(
		[
			{"role": "system", "content": "Reply with one short sentence."},
			{"role": "user", "content": "Say that the Dutch game assistant is connected."},
		],
		[],
		"fast",
		{"max_tokens": 160, "timeout_sec": 45.0}
	)
	if not _require(completion.get("ok", false), "live completion failed: %s" % completion): return
	if not _require(str(completion.get("content", "")).strip_edges() != "", "live completion was empty"): return
	print("[LM-CLIENT-TEST] live completion PASS")

	var tool_completion: Dictionary = await client.chat_completion(
		[
			{"role": "system", "content": "Use the supplied tool. Return no prose."},
			{"role": "user", "content": "Draw one card now."},
		],
		[{
			"type": "function",
			"function": {
				"name": "draw_card",
				"description": "Draw one card.",
				"parameters": {
					"type": "object",
					"properties": {},
					"required": [],
					"additionalProperties": false,
				},
			},
		}],
		"fast",
		{"tool_choice": "required", "max_tokens": 96, "timeout_sec": 8.0}
	)
	if not _require(tool_completion.get("ok", false), "live tool completion failed: %s" % tool_completion): return
	if not _require(tool_completion.get("tool_calls", []).size() == 1, "model should return one tool call"): return
	if not _require(tool_completion["tool_calls"][0]["name"] == "draw_card", "model selected wrong tool"): return
	print("[LM-CLIENT-TEST] live tool calling PASS")
	quit(0)

func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("[LM-CLIENT-TEST] FAIL: " + message)
	quit(1)
	return false

extends Node

## Shared OpenAI-compatible client for the local LM Studio server.
## Agents own their prompts and tools; this node only handles transport,
## response normalization, and safe removal of model reasoning text.

const DEFAULT_BASE_URL := "http://127.0.0.1:1234/v1"
const DEFAULT_MODEL := "qwen/qwen3.5-9b"

const PROFILES := {
	"fast": {
		"temperature": 0.15,
		"max_tokens": 220,
		"timeout_sec": 30.0,
	},
	"strategic": {
		"temperature": 0.2,
		"max_tokens": 420,
		"timeout_sec": 45.0,
	},
}

var base_url := DEFAULT_BASE_URL
var model := DEFAULT_MODEL

func _ready() -> void:
	var env_url := OS.get_environment("DUTCH_LM_STUDIO_URL").strip_edges()
	var env_model := OS.get_environment("DUTCH_LM_STUDIO_MODEL").strip_edges()
	if env_url != "":
		base_url = env_url.trim_suffix("/")
	if env_model != "":
		model = env_model

func list_models() -> Dictionary:
	return await _request_json(HTTPClient.METHOD_GET, "/models", {}, 5.0)

func is_available() -> bool:
	var result := await list_models()
	if not result.get("ok", false):
		return false
	var data: Dictionary = result.get("data", {})
	for entry in data.get("data", []):
		if entry is Dictionary and str(entry.get("id", "")) == model:
			return true
	return false

func chat_completion(
		messages: Array,
		tools: Array = [],
		profile_name: String = "fast",
		extra: Dictionary = {}
	) -> Dictionary:
	var profile: Dictionary = PROFILES.get(profile_name, PROFILES["fast"])
	var payload := {
		"model": model,
		"messages": messages,
		"temperature": float(extra.get("temperature", profile["temperature"])),
		"max_tokens": int(extra.get("max_tokens", profile["max_tokens"])),
		"stream": false,
		"chat_template_kwargs": extra.get("chat_template_kwargs", {"enable_thinking": false}),
	}
	if not tools.is_empty():
		payload["tools"] = tools
		payload["tool_choice"] = extra.get("tool_choice", "auto")
	for key in extra:
		if key not in ["temperature", "max_tokens", "timeout_sec", "tool_choice", "chat_template_kwargs"]:
			payload[key] = extra[key]

	var timeout_sec := float(extra.get("timeout_sec", profile["timeout_sec"]))
	var raw := await _request_json(
		HTTPClient.METHOD_POST,
		"/chat/completions",
		payload,
		timeout_sec
	)
	if not raw.get("ok", false):
		return raw
	return normalize_chat_response(raw.get("data", {}))

func _request_json(method: HTTPClient.Method, path: String, payload: Dictionary, timeout_sec: float) -> Dictionary:
	var request := HTTPRequest.new()
	request.timeout = timeout_sec
	add_child(request)

	var headers := PackedStringArray(["Content-Type: application/json"])
	var body := "" if method == HTTPClient.METHOD_GET else JSON.stringify(payload)
	var err := request.request(base_url + path, headers, method, body)
	if err != OK:
		request.queue_free()
		return _error("request_start_failed", "Could not start LM Studio request", err)

	var completed: Array = await request.request_completed
	request.queue_free()
	if completed.size() < 4:
		return _error("invalid_transport_result", "LM Studio returned an invalid transport result")

	var result_code := int(completed[0])
	var response_code := int(completed[1])
	var response_body: PackedByteArray = completed[3]
	if result_code != HTTPRequest.RESULT_SUCCESS:
		return _error("transport_error", "LM Studio request failed", result_code, response_code)

	var text := response_body.get_string_from_utf8()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return _error("invalid_json", "LM Studio returned invalid JSON", result_code, response_code)
	if response_code < 200 or response_code >= 300:
		return {
			"ok": false,
			"error": "http_error",
			"message": str(parsed.get("error", parsed)),
			"http_status": response_code,
		}
	return {
		"ok": true,
		"http_status": response_code,
		"data": parsed,
	}

func normalize_chat_response(payload: Dictionary) -> Dictionary:
	var choices: Array = payload.get("choices", [])
	if choices.is_empty() or not (choices[0] is Dictionary):
		return _error("missing_choice", "LM Studio response has no completion choice")
	var message: Dictionary = choices[0].get("message", {})
	if message.is_empty():
		return _error("missing_message", "LM Studio response has no assistant message")

	var tool_calls: Array = []
	for raw_call in message.get("tool_calls", []):
		if not (raw_call is Dictionary):
			continue
		var function_data: Dictionary = raw_call.get("function", {})
		var args_text := str(function_data.get("arguments", "{}"))
		var args = JSON.parse_string(args_text)
		if typeof(args) != TYPE_DICTIONARY:
			args = {}
		tool_calls.append({
			"id": str(raw_call.get("id", "")),
			"name": str(function_data.get("name", "")),
			"arguments": args,
		})

	return {
		"ok": true,
		"content": strip_thinking(str(message.get("content", ""))),
		"raw_content": str(message.get("content", "")),
		"tool_calls": tool_calls,
		"finish_reason": str(choices[0].get("finish_reason", "")),
		"usage": payload.get("usage", {}),
		"assistant_message": message,
	}

func strip_thinking(text: String) -> String:
	var cleaned := text
	while true:
		var start := cleaned.find("<think>")
		if start == -1:
			break
		var finish := cleaned.find("</think>", start + 7)
		if finish == -1:
			cleaned = cleaned.substr(0, start)
			break
		cleaned = cleaned.substr(0, start) + cleaned.substr(finish + 8)

	var marker := "Thinking Process:"
	if cleaned.begins_with(marker):
		var paragraphs := cleaned.split("\n\n", false)
		if paragraphs.size() > 1:
			paragraphs.remove_at(0)
			cleaned = "\n\n".join(paragraphs)
		else:
			cleaned = ""
	return cleaned.strip_edges()

func _error(
		code: String,
		message: String,
		transport_code: int = -1,
		http_status: int = 0
	) -> Dictionary:
	return {
		"ok": false,
		"error": code,
		"message": message,
		"transport_code": transport_code,
		"http_status": http_status,
	}

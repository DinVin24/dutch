extends Node

## Chippy rules coach. Answers known rules immediately from the grounded local
## engine and uses LM Studio only to clarify ambiguous questions.
## Offline fallback modes:
##   - Simple: question matched against GameKnowledge with token/pattern scoring.
##   - Deep (default): a 4-step offline pipeline that simulates reasoning:
##       1. IntentClassifier   - what is the player asking? (rule / situational / what-now / follow-up)
##       2. GameContext         - live FSM snapshot + can_player_* allowed actions
##       3. RAG retrieve top-K  - best matching entries + related[] propagation
##       4. AnswerSynthesizer   - assemble [Situation]/[Rule]/[Suggestion] from facts only
## Anti-hallucination: situational claims come ONLY from can_player_* checks,
## rule text comes ONLY from retrieved KB entries. No free text generation.

const CONFIDENCE_THRESHOLD := 0.34
const TOP_K := 3
const CHIPPY_LM_TIMEOUT_SEC := 3.2
const CHIPPY_LM_MAX_TOKENS := 180
const CHIPPY_MIN_RESPONSE_MS := 2200
# Question intents detected before retrieval.
const INTENT_RULE := "rule_lookup"
const INTENT_SITUATIONAL := "situational"
const INTENT_WHAT_NOW := "what_now"
const INTENT_FOLLOW_UP := "follow_up"
const INTENT_UNKNOWN := "unknown"

# Remembered topic id from the previous answer (for follow-up questions).
var _last_topic_id := ""

# Diacritic folding so Romanian input matches ASCII patterns.
const DIACRITICS := {
	"ă": "a", "â": "a", "î": "i", "ș": "s", "ş": "s", "ț": "t", "ţ": "t",
}

# Common filler words ignored during token scoring (RO + EN).
const STOP_WORDS := {
	"the": true, "a": true, "an": true, "is": true, "are": true, "do": true,
	"does": true, "what": true, "how": true, "i": true, "to": true, "of": true,
	"my": true, "me": true, "can": true, "it": true, "and": true, "in": true,
	"ce": true, "cum": true, "e": true, "este": true, "sa": true, "sunt": true,
	"un": true, "o": true, "la": true, "se": true, "imi": true, "pot": true,
	"de": true, "mea": true, "mele": true, "si": true,
}

# When the player asks something vague during a specific FSM state, nudge the
# answer toward the relevant rule. Maps GameManager state name -> entry id.
const STATE_HINTS := {
	"INITIAL_PEEK": "initial_peek",
	"TURN_START_DRAW": "turn_flow",
	"TURN_RESOLVE_DRAWN": "swap_vs_discard",
	"TURN_PEEK_ABILITY": "queen",
	"TURN_SWAP_ABILITY": "jack",
	"TURN_END_CHOICE": "dutch",
	"TURN_JUMP_IN_SELECTION": "jump_in",
	"TURN_CONFIRM_DUTCH": "dutch",
}

# Vague catch-all questions that should defer to the current FSM state.
const VAGUE_PATTERNS := [
	"ce fac", "ce fac acum", "what now", "what do i do", "ce trebuie sa fac",
	"help", "ajutor", "what should i do", "stuck", "blocat", "what is happening",
	"ce se intampla", "ce urmeaza", "whats next",
]

# Phrases that signal a situational ("can I X right now?") question.
const SITUATIONAL_MARKERS := [
	"can i", "could i", "am i allowed", "is it ok to", "pot sa", "pot eu",
	"e voie", "am voie", "imi e permis", "right now", "acum", "este randul",
	"is it my turn", "e randul meu", "whose turn", "al cui rand",
]

# Phrases that signal a follow-up referring to the previous answer.
const FOLLOW_UP_MARKERS := [
	"si daca", "dar daca", "what if", "and if", "but if", "what about",
	"si despre", "dar despre", "si atunci", "si apoi", "then what",
]

# Maps a situational question to a concrete allowed_actions key + friendly
# verb + KB topic. Order matters: first match wins.
const SITUATIONAL_ACTIONS := [
	{"keys": ["jump in", "jump-in", "jumpin", "intru", "intra", "sar peste"], "action": "jump_in", "verb": "Jump-In", "topic": "jump_in"},
	{"keys": ["call dutch", "chem dutch", "cheama dutch", "spun dutch"], "action": "call_dutch", "verb": "call Dutch", "topic": "dutch"},
	{"keys": ["confirm dutch", "confirm the dutch"], "action": "confirm_dutch", "verb": "confirm Dutch", "topic": "dutch"},
	{"keys": ["draw", "trag", "trage o carte", "iau o carte"], "action": "draw", "verb": "draw", "topic": "turn_flow"},
	{"keys": ["end turn", "end my turn", "termin randul", "termin tura", "incheia rand"], "action": "end_turn", "verb": "end your turn", "topic": "turn_flow"},
	{"keys": ["swap", "schimb"], "action": "swap_drawn", "verb": "swap", "topic": "swap_vs_discard"},
	{"keys": ["discard", "arunc"], "action": "discard_drawn", "verb": "discard the drawn card", "topic": "swap_vs_discard"},
	{"keys": ["peek", "use queen", "uit", "regina"], "action": "peek_ability", "verb": "use the Queen peek", "topic": "queen"},
]

## Main entry point. Routes to the deep pipeline when enabled, otherwise the
## original simple matcher. Always synchronous and deterministic.
func ask(question: String) -> Dictionary:
	var norm := _normalize(question)
	if norm.strip_edges() == "":
		return _fallback()
	if _deep_enabled():
		return _ask_deep(norm)
	return _ask_simple(norm)

## Async wrapper used by the UI to show a brief "thinking" animation.
## Returns the same dictionary as ask() after a short, skippable delay.
func ask_async(question: String, think_ms: int = 280, previous_answer: String = "") -> Dictionary:
	var started_ms := Time.get_ticks_msec()
	var gm := get_node_or_null("/root/GameManager")
	var grounded_result := _environment_answer(question)
	var local_result := ask(question)
	if grounded_result.is_empty():
		grounded_result = local_result
	var grounded_confident := _is_confident_local_answer(grounded_result)
	if gm != null and bool(gm.get("assistant_lm_enabled")):
		var lm_result: Dictionary = {}
		if grounded_confident:
			lm_result = await _ask_lm_refine_grounded(question, previous_answer, grounded_result)
		else:
			lm_result = await _ask_lm(question, previous_answer, grounded_result)
		if lm_result.get("ok", false):
			await _wait_for_polish_budget(started_ms)
			return lm_result.get("result", {})
	if grounded_confident:
		grounded_result["source"] = "deterministic_fast"
		return grounded_result
	var tree := get_tree()
	if tree != null and think_ms > 0:
		await tree.create_timer(think_ms / 1000.0).timeout
	local_result["source"] = "deterministic_fallback"
	return local_result

func _ask_lm(question: String, previous_answer: String, grounded_result: Dictionary) -> Dictionary:
	var snap: Dictionary = GameContext.build_snapshot()
	var grounded_answer := str(grounded_result.get("answer", "")).strip_edges()
	var grounded_topic := str(grounded_result.get("topic_id", "")).strip_edges()
	var compact_context := _compact_chippy_context(snap, grounded_topic)
	var messages: Array = [
		{"role": "system", "content": _chippy_system_prompt()},
		{"role": "user", "content": "Game context: %s\nGrounded draft: %s\nTopic: %s\nPrevious answer to avoid repeating: %s\nQuestion: %s" % [
			JSON.stringify(compact_context),
			grounded_answer if grounded_answer != "" else "(none)",
			grounded_topic if grounded_topic != "" else "(none)",
			previous_answer if previous_answer != "" else "(none)",
			question.strip_edges(),
		]},
	]
	var completion: Dictionary = await LmStudioClient.chat_completion(
		messages,
		[],
		"fast",
		{"max_tokens": CHIPPY_LM_MAX_TOKENS, "timeout_sec": CHIPPY_LM_TIMEOUT_SEC}
	)
	if not completion.get("ok", false):
		return completion
	var content := str(completion.get("content", "")).strip_edges()
	if content == "":
		return {"ok": false, "error": "empty_lm_answer"}
	if previous_answer != "" and _answers_match(content, previous_answer):
		return {"ok": false, "error": "repeated_previous_answer"}
	return {
		"ok": true,
		"result": {
			"answer": content,
			"confidence": 1.0,
			"topic_id": "lm_studio",
			"face": "cool",
			"thinking_steps": [],
			"suggestions": [],
			"source": "lm_studio",
			"model": LmStudioClient.model,
		},
	}

func _ask_lm_refine_grounded(question: String, previous_answer: String, grounded_result: Dictionary) -> Dictionary:
	var grounded_answer := str(grounded_result.get("answer", "")).strip_edges()
	var grounded_topic := str(grounded_result.get("topic_id", "")).strip_edges()
	var messages: Array = [
		{"role": "system", "content": _chippy_refine_prompt()},
		{"role": "user", "content": "Question: %s\nGrounded draft: %s\nTopic: %s\nPrevious answer to avoid repeating: %s" % [
			question.strip_edges(),
			grounded_answer if grounded_answer != "" else "(none)",
			grounded_topic if grounded_topic != "" else "(none)",
			previous_answer if previous_answer != "" else "(none)",
		]},
	]
	var completion: Dictionary = await LmStudioClient.chat_completion(
		messages,
		[],
		"fast",
		{"max_tokens": 80, "timeout_sec": 3.0}
	)
	if not completion.get("ok", false):
		return completion
	var content := str(completion.get("content", "")).strip_edges()
	if content == "":
		return {"ok": false, "error": "empty_lm_answer"}
	if previous_answer != "" and _answers_match(content, previous_answer):
		return {"ok": false, "error": "repeated_previous_answer"}
	return {
		"ok": true,
		"result": {
			"answer": content,
			"confidence": 1.0,
			"topic_id": "lm_studio",
			"face": "cool",
			"thinking_steps": [],
			"suggestions": [],
			"source": "lm_studio",
			"model": LmStudioClient.model,
		},
	}

func _compact_chippy_context(snap: Dictionary, grounded_topic: String) -> Dictionary:
	if grounded_topic.begins_with("environment_"):
		return {"kind": "environment"}
	var compact := {
		"fsm_state": snap.get("fsm_state", ""),
		"is_my_turn": snap.get("is_my_turn", false),
		"allowed_actions": snap.get("allowed_actions", []),
		"action_hint": snap.get("action_hint", ""),
	}
	if grounded_topic in ["dutch", "turn_flow", "swap_vs_discard", "queen", "jack", "jump_in", "lm_studio"]:
		compact["top_discard_rank"] = snap.get("top_discard_rank", "")
		compact["drawn_card_rank"] = snap.get("drawn_card_rank", "")
	return compact

func _wait_for_polish_budget(started_ms: int) -> void:
	var remaining_ms := CHIPPY_MIN_RESPONSE_MS - (Time.get_ticks_msec() - started_ms)
	if remaining_ms <= 0:
		return
	var tree := get_tree()
	if tree != null:
		await tree.create_timer(remaining_ms / 1000.0).timeout

func _is_confident_local_answer(result: Dictionary) -> bool:
	return str(result.get("topic_id", "")) != "" \
		or float(result.get("confidence", 0.0)) >= CONFIDENCE_THRESHOLD

func _environment_answer(question: String) -> Dictionary:
	var entry: Dictionary = EnvironmentKnowledge.lookup(question)
	if entry.is_empty():
		return {}
	return {
		"answer": str(entry.get("answer", "")),
		"confidence": 1.0,
		"topic_id": "environment_%s" % str(entry.get("id", "scene")),
		"face": "cool",
		"thinking_steps": [],
		"suggestions": [],
		"source": "deterministic_fast",
	}

func _answers_match(first: String, second: String) -> bool:
	var a := _normalize(first)
	var b := _normalize(second)
	return a != "" and b != "" and (a == b or (a.length() > 24 and b.contains(a)) or (b.length() > 24 and a.contains(b)))

func _chippy_system_prompt() -> String:
	return """You are Chippy, the read-only rules coach inside the Dutch card game.
Answer in the same language as the player, briefly and clearly.
If a grounded draft is supplied, improve it into a more natural and helpful answer without changing its facts.
Add one useful detail or short explanation when it helps, but stay concise.
Answer only the current standalone question. Never repeat the previous answer unless the player explicitly asks you to.
Never invent hidden cards, never claim an illegal action is legal, and never execute gameplay actions.
Treat the supplied live game context as authoritative for gameplay questions.
For questions about scenery, explain that visual details build the tavern atmosphere unless a documented gameplay role exists.
Do not reveal private chain-of-thought. Return only the concise answer for the player."""

func _chippy_refine_prompt() -> String:
	return """You are Chippy, the in-game Dutch card helper.
Rewrite the grounded draft into a better player-facing answer in the same language.
Keep all facts from the grounded draft, but make the wording smoother and a bit more helpful.
Use 1 or 2 short sentences. Do not add new rules or hidden information.
Do not repeat the previous answer verbatim."""

# ── Simple mode (backward compatible) ────────────────────────────────────────

func _ask_simple(norm: String) -> Dictionary:
	var tokens := _tokenize(norm)
	var best: Dictionary = {}
	var best_score := 0.0
	for entry in GameKnowledge.all_entries():
		var score := _score_entry(entry, norm, tokens)
		if score > best_score:
			best_score = score
			best = entry
	if _is_vague(norm):
		var ctx := _context_entry()
		if not ctx.is_empty():
			return _make_result(ctx, max(best_score, CONFIDENCE_THRESHOLD + 0.1))
	if best.is_empty() or best_score < CONFIDENCE_THRESHOLD:
		return _fallback()
	return _make_result(best, best_score)

# ── Deep mode (4-step reasoning pipeline) ────────────────────────────────────

func _ask_deep(norm: String) -> Dictionary:
	var tokens := _tokenize(norm)
	var steps: Array = []

	# Step 1 — intent.
	var intent := _classify_intent(norm, tokens)
	steps.append("Reading your question (%s)..." % intent)

	# Step 2 — live game context.
	var snap: Dictionary = {}
	if GameContext != null:
		snap = GameContext.build_snapshot()
	if snap.get("valid", false) and snap.get("in_game", false):
		steps.append("Checking the table: %s." % snap.get("fsm_state", "?"))

	# Step 3 — retrieve relevant rules.
	var ranked := retrieve(norm, tokens, TOP_K)
	if not ranked.is_empty():
		steps.append("Found rule: %s." % str(ranked[0]["entry"].get("id", "")))

	# Step 4 — synthesize an answer grounded in facts.
	match intent:
		INTENT_SITUATIONAL:
			return _synthesize_situational(norm, snap, ranked, steps)
		INTENT_WHAT_NOW:
			return _synthesize_what_now(snap, ranked, steps)
		INTENT_FOLLOW_UP:
			return _synthesize_follow_up(norm, tokens, ranked, steps)
		_:
			return _synthesize_rule(ranked, steps)

# ── Step 1: Intent classifier ────────────────────────────────────────────────

func _classify_intent(norm: String, tokens: PackedStringArray) -> String:
	for marker in FOLLOW_UP_MARKERS:
		if norm.begins_with(marker) or norm.contains(" " + marker + " "):
			if _last_topic_id != "":
				return INTENT_FOLLOW_UP
	if _is_vague(norm):
		return INTENT_WHAT_NOW
	for marker in SITUATIONAL_MARKERS:
		if norm.contains(marker):
			return INTENT_SITUATIONAL
	# Strong KB match -> rule lookup; nothing meaningful -> unknown.
	var best_score := 0.0
	for entry in GameKnowledge.all_entries():
		best_score = maxf(best_score, _score_entry(entry, norm, tokens))
	if best_score >= CONFIDENCE_THRESHOLD:
		return INTENT_RULE
	return INTENT_UNKNOWN

# ── Step 3: RAG retrieval (top-K + related propagation) ───────────────────────

## Returns an Array of {entry, score} sorted by score desc, length <= top_k.
## Entries whose situational_triggers match the current allowed_actions get a
## bonus, and high-scoring entries pull in their related[] topics.
func retrieve(norm: String, tokens: PackedStringArray, top_k: int = TOP_K) -> Array:
	var allowed: Array = []
	if GameContext != null:
		var snap: Dictionary = GameContext.build_snapshot()
		allowed = snap.get("allowed_actions", [])

	var scored: Array = []
	for entry in GameKnowledge.all_entries():
		var score := _score_entry(entry, norm, tokens)
		for trig in entry.get("situational_triggers", []):
			if trig in allowed:
				score += 0.4
		if score > 0.0:
			scored.append({"entry": entry, "score": score})

	scored.sort_custom(func(a, b): return a["score"] > b["score"])

	var result: Array = []
	var seen := {}
	for item in scored:
		if result.size() >= top_k:
			break
		var eid: String = str(item["entry"].get("id", ""))
		if seen.has(eid):
			continue
		seen[eid] = true
		result.append(item)

	# Pull in related topics of the top entry if there is room.
	if not result.is_empty() and result[0]["score"] >= CONFIDENCE_THRESHOLD:
		for rel_id in result[0]["entry"].get("related", []):
			if result.size() >= top_k:
				break
			if seen.has(str(rel_id)):
				continue
			var rel := GameKnowledge.get_entry(str(rel_id))
			if not rel.is_empty():
				seen[str(rel_id)] = true
				result.append({"entry": rel, "score": CONFIDENCE_THRESHOLD})
	return result

# ── Step 4: Answer synthesizers (facts only, no free generation) ─────────────

func _synthesize_situational(norm: String, snap: Dictionary, ranked: Array, steps: Array) -> Dictionary:
	var spec := _match_situational_action(norm)

	# "is it my turn" style question without a specific action.
	if spec.is_empty():
		if not snap.get("valid", false):
			return _with_steps(_synthesize_rule(ranked, steps), steps)
		var turn_line: String = "It's your turn right now." if snap.get("is_my_turn", false) \
				else "It's not your turn right now."
		var hint: String = str(snap.get("action_hint", ""))
		var ans := "[Situation] %s" % turn_line
		if hint != "":
			ans += "\n[Suggestion] %s" % hint
		steps.append("Turn owner check via FSM.")
		return _ground_result(ans, "turn_flow", "cool", 0.85, steps, _actions_to_suggestions(snap))

	steps.append("Verifying '%s' with the rules engine." % spec["action"])
	var topic_entry := GameKnowledge.get_entry(spec["topic"])
	var rule_text: String = topic_entry.get("answer", "") if not topic_entry.is_empty() else ""

	# Anti-hallucination: rely strictly on the live allowed_actions list.
	if not snap.get("valid", false) or not snap.get("in_game", false):
		var ans2 := "[Rule] %s" % rule_text
		ans2 += "\n[Note] Start a game and I can tell you if you may %s right now." % spec["verb"]
		return _ground_result(ans2, spec["topic"], "happy", 0.7, steps, [])

	var allowed: Array = snap.get("allowed_actions", [])
	var can_do: bool = spec["action"] in allowed
	var face: String = "cool" if can_do else "scared"
	var verdict: String = "Yes - you CAN %s right now." % spec["verb"] if can_do \
			else "No - you can't %s right now." % spec["verb"]

	var lines := "[Situation] %s" % verdict
	if not can_do and str(snap.get("action_hint", "")) != "":
		lines += "\n[Why] %s" % snap.get("action_hint", "")
	if rule_text != "":
		lines += "\n[Rule] %s" % rule_text
	if can_do and spec["action"] == "jump_in" and str(snap.get("top_discard_rank", "")) != "":
		lines += "\n[Tip] Top discard is %s - play a %s if you hold one." % [snap["top_discard_rank"], snap["top_discard_rank"]]

	return _ground_result(lines, spec["topic"], face, 0.95 if can_do else 0.8, steps, _actions_to_suggestions(snap))

func _synthesize_what_now(snap: Dictionary, ranked: Array, steps: Array) -> Dictionary:
	if not snap.get("valid", false) or not snap.get("in_game", false):
		# No live game: fall back to a general turn overview.
		return _with_steps(_synthesize_rule(ranked, steps), steps)

	var lines := ""
	var turn_line: String = "It's your turn." if snap.get("is_my_turn", false) else "It's not your turn yet."
	lines += "[Situation] %s" % turn_line
	if str(snap.get("action_hint", "")) != "":
		lines += "\n[Do] %s" % snap.get("action_hint", "")

	var allowed: Array = snap.get("allowed_actions", [])
	if not allowed.is_empty():
		lines += "\n[Options] %s" % ", ".join(_actions_to_labels(allowed))

	var beers: int = int(snap.get("beers", 0))
	if beers <= 1:
		lines += "\n[Careful] Only %d beer left - avoid risky Jump-Ins." % beers

	steps.append("Listed %d allowed action(s)." % allowed.size())
	return _ground_result(lines, "turn_flow", "cool", 0.85, steps, _actions_to_suggestions(snap))

func _synthesize_follow_up(norm: String, tokens: PackedStringArray, ranked: Array, steps: Array) -> Dictionary:
	steps.append("Linking to your last topic: %s." % _last_topic_id)
	# Re-rank, but bias toward the previous topic and its related entries.
	var prev := GameKnowledge.get_entry(_last_topic_id)
	if not prev.is_empty():
		# If the new question scores poorly, answer from the related graph.
		var top_score: float = ranked[0]["score"] if not ranked.is_empty() else 0.0
		if top_score < CONFIDENCE_THRESHOLD:
			var related_ids: Array = prev.get("related", [])
			if not related_ids.is_empty():
				var rel := GameKnowledge.get_entry(str(related_ids[0]))
				if not rel.is_empty():
					var ans := "[Follow-up] About %s: %s" % [_last_topic_id, rel.get("answer", "")]
					return _ground_result(ans, str(rel.get("id", "")), rel.get("face", "happy"), 0.7, steps, [])
	return _synthesize_rule(ranked, steps)

func _synthesize_rule(ranked: Array, steps: Array) -> Dictionary:
	if ranked.is_empty() or ranked[0]["score"] < CONFIDENCE_THRESHOLD:
		return _with_steps(_fallback(), steps)
	var primary: Dictionary = ranked[0]["entry"]
	var answer: String = primary.get("answer", "")
	# Append one closely related rule if it is also a strong hit.
	if ranked.size() > 1 and ranked[1]["score"] >= CONFIDENCE_THRESHOLD + 0.3:
		var second: Dictionary = ranked[1]["entry"]
		if str(second.get("id", "")) != str(primary.get("id", "")):
			answer += "\n\nRelated - %s" % second.get("answer", "")
			steps.append("Combined with: %s." % str(second.get("id", "")))
	var res := _make_result(primary, ranked[0]["score"])
	res["thinking_steps"] = steps
	res["answer"] = answer
	_last_topic_id = str(primary.get("id", ""))
	return res

func quick_questions() -> Array:
	return [
		{"label": "What is Dutch?", "query": "what is dutch"},
		{"label": "Jump-In?", "query": "how does jump in work"},
		{"label": "Queen / Jack?", "query": "what does queen and jack do"},
		{"label": "The chicken?", "query": "what is the chicken"},
		{"label": "Scoring?", "query": "how does scoring work"},
		{"label": "Abilities?", "query": "what abilities are there"},
	]

# ── Scoring ──────────────────────────────────────────────────────────────────

func _score_entry(entry: Dictionary, norm: String, tokens: PackedStringArray) -> float:
	var score := 0.0
	for pattern in entry.get("patterns", []):
		var pat := _normalize(str(pattern))
		if pat == "":
			continue
		# Strong signal: the whole pattern phrase appears in the question.
		if norm.contains(pat):
			score += 1.2 + 0.04 * pat.length()
		else:
			# Partial: shared meaningful tokens between pattern and question.
			score += 0.5 * _token_overlap(tokens, _tokenize(pat))

	# Tag keyword bonus: a tag word appears directly in the question.
	for tag in entry.get("tags", []):
		var tag_norm := _normalize(str(tag)).replace("_", " ")
		if tag_norm != "" and norm.contains(tag_norm):
			score += 0.6

	return score

func _token_overlap(a: PackedStringArray, b: PackedStringArray) -> float:
	if b.is_empty():
		return 0.0
	var hits := 0
	for t in b:
		if a.has(t):
			hits += 1
	return float(hits) / float(b.size())

# ── Context ──────────────────────────────────────────────────────────────────

func _is_vague(norm: String) -> bool:
	var tokens := _tokenize(norm)
	if tokens.size() <= 3:
		for vp in VAGUE_PATTERNS:
			if norm.contains(vp):
				return true
	return false

func _context_entry() -> Dictionary:
	var gm := get_node_or_null("/root/GameManager")
	if gm == null:
		return {}
	var state_name: String = gm.GameState.keys()[gm.current_state]
	if STATE_HINTS.has(state_name):
		return GameKnowledge.get_entry(STATE_HINTS[state_name])
	return {}

# ── Results ──────────────────────────────────────────────────────────────────

func _make_result(entry: Dictionary, score: float) -> Dictionary:
	_last_topic_id = str(entry.get("id", ""))
	return {
		"answer": entry.get("answer", ""),
		"confidence": clampf(score / 2.0, 0.0, 1.0),
		"topic_id": entry.get("id", ""),
		"face": entry.get("face", "happy"),
		"thinking_steps": [],
		"suggestions": [],
	}

func _fallback() -> Dictionary:
	return {
		"answer": "Hmm, I didn't quite get that. Try one of these, or ask about Dutch, Jump-In, the chicken, or scoring.",
		"confidence": 0.0,
		"topic_id": "",
		"face": "scared",
		"thinking_steps": [],
		"suggestions": quick_questions(),
	}

## Build a synthesized result whose answer text is grounded in facts (no KB id
## copy). Remembers topic for follow-ups.
func _ground_result(answer: String, topic_id: String, face: String, confidence: float, steps: Array, suggestions: Array) -> Dictionary:
	if topic_id != "":
		_last_topic_id = topic_id
	return {
		"answer": answer,
		"confidence": clampf(confidence, 0.0, 1.0),
		"topic_id": topic_id,
		"face": face,
		"thinking_steps": steps,
		"suggestions": suggestions,
	}

func _with_steps(result: Dictionary, steps: Array) -> Dictionary:
	result["thinking_steps"] = steps
	return result

# ── Deep-mode helpers ────────────────────────────────────────────────────────

func _deep_enabled() -> bool:
	if GameContext == null:
		return false
	var gm := get_node_or_null("/root/GameManager")
	if gm == null:
		return false
	return bool(gm.get("assistant_deep_reasoning"))

func _match_situational_action(norm: String) -> Dictionary:
	for spec in SITUATIONAL_ACTIONS:
		for key in spec["keys"]:
			if norm.contains(key):
				return spec
	return {}

const ACTION_LABELS := {
	"draw": "Draw",
	"discard_drawn": "Discard",
	"swap_drawn": "Swap",
	"jump_in": "Jump-In",
	"end_turn": "End turn",
	"call_dutch": "Call Dutch",
	"confirm_dutch": "Confirm Dutch",
	"forfeit_dutch": "Forfeit Dutch",
	"peek_ability": "Queen peek",
	"swap_ability": "Jack swap",
}

func _actions_to_labels(actions: Array) -> Array:
	var out: Array = []
	for a in actions:
		out.append(ACTION_LABELS.get(a, str(a)))
	return out

func _actions_to_suggestions(snap: Dictionary) -> Array:
	var out: Array = []
	for a in snap.get("allowed_actions", []):
		match a:
			"jump_in":
				out.append({"label": "Jump-In rules", "query": "how does jump in work"})
			"call_dutch":
				out.append({"label": "When to call Dutch?", "query": "what is dutch"})
			"draw":
				out.append({"label": "How a turn works", "query": "how does a turn work"})
			"peek_ability":
				out.append({"label": "Queen ability", "query": "what does queen do"})
			"swap_ability":
				out.append({"label": "Jack ability", "query": "what does jack do"})
	return out

# ── Text helpers ─────────────────────────────────────────────────────────────

func _normalize(text: String) -> String:
	var lower := text.to_lower()
	var out := ""
	for ch in lower:
		out += DIACRITICS.get(ch, ch)
	return out

func _tokenize(norm: String) -> PackedStringArray:
	var raw := norm.replace("-", " ").replace("/", " ").replace("?", " ").replace(",", " ").replace(".", " ").split(" ", false)
	var tokens: PackedStringArray = []
	for t in raw:
		var clean := t.strip_edges()
		if clean.length() < 2:
			continue
		if STOP_WORDS.has(clean):
			continue
		tokens.append(clean)
	return tokens

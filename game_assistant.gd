extends Node

## Offline answer engine for the in-game assistant (Chippy Q&A).
## No cloud LLM: questions are matched against GameKnowledge entries using
## token overlap + pattern substring scoring, with a small FSM context boost.

const CONFIDENCE_THRESHOLD := 0.34

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
	"help", "ajutor", "what should i do", "stuck", "blocat",
]

func ask(question: String) -> Dictionary:
	var norm := _normalize(question)
	if norm.strip_edges() == "":
		return _fallback()

	var tokens := _tokenize(norm)
	var best: Dictionary = {}
	var best_score := 0.0

	for entry in GameKnowledge.all_entries():
		var score := _score_entry(entry, norm, tokens)
		if score > best_score:
			best_score = score
			best = entry

	# Context boost: a vague question during a meaningful FSM state.
	if _is_vague(norm):
		var ctx := _context_entry()
		if not ctx.is_empty():
			return _make_result(ctx, max(best_score, CONFIDENCE_THRESHOLD + 0.1))

	if best.is_empty() or best_score < CONFIDENCE_THRESHOLD:
		return _fallback()

	return _make_result(best, best_score)

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
	return {
		"answer": entry.get("answer", ""),
		"confidence": clampf(score / 2.0, 0.0, 1.0),
		"topic_id": entry.get("id", ""),
		"face": entry.get("face", "happy"),
		"suggestions": [],
	}

func _fallback() -> Dictionary:
	return {
		"answer": "Hmm, I didn't quite get that. Try one of these, or ask about Dutch, Jump-In, the chicken, or scoring.",
		"confidence": 0.0,
		"topic_id": "",
		"face": "scared",
		"suggestions": quick_questions(),
	}

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

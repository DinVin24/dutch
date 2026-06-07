extends Node

## Offline knowledge base for the in-game assistant (Chippy Q&A).
## Entries are loaded from res://data/game_knowledge.json. A tiny embedded
## fallback keeps the assistant functional if the file is missing.
##
## Each entry: { id, tags[], patterns[], answer, face, related[], situational_triggers[] }
## "face" is a keyword resolved to a Chippy ASCII face by the assistant UI.
## "related" lists ids of connected topics; "situational_triggers" are action
## keywords (e.g. "jump_in") that link a topic to the live game context.

const KNOWLEDGE_PATH := "res://data/game_knowledge.json"

const FALLBACK_ENTRIES: Array = [
	{
		"id": "goal",
		"tags": ["goal", "win"],
		"patterns": ["goal", "how to win", "lowest score", "obiectiv", "cum castig"],
		"face": "cool",
		"answer": "Goal: finish with the LOWEST score. Cards are worth their rank in points, so trim high cards and call Dutch when you are ahead.",
	},
	{
		"id": "jump_in",
		"tags": ["jump_in"],
		"patterns": ["jump in", "jump-in", "match discard", "cum functioneaza jump in", "pot sa intru"],
		"face": "scared",
		"answer": "Jump-In: if you hold a card of the same rank as the top discard, play it any time. Wrong card = penalty card and a beer.",
	},
]

var entries: Array = []

func _ready() -> void:
	_load_entries()

func _load_entries() -> void:
	entries = _read_from_file()
	if entries.is_empty():
		entries = FALLBACK_ENTRIES.duplicate(true)

func _read_from_file() -> Array:
	if not FileAccess.file_exists(KNOWLEDGE_PATH):
		return []
	var file := FileAccess.open(KNOWLEDGE_PATH, FileAccess.READ)
	if file == null:
		return []
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("entries"):
		push_warning("GameKnowledge: malformed knowledge JSON, using fallback")
		return []
	var loaded: Array = []
	for raw in parsed["entries"]:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		if not raw.has("answer") or not raw.has("patterns"):
			continue
		loaded.append({
			"id": str(raw.get("id", "")),
			"tags": raw.get("tags", []),
			"patterns": raw.get("patterns", []),
			"face": str(raw.get("face", "happy")),
			"answer": str(raw.get("answer", "")),
			"related": raw.get("related", []),
			"situational_triggers": raw.get("situational_triggers", []),
		})
	return loaded

func all_entries() -> Array:
	return entries

func get_entry(entry_id: String) -> Dictionary:
	for e in entries:
		if e.get("id", "") == entry_id:
			return e
	return {}

## Returns the entry whose situational_triggers contains the given action key,
## or an empty dictionary if none match.
func entry_for_trigger(trigger: String) -> Dictionary:
	for e in entries:
		if trigger in e.get("situational_triggers", []):
			return e
	return {}

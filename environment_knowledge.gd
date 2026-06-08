extends Node

## Grounded catalog of semantic objects visible in the 3D game scene.
## This describes authored scene nodes and runtime-created props, not guesses
## about individual mesh names inside imported models.

const ENTRIES := [
	{
		"id": "room",
		"aliases": ["room", "tavern", "environment", "background", "walls", "wall", "floor", "ceiling", "brick", "wooden floor"],
		"answer": "The match takes place inside a stylized tavern room with brick walls, a wooden floor, a ceiling, ambient lighting, and a fixed gameplay camera. The room frames the card table but does not change the rules.",
	},
	{
		"id": "posters",
		"aliases": ["poster", "posters", "picture", "pictures", "wall art", "decorations", "decor", "afis", "afise"],
		"answer": "The wall posters and decorations build the tavern atmosphere and provide environmental storytelling. They are visual props and have no gameplay effect.",
	},
	{
		"id": "table",
		"aliases": ["table", "card table", "central table"],
		"answer": "The large central wooden table holds the deck, discard pile, player cards, turn indicators, and most match interactions.",
	},
	{
		"id": "chairs",
		"aliases": ["chair", "chairs", "seat", "seats"],
		"answer": "There are four wooden chairs arranged around the table, one for each player seat. Seat positions also anchor hands, beer mugs, avatars, and nearby cabinets.",
	},
	{
		"id": "cabinets",
		"aliases": ["cabinet", "cabinets", "drawer cabinet", "drawers", "drawer", "shelf", "shelves", "dulap", "sertar", "sertare"],
		"answer": "Each player has a cabinet beside their chair, positioned to the left of the seat. It has three interactive drawers: top, middle, and bottom. Click a drawer while within about 4.5 meters to open or close it. The cabinet stores up to six ability hammers, two per drawer; drawers containing abilities open automatically.",
	},
	{
		"id": "ability_hammers",
		"aliases": ["hammer", "hammers", "ability hammer", "ability hammers", "gold hammer", "sparkles", "ciocan", "ciocane"],
		"answer": "Glowing hammers inside a player's drawers represent owned chicken abilities. A cabinet has six hammer slots, two in each drawer. Hovering raises and highlights a hammer; clicking your own hammer on your turn uses that ability or begins target selection. Small gold sparkles and lights make active hammers easier to spot.",
	},
	{
		"id": "decorative_hammer",
		"aliases": ["big hammer", "large hammer", "decorative hammer", "hammer near player"],
		"answer": "The large standalone hammer model near the local side of the table is a scene prop. Usable abilities are the smaller glowing hammers stored inside the player cabinets.",
	},
	{
		"id": "deck",
		"aliases": ["deck", "draw pile", "card stack", "draw arrow", "cyan arrow"],
		"answer": "The deck is the face-down card stack on the left side of the table center. A cyan arrow appears above it when drawing is the expected action. Clicking the deck draws only when the FSM allows it.",
	},
	{
		"id": "discard",
		"aliases": ["discard", "discard pile", "discard area", "discard indicator", "played cards"],
		"answer": "The discard pile is the card area on the right side of the table center. It shows the most recently discarded card and drives rank-based Jump-In opportunities.",
	},
	{
		"id": "cards",
		"aliases": ["card", "cards", "hand", "hands", "face down cards", "pending card", "drawn card"],
		"answer": "Each player has a face-down hand at their seat. Cards only turn face up during allowed peeks, draws, or reveals. A newly drawn card temporarily appears as the pending card near the deck until it is discarded or swapped into the hand.",
	},
	{
		"id": "beer_mugs",
		"aliases": ["beer", "beers", "beer mug", "beer mugs", "mug", "mugs", "bere", "halba"],
		"answer": "Three beer mugs are displayed to the right of each player's hand. They visualize that player's remaining mistake allowance; mugs empty or disappear as beers are lost and refill when a refuel effect restores one.",
	},
	{
		"id": "chicken",
		"aliases": ["chicken", "chick", "hen", "ability shop", "shop", "gain ability"],
		"answer": "The chicken near the table is the ability shop. Clicking it on your turn attempts to spend 50 money for a random ability, provided your six cabinet slots are not full. The purchased ability appears as a hammer in your cabinet.",
	},
	{
		"id": "avatars",
		"aliases": ["player model", "player models", "avatar", "avatars", "characters", "character", "people", "players around table"],
		"answer": "Animated player avatars occupy the seats around the table. Remote and bot bodies are visible; the local body is hidden or adjusted in first-person view to avoid blocking the camera. Avatars idle and react during turns.",
	},
	{
		"id": "turn_indicators",
		"aliases": ["turn light", "turn lights", "colored light", "circle", "turn circle", "turn indicator", "glowing ring"],
		"answer": "A glowing ring around the table and colored seat lights show whose turn or targeting phase is active. The local seat is blue, with red, green, and amber used for the other seats.",
	},
	{
		"id": "camera_crosshair",
		"aliases": ["camera", "crosshair", "gray dot", "centre dot", "center dot", "view"],
		"answer": "The camera gives the player's table view and supports mouse or touch looking. The small gray center dot is the crosshair used to aim at interactive drawers, ability hammers, cards, and other selectable objects.",
	},
	{
		"id": "hud",
		"aliases": ["hud", "interface", "ui", "turn label", "buttons", "help button", "emote button", "action panel"],
		"answer": "The HUD contains the turn label, legal action buttons, status messages, targeting prompts, the emote wheel, and the Chippy help panel. These controls reflect the authoritative game state.",
	},
	{
		"id": "effects",
		"aliases": ["particles", "sparkles", "glitch", "crt", "screen effect", "visual effects", "fog", "lighting"],
		"answer": "The scene uses tavern lighting, glow, card and ability particles, camera shake, a CRT overlay, and brief glitch effects to communicate actions. These are presentation effects unless paired with a rule-driven event.",
	},
]

func lookup(question: String) -> Dictionary:
	var norm := _normalize(question)
	if norm == "":
		return {}
	var best: Dictionary = {}
	var best_score := 0
	for entry in ENTRIES:
		var score := 0
		for alias in entry.get("aliases", []):
			var alias_norm := _normalize(str(alias))
			if norm.contains(alias_norm):
				score += 2 + alias_norm.split(" ", false).size() + alias_norm.length()
		if score > best_score:
			best_score = score
			best = entry
	if best.is_empty():
		if _asks_for_inventory(norm):
			return {
				"id": "scene_inventory",
				"answer": inventory_summary(),
			}
		return {}
	return best.duplicate(true)

func inventory_summary() -> String:
	return "The 3D scene contains the tavern room and wall decor, central wooden table, four chairs, four three-drawer ability cabinets, glowing ability hammers, deck and discard zones, player hands and pending card, beer mugs, the chicken ability shop, animated player avatars, turn lights and ring, a decorative hammer, camera and crosshair, HUD panels, and temporary particles or screen effects."

func all_entries() -> Array:
	return ENTRIES.duplicate(true)

func _asks_for_inventory(norm: String) -> bool:
	var phrases := [
		"what is in the room",
		"what objects",
		"everything in the scene",
		"objects in the scene",
		"what can i see",
		"what is around me",
	]
	return phrases.any(func(phrase): return norm.contains(phrase))

func _normalize(text: String) -> String:
	return text.to_lower().strip_edges() \
		.replace("?", "") \
		.replace("!", "") \
		.replace(".", "") \
		.replace(",", "") \
		.replace("-", " ")

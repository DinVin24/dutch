extends Node
class_name DeckManager

# Signal for when the deck is reshuffled from discard
signal deck_reshuffled

var deck: Array = []
var discard_pile: Array = []

# Define standard suits and ranks
const SUITS = ["Hearts", "Diamonds", "Clubs", "Spades"]
const RANKS = [
	{"name": "Ace", "value": 1},
	{"name": "2", "value": 2},
	{"name": "3", "value": 3},
	{"name": "4", "value": 4},
	{"name": "5", "value": 5},
	{"name": "6", "value": 6},
	{"name": "7", "value": 7},
	{"name": "8", "value": 8},
	{"name": "9", "value": 9},
	{"name": "10", "value": 10},
	{"name": "Jack", "value": 11},
	{"name": "Queen", "value": 12},
	{"name": "King", "value": 13}
]

func create_deck():
	deck.clear()
	discard_pile.clear()
	for suit in SUITS:
		for rank in RANKS:
			var card_info = {
				"suit": suit,
				"rank": rank.name,
				"value": rank.value
			}
			# Special rule: King of Diamonds = 0 points
			if suit == "Diamonds" and rank.name == "King":
				card_info.value = 0
			
			deck.append(card_info)
	
	shuffle_deck()

func shuffle_deck():
	deck.shuffle()

func draw_card() -> Dictionary:
	if deck.is_empty():
		if discard_pile.size() > 1:
			# Keep the top card of discard, shuffle the rest back into deck
			var top_discard = discard_pile.pop_back()
			deck = discard_pile.duplicate()
			discard_pile = [top_discard]
			deck.shuffle()
			deck_reshuffled.emit()
		else:
			return {} # No cards left anywhere
			
	return deck.pop_back()

func discard_card(card: Dictionary):
	discard_pile.append(card)

func get_top_discard() -> Dictionary:
	if discard_pile.is_empty():
		return {}
	return discard_pile.back()

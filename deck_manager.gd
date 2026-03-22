extends Node
class_name DeckManager

# Signal for when the deck is reshuffled from discard
signal deck_reshuffled
signal discard_pile_updated

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
			var card = CardData.new(rank.name, suit)
			deck.append(card)
	
	shuffle_deck()

func shuffle_deck():
	deck.shuffle()

func draw_card() -> CardData:
	if deck.is_empty():
		if discard_pile.size() > 1:
			# Keep the top card of discard, shuffle the rest back into deck
			var top_discard = discard_pile.pop_back()
			# discard is an array of CardData
			deck = discard_pile.duplicate()
			discard_pile = [top_discard]
			deck.shuffle()
			deck_reshuffled.emit()
			
			# Ensure recycled cards are face down
			for card in deck:
				card.is_face_up = false
		else:
			return null # No cards left anywhere
			
	return deck.pop_back()

func discard_card(card: CardData):
	discard_pile.append(card)
	discard_pile_updated.emit()

func get_top_discard() -> CardData:
	if discard_pile.is_empty():
		return null
	return discard_pile.back()

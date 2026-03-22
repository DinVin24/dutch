extends Resource
class_name CardData

@export var suit: String = "Clubs"
@export var rank: String = "Ace"
@export var point_value: int = 1
@export var is_face_up: bool = false
@export var point_modifier: float = 1.0

func _init(p_rank: String = "Ace", p_suit: String = "Clubs"):
	rank = p_rank
	suit = p_suit
	recalc_point_value()

func recalc_point_value() -> int:
	var r = rank.to_upper()
	var s = suit.capitalize()
	
	# Mapping for standard points
	var values = {
		"ACE": 1, "2": 2, "3": 3, "4": 4, "5": 5, "6": 6, "7": 7,
		"8": 8, "9": 9, "10": 10, "JACK": 11, "QUEEN": 12, "KING": 13
	}
	
	point_value = values.get(r, 0)
	
	# Rule: Only King of Diamonds is 0
	if r == "KING" and s == "Diamonds":
		point_value = 0
		
	return int(point_value * point_modifier)

func display_name() -> String:
	return "%s of %s" % [rank, suit]

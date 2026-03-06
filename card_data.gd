extends Resource
class_name CardData

@export var suit: String = "Clubs"
@export var rank: String = "A"
@export var point_value: int = 1
@export var is_face_up: bool = false

const _rank_to_value: Dictionary = {
	"A": 1,
	"2": 2,
	"3": 3,
	"4": 4,
	"5": 5,
	"6": 6,
	"7": 7,
	"8": 8,
	"9": 9,
	"10": 10,
	"J": 11,
	"Q": 12,
	"K": 13,
}

const _red_suits: Array = ["Hearts", "Diamonds"]

func _init(default_rank: String = "A", default_suit: String = "Clubs") -> void:
	rank = default_rank
	suit = default_suit
	recalc_point_value()

func recalc_point_value() -> int:
	var normalized_rank = rank.strip_edges().to_upper()
	var normalized_suit = suit.strip_edges().capitalize()
	var base_value = _rank_to_value.get(normalized_rank, 0)
	# Rule: Only King of Diamonds is 0
	point_value = 0 if (normalized_rank == "K" and normalized_suit == "Diamonds") else base_value
	return point_value

func display_name() -> String:
	return "%s of %s" % [rank, suit]

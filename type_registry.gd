extends Node

# This autoload ensures shared GDScript classes are registered before other scripts compile.
const CARD_DATA_CLASS := preload("res://card_data.gd")
const BOT_CONTROLLER_CLASS := preload("res://bot_controller.gd")
const CARD_UI_CLASS := preload("res://card.gd")
const CARD_3D_CLASS := preload("res://card_3d.gd")

func _ready():
    # Instantiating is unnecessary; the preload-side effect registers the class names.
    set_process(false)

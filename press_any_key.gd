extends Control

@onready var prompt_label = $CenterContainer/PromptLabel
@onready var music_player_1 = $MusicPlayer1
@onready var music_player_2 = $MusicPlayer2

var current_player: AudioStreamPlayer
var next_player: AudioStreamPlayer

var wave_amplitude = 10.0
var wave_speed = 4.0
var base_y = 0.0

func _ready() -> void:
	# Ensure background music in GameManager is stopped if any
	if GameManager:
		GameManager.stop_menu_music()
	
	base_y = prompt_label.position.y
	
	# Setup Music
	var stream = preload("res://assets/music/press_any_key.mp3")
	music_player_1.stream = stream
	music_player_2.stream = stream
	
	current_player = music_player_1
	next_player = music_player_2
	
	current_player.play()
	
	# Initial volume setup
	current_player.volume_db = 0
	next_player.volume_db = -80

func _process(delta: float) -> void:
	# Wave animation
	var time = Time.get_ticks_msec() / 1000.0
	prompt_label.position.y = base_y + sin(time * wave_speed) * wave_amplitude
	
	# Manual crossfade loop logic
	if current_player.playing:
		var pos = current_player.get_playback_position()
		var length = current_player.stream.get_length()
		
		# Start crossfade 2 seconds before end
		if pos > length - 2.0 and not next_player.playing:
			_start_crossfade()

func _start_crossfade() -> void:
	next_player.play()
	var tween = create_tween().set_parallel(true)
	tween.tween_property(current_player, "volume_db", -80, 2.0)
	tween.tween_property(next_player, "volume_db", 0, 2.0)
	
	# Swap roles
	var temp = current_player
	current_player = next_player
	next_player = temp

func _input(event: InputEvent) -> void:
	if event is InputEventKey or event is InputEventMouseButton:
		if event.is_pressed():
			_transition_to_menu()

func _transition_to_menu() -> void:
	# Stop crossfade processing
	set_process(false)
	
	# Fade out current music before switching
	var tween = create_tween()
	tween.tween_property(current_player, "volume_db", -80, 0.5)
	tween.finished.connect(func():
		get_tree().change_scene_to_file("res://main_menu.tscn")
	)

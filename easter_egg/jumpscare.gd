extends CanvasLayer

# Jumpscare Singleton
# Triggered by typing "unsuros"

var input_sequence: String = ""
var target_sequence: String = "unsuros"

@onready var overlay = $Overlay
@onready var sprite = $Overlay/Sprite
@onready var audio_player = $AudioStreamPlayer

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS # Run even if game is paused
	overlay.hide()
	
	# Setup Procedural Scary Sound (Noise + Distortion)
	var audio_stream = AudioStreamGenerator.new()
	audio_stream.mix_rate = 44100
	audio_stream.buffer_length = 0.1
	audio_player.stream = audio_stream

func _input(event):
	if event is InputEventKey and event.pressed:
		var key_text = char(event.unicode).to_lower()
		if key_text.length() == 1:
			input_sequence += key_text
			if input_sequence.length() > target_sequence.length():
				input_sequence = input_sequence.right(target_sequence.length())
			
			if input_sequence == target_sequence:
				trigger_jumpscare()

func trigger_jumpscare():
	input_sequence = "" # Reset
	overlay.show()
	
	# Play procedural horrific noise
	_play_horror_noise()
	
	# Shake the sprite
	var center = sprite.position
	var tween = create_tween()
	for i in range(10):
		var offset = Vector2(randf_range(-30, 30), randf_range(-30, 30))
		tween.tween_property(sprite, "position", center + offset, 0.04).set_trans(Tween.TRANS_SINE)
	
	# Reset position at end
	tween.tween_property(sprite, "position", center, 0.04)
	
	# Hide after delay
	await get_tree().create_timer(1.5).timeout
	overlay.hide()
	audio_player.stop()

func _play_horror_noise():
	audio_player.play()
	var playback = audio_player.get_stream_playback()
	
	# Fill buffer with horrific distorted noise
	for i in range(playback.get_frames_available()):
		var sample = randf_range(-1.0, 1.0) # White noise
		playback.push_frame(Vector2(sample, sample))

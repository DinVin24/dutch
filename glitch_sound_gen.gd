extends AudioStreamPlayer

# A tiny script to generate procedural "blips" and "static" for UI feedback

func play_glitch_hover():
	var generator = AudioStreamGenerator.new()
	generator.mix_rate = 44100
	generator.buffer_length = 0.05 # Very short blip
	self.stream = generator
	self.play()
	
	var playback := get_stream_playback()
	if playback == null:
		return
	
	var phase = 0.0
	var increment = 400.0 / 44100.0 # 400Hz blip (less sharp)
	var frame_count := int(44100 * 0.05)
	
	for i in range(frame_count):
		if not playback.can_push_buffer(1):
			break
		var sample = sin(phase * TAU) * 0.15 # Reduced volume
		# Add noise for "glitch" feel
		sample += (randf() - 0.5) * 0.05 # Reduced noise
		playback.push_frame(Vector2(sample, sample))
		phase = fmod(phase + increment, 1.0)

func play_glitch_click():
	var generator = AudioStreamGenerator.new()
	generator.mix_rate = 44100
	generator.buffer_length = 0.1 # Deeper thump
	self.stream = generator
	self.play()
	
	var playback := get_stream_playback()
	if playback == null:
		return
	
	var phase = 0.0
	var increment = 100.0 / 44100.0 # 100Hz thump
	var frame_count := int(44100 * 0.1)
	
	for i in range(frame_count):
		if not playback.can_push_buffer(1):
			break
		var sample = sin(phase * TAU) * 0.3 # Reduced volume from 0.8
		# Drop pitch over time for "thud" effect
		increment *= 0.999
		# Add static
		sample += (randf() - 0.5) * 0.1 # Reduced static
		playback.push_frame(Vector2(sample, sample))
		phase = fmod(phase + increment, 1.0)

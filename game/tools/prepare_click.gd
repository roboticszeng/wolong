extends SceneTree

# Reproducible edit of Kenney's CC0 click: trim silence and resonant tail.
func _initialize() -> void:
	var source := AudioStreamOggVorbis.load_from_file("res://assets/audio/kenney/click_002.ogg")
	if source == null:
		push_error("Cannot decode source click")
		quit(1)
		return
	var playback := source.instantiate_playback()
	playback.start()
	var rate := int(AudioServer.get_mix_rate())
	var frames := playback.mix_audio(1.0, int(ceil(source.get_length() * rate)))
	playback.stop()
	var peak := 0.0
	for frame in frames: peak = maxf(peak, absf((frame.x + frame.y) * 0.5))
	var start := 0
	while start < frames.size() and absf((frames[start].x + frames[start].y) * 0.5) < peak * 0.02: start += 1
	var count := mini(int(rate * 0.035), frames.size() - start)
	if count < 16 or peak <= 0:
		push_error("Source click has no usable transient")
		quit(1)
		return
	var data := PackedByteArray()
	data.resize(count * 2)
	var mean := 0.0
	for index in count: mean += (frames[start + index].x + frames[start + index].y) * 0.5 / count
	for index in count:
		var sample: float = (frames[start + index].x + frames[start + index].y) * 0.5 - mean
		var attack := minf(1.0, float(index) / maxf(1, rate * 0.0005))
		var release := minf(1.0, float(count - 1 - index) / maxf(1, rate * 0.008))
		var value := int(clampf(sample / peak * 0.7 * attack * release, -0.85, 0.85) * 32767)
		data.encode_s16(index * 2, value)
	var output := AudioStreamWAV.new()
	output.format = AudioStreamWAV.FORMAT_16_BITS
	output.mix_rate = rate
	output.stereo = false
	output.data = data
	var error := output.save_to_wav("res://assets/audio/kenney/click_crisp.wav")
	print("Crisp click: %.1f ms, mono PCM, source %.1f ms" % [float(count) / rate * 1000, source.get_length() * 1000])
	quit(0 if error == OK else 1)

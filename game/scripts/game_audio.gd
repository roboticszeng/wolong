extends Node

const TRACKS = {
	"chengdu": preload("res://assets/audio/tozan/asianoriental1.ogg"),
	"hanzhong": preload("res://assets/audio/tozan/asianoriental2.ogg")}
const CRISP_CLICK = preload("res://assets/audio/kenney/click_crisp.wav")
const SOUNDS = {
	"click": CRISP_CLICK, "open": CRISP_CLICK, "close": CRISP_CLICK,
	"page": CRISP_CLICK, "work": CRISP_CLICK, "success": CRISP_CLICK,
	"error": CRISP_CLICK, "month": CRISP_CLICK, "trade": CRISP_CLICK,
	"arrival": CRISP_CLICK}
var settings_path := "user://audio.cfg"
var music_volume := 0.35
var effects_volume := 0.60
var muted := false
var ducked := false
var focused := true
var current_track := ""
var active_music := -1
var music_players: Array[AudioStreamPlayer] = []
var effects_players: Array[AudioStreamPlayer] = []
var gains := [0.0, 0.0]
var last_effect := ""
var pending_effect := ""
var effect_flush_queued := false
var effects_played := 0
const EFFECT_PRIORITY = {"click": 0, "open": 1, "close": 1, "page": 2, "month": 3, "arrival": 4, "work": 4, "trade": 4, "success": 5, "error": 6}
var loop_count := 0

func _ready() -> void:
	load_settings()
	for index in range(2):
		var player := AudioStreamPlayer.new()
		player.volume_linear = 0
		add_child(player)
		music_players.append(player)
	for index in range(1):
		var player := AudioStreamPlayer.new()
		add_child(player)
		effects_players.append(player)

func music(track: String, restart: bool = false) -> void:
	if not TRACKS.has(track): return
	if current_track == track and not restart: return
	current_track = track
	active_music = 0 if active_music != 0 else 1
	gains[active_music] = 0.0
	var player := music_players[active_music]
	player.stream = TRACKS[track]
	player.volume_linear = 0
	player.play()
	player.stream_paused = not focused

func _process(delta: float) -> void:
	if active_music < 0: return
	var active := music_players[active_music]
	# Overlap the end and beginning softly rather than hard-cutting full songs.
	if focused and active.playing and active.get_playback_position() >= active.stream.get_length() - 1.2:
		loop_count += 1
		music(current_track, true)
	for index in range(2):
		gains[index] = move_toward(gains[index], 1.0 if index == active_music else 0.0, delta / 1.2)
		music_players[index].volume_linear = 0.0 if muted else gains[index] * music_volume * 0.5 * (0.65 if ducked else 1.0)
		if index != active_music and gains[index] == 0.0: music_players[index].stop()

func effect(kind: String) -> void:
	if muted or not focused or effects_volume <= 0 or not SOUNDS.has(kind): return
	# A button and its action can both request feedback. Resolve those requests
	# together before playback: the result cue replaces the generic click.
	if pending_effect.is_empty() or EFFECT_PRIORITY[kind] >= EFFECT_PRIORITY[pending_effect]:
		pending_effect = kind
		last_effect = kind
	if not effect_flush_queued:
		effect_flush_queued = true
		_flush_effect.call_deferred()

func _flush_effect() -> void:
	effect_flush_queued = false
	var kind := pending_effect
	pending_effect = ""
	if kind.is_empty() or muted or not focused or effects_volume <= 0: return
	# A single voice prevents rapid clicks from leaving a stack of old cues.
	var player: AudioStreamPlayer = effects_players[0]
	player.stop()
	player.stream = SOUNDS[kind]
	player.pitch_scale = 1.0
	player.volume_linear = effects_volume * 0.45
	player.play()
	effects_played += 1

func set_volume(kind: String, value: float) -> void:
	if kind == "music": music_volume = clampf(value, 0.0, 1.0)
	elif kind == "effects":
		effects_volume = clampf(value, 0.0, 1.0)
		for player in effects_players: player.volume_linear = effects_volume * 0.45

func set_muted(value: bool) -> void:
	muted = value
	if value:
		for player in music_players: player.volume_linear = 0
		for player in effects_players: player.stop()

func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(settings_path) != OK: return
	for key in ["music", "effects"]:
		var value: Variant = config.get_value("audio", key, 0.35 if key == "music" else 0.60)
		if (value is float or value is int) and is_finite(float(value)):
			if key == "music": music_volume = clampf(float(value), 0, 1)
			else: effects_volume = clampf(float(value), 0, 1)
	var flag: Variant = config.get_value("audio", "muted", false)
	muted = flag if flag is bool else false

func save_settings() -> Error:
	var config := ConfigFile.new()
	config.set_value("audio", "music", music_volume)
	config.set_value("audio", "effects", effects_volume)
	config.set_value("audio", "muted", muted)
	return config.save(settings_path)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		focused = what == NOTIFICATION_APPLICATION_FOCUS_IN
		for player in music_players: player.stream_paused = not focused
		if not focused:
			for player in effects_players: player.stop()

func _exit_tree() -> void:
	for player in music_players + effects_players:
		player.stop()
		player.stream = null
	music_players.clear()
	effects_players.clear()

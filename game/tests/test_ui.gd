extends SceneTree

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, reason: String) -> void:
	checks += 1
	if not condition: failures.append(reason)

func find_buttons(node: Node) -> Array[Button]:
	var result: Array[Button] = []
	if node is Button: result.append(node)
	for child in node.get_children(): result.append_array(find_buttons(child))
	return result

func press(node: Node, title: String) -> bool:
	for button in find_buttons(node):
		if button.text == title and not button.disabled:
			button.pressed.emit()
			return true
	return false

func capture(name: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../logs/" + name + ".png"))

func click_world(app: Control, place: String) -> void:
	var position: Vector2 = root.get_final_transform() * (app.world.global_position + app.world.hit_point(place))
	var event := InputEventMouseButton.new()
	event.position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	root.push_input(event)
	await process_frame
	event = InputEventMouseButton.new()
	event.position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = false
	root.push_input(event)
	await process_frame

func _run() -> void:
	var guided = load("res://scenes/main.tscn").instantiate()
	guided.audio_settings_path = "user://test-ui-audio.cfg"
	root.add_child(guided)
	await process_frame
	check(guided.story_layer != null, "New game introduces modern reincarnation")
	await capture("ui-reincarnation")
	check(press(guided.story_layer, "这是……三国？"), "Opening is interactive")
	check(press(guided.story_layer, "先找到能落地的办法"), "Knowledge has material constraints")
	check(press(guided.story_layer, "进入成都 · 开始引导"), "Opening enters real tutorial")
	check(guided.simulation.state.turn == 0 and guided.story_layer == null, "Opening spends no campaign time")
	await process_frame
	await capture("ui-guidance")
	guided._open_place("warehouse")
	check(guided.story_layer != null and guided.simulation.state.chronicle.observed, "First granary visit explains a modern method")
	press(guided.story_layer, "打开委任面板")
	press(guided.drawer, "委任并开工")
	guided._advance()
	check(guided.simulation.state.projects.warehouse.stage == 1 and guided.story_layer != null, "Actual trial completion triggers scientist/officer feedback")
	await process_frame
	await capture("ui-tech-result")
	var turn_before: int = guided.simulation.state.turn
	guided._advance()
	check(guided.simulation.state.turn == turn_before, "Dialogue prevents accidental monthly advancement")
	press(guided.story_layer, "我的思考")
	press(guided.story_layer, "回到城中")
	guided._knowledge()
	await process_frame
	await capture("ui-knowledge")
	check(guided.simulation.save_game("user://tutorial-test.json").is_empty(), "Tutorial progress can be saved")
	var restored = load("res://scripts/simulation.gd").new()
	check(restored.load_game("user://tutorial-test.json").is_empty() and "trial" in restored.state.chronicle.events, "Loading retains identity and witnessed tech results")
	guided.queue_free()
	await process_frame
	var app = load("res://scenes/main.tscn").instantiate()
	app.audio_settings_path = "user://test-ui-audio.cfg"
	app.skip_intro = true
	root.add_child(app)
	await process_frame
	await process_frame
	await check_audio(app)
	await check_extensions(app)
	app._new_game()
	check(app.current_panel.is_empty() and not app.notice.visible, "Opening should be the game scene, without a text wall")
	check(app.world.size.x >= 1200 and app.world.size.y >= 700, "Town scene should fill the screen")
	await capture("ui-opening")
	await click_world(app, "warehouse")
	check(app.current_panel == "warehouse", "Clicking granary opens its contextual command card")
	await capture("ui-project-start")
	check(press(app.drawer, "委任并开工"), "Granary appointment action exists")
	check(app.simulation.state.projects.warehouse.active and app.current_panel.is_empty(), "Appointment starts project and returns to the scene")
	await click_world(app, "road")
	check(app.current_panel == "road", "Gate opens logistics controls")
	check(press(app.drawer, "整备粮道"), "Road improvement is accessible from gate")
	check(press(app.drawer, "委任并开工"), "Road officer can be appointed")
	check(app.simulation.state.projects.road.active, "Road appointment commits to simulation")
	await click_world(app, "road")
	check(press(app.drawer, "开始运粮"), "Transport starts through the game card")
	check(app.simulation.state.transport.enabled, "Transport remains a persistent policy")
	app._advance()
	check(app.simulation.state.turn == 1 and app.simulation.state.convoys.size() == 1, "Monthly advancement produces a real convoy")
	await process_frame
	app._toggle_map()
	await process_frame
	check(app.mode == "map", "Map mode is available")
	await capture("ui-logistics")
	await click_world(app, "hanzhong")
	check(app.selected_city == "hanzhong" and app.mode == "city", "Clicking map city enters its different town scene")
	await capture("ui-hanzhong")
	app._open_place("preview")
	await process_frame
	check(app.current_panel == "preview" and app.simulation.state.turn == 1, "Preview is contextual and does not advance")
	await capture("ui-report")
	app.current_panel = ""
	app._begin_auto(3)
	app._auto_step()
	if app.auto_remaining > 0: app._auto_step()
	check(app.auto_remaining == 0, "Milestone interrupts automatic passage of time")
	app._new_game()
	await process_frame
	root.size = Vector2i(1100,650)
	await process_frame
	await process_frame
	await capture("ui-small-window")
	await click_world(app, "market")
	await process_frame
	await capture("ui-market")
	var food_before: float = app.simulation.state.food.chengdu
	check(press(app.drawer, "买下这批粮"), "Market has direct visual purchase action")
	check(app.simulation.state.food.chengdu > food_before, "Market action changes local stock")
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	root.push_input(key)
	await process_frame
	check(app.simulation.state.turn == 1, "Space advances the month from the town view")
	app._new_game()
	app._open_place("warehouse")
	press(app.drawer, "委任并开工")
	app._open_place("roadproject")
	press(app.drawer, "委任并开工")
	app._open_place("road")
	press(app.drawer, "开始运粮")
	for month in range(24):
		if app.simulation.state.finished: break
		if not app.simulation.state.projects.warehouse.active and not app.simulation.stage_data("warehouse").is_empty():
			app.current_panel = ""
			app._open_place("warehouse")
			press(app.drawer, "委任并开工")
		app._advance()
		await process_frame
	check(app.simulation.state.finished and app.simulation.assessment().title == "后方初定", "New scene interface completes a full campaign")
	await process_frame
	check(app.ending_layer != null, "Outcome is presented as a graphical review")
	await capture("ui-ending")
	for failure in failures: push_error(failure)
	print("%s: %d UI checks" % ["PASS" if failures.is_empty() else "FAIL", checks])
	app.queue_free()
	await process_frame
	await create_timer(0.12).timeout
	quit(0 if failures.is_empty() else 1)

func check_extensions(app: Control) -> void:
	for kind in ["grain","coin","military","people"]:
		var chip = app.shell.find_child("resource_"+kind,true,false)
		check(chip != null and chip.tooltip_text.length() > 20 and chip.mouse_filter == Control.MOUSE_FILTER_STOP, "Resource chip has an accessible descriptive hover tooltip: " + kind)
	var world_script = load("res://scripts/world_view.gd")
	check(world_script.direction_row(Vector2.RIGHT) == 2 and world_script.direction_row(Vector2.LEFT) == 1 and world_script.direction_row(Vector2.UP) == 3 and world_script.direction_row(Vector2.DOWN) == 0, "Sprite facing follows all four actual movement directions")
	var walker_a: Dictionary = world_script.walker_state(Vector2.ZERO,Vector2(240,0),1)
	var walker_b: Dictionary = world_script.walker_state(Vector2.ZERO,Vector2(240,0),2)
	check(is_equal_approx(walker_a.position.distance_to(walker_b.position),24) and walker_a.row == 2, "Walking has consistent forward speed")
	var idle: Dictionary = world_script.walker_state(Vector2.ZERO,Vector2(240,0),10.5)
	var returning: Dictionary = world_script.walker_state(Vector2.ZERO,Vector2(240,0),13)
	check(not idle.moving and idle.frame == 1 and returning.row == 1 and returning.velocity.x < 0, "Pedestrians rest at destinations and face correctly on the return trip")
	app._toggle_map()
	await process_frame
	check(app.world.national_map != null and app.world.national_map.land.size() > 10, "Nationwide map uses geographical land data")
	var previous_city: String = app.selected_city
	await click_world(app,"luoyang")
	check(app.selected_city == previous_city and app.mode == "map" and app.notice.visible, "Other national cities can be inspected but cannot be governed")
	app.notice.hide()
	await capture("ui-national-map")
	await click_world(app,"chengdu")
	check(app.selected_city == "chengdu" and app.mode == "city", "Chengdu remains operable from the national map")
	app._knowledge()
	await process_frame
	check(app.technology_layer != null, "Technology workshop is available from the game UI")
	await capture("ui-technology-quiz")
	var panel = app.technology_layer
	for index in range(3):
		var q: Dictionary = app.simulation.technology.questions("chengdu","irrigation",0)[index]
		for option in q.options:
			if option.quality == 2:
				check(press(panel.card,option.text), "Real quiz choice submits the water knowledge answer")
				break
	check(press(panel.card,"委任科技试验"), "Completed quiz exposes a real appointment action")
	check(app.simulation.state.technology.projects["chengdu:irrigation"].active, "UI appointment commits technology to monthly simulation")
	await process_frame
	await capture("ui-technology-running")
	app._close_technology()
	app._advance()
	app._advance()
	check(app.simulation.state.technology.projects["chengdu:irrigation"].stage == 1, "Quiz project completes through real game months")
	app._knowledge()
	panel = app.technology_layer
	await process_frame
	check(panel.city == "chengdu", "Workshop keeps the selected region")
	check(press(panel.card,"汉中"), "Workshop supports a distinct Hanzhong project")
	check(app.simulation.state.technology.projects["hanzhong:irrigation"].stage == 0, "Chengdu adoption does not unlock Hanzhong adoption")
	app._close_technology()
	app._new_game()

func check_audio(app: Control) -> void:
	var sounds = app.audio
	sounds.focused = true
	sounds._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	sounds.set_muted(false)
	sounds.set_volume("music", 0.4)
	sounds.set_volume("effects", 0.6)
	await process_frame
	var played_before: int = sounds.effects_played
	app.current_panel = ""
	var test_open = app._button("打开行囊", func(): app._open_place("menu"))
	app.add_child(test_open)
	test_open.pressed.emit()
	await process_frame
	check(sounds.effects_played == played_before + 1 and sounds.last_effect == "open", "One button click plus panel action plays exactly one cue")
	test_open.queue_free()
	played_before = sounds.effects_played
	sounds.effect("click")
	sounds.effect("work")
	sounds.effect("success")
	await process_frame
	check(sounds.effects_played == played_before + 1 and sounds.last_effect == "success", "One action with multiple feedback requests plays only its result")
	played_before = sounds.effects_played
	sounds.effect("click")
	sounds.set_muted(true)
	await process_frame
	check(sounds.effects_played == played_before, "Muting cancels feedback queued by the mute button")
	sounds.set_muted(false)
	sounds.effect("page")
	await process_frame
	sounds.effect("page")
	await process_frame
	check(sounds.effects_played == played_before + 2 and sounds.effects_players.size() == 1, "Separate rapid clicks each play once without stacking voices")
	app.current_panel = ""
	app._refresh()
	check(sounds.TRACKS.size() == 2 and sounds.SOUNDS.size() == 10, "Downloaded music and effects are loaded")
	for stream in sounds.TRACKS.values():
		check(stream.get_length() > 30 and not stream.loop, "BGM is a real decodable song with managed loop transitions")
	for stream in sounds.SOUNDS.values():
		check(stream.get_length() > 0 and stream.get_length() < 5, "Effect decodes to a short playable sound")
	check(sounds.SOUNDS.click.get_length() <= 0.035, "Click ends within 35 ms without a resonant tail")
	check(sounds.SOUNDS.open == sounds.SOUNDS.click and sounds.SOUNDS.page == sounds.SOUNDS.click and sounds.SOUNDS.trade == sounds.SOUNDS.click, "Ordinary actions use the same dry click without musical chirps")
	var player = sounds.music_players[sounds.active_music]
	await create_timer(0.08).timeout
	var position: float = player.get_playback_position()
	app._refresh()
	check(sounds.music_players[sounds.active_music] == player and player.get_playback_position() >= position, "UI refresh preserves the music timeline")
	app._visit_city("hanzhong")
	check(sounds.current_track == "hanzhong" and sounds.music_players[sounds.active_music] != player, "City transition crossfades between two music players")
	await create_timer(1.4).timeout
	check(not player.playing and sounds.music_players[sounds.active_music].playing, "Old track stops after the fade while the new track continues")
	if DisplayServer.get_name() != "headless":
		var capture_effect := AudioEffectCapture.new()
		capture_effect.buffer_length = 0.5
		var effect_index := AudioServer.get_bus_effect_count(0)
		AudioServer.add_bus_effect(0, capture_effect)
		sounds.music_players[sounds.active_music].seek(20)
		await create_timer(0.25).timeout
		var frames := capture_effect.get_buffer(capture_effect.get_frames_available())
		var peak := 0.0
		for frame in frames: peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
		check(frames.size() > 0 and peak > 0.00001 and peak < 1.0, "Real audio driver outputs non-silent BGM below clipping")
		print("BGM output: %d PCM frames, peak %.5f" % [frames.size(), peak])
		sounds.set_volume("music", 0)
		sounds.effect("work")
		await create_timer(0.1).timeout
		capture_effect.clear_buffer()
		sounds.effect("trade")
		await create_timer(0.25).timeout
		frames = capture_effect.get_buffer(capture_effect.get_frames_available())
		peak = 0.0
		for frame in frames: peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
		check(frames.size() > 0 and peak > 0.00001 and peak < 1.0, "Real audio driver outputs non-silent effects below clipping")
		print("SFX output: %d PCM frames, peak %.5f" % [frames.size(), peak])
		sounds.set_volume("music", 0.4)
		AudioServer.remove_bus_effect(0, effect_index)
	sounds.music_players[sounds.active_music].seek(sounds.TRACKS.hanzhong.get_length() - 0.8)
	await create_timer(0.16).timeout
	check(sounds.loop_count > 0, "Track end restarts through a fade rather than falling silent")
	app._open_place("audio")
	await process_frame
	await capture("ui-audio-settings")
	var music_slider = app.drawer.find_child("music_volume", true, false)
	var effects_slider = app.drawer.find_child("effects_volume", true, false)
	music_slider.value = 25
	effects_slider.value = 0
	check(is_equal_approx(sounds.music_volume, 0.25) and sounds.effects_volume == 0, "Music and sound effects have independent working sliders")
	sounds.set_muted(true)
	check(sounds.music_players[sounds.active_music].volume_linear == 0, "Mute silences currently playing music immediately")
	check(sounds.save_settings() == OK, "Audio preferences save independently from the campaign")
	var restored = load("res://scripts/game_audio.gd").new()
	restored.settings_path = sounds.settings_path
	restored.load_settings()
	check(restored.muted and restored.effects_volume == 0 and is_equal_approx(restored.music_volume, 0.25), "Audio preferences survive a restart")
	restored.free()
	sounds.set_muted(false)
	sounds.set_volume("music", 0.4)
	sounds.set_volume("effects", 0.6)
	sounds.effect("success")
	check(sounds.last_effect == "success", "Success cue reaches the audio system")
	sounds._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(sounds.music_players[sounds.active_music].stream_paused, "Background window pauses music")
	sounds._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	app._visit_city("chengdu")

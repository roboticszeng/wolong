extends Control

const Simulation = preload("res://scripts/simulation.gd")
const World = preload("res://scripts/world_view.gd")
const Icon = preload("res://scripts/pixel_icon.gd")
const Portrait = preload("res://scripts/officer_portrait.gd")
const Chronicle = preload("res://scripts/chronicle.gd")
const GameAudio = preload("res://scripts/game_audio.gd")
const TechnologyPanel = preload("res://scripts/technology_panel.gd")
const GOLD = Color("e6c98c")
const CREAM = Color("f5ead1")
const MUTED = Color("bdb393")
var simulation = Simulation.new()
var selected_city := "chengdu"
var mode := "city"
var current_panel := ""
var selected_officers := {"warehouse": "jiangwan", "road": "liyan"}
var supervise := {"warehouse": false, "road": false}
var message := "先从粮仓开始，把记忆变成办法。"
var shell: Control
var world: Control
var drawer: PanelContainer
var notice: AcceptDialog
var new_game_dialog: ConfirmationDialog
var auto_timer: Timer
var auto_remaining := 0
var end_dialog_shown := false
var toast_timer: Timer
var adviser_text: Label
var ending_layer: Control
var story_layer: Control
var story_pages: Array = []
var story_index := 0
var skip_intro := false
var audio: Node
var audio_settings_path := "user://audio.cfg"
var technology_layer: Control

func _ready() -> void:
	audio = GameAudio.new()
	audio.settings_path = audio_settings_path
	add_child(audio)
	_make_theme()
	notice = AcceptDialog.new()
	notice.title = "蜀汉"
	notice.dialog_autowrap = true
	notice.min_size = Vector2i(400, 200)
	add_child(notice)
	new_game_dialog = ConfirmationDialog.new()
	new_game_dialog.title = "另起新局"
	new_game_dialog.dialog_text = "回到223年五月？未保存的进度会被替换。"
	new_game_dialog.confirmed.connect(_new_game)
	add_child(new_game_dialog)
	auto_timer = Timer.new()
	auto_timer.wait_time = 0.8
	auto_timer.timeout.connect(_auto_step)
	add_child(auto_timer)
	toast_timer = Timer.new()
	toast_timer.one_shot = true
	toast_timer.wait_time = 7
	toast_timer.timeout.connect(func(): message = "点击城中设施，安排下一步。"; if is_instance_valid(adviser_text): adviser_text.text = message)
	add_child(toast_timer)
	_refresh()
	if not skip_intro:
		_resume_intro()

func _make_theme() -> void:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "SimHei"])
	var t := Theme.new()
	t.default_font = font
	t.default_font_size = 17
	t.set_color("font_color", "Label", CREAM)
	t.set_color("font_color", "Button", CREAM)
	t.set_color("font_hover_color", "Button", Color("fff2c0"))
	t.set_color("font_disabled_color", "Button", Color("817662"))
	for type in ["Button", "CheckButton"]:
		t.set_stylebox("normal", type, _box(Color("3f3628"), Color("89754f")))
		t.set_stylebox("hover", type, _box(Color("685236"), GOLD))
		t.set_stylebox("pressed", type, _box(Color("8d6540"), GOLD))
		t.set_stylebox("disabled", type, _box(Color("302d26"), Color("5a5140")))
		t.set_stylebox("focus", type, _box(Color(0,0,0,0), GOLD))
	t.set_stylebox("panel", "PanelContainer", _box(Color("292820"), Color("a28a58")))
	t.set_stylebox("panel", "AcceptDialog", _box(Color("292820"), GOLD))
	t.set_stylebox("background", "ProgressBar", _box(Color("171d19"), Color("72613d")))
	t.set_stylebox("fill", "ProgressBar", _box(Color("ad9858"), Color("d8c27d")))
	t.set_constant("separation", "HBoxContainer", 10)
	t.set_constant("separation", "VBoxContainer", 10)
	theme = t

func _box(bg: Color, border: Color, margin: int = 10) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(1)
	box.content_margin_left = margin
	box.content_margin_right = margin
	box.content_margin_top = margin
	box.content_margin_bottom = margin
	box.shadow_color = Color(0,0,0,0.3)
	box.shadow_size = 3
	return box

func _text(value: String, font_size: int = 17, color: Color = CREAM) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	return label

func _button(title: String, callback: Callable, disabled: bool = false) -> Button:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size.y = 38
	button.disabled = disabled
	button.pressed.connect(func(): audio.effect("click"); callback.call())
	return button

func _icon(kind: String, dimension: int = 28) -> Control:
	var icon = Icon.new()
	icon.kind = kind
	icon.custom_minimum_size = Vector2(dimension, dimension)
	return icon

func _portrait(id: String, dimensions: Vector2 = Vector2(82, 82)) -> TextureRect:
	var portrait = Portrait.new()
	portrait.officer = id
	portrait.custom_minimum_size = dimensions
	return portrait

func _stat(kind: String, value: String, help: String = "") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.tooltip_text = help
	row.add_child(_icon(kind))
	row.add_child(_text(value, 20, GOLD))
	return row

func _place(node: Control, rectangle: Rect2) -> void:
	node.position = rectangle.position
	node.size = rectangle.size

func _refresh() -> void:
	audio.music("hanzhong" if mode == "map" else selected_city)
	Chronicle.ensure(simulation.state)
	if skip_intro:
		simulation.state.chronicle.skipped = true
		simulation.state.chronicle.observed = true
	if shell != null:
		remove_child(shell)
		shell.queue_free()
	shell = Control.new()
	shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shell)
	world = World.new()
	world.simulation = simulation
	world.city = selected_city
	world.view = mode
	world.selected_place = current_panel
	world.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	world.place_clicked.connect(_open_place)
	world.city_clicked.connect(_visit_city)
	shell.add_child(world)
	_build_hud()
	_build_bottom()
	_build_guidance()
	if not current_panel.is_empty():
		_build_drawer()
	if simulation.state.finished:
		if not end_dialog_shown:
			end_dialog_shown = true
			_show_ending.call_deferred()

func _build_hud() -> void:
	var top := PanelContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 18
	top.offset_right = -18
	top.offset_top = 14
	top.offset_bottom = 74
	top.add_theme_stylebox_override("panel", _box(Color(0.12,0.14,0.12,0.92), Color("b79c62"), 8))
	shell.add_child(top)
	var row := HBoxContainer.new()
	top.add_child(row)
	var seal := _text("蜀", 26, GOLD)
	seal.custom_minimum_size.x = 38
	row.add_child(seal)
	var city_name := _text("天下舆图" if mode == "map" else ("成都" if selected_city == "chengdu" else "汉中"), 25)
	city_name.custom_minimum_size.x = 128
	row.add_child(city_name)
	var resources := HBoxContainer.new()
	resources.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(resources)
	var free_labor: float = 100 - simulation.labor_used("chengdu") - simulation.labor_used("hanzhong")
	for item in [["grain", "粮 %.0f" % simulation.total_food(), "粮草总量（含在途）\n成都：%.1f · 汉中：%.1f\n人口每月消耗成都4、汉中2；施工供粮、仓储与运输也有损耗。九月税粮入库。" % [simulation.state.food.chengdu,simulation.state.food.hanzhong]], ["coin", "钱 %.0f" % simulation.state.money, "国库财政\n支付开工、施工、原料和运输。常规月收入4、支出3；项目另计，不能无限举债。"], ["military", "军需 %.0f" % simulation.state.military, "军需储备\n当前每月常规增加0.5。变卖可筹钱但削减军备；3铁料可加工为2军需。"], ["people", "劳力 %.0f" % free_labor, "可分配劳力（两地合计）\n成都余%.1f · 汉中余%.1f\n施工、作坊和运粮持续占用当地人手，异地劳力不能借用。" % [70-simulation.labor_used("chengdu"),30-simulation.labor_used("hanzhong")]]]:
		var chip := _stat(item[0], item[1], item[2])
		chip.custom_minimum_size.x = 112
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		chip.name = "resource_" + item[0]
		for child in chip.get_children(): child.mouse_filter = Control.MOUSE_FILTER_IGNORE
		resources.add_child(chip)
	row.add_child(_text(simulation.date_text(), 20, GOLD))
	row.add_child(_button("成都", func(): _visit_city("chengdu")))
	row.add_child(_button("汉中", func(): _visit_city("hanzhong")))
	var map_button := _button("舆图" if mode == "city" else "入城", _toggle_map)
	map_button.tooltip_text = "切换城镇与战略地图"
	row.add_child(map_button)
	var menu := _button("☰", func(): _open_place("menu"))
	menu.custom_minimum_size.x = 42
	row.add_child(menu)

func _build_bottom() -> void:
	# The adviser is a character, with a single short situational line.
	var adviser := PanelContainer.new()
	adviser.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	adviser.offset_left = 18
	adviser.offset_top = -160
	adviser.offset_right = 260
	adviser.offset_bottom = -18
	adviser.add_theme_stylebox_override("panel", _box(Color(0.12,0.14,0.12,0.94), Color("ab925f"), 7))
	shell.add_child(adviser)
	var row := HBoxContainer.new()
	adviser.add_child(row)
	row.add_child(_portrait("zhuge", Vector2(94, 112)))
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(details)
	details.add_child(_text("亮 · 我的心声", 17, GOLD))
	var health := ProgressBar.new()
	health.value = simulation.state.health
	health.show_percentage = false
	health.custom_minimum_size.y = 8
	health.tooltip_text = "健康 %.0f" % simulation.state.health
	details.add_child(health)
	details.add_child(_text("精力  %s" % ("●".repeat(simulation.personal_used()) + "○".repeat(3 - simulation.personal_used())), 14, MUTED))
	adviser_text = _text(message, 14)
	adviser_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	adviser_text.max_lines_visible = 3
	adviser_text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	details.add_child(adviser_text)
	var dock := PanelContainer.new()
	dock.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	dock.offset_left = 278
	dock.offset_right = -18
	dock.offset_top = -100
	dock.offset_bottom = -18
	dock.add_theme_stylebox_override("panel", _box(Color(0.12,0.14,0.12,0.96), Color("b79c62"), 8))
	shell.add_child(dock)
	var commands := HBoxContainer.new()
	dock.add_child(commands)
	for item in [["warehouse", "粮仓"], ["road", "粮道"], ["officers", "人物"], ["market", "集市"], ["report", "奏报"], ["knowledge", "科技"]]:
		var button := _button("", func(): _open_place(item[0]))
		button.custom_minimum_size = Vector2(80, 64)
		button.tooltip_text = item[1]
		var contents := VBoxContainer.new()
		contents.mouse_filter = Control.MOUSE_FILTER_IGNORE
		contents.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		contents.offset_top = 7
		contents.offset_bottom = -5
		contents.alignment = BoxContainer.ALIGNMENT_CENTER
		button.add_child(contents)
		contents.add_child(_icon("scroll" if item[0] == "knowledge" else item[0], 26))
		var caption := _text(item[1], 15)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		contents.add_child(caption)
		commands.add_child(button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	commands.add_child(spacer)
	if simulation.state.finished:
		commands.add_child(_button("复盘", _show_ending))
	else:
		commands.add_child(_button("预览", func(): _open_place("preview")))
	var next := _button("下个月 ▶", _advance, simulation.state.finished)
	next.custom_minimum_size.x = 130
	next.add_theme_stylebox_override("normal", _box(Color("8a392b"), Color("e2b873")))
	commands.add_child(next)
	var auto := _button("■ 暂停" if auto_remaining > 0 else "▶ 连续", func():
		if auto_remaining > 0: _stop_auto(); _say("已暂停。")
		else: _begin_auto(24), simulation.state.finished)
	auto.custom_minimum_size.x = 86
	commands.add_child(auto)
	# Four quiet goal symbols, hover reveals the criteria.
	var goals := HBoxContainer.new()
	goals.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	goals.position = Vector2(27, 90)
	goals.size = Vector2(175, 44)
	shell.add_child(goals)
	var score: Dictionary = simulation.assessment()
	for item in [["warehouse", score.warehouse, "仓储推广"], ["road", score.road, "粮道整备"], ["grain", score.supply, "汉中储粮达到50"], ["coin", score.finance, "留钱至少10"]]:
		var badge := PanelContainer.new()
		badge.custom_minimum_size = Vector2(38, 38)
		badge.tooltip_text = item[2]
		badge.add_theme_stylebox_override("panel", _box(Color(0.15,0.18,0.14,0.88), GOLD if item[1] else Color("716c55"), 5))
		var icon := _icon(item[0], 25)
		icon.modulate = Color.WHITE if item[1] else Color(0.65,0.65,0.65,1)
		badge.add_child(icon)
		goals.add_child(badge)

func _open_place(id: String) -> void:
	_stop_auto()
	audio.effect("open")
	if id == "knowledge":
		_knowledge()
		return
	if id == "warehouse":
		var c := Chronicle.ensure(simulation.state)
		if not c.observed and not c.skipped:
			c.observed = true
			current_panel = "warehouse"
			_refresh()
			_story([["zhuge", "现代记忆 · 粮为什么会坏？", "这里有粮，却仍在损失。我记得潮气、霉变与储藏条件有关；现代机器造不出来，但垫高粮袋、通风、分批记账，可以先小规模试一试。", "打开委任面板" ]])
			return
	current_panel = "" if current_panel == id else id
	_refresh()

func _visit_city(id: String) -> void:
	if id not in ["chengdu", "hanzhong"]:
		_show_notice("天下舆图", "这里目前只能察看；本轮开放治理成都与汉中。")
		return
	selected_city = id
	mode = "city"
	current_panel = ""
	_refresh()

func _toggle_map() -> void:
	mode = "map" if mode == "city" else "city"
	current_panel = ""
	_refresh()

func _build_drawer() -> void:
	drawer = PanelContainer.new()
	drawer.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	drawer.offset_left = -420
	drawer.offset_right = -18
	drawer.offset_top = 100
	drawer.offset_bottom = 570
	drawer.add_theme_stylebox_override("panel", _box(Color(0.12,0.14,0.12,0.97), GOLD, 16))
	shell.add_child(drawer)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 7)
	drawer.add_child(body)
	var header := HBoxContainer.new()
	body.add_child(header)
	var title: String = {"warehouse": "粮仓改良", "roadproject": "整备粮道", "road": "成都 → 汉中", "officers": "丞相府 · 人才", "market": "集市", "farm": "田地与收获", "report": "本月奏报", "preview": "下月预览", "menu": "行囊", "audio": "声音"}.get(current_panel, "蜀汉")
	var heading := _text(title, 25, GOLD)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	header.add_child(_button("?", _context_help))
	header.add_child(_button("×", func(): audio.effect("close"); current_panel = ""; _refresh()))
	body.add_child(HSeparator.new())
	match current_panel:
		"warehouse": _project_card(body, "warehouse")
		"roadproject": _project_card(body, "road")
		"road": _route_card(body)
		"market": _market_card(body)
		"officers": _officers_card(body)
		"farm": _farm_card(body)
		"report": _report_card(body, false)
		"preview": _report_card(body, true)
		"menu": _menu_card(body)
		"audio": _audio_card(body)

func _officer_picker(parent: VBoxContainer, id: String) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	for person in simulation.rules.officers:
		var button := _button("", func(): selected_officers[id] = person.id; _refresh())
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(106, 106)
		var chosen: bool = selected_officers[id] == person.id
		button.add_theme_stylebox_override("normal", _box(Color("54472e") if chosen else Color("252b25"), GOLD if chosen else Color("665c46"), 4))
		var content := VBoxContainer.new()
		content.add_theme_constant_override("separation", 3)
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		content.offset_top = 5
		content.offset_bottom = -5
		button.add_child(content)
		content.add_child(_portrait(person.id, Vector2(90, 70)))
		var name_label := _text(person.name + (" · 宜" if person.specialty == id else ""), 16, GOLD if chosen else CREAM)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(name_label)
		var busy := false
		for project_id in simulation.state.projects:
			var other: Dictionary = simulation.state.projects[project_id]
			if project_id != id and other.active and other.leader == person.id:
				busy = true
		button.disabled = busy or simulation.state.projects[id].active
		button.tooltip_text = "正在主持另一项目" if busy else person.description
		row.add_child(button)

func _project_card(body: VBoxContainer, id: String) -> void:
	var p: Dictionary = simulation.state.projects[id]
	var stage: Dictionary = simulation.stage_data(id)
	if id == "warehouse":
		var stocks := HBoxContainer.new()
		body.add_child(stocks)
		stocks.add_child(_stat("grain", "%.0f" % simulation.state.food[selected_city], "当地现粮"))
		stocks.add_child(_text("%s · 损耗%.2f%%" % [simulation.rules.cities[selected_city].name, simulation.storage_rate(simulation.state, selected_city) * 100], 14, MUTED))
	if id == "warehouse":
		var stages := HBoxContainer.new()
		body.add_child(stages)
		for index in range(3):
			var tile := _text(("✓ " if index < int(p.stage) else "") + ["试点", "常规", "推广"][index], 18, GOLD if index <= int(p.stage) else MUTED)
			tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			tile.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			stages.add_child(tile)
	if stage.is_empty():
		body.add_child(_icon("warehouse" if id == "warehouse" else "road", 80))
		body.add_child(_text("已落地", 25, GOLD))
		body.add_child(_text("成都与汉中都已采用仓储规范。" if id == "warehouse" else "道路容量20，运输损耗6%。", 17))
		return
	body.add_child(_text(stage.name, 18))
	_officer_picker(body, id)
	var cost: float = 0 if p.funded else float(stage.cost)
	var costs := HBoxContainer.new()
	body.add_child(costs)
	costs.add_child(_stat("coin", "%.0f" % cost, "本阶段首次投入"))
	costs.add_child(_stat("people", "%.0f" % stage.labor, "当地持续劳力"))
	var months: int = maxi(1, int(stage.months) - (1 if simulation.is_specialist(selected_officers[id], id) else 0))
	costs.add_child(_text("%d月" % months, 20, GOLD))
	body.add_child(_text("每月 %.1f钱 · %.1f粮" % [stage.upkeep, stage.food], 14, MUTED))
	var progress := ProgressBar.new()
	progress.max_value = maxi(1, simulation.duration(id) if p.active else months)
	progress.value = p.progress
	progress.show_percentage = false
	progress.custom_minimum_size.y = 12
	body.add_child(progress)
	var option := CheckButton.new()
	option.text = "亲自督办  ·  占1精力"
	option.button_pressed = supervise[id]
	option.disabled = p.active or simulation.state.finished
	option.toggled.connect(func(enabled: bool): supervise[id] = enabled)
	body.add_child(option)
	var action := _button("暂停施工" if p.active else ("继续施工" if p.funded else "委任并开工"), func():
		if p.active:
			simulation.pause_project(id)
			_say("工程暂停，进度保留。")
		else:
			var error: String = simulation.start_project(id, selected_officers[id], supervise[id])
			if not error.is_empty(): audio.effect("error"); _say(error); return
			audio.effect("work")
			_say("%s已领命。" % simulation.officer_name(selected_officers[id]))
		current_panel = ""
		_refresh(), simulation.state.finished)
	action.add_theme_stylebox_override("normal", _box(Color("7c3e29"), GOLD))
	body.add_child(action)
	if not p.reason.is_empty():
		body.add_child(_text(p.reason, 14, GOLD))
	action.tooltip_text = "已消耗的投入不退还；暂停释放劳力和精力。"

func _route_card(body: VBoxContainer) -> void:
	var route: Dictionary = simulation.route_values()
	var s: Dictionary = simulation.state
	var endpoints := HBoxContainer.new()
	body.add_child(endpoints)
	endpoints.add_child(_stat("grain", "%.0f" % s.food.chengdu, "成都库存"))
	endpoints.add_child(_text("→  一月  →", 17, MUTED))
	endpoints.add_child(_stat("grain", "%.0f" % s.food.hanzhong, "汉中库存"))
	body.add_child(_text("月容量%.0f · 损耗%.0f%%" % [route.capacity, route.loss * 100], 17))
	body.add_child(_text("每月运粮", 16, GOLD))
	var amounts := HBoxContainer.new()
	body.add_child(amounts)
	for amount in [4, 8, 12, 20]:
		var button := _button(str(amount), func(): simulation.set_transport(simulation.state.transport.enabled, amount); _refresh(), amount > route.capacity or s.finished)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if int(s.transport.amount) == amount:
			button.add_theme_stylebox_override("normal", _box(Color("665234"), GOLD))
		amounts.add_child(button)
	body.add_child(_text("成都保留20 · 汉中补到60", 14, MUTED))
	var row := HBoxContainer.new()
	row.add_child(_icon("road", 48))
	row.add_child(_text("运输中" if s.transport.enabled else "尚未发运", 21, GOLD))
	body.add_child(row)
	var cargo := 0.0
	for convoy in s.convoys: cargo += float(convoy.food)
	var arrival_month := int(s.month) % 12 + 1
	var arrival_year := int(s.year) + (1 if int(s.month) == 12 else 0)
	body.add_child(_text("在途 %.1f粮 · %d年%d月入汉中" % [cargo,arrival_year,arrival_month] if cargo > 0 else "本月无在途粮食", 16))
	var shipping_help := _text("出发扣成都现粮 → 途中运输 → 次月入汉中",14,MUTED)
	shipping_help.tooltip_text = "出发时汉中尚未收到；停止后续运粮也不取消已经出发的车队。"
	body.add_child(shipping_help)
	var toggle := _button("暂停运粮" if s.transport.enabled else "开始运粮", func():
		var enabled: bool = not simulation.state.transport.enabled
		simulation.set_transport(enabled, simulation.state.transport.amount)
		current_panel = ""
		_say("车队按月运粮，下月到货。" if enabled else "已暂停后续发运。")
		_refresh(), s.finished)
	toggle.add_theme_stylebox_override("normal", _box(Color("7c3e29"), GOLD))
	body.add_child(toggle)
	body.add_child(_button("整备粮道", func(): current_panel = "roadproject"; _refresh(), s.finished))
	body.add_child(_button("在舆图上查看", func(): mode = "map"; current_panel = ""; _refresh()))

func _market_card(body: VBoxContainer) -> void:
	body.add_child(_icon("grain", 64))
	body.add_child(_text("一批税粮替补", 21, GOLD))
	var city_rules: Dictionary = simulation.rules.cities[selected_city]
	body.add_child(_text("%s就地采购" % city_rules.name, 16, MUTED))
	var quota: float = simulation.rules.market_limit - simulation.state.market_used[selected_city]
	var amount := minf(12, quota)
	body.add_child(_text("%.0f粮   /   %.0f钱" % [amount, amount * 0.5], 23))
	body.add_child(_button("买下这批粮", func(): _action(simulation.buy_food(selected_city), "粮食已送入当地仓库。"), simulation.state.finished or quota <= 0))
	body.add_child(_text("本季还能采购 %.0f粮" % quota, 14, MUTED))
	body.add_child(HSeparator.new())
	body.add_child(_stat("military", "10军需 → 5钱"))
	body.add_child(_button("变卖军需", func(): _action(simulation.sell_military(), "筹得5钱，军备库存下降。"), simulation.state.finished))

func _officers_card(body: VBoxContainer) -> void:
	for person in simulation.rules.officers:
		var row := HBoxContainer.new()
		body.add_child(row)
		row.add_child(_portrait(person.id, Vector2(88,88)))
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(column)
		column.add_child(_text(person.name, 21, GOLD))
		var duty := "待命"
		for id in simulation.state.projects:
			if simulation.state.projects[id].active and simulation.state.projects[id].leader == person.id:
				duty = "主持仓储" if id == "warehouse" else "整备粮道"
		column.add_child(_text(duty, 16))
		column.add_child(_text("仓储专长" if person.specialty == "warehouse" else ("供给专长" if person.specialty == "road" else "善于协调"), 14, MUTED))
	body.add_child(_text("去粮仓或粮道，选择负责人。", 15, MUTED))

func _farm_card(body: VBoxContainer) -> void:
	body.add_child(_icon("leaf", 88))
	var months_left: int = (9 - int(simulation.state.month) + 12) % 12
	body.add_child(_text("九月收获", 26, GOLD))
	body.add_child(_text("本地预计税粮  %.1f" % (float(simulation.rules.cities[selected_city].harvest) * simulation.technology.harvest_factor(simulation.state,selected_city)), 21))
	var progress := ProgressBar.new()
	progress.value = (12 - months_left) / 12.0 * 100
	progress.show_percentage = false
	progress.custom_minimum_size.y = 18
	body.add_child(progress)
	body.add_child(_text("还有%d个月" % months_left if months_left > 0 else "今年税粮已入库", 18))
	body.add_child(_text("田间收入要等到收获，不能预支。", 15, MUTED))
	body.add_child(_button("水利知识与试验",_knowledge))

func _report_card(body: VBoxContainer, preview: bool) -> void:
	var report: Dictionary = simulation.state.last_report
	if preview:
		var result: Dictionary = simulation.preview_month()
		if not result.ok:
			var warning := _text(result.error, 17, GOLD)
			warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			body.add_child(warning)
			return
		report = result.state.last_report
	if report.is_empty():
		body.add_child(_icon("scroll", 88))
		body.add_child(_text("本月尚未结算", 20, GOLD))
		body.add_child(_text("先到粮仓委任，再安排粮道。", 16, MUTED))
		return
	body.add_child(_text(report.date, 18, GOLD))
	var stats := HBoxContainer.new()
	body.add_child(stats)
	stats.add_child(_stat("grain", "%+.1f" % (report.after - report.before), "国家总粮变化，包含在途"))
	stats.add_child(_stat("coin", "%+.1f" % report.money_delta, "财政变化"))
	body.add_child(_text("收获 +%.1f  ·  人口 −6.0  ·  施工供粮 −%.1f" % [report.harvest,maxf(0,report.consumed-6)],14,MUTED))
	body.add_child(_text("仓储 −%.2f  ·  运输 −%.2f（途中粮仍算总粮）" % [report.spoilage,report.transport_loss],14,MUTED))
	var shown := 0
	for note in report.notes:
		if shown >= 3: break
		var summary := _text(note, 16)
		summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		summary.max_lines_visible = 2
		summary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		summary.tooltip_text = note
		body.add_child(summary)
		shown += 1
	var space := Control.new()
	space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(space)
	body.add_child(_button("详细账目", func(): _show_detail(report)))
	if not preview:
		body.add_child(_button("往期记事", _journal))

func _show_detail(r: Dictionary) -> void:
	_show_notice("粮钱账目", "粮食 %.1f → %.1f\n收获 +%.1f · 消耗 −%.1f\n仓储损耗 %.2f · 运输损耗 %.2f\n财政变化 %+.2f\n实际劳力 成都%.1f / 汉中%.1f" % [r.before,r.after,r.harvest,r.consumed,r.spoilage,r.transport_loss,r.money_delta,r.labor.chengdu,r.labor.hanzhong])

func _menu_card(body: VBoxContainer) -> void:
	for item in [["保存游戏", _save], ["读取游戏", _load], ["声音设置", func(): _open_place("audio")], ["怎么玩", _help], ["恢复操作引导", func(): simulation.state.chronicle.skipped = false; _refresh()], ["另起新局", func(): new_game_dialog.popup_centered()]]:
		body.add_child(_button(item[0], item[1]))
	body.add_child(_text("画面：B.B.Bits / 原创生成\n音乐：Tozan · 音效：Kenney", 13, MUTED))

func _audio_card(body: VBoxContainer) -> void:
	body.add_child(_text("城中有乐，案前有声", 19, GOLD))
	for item in [["music", "背景音乐", audio.music_volume], ["effects", "操作音效", audio.effects_volume]]:
		var row := HBoxContainer.new()
		body.add_child(row)
		var label := _text(item[1], 17)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var amount := _text("%d%%" % roundi(item[2] * 100), 17, GOLD)
		row.add_child(amount)
		var slider := HSlider.new()
		slider.name = item[0] + "_volume"
		slider.min_value = 0
		slider.max_value = 100
		slider.step = 1
		slider.value = item[2] * 100
		slider.custom_minimum_size = Vector2(330, 28)
		slider.value_changed.connect(func(value: float):
			audio.set_volume(item[0], value / 100)
			amount.text = "%d%%" % roundi(value))
		slider.drag_ended.connect(func(_changed: bool): _persist_audio())
		slider.focus_exited.connect(_persist_audio)
		body.add_child(slider)
	var mute := CheckButton.new()
	mute.text = "全部静音"
	mute.button_pressed = audio.muted
	mute.toggled.connect(func(value: bool): audio.set_muted(value); _persist_audio())
	body.add_child(mute)
	body.add_child(_button("试听音效", func(): audio.effect("success")))
	body.add_child(_text("音乐：Tozan · 东方风格器乐\n音效：Kenney · CC0开放授权", 14, MUTED))
	body.add_child(_button("音频素材鸣谢", func(): _show_notice("音频鸣谢", "Tozan：Asianoriental1、Asianoriental2\nhttps://opengameart.org/content/asianoriental1\nhttps://opengameart.org/content/asianoriental2\n\nKenney：Interface Sounds\nhttps://kenney.nl/assets/interface-sounds\n\n均以原作者页面的CC0授权使用。")))
	body.add_child(_button("返回行囊", func(): _persist_audio(); _open_place("menu")))

func _persist_audio() -> void:
	if audio.save_settings() != OK: _say("声音偏好保存失败，本次调整仍然生效。")

func _exit_tree() -> void:
	if is_instance_valid(audio): audio.save_settings()

func _show_notice(title: String, content: String) -> void:
	notice.title = title
	notice.dialog_text = content
	notice.popup_centered(Vector2i(500, 260))

func _say(content: String) -> void:
	message = content
	if is_instance_valid(adviser_text):
		adviser_text.text = content
	toast_timer.start()
	if content.length() > 38:
		_show_notice("丞相案前", content)

func _action(error: String, success: String) -> void:
	_stop_auto()
	audio.effect(("trade" if current_panel == "market" else "success") if error.is_empty() else "error")
	_say(success if error.is_empty() else error)
	if error.is_empty():
		current_panel = ""
	_refresh()

func _advance() -> void:
	_stop_auto()
	_step()

func _step() -> bool:
	if story_layer != null: return false
	var had_convoy: bool = not simulation.state.convoys.is_empty()
	var result: Dictionary = simulation.advance_month()
	if not result.ok:
		_stop_auto()
		audio.effect("error")
		_say(result.error)
		return false
	current_panel = ""
	message = "九月丰收，税粮入库。" if int(simulation.state.month) == 9 else "又过了一月。"
	for note in result.notes:
		if note.contains("完成："):
			message = "仓储成果已成，去粮仓继续推广。" if note.contains("仓储") else "栈道整备完成，运粮更顺畅了。"
			break
		if note.contains("库存低") or note.contains("受阻"):
			message = "供给有变化，请检视粮仓与粮道。"
	if result.important:
		_stop_auto()
	_refresh()
	world.effect_time = 1.2
	toast_timer.start()
	var entry := Chronicle.event(simulation.state, had_convoy)
	audio.effect("success" if not entry.is_empty() else ("arrival" if had_convoy else "month"))
	if not entry.is_empty():
		_stop_auto()
		if not skip_intro:
			_story([[entry[2], entry[3], entry[4], "我的思考"], ["zhuge", "穿越者的思考", entry[5], "回到城中"]])
	return not result.important

func _begin_auto(months: int) -> void:
	if story_layer != null: return
	current_panel = ""
	auto_remaining = months
	message = "时间流逝，遇到要事会停下。"
	auto_timer.start()
	_refresh()

func _auto_step() -> void:
	if auto_remaining <= 0:
		_stop_auto()
		return
	auto_remaining -= 1
	var continue_time := _step()
	if not continue_time or auto_remaining <= 0:
		_stop_auto()
		_refresh()

func _stop_auto() -> void:
	auto_remaining = 0
	if auto_timer != null:
		auto_timer.stop()

func _save() -> void:
	_stop_auto()
	var error: String = simulation.save_game()
	audio.effect("success" if error.is_empty() else "error")
	current_panel = ""
	_say("已记下当前进度。" if error.is_empty() else error)
	_refresh()

func _load() -> void:
	_stop_auto()
	var error: String = simulation.load_game()
	audio.effect("page" if error.is_empty() else "error")
	if error.is_empty():
		for id in simulation.state.projects:
			var p: Dictionary = simulation.state.projects[id]
			if simulation.officer_name(p.leader) != "未委任":
				selected_officers[id] = p.leader
			supervise[id] = p.supervise
		end_dialog_shown = false
	current_panel = ""
	_say("已回到" + simulation.date_text() if error.is_empty() else error)
	_refresh()
	if error.is_empty() and not skip_intro: _resume_intro()

func _new_game() -> void:
	_stop_auto()
	if ending_layer != null:
		ending_layer.queue_free()
		ending_layer = null
	simulation.reset()
	selected_city = "chengdu"
	mode = "city"
	current_panel = ""
	selected_officers = {"warehouse": "jiangwan", "road": "liyan"}
	supervise = {"warehouse": false, "road": false}
	end_dialog_shown = false
	message = "丞相，先去粮仓看看吧。"
	_refresh()
	if not skip_intro: _resume_intro()

func _help() -> void:
	_show_notice("你是谁 · 怎样兴汉", "你是魂穿诸葛亮的现代人。用现代常识提出办法，让蜀汉的人才把它变成可执行的制度。\n\n点粮仓选负责人开工 → 下个月等待试点完成 → 再做常规执行、汉中推广。点城门修路并运粮，粮下一月到达。\n\n粮钱与劳力有限；九月收税粮，途中也有损耗。札记解释知识如何落地，各面板的 ? 解释规则。\n\n224年十月检视后方筹备，这一章尚未进入北伐。空格推进、Esc关闭面板、Ctrl+S保存。")

func _journal() -> void:
	var lines: Array = simulation.state.history.slice(maxi(0, simulation.state.history.size()-8))
	lines.reverse()
	_show_notice("往期记事", "\n".join(lines))

func _show_ending() -> void:
	_stop_auto()
	audio.effect("success")
	if ending_layer != null:
		ending_layer.queue_free()
	ending_layer = Control.new()
	ending_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(ending_layer)
	var shade := ColorRect.new()
	shade.color = Color(0.06,0.08,0.06,0.78)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ending_layer.add_child(shade)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -330
	panel.offset_right = 330
	panel.offset_top = -230
	panel.offset_bottom = 230
	panel.add_theme_stylebox_override("panel", _box(Color("282a22"), GOLD, 24))
	ending_layer.add_child(panel)
	var body := VBoxContainer.new()
	panel.add_child(body)
	var score: Dictionary = simulation.assessment()
	body.add_child(_text("建兴二年 · 后方检视", 17, MUTED))
	body.add_child(_text(score.title, 34, GOLD))
	var symbols := HBoxContainer.new()
	body.add_child(symbols)
	for item in [["warehouse", "仓储", score.warehouse], ["road", "粮道", score.road], ["grain", "储备", score.supply], ["coin", "财政", score.finance]]:
		var card := VBoxContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		symbols.add_child(card)
		card.add_child(_icon(item[0], 74))
		var label := _text(item[1] + ("  ✓" if item[2] else "  ○"), 21, GOLD if item[2] else MUTED)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.add_child(label)
	body.add_child(_text("汉中储粮 %.0f · 国库留钱 %.0f" % [simulation.state.food.hanzhong, simulation.state.money], 20))
	body.add_child(_text("整备后方，是走向北方的第一步。", 18, MUTED))
	var portrait_row := HBoxContainer.new()
	portrait_row.add_child(_portrait("zhuge", Vector2(84,84)))
	portrait_row.add_child(_text("人能接过职责，粮能走出山川。\n蜀汉的准备，如今有了着落。", 19))
	body.add_child(portrait_row)
	var actions := HBoxContainer.new()
	body.add_child(actions)
	actions.add_child(_button("再试一种安排", _new_game))
	actions.add_child(_button("回到城中", func(): ending_layer.queue_free(); ending_layer = null))

func _resume_intro() -> void:
	var c := Chronicle.ensure(simulation.state)
	if c.intro >= 3: return
	var pages := [
		["zhuge", "序章 · 醒在白帝城", "你最后记得的，是现代生活。再睁眼时，床前的人叫你‘丞相’。你的手中是一把羽扇，镜中却是诸葛亮的脸。", "这是……三国？"],
		["zhuge", "你知道历史，却没有现成答案", "刘备的托付压在肩上。你记得蜀汉的结局，也懂一些现代科学常识。但这里没有工厂，没有仪器；光知道原理，救不了这个时代。", "先找到能落地的办法"],
		["jiangwan", "第一章 · 223年五月，成都", "丞相，汉中要粮，国库也需留钱。先从粮仓试起吧。您提出办法，我来组织仓吏。兴复汉室，得从后方能供得上开始。", "进入成都 · 开始引导"]]
	_story(pages.slice(int(c.intro)), true)

func _story(pages: Array, opening: bool = false) -> void:
	_stop_auto()
	if story_layer != null: story_layer.queue_free()
	story_pages = pages
	story_index = 0
	_show_story_page(opening)

func _show_story_page(opening: bool) -> void:
	if story_layer != null:
		remove_child(story_layer)
		story_layer.queue_free()
		story_layer = null
	if story_index >= story_pages.size():
		audio.ducked = false
		_refresh()
		if not opening:
			var entry := Chronicle.event(simulation.state, false)
			if not entry.is_empty():
				_story([[entry[2], entry[3], entry[4], "我的思考"], ["zhuge", "穿越者的思考", entry[5], "回到城中"]])
		return
	story_layer = Control.new()
	audio.ducked = true
	story_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(story_layer)
	var shade := ColorRect.new()
	shade.color = Color(0.03, 0.06, 0.05, 0.65)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	story_layer.add_child(shade)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -430
	panel.offset_right = 430
	panel.offset_top = -155
	panel.offset_bottom = 155
	panel.add_theme_stylebox_override("panel", _box(Color("252b25"), GOLD, 24))
	story_layer.add_child(panel)
	var page: Array = story_pages[story_index]
	var row := HBoxContainer.new()
	panel.add_child(row)
	row.add_child(_portrait(page[0], Vector2(180, 230)))
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(body)
	body.add_child(_text("卧龙 · 科技兴汉", 15, MUTED))
	body.add_child(_text(page[1], 25, GOLD))
	var line := _text(page[2], 21)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(line)
	var actions := HBoxContainer.new()
	body.add_child(actions)
	actions.add_child(_button(page[3], func():
		audio.effect("page")
		story_index += 1
		if opening: simulation.state.chronicle.intro += 1
		_show_story_page(opening)))
	if opening:
		actions.add_child(_button("跳过序章", func():
			simulation.state.chronicle.intro = 3
			story_index = story_pages.size()
			_show_story_page(opening)))

func _build_guidance() -> void:
	var goal := Chronicle.goal(simulation.state)
	if goal.is_empty(): return
	world.tutorial_target = goal[0]
	var panel := PanelContainer.new()
	panel.position = Vector2(24, 145)
	panel.custom_minimum_size = Vector2(350, 100)
	panel.add_theme_stylebox_override("panel", _box(Color(0.09,0.14,0.12,0.92), GOLD, 10))
	shell.add_child(panel)
	var body := VBoxContainer.new()
	panel.add_child(body)
	body.add_child(_text(goal[1], 18, GOLD))
	var instruction := _text(goal[2], 15)
	instruction.custom_minimum_size.x = 325
	instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(instruction)
	var actions := HBoxContainer.new()
	body.add_child(actions)
	actions.add_child(_button("查看目标 →", func():
		if goal[0] == "next": _open_place("preview")
		elif goal[0] == "map": _toggle_map()
		else: _open_place(goal[0])))
	actions.add_child(_button("收起引导", func(): simulation.state.chronicle.skipped = true; _refresh()))

func _knowledge() -> void:
	_stop_auto()
	if technology_layer != null: _close_technology()
	technology_layer = TechnologyPanel.new()
	technology_layer.app = self
	technology_layer.city = selected_city
	add_child(technology_layer)

func _close_technology() -> void:
	if technology_layer != null:
		remove_child(technology_layer)
		technology_layer.queue_free()
		technology_layer = null
	_refresh()

func _memory_notes() -> void:
	var p: Dictionary = simulation.state.projects.warehouse
	var local_rate: float = simulation.storage_rate(simulation.state, "chengdu") * 100
	_story([["zhuge", "现代记忆 · 仓储科学", "知识：潮气会让粮更容易坏。\n办法：垫高、通风、分批登记，先在成都试。\n落地：试点 → 仓吏章程 → 汉中训练。\n当前成都月损耗 %.2f%%；汉中必须当地推广后才受益。" % local_rate, "为什么不能直接造机器？"],
		["zhuge", "知道原理，不等于拥有技术", "我记得蒸汽机、工业生产，也知道它们需要材料、加工精度与大量燃料。眼下能验证的是仓储与运输。先学会测量、训练匠人，让人才与制度接住知识，才有资格谈更远的工业。", "查看当前成果"],
		["jiangwan", "兴汉札记 · 已落地的能力", "仓储阶段：%d / 3\n粮道整备：%s\n下一步：%s\n\n224年十月检视后方。汉中储粮50、留钱10，还要完成仓储推广和粮道整备。" % [int(p.stage), "已完成" if simulation.state.projects.road.stage > 0 else "待完成", "维持粮运与财政" if p.stage >= 3 else "回粮仓推进下一阶段"], "回到城中"]])

func _context_help() -> void:
	var content: String = {
		"audio": "背景音乐和操作音效分别调节，拖动后立即生效。全部静音会停止提示音并关闭音乐输出，取消后恢复。切到后台时暂停声音，回到游戏继续。声音偏好独立保存，不随另起新局或读取游戏而重置。",
		"warehouse": "现代常识提出防潮与记录办法，蒋琬组织仓吏落实。试点只影响成都；常规执行扩大成都效果；汉中推广才改变当地损耗。开工付一次投入，施工每月付粮钱、占劳力。选擅长者缩短工期；亲自督办占持续精力。", 
		"roadproject": "李严擅长粮道。修路提高运量、减少运输损耗，但不会自动运粮；完工后仍需在城门安排运输。", 
		"road": "粮当月从成都扣除，扣除途中损耗，下一月交入汉中。运量受道路、劳力、粮钱约束。成都保留20、汉中目标60，防止把后方搬空。途中粮计入总粮，不能用于当地吃饭。", 
		"market": "购买的是所在城市的现粮，花钱立即补库存；每季购买有上限。卖军需换钱会削减军需储备，不能无限售卖。", 
		"officers": "你提出方向，历史人物组织实施。带‘宜’者擅长这个项目，可缩短工期；一人不能同时主持两个项目。亲自督办也不是免费加速，会占精力、影响健康。", 
		"farm": "税粮在九月入库，平时要靠现粮撑过去。科技中的水利试验会提高或降低当地收成；收益需要实际采用，并等到收获结算，不能预支秋收。", 
		"preview": "预览用当前政策推算下一月，不提交结果。粮仓、运粮、劳力和财政会同时结算；失败时先调整政策再推进。", 
		"report": "奏报记录实际月度变化。总粮包含途中粮；各地库存才是可在当地消耗的粮。详情可查看仓储、运输损失与粮钱变化。"}.get(current_panel, "札记解释知识，左上方引导给出当前行动。粮仓与城门是这一章的主要设施。")
	_show_notice("说明 · " + current_panel, content)

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if notice == null or notice.visible or new_game_dialog.visible or ending_layer != null or story_layer != null or technology_layer != null:
		return
	if event.keycode == KEY_ESCAPE:
		audio.effect("close")
		_stop_auto()
		current_panel = ""
		_refresh()
	elif event.keycode == KEY_SPACE and not simulation.state.finished:
		_advance()
	elif event.keycode == KEY_S and event.ctrl_pressed:
		_save()
	else:
		return
	get_viewport().set_input_as_handled()

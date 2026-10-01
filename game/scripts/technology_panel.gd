extends Control

var app: Control
var city := "chengdu"
var topic := "irrigation"
var leader := "feiyi"
var feedback := ""
var card: PanelContainer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.03,0.06,0.05,0.72)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	_refresh()

func _refresh() -> void:
	if card != null:
		remove_child(card)
		card.queue_free()
	card = PanelContainer.new()
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	card.offset_left = -510
	card.offset_right = 510
	card.offset_top = -285
	card.offset_bottom = 285
	card.add_theme_stylebox_override("panel", app._box(Color("252b25"),app.GOLD,20))
	add_child(card)
	var body := VBoxContainer.new()
	card.add_child(body)
	var header := HBoxContainer.new()
	body.add_child(header)
	var heading = app._text("现代记忆 · 试验工坊",26,app.GOLD)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	header.add_child(app._button("成都",func(): _city("chengdu")))
	header.add_child(app._button("汉中",func(): _city("hanzhong")))
	header.add_child(app._button("×",func(): app._close_technology()))
	body.add_child(app._text("提出办法 → 三题现场问答 → 委任试验 → 当地采用 → 扩大执行",16,app.MUTED))
	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(split)
	var topics := VBoxContainer.new()
	topics.custom_minimum_size.x = 180
	split.add_child(topics)
	var tech = app.simulation.technology
	for id in tech.definitions:
		var d: Dictionary = tech.definitions[id]
		var button = app._button(d.name,func(): topic = id; feedback = ""; _refresh())
		button.custom_minimum_size.y = 58
		if topic == id: button.add_theme_stylebox_override("normal",app._box(Color("665234"),app.GOLD))
		topics.add_child(button)
	topics.add_child(app._button("仓储与粮道",func(): app._close_technology(); app._open_place("warehouse")))
	topics.add_child(app._button("穿越记忆札记",func(): app._close_technology(); app._memory_notes()))
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(content)
	var d: Dictionary = tech.definitions[topic]
	var p: Dictionary = tech.project(app.simulation.state,city,topic)
	var title := HBoxContainer.new()
	content.add_child(title)
	title.add_child(app._icon(d.icon,32))
	title.add_child(app._text(("成都" if city == "chengdu" else "汉中") + " · " + d.name,24,app.GOLD))
	content.add_child(_wrapped(d.summary,17))
	var phase := "未试验" if p.stage == 0 else ("小试采用" if p.stage == 1 else "稳定执行")
	var plan_efficiency: float = tech.efficiency(p.answers) if p.answer_stage == p.stage and p.answers.size() == 3 and not p.active else p.efficiency
	content.add_child(app._text("%s   ·   方案效率 %+.0f%%" % [phase,plan_efficiency * 100],18,app.GOLD))
	var answered: int = p.answers.size() if p.answer_stage == p.stage else 0
	if not p.active and p.stage < 2 and answered < 3:
		_quiz(content,p,answered)
	else:
		_status(content,p,d)
	var stocks: Dictionary = app.simulation.state.technology.stocks[city]
	body.add_child(app._text("当地成品   铁料 %.1f  ·  盐 %.1f  ·  糖 %.1f      当地现粮 %.1f  ·  国库 %.1f" % [stocks.iron,stocks.salt,stocks.sugar,app.simulation.state.food[city],app.simulation.state.money],16,app.MUTED))

func _wrapped(value: String, font_size: int = 17) -> Label:
	var label = app._text(value,font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func _city(id: String) -> void:
	city = id
	feedback = ""
	app._visit_city(id)
	_refresh()

func _quiz(content: VBoxContainer, p: Dictionary, answered: int) -> void:
	var tech = app.simulation.technology
	var q: Dictionary = tech.questions(city,topic,int(p.stage))[answered]
	content.add_child(app._text("现场问答 %d / 3 · %s" % [answered+1,"试点方案" if p.stage == 0 else "推广方案"],16,app.MUTED))
	content.add_child(_wrapped(q.prompt,21))
	for index in q.options.size():
		var button = app._button(q.options[index].text,func():
			var error: String = tech.answer(app.simulation.state,city,topic,index)
			feedback = error if not error.is_empty() else q.explanation
			app.audio.effect("click")
			_refresh(),app.simulation.state.finished)
		button.name = "quiz_choice_%d" % index
		button.custom_minimum_size.y = 48
		content.add_child(button)
	if not feedback.is_empty(): content.add_child(_wrapped("记忆校验：" + feedback,15))
	var source: Dictionary = tech.bank.sources[q.source]
	var link = app._button("依据：" + source.title,func(): OS.shell_open(source.url))
	link.add_theme_font_size_override("font_size",13)
	link.tooltip_text = source.url
	content.add_child(link)
	content.add_child(_wrapped("改良：135%效率；沿用旧法：100%；错误方案：−50%。三题合计决定本轮方案，必须施工才能采用。",14))

func _status(content: VBoxContainer, p: Dictionary, d: Dictionary) -> void:
	if not feedback.is_empty(): content.add_child(_wrapped("记忆校验：" + feedback,15))
	if p.active:
		var progress := ProgressBar.new()
		progress.max_value = int(d.months) + int(p.stage)
		progress.value = p.progress
		content.add_child(progress)
		content.add_child(app._text("%s主持 · 进度 %d / %d月" % [app.simulation.officer_name(p.leader),p.progress,int(d.months)+int(p.stage)],19))
		content.add_child(app._button("暂停试验",func(): app.simulation.technology.toggle(app.simulation.state,city,topic); app._refresh(); _refresh()))
	elif p.stage < 2:
		var officers := HBoxContainer.new()
		content.add_child(officers)
		for person in app.simulation.rules.officers:
			var button = app._button(person.name + (" ✓" if leader == person.id else ""),func(): leader = person.id; _refresh())
			officers.add_child(button)
		var cost := 0.0 if p.funded else float(d.cost) * (1.0 if p.stage == 0 else 1.25)
		content.add_child(app._text("开工 %.1f钱 · %d月 · 当地劳力%.0f" % [cost,int(d.months)+int(p.stage),d.labor],18,app.GOLD))
		content.add_child(app._text("每月 %.1f钱 / %.1f粮；投入与工期不会因答题消失。" % [d.upkeep,d.food],15))
		content.add_child(app._button("委任科技试验" if p.stage == 0 else "委任扩大执行",func():
			var error: String = app.simulation.technology.start(app.simulation,city,topic,leader)
			feedback = error if not error.is_empty() else "已开工。返回城中推进月份，结果实际结算后采用。"
			app.audio.effect("error" if not error.is_empty() else "work")
			app._refresh()
			_refresh(),app.simulation.state.finished))
	content.add_child(_wrapped(d.explanation,16))
	if p.stage > 0 and not p.active:
		content.add_child(app._button("暂停当地采用" if p.enabled else "恢复当地采用",func(): app.simulation.technology.toggle(app.simulation.state,city,topic); app._refresh(); _refresh(),app.simulation.state.finished))
		content.add_child(app._text("采用占2劳力；每月%.1f钱、%.1f粮（含原料燃料）。" % [float(d.upkeep)+float(d.input),d.food],14))
		if p.efficiency < 0:
			content.add_child(app._button("撤回错误方案，重做试验",func(): feedback = app.simulation.technology.retry(app.simulation.state,city,topic); app._refresh(); _refresh(),app.simulation.state.finished))
	if topic != "irrigation":
		var trade := HBoxContainer.new()
		content.add_child(trade)
		trade.add_child(app._button("出售当地成品",func():
			feedback = app.simulation.technology.trade(app.simulation.state,city,d.resource)
			if feedback.is_empty(): feedback = "已交易，国库增加。"
			app.audio.effect("trade")
			app._refresh()
			_refresh(),app.simulation.state.finished))
		if topic == "mining": trade.add_child(app._button("3铁料 → 2军需",func(): feedback = app.simulation.technology.use_iron(app.simulation.state,city); app._refresh(); _refresh(),app.simulation.state.finished))
	if not p.reason.is_empty(): content.add_child(_wrapped(p.reason,14))

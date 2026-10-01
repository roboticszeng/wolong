extends RefCounted

const SCENARIO_PATH = "res://data/scenario.json"
const SAVE_VERSION = 1
const Technology = preload("res://scripts/technology.gd")
var technology = Technology.new()
var rules: Dictionary
var state: Dictionary
var rules_hash: String

func _init() -> void:
	var rules_text := FileAccess.get_file_as_string(SCENARIO_PATH)
	rules_hash = rules_text.sha256_text()
	rules = JSON.parse_string(rules_text)
	reset()

func reset() -> void:
	state = rules.initial.duplicate(true)
	state.merge({"year": int(rules.start_year), "month": int(rules.start_month), "turn": 0,
		"food": {}, "projects": {}, "convoys": [], "market_used": {},
		"transport": {"enabled": false, "amount": 8.0, "floor": 20.0, "target": 60.0},
		"history": ["223年五月 · 接过托付。先任命负责人，再决定投入；九月才有税粮入库。"],
		"last_report": {}, "finished": false, "ending": {}})
	for city in rules.cities:
		state.food[city] = float(rules.cities[city].food)
		state.market_used[city] = 0.0
	for id in rules.projects:
		state.projects[id] = {"stage": 0, "progress": 0, "active": false, "funded": false,
			"leader": "", "supervise": false, "adopted": 0, "reason": ""}
	technology.ensure(state)

func date_text() -> String:
	return "%d年 %02d月" % [state.year, state.month]

func total_food(s: Dictionary = state) -> float:
	var result: float = s.food.chengdu + s.food.hanzhong
	for convoy in s.convoys:
		result += float(convoy.food)
	return result

func log_message(message: String) -> void:
	state.history.append("%s · %s" % [date_text(), message])
	if state.history.size() > 120:
		state.history.pop_front()

func stage_data(id: String) -> Dictionary:
	var p: Dictionary = state.projects[id]
	if int(p.stage) >= rules.projects[id].stages.size():
		return {}
	return rules.projects[id].stages[int(p.stage)]

func officer_name(id: String) -> String:
	for officer in rules.officers:
		if officer.id == id:
			return officer.name
	return "未委任"

func is_specialist(id: String, project: String) -> bool:
	for officer in rules.officers:
		if officer.id == id:
			return officer.specialty == project
	return false

func duration(id: String) -> int:
	var stage: Dictionary = stage_data(id)
	if stage.is_empty():
		return 0
	return maxi(1, int(stage.months) - (1 if is_specialist(state.projects[id].leader, id) else 0))

func personal_used() -> int:
	var result := 0
	for p in state.projects.values():
		if p.active and p.supervise:
			result += 1
	return result

func labor_used(city: String) -> float:
	var result: float = rules.cities[city].reserved + technology.labor(state, city)
	for id in state.projects:
		if state.projects[id].active:
			var stage := stage_data(id)
			if stage.city == city:
				result += float(stage.labor)
	return result

func start_project(id: String, leader: String, supervise: bool) -> String:
	if state.finished:
		return "本轮筹备已结束，请开始新局。"
	if not state.projects.has(id) or officer_name(leader) == "未委任":
		return "请选择有效项目与负责人。"
	var p: Dictionary = state.projects[id]
	var stage := stage_data(id)
	if stage.is_empty():
		return "项目已完成。"
	if p.active:
		return "项目已在执行。"
	for other in state.projects.values():
		if other.active and other.leader == leader:
			return "这位负责人已有职责，请先暂停其原项目。"
	for other in state.technology.projects.values():
		if other.active and other.leader == leader:
			return "这位负责人正在主持科技试验。"
	if supervise and personal_used() >= 3:
		return "个人精力不足。"
	if labor_used(stage.city) + float(stage.labor) > float(rules.cities[stage.city].labor):
		return "当地劳力不足。"
	var cost: float = 0.0 if p.funded else float(stage.cost)
	if state.money < cost:
		return "财政不足：需要 %.1f 钱。" % cost
	state.money -= cost
	p.merge({"active": true, "funded": true, "leader": leader, "supervise": supervise, "reason": ""}, true)
	log_message("委任%s：%s / %s，投入 %.1f 钱%s。" % [officer_name(leader), rules.projects[id].name, stage.name, cost, "，丞相督办" if supervise else "，授权执行"])
	return ""

func pause_project(id: String) -> void:
	if state.projects[id].active:
		state.projects[id].active = false
		state.projects[id].reason = "主动暂停"
		log_message("暂停%s；已施工部分与已付投入保留，不重复收费。" % rules.projects[id].name)

func buy_food(city: String) -> String:
	if state.finished:
		return "本轮筹备已结束。"
	var amount := minf(12.0, float(rules.market_limit) - float(state.market_used[city]))
	if amount <= 0:
		return "当地本收获周期的采购额度已用尽，九月恢复。"
	var cost: float = amount * float(rules.market_price)
	if state.money < cost:
		return "钱不足，无法完成采购。"
	state.money -= cost
	state.food[city] += amount
	state.market_used[city] += amount
	log_message("%s就地采购 %.1f 粮，支付 %.1f 钱。" % [rules.cities[city].name, amount, cost])
	return ""

func sell_military() -> String:
	if state.finished:
		return "本轮筹备已结束。"
	if state.military < 20.0:
		return "军需须留至少10，无法再变卖。"
	state.military -= 10.0
	state.money += 5.0
	log_message("变卖10军需，筹得5钱；军备库存下降。")
	return ""

func set_transport(enabled: bool, amount: float) -> void:
	if state.finished:
		return
	state.transport.enabled = enabled
	state.transport.amount = clampf(amount, 0.0, 20.0)
	log_message("粮道政策：%s，每月最多 %.0f 粮；保留成都20，汉中目标60。" % ["开启" if enabled else "暂停", state.transport.amount])

func storage_rate(s: Dictionary, city: String) -> float:
	var adopted: int = int(s.projects.warehouse.adopted)
	if city == "chengdu":
		return 0.0015 if adopted >= 2 else (0.003 if adopted == 1 else 0.005)
	return 0.0015 if adopted >= 3 else 0.005

func route_values(s: Dictionary = state) -> Dictionary:
	var improved: bool = int(s.projects.road.adopted) > 0
	return {"capacity": rules.route.improved_capacity if improved else rules.route.capacity,
		"loss": rules.route.improved_loss if improved else rules.route.loss}

func _next_date(s: Dictionary) -> void:
	s.month = int(s.month) + 1
	if int(s.month) > 12:
		s.month = 1
		s.year = int(s.year) + 1
	s.turn = int(s.turn) + 1

# Preview and advancement share this resolver. Only advance_month commits its copy.
func preview_month() -> Dictionary:
	return _resolve_month()

func advance_month() -> Dictionary:
	var result := _resolve_month()
	if result.ok:
		state = result.state
	return result

func _resolve_month() -> Dictionary:
	if state.finished:
		return {"ok": false, "error": "本轮筹备已结束。", "important": true}
	var s := state.duplicate(true)
	_next_date(s)
	var notes: Array[String] = []
	var important := false
	var before := total_food()
	var old_rate: Dictionary = {"chengdu": storage_rate(state, "chengdu"), "hanzhong": storage_rate(state, "hanzhong")}
	var route := route_values(state)
	var incoming := 0.0
	var consumed := 0.0
	var spoilage := 0.0
	var transport_loss := 0.0
	var money_before: float = s.money
	var delivered: Array = []
	for convoy in s.convoys:
		if int(convoy.due) <= int(s.turn):
			s.food.hanzhong += float(convoy.food)
			delivered.append(convoy)
			notes.append("在途粮食送达汉中：%.1f。" % convoy.food)
	for convoy in delivered:
		s.convoys.erase(convoy)
	if int(s.month) == 9:
		for city in rules.cities:
			var harvest: float = float(rules.cities[city].harvest) * technology.harvest_factor(state, city)
			s.food[city] += harvest
			incoming += harvest
			s.market_used[city] = 0.0
		notes.append("九月税粮入库：合计%.1f，含当地水利增减产；采购额度恢复。" % incoming)
		important = true
	s.money += float(rules.monthly_income)
	if s.money < float(rules.monthly_upkeep):
		return {"ok": false, "error": "下月常规支出无法支付，请先筹钱或削减投入。", "important": true}
	s.money -= float(rules.monthly_upkeep)
	# Mandatory local consumption is reserved before optional work/transport.
	for city in rules.cities:
		var need: float = rules.cities[city].consumption
		if s.food[city] < need:
			return {"ok": false, "error": "%s下月缺粮 %.1f；需要就地采购或等待此前发出的运输，无法使用异地库存。" % [rules.cities[city].name, need - s.food[city]], "important": true}
		s.food[city] -= need
		consumed += need
	var labor := {"chengdu": float(rules.cities.chengdu.reserved), "hanzhong": float(rules.cities.hanzhong.reserved)}
	var supervision := 0
	for id in rules.projects:
		var p: Dictionary = s.projects[id]
		if not p.active:
			continue
		var stage: Dictionary = rules.projects[id].stages[int(p.stage)]
		var city: String = stage.city
		if s.money < float(stage.upkeep) or s.food[city] < float(stage.food):
			p.active = false
			p.reason = "月度预算或当地供粮不足"
			notes.append("%s受阻并暂停：%s。进度保留。" % [rules.projects[id].name, p.reason])
			important = true
			continue
		s.money -= float(stage.upkeep)
		s.food[city] -= float(stage.food)
		consumed += float(stage.food)
		labor[city] += float(stage.labor)
		if p.supervise:
			supervision += 1
		# Personal supervision adds evidence/coordination, never bypasses costs.
		p.progress = int(p.progress) + 1
		if p.supervise and int(p.progress) == 1 and duration(id) > 2:
			p.progress += 1
		if int(p.progress) >= duration(id):
			p.stage = int(p.stage) + 1
			p.adopted = int(p.stage)
			p.progress = 0
			p.active = false
			p.funded = false
			p.reason = ""
			notes.append("%s完成：%s；成果下月生效，负责人和精力释放。" % [rules.projects[id].name, stage.name])
			important = true
	var tech_result: Dictionary = technology.settle(s, notes, labor, rules.cities)
	consumed += float(tech_result.consumed)
	important = important or bool(tech_result.important)
	if s.transport.enabled:
		var in_transit := 0.0
		for convoy in s.convoys:
			in_transit += float(convoy.food)
		var amount := minf(float(s.transport.amount), float(route.capacity))
		amount = minf(amount, maxf(0.0, s.food.chengdu - float(s.transport.floor)))
		amount = minf(amount, maxf(0.0, float(s.transport.target) - s.food.hanzhong - in_transit) / (1.0 - float(route.loss)))
		amount = minf(amount, maxf(0.0, float(rules.cities.chengdu.labor) - labor.chengdu) / float(rules.route.labor_per_food))
		amount = minf(amount, s.money / float(rules.route.money_per_food))
		if amount > 0.01:
			transport_loss = amount * float(route.loss)
			s.food.chengdu -= amount
			s.money -= amount * float(rules.route.money_per_food)
			labor.chengdu += amount * float(rules.route.labor_per_food)
			s.convoys.append({"food": amount - transport_loss, "due": int(s.turn) + 1})
			notes.append("成都发出 %.1f 粮，运输损耗 %.1f，%.1f 粮下月到汉中。" % [amount, transport_loss, amount - transport_loss])
		elif float(s.transport.target) > s.food.hanzhong + in_transit + 0.01:
			notes.append("粮道未发运：成都保留库存、劳力或预算限制。")
			important = true
	for city in rules.cities:
		var loss: float = s.food[city] * float(old_rate[city])
		s.food[city] -= loss
		spoilage += loss
		if s.food[city] < 12.0:
			notes.append("%s库存低于12，请检视供给。" % rules.cities[city].name)
			important = true
	s.military += 0.5
	s.health = clampf(float(s.health) + (0.5 if supervision == 0 else -0.4 * supervision), 0.0, 100.0)
	if float(s.health) < 60.0:
		notes.append("健康低于60，请减少亲自督办、改为授权。")
		important = true
	var after := total_food(s)
	var delta := incoming - consumed - spoilage - transport_loss
	assert(absf((after - before) - delta) < 0.001, "Grain conservation failed")
	s.last_report = {"date": "%d年 %02d月" % [s.year, s.month], "before": before, "after": after,
		"harvest": incoming, "consumed": consumed, "spoilage": spoilage, "transport_loss": transport_loss,
		"money_delta": float(s.money) - money_before, "labor": labor, "notes": notes}
	for note in notes:
		s.history.append("%s · %s" % [s.last_report.date, note])
	while s.history.size() > 120:
		s.history.pop_front()
	if int(s.year) > int(rules.review_year) or (int(s.year) == int(rules.review_year) and int(s.month) >= int(rules.review_month)):
		s.finished = true
		s.ending = _assessment(s)
		notes.append("后方筹备检视完成。可查看复盘，或开始新局尝试另一种分配。")
		important = true
	return {"ok": true, "state": s, "important": important, "notes": notes}

func _assessment(s: Dictionary) -> Dictionary:
	var warehouse: bool = int(s.projects.warehouse.adopted) >= 3
	var road: bool = int(s.projects.road.adopted) >= 1
	var supply: bool = float(s.food.hanzhong) >= float(rules.goal_food)
	var finance: bool = float(s.money) >= 10.0
	return {"title": "后方初定" if warehouse and road and supply and finance else "筹备尚待完善",
		"warehouse": warehouse, "road": road, "supply": supply, "finance": finance,
		"explanation": "仓储、粮道、汉中储备与财政分别评价。这个切片检验后方经营；北伐与南中将在后续版本接入。"}

func assessment() -> Dictionary:
	return _assessment(state)

func validate_snapshot(candidate: Variant) -> String:
	if candidate is Dictionary and candidate.has("chronicle"):
		var c: Variant = candidate.chronicle
		if not c is Dictionary or not c.get("intro") is float and not c.get("intro") is int:
			return "剧情记录损坏。"
		if c.intro < 0 or c.intro > 3 or c.intro != floor(c.intro) or not c.get("skipped") is bool or not c.get("observed") is bool or not c.get("events") is Array:
			return "剧情记录损坏。"
		for event in c.events:
			if not event is String or event not in ["trial", "routine", "adoption", "road", "arrival"]:
				return "剧情记录损坏。"
		if c.has("arrival_ready") and not c.arrival_ready is bool:
			return "剧情记录损坏。"
	if not candidate is Dictionary:
		return "存档状态格式错误。"
	var tech_error: String = technology.validate(candidate)
	if not tech_error.is_empty(): return tech_error
	for key in ["year", "month", "turn", "money", "military", "health", "trust", "food", "projects", "convoys", "market_used", "transport", "history", "last_report", "finished", "ending"]:
		if not candidate.has(key):
			return "存档缺少字段：%s。" % key
	for key in ["money", "military", "health", "trust", "turn", "year", "month"]:
		if not _number(candidate[key]) or candidate[key] < 0:
			return "存档数值无效：%s。" % key
	if candidate.month < 1 or candidate.month > 12 or candidate.turn != floor(candidate.turn):
		return "存档日期无效。"
	if candidate.year != floor(candidate.year) or candidate.month != floor(candidate.month):
		return "存档日期必须为整数。"
	var absolute_month: int = int(rules.start_year) * 12 + int(rules.start_month) - 1 + int(candidate.turn)
	if int(candidate.year) != absolute_month / 12 or int(candidate.month) != absolute_month % 12 + 1:
		return "存档日期与月度进度不一致。"
	for key in ["food", "projects", "market_used", "transport", "last_report", "ending"]:
		if not candidate[key] is Dictionary:
			return "存档字段类型无效：%s。" % key
	if not candidate.convoys is Array or not candidate.history is Array or not candidate.finished is bool:
		return "存档列表格式无效。"
	if candidate.food.size() != rules.cities.size() or candidate.market_used.size() != rules.cities.size() or candidate.projects.size() != rules.projects.size():
		return "存档区域或项目与当前版本不同。"
	for city in rules.cities:
		if not candidate.food.has(city) or not _number(candidate.food[city]) or candidate.food[city] < 0:
			return "地区粮食无效。"
		if not candidate.market_used.has(city) or not _number(candidate.market_used[city]) or candidate.market_used[city] < 0 or candidate.market_used[city] > float(rules.market_limit):
			return "采购记录无效。"
	var leaders: Array = []
	for id in rules.projects:
		if not candidate.projects.has(id) or not candidate.projects[id] is Dictionary:
			return "项目记录缺失。"
		var p: Dictionary = candidate.projects[id]
		for key in ["stage", "progress", "active", "funded", "leader", "supervise", "adopted", "reason"]:
			if not p.has(key):
				return "项目字段缺失。"
		for key in ["stage", "progress", "adopted"]:
			if not _number(p[key]) or p[key] < 0 or p[key] != floor(p[key]):
				return "项目进度无效。"
		for key in ["active", "funded", "supervise"]:
			if not p[key] is bool:
				return "项目状态无效。"
		if not p.leader is String or not p.reason is String:
			return "负责人记录无效。"
		if p.stage > rules.projects[id].stages.size() or p.adopted != p.stage:
			return "项目阶段无效。"
		if p.progress > 0 and not p.funded:
			return "未投入项目不能有施工进度。"
		if p.stage == rules.projects[id].stages.size() and (p.progress != 0 or p.funded):
			return "已完成项目状态无效。"
		if p.active and (p.stage == rules.projects[id].stages.size() or not p.funded or officer_name(p.leader) == "未委任" or leaders.has(p.leader)):
			return "项目委任冲突。"
		if p.active:
			leaders.append(p.leader)
		if p.stage < rules.projects[id].stages.size() and p.progress >= int(rules.projects[id].stages[int(p.stage)].months):
			return "项目进度超出阶段。"
	if candidate.has("technology"):
		for p in candidate.technology.projects.values():
			if p.active:
				if officer_name(p.leader) == "未委任" or p.leader in leaders: return "科技与常规项目负责人冲突。"
				leaders.append(p.leader)
	for convoy in candidate.convoys:
		if not convoy is Dictionary or not convoy.has("food") or not convoy.has("due"):
			return "在途运输格式无效。"
		if not _number(convoy.food) or convoy.food <= 0 or not _number(convoy.due) or convoy.due != int(candidate.turn) + 1:
			return "在途运输记录无效。"
	for key in ["enabled", "amount", "floor", "target"]:
		if not candidate.transport.has(key):
			return "运输政策缺失。"
	if not candidate.transport.enabled is bool:
		return "运输政策状态无效。"
	for key in ["amount", "floor", "target"]:
		if not _number(candidate.transport[key]) or candidate.transport[key] < 0:
			return "运输政策数值无效。"
	if candidate.transport.amount > 20.0 or candidate.health > 100 or candidate.trust > 100:
		return "存档数值超出范围。"
	for entry in candidate.history:
		if not entry is String:
			return "日志格式无效。"
	if not candidate.last_report.is_empty():
		var report: Dictionary = candidate.last_report
		for key in ["before", "after", "harvest", "consumed", "spoilage", "transport_loss", "money_delta"]:
			if not report.has(key) or not _number(report[key]):
				return "月度报告数值无效。"
		if not report.get("date") is String or not report.get("notes") is Array or not report.get("labor") is Dictionary:
			return "月度报告格式无效。"
		for note in report.notes:
			if not note is String:
				return "月度报告条目无效。"
		for city in rules.cities:
			if not report.labor.has(city) or not _number(report.labor[city]) or report.labor[city] < 0 or report.labor[city] > rules.cities[city].labor:
				return "报告劳力记录无效。"
	return ""

func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

func save_game(path: String = "user://campaign.json") -> String:
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return "无法写入存档：%s。" % error_string(FileAccess.get_open_error())
	file.store_string(JSON.stringify({"version": SAVE_VERSION, "rules_hash": rules_hash, "state": state}, "\t", true, true))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		return "存档写入失败。"
	if FileAccess.file_exists(path):
		var backup_error := DirAccess.copy_absolute(path, path + ".bak")
		if backup_error != OK:
			return "无法备份旧存档，保留原文件。"
	var result := DirAccess.rename_absolute(path + ".tmp", path)
	return "" if result == OK else "存档替换失败：%s。" % error_string(result)

func load_game(path: String = "user://campaign.json") -> String:
	if not FileAccess.file_exists(path):
		return "尚无存档。"
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK:
		return "存档损坏，当前游戏未改变。"
	var data: Variant = parser.data
	if not data is Dictionary or data.get("version") != SAVE_VERSION or not data.has("state"):
		return "存档版本不兼容。"
	if data.get("rules_hash") != rules_hash:
		return "参数表与此存档不同，请恢复原参数或开始新局。"
	var error := validate_snapshot(data.state)
	if not error.is_empty():
		return error
	state = data.state.duplicate(true)
	technology.ensure(state)
	# JSON stores all numbers as floats; restore integer counters explicitly.
	for key in ["year", "month", "turn"]:
		state[key] = int(state[key])
	for p in state.projects.values():
		for key in ["stage", "progress", "adopted"]:
			p[key] = int(p[key])
	for convoy in state.convoys:
		convoy.due = int(convoy.due)
	for p in state.technology.projects.values():
		for key in ["stage", "progress", "answer_stage", "committed_stage"]: p[key] = int(p[key])
		for a in p.answers + p.committed: a.choice = int(a.choice)
	return ""

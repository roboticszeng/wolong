extends RefCounted

var definitions: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/knowledge/projects.json"))
var bank: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/knowledge/questions.json"))
const CITIES = ["chengdu", "hanzhong"]
const RESOURCE_NAMES = {"iron": "铁料", "salt": "盐", "sugar": "糖"}

func ensure(s: Dictionary) -> void:
	if s.has("technology"): return
	s.technology = {"projects": {}, "stocks": {}}
	for city in CITIES:
		s.technology.stocks[city] = {"iron": 0.0, "salt": 0.0, "sugar": 0.0}
		for id in definitions:
			s.technology.projects[city + ":" + id] = {"stage": 0, "progress": 0, "active": false, "enabled": false, "leader": "", "funded": false, "efficiency": 1.0, "answers": [], "answer_stage": 0, "committed": [], "committed_stage": 0, "reason": ""}

func project(s: Dictionary, city: String, id: String) -> Dictionary:
	ensure(s)
	return s.technology.projects[city + ":" + id]

func questions(city: String, id: String, stage: int) -> Array:
	var pool: Array = bank.questions.filter(func(q): return q.topic == id)
	var result: Array = []
	var offset := (stage + (1 if city == "hanzhong" else 0)) % pool.size()
	for index in range(3): result.append(pool[(offset + index) % pool.size()])
	return result

func answer(s: Dictionary, city: String, id: String, option: int) -> String:
	if not CITIES.has(city) or not definitions.has(id): return "地区或项目无效。"
	if s.finished: return "本轮筹备已结束。"
	var p := project(s, city, id)
	if p.active or p.stage >= 2: return "当前无法更改方案。"
	if int(p.answer_stage) != int(p.stage):
		p.answers = []
		p.answer_stage = int(p.stage)
	if p.answers.size() >= 3: return "方案已定，先完成本轮试验；不能免费反复刷答案。"
	var q: Dictionary = questions(city, id, int(p.stage))[p.answers.size()]
	if option < 0 or option >= q.options.size(): return "答案选项无效。"
	p.answers.append({"id": q.id, "choice": option})
	return ""

func efficiency(answers: Array) -> float:
	var total := 0
	for a in answers:
		for q in bank.questions:
			if q.id == a.id: total += int(q.options[int(a.choice)].quality)
	return 1.35 if total >= 5 else (1.0 if total >= 3 else -0.5)

func labor(s: Dictionary, city: String) -> float:
	ensure(s)
	var result := 0.0
	for id in definitions:
		var p := project(s, city, id)
		if p.active: result += float(definitions[id].labor)
		elif p.enabled and p.stage > 0: result += 2.0
	return result

func start(sim: RefCounted, city: String, id: String, leader: String) -> String:
	var s: Dictionary = sim.state
	if not CITIES.has(city) or not definitions.has(id): return "地区或项目无效。"
	if s.finished: return "本轮筹备已结束。"
	var p := project(s, city, id)
	if p.active or p.stage >= 2: return "项目已开工或已推广。"
	if int(p.answer_stage) != int(p.stage) or p.answers.size() != 3: return "先完成三道现场知识问答，确定试验方案。"
	if sim.officer_name(leader) == "未委任": return "请选择负责人。"
	for other in s.projects.values():
		if other.active and other.leader == leader: return "负责人已有其他职责。"
	for other in s.technology.projects.values():
		if other.active and other.leader == leader: return "负责人正在主持另一项科技试验。"
	var d: Dictionary = definitions[id]
	var used: float = sim.labor_used(city) - (2.0 if p.enabled else 0.0)
	if used + float(d.labor) > float(sim.rules.cities[city].labor): return "当地劳力不足；先暂停其他项目或作坊。"
	var cost := 0.0 if p.funded else float(d.cost) * (1.0 if p.stage == 0 else 1.25)
	if s.money < cost: return "财政不足，需要 %.1f 钱。" % cost
	s.money -= cost
	p.efficiency = efficiency(p.answers)
	p.committed = p.answers.duplicate(true)
	p.committed_stage = int(p.stage)
	p.merge({"active": true, "enabled": false, "funded": true, "leader": leader, "reason": ""}, true)
	sim.log_message("%s委任%s开展%s，方案效率%+.0f%%，投入%.1f钱。" % [sim.rules.cities[city].name, sim.officer_name(leader), d.name, p.efficiency * 100, cost])
	return ""

func harvest_factor(s: Dictionary, city: String) -> float:
	var p := project(s, city, "irrigation")
	return 1.0 + float(definitions.irrigation.harvest_bonus) * float(p.efficiency) * (0.5 if p.stage == 1 else 1.0) if p.enabled and not p.active and p.stage > 0 else 1.0

func settle(s: Dictionary, notes: Array[String], labor_used: Dictionary, cities: Dictionary) -> Dictionary:
	ensure(s)
	var consumed := 0.0
	var important := false
	for city in CITIES:
		for id in definitions:
			var p := project(s, city, id)
			var d: Dictionary = definitions[id]
			if not p.active and not p.enabled: continue
			var work := float(d.labor) if p.active else 2.0
			var cost := float(d.upkeep) + (0.0 if p.active else float(d.input))
			if s.money < cost or s.food[city] < float(d.food) or labor_used[city] + work > float(cities[city].labor):
				p.active = false
				p.enabled = false
				p.reason = "预算、当地供粮或劳力不足"
				notes.append("%s%s暂停：%s。" % ["成都" if city == "chengdu" else "汉中", d.name, p.reason])
				important = true
				continue
			s.money -= cost
			s.food[city] -= float(d.food)
			consumed += float(d.food)
			labor_used[city] += work
			if p.active:
				p.progress += 1
				if p.progress >= int(d.months) + int(p.stage):
					p.stage += 1
					p.progress = 0
					p.active = false
					p.funded = false
					p.enabled = true
					notes.append("%s%s%s完成：方案效率%+.0f%%，下月采用；错误方案可重做试验。" % ["成都" if city == "chengdu" else "汉中", d.name, "试点" if p.stage == 1 else "推广", p.efficiency * 100])
					important = true
				continue
			if id == "irrigation": continue
			var output := float(d.yield) * float(p.efficiency) * (0.5 if p.stage == 1 else 1.0)
			if output > 0:
				s.technology.stocks[city][d.resource] += output
				notes.append("%s%s产出%s%.2f，原料燃料已计入开支。" % ["成都" if city == "chengdu" else "汉中", d.name, RESOURCE_NAMES[d.resource], output])
			else:
				var waste := minf(s.money, absf(output))
				s.money -= waste
				notes.append("%s%s错误工艺：废品未入库，额外损失%.2f钱。" % ["成都" if city == "chengdu" else "汉中", d.name, waste])
	return {"consumed": consumed, "important": important}

func toggle(s: Dictionary, city: String, id: String) -> void:
	if s.finished: return
	var p := project(s, city, id)
	if p.active:
		p.active = false
		p.reason = "主动暂停，试验进度保留"
	elif p.stage > 0: p.enabled = not p.enabled

func retry(s: Dictionary, city: String, id: String) -> String:
	var p := project(s, city, id)
	if s.finished or p.active or p.stage <= 0: return "当前不能重做试验。"
	p.merge({"stage": 0, "progress": 0, "enabled": false, "funded": false, "answers": [], "answer_stage": 0, "committed": [], "committed_stage": 0, "efficiency": 1.0, "reason": "已撤回原方案；重新试验仍需投入与工期。"}, true)
	return ""

func trade(s: Dictionary, city: String, resource: String) -> String:
	if s.finished: return "本轮筹备已结束。"
	if not CITIES.has(city) or not RESOURCE_NAMES.has(resource): return "商品无效。"
	ensure(s)
	var amount := minf(3.0, float(s.technology.stocks[city][resource]))
	if amount <= 0: return "当地没有可交易的成品。"
	s.technology.stocks[city][resource] -= amount
	var id := "mining" if resource == "iron" else resource
	s.money += amount * float(definitions[id].sale_price)
	return ""

func use_iron(s: Dictionary, city: String) -> String:
	ensure(s)
	if s.finished or s.technology.stocks[city].iron < 3.0: return "至少需要当地3铁料，且本轮尚未结束。"
	s.technology.stocks[city].iron -= 3.0
	s.military += 2.0
	return ""

func validate(s: Dictionary) -> String:
	if not s.has("technology"): return ""
	var t: Variant = s.technology
	if not t is Dictionary or not t.get("projects") is Dictionary or not t.get("stocks") is Dictionary: return "科技存档格式无效。"
	if t.projects.size() != 8 or t.stocks.size() != 2: return "科技地区记录无效。"
	var owners: Array = []
	for city in CITIES:
		if not t.stocks.get(city) is Dictionary or t.stocks[city].size() != 3: return "科技库存缺失。"
		for resource in RESOURCE_NAMES:
			var v: Variant = t.stocks[city].get(resource)
			if not (v is float or v is int) or not is_finite(float(v)) or v < 0: return "科技库存数值无效。"
		for id in definitions:
			var p: Variant = t.projects.get(city + ":" + id)
			if not p is Dictionary: return "科技项目缺失。"
			for key in ["stage", "progress", "answer_stage", "efficiency", "committed_stage"]:
				var v: Variant = p.get(key)
				if not (v is float or v is int) or not is_finite(float(v)): return "科技项目数值无效。"
			if p.stage < 0 or p.stage > 2 or p.stage != floor(p.stage) or p.progress < 0 or p.progress != floor(p.progress) or p.progress >= int(definitions[id].months) + int(p.stage): return "科技进度无效。"
			for key in ["active", "enabled", "funded"]:
				if not p.get(key) is bool: return "科技项目状态无效。"
			if not p.get("leader") is String or not p.get("reason") is String or not p.get("answers") is Array or p.answers.size() > 3: return "科技问答记录无效。"
			if p.answer_stage < 0 or p.answer_stage > p.stage or p.answer_stage != floor(p.answer_stage): return "科技问答阶段无效。"
			var qs := questions(city, id, int(p.answer_stage))
			for index in p.answers.size():
				var a: Variant = p.answers[index]
				if not a is Dictionary or a.get("id") != qs[index].id or not a.get("choice") is float and not a.get("choice") is int: return "科技答案无效。"
				if a.choice < 0 or a.choice >= 3 or a.choice != floor(a.choice): return "科技答案选项无效。"
			if not p.get("committed") is Array or p.committed.size() not in [0,3] or p.committed_stage < 0 or p.committed_stage > p.stage or p.committed_stage != floor(p.committed_stage): return "科技采用答案无效。"
			var committed_questions := questions(city,id,int(p.committed_stage))
			for index in p.committed.size():
				var a: Variant = p.committed[index]
				if not a is Dictionary or a.get("id") != committed_questions[index].id or not (a.get("choice") is float or a.get("choice") is int): return "科技采用记录无效。"
				if a.choice < 0 or a.choice >= 3 or a.choice != floor(a.choice): return "科技采用选项无效。"
			if p.efficiency != (efficiency(p.committed) if p.committed.size() == 3 else 1.0): return "科技效率与采用答案不一致。"
			if p.active and (p.stage >= 2 or not p.funded or p.answers.size() != 3 or p.answer_stage != p.stage or p.enabled or p.leader in owners): return "科技委任状态无效。"
			if (p.stage > 0 or p.funded) and p.committed.size() != 3: return "已试验项目缺少采用方案。"
			if p.enabled and (p.stage <= 0 or p.active): return "科技采用状态无效。"
			if p.progress > 0 and not p.funded: return "科技试验缺少投入。"
			if p.active: owners.append(p.leader)
	return ""

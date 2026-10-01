extends SceneTree

const Simulation = preload("res://scripts/simulation.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_test_calendar_and_transport()
	_test_projects()
	_test_shortages()
	_test_save()
	_test_playable_routes()
	_test_technology()
	if failures.is_empty():
		print("PASS: %d simulation checks" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("FAIL: %d of %d checks" % [failures.size(), checks])
		quit(1)

func tech_answers(sim: RefCounted, city: String, topic: String, quality: int) -> void:
	var p: Dictionary = sim.technology.project(sim.state,city,topic)
	for q in sim.technology.questions(city,topic,int(p.stage)):
		for index in q.options.size():
			if q.options[index].quality == quality:
				expect(sim.technology.answer(sim.state,city,topic,index).is_empty(), "Technology answer is accepted once")
				break

func _test_technology() -> void:
	var outcomes: Array = []
	for quality in [2,1,0]:
		var sim = Simulation.new()
		tech_answers(sim,"chengdu","salt",quality)
		var p: Dictionary = sim.technology.project(sim.state,"chengdu","salt")
		expect(sim.technology.answer(sim.state,"chengdu","salt",0) != "", "Completed quiz cannot be rerolled for free")
		expect(sim.technology.start(sim,"chengdu","salt","feiyi").is_empty(), "Quiz plans start a real funded local project")
		expect(near(p.efficiency,[1.35,1.0,-0.5][outcomes.size()]), "Best, ordinary, wrong plans have the specified multipliers")
		var before := JSON.stringify(sim.state)
		var preview: Dictionary = sim.preview_month()
		expect(JSON.stringify(sim.state) == before and preview.ok, "Technology preview is read-only")
		expect(sim.advance_month().ok and sim.advance_month().ok, "Technology trial pays monthly inputs and completes")
		expect(sim.state.technology.stocks.chengdu.salt == 0 and not sim.state.technology.projects["chengdu:salt"].active, "Trial completion does not grant instant production")
		expect(sim.advance_month().ok, "Adopted plan produces on the following month")
		outcomes.append(sim)
		expect(sim.state.technology.stocks.hanzhong.salt == 0, "Chengdu production does not become Hanzhong stock")
		expect(sim.validate_snapshot(sim.state).is_empty(), "Technology state satisfies save validation")
	expect(outcomes[0].state.technology.stocks.chengdu.salt > outcomes[1].state.technology.stocks.chengdu.salt, "Knowledge improvement raises actual salt yield")
	expect(outcomes[2].state.technology.stocks.chengdu.salt == 0 and outcomes[2].state.money < outcomes[1].state.money, "Wrong plan wastes money and yields no usable salt")
	var good = outcomes[0]
	var prior_money: float = good.state.money
	expect(good.technology.trade(good.state,"chengdu","salt").is_empty() and good.state.money > prior_money, "Local salt can be sold for actual money")
	var p: Dictionary = good.technology.project(good.state,"chengdu","salt")
	var adopted_efficiency: float = p.efficiency
	var q: Dictionary = good.technology.questions("chengdu","salt",1)[0]
	expect(good.technology.answer(good.state,"chengdu","salt",0).is_empty() and p.efficiency == adopted_efficiency, "Drafting a promotion answer does not alter the already adopted plan")
	expect(good.save_game("user://technology-test.json").is_empty(), "Partial promotion quiz saves successfully")
	var restored = Simulation.new()
	var restore_error: String = restored.load_game("user://technology-test.json")
	expect(restore_error.is_empty() and JSON.stringify(restored.state.technology,"",true,true) == JSON.stringify(good.state.technology,"",true,true), "Partial quiz and local outputs survive loading: " + restore_error)
	var invalid: Dictionary = good.state.duplicate(true)
	invalid.technology.projects["chengdu:salt"].efficiency = 99
	expect(not good.validate_snapshot(invalid).is_empty(), "Tampered efficiency is rejected")
	var bad = outcomes[2]
	var bad_money: float = bad.state.money
	expect(bad.technology.retry(bad.state,"chengdu","salt").is_empty() and bad.state.money == bad_money, "Retry removes harmful adoption without refunding sunk costs")
	tech_answers(bad,"chengdu","salt",2)
	expect(bad.technology.start(bad,"chengdu","salt","feiyi").is_empty() and bad.state.money < bad_money, "Repairing wrong knowledge requires another funded trial")
	var harvests: Array = []
	for quality in [2,1,0]:
		var sim = Simulation.new()
		tech_answers(sim,"chengdu","irrigation",quality)
		sim.technology.start(sim,"chengdu","irrigation","feiyi")
		for index in range(4): sim.advance_month()
		harvests.append(sim.state.last_report.harvest)
	expect(harvests[0] > harvests[1] and harvests[1] > 100 and harvests[2] < 100, "Water knowledge changes the actual September harvest, including negative yield")
	var mining = Simulation.new()
	tech_answers(mining,"chengdu","mining",2)
	mining.technology.start(mining,"chengdu","mining","feiyi")
	expect(not mining.start_project("warehouse","feiyi",false).is_empty(), "A technology leader cannot also lead storage")
	for index in range(5): mining.advance_month()
	var military_before: float = mining.state.military
	expect(mining.technology.use_iron(mining.state,"chengdu").is_empty() and near(mining.state.military,military_before+2), "Iron production can actually supply military stores")
	var labor = Simulation.new()
	labor.start_project("road","liyan",false)
	tech_answers(labor,"hanzhong","salt",2)
	expect(not labor.technology.start(labor,"hanzhong","salt","feiyi").is_empty(), "Road work competes with salt trial for real Hanzhong labor")
	var sugar = Simulation.new()
	tech_answers(sugar,"chengdu","sugar",2)
	sugar.technology.start(sugar,"chengdu","sugar","feiyi")
	for index in range(3): sugar.advance_month()
	expect(sugar.state.technology.stocks.chengdu.sugar > 0, "Sugar is a real local output distinct from food")

func expect(condition: bool, explanation: String) -> void:
	checks += 1
	if not condition:
		failures.append(explanation)

func near(a: float, b: float) -> bool:
	return absf(a - b) < 0.0001

func _test_calendar_and_transport() -> void:
	var sim = Simulation.new()
	sim.set_transport(true, 8)
	var before := JSON.stringify(sim.state)
	var preview: Dictionary = sim.preview_month()
	expect(JSON.stringify(sim.state) == before, "Preview must not mutate state")
	var result: Dictionary = sim.advance_month()
	expect(result.ok and sim.state.month == 6 and sim.state.year == 223, "Month must advance exactly once")
	expect(JSON.stringify(sim.state) == JSON.stringify(preview.state), "Preview and actual settlement must match")
	expect(sim.state.convoys.size() == 1 and near(sim.state.convoys[0].food, 7.2), "Route loss must be recorded on dispatched cargo")
	expect(near(sim.state.food.hanzhong, 28.0 * 0.995), "New convoy must not arrive in its departure month")
	var report: Dictionary = sim.state.last_report
	expect(near(report.after - report.before, report.harvest - report.consumed - report.spoilage - report.transport_loss), "Local plus in-transit grain must be conserved")
	sim.set_transport(false, 8)
	result = sim.advance_month()
	expect(result.ok and near(sim.state.food.hanzhong, (28.0 * 0.995 + 7.2 - 2.0) * 0.995), "Cargo must arrive next month even when future transport is paused")
	expect(sim.state.convoys.is_empty(), "Arrived cargo must leave transit ledger")
	sim.advance_month()
	expect(sim.state.last_report.harvest == 0, "August must not spend September harvest")
	sim.advance_month()
	expect(sim.state.month == 9 and sim.state.last_report.harvest == 100, "Harvest occurs in September")

func _test_projects() -> void:
	var sim = Simulation.new()
	expect(sim.start_project("warehouse", "jiangwan", false).is_empty(), "Valid warehouse appointment")
	expect(not sim.start_project("road", "jiangwan", false).is_empty(), "One officer cannot lead two active projects")
	expect(sim.start_project("road", "liyan", false).is_empty(), "Separate specialist can lead road")
	expect(sim.personal_used() == 0, "Delegation must not consume personal energy")
	expect(sim.labor_used("chengdu") == 50 and sim.labor_used("hanzhong") == 28, "Labor capacity must include baseline and active local tasks")
	var initial_money: float = sim.state.money
	sim.pause_project("warehouse")
	expect(sim.labor_used("chengdu") == 42, "Pause releases labor")
	expect(sim.start_project("warehouse", "jiangwan", true).is_empty() and sim.state.money == initial_money, "Resume must not repeat funded stage entry cost")
	expect(sim.personal_used() == 1, "Personal supervision occupies one slot")
	var result: Dictionary = sim.advance_month()
	expect(result.ok and result.important, "Stage completion pauses auto advance")
	expect(sim.state.projects.warehouse.stage == 1 and sim.personal_used() == 0, "Specialist completion advances stage and frees duty")
	expect(near(sim.state.last_report.spoilage, (90.0 - 4.0 - 0.5) * 0.005 + (30.0 - 2.0 - 0.5) * 0.005), "New warehouse benefit must not apply in completion month")
	expect(sim.storage_rate(sim.state, "chengdu") == 0.003 and sim.storage_rate(sim.state, "hanzhong") == 0.005, "Trial applies locally only")
	sim.start_project("warehouse", "jiangwan", false)
	sim.advance_month()
	sim.advance_month()
	expect(sim.state.projects.warehouse.stage == 2 and sim.state.projects.road.stage == 1, "Independent tasks finish at their own pace")
	expect(sim.storage_rate(sim.state, "chengdu") == 0.0015, "Stable execution replaces trial rate instead of stacking")
	expect(sim.route_values().capacity == 20, "Completed road unlocks larger capacity")
	sim.start_project("warehouse", "jiangwan", false)
	sim.advance_month()
	sim.advance_month()
	expect(sim.storage_rate(sim.state, "hanzhong") == 0.0015, "Propagation reaches Hanzhong after local work")

func _test_shortages() -> void:
	var sim = Simulation.new()
	sim.state.food.hanzhong = 0
	var before := JSON.stringify(sim.state)
	var result: Dictionary = sim.advance_month()
	expect(not result.ok and JSON.stringify(sim.state) == before, "Local shortage must reject advancement without consuming other inputs")
	expect(sim.buy_food("hanzhong").is_empty(), "Local market can repair shortage")
	expect(sim.advance_month().ok, "Repaired plan can advance")
	sim.buy_food("hanzhong")
	expect(not sim.buy_food("hanzhong").is_empty(), "Market quota prevents infinite purchases")
	sim = Simulation.new()
	sim.state.money = 0
	expect(not sim.start_project("warehouse", "jiangwan", false).is_empty(), "Unfunded project must not start")
	sim = Simulation.new()
	sim.start_project("warehouse", "jiangwan", false)
	sim.start_project("road", "liyan", false)
	sim.state.money = 0
	result = sim.advance_month()
	expect(result.ok and not sim.state.projects.road.active, "Optional project pauses when budget cannot cover its upkeep")
	expect(sim.state.money >= 0 and sim.state.projects.road.progress == 0, "Unpaid task must not progress or produce negative cash")
	sim = Simulation.new()
	sim.rules.cities.chengdu.labor = 45
	expect(not sim.start_project("warehouse", "jiangwan", false).is_empty(), "Local labor limit must block project")

func _test_save() -> void:
	var sim = Simulation.new()
	sim.start_project("road", "liyan", false)
	sim.set_transport(true, 8)
	sim.advance_month()
	var path := "user://test-campaign.json"
	expect(sim.save_game(path).is_empty(), "Save can write valid state")
	var restored = Simulation.new()
	expect(restored.load_game(path).is_empty(), "Saved state validates and restores")
	expect(JSON.stringify(restored.state) == JSON.stringify(sim.state), "Save/load retains complete state")
	var expected: Dictionary = sim.advance_month()
	var actual: Dictionary = restored.advance_month()
	expect(expected.ok and actual.ok and JSON.stringify(restored.state) == JSON.stringify(sim.state), "Restored cargo and projects continue identically")
	expect(restored.save_game(path).is_empty() and FileAccess.file_exists(path + ".bak"), "Replacing a save retains a backup")
	var before := JSON.stringify(restored.state)
	var invalid: Dictionary = restored.state.duplicate(true)
	invalid.food.hanzhong = -1
	expect(not restored.validate_snapshot(invalid).is_empty(), "Negative inventories must be rejected")
	invalid = restored.state.duplicate(true)
	invalid.month = 2
	expect(not restored.validate_snapshot(invalid).is_empty(), "Inconsistent dates must be rejected")
	invalid = restored.state.duplicate(true)
	invalid.projects.road.active = "yes"
	expect(not restored.validate_snapshot(invalid).is_empty(), "Invalid nested field types must be rejected")
	invalid = restored.state.duplicate(true)
	invalid.last_report.notes = "invalid"
	expect(not restored.validate_snapshot(invalid).is_empty(), "Malformed reports must not pass validation and crash UI")
	var other_rules = Simulation.new()
	other_rules.rules_hash = "different"
	expect(not other_rules.load_game(path).is_empty(), "Changed rules must not mix with an older campaign")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{bad json")
	file.close()
	expect(not restored.load_game(path).is_empty() and JSON.stringify(restored.state) == before, "Corrupt save must leave current game intact")
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(path + suffix)

func _run_route(supervise: bool) -> Dictionary:
	var sim = Simulation.new()
	sim.start_project("warehouse", "jiangwan", supervise)
	sim.start_project("road", "liyan", supervise)
	sim.set_transport(true, 8)
	for month in range(30):
		if sim.state.finished:
			break
		if not sim.stage_data("warehouse").is_empty() and not sim.state.projects.warehouse.active:
			sim.start_project("warehouse", "jiangwan", supervise)
		var result: Dictionary = sim.advance_month()
		if not result.ok:
			return {"ok": false, "error": result.error}
		if sim.state.money < 0 or sim.state.food.chengdu < 0 or sim.state.food.hanzhong < 0:
			return {"ok": false, "error": "Negative resources"}
	return {"ok": sim.state.finished, "sim": sim}

func _test_playable_routes() -> void:
	var delegated := _run_route(false)
	var supervised := _run_route(true)
	expect(delegated.ok and supervised.ok, "Both delegated and supervised routes reach review without starvation")
	if not delegated.ok or not supervised.ok:
		return
	var a: Dictionary = delegated.sim.assessment()
	var b: Dictionary = supervised.sim.assessment()
	expect(a.warehouse and a.road and a.supply and a.finance, "Delegated route can achieve all preparation goals")
	expect(b.warehouse and b.road and b.supply and b.finance, "Supervised route can achieve all preparation goals")
	expect(delegated.sim.state.health > supervised.sim.state.health, "Supervision has a persistent health opportunity cost")
	print("Delegated route: grain %.2f, Hanzhong %.2f, money %.2f, health %.2f" % [delegated.sim.total_food(), delegated.sim.state.food.hanzhong, delegated.sim.state.money, delegated.sim.state.health])
	print("Supervised route: grain %.2f, Hanzhong %.2f, money %.2f, health %.2f" % [supervised.sim.total_food(), supervised.sim.state.food.hanzhong, supervised.sim.state.money, supervised.sim.state.health])

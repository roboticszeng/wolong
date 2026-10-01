extends RefCounted

# Narrative progress lives in the campaign, not in a separate preference file.
static func ensure(s: Dictionary) -> Dictionary:
	if not s.has("chronicle"):
		s.chronicle = {"intro": 0, "skipped": false, "observed": false, "events": []}
	return s.chronicle

static func goal(s: Dictionary) -> Array:
	var c := ensure(s)
	if c.skipped: return []
	if not c.observed: return ["warehouse", "第一步 · 点击城中的粮仓", "观察损耗，找出现代知识能解决的问题。"]
	if s.projects.warehouse.stage == 0:
		if not s.projects.warehouse.active: return ["warehouse", "第二步 · 委任仓储试验", "选负责人；蒋琬擅长仓储，能缩短工期。"]
		return ["next", "第三步 · 等待试验结果", "点下个月。时间会消耗粮钱，试验不会凭空完成。"]
	if not s.projects.road.active and s.projects.road.stage == 0: return ["road", "第四步 · 修路，让成果走出成都", "点城门 → 整备粮道 → 委任李严。"]
	if not s.transport.enabled: return ["road", "第五步 · 开始运粮", "城门安排成都运往汉中；到货需要一个月。"]
	if not "arrival" in c.events: return ["next", "第六步 · 等待汉中收粮", "运粮当月出发，下个月到达。可在舆图查看粮车。"]
	if s.projects.warehouse.stage < 3: return ["warehouse", "下一目标 · 把知识变成制度", "回粮仓继续常规执行、汉中推广。试点成功不等于全国采用。"]
	return ["map", "兴汉第一章 · 后方初定", "224年十月前：仓储推广、粮道整备、汉中粮50、留钱10。"]

static func event(s: Dictionary, had_convoy: bool) -> Array:
	var c := ensure(s)
	if had_convoy: c["arrival_ready"] = true
	var entries := [
		["trial", s.projects.warehouse.stage >= 1, "jiangwan", "蒋琬 · 小试初成", "按您的办法，仓吏将粮袋垫高、保持通风，分批登记损耗。成都试点已成，下一月开始减少损失。", "我的现代记忆：控制潮气与记录数据，比喊一句‘节约粮食’有用。但小试还不足以证明各地都能照做。"],
		["routine", s.projects.warehouse.stage >= 2, "jiangwan", "蒋琬 · 不靠丞相盯着", "交接、验收与巡仓有了章程。成都仓储已进入常规执行，仓吏可以接手。", "技术不是我亲自做一辈子。把方法教给人、把记录留下来，才是蜀汉真正增加的能力。"],
		["adoption", s.projects.warehouse.stage >= 3, "feiyi", "费祎 · 汉中也能照做", "汉中的仓吏已完成训练，当地仓储规范开始生效。成都的经验终于越过了山路。", "兴复汉室不能靠一张蓝图。每少损失一袋粮，前线就少一分后顾之忧。"],
		["road", s.projects.road.stage >= 1, "liyan", "李严 · 栈道交接已通", "栈道和交接站整备完毕。运量增加，途中损耗降低；仍需安排运粮，粮不会自动出现在汉中。", "供应链也是技术。道路、仓储、交接记录必须连在一起，才能支撑将来的北伐。"],
		["arrival", had_convoy, "liyan", "李严 · 粮已抵达汉中", "前月发出的粮已交入汉中仓。路上的损失已计入账目，城里的现粮才真正增加。", "我带来的不是凭空变出的机器，而是能验证、能传授的方法。先让后方稳下来，再谈改变历史。"]]
	for entry in entries:
		if entry[0] == "arrival": entry[1] = c.get("arrival_ready", false)
		if entry[1] and not entry[0] in c.events:
			c.events.append(entry[0])
			return entry
	return []

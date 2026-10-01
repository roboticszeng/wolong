@tool
extends EditorPlugin

var dock: VBoxContainer
var fields := {}
var source: Dictionary
var original_text := ""
var status: Label
var scenario_path := "res://data/scenario.json"
const FIELD_PATHS = {
	"开局财政": ["initial", "money"],
	"成都开局粮": ["cities", "chengdu", "food"],
	"汉中开局粮": ["cities", "hanzhong", "food"],
	"成都秋收": ["cities", "chengdu", "harvest"],
	"汉中秋收": ["cities", "hanzhong", "harvest"],
	"常规月收入": ["monthly_income"],
	"常规月维护": ["monthly_upkeep"],
	"基础道路容量": ["route", "capacity"],
	"整备后容量": ["route", "improved_capacity"],
	"基础运输损耗": ["route", "loss"],
	"整备后损耗": ["route", "improved_loss"],
	"汉中储粮目标": ["goal_food"]
}

func _enter_tree() -> void:
	dock = VBoxContainer.new()
	dock.name = "卧龙筹备"
	dock.custom_minimum_size.x = 270
	var intro := Label.new()
	intro.text = "后方经营 · 参数与试玩\n修改保存后，重新开始游戏生效。"
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dock.add_child(intro)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 360
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dock.add_child(scroll)
	var form := VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(form)
	for title in FIELD_PATHS:
		var row := HBoxContainer.new()
		form.add_child(row)
		var label := Label.new()
		label.text = title
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var input := SpinBox.new()
		var is_loss: bool = title.ends_with("损耗")
		input.max_value = 0.9 if is_loss else 500
		input.step = 0.01 if is_loss else 1
		input.custom_minimum_size.x = 110
		row.add_child(input)
		fields[title] = input
	_button("保存参数（备份原表）", _save)
	_button("重新载入参数", _reload)
	_button("打开游戏主场景", func(): EditorInterface.open_scene_from_path("res://scenes/main.tscn"))
	_button("运行游戏 · F5", func(): EditorInterface.play_main_scene())
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dock.add_child(status)
	add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_UL, dock)
	_reload()
	if OS.get_cmdline_user_args().has("--verify-wolong-editor"):
		_verify.call_deferred()

func _button(title: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = title
	button.pressed.connect(callback)
	dock.add_child(button)

func _reload() -> void:
	original_text = FileAccess.get_file_as_string(scenario_path)
	var data: Variant = JSON.parse_string(original_text)
	if not data is Dictionary:
		status.text = "参数表无法读取，请修复 JSON 后重新载入。"
		return
	source = data
	for title in FIELD_PATHS:
		var current: Variant = source
		for key in FIELD_PATHS[title]:
			if not current is Dictionary or not current.has(key):
				status.text = "参数缺少字段：" + title
				return
			current = current[key]
		if not current is float and not current is int:
			status.text = "参数不是数字：" + title
			return
		fields[title].value = float(current)
	status.text = "已载入 scenario.json。项目阶段、人物等详细参数也在此表。"

func _save() -> void:
	if source.is_empty():
		return
	if FileAccess.get_file_as_string(scenario_path) != original_text:
		status.text = "文件已在外部修改，请先重新载入，避免覆盖。"
		return
	var data := source.duplicate(true)
	for title in FIELD_PATHS:
		if fields[title].get_line_edit().has_focus():
			fields[title].apply()
		var current: Dictionary = data
		var path: Array = FIELD_PATHS[title]
		for index in range(path.size() - 1):
			current = current[path[index]]
		current[path.back()] = fields[title].value
	if data.route.improved_capacity < data.route.capacity or data.route.improved_loss > data.route.loss:
		status.text = "整备后的容量不可更小，损耗不可更大。未保存。"
		return
	if data.route.capacity <= 0 or data.monthly_income <= 0:
		status.text = "基础容量和常规月收入必须大于零。未保存。"
		return
	var file := FileAccess.open(scenario_path + ".tmp", FileAccess.WRITE)
	if file == null:
		status.text = "参数写入失败。"
		return
	file.store_string(JSON.stringify(data, "\t", true, true))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK or DirAccess.copy_absolute(scenario_path, scenario_path + ".bak") != OK:
		status.text = "写入或备份失败，原表保留。"
		return
	if DirAccess.rename_absolute(scenario_path + ".tmp", scenario_path) != OK:
		status.text = "替换参数表失败，原表与备份保留。"
		return
	_reload()
	status.text = "已保存并备份。新局生效；不同参数表的旧存档不会混用。"
	EditorInterface.get_resource_filesystem().scan()

func _verify() -> void:
	# Exercise parameter editing against a temporary copy, preserving real rules.
	await get_tree().process_frame
	await get_tree().process_frame
	var test_path := "res://../logs/editor-test-scenario.json"
	assert(DirAccess.copy_absolute(scenario_path, test_path) == OK)
	scenario_path = test_path
	_reload()
	var value: float = fields["开局财政"].value
	fields["开局财政"].value = value + 1
	await get_tree().process_frame
	_save()
	print("Editor save verification: ", status.text)
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(test_path))
	assert(saved.initial.money == value + 1)
	assert(FileAccess.file_exists(test_path + ".bak"))
	fields["整备后容量"].value = 0
	await get_tree().process_frame
	_save()
	assert(FileAccess.get_file_as_string(test_path) == original_text)
	assert(status.text.contains("未保存"))
	scenario_path = "res://data/scenario.json"
	_reload()
	print("PASS: Wolong editor dock loads, edits, saves, backs up and rejects invalid route parameters")

func _exit_tree() -> void:
	if dock != null:
		remove_control_from_docks(dock)
		dock.queue_free()

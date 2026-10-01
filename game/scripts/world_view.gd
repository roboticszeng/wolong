extends Control
const NationalMap = preload("res://scripts/national_map.gd")
var national_map: RefCounted

signal place_clicked(place: String)
signal city_clicked(city: String)
var simulation: RefCounted
var city := "chengdu"
var view := "city"
var selected_place := ""
var scene_texture: Texture2D
var sprites: Texture2D
var font: Font
var tick := 0.0
var tutorial_target := ""
var hover := ""
var effect_time := 0.0
var place_points := {"warehouse": Vector2(0.30, 0.51), "officers": Vector2(0.56, 0.30), "market": Vector2(0.78, 0.65), "road": Vector2(0.84, 0.24), "farm": Vector2(0.18, 0.70)}
var building_areas := {"warehouse": Rect2(0.21, 0.37, 0.26, 0.27), "officers": Rect2(0.49, 0.19, 0.21, 0.24), "road": Rect2(0.79, 0.10, 0.20, 0.23), "market": Rect2(0.71, 0.52, 0.24, 0.25), "farm": Rect2(0.01, 0.64, 0.26, 0.22)}
var city_points := {"chengdu": Vector2(0.34, 0.68), "hanzhong": Vector2(0.65, 0.35)}
const TITLES = {"warehouse": "粮仓", "officers": "官署", "market": "集市", "road": "粮道", "farm": "田地"}

func _ready() -> void:
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var system_font := SystemFont.new()
	system_font.font_names = PackedStringArray(["Microsoft YaHei", "SimHei"])
	font = system_font
	if view == "map":
		national_map = NationalMap.new()
	var image_path := "res://assets/original/shu_map_v2.png" if view == "map" else "res://assets/original/%s_scene_v2.png" % city
	scene_texture = load(image_path)
	if ResourceLoader.exists("res://assets/third_party/bbbits/npc_characters.png"):
		sprites = load("res://assets/third_party/bbbits/npc_characters.png")
	if city == "hanzhong":
		place_points.farm = Vector2(0.16, 0.72)
	set_default_cursor_shape(Control.CURSOR_ARROW)

func _process(delta: float) -> void:
	tick += delta
	effect_time = maxf(0, effect_time - delta)
	queue_redraw()

func hit_point(id: String) -> Vector2:
	if view == "map" and NationalMap.LOCATIONS.has(id):
		return NationalMap.label_point(size,id) if id in ["chengdu", "hanzhong"] else NationalMap.marker(size,id)
	return size * (city_points[id] if view == "map" and city_points.has(id) else place_points.get(id, Vector2(0.5, 0.5)))

func _hit(point: Vector2) -> String:
	if view == "map":
		for id in NationalMap.LOCATIONS:
			if point.distance_to(NationalMap.marker(size,id)) < 12: return id
		for id in ["chengdu", "hanzhong"]:
			if Rect2(hit_point(id)-Vector2(42,17),Vector2(84,59)).has_point(point): return id
		return ""
	var locations: Dictionary = city_points if view == "map" else place_points
	for id in locations:
		var p: Vector2 = size * locations[id]
		var hit := Rect2(p - Vector2(54, 22), Vector2(108, 65))
		if hit.has_point(point):
			return id
	if view == "city":
		var normalized := point / size
		for id in building_areas:
			if building_areas[id].has_point(normalized):
				return id
	return ""

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		hover = _hit(event.position)
		set_default_cursor_shape(Control.CURSOR_POINTING_HAND if not hover.is_empty() else Control.CURSOR_ARROW)
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var id := _hit(event.position)
		if not id.is_empty():
			if view == "map": city_clicked.emit(id)
			else: place_clicked.emit(id)
			accept_event()

func _draw() -> void:
	if scene_texture == null:
		return
	if view == "map": national_map.render(self,font)
	else: draw_texture_rect(scene_texture, Rect2(Vector2.ZERO, size), false)
	if simulation != null and int(simulation.state.month) >= 11:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.55, 0.72, 0.87, 0.10))
	if view == "map":
		_draw_map()
	else:
		_draw_city()
	if effect_time > 0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.86, 0.5, effect_time * 0.07))

func _tag(position: Vector2, title: String, focused: bool, subtitle: String = "") -> void:
	var width := maxf(78, title.length() * 21 + 25)
	var box := Rect2(position - Vector2(width / 2, 14), Vector2(width, 36 if subtitle.is_empty() else 57))
	draw_rect(box.grow(3), Color(0.10, 0.12, 0.10, 0.85))
	draw_rect(box, Color("3c3529") if not focused else Color("705c37"))
	draw_rect(box, Color("c5ad78"), false, 1)
	draw_string(font, position + Vector2(-width / 2 + 12, 10), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color("f4e6c5"))
	if not subtitle.is_empty():
		draw_string(font, position + Vector2(-width / 2 + 10, 33), subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("ded2ac"))
	var arrow_y := box.position.y - 9 + sin(tick * 3.0) * 2
	draw_colored_polygon(PackedVector2Array([Vector2(position.x - 5, arrow_y - 5), Vector2(position.x + 5, arrow_y - 5), Vector2(position.x, arrow_y)]), Color("ecd48b"))

func _draw_city() -> void:
	if sprites != null:
		var paths := [Vector4(0.43, 0.66, 0.62, 0.70), Vector4(0.59, 0.60, 0.65, 0.47), Vector4(0.76, 0.77, 0.88, 0.64), Vector4(0.27, 0.61, 0.38, 0.64)]
		for index in paths.size():
			var path: Vector4 = paths[index]
			var walker := walker_state(Vector2(path.x,path.y)*size,Vector2(path.z,path.w)*size,tick + index * 3.7)
			var p: Vector2 = walker.position
			var character: int = [0, 2, 5, 6][index]
			var source := Vector2((character % 4) * 144 + int(walker.frame) * 48, (character / 4) * 384 + int(walker.row) * 96)
			draw_texture_rect_region(sprites, Rect2(p - Vector2(12, 38), Vector2(24, 48)), Rect2(source,Vector2(48,96)))
	for id in place_points:
		var position: Vector2 = size * place_points[id]
		if id == tutorial_target:
			var pulse: float = (sin(tick * 4.0) + 1.0) * 0.5
			draw_arc(position, 57 + pulse * 5, 0, TAU, 48, Color(1.0, 0.83, 0.38, 0.65 + pulse * 0.3), 3, true)
			draw_line(position + Vector2(0, -82), position + Vector2(0, -62), Color("ffe291"), 4)
			draw_line(position + Vector2(-7, -70), position + Vector2(0, -62), Color("ffe291"), 3)
			draw_line(position + Vector2(7, -70), position + Vector2(0, -62), Color("ffe291"), 3)
		var subtitle := ""
		if simulation != null and id in ["warehouse", "road"]:
			var p: Dictionary = simulation.state.projects[id]
			if p.active:
				var stage: Dictionary = simulation.stage_data(id)
				subtitle = "%s · %d/%d" % [simulation.officer_name(p.leader), p.progress, simulation.duration(id)] if id == "road" or stage.city == city else "异地试行中"
			elif int(p.stage) > 0:
				if id == "warehouse":
					subtitle = "已采用" if int(p.stage) >= 3 else ("可继续" if city == "chengdu" else "尚未采用")
				else:
					subtitle = "已整备"
		_tag(position, TITLES[id] if id != "farm" or city == "chengdu" else "屯田", hover == id or selected_place == id, subtitle)
		if simulation != null and id == "warehouse":
			for index in range(3):
				draw_circle(position + Vector2(-12 + index * 12, 51), 3, Color("e1c780") if index < int(simulation.state.projects.warehouse.adopted) else Color("584b34"))
	if simulation != null and int(simulation.state.projects.warehouse.adopted) >= (1 if city == "chengdu" else 3):
		var flag := size * Vector2(0.39, 0.45)
		draw_line(flag, flag + Vector2(0, 34), Color("514126"), 3)
		draw_rect(Rect2(flag + Vector2(0, 2), Vector2(17, 12)), Color("637846"))
		var crates: int = int(simulation.state.projects.warehouse.adopted) + 1
		for index in crates:
			var p := size * Vector2(0.40, 0.59) + Vector2(index * 11, 0)
			draw_rect(Rect2(p, Vector2(10, 11)), Color("b18947"))
			draw_rect(Rect2(p + Vector2(1, 4), Vector2(8, 2)), Color("5a4227"))
	if simulation != null and int(simulation.state.projects.road.adopted) > 0:
		var flag := size * Vector2(0.87, 0.37)
		draw_line(flag, flag + Vector2(0, 25), Color("514126"), 3)
		draw_rect(Rect2(flag, Vector2(20, 11)), Color("994e36"))
	if simulation != null and not simulation.state.convoys.is_empty():
		var t := fmod(tick * 0.075, 1.0)
		var p := Vector2(0.43, 0.62).lerp(Vector2(0.86, 0.29), t) * size
		_draw_cart(p)
	# Subtle moving river sparkles and chimney wisps keep the scene alive.
	for index in range(7):
		var p := Vector2(0.035 + index * 0.018, 0.43 + sin(index * 4.0) * 0.06) * size
		draw_line(p, p + Vector2(7, 0), Color(0.88, 0.96, 0.9, 0.16 + (sin(tick * 2 + index) + 1) * 0.16), 2)
	for index in range(3):
		var p := Vector2(0.73, 0.53) * size - Vector2(0, fmod(tick * 8 + index * 13, 40))
		draw_rect(Rect2(p, Vector2(4, 5)), Color(0.88, 0.9, 0.81, 0.13))

static func direction_row(velocity: Vector2) -> int:
	if absf(velocity.x) >= absf(velocity.y): return 2 if velocity.x >= 0 else 1
	return 0 if velocity.y >= 0 else 3

static func walker_state(start: Vector2, finish: Vector2, time: float) -> Dictionary:
	var walk_time := start.distance_to(finish) / 24.0
	var rest := 1.8
	var phase := fposmod(time, (walk_time + rest) * 2)
	var forward := phase < walk_time + rest
	var leg := phase if forward else phase - walk_time - rest
	var moving := leg < walk_time
	var direction := finish - start if forward else start - finish
	var position := start.lerp(finish,minf(leg/walk_time,1.0)) if forward else finish.lerp(start,minf(leg/walk_time,1.0))
	return {"position":position,"row":direction_row(direction),"frame":[0,1,2,1][int(leg*6) % 4] if moving else 1,"moving":moving,"velocity":direction.normalized()*24.0 if moving else Vector2.ZERO}

func _draw_map() -> void:
	var a := NationalMap.marker(size,"chengdu")
	var b := NationalMap.marker(size,"hanzhong")
	var path := PackedVector2Array([a,a.lerp(b,0.25)+Vector2(-6,0),a.lerp(b,0.5),a.lerp(b,0.75)+Vector2(3,0),b])
	var active: bool = simulation != null and simulation.state.transport.enabled
	draw_polyline(path, Color(0.2, 0.18, 0.12, 0.8), 8)
	draw_polyline(path, Color("d7b75f") if active else Color("a79b78"), 3)
	for id in NationalMap.LOCATIONS:
		var location: Vector2 = NationalMap.marker(size,id)
		var playable: bool = id in ["chengdu", "hanzhong"]
		draw_circle(location, 5 if playable else 3, Color("f3ce72") if playable else Color("b8ba9b"))
		if not playable:
			draw_string(font,location+Vector2(6,-3),NationalMap.LOCATIONS[id][2],HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("e0dfb9") if hover == id else Color("b8ba9b"))
			continue
		var point: Vector2 = NationalMap.label_point(size,id)
		draw_line(location,point,Color("d7b75f"),1)
		var subtitle := ""
		if simulation != null:
			subtitle = "储粮 %.0f" % simulation.state.food[id]
		_tag(point, "成都" if id == "chengdu" else "汉中", hover == id, subtitle)
		if id == city:
			draw_arc(point + Vector2(0, 14), 48, 0, TAU, 36, Color("e3c578"), 2)
	if active and simulation != null and not simulation.state.convoys.is_empty():
		var time := fmod(tick * 0.16, 4.0)
		var section := mini(int(time), 3)
		_draw_cart(path[section].lerp(path[section + 1], time - section))

func _draw_cart(p: Vector2) -> void:
	draw_rect(Rect2(p + Vector2(-10, -9), Vector2(24, 12)), Color("674b2b"))
	for offset in [Vector2(-7, -16), Vector2(2, -17)]:
		draw_rect(Rect2(p + offset, Vector2(9, 10)), Color("d4b16b"))
	draw_circle(p + Vector2(-5, 5), 4, Color("342c22"))
	draw_circle(p + Vector2(11, 5), 4, Color("342c22"))
	draw_rect(Rect2(p + Vector2(19, -5), Vector2(12, 7)), Color("986e43"))
	draw_line(p + Vector2(10, 0), p + Vector2(23, 0), Color("674b2b"), 2)

extends RefCounted

# Coordinates are geographical, with no modern administrative borders.
const LOCATIONS = {
	"chengdu": [104.07,30.67,"成都"], "hanzhong": [107.03,33.07,"汉中"],
	"changan": [108.94,34.34,"长安"], "luoyang": [112.45,34.62,"洛阳"],
	"xuchang": [113.85,34.03,"许昌"], "yecheng": [114.60,36.30,"邺"],
	"jianye": [118.78,32.04,"建业"], "xiangyang": [112.14,32.04,"襄阳"],
	"jiangling": [112.19,30.35,"江陵"], "shouchun": [116.79,32.58,"寿春"],
	"baidi": [109.57,31.05,"白帝"], "nanzhong": [102.71,25.04,"南中"],
	"wuwei": [102.63,37.93,"武威"], "liaodong": [123.17,41.27,"辽东"],
	"jiaozhi": [105.85,21.03,"交趾"], "guangling": [119.42,32.39,"广陵"]}
var land: Array = []

func _init() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/maps/ne_110m_land.geojson"))
	for feature in data.features:
		var geometry: Dictionary = feature.geometry
		var polygons: Array = [geometry.coordinates] if geometry.type == "Polygon" else geometry.coordinates
		for polygon in polygons:
			var ring := PackedVector2Array()
			for point in polygon[0]: ring.append(Vector2(float(point[0]), float(point[1])))
			land.append(ring)

static func project(size: Vector2, lon: float, lat: float) -> Vector2:
	var scale := minf((size.x - 120) / (63.0 * 0.82), (size.y - 220) / 38.0)
	var start := Vector2((size.x - 63 * 0.82 * scale) * 0.5, 105)
	return start + Vector2((lon - 73) * 0.82, 54 - lat) * scale

static func marker(size: Vector2, id: String) -> Vector2:
	var p: Array = LOCATIONS[id]
	return project(size, float(p[0]), float(p[1]))

static func label_point(size: Vector2, id: String) -> Vector2:
	return marker(size, id) + (Vector2(-42, 22) if id == "chengdu" else Vector2(-45,-40))

func render(canvas: Control, font: Font) -> void:
	var size := canvas.size
	canvas.draw_rect(Rect2(Vector2.ZERO, size), Color("192b30"))
	for index in range(16):
		var y := 80 + index * 34.0
		canvas.draw_line(Vector2(20,y), Vector2(size.x-20,y), Color(0.42,0.63,0.65,0.05), 1)
	for ring in land:
		var points := PackedVector2Array()
		for p in ring: points.append(project(size, p.x, p.y))
		canvas.draw_colored_polygon(points, Color("53674b"))
		canvas.draw_polyline(points, Color("acb17d"), 2, true)
	# Relief symbols are decorative; the coastline comes from Natural Earth.
	for range_data in [[84,32,20],[95,36,17],[105,34,10],[112,38,8],[102,28,9]]:
		for index in int(range_data[2]):
			var p := project(size, range_data[0] + (index % 7) * 0.85, range_data[1] + (index / 7) * 0.75)
			var height := 8 + (index % 3) * 3
			canvas.draw_colored_polygon(PackedVector2Array([p+Vector2(-8,5),p+Vector2(0,-height),p+Vector2(9,5)]), Color("354637"))
			canvas.draw_line(p+Vector2(-8,5),p+Vector2(0,-height),Color("a6ad79"),2)
	for river in [
		[[91,33],[97,33],[100,28],[103,29],[106,29.5],[110,30],[114,30.5],[118,31],[122,31]],
		[[96,35],[101,36],[104,36],[106,38],[110,40],[111,36],[114,35],[118,37]]]:
		var points := PackedVector2Array()
		for p in river: points.append(project(size,p[0],p[1]))
		canvas.draw_polyline(points,Color("69a4ad"),3,true)
	for label in [[88,41,"西域"],[93,29,"高原"],[107,45,"漠北"],[122,39,"辽东"],[116,26,"江南"],[106,22,"岭南"],[128,29,"东海"],[108,18,"南海"]]:
		canvas.draw_string(font,project(size,label[0],label[1]),label[2],HORIZONTAL_ALIGNMENT_CENTER,-1,23,Color("b7be8d"))
	canvas.draw_string(font,Vector2(34,107),"天下山川舆图",HORIZONTAL_ALIGNMENT_LEFT,-1,28,Color("e6c98c"))
	canvas.draw_string(font,Vector2(size.x-315,size.y-125),"成都、汉中可治理 · 其余仅供察看",HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color("d3c6a7"))
	var compass := Vector2(size.x-75,130)
	canvas.draw_line(compass+Vector2(0,12),compass+Vector2(0,-15),Color("e6c98c"),2)
	canvas.draw_colored_polygon(PackedVector2Array([compass+Vector2(0,-24),compass+Vector2(-5,-12),compass+Vector2(5,-12)]),Color("e6c98c"))
	canvas.draw_string(font,compass+Vector2(-8,-31),"北",HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("e6c98c"))

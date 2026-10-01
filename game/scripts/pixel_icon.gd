extends Control

var kind := "grain"
var tint := Color("e7c887")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(28, 28)

func _draw() -> void:
	var scale_factor := minf(size.x, size.y) / 32.0
	draw_set_transform((size - Vector2(32, 32) * scale_factor) / 2.0, 0, Vector2.ONE * scale_factor)
	var dark := Color("54412b")
	match kind:
		"grain", "warehouse":
			draw_polygon(PackedVector2Array([Vector2(10, 5), Vector2(22, 5), Vector2(20, 11), Vector2(26, 18), Vector2(25, 28), Vector2(7, 28), Vector2(6, 18), Vector2(12, 11)]), PackedColorArray([tint]))
			draw_rect(Rect2(10, 9, 12, 3), dark)
			draw_line(Vector2(16, 16), Vector2(16, 25), dark, 2)
			for y in [17, 21]:
				draw_line(Vector2(12, y), Vector2(16, y + 3), dark, 2)
				draw_line(Vector2(20, y), Vector2(16, y + 3), dark, 2)
		"coin", "market":
			for offset in [Vector2(0, 8), Vector2(7, 2)]:
				draw_rect(Rect2(4 + offset.x, 5 + offset.y, 17, 16), dark)
				draw_rect(Rect2(6 + offset.x, 3 + offset.y, 13, 16), tint)
				draw_rect(Rect2(10 + offset.x, 8 + offset.y, 5, 5), dark)
		"military":
			draw_line(Vector2(8, 6), Vector2(25, 25), tint, 4)
			draw_line(Vector2(24, 6), Vector2(7, 25), tint, 4)
			draw_line(Vector2(5, 19), Vector2(13, 26), dark, 3)
			draw_line(Vector2(20, 26), Vector2(27, 19), dark, 3)
		"people", "officers":
			draw_rect(Rect2(12, 4, 8, 8), tint)
			draw_rect(Rect2(9, 14, 14, 14), tint)
			draw_rect(Rect2(3, 10, 5, 5), tint.darkened(0.2))
			draw_rect(Rect2(2, 18, 5, 10), tint.darkened(0.2))
			draw_rect(Rect2(24, 10, 5, 5), tint.darkened(0.2))
			draw_rect(Rect2(25, 18, 5, 10), tint.darkened(0.2))
		"road", "map":
			draw_line(Vector2(8, 28), Vector2(15, 19), tint, 5)
			draw_line(Vector2(15, 19), Vector2(10, 13), tint, 5)
			draw_line(Vector2(10, 13), Vector2(23, 4), tint, 5)
			draw_rect(Rect2(20, 2, 8, 6), dark)
		"scroll", "report":
			draw_rect(Rect2(7, 5, 18, 23), tint)
			draw_rect(Rect2(4, 4, 24, 4), dark)
			draw_rect(Rect2(4, 26, 24, 4), dark)
			for y in [12, 17, 22]:
				draw_rect(Rect2(11, y, 10, 2), dark)
		"leaf", "farm":
			draw_line(Vector2(16, 5), Vector2(16, 29), tint, 3)
			for y in [7, 14, 21]:
				draw_line(Vector2(7, y), Vector2(16, y + 7), tint, 4)
				draw_line(Vector2(25, y), Vector2(16, y + 7), tint, 4)
		"next":
			draw_polygon(PackedVector2Array([Vector2(9, 5), Vector2(27, 16), Vector2(9, 27)]), PackedColorArray([tint]))
		"gear":
			draw_rect(Rect2(5, 5, 22, 22), tint)
			draw_rect(Rect2(11, 11, 10, 10), dark)
		"heart":
			draw_polygon(PackedVector2Array([Vector2(4, 10), Vector2(9, 5), Vector2(16, 10), Vector2(23, 5), Vector2(28, 10), Vector2(28, 16), Vector2(16, 28), Vector2(4, 16)]), PackedColorArray([tint]))
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

extends TextureRect

var officer := "zhuge"

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var source: Texture2D = load("res://assets/original/officers_v2.png")
	var cell := source.get_size() / 2.0
	var index: Vector2 = {"zhuge": Vector2(0, 0), "jiangwan": Vector2(1, 0), "liyan": Vector2(0, 1), "feiyi": Vector2(1, 1)}.get(officer, Vector2.ZERO)
	var picture := AtlasTexture.new()
	picture.atlas = source
	picture.region = Rect2(index * cell, cell)
	texture = picture

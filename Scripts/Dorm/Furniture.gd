extends StaticBody2D

# Reusable physical furniture. No inventory or storage UI is created here.
@export var object_id: String = ""
@export_enum("wardrobe", "nightstand", "fridge", "bed", "desk", "toilet", "shower", "sink") var furniture_kind := "nightstand"
@export var footprint := Vector2(32, 32)
@export var tint := Color("829b9a")
@export var opened := false
@export_enum("south", "east") var facing := "south"
@export var flush_mount := false

func _ready() -> void:
	assert(not object_id.is_empty(), "Furniture needs a stable object ID")
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = footprint
	shape.shape = box
	shape.position = Vector2(0, -footprint.y / 2)
	add_child(shape)
	queue_redraw()

func _draw() -> void:
	var box := Rect2(Vector2(-footprint.x / 2, -footprint.y), footprint)
	draw_rect(box if flush_mount else box.grow(2), Color("394746"))
	draw_rect(box, Color("a37d57"))
	draw_line(box.position, Vector2(box.end.x, box.position.y), Color("dfc39a"), 2)
	match furniture_kind:
		"bed":
			# Draw along the long axis so a horizontal bed has its pillow at its head.
			var horizontal := footprint.x > footprint.y
			var bed_size := Vector2(footprint.y, footprint.x) if horizontal else footprint
			if horizontal:
				draw_set_transform(box.position + Vector2(footprint.x, 0), PI / 2)
			else:
				draw_set_transform(box.position)
			var mattress := Rect2(Vector2(3,3), bed_size - Vector2(6,6))
			draw_rect(mattress, tint)
			var pillow_depth := floorf(bed_size.y * .2)
			draw_rect(Rect2(6,5,bed_size.x-12,pillow_depth), Color("ece4c9"))
			draw_rect(Rect2(6,6,bed_size.x-12,2), Color("fff1d6"))
			var blanket_start := pillow_depth + 10
			draw_line(Vector2(3,blanket_start), Vector2(bed_size.x-3,blanket_start), tint.lightened(.24), 3)
			for x in range(8, int(bed_size.x)-3, 8):
				draw_line(Vector2(x,blanket_start+2), Vector2(x,bed_size.y-4), tint.darkened(.12))
			draw_set_transform(Vector2.ZERO)
		"desk":
			draw_rect(box.grow(-3), Color("c4a076"))
			draw_rect(Rect2(box.position + Vector2(7, 5), Vector2(15, 12)), Color("e7dfc6"))
			draw_line(box.position + Vector2(9, 8), box.position + Vector2(18, 8), Color("8b9b9b"))
			draw_rect(Rect2(Vector2(box.end.x - 14, box.position.y + 5), Vector2(7, 9)), Color("567679"))
		"wardrobe", "nightstand":
			draw_rect(box.grow(-3), Color("b08b61"), false, 1)
			if furniture_kind == "wardrobe" and facing == "east":
				draw_rect(Rect2(box.end.x - 5, box.position.y + 2, 5, box.size.y - 4), Color("c29a6b"))
				for y in range(int(box.position.y) + 4, -4, 24):
					draw_line(Vector2(box.position.x + 3, y), Vector2(box.end.x - 2, y), Color("634f3d"))
					draw_rect(Rect2(box.end.x - 4, y + 7, 2, 6), Color("e6d3a3"))
			elif furniture_kind == "wardrobe":
				draw_line(Vector2(0, box.position.y + 3), Vector2(0, -3), Color("634f3d"), 2)
				draw_rect(Rect2(-6, -18, 2, 7), Color("e6d3a3"))
				draw_rect(Rect2(4, -18, 2, 7), Color("e6d3a3"))
			else:
				draw_line(Vector2(box.position.x + 3, -12), Vector2(box.end.x - 3, -12), Color("6a5743"))
				draw_rect(Rect2(-4, -9, 8, 2), Color("dfc997"))
		"fridge":
			draw_rect(box, Color("c5d1c8"))
			draw_rect(box.grow(-3), Color("e1e5cf"), false, 2)
			draw_line(Vector2(box.position.x + 2, -28), Vector2(box.end.x - 2, -28), Color("7c9191"), 2)
			draw_rect(Rect2(box.end.x - 7, -21, 2, 12), Color("617b7e"))
			draw_rect(Rect2(box.position.x + 5, box.position.y + 6, 7, 6), Color("cf9d74"))
		"toilet":
			draw_rect(box, Color("819e9a"))
			draw_rect(Rect2(box.position + Vector2(2, 2), Vector2(box.size.x - 4, 12)), Color("e8e5cf"))
			draw_ellipse_pixels(Rect2(box.position + Vector2(4, 17), box.size - Vector2(8, 19)), Color("e8e5cf"))
			draw_rect(Rect2(-5, -18, 10, 9), Color("8ca9a7"))
		"shower":
			draw_rect(box, Color("adc4bd"))
			draw_rect(box.grow(-5), Color("839fa1"))
			for x in range(int(box.position.x) + 8, int(box.end.x) - 4, 12):
				draw_line(Vector2(x, box.position.y + 5), Vector2(x, -5), Color("a2b9b2"))
			draw_rect(Rect2(-3, -17, 6, 6), Color("4c707a"))
			draw_line(box.position + Vector2(6, 3), box.position + Vector2(26, 3), Color("e0e5d2"), 3)
		"sink":
			draw_rect(box, Color("e0e5d2"))
			draw_rect(box.grow(-5), Color("8ba6a6"))
			if facing == "east":
				draw_rect(Rect2(box.position.x, -footprint.y/2-2, 10, 4), Color("d1d9ce"))
				draw_rect(Rect2(box.end.x-10, -footprint.y/2-2, 3, 4), Color("4c707a"))
			else:
				draw_rect(Rect2(-2, box.position.y, 4, 10), Color("d1d9ce"))
				draw_rect(Rect2(-2, -10, 4, 3), Color("4c707a"))

func draw_ellipse_pixels(box: Rect2, color: Color) -> void:
	# Stepped corners keep fixtures on the same integer pixel grid as the other art.
	draw_rect(box.grow(-3), color)
	draw_rect(Rect2(box.position + Vector2(3, 0), box.size - Vector2(6, 0)), color)

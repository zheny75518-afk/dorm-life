extends "res://Scripts/Dorm/FloorManager.gd"

const FURNITURE = preload("res://Scenes/Furniture/Furniture.tscn")
var furniture: Array = []
var internal_doors: Array = []
var partitions: Array[Rect2] = []
var room_areas := {
	"Б": Rect2(18,18,588,222),
	"А": Rect2(336,252,270,210),
	"Коридор": Rect2(216,252,108,210),
	"Туалет": Rect2(18,252,186,102),
	"Душевая": Rect2(18,366,186,96)
}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	font = ThemeDB.fallback_font
	for asset in ["floor", "terrazzo", "door", "window"]:
		textures[asset] = load("res://Art/Dorm/" + asset + ".png")
	bounds = Rect2(12,12,600,456)
	props = Node2D.new()
	props.name = "Environment"
	props.y_sort_enabled = true
	add_child(props)
	interactions = MANAGER.new()
	add_child(interactions)
	# Outer shell. The bottom doorway is a scene exit, never a gap off the map.
	for rect in [Rect2(12,12,600,6), Rect2(12,462,600,6), Rect2(12,18,6,444), Rect2(606,18,6,444),
		Rect2(18,240,234,12), Rect2(288,240,318,12),
		Rect2(204,252,12,30), Rect2(204,318,12,72), Rect2(204,426,12,36),
		Rect2(18,354,186,12), Rect2(324,252,12,78), Rect2(324,366,12,96)]:
		partitions.append(rect)
		solid(rect.get_center(), rect.size)
	for data in [["Комната Б", Vector2(270,246), false], ["Комната А", Vector2(330,348), true], ["Туалет", Vector2(210,300), true], ["Душевая", Vector2(210,408), true]]:
		var door := make_interaction("door", "Открыть · " + data[0], data[1])
		door.barrier = solid(Vector2.ZERO, Vector2(6,36) if data[2] else Vector2(36,6), door)
		door.art = picture("door", Vector2.ZERO, Vector2.ZERO, door)
		door.art.offset = Vector2.ZERO
		door.art.scale = Vector2(1.125,.1875)
		door.art.rotation = PI/2 if data[2] else 0.0
		door.art.z_index = 1
		internal_doors.append(door)
	build_furniture()
	var exit_door := make_interaction("block_exit", "Выйти на восьмой этаж", Vector2(270,462))
	exit_door.barrier = solid(Vector2.ZERO, Vector2(36,6), exit_door)
	exit_door.art = picture("door", Vector2.ZERO, Vector2.ZERO, exit_door)
	exit_door.art.offset = Vector2.ZERO
	exit_door.art.scale = Vector2(1.125,.1875)
	spawn_player(Vector2(270,427.5))
	player.restore_facing(Vector2.UP)
	var camera: Camera2D = player.get_node("Camera2D")
	camera.limit_left = 12
	camera.limit_top = 12
	camera.limit_right = 612
	camera.limit_bottom = 468
	camera.limit_smoothed = false
	# Keep the visible viewport inside the shell even after window aspect changes.
	get_viewport().size_changed.connect(fit_camera)
	fit_camera()
	camera.reset_smoothing()
	setup_controls()
	build_ui()
	setup_audio()
	location_label.text = "8 ЭТАЖ / БЛОК 813"
	toast("Блок 813 · Комнаты А и Б. Выход — через входную дверь.", 5)
	for item in [["КОМНАТА Б", Vector2(255,112.5)], ["КОМНАТА А", Vector2(420,336)], ["ТУАЛЕТ", Vector2(120,330)], ["ДУШЕВАЯ", Vector2(112.5,396)], ["813 / ВЫХОД", Vector2(238.5,445.5)]]:
		text_at(item[0], item[1], 9, Color("576967"))
	print("BLOCK813_READY furniture=", furniture.size())

func fit_camera() -> void:
	var view := get_viewport_rect().size
	var zoom_at := ceilf(maxf(1.0, maxf(view.x / bounds.size.x, view.y / bounds.size.y)))
	player.get_node("Camera2D").zoom = Vector2.ONE * zoom_at

func furnish(id: String, kind: String, at: Vector2, size: Vector2, color: Color = Color("829b9a")) -> void:
	var item = FURNITURE.instantiate()
	item.object_id = "813_" + id
	item.furniture_kind = kind
	item.footprint = size
	item.tint = color
	item.position = at
	props.add_child(item)
	furniture.append(item)

func build_furniture() -> void:
	furnish("b_bed1", "bed", Vector2(84,96), Vector2(36,60))
	furnish("b_bed2", "bed", Vector2(192,96), Vector2(36,60), Color("a6a17b"))
	furnish("b_desk1", "desk", Vector2(309,66), Vector2(60,30))
	furnish("b_wardrobe", "wardrobe", Vector2(42,168), Vector2(36,48))
	furnish("b_cabinet1", "nightstand", Vector2(576,54), Vector2(24,24))
	furnish("b_desk2", "desk", Vector2(576,168), Vector2(36,48))
	furnish("b_fridge", "fridge", Vector2(60,228), Vector2(24,36))
	furnish("b_cabinet2", "nightstand", Vector2(99,228), Vector2(24,24))
	furnish("b_cabinet3", "nightstand", Vector2(135,228), Vector2(24,24))
	furnish("b_desk3", "desk", Vector2(402,228), Vector2(60,30))
	furnish("b_bed3", "bed", Vector2(504,228), Vector2(60,36), Color("9c9a80"))
	furnish("a_bed1", "bed", Vector2(564,324), Vector2(36,60), Color("b28d77"))
	furnish("a_bed2", "bed", Vector2(564,444), Vector2(36,60))
	furnish("a_cabinet1", "nightstand", Vector2(366,282), Vector2(24,24))
	furnish("a_cabinet2", "nightstand", Vector2(408,282), Vector2(24,24))
	furnish("a_desk1", "desk", Vector2(576,366), Vector2(36,24))
	furnish("a_desk2", "desk", Vector2(366,444), Vector2(42,30))
	furnish("toilet", "toilet", Vector2(72,324), Vector2(24,33))
	furnish("sink", "sink", Vector2(168,282), Vector2(30,18))
	furnish("shower", "shower", Vector2(72,450), Vector2(48,60))
	furnish("utility", "wardrobe", Vector2(168,450), Vector2(30,30))

func _draw() -> void:
	draw_rect(bounds, Color("d1c7ac"))
	for key in room_areas:
		var area: Rect2 = room_areas[key]
		for x in range(int(area.position.x), int(area.end.x), 16):
			for y in range(int(area.position.y), int(area.end.y), 16):
				var tile := Rect2(x,y,16,16).intersection(area)
				draw_texture_rect(textures.terrazzo if key in ["А", "Б"] else textures.floor, tile, false)
				if key in ["Туалет", "Душевая"]:
					draw_rect(tile, Color(.4,.7,.7,.15))
	# Small rugs and door thresholds remain entirely nonphysical.
	for rug in [Rect2(120,126,336,48), Rect2(390,366,114,42)]:
		draw_rect(rug, Color("778b83"))
		draw_rect(rug.grow(-4), Color("b8b59a"), false, 2)
	for rect in partitions:
		draw_rect(rect, Color("6a685b"))
		draw_rect(Rect2(rect.position, Vector2(rect.size.x, minf(3,rect.size.y))), Color("e2d4ae"))
	for door in [Rect2(252,240,36,12), Rect2(204,282,12,36), Rect2(204,390,12,36), Rect2(324,330,12,36)]:
		draw_rect(door, Color("bdac83"))
		draw_rect(door.grow(-2), Color("e1cd9f"), false, 1)
	# Wall-mounted windows, with evening glass in the same existing pixel style.
	for at in [Vector2(384,15), Vector2(492,15)]:
		draw_texture_rect(textures.window, Rect2(at - Vector2(24,3), Vector2(48,6)), false)
	draw_texture_rect(textures.window, Rect2(606,372,6,36), false)

func _process(delta: float) -> void:
	super(delta)
	if is_instance_valid(location_label):
		for key in room_areas:
			if room_areas[key].has_point(player.position):
				location_label.text = "БЛОК 813 / " + str(key).to_upper()
				break

func draw_map() -> void:
	var scale_at := .42
	for key in room_areas:
		var rect: Rect2 = room_areas[key]
		map_canvas.draw_rect(Rect2(Vector2(10, -30) + rect.position * scale_at, rect.size * scale_at), Color("a9b7a0"))
	map_canvas.draw_circle(Vector2(10,-30) + player.position * scale_at, 3, Color("fa8f63"))

func build_ui() -> void:
	super()
	map_panel.get_child(0).get_child(0).text = "813 / ПЛАН БЛОКА"
	map_panel.get_child(0).get_child(2).text = "Б — сверху · А — справа · Санузел — слева"

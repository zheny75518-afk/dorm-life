extends "res://Scripts/Dorm/FloorManager.gd"

# All architectural dimensions are real pixels, authored separately from rendering.
const FURNITURE = preload("res://Scenes/Furniture/Furniture.tscn")
var layout: Dictionary
var furniture: Array = []
var internal_doors: Array = []
var partitions: Array[Rect2] = []
var room_areas: Dictionary = {}
var window_rects: Dictionary = {}

func rectangle(values: Array) -> Rect2:
	return Rect2(values[0], values[1], values[2], values[3])

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	font = ThemeDB.fallback_font
	layout = JSON.parse_string(FileAccess.get_file_as_string("res://Data/Interiors/block812.json"))
	bounds = rectangle(layout.bounds)
	for key in layout.rooms:
		room_areas[key] = rectangle(layout.rooms[key])
	for asset in ["floor", "terrazzo", "door", "window"]:
		textures[asset] = load("res://Art/Dorm/" + asset + ".png")
	props = Node2D.new()
	props.name = "Environment"
	props.y_sort_enabled = true
	add_child(props)
	interactions = MANAGER.new()
	add_child(interactions)
	for values in layout.walls:
		var wall := rectangle(values)
		partitions.append(wall)
		solid(wall.get_center(), wall.size)
	for data in layout.doors:
		internal_doors.append(make_door(rectangle(data.rect), "door", "Открыть · " + data.room))
	make_door(rectangle(layout.exit), "block_exit", "Выйти на восьмой этаж")
	for data in layout.furniture:
		var box := rectangle(data.rect)
		var item = FURNITURE.instantiate()
		item.object_id = data.id
		item.furniture_kind = data.kind
		item.facing = data.facing
		item.flush_mount = true
		item.footprint = box.size
		item.position = Vector2(box.get_center().x, box.end.y)
		item.set_meta("room", data.room)
		props.add_child(item)
		furniture.append(item)
	for data in layout.windows:
		window_rects[data.room] = rectangle(data.rect)
	spawn_player(Vector2(layout.spawn[0], layout.spawn[1]))
	player.restore_facing(Vector2.UP)
	get_viewport().size_changed.connect(fit_camera)
	fit_camera()
	player.get_node("Camera2D").reset_smoothing()
	setup_controls()
	build_ui()
	setup_audio()
	location_label.text = "8 ЭТАЖ / БЛОК 812"
	toast("Блок 812 · Комнаты А и Б. Выход — через входную дверь.", 5)
	print("BLOCK812_READY furniture=", furniture.size())

func make_door(box: Rect2, kind: String, title: String) -> DormInteractable:
	var door := make_interaction(kind, title, box.get_center())
	var vertical := box.size.y > box.size.x
	var size := Vector2(6,36) if vertical else Vector2(36,6)
	door.barrier = solid(Vector2.ZERO, size, door)
	door.art = picture("door", Vector2.ZERO, Vector2.ZERO, door)
	door.art.offset = Vector2.ZERO
	door.art.scale = Vector2(1.125,.1875)
	door.art.rotation = PI/2 if vertical else 0.0
	door.art.z_index = 1
	return door

func fit_camera() -> void:
	var camera: Camera2D = player.get_node("Camera2D")
	# Fixed zoom avoids the previous ceil(640/600) = 2 and doorway zoom jumps.
	camera.zoom = Vector2.ONE * float(layout.camera_zoom)
	var view := get_viewport_rect().size / camera.zoom
	var margin := ((view - bounds.size) / 2).max(Vector2.ZERO)
	camera.limit_left = floori(bounds.position.x - margin.x)
	camera.limit_top = floori(bounds.position.y - margin.y)
	camera.limit_right = ceili(bounds.end.x + margin.x)
	camera.limit_bottom = ceili(bounds.end.y + margin.y)
	camera.limit_smoothed = true

func _draw() -> void:
	if layout == null or textures.is_empty():
		return
	draw_rect(bounds, Color("d1c7ac"))
	for key in room_areas:
		var area: Rect2 = room_areas[key]
		for x in range(int(area.position.x), int(area.end.x), 16):
			for y in range(int(area.position.y), int(area.end.y), 16):
				var tile := Rect2(x,y,16,16).intersection(area)
				draw_texture_rect(textures.terrazzo if key in ["А", "Б"] else textures.floor, tile, false)
				if key in ["Туалет", "Душевая"]:
					draw_rect(tile, Color(.4,.7,.7,.15))
	for wall in partitions:
		draw_rect(wall, Color("6a685b"))
		draw_rect(Rect2(wall.position, Vector2(wall.size.x,minf(3,wall.size.y))), Color("e2d4ae"))
	for data in layout.doors:
		draw_rect(rectangle(data.rect), Color("bdac83"))
	# Rotate the existing glass texture so mullions run along the vertical wall.
	for key in window_rects:
		var box: Rect2 = window_rects[key]
		draw_set_transform(box.position + Vector2(box.size.x,0), PI/2)
		draw_texture_rect(textures.window, Rect2(Vector2.ZERO,Vector2(box.size.y,box.size.x)), false)
		draw_set_transform(Vector2.ZERO)

func _process(delta: float) -> void:
	super(delta)
	if is_instance_valid(location_label):
		for key in room_areas:
			if room_areas[key].has_point(player.position):
				location_label.text = "БЛОК 812 / " + str(key).to_upper()
				break

func draw_map() -> void:
	var scale_at := minf(370.0/bounds.size.x,205.0/bounds.size.y)
	var shift := Vector2(190,105)-bounds.get_center()*scale_at
	for key in room_areas:
		var box: Rect2 = room_areas[key]
		map_canvas.draw_rect(Rect2(shift+box.position*scale_at,box.size*scale_at),Color("a9b7a0"))
	map_canvas.draw_circle(shift+player.position*scale_at,3,Color("fa8f63"))

func build_ui() -> void:
	super()
	map_panel.get_child(0).get_child(0).text = "812 / ПЛАН БЛОКА"
	map_panel.get_child(0).get_child(2).text = "Б — север · А — восток · Санузел — запад"

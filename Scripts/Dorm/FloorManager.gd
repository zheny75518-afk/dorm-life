extends Node2D

const TILE: int = 16
const INTERACT = preload("res://Scripts/Dorm/Interactable.gd")
const MANAGER = preload("res://Scripts/Dorm/InteractionManager.gd")
const PLAYER_SCRIPT = preload("res://Scripts/Dorm/DormPlayer.gd")
@export var floor_data_path: String = "res://Data/Floors/floor08.json"
var floor_id: int = 8
var cells: Dictionary = {}
var zones: Array = []
var props: Node2D
var player: CharacterBody2D
var interactions: DormInteractionManager
var textures: Dictionary = {}
var font: Font
var prompt: Label
var location_label: Label
var notice: Label
var modal: PanelContainer
var modal_text: Label
var modal_title: Label
var modal_actions: VBoxContainer
var map_panel: PanelContainer
var notice_time: float = 0.0
var bounds := Rect2()
var door_cells: Array[Vector2i] = []
var door_records: Array = []
var show_map: bool = false
var map_canvas: Node2D
var elapsed: float = 0.0
var repairs: Array = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	font = ThemeDB.fallback_font
	for asset in ["floor", "terrazzo", "wall", "door", "elevator", "stove", "sink", "window", "radiator", "board", "rack", "stairs", "table", "lamp"]:
		textures[asset] = load("res://Art/Dorm/" + asset + ".png")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(floor_data_path))
	floor_id = int(data.floor_id)
	zones = data.zones
	for zone in zones:
		zone["area"] = Rect2(float(zone.rect[0]), float(zone.rect[1]), float(zone.rect[2]), float(zone.rect[3]))
		if zone.kind != "block":
			paint_area(zone.area, zone.kind)
	connect_components()
	props = Node2D.new()
	props.name = "Environment"
	props.y_sort_enabled = true
	add_child(props)
	interactions = MANAGER.new()
	add_child(interactions)
	build_walls()
	build_rooms()
	build_blocks()
	player = preload("res://Scenes/Player/Player.tscn").instantiate()
	player.set_script(PLAYER_SCRIPT)
	player.sprite = player.get_node("AnimatedSprite2D")
	player.healthbar = player.get_node("Camera2D/ProgressBar")
	player.hit_particles = player.get_node("hit_particle_blood")
	player.health = 200
	player.collision_layer = 2
	player.position = Vector2(float(data.spawn[0]), float(data.spawn[1]))
	props.add_child(player)
	player.top_level = false
	interactions.player = player
	var camera: Camera2D = player.get_node("Camera2D")
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 15.0
	camera.limit_left = int(bounds.position.x - 80)
	camera.limit_top = int(bounds.position.y - 80)
	camera.limit_right = int(bounds.end.x + 80)
	camera.limit_bottom = int(bounds.end.y + 80)
	for action in ["Punch", "Kick", "Dash", "Restart"]:
		InputMap.action_erase_events(action)
	for pair in [["MoveLeft", KEY_LEFT], ["MoveRight", KEY_RIGHT], ["MoveUp", KEY_UP], ["MoveDown", KEY_DOWN]]:
		var event := InputEventKey.new()
		event.physical_keycode = pair[1]
		InputMap.action_add_event(pair[0], event)
	build_ui()
	setup_audio()
	toast("Добро пожаловать домой. Исследуйте восьмой этаж.", 6.0)
	queue_redraw()
	print("DORM_READY floor=", floor_id, " cells=", cells.size(), " interactables=", interactions.objects.size(), " connectors=", repairs.size())

func paint_area(area: Rect2, kind: String) -> void:
	for x in range(int(area.position.x / TILE), int(area.end.x / TILE)):
		for y in range(int(area.position.y / TILE), int(area.end.y / TILE)):
			cells[Vector2i(x, y)] = kind

func connect_components() -> void:
	# Draw.io contains drafting gaps. Bridge only disconnected public areas.
	var start := Vector2i(16, 14)
	for attempt in range(12):
		var seen := flood(start)
		if seen.size() == cells.size():
			break
		var best_distance: int = 2147483647
		var a := Vector2i.ZERO
		var b := Vector2i.ZERO
		for outside: Vector2i in cells:
			if seen.has(outside):
				continue
			for inside: Vector2i in seen:
				var distance: int = absi(outside.x - inside.x) + absi(outside.y - inside.y)
				if distance < best_distance:
					best_distance = distance
					a = inside
					b = outside
		var cursor := a
		while cursor != b:
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					cells[cursor + Vector2i(dx, dy)] = "corridor"
			if cursor.x != b.x:
				cursor.x += signi(b.x - cursor.x)
			else:
				cursor.y += signi(b.y - cursor.y)
		repairs.append([a, b])

func flood(start: Vector2i, blocked: Array = []) -> Dictionary:
	var seen: Dictionary = {start: true}
	var pending: Array[Vector2i] = [start]
	var index: int = 0
	while index < pending.size():
		var at: Vector2i = pending[index]
		index += 1
		for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = at + direction
			if cells.has(next) and not seen.has(next) and not blocked.has(next):
				seen[next] = true
				pending.append(next)
	return seen

func solid(position_at: Vector2, size: Vector2, parent: Node = null) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.position = position_at
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	body.add_child(shape)
	(parent if parent else self).add_child(body)
	return body

func picture(asset: String, at: Vector2, collision_size: Vector2 = Vector2.ZERO, parent: Node = null) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = textures[asset]
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.position = at
	sprite.offset.y = -float(sprite.texture.get_height()) / 2.0 + 6.0
	(parent if parent else props).add_child(sprite)
	if collision_size != Vector2.ZERO:
		sprite.set_meta("body", solid(at, collision_size))
	return sprite

func text_at(value: String, at: Vector2, size: int = 10, tint: Color = Color("eee2bc")) -> Label:
	var label := Label.new()
	label.text = value
	label.position = at
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", tint)
	label.add_theme_color_override("font_shadow_color", Color("403e36"))
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.z_index = 2
	add_child(label)
	return label

func make_interaction(kind: String, title: String, at: Vector2, message: String = "") -> DormInteractable:
	var object: DormInteractable = INTERACT.new()
	object.kind = kind
	object.title = title
	object.message = message
	object.position = at
	props.add_child(object)
	interactions.objects.append(object)
	object.activated.connect(on_interaction)
	return object

func build_walls() -> void:
	var edges: Dictionary = {}
	for cell: Vector2i in cells:
		var point := Vector2(cell * TILE)
		if bounds == Rect2():
			bounds = Rect2(point, Vector2(TILE, TILE))
		else:
			bounds = bounds.expand(point + Vector2(TILE, TILE)).expand(point)
		for direction in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			if not cells.has(cell + direction):
				edges[cell + direction] = true
	for cell: Vector2i in edges:
		solid(Vector2(cell * TILE) + Vector2(8, 8), Vector2(16, 16))
		var sprite := Sprite2D.new()
		sprite.texture = textures.wall
		sprite.position = Vector2(cell * TILE) + Vector2(8, 0)
		sprite.z_index = 1
		add_child(sprite)

func build_rooms() -> void:
	for zone in zones:
		var area: Rect2 = zone.area
		var center := area.get_center()
		match zone.kind:
			"kitchen":
				add_partition(zone)
				picture("window", Vector2(center.x, area.position.y + 18))
				picture("radiator", Vector2(area.position.x + 24, area.position.y + 30), Vector2(28, 8))
				for x in [area.position.x + 22, area.end.x - 22]:
					var stove := Vector2(x, area.position.y + 60)
					var stove_art := picture("stove", stove, Vector2(28, 20))
					var inspect_stove := make_interaction("inspect", "Электроплита", stove, "Четыре конфорки и знакомый запах ужина.\nПосле готовки не забудьте выключить плиту.")
					inspect_stove.barrier = stove_art.get_meta("body")
				picture("sink", Vector2(area.end.x - 22, area.position.y + 97), Vector2(28, 20))
				picture("table", Vector2(area.position.x + 30, area.end.y - 26), Vector2(40, 20))
				text_at("КУХНЯ", Vector2(center.x - 22, area.position.y + 35), 9, Color("5a6860"))
			"loggia", "balcony":
				add_partition(zone)
				picture("window", Vector2(center.x, area.position.y + 20))
				if zone.kind == "loggia":
					picture("rack", Vector2(area.position.x + 24, area.end.y - 26), Vector2(24, 18))
					picture("rack", Vector2(area.end.x - 24, area.end.y - 26), Vector2(24, 18))
				make_interaction("inspect", "Вечер за окном", Vector2(center.x, area.position.y + 40), "В окнах соседнего корпуса загорается свет.\nВнизу шумит город, здесь сохнет бельё.")
			"elevator":
				var pair: bool = zone.id == "3"
				var positions: Array = [Vector2(center.x, area.position.y + 48)]
				if pair:
					positions = [Vector2(area.position.x + 28, area.position.y + 48), Vector2(area.end.x - 28, area.position.y + 48)]
				for at: Vector2 in positions:
					picture("elevator", at, Vector2(44, 14))
					make_interaction("elevator", "Вызвать лифт", at + Vector2(0, 18))
				picture("board", Vector2(center.x, area.position.y + 104), Vector2(42, 12))
				make_interaction("inspect", "Объявления", Vector2(center.x, area.position.y + 120), "8 ЭТАЖ · ИНФОРМАЦИЯ\nТихие часы: 23:00–07:00.\nКухню после себя оставляйте чистой.")
			"stairs":
				picture("stairs", Vector2(center.x, area.position.y + 68), Vector2(44, 48))
				make_interaction("stairs", "Лестница", Vector2(center.x, area.position.y + 88), "Переход между этажами будет доступен позже.")
			"classroom":
				add_partition(zone)
				picture("board", Vector2(center.x, area.position.y + 22), Vector2(40, 8))
				picture("table", center, Vector2(40, 20))
			"hall":
				picture("board", Vector2(area.position.x + 30, area.position.y + 38), Vector2(40, 10))
				make_interaction("inspect", "План этажа", Vector2(area.position.x + 30, area.position.y + 62), "Вы в центральном холле восьмого этажа.\nM — схема. В каждом крыле есть общая кухня.")
				text_at("ОБЩЕЖИТИЕ / 08", area.position + Vector2(60, 12), 11)
				text_at("← ЗАПАД     ВОСТОК →", area.position + Vector2(24, area.size.y * .52), 8, Color("68786e"))
		# Lights are floor-mounted overhead representations; no collision.
		if zone.kind == "corridor":
			var horizontal: bool = area.size.x > area.size.y
			var length: float = area.size.x if horizontal else area.size.y
			for step in range(48, int(length), 112):
				var at := Vector2(area.position.x + step, center.y - 24) if horizontal else Vector2(center.x - 24, area.position.y + step)
				picture("lamp", at)
				if step % 224 == 48:
					picture("radiator", at + Vector2(0, 16), Vector2(28, 8))

func add_partition(zone: Dictionary) -> void:
	var area: Rect2 = zone.area
	var sides: Array = []
	var origin := Vector2i(area.position / TILE)
	var size := Vector2i(area.size / TILE)
	for direction: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var line: Array[Vector2i] = []
		var length: int = size.x if direction.y != 0 else size.y
		for i in range(length):
			var cell := origin + (Vector2i(i, 0 if direction.y == -1 else size.y - 1) if direction.y != 0 else Vector2i(0 if direction.x == -1 else size.x - 1, i))
			if cells.has(cell + direction):
				line.append(cell)
		if line.size() >= 3:
			sides.append({"line": line, "direction": direction})
	if sides.is_empty():
		return
	# Keep the longest shared edge, with a two-tile, 32 px doorway.
	sides.sort_custom(func(a, b): return a.line.size() > b.line.size())
	var selected: Dictionary = sides[0]
	var line: Array = selected.line
	var middle: int = int(line.size() / 2)
	var direction: Vector2i = selected.direction
	var door_at := Vector2(line[middle] * TILE) + Vector2(8, 8)
	for side in sides:
		for i in range(side.line.size()):
			var cell: Vector2i = side.line[i]
			if side == selected and (i == middle or i == middle - 1):
				door_cells.append(cell)
				continue
			solid(Vector2(cell * TILE) + Vector2(8, 8), Vector2(16, 16))
			picture("wall", Vector2(cell * TILE) + Vector2(8, 16))
	var door_center := door_at - (Vector2(8, 0) if direction.y != 0 else Vector2(0, 8))
	var obj := make_interaction("door", "Дверь · " + str(zone.label), door_center)
	obj.barrier = solid(Vector2.ZERO, Vector2(32, 8) if direction.y != 0 else Vector2(8, 32), obj)
	obj.art = picture("door", Vector2.ZERO, Vector2.ZERO, obj)
	if direction.x != 0:
		obj.art.rotation = PI / 2.0
		obj.art.offset = Vector2.ZERO
	obj.title = "Открыть · " + str(zone.label)
	door_records.append({"object": obj, "zone": zone.id})

func build_blocks() -> void:
	var number: int = 801
	for zone in zones:
		if zone.kind != "block":
			continue
		var area: Rect2 = zone.area
		var nearest_cell := Vector2i.ZERO
		var nearest_point := Vector2.ZERO
		var best: float = INF
		for cell: Vector2i in cells:
			var point := Vector2(cell * TILE) + Vector2(8, 8)
			var edge := Vector2(clampf(point.x, area.position.x, area.end.x), clampf(point.y, area.position.y, area.end.y))
			var distance := point.distance_to(edge)
			if distance < best:
				best = distance
				nearest_cell = cell
				nearest_point = edge
		if best > 48:
			continue
		var at := Vector2(nearest_cell * TILE) + Vector2(8, 8)
		var direction := (nearest_point - at).normalized()
		var object := make_interaction("locked", "Блок " + str(number), at, "Комната закрыта")
		var door_art := picture("door", at + direction * 12)
		if absf(direction.x) > absf(direction.y):
			door_art.rotation = PI / 2.0
		text_at(str(number), at + Vector2(-10, -21), 8)
		number += 1

func _draw() -> void:
	# Tile floor is independent of furniture and wall collision nodes.
	for zone in zones:
		if zone.kind == "block":
			draw_rect(zone.area, Color("344249"))
			draw_rect(zone.area.grow(-4), Color("3b4c51"), false, 2)
	for cell: Vector2i in cells:
		var area := Rect2(Vector2(cell * TILE), Vector2(TILE, TILE))
		var kind: String = cells[cell]
		draw_texture_rect(textures.terrazzo if kind in ["hall", "elevator"] else textures.floor, area, false)
		if kind in ["loggia", "balcony"]:
			draw_rect(area, Color(0.52, 0.75, 0.52, .20))
	for zone in zones:
		if zone.kind in ["kitchen", "loggia", "balcony"]:
			var area: Rect2 = zone.area
			draw_rect(Rect2(area.position + Vector2(6, 8), Vector2(area.size.x - 12, 44)), Color(.95, .67, .40, .12))

func on_interaction(object: DormInteractable) -> void:
	match object.kind:
		"door":
			if object.blocked_by_player:
				toast("Отойдите от дверного проёма, чтобы закрыть дверь.")
				return
			object.title = ("Закрыть" if object.opened else "Открыть") + " дверь"
			play_tone(180.0 if object.opened else 130.0, .12)
		"elevator":
			play_tone(660.0, .13)
			open_modal("ЛИФТ / 08", "Текущий этаж — 8.\nДругие этажи появятся позже.", true)
		"stairs":
			open_modal("ЛЕСТНИЦА", object.message)
		_:
			toast(object.message, 5.0)

func _process(delta: float) -> void:
	elapsed += delta
	notice_time -= delta
	if is_instance_valid(notice):
		notice.visible = notice_time > 0
	if not is_instance_valid(player) or not is_instance_valid(prompt):
		return
	if not get_tree().paused:
		var object := interactions.nearest()
		prompt.text = "[ E ]  " + object.title if object else ""
		prompt.visible = object != null
		for zone in zones:
			if zone.kind != "block" and zone.area.has_point(player.position):
				var names := {"hall": "Центральный холл", "corridor": "Жилое крыло", "kitchen": "Общая кухня", "elevator": "Лифтовая", "stairs": "Лестничная клетка", "loggia": "Лоджия", "balcony": "Балкон", "classroom": "Аудитория"}
				location_label.text = str(floor_id) + " ЭТАЖ   /   " + str(names.get(zone.kind, "Общежитие"))
				break
		update_steps(delta)
	if show_map:
		map_canvas.queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("Escape"):
		if modal.visible or show_map:
			close_modal()
		else:
			open_modal("ПАУЗА", "Вечер в общежитии\nWASD / стрелки — движение\nE — взаимодействие · M — схема этажа")
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_M:
		if show_map:
			close_modal()
		elif not modal.visible:
			show_map = true
			map_panel.show()
			get_tree().paused = true
	elif not get_tree().paused and event.is_action_pressed("Enter"):
		var object := interactions.nearest()
		if object:
			object.interact()
		get_viewport().set_input_as_handled()

func panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("23363bee")
	style.border_color = Color("a7ad88")
	style.set_border_width_all(1)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style

func ui_label(value: String, size: int) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color("ede8cc"))
	return label

func build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "DormUI"
	add_child(layer)
	var top := PanelContainer.new()
	top.position = Vector2(16, 14)
	top.add_theme_stylebox_override("panel", panel_style())
	layer.add_child(top)
	var stack := VBoxContainer.new()
	top.add_child(stack)
	stack.add_child(ui_label("D O R M   L I F E", 13))
	location_label = ui_label("8 ЭТАЖ / ЦЕНТРАЛЬНЫЙ ХОЛЛ", 10)
	stack.add_child(location_label)
	var help := ui_label("WASD / ↑↓←→   ·   E действие   ·   M схема   ·   Esc пауза", 10)
	help.position = Vector2(16, 337)
	layer.add_child(help)
	prompt = ui_label("", 12)
	prompt.position = Vector2(170, 288)
	prompt.add_theme_color_override("font_shadow_color", Color("1d3033"))
	prompt.add_theme_constant_override("shadow_outline_size", 4)
	layer.add_child(prompt)
	notice = ui_label("", 11)
	notice.position = Vector2(18, 92)
	notice.add_theme_color_override("font_shadow_color", Color("1d3033"))
	notice.add_theme_constant_override("shadow_outline_size", 4)
	layer.add_child(notice)
	modal = PanelContainer.new()
	modal.position = Vector2(148, 104)
	modal.custom_minimum_size = Vector2(344, 150)
	modal.add_theme_stylebox_override("panel", panel_style())
	layer.add_child(modal)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	modal.add_child(column)
	modal_title = ui_label("", 16)
	column.add_child(modal_title)
	modal_text = ui_label("", 12)
	column.add_child(modal_text)
	modal_actions = VBoxContainer.new()
	column.add_child(modal_actions)
	var close := Button.new()
	close.text = "Продолжить · Esc"
	close.add_theme_font_size_override("font_size", 12)
	close.pressed.connect(close_modal)
	column.add_child(close)
	modal.hide()
	map_panel = PanelContainer.new()
	map_panel.position = Vector2(110, 30)
	map_panel.custom_minimum_size = Vector2(420, 295)
	map_panel.add_theme_stylebox_override("panel", panel_style())
	layer.add_child(map_panel)
	var map_box := VBoxContainer.new()
	map_panel.add_child(map_box)
	map_box.add_child(ui_label("08 / СХЕМА ОБЩЕЖИТИЯ", 14))
	var canvas_space := Control.new()
	canvas_space.custom_minimum_size = Vector2(380, 215)
	map_box.add_child(canvas_space)
	map_canvas = Node2D.new()
	canvas_space.add_child(map_canvas)
	map_canvas.draw.connect(draw_map)
	map_box.add_child(ui_label("● Вы здесь   ▪ Кухни   ▪ Лоджия     M / Esc — закрыть", 10))
	map_panel.hide()

func draw_map() -> void:
	var scale_at: float = minf(370.0 / bounds.size.x, 205.0 / bounds.size.y)
	var shift := Vector2(190, 105) - bounds.get_center() * scale_at
	for zone in zones:
		var area: Rect2 = zone.area
		var colors := {"block": Color("435960"), "kitchen": Color("dab17c"), "loggia": Color("9dbd97"), "elevator": Color("a9bcb1")}
		map_canvas.draw_rect(Rect2(shift + area.position * scale_at, area.size * scale_at), colors.get(zone.kind, Color("bdc6b2")))
	map_canvas.draw_circle(shift + player.position * scale_at, 3, Color("fa8f63"))

func toast(value: String, duration: float = 4.0) -> void:
	notice.text = value
	notice_time = duration

func open_modal(title: String, body: String, elevator: bool = false) -> void:
	modal_title.text = title
	modal_text.text = body
	for child in modal_actions.get_children():
		child.queue_free()
	if elevator:
		var row := HBoxContainer.new()
		modal_actions.add_child(row)
		for floor_number in range(1, 15):
			var button := Button.new()
			button.text = str(floor_number)
			button.add_theme_font_size_override("font_size", 9)
			button.disabled = floor_number != floor_id
			button.tooltip_text = "Другие этажи появятся позже" if floor_number != floor_id else "Вы на этом этаже"
			button.pressed.connect(func(): modal_text.text = "Вы уже на восьмом этаже.")
			row.add_child(button)
	modal.show()
	get_tree().paused = true
	prompt.hide()

func close_modal() -> void:
	modal.hide()
	map_panel.hide()
	show_map = false
	get_tree().paused = false

var hum: AudioStreamPlayer
var effects: AudioStreamPlayer
var step_time: float = 0.0

func tone(frequency: float, duration: float, volume: float = .2) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	var count: int = int(22050 * duration)
	for i in range(count):
		var envelope: float = minf(float(i) / 100.0, 1.0) * (1.0 - float(i) / count)
		var value: int = int(sin(TAU * frequency * i / 22050.0) * envelope * volume * 32767)
		bytes.append(value & 255)
		bytes.append((value >> 8) & 255)
	var sound := AudioStreamWAV.new()
	sound.format = AudioStreamWAV.FORMAT_16_BITS
	sound.mix_rate = 22050
	sound.data = bytes
	return sound

func setup_audio() -> void:
	hum = AudioStreamPlayer.new()
	hum.stream = tone(100, 2.0, .025)
	hum.volume_db = -22
	add_child(hum)
	hum.finished.connect(func(): hum.play())
	hum.play()
	effects = AudioStreamPlayer.new()
	effects.volume_db = -16
	add_child(effects)

func play_tone(frequency: float, duration: float) -> void:
	effects.stream = tone(frequency, duration)
	effects.play()

func update_steps(delta: float) -> void:
	step_time -= delta
	if player.velocity.length() > 10 and step_time <= 0:
		play_tone(95 + int(elapsed * 17) % 30, .055)
		step_time = .31

func stop_audio() -> void:
	if is_instance_valid(hum):
		hum.stop()
		hum.stream = null
	if is_instance_valid(effects):
		effects.stop()
		effects.stream = null

func _exit_tree() -> void:
	stop_audio()

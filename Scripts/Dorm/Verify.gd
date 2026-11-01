extends SceneTree

var failures: Array[String] = []
var checks: int = 0

func check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS ", description)
	else:
		failures.append(description)
		push_error("FAIL " + description)

func _initialize() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	var level = load("res://Scenes/Levels/DormFloor08.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	await process_frame
	await physics_frame
	check(level.floor_id == 8, "Floor 8 is the main scene")
	check(level.flood(Vector2i(16,14)).size() == level.cells.size(), "All public floor cells connected")
	check(level.door_records.size() >= 5, "Kitchens and public room doors exist")
	check(level.player.sprite.sprite_frames.has_animation("Walk"), "Upstream Walk animation retained")
	var start: Vector2 = level.player.position
	Input.action_press("MoveDown")
	for i in range(20):
		await physics_frame
	Input.action_release("MoveDown")
	await physics_frame
	check(level.player.position.distance_to(start) > 15, "Player moves through physics/FSM")
	check(level.player.get_node("AnimationPlayer").has_animation("Idle"), "Upstream animation library retained")
	for record in level.door_records:
		var object = record.object
		if record.number == 812:
			check(object.kind == "block_entry" and not object.opened and object.barrier.collision_layer == 1, str(record.number) + " facade stays solid and opens a separate scene")
			continue
		if record.locked:
			object.interact()
			check(not object.opened and object.barrier.collision_layer == 1 and object.message == "Комната закрыта", "Residential block remains locked: " + record.zone)
			continue
		check(object.barrier.collision_layer == 1, "Door starts solid: " + record.zone)
		object.interact()
		check(object.opened and object.barrier.collision_layer == 0, "Door opens passage: " + record.zone)
		object.interact()
		check(not object.opened and object.barrier.collision_layer == 1, "Door closes passage: " + record.zone)
	await check_architecture(level)
	await check_revision(level)
	# Actual character sweep into a solid exterior wall.
	level.player.position = Vector2(190, 116)
	Input.action_press("MoveUp")
	for i in range(40):
		await physics_frame
	Input.action_release("MoveUp")
	await physics_frame
	check(level.player.position.y > 82, "Exterior wall stops player")
	level.open_modal("ЛИФТ / 08", "Другие этажи появятся позже", true)
	check(paused and level.modal.visible, "Elevator pauses movement and opens panel")
	var row = level.modal_actions.get_child(0)
	check(row.get_child_count() == 14, "14 elevator destinations shown")
	var enabled: int = 0
	for button in row.get_children():
		if not button.disabled:
			enabled += 1
	check(enabled == 1, "Only current floor available")
	if DisplayServer.get_name() != "headless":
		await process_frame
		RenderingServer.force_draw.call_deferred()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://docs/preview_elevator_ui.png")
	level.close_modal()
	check(not paused, "Closing panel resumes game")
	var kitchen_door = null
	for record in level.door_records:
		if record.zone == "7":
			kitchen_door = record.object
	level.player.position = Vector2(720, 330)
	Input.action_press("MoveUp")
	for i in range(20):
		await physics_frame
	Input.action_release("MoveUp")
	await physics_frame
	check(level.player.position.y > 290, "Closed kitchen door stops character sweep")
	check(level.interactions.nearest() == kitchen_door, "E targets nearby kitchen door through ray query")
	kitchen_door.interact()
	Input.action_press("MoveUp")
	for i in range(18):
		await physics_frame
	Input.action_release("MoveUp")
	await physics_frame
	check(level.player.position.y < 280, "Character walks through opened kitchen doorway")
	for object in level.interactions.objects:
		if object.title == "Электроплита":
			level.player.position = object.position + Vector2(0,28)
			await physics_frame
			check(level.interactions.nearest() == object, "Inspect furniture ray permits its own collision")
			object.interact()
			check(level.notice.text.contains("конфорки"), "Kitchen inspection displays description")
			break
	# Exercise the existing input handlers and bindings.
	for pair in [["MoveLeft", KEY_A, KEY_LEFT], ["MoveRight", KEY_D, KEY_RIGHT], ["MoveUp", KEY_W, KEY_UP], ["MoveDown", KEY_S, KEY_DOWN], ["Enter", KEY_E, KEY_E]]:
		for key in [pair[1], pair[2]]:
			var bound := false
			for event in InputMap.action_get_events(pair[0]):
				if event is InputEventKey and event.physical_keycode == key:
					bound = true
			check(bound, "Keyboard binding " + str(pair[0]) + " " + str(key))
	var map_key := InputEventKey.new()
	map_key.physical_keycode = KEY_M
	map_key.pressed = true
	level._unhandled_input(map_key)
	check(paused and level.show_map and level.map_panel.visible, "M opens map and pauses")
	var escape := InputEventAction.new()
	escape.action = "Escape"
	escape.pressed = true
	level._unhandled_input(escape)
	check(not paused and not level.show_map, "Esc closes map")
	level._unhandled_input(escape)
	check(paused and level.modal.visible, "Esc opens pause")
	level._unhandled_input(escape)
	check(not paused and not level.modal.visible, "Esc resumes game")
	check(level.player.get_node("Camera2D").enabled and level.player.get_node("Camera2D").position_smoothing_enabled, "Following camera retained")
	level.player.position = Vector2(720, 330)
	await physics_frame
	await physics_frame
	var e_key := InputEventAction.new()
	e_key.action = "Enter"
	e_key.pressed = true
	var was_open: bool = kitchen_door.opened
	level._unhandled_input(e_key)
	check(kitchen_door.opened != was_open, "E handler toggles nearby door")
	level.player.position = Vector2(256, 232)
	# Full physics occupancy search, including walls, furniture and opened doors.
	for record in level.door_records:
		if record.object.kind == "door" and not record.object.opened:
			record.object.interact()
	await physics_frame
	var free: Dictionary = {}
	var circle := CircleShape2D.new()
	circle.radius = level.player.get_node("BodyCollisionShape").shape.radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = circle
	query.collision_mask = 1
	query.exclude = [level.player.get_rid()]
	for cell: Vector2i in level.cells:
		query.transform = Transform2D(0, Vector2(cell * 16) + Vector2(8,8))
		if level.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty():
			free[cell] = true
	var seen: Dictionary = {Vector2i(16,14): true}
	var queue: Array[Vector2i] = [Vector2i(16,14)]
	var index: int = 0
	while index < queue.size():
		var cell: Vector2i = queue[index]
		index += 1
		for direction in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var next: Vector2i = cell + direction
			if free.has(next) and not seen.has(next):
				seen[next] = true
				queue.append(next)
	for zone in level.zones:
		if zone.kind == "block":
			continue
		var reached: bool = false
		for cell: Vector2i in seen:
			if zone.area.grow(-16).has_point(Vector2(cell * 16) + Vector2(8,8)):
				reached = true
				break
		check(reached, "Physics route reaches " + zone.kind + " " + zone.id)
	for object in level.interactions.objects:
		var usable := false
		for cell: Vector2i in seen:
			var at := Vector2(cell * 16) + Vector2(8, 1)
			if at.distance_to(object.position) >= 46:
				continue
			level.player.position = at
			if level.interactions.nearest() == object:
				usable = true
				break
		check(usable, "Reachable interaction: " + object.title + " at " + str(object.position))
		if usable and object.kind == "elevator":
			var event := InputEventAction.new()
			event.action = "Enter"
			event.pressed = true
			level._unhandled_input(event)
			check(paused and level.modal.visible, "E operates reachable elevator at " + str(object.position))
			level.close_modal()
	var lift_count := 0
	for object in level.interactions.objects:
		if object.kind == "elevator":
			lift_count += 1
	check(lift_count == 4, "Exactly four elevators in two rooms")
	check_radiators(level)
	if DisplayServer.get_name() != "headless":
		await check_render(level)
	level.close_modal()
	level.stop_audio()
	await create_timer(.15).timeout
	level.queue_free()
	await process_frame
	await process_frame
	await check_closed_blocks()
	await check_block812()
	await create_timer(.2).timeout
	print("VERIFY_COMPLETE checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func physics_hit(level, at: Vector2, size: Vector2 = Vector2(1, 1)) -> bool:
	var query := PhysicsShapeQueryParameters2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	query.shape = shape
	query.transform = Transform2D(0, at)
	query.collision_mask = 1
	return not level.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()

func check_architecture(level) -> void:
	var unique: Dictionary = {}
	for wall in level.wall_records:
		check(not unique.has(wall.key), "Unique wall segment " + str(wall.key))
		unique[wall.key] = true
		check(wall.body.position.is_equal_approx(wall.art.position) and wall.art.get_rect().size * wall.art.scale == wall.body.get_child(0).shape.size, "Wall art matches collider " + str(wall.key))
	for record in level.door_records:
		var obj = record.object
		var axis := Vector2.RIGHT if record.keys[0].z == 1 else Vector2.DOWN
		var at: Vector2 = obj.position
		check(obj.art.position == Vector2.ZERO and obj.art.offset == Vector2.ZERO, "Door art anchored to collider " + record.zone)
		for key in record.keys:
			check(level.wall_edges.has(key) and level.openings.get(key) == record.zone and not unique.has(key), "Door replaces wall, without overlapping wall " + record.zone)
		check(physics_hit(level, at), "Closed door physically occupies opening " + record.zone)
		if record.locked:
			continue
		obj.interact()
		await physics_frame
		check(not physics_hit(level, at), "Opened doorway has no invisible obstacle " + record.zone)
		# Use the real player collider; its center is seven pixels below its root.
		level.player.position = at - Vector2(0, 7)
		await physics_frame
		await physics_frame
		obj.interact()
		check(obj.opened and obj.blocked_by_player, "Cannot close on player " + record.zone)
		level.player.position = Vector2(256, 232)
		await physics_frame
		await physics_frame
		obj.interact()
		check(not obj.opened, "Can close after player leaves " + record.zone)
		# Sweep across the doorway from a free side, with closed and open state.
		var origin: Vector2 = at - axis * 22 - Vector2(0, 7)
		var target := Transform2D(0, origin)
		var hit := KinematicCollision2D.new()
		check(level.player.test_move(target, axis * 44, hit) and hit.get_collider() == obj.barrier, "Closed door stops real player sweep " + record.zone)
		obj.interact()
		await physics_frame
		check(not level.player.test_move(target, axis * 44), "Open door permits real player sweep " + record.zone)
		obj.interact()
	# Every perimeter segment is physically present, including both lift rooms.
	await physics_frame
	for zone in level.zones:
		if not zone.has("entrance"):
			continue
		var intact := true
		for direction in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			for key in level.perimeter(zone, direction):
				if not physics_hit(level, level.edge_center(key)):
					intact = false
		check(intact, "Closed room has no perimeter bypass " + zone.kind + " " + zone.id)
	# Check every exterior floor edge against the live physics space.
	var enclosed := true
	for cell: Vector2i in level.cells:
		for direction in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			if not level.cells.has(cell + direction):
				if not physics_hit(level, level.edge_center(level.edge_key(cell, direction))):
					enclosed = false
	check(enclosed, "All exterior edges stop escape from floor")
	# No authored public rectangles overlap protected rooms or residential blocks.
	for zone in level.zones:
		if not zone.has("entrance") and zone.kind != "block":
			continue
		var clear := true
		for other in level.zones:
			if other.id != zone.id and zone.area.intersects(other.area):
				clear = false
		check(clear, "No zone overlap " + zone.id)
	# Furniture visual bounds (including legacy sprite offsets) stay inside the room.
	for zone in level.zones:
		if not zone.has("entrance"):
			continue
		var contained := true
		var furniture: Array[Rect2] = []
		for child in level.props.get_children():
			if child is Sprite2D and child.has_meta("body") and zone.area.has_point(child.position):
				var rect: Rect2 = child.transform * child.get_rect()
				if not zone.area.encloses(rect):
					contained = false
				for previous in furniture:
					if previous.intersects(rect):
						contained = false
				furniture.append(rect)
		check(contained, "Furniture art contained and separated " + zone.id)
	level.player.position = Vector2(256, 232)

func capture(level, title: String, at: Vector2) -> Image:
	level.player.position = at
	level.player.get_node("Camera2D").reset_smoothing()
	level.notice_time = 0
	for i in range(3):
		await process_frame
	RenderingServer.force_draw.call_deferred()
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	if not title.is_empty():
		# Windows preview/indexing may briefly hold the previous image open.
		var path := "res://docs/preview_" + title + ".png"
		var output: FileAccess
		for attempt in range(10):
			output = FileAccess.open(path, FileAccess.WRITE)
			if output != null:
				break
			await create_timer(.1).timeout
		check(output != null, "Screenshot writable " + title)
		if output != null:
			output.store_buffer(frame.save_png_to_buffer())
			output.close()
	return frame

func check_render(level) -> void:
	level.player.position = Vector2(256, 232)
	await physics_frame
	await physics_frame
	for record in level.door_records:
		if record.object.opened:
			record.object.interact()
	await physics_frame
	for target in [["hall", Vector2(256, 232)], ["elevator_3", Vector2(408, 208)], ["elevator_26", Vector2(104, 448)], ["classroom", Vector2(120, 240)], ["kitchen", Vector2(720, 220)], ["loggia", Vector2(136, 142)], ["balcony_4", Vector2(408, 440)], ["balcony_6", Vector2(1112, 344)], ["balcony_9", Vector2(-600, 328)], ["balcony_13", Vector2(264, 1256)], ["balcony_22", Vector2(264, -656)], ["corridor", Vector2(864, 344)]]:
		await capture(level, target[0], target[1])
	var radiator_views := {}
	for record in level.radiator_records:
		if record.zone in ["8", "12", "5", "21"] and not radiator_views.has(record.zone):
			radiator_views[record.zone] = true
			await capture(level, "radiator_" + record.zone, record.art.position - Vector2(record.direction)*40 - Vector2(0,7))
	for id in ["3", "26", "27"]:
		for record in level.door_records:
			if record.zone != id:
				continue
			var obj = record.object
			level.player.hide()
			var shown: Image = await capture(level, "door_" + id, obj.position + Vector2(40, 0))
			obj.art.hide()
			await process_frame
			RenderingServer.force_draw.call_deferred()
			await RenderingServer.frame_post_draw
			var hidden := root.get_texture().get_image()
			obj.art.show()
			level.player.show()
			var changed := 0
			for y in range(shown.get_height()):
				for x in range(shown.get_width()):
					if shown.get_pixel(x,y) != hidden.get_pixel(x,y):
						changed += 1
			check(changed >= 100, "Door visible in actual raster " + id + " pixels=" + str(changed))
	level.show_map = true
	level.map_panel.show()
	level.map_canvas.queue_redraw()
	await capture(level, "map", Vector2(256,232))
	level.show_map = false
	level.map_panel.hide()
	# A/B render comparison: hide only the player and count changed world pixels.
	# This verifies actual raster visibility at each window, rather than z values alone.
	for record in level.window_records:
		var art: Sprite2D = record.art
		var normal := Vector2.DOWN if is_zero_approx(art.rotation) else Vector2.RIGHT
		var samples: int = 0
		for sign_at in [-1, 1]:
			for slide in [-12, 0, 12]:
				var at: Vector2 = art.position + normal * sign_at * 20 + normal.orthogonal() * slide - Vector2(0, 7)
				var feet: Vector2 = at + Vector2(0, 7)
				var cell := Vector2i(floor(feet.x / 16), floor(feet.y / 16))
				if not level.cells.has(cell) or physics_hit(level, feet, Vector2(17, 17)):
					continue
				level.player.show()
				var shown: Image = await capture(level, "window_" + record.zone if slide == 0 else "", at)
				level.player.hide()
				await process_frame
				RenderingServer.force_draw.call_deferred()
				await RenderingServer.frame_post_draw
				var hidden := root.get_texture().get_image()
				level.player.show()
				var changed: int = 0
				var screen_at: Vector2 = level.player.get_global_transform_with_canvas().origin
				for y in range(maxi(0, int(screen_at.y) - 32), mini(shown.get_height(), int(screen_at.y) + 32)):
					for x in range(maxi(0, int(screen_at.x) - 24), mini(shown.get_width(), int(screen_at.x) + 24)):
						if shown.get_pixel(x, y) != hidden.get_pixel(x, y):
							changed += 1
				check(changed >= 70, "Player rendered beside window " + record.zone + " offset=" + str(slide) + " pixels=" + str(changed))
				samples += 1
		check(samples > 0, "Window has tested walkable viewpoint " + record.zone)

func check_revision(level) -> void:
	var by_id: Dictionary = {}
	for zone in level.zones:
		by_id[zone.id] = zone
	var expected := {"9": Vector2i.LEFT, "6": Vector2i.RIGHT, "22": Vector2i.UP, "13": Vector2i.DOWN, "28": Vector2i.LEFT, "4": Vector2i.RIGHT}
	for id in expected:
		var found: Array = level.window_records.filter(func(r): return r.zone == id)
		check(found.size() == 1 and found[0].direction == expected[id], "Authored exterior window direction " + id)
		if found.is_empty():
			continue
		var art: Sprite2D = found[0].art
		check(by_id[id].area.grow(4.01).encloses(art.transform * art.get_rect()), "Window stays within wall footprint " + id)
		var clear := true
		for door in level.door_records:
			if door.zone == id and art.position.distance_to(door.object.position) < 40:
				clear = false
		check(clear, "Window separated from entrance " + id)
	for id in ["3", "26"]:
		var lifts: Array = level.elevator_records.filter(func(r): return r.zone == id)
		var side: String = "east" if id == "3" else "west"
		check(lifts.size() == 2, "Two lifts in room " + id)
		var boxes: Array[Rect2] = []
		for lift in lifts:
			var area: Rect2 = by_id[id].area
			var box: Rect2 = lift.art.transform * lift.art.get_rect()
			check(lift.side == side and area.grow(-3).encloses(box), "Lift faces inward and stays inside " + id)
			var edge: float = area.end.x - box.end.x if side == "east" else box.position.x - area.position.x
			check(is_equal_approx(edge, 4), "Lift mounted along authored wall " + id)
			check(lift.body.get_child(0).shape.size.is_equal_approx(box.size), "Lift art matches collision " + id)
			for previous in boxes:
				check(not previous.intersects(box), "Lift cabins separated " + id)
			boxes.append(box)
			check(not physics_hit(level, lift.object.position, Vector2(17, 17)), "Lift interaction point free " + id)
		var doors: Array = level.door_records.filter(func(r): return r.zone == id)
		check(doors.size() == 1 and not doors[0].locked and doors[0].object.art.visible, "Single visible lift entrance " + id)
	check(by_id["26"].area.size == Vector2(144,160), "Second lift room expanded south by 32 pixels")
	var classroom: Array = level.door_records.filter(func(r): return r.zone == "27")
	check(classroom.size() == 1 and classroom[0].object.position.x == by_id["27"].area.end.x, "Classroom has single east entrance")
	for id in ["3", "26", "27"]:
		var door = level.door_records.filter(func(r): return r.zone == id)[0].object
		var outward := Vector2.LEFT if by_id[id].entrance == "left" else Vector2.RIGHT
		level.player.position = door.position + outward * 14 - Vector2(0,7)
		await physics_frame
		check(level.interactions.nearest() == door, "Hall approach targets entrance with E " + id)
		var event := InputEventAction.new()
		event.action = "Enter"
		event.pressed = true
		level._unhandled_input(event)
		check(door.opened, "E opens room entrance " + id)
		level._unhandled_input(event)
		check(not door.opened, "E closes room entrance " + id)
	level.player.position = Vector2(256,232)
	var route: Array = ["36","35","34","33","32","31","51","52","53","57","56","55","54","38","39","40","41","43","42","37","44","45","46","47","48","49","50"]
	var numbers: Array = []
	for record in level.door_records:
		if record.locked:
			check(record.number == 800 + route.find(record.zone), "Explicit route number " + record.zone)
			check(record.object.title == ("Войти в блок " + str(record.number) if record.number == 812 else "Блок " + str(record.number)) and record.object.get_meta("number_label").text == str(record.number), "Door prompt and label share block number " + record.zone)
			numbers.append(record.number)
	numbers.sort()
	check(numbers == range(800,827), "Unique contiguous numbers 800 to 826")
	check(by_id["36"].area.position.x < by_id["29"].area.position.x and by_id["36"].area.position.y < by_id["29"].area.end.y and by_id["36"].area.end.y > by_id["29"].area.position.y, "Block 800 faces staircase across north corridor")
	# Instantiate the real generator with reversed source order, not a duplicate numbering algorithm.
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(level.floor_data_path))
	data.zones.reverse()
	var path := "user://verify_reversed_floor.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	var reversed = load("res://Scenes/Levels/DormFloor08.tscn").instantiate()
	reversed.floor_data_path = path
	root.add_child(reversed)
	await physics_frame
	var stable := true
	for record in reversed.door_records:
		if record.locked and record.number != 800 + route.find(record.zone):
			stable = false
	check(stable, "Real generation keeps numbers with reversed JSON zone order")
	reversed.stop_audio()
	reversed.queue_free()
	await process_frame
	DirAccess.remove_absolute(path)

func wait_for_scene(path: String) -> void:
	for i in range(120):
		await process_frame
		if is_instance_valid(current_scene) and current_scene.scene_file_path == path and not root.get_node("DormTransition").busy:
			await physics_frame
			return
	check(false, "Scene transition timed out: " + path)

func check_closed_blocks() -> void:
	var transition = root.get_node("DormTransition")
	var level = load(transition.FLOOR).instantiate()
	root.add_child(level)
	current_scene = level
	await physics_frame
	var entries: Array = level.door_records.filter(func(r): return r.object.kind == "block_entry")
	check(entries.size() == 1 and entries[0].number == 812 and entries[0].zone == "54", "Only zone 54 / block 812 has an interior route")
	for number in [813,818]:
		var record = level.door_records.filter(func(r): return r.number == number)[0]
		check(record.zone == ("38" if number == 813 else "42"), "Closed block retains zone identity " + str(number))
		level.player.position = record.object.position + Vector2(-28,-7) if number == 813 else record.object.position + Vector2(28,-7)
		await physics_frame
		var input := InputEventAction.new()
		input.action = "Enter"
		input.pressed = true
		level._unhandled_input(input)
		record.object.interact()
		transition.enter_block(Vector2.ZERO, Vector2.RIGHT, number)
		await process_frame
		check(current_scene == level and not transition.busy and record.object.kind == "locked" and record.object.barrier.collision_layer == 1 and not record.object.opened, "E and direct routing reject closed block " + str(number))
	transition.enter_block(Vector2.ZERO,Vector2.RIGHT,999)
	check(not transition.busy, "Unknown block has no fallback interior")
	level.stop_audio()
	level.queue_free()
	await process_frame


func check_radiators(level) -> void:
	var covered := {}
	for record in level.radiator_records:
		covered[record.zone] = true
		var art: Sprite2D = record.art
		var normal := Vector2(record.direction)
		check(art.position.is_equal_approx(record.wall_at-normal*9), "Radiator follows wall inner face " + record.zone)
		var visual: Rect2 = art.transform * art.get_rect()
		check(visual.is_equal_approx(record.box), "Radiator art matches physical bounds " + record.zone)
		var shape: CollisionShape2D = record.body.get_child(0)
		check(shape.shape.size == record.box.size and record.body.position == record.box.get_center(), "Radiator collision matches footprint " + record.zone)
		for door in level.door_records:
			var door_shape: CollisionShape2D = door.object.barrier.get_child(0)
			var box: Rect2 = door_shape.global_transform * door_shape.shape.get_rect()
			check(not record.box.intersects(box.grow(20)), "Radiator keeps doorway approach free " + record.zone + "/" + door.zone)
		var clear := true
		for other in level.find_children("*", "CollisionShape2D", true, false):
			if other.get_parent() == record.body or other.shape == null:
				continue
			var occupied: Rect2 = other.global_transform * other.shape.get_rect()
			clear = clear and not record.box.intersects(occupied)
		check(clear, "Radiator does not overlap physical objects " + record.zone)
	for zone in level.zones:
		if zone.kind == "corridor":
			check(covered.has(zone.id), "Wall radiators cover corridor " + zone.id)

func check_block812() -> void:
	var transition = root.get_node("DormTransition")
	var floor_scene = load(transition.FLOOR).instantiate()
	root.add_child(floor_scene)
	current_scene = floor_scene
	await physics_frame
	var entries: Array = floor_scene.door_records.filter(func(r): return r.number == 812)
	check(entries.size() == 1 and entries[0].zone == "54", "812 belongs to zone 42, independent of array order")
	var entry = entries[0].object
	var return_at: Vector2 = entry.get_meta("return_position")
	floor_scene.player.position = return_at
	floor_scene.player.restore_facing(Vector2.DOWN)
	await physics_frame
	check(floor_scene.interactions.nearest() == entry, "812 facade is accessible from existing corridor")
	var input := InputEventAction.new()
	input.action = "Enter"
	input.pressed = true
	floor_scene._unhandled_input(input)
	await wait_for_scene(transition.BLOCK812)
	var room = current_scene
	check(room.scene_file_path == transition.BLOCK812, "E enters 812 rather than 813")
	check(get_nodes_in_group("Player").size() == 1, "812 has one unchanged player")
	check(room.scale == Vector2.ONE, "812 uses real geometry, no scene scaling")
	check(room.bounds.size == Vector2(420,348), "812 shell is 420 x 348")
	check(room.room_areas["Б"].size == Vector2(408,150) and room.room_areas["А"].size == Vector2(228,174), "Compact bedrooms have authored dimensions")
	var camera: Camera2D = room.player.get_node("Camera2D")
	check(camera.zoom == Vector2(1.5,1.5) and camera.position_smoothing_enabled, "812 camera shows 33 percent more linear space than zoom 2")
	check(root.get_camera_2d() == camera, "812 camera active")
	var shape: CollisionShape2D = room.player.get_node("BodyCollisionShape")
	check(is_equal_approx(shape.shape.radius,8.06226) and shape.position == Vector2(0,7), "Player physical dimensions remain unchanged")
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape.shape
	query.collision_mask = 1
	query.exclude = [room.player.get_rid()]
	await physics_frame
	query.transform = shape.global_transform
	check(room.get_world_2d().direct_space_state.intersect_shape(query,1).is_empty(), "812 spawn clears geometry")
	for i in range(room.internal_doors.size()):
		var door = room.internal_doors[i]
		var approach := Vector2(0,26) if i == 0 else (Vector2(-28,-7) if i == 1 else Vector2(0,-33))
		room.player.position = door.position + approach
		await physics_frame
		check(room.interactions.nearest() == door, "812 E targets " + door.title)
		var closed_axis := Vector2.RIGHT if i == 1 else Vector2.DOWN
		check(room.player.test_move(Transform2D(0,door.position-closed_axis*24-Vector2(0,7)),closed_axis*48), "812 closed door blocks player " + str(i))
		room._unhandled_input(input)
		check(door.opened and door.barrier.collision_layer == 0, "812 E opens " + door.title)
		var axis := Vector2.RIGHT if i == 1 else Vector2.DOWN
		check(not room.player.test_move(Transform2D(0,door.position-axis*24-Vector2(0,7)),axis*48), "812 player sweeps through " + str(i))
		room.player.position = door.position - Vector2(0,7)
		await physics_frame
		door.interact()
		check(door.opened and door.blocked_by_player, "812 door cannot close on player " + str(i))
	# Search physical free space and sweep the original CharacterBody2D on every edge.
	var free := {}
	for x in range(20,428,4):
		for y in range(20,356,4):
			query.transform = Transform2D(0,Vector2(x,y))
			if room.get_world_2d().direct_space_state.intersect_shape(query,1).is_empty():
				free[Vector2i(x/4,y/4)] = true
	var seed := Vector2i(10,55)
	check(free.has(seed), "812 entry has a character-sized free approach")
	var seen := {seed:true}
	var pending: Array[Vector2i] = [seed]
	var index := 0
	while index < pending.size():
		var at := pending[index]
		index += 1
		for axis in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:
			var next: Vector2i = at + axis
			if free.has(next) and not seen.has(next) and not room.player.test_move(Transform2D(0,Vector2(at*4)-Vector2(0,7)),Vector2(axis*4)):
				seen[next] = true
				pending.append(next)
	for key in room.room_areas:
		var reached := false
		for at in seen:
			if room.room_areas[key].grow(-20).has_point(Vector2(at*4)):
				reached = true
				break
		check(reached, "812 swept route from exit reaches " + str(key))
	# Sample every authored room boundary: each point must belong to a wall or door.
	var barriers: Array[Rect2] = []
	barriers.assign(room.partitions)
	for data in room.layout.doors:
		barriers.append(room.rectangle(data.rect))
	barriers.append(room.rectangle(room.layout.exit))
	for key in room.room_areas:
		var area: Rect2 = room.room_areas[key]
		var sealed := true
		for vertical in [false,true]:
			var length: int = int(area.size.y if vertical else area.size.x)
			for offset in range(length):
				for far_side in [false,true]:
					var point := Vector2(area.end.x if far_side else area.position.x,area.position.y+offset) if vertical else Vector2(area.position.x+offset,area.end.y if far_side else area.position.y)
					var covered := false
					for box in barriers:
						covered = covered or box.grow(.01).has_point(point)
					sealed = sealed and covered
		check(sealed, "812 complete room perimeter without wall gaps " + str(key))
	var by_id := {}
	var boxes: Array[Rect2] = []
	var toilet_count := 0
	for item in room.furniture:
		var box: Rect2 = item.get_child(0).global_transform * item.get_child(0).shape.get_rect()
		check(not by_id.has(item.object_id), "812 unique furniture " + item.object_id)
		by_id[item.object_id] = item
		check(room.room_areas[item.get_meta("room")].encloses(box), "812 furniture inside intended room " + item.object_id)
		var clear := true
		for wall in room.partitions:
			clear = clear and not box.intersects(wall)
		for previous in boxes:
			clear = clear and not box.intersects(previous)
		boxes.append(box)
		check(clear and item.collision_layer == 1 and item.get_child(0).shape.size == item.footprint, "812 furniture physical bounds clear " + item.object_id)
		# At least one accessible side of every furnishing, including sanitary fixtures.
		var accessible := false
		for at in seen:
			var foot := Vector2(at*4)
			if box.grow(14).has_point(foot) and not box.has_point(foot):
				accessible = true
				break
		check(accessible, "812 furnishing has reachable approach " + item.object_id)
		if item.get_meta("room") == "Туалет":
			toilet_count += 1
			check(item.furniture_kind == "toilet", "812 toilet room contains only toilet")
	check(toilet_count == 1, "812 exactly one toilet fixture")
	var toilet = by_id["812_toilet"]
	check((toilet.position-Vector2(0,toilet.footprint.y/2)).is_equal_approx(room.room_areas["Туалет"].get_center()), "Toilet visual and physical rectangle centered on both axes")
	check(room.layout.walls[5] == [18.0,168.0,66.0,12.0], "B entrance wall shortened from 126 to 66 pixels with full collision update")
	check(room.room_areas["А"].position.x == 198 and room.bounds.end.x == 432, "Right room and exterior compacted together by 60 pixels")
	var bed = by_id["812_b_bed2"]
	var cabinet = by_id["812_b_cabinet1"]
	check(room.window_rects["Б"].position.x-(bed.position.x+bed.footprint.x/2) == 60, "B upper right bed closer to window: gap 150 to 60 pixels")
	var front_reached := false
	for at in seen:
		var foot := Vector2(at*4)
		if foot.x >= cabinet.position.x-cabinet.footprint.x/2-14 and foot.x <= cabinet.position.x+cabinet.footprint.x/2 and foot.y > cabinet.position.y and foot.y <= cabinet.position.y+14:
			front_reached = true
	check(front_reached, "Original player sweep reaches south-facing nightstand front beside moved bed")
	var wardrobe = by_id["812_b_wardrobe"]
	check(wardrobe.position.x-wardrobe.footprint.x/2 == room.room_areas["Б"].position.x and wardrobe.footprint.y >= room.room_areas["Б"].size.y-8 and wardrobe.facing == "east", "812 B wardrobe covers west wall and faces east window")
	check(room.window_rects["Б"].position.x == room.room_areas["Б"].end.x and room.window_rects["А"].position.x == room.room_areas["А"].end.x, "812 windows mounted on opposite east walls")
	check(room.window_rects["А"].size.y >= room.room_areas["А"].size.y*.85, "812 A window spans almost entire wall opposite west entrance")
	check(room.internal_doors[0].position.x < room.room_areas["Б"].get_center().x, "812 B has more floor east of entrance")
	for id in ["812_b_fridge","812_b_cabinet2","812_b_cabinet3"]:
		check(by_id[id].position.x > room.internal_doors[0].position.x, "812 right of B entrance " + id)
	var shower = by_id["812_shower"]
	var sink = by_id["812_sink"]
	check(shower.position.y == room.room_areas["Душевая"].end.y and shower.position.x-shower.footprint.x/2 == room.room_areas["Душевая"].position.x, "812 shower touches deep south and west walls")
	check(sink.position.y == shower.position.y-shower.footprint.y and sink.position.x == shower.position.x, "812 sink touches shower to its north as in sketch")
	for id in ["812_a_bed1","812_a_bed2"]:
		check(by_id[id].footprint.x > by_id[id].footprint.y and by_id[id].position.x+by_id[id].footprint.x/2 < room.room_areas["А"].end.x, "812 A beds parallel to non-window walls " + id)
	check(sink.facing == "east", "812 sink faucet faces west wall and basin opens east")
	check(by_id.has("812_a_wardrobe"), "812 A includes wardrobe")
	if DisplayServer.get_name() != "headless":
		for target in [["812_room_b",Vector2(288,90)],["812_room_a",Vector2(384,264)],["812_toilet",Vector2(78,318)],["812_shower",Vector2(210,318)]]:
			await capture(room,target[0],target[1])
		room.get_node("DormUI").hide()
		room.player.hide()
		camera.zoom = Vector2(.85,.85)
		camera.limit_left = -1000
		camera.limit_top = -1000
		camera.limit_right = 2000
		camera.limit_bottom = 2000
		await capture(room,"812_overview",room.bounds.get_center())
		room.get_node("DormUI").show()
		room.player.show()
	for cycle in range(2):
		room.player.position = Vector2(42,215)
		await physics_frame
		check(room.interactions.nearest().kind == "block_exit", "812 exit accessible through E")
		room._unhandled_input(input)
		await wait_for_scene(transition.FLOOR)
		floor_scene = current_scene
		check(floor_scene.player.position.is_equal_approx(return_at) and floor_scene.player.facing == Vector2.DOWN, "812 return restores corridor position and facing")
		if cycle == 0:
			floor_scene._unhandled_input(input)
			await wait_for_scene(transition.BLOCK812)
			room = current_scene
	floor_scene.stop_audio()
	floor_scene.queue_free()
	await process_frame
	await process_frame

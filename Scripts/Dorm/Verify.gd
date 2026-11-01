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
		if record.locked:
			object.interact()
			check(not object.opened and object.barrier.collision_layer == 1, "Residential block remains locked: " + record.zone)
			continue
		check(object.barrier.collision_layer == 1, "Door starts solid: " + record.zone)
		object.interact()
		check(object.opened and object.barrier.collision_layer == 0, "Door opens passage: " + record.zone)
		object.interact()
		check(not object.opened and object.barrier.collision_layer == 1, "Door closes passage: " + record.zone)
	await check_architecture(level)
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
		if not record.object.opened:
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
	var lift_count := 0
	for object in level.interactions.objects:
		if object.kind == "elevator":
			lift_count += 1
	check(lift_count == 3, "Original two plus one elevators retained")
	if DisplayServer.get_name() != "headless":
		await check_render(level)
	level.close_modal()
	level.stop_audio()
	await create_timer(.15).timeout
	level.queue_free()
	await process_frame
	await process_frame
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
				var rect: Rect2 = child.get_rect()
				rect.position += child.position
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
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	if not title.is_empty():
		frame.save_png("res://docs/preview_" + title + ".png")
	return frame

func check_render(level) -> void:
	level.player.position = Vector2(256, 232)
	await physics_frame
	await physics_frame
	for record in level.door_records:
		if record.object.opened:
			record.object.interact()
	await physics_frame
	for target in [["hall", Vector2(256, 232)], ["elevator_3", Vector2(408, 208)], ["elevator_26", Vector2(104, 436)], ["kitchen", Vector2(720, 220)], ["loggia", Vector2(136, 142)], ["balcony_4", Vector2(408, 440)], ["balcony_6", Vector2(1112, 344)], ["balcony_9", Vector2(-600, 328)], ["balcony_13", Vector2(264, 1256)], ["balcony_22", Vector2(264, -656)], ["corridor", Vector2(864, 344)]]:
		await capture(level, target[0], target[1])
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

extends SceneTree

var failures: Array[String] = []

func check(condition: bool, description: String) -> void:
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
		check(object.barrier.collision_layer == 1, "Door starts solid: " + record.zone)
		object.interact()
		check(object.opened and object.barrier.collision_layer == 0, "Door opens passage: " + record.zone)
		object.interact()
		check(not object.opened and object.barrier.collision_layer == 1, "Door closes passage: " + record.zone)
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
	# Full physics occupancy search, including walls, furniture and opened doors.
	for record in level.door_records:
		if not record.object.opened:
			record.object.interact()
	await physics_frame
	var free: Dictionary = {}
	var circle := CircleShape2D.new()
	circle.radius = 7
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
	if DisplayServer.get_name() != "headless":
		for target in [["hall", Vector2(256, 232)], ["kitchen", Vector2(720, 220)], ["loggia", Vector2(96, 140)]]:
			level.player.position = target[1]
			level.player.get_node("Camera2D").reset_smoothing()
			for i in range(5):
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://docs/preview_" + target[0] + ".png")
	level.close_modal()
	level.stop_audio()
	await create_timer(.15).timeout
	level.queue_free()
	await process_frame
	await process_frame
	print("VERIFY_COMPLETE failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

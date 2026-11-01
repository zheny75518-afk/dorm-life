extends Node

const FLOOR = "res://Scenes/Levels/DormFloor08.tscn"
const BLOCK812 = "res://Scenes/Rooms/Block812.tscn"
const BLOCK_SCENES = {812: BLOCK812}
var return_position := Vector2.ZERO
var return_facing := Vector2.RIGHT
var has_return := false
var busy := false

func enter_block(at: Vector2, facing: Vector2, number: int) -> void:
	if busy or not block_accessible(number):
		return
	return_position = at
	return_facing = facing
	has_return = true
	change_scene.call_deferred(BLOCK_SCENES[number])
	busy = true

func block_accessible(number: int) -> bool:
	if not BLOCK_SCENES.has(number):
		return false
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://Data/Floors/floor08.json"))
	for zone in data.zones:
		if int(zone.get("block_number", -1)) == number:
			return bool(zone.get("accessible", false))
	return false

func leave_block() -> void:
	if busy:
		return
	change_scene.call_deferred(FLOOR)
	busy = true

func change_scene(path: String) -> void:
	get_tree().paused = false
	var error := get_tree().change_scene_to_file(path)
	if error != OK:
		push_error("Cannot load dorm scene: " + path)
		busy = false
		return
	await get_tree().process_frame
	await get_tree().process_frame
	busy = false

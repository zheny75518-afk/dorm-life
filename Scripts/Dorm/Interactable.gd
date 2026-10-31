extends Node2D
class_name DormInteractable

signal activated(object: DormInteractable)
@export var kind: String = "inspect"
@export var title: String = "Осмотреть"
@export var message: String = ""
@export var target_floor: int = 8
var opened: bool = false
var barrier: StaticBody2D
var art: Sprite2D
var blocked_by_player: bool = false

func interact() -> void:
	if kind == "door":
		blocked_by_player = false
		if opened and barrier:
			var shape_node: CollisionShape2D = barrier.get_child(0)
			var query := PhysicsShapeQueryParameters2D.new()
			query.shape = shape_node.shape
			query.transform = shape_node.global_transform
			query.collision_mask = 2
			query.exclude = [barrier.get_rid()]
			if not get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty():
				blocked_by_player = true
				activated.emit(self)
				return
		opened = not opened
		if barrier:
			barrier.collision_layer = 0 if opened else 1
		if art:
			art.visible = not opened
	activated.emit(self)

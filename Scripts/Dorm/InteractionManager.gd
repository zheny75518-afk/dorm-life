extends Node
class_name DormInteractionManager

var objects: Array[DormInteractable] = []
var current: DormInteractable
var player: CharacterBody2D

func nearest() -> DormInteractable:
	current = null
	var best: float = 46.0
	for object in objects:
		var distance: float = player.global_position.distance_to(object.global_position)
		if distance < best:
			var query := PhysicsRayQueryParameters2D.create(player.global_position + Vector2(0, 7), object.global_position, 1)
			query.exclude = [player.get_rid()]
			var hit := player.get_world_2d().direct_space_state.intersect_ray(query)
			if hit.is_empty() or hit.collider == object.barrier:
				current = object
				best = distance
	return current

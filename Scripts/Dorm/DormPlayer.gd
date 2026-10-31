extends PlayerMain

# Retain upstream CharacterBase, animation library and idle/walk FSM.
# Dorm movement uses the same speed, with physics-tick updates for stable collision.
func _ready() -> void:
	super()
	$Camera2D/ProgressBar.hide()
	$Camera2D/Label.hide()
	$QuestTracker.hide()
	$QuestTracker.process_mode = Node.PROCESS_MODE_DISABLED
	$PointLight2D2.hide()
	$FSM.set_process(false)
	$FSM/Moving.can_dash = false

func _physics_process(delta: float) -> void:
	if fsm.current_state:
		fsm.current_state.Update(delta)

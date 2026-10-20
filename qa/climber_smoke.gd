extends SceneTree

var signal_count: int = 0
var fall_count: int = 0

func _initialize() -> void:
	var script: Script = load("res://scripts/climber.gd")
	var climber: Node3D = script.new()
	root.add_child(climber)
	climber.set_process(false)
	climber.setup({"id": 0, "position": Vector3(0, 1, 0.45), "checkpoint": true})
	climber.reached_hold.connect(func(_id: int) -> void: signal_count += 1)
	climber.fell.connect(func() -> void: fall_count += 1)
	assert(not climber.climb_to({"id": 1, "position": Vector3(0.5, 2.3, 0.45)}))
	climber.climbing = true
	assert(climber.climb_to({"id": 1, "position": Vector3(0.5, 2.3, 0.45), "checkpoint": true}))
	assert(not climber.climb_to({"id": 2, "position": Vector3(0.9, 3.6, 0.45)}))
	for i in range(250):
		climber._process(0.016)
	assert(signal_count == 1)
	assert(climber.current_hold_id == 1)
	assert(climber.total_moves == 1)
	assert(climber.checkpoint_hold_id == 1)
	assert(climber.get_reach_origin().is_equal_approx(Vector3(0.5, 2.3, 0.45)))
	assert(climber.get_body_position().y < 1.6)
	climber.stamina = 40.0
	assert(climber.chalk())
	assert(not climber.chalk())
	assert(is_equal_approx(climber.stamina, 50.0))
	climber.rest(1.0)
	assert(is_equal_approx(climber.stamina, 73.0))
	climber.stamina = 0.01
	climber._process(0.1)
	climber._process(0.1)
	assert(fall_count == 1)
	climber.recover()
	assert(climber.current_hold_id == 1)
	assert(climber.climbing)
	assert(is_equal_approx(climber.stamina, 100.0))
	climber.celebrate()
	for i in range(150):
		climber._process(0.016)
	assert(climber.summit_mode)
	assert(climber.get_body_position().y > 2.6)
	print("CLIMBER PASS: movement, callbacks, checkpoint, stamina, chalk cooldown, recovery and summit animation")
	climber.queue_free()
	quit()


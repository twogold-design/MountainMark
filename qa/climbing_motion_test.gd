extends SceneTree
## Physical action sequencing and selected-foot feedback, without a player save.
const ACTOR = preload("res://scripts/climber.gd")
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func verify(ok: bool, detail: String) -> void:
	checks += 1
	if not ok:
		failures.append(detail)
		print("FAIL ", detail)

func check_limbs(actor: Node3D) -> void:
	for i in range(2):
		var side: float = -1.0 if i == 0 else 1.0
		var shoulder: Vector3 = actor.get_shoulder_position(i)
		verify(shoulder.is_equal_approx(actor._torso.transform * Vector3(side * 0.225, 0.22, -0.02)), "Shared rendered shoulder")
		var elbow: Vector3 = actor._elbows[i].position
		var palm: Vector3 = actor._gloves[i].position
		verify(absf(shoulder.distance_to(elbow) - 0.34) < 0.0002, "Upper arm remains 0.34m")
		verify(absf(elbow.distance_to(palm) - 0.38) < 0.0002, "Forearm remains 0.38m")
		verify(shoulder.distance_to(palm) <= actor.ARM_REACH + 0.0001, "Hand stays inside actual arm reach")
		var hip: Vector3 = actor._torso.transform * Vector3(side * 0.13, -0.29, 0)
		var knee: Vector3 = actor._knees[i].position
		var ankle: Vector3 = actor._boots[i].position - Vector3(0, -0.015, -0.045)
		verify(absf(hip.distance_to(knee) - 0.43) < 0.0002, "Thigh remains 0.43m")
		verify(absf(knee.distance_to(ankle) - 0.44) < 0.0002, "Shin remains 0.44m")

func begin(actor: Node3D) -> void:
	actor.set_support_foot(-1)
	actor.setup({"id": 0, "position": Vector3(0, 2.5, 0.45)})
	actor.climbing = true
	actor.set_process(false)

func _run() -> void:
	var actor: Node3D = ACTOR.new()
	root.add_child(actor)
	begin(actor)
	actor.set_support_foot(0)
	var left_body: Vector3 = actor.get_body_position()
	verify(actor.get_foot_position(1).y - actor.get_foot_position(0).y > 0.18, "Left support raises the free right foot")
	verify(actor._support_marker.visible, "Selected support has a local foot ring")
	verify(actor.get_support_position().is_equal_approx(actor.get_foot_position(0)), "Support position follows actual boot")
	check_limbs(actor)
	actor.set_support_foot(1)
	verify(actor.get_foot_position(0).y - actor.get_foot_position(1).y > 0.15, "Right support raises the free left foot")
	verify(actor.get_body_position().x - left_body.x > 0.08, "Pelvis shifts toward the loaded foot")
	verify(actor.get_support_position().is_equal_approx(actor.get_foot_position(1)), "Swapped support follows right boot")
	actor.set_support_feedback_visible(false)
	verify(not actor._support_marker.visible, "Pause/menu can hide support feedback immediately")
	actor.set_support_feedback_visible(true)
	actor.set_lean(0.65)
	check_limbs(actor)
	var styles: Array[Dictionary] = [
		{"delta": Vector3(0.15, 1.25, 0), "name": "正身蹬起", "kind": "front"},
		{"delta": Vector3(1.15, 0.35, 0), "name": "侧身横渡", "kind": "side"},
		{"delta": Vector3(0.25, 2.0, 0), "name": "折膝高踩", "kind": "high_step"}
	]
	var turns: Dictionary = {}
	var crouches: Dictionary = {}
	for style: Dictionary in styles:
		for loaded in range(2):
			begin(actor)
			actor.set_support_foot(loaded)
			var target: Vector3 = actor.get_reach_origin() + Vector3(style.delta)
			verify(actor.climb_to({"id": 1, "position": target}, 1, 5.0), "Start " + str(style.name))
			verify(actor.get_motion_name() == style.name, "Geometry chooses " + str(style.name))
			var fixed_foot: Vector3 = actor._old_feet[loaded]
			var fixed_boot: Vector3 = actor.get_foot_position(loaded)
			var free_boot: Vector3 = actor.get_foot_position(1 - loaded)
			var fixed_hands: Array = actor._hands.duplicate()
			var fixed_palms: Array[Vector3] = [actor._gloves[0].position, actor._gloves[1].position]
			actor._process(0.20 * actor._move_duration / float(actor._step_count))
			verify(actor._feet[loaded].is_equal_approx(fixed_foot), "Loaded foot stays planted during free-foot placement")
			verify(actor.get_foot_position(loaded).distance_to(fixed_boot) < 0.0002, "Rendered support boot stays planted")
			verify(actor.get_foot_position(1 - loaded).distance_to(free_boot) > 0.03, "Free foot moves before the loaded foot")
			verify(actor._hands[0].is_equal_approx(fixed_hands[0]) and actor._hands[1].is_equal_approx(fixed_hands[1]), "Both hands wait for the foothold")
			verify(actor._gloves[0].position.distance_to(fixed_palms[0]) < 0.0002 and actor._gloves[1].position.distance_to(fixed_palms[1]) < 0.0002, "Rendered hands keep their contacts until the foot is planted: %s support %d" % [style.kind, loaded])
			actor.set_support_foot(1 - loaded)
			verify(actor._move_support_foot == loaded, "Active support is snapshotted for the move")
			var max_turn: float = 0.0
			var max_crouch: float = 0.0
			while actor.moving:
				actor._process(0.012)
				max_turn = maxf(max_turn, absf(actor._motion_turn))
				max_crouch = maxf(max_crouch, actor._motion_crouch)
				check_limbs(actor)
			verify(actor.current_hold_id == 1, "Action reaches the requested hold")
			verify(actor._gloves[1].position.distance_to(target + Vector3(0, 0, 0.025)) < 0.002, "Final hand actually contacts the target")
			verify(is_zero_approx(actor._motion_turn) and is_zero_approx(actor._motion_crouch), "Moving pose settles before the next reach query")
			turns[style.kind] = max_turn
			crouches[style.kind] = max_crouch
	verify(float(turns.side) > 0.50 and float(turns.front) < 0.10, "Traverse visibly turns shoulders and hips")
	verify(float(crouches.high_step) > 0.07 and float(crouches.front) < 0.03, "High step folds then extends more than a front push")
	actor.celebrate(Vector3(0, 7.0, -0.8))
	actor._process(0.05)
	verify(not actor._support_marker.visible, "Summit hides support ring")
	for i in range(300):
		actor._process(0.012)
		check_limbs(actor)
	verify(actor.summit_mode and not actor.moving and actor.get_motion_name() == "翻越山顶", "Summit sequence remains available")
	actor.queue_free()
	await create_timer(0.1).timeout
	print("CLIMBING_MOTION_RESULT checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

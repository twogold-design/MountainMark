extends SceneTree
const Actor = preload("res://scripts/climber.gd")
var actor: Node3D
var checks: int = 0
var failures: Array[String] = []
var effort_count: int = 0
func _initialize() -> void:
	call_deferred("run")
func verify(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		print("FAIL ",message)
func begin(offset: Vector3, support: int, lean: float, hand: int = 1) -> void:
	actor.set_support_foot(-1)
	actor.setup({"id":0,"position":Vector3(0,2.5,0.45)})
	actor.climbing = true
	actor.set_support_foot(support)
	actor.set_lean(lean)
	effort_count = 0
	actor.climb_to({"id":1,"position":Vector3(0,2.5,0.45)+offset},hand,8.0)
func run() -> void:
	actor = Actor.new()
	root.add_child(actor)
	actor.set_process(false)
	actor.effort_started.connect(func(): effort_count += 1)
	var maximum_jump: float = 0.0
	var max_contact_slip: float = 0.0
	var cases: Array[Vector3] = [Vector3(0.15,1.25,0),Vector3(0.15,1.7,0),Vector3(1.15,0.35,0),Vector3(-1.15,0.35,0),Vector3(0.25,2,0),Vector3(0.2,2.8,0),Vector3(0.32,0.2,0)]
	for offset in cases:
		for support in [-1,0,1]:
			for lean in [-0.65,0.0,0.65]:
				begin(offset,support,lean)
				verify(actor._step_count == 1 and actor._move_duration <= 1.36,"one bounded-duration action per rock")
				var target: Vector3 = Vector3(0,2.5,0.475)+offset
				var axis: Vector3 = (actor._new_body-actor._old_body).normalized()
				var previous_body: Vector3 = actor._body
				var previous: Array[Vector3] = [actor.get_body_position(),actor._gloves[0].position,actor._gloves[1].position,actor.get_foot_position(0),actor.get_foot_position(1)]
				var stopped: int = 0
				var backwards: int = 0
				var early_speed: float = 0.0
				var drive_speed: float = 0.0
				var contacted: bool = false
				for frame in range(1,241):
					var dt: float = actor._move_duration / 240.0
					actor._process(dt)
					var p: float = float(frame) / 240.0
					var advance: float = (Vector3(actor._body)-previous_body).dot(axis)
					if p > 0.25 and p < 0.78:
						if advance <= 0.00001: stopped += 1
						if advance < -0.00001: backwards += 1
					if p > 0.20 and p < 0.28: early_speed = maxf(early_speed,advance/dt)
					if p > 0.35 and p < 0.65: drive_speed = maxf(drive_speed,advance/dt)
					var current: Array[Vector3] = [actor.get_body_position(),actor._gloves[0].position,actor._gloves[1].position,actor.get_foot_position(0),actor.get_foot_position(1)]
					for i in range(5): maximum_jump = maxf(maximum_jump,current[i].distance_to(previous[i]))
					var palm: Vector3 = actor._gloves[1].position
					if contacted: max_contact_slip = maxf(max_contact_slip,palm.distance_to(target))
					if palm.distance_to(target) < 0.001: contacted = true
					previous = current
					previous_body = actor._body
				actor._process(0.00001)
				verify(stopped == 0 and backwards == 0,"no intermediate stop or repeated push")
				verify(drive_speed > early_speed * (1.3 if actor._motion == "pull" else 1.7),"visible acceleration through a single movement")
				verify(contacted and actor._gloves[1].position.distance_to(target)<0.001,"actual hand reaches final rock")
				verify(effort_count==1 and actor.total_moves==1 and actor.current_hold_id==1 and absf(actor.stamina-92)<0.001,"one effort and completion, unchanged move cost")
	verify(maximum_jump < 0.10,"no discontinuous limb or torso jumps")
	verify(max_contact_slip < 0.005,"palm stays on rock after catch")
	# Both hands must lead the visible pose on nearby holds.
	for hand in [0,1]:
		begin(Vector3(0.15,1.25,0),0,0.0,hand)
		var palms: Array[Vector3] = [actor._gloves[0].position,actor._gloves[1].position]
		var hips: Vector3 = actor.get_body_position()
		actor._process(actor._move_duration*0.10)
		verify(actor._motion == "pull", "Nearby target selects hand-led pull")
		verify(actor._gloves[hand].position.distance_to(palms[hand]) > 0.005, "Selected palm reaches before body")
		verify(actor._gloves[1-hand].position.distance_to(palms[1-hand]) < 0.0002 and actor.get_body_position().distance_to(hips) < 0.0002, "Other palm and hips stay while leading hand reaches")
		actor._process(actor._move_duration)
		verify(actor._gloves[hand].position.distance_to(Vector3(0.15,3.75,0.475)) < 0.001,"Either hand can finish a pull")
	# Each family is deterministic at common frame rates, including catch timing.
	for offset in [Vector3(0.15,1.25,0),Vector3(0.15,1.7,0),Vector3(-1.15,0.35,0),Vector3(0.2,2.8,0)]:
		var samples: Array[Transform3D] = []
		for rate in [30,60,120]:
			begin(offset,0,0.5)
			for fraction in [0.25,0.5,0.75,1.0]:
				var finish: float = fraction*actor._move_duration
				while actor._move_time < finish-0.0000001:
					actor._process(minf(1.0/rate,finish-actor._move_time))
				samples.append(actor._torso.transform)
		for i in range(4): verify(samples[i].is_equal_approx(samples[i+4]) and samples[i].is_equal_approx(samples[i+8]),"same motion at 30/60/120 FPS")
	# Distances at either side of each boundary select the intended action.
	for sample in [{"distance":1.49,"kind":"pull"},{"distance":1.51,"kind":"front"},{"distance":1.94,"kind":"front"},{"distance":1.96,"kind":"high_step"}]:
		begin(Vector3(0,sample.distance,0),0,0.0)
		verify(actor._motion == sample.kind,"Distance boundary chooses " + sample.kind)
		actor._process(actor._move_duration*0.5)
		if sample.kind == "pull":
			verify(actor._body.z < actor._old_body.z and is_zero_approx(actor._motion_crouch),"Pull stays close to wall without jumping")
		else:
			verify(actor._body.z > actor._old_body.z,"Leg-driven movement has outward extension")
		actor._process(actor._move_duration)
	print("DISTANCE_MOTION_RESULT checks=",checks," failures=",failures.size()," max_frame_jump=",maximum_jump," catch_slip=",max_contact_slip)
	actor.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

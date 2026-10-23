extends SceneTree
## Mirrored drop-knee selection, real reach geometry and continuous two-bone IK.
## Isolated actor fixtures only; no scene/save controller is loaded.
const Actor = preload("res://scripts/climber.gd")
const START := Vector3(0.0, 2.5, 0.45)
var checks: int = 0
var failures: Array[String] = []
var actor: Node3D
var contacts: int = 0
var arrivals: int = 0
var contact_error: float = 0.0

func _initialize() -> void:
	call_deferred("run")

func verify(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("FAIL ", label)

func on_contact(_id: int, hand: int, _kind: String) -> void:
	contacts += 1
	contact_error = maxf(contact_error, Vector3(actor._gloves[hand].position).distance_to(actor._new_hands[hand]))

func on_arrival(_id: int) -> void:
	arrivals += 1

func prepare(hand: int, support: int, lean: float = 0.0) -> void:
	actor.support_foot = -1
	actor.setup({"id": 0, "position": START})
	actor.climbing = true
	actor.set_support_foot(support)
	actor.set_lean(lean)
	contacts = 0
	arrivals = 0
	contact_error = 0.0

func begin(hand: int, support: int, delta: Vector3, lean: float = 0.0) -> bool:
	prepare(hand, support, lean)
	return actor.climb_to({"id": 1, "position": START + delta}, hand, 8.5)

func ankle_position(index: int) -> Vector3:
	# Read the actual shin end; visual shoe yaw can pivot about its rock contact.
	return actor._shins[index].transform * Vector3(0.0, 0.5, 0.0)

func limb_error() -> float:
	var error: float = 0.0
	for index in range(2):
		var shoulder: Vector3 = actor.get_shoulder_position(index)
		var elbow: Vector3 = actor._elbows[index].position
		var palm: Vector3 = actor._gloves[index].position
		error = maxf(error, absf(shoulder.distance_to(elbow) - 0.34))
		error = maxf(error, absf(elbow.distance_to(palm) - 0.38))
		var side: float = -1.0 if index == 0 else 1.0
		var hip: Vector3 = actor._torso.transform * Vector3(side * 0.13, -0.29, 0.0)
		var knee: Vector3 = actor._knees[index].position
		error = maxf(error, absf(hip.distance_to(knee) - 0.43))
		error = maxf(error, absf(knee.distance_to(ankle_position(index)) - 0.44))
	return error

func knee_bend(index: int) -> Vector3:
	var side: float = -1.0 if index == 0 else 1.0
	var hip: Vector3 = actor._torso.transform * Vector3(side * 0.13, -0.29, 0.0)
	var axis: Vector3 = (ankle_position(index) - hip).normalized()
	var knee_delta: Vector3 = actor._knees[index].position - hip
	return knee_delta - axis * knee_delta.dot(axis)

func check_selection() -> void:
	for hand in range(2):
		var side: float = -1.0 if hand == 0 else 1.0
		var delta := Vector3(side * 0.90, 0.95, 0.0)
		verify(begin(hand, hand, delta, side * 0.90), "Same-side hand/support fixture begins")
		verify(actor._motion == "drop_knee" and actor.get_motion_name() == "折膝侧伸", "Same-side diagonal reach selects the named drop knee")
		verify(begin(hand, 1 - hand, delta), "Cross-side fixture begins")
		verify(actor._motion != "drop_knee", "Cross-side hand/support retains its ordinary action")
		verify(begin(hand, -1, delta), "Unselected-foot fixture begins")
		verify(actor._motion != "drop_knee", "No chosen support does not invent a drop-knee side")
		verify(begin(hand, hand, Vector3(-side * 0.90, 0.95, 0.0)), "Reverse-direction fixture begins")
		verify(actor._motion != "drop_knee", "Reaching across the selected foot does not use the wrong knee")
		verify(begin(hand, hand, Vector3(side * 0.20, 0.95, 0.0)), "Near-vertical fixture begins")
		verify(actor._motion != "drop_knee", "Small lateral reach retains ordinary climbing")
		verify(begin(hand, hand, Vector3(side * 0.90, 0.20, 0.0)), "Low traverse fixture begins")
		verify(actor._motion != "drop_knee", "A low traverse does not drop the knee unnecessarily")
		verify(begin(hand, hand, Vector3(side * 0.20, 2.10, 0.0)), "High-step fixture begins")
		verify(actor._motion == "high_step" and actor.get_motion_name() == "远点跃抓", "High stepping remains a separate, accurately named action")
		verify(begin(hand, hand, delta, side * 0.90), "Support snapshot fixture begins")
		actor.set_support_foot(1 - hand)
		verify(actor._move_support_foot == hand and actor._motion == "drop_knee", "Changing the next support cannot switch the active drop knee")

func check_preparation() -> void:
	for hand in range(2):
		var side: float = -1.0 if hand == 0 else 1.0
		prepare(hand, hand)
		var target: Vector3 = START + Vector3(side * 0.90, 0.95, 0.0)
		var before: Vector3 = actor.get_shoulder_position(hand)
		var initial_support: Vector3 = ankle_position(hand)
		var maximum_limb_error: float = 0.0
		var maximum_step: float = 0.0
		var previous_knee: Vector3 = actor._knees[hand].position
		for increment in range(1, 19):
			actor.set_lean(side * float(increment) * 0.05)
			maximum_limb_error = maxf(maximum_limb_error, limb_error())
			maximum_step = maxf(maximum_step, previous_knee.distance_to(actor._knees[hand].position))
			previous_knee = actor._knees[hand].position
		var prepared: Vector3 = actor.get_shoulder_position(hand)
		var displayed: Vector3 = actor._torso.transform * Vector3(side * 0.225, 0.22, -0.02)
		print("DROP_PREP_METRICS hand=", hand, " ankle_shift=", ankle_position(hand).distance_to(initial_support), " max_knee_step=", maximum_step, " limb_error=", maximum_limb_error)
		verify(prepared.distance_to(displayed) < 0.00001 and actor.get_body_position().distance_to(actor._torso.position) < 0.00001, "Prepared drop-knee reach uses the actual displayed torso and shoulder")
		verify(prepared.distance_to(before) > 0.08 and prepared.distance_to(target) < before.distance_to(target) - 0.02, "Weight preparation changes actual target distance through the shoulder pose")
		verify(ankle_position(hand).distance_to(initial_support) < 0.001, "Weight preparation keeps the chosen ankle planted")
		verify(maximum_limb_error < 0.0005 and maximum_step < 0.12, "Preparation preserves limb lengths and turns the knee continuously")
		actor.set_lean(0.0)
		verify(actor.get_shoulder_position(hand).distance_to(before) < 0.00001, "Returning to center removes the prepared torso offset")

func sample(hand: int, fps: int) -> Dictionary:
	var side: float = -1.0 if hand == 0 else 1.0
	var delta := Vector3(side * 0.90, 0.95, 0.0)
	var label: String = "%d FPS / %s knee" % [fps, "left" if hand == 0 else "right"]
	verify(begin(hand, hand, delta, side * 0.90), label + " begins")
	var initial_support: Vector3 = ankle_position(hand)
	actor._process(0.20 * actor._move_duration / float(actor._step_count))
	verify(ankle_position(hand).distance_to(initial_support) < 0.001, label + " keeps loaded ankle fixed while the free foot plants")
	var worst_limb: float = limb_error()
	var max_knee_step: float = 0.0
	var max_palm_step: float = 0.0
	var inward: float = 0.0
	var downward: float = 0.0
	var maximum_drop: float = 0.0
	var maximum_yaw: float = 0.0
	var plane_alignment: float = 1.0
	var previous_knee: Vector3 = actor._knees[hand].position
	var previous_palm: Vector3 = actor._gloves[hand].position
	var previous_bend: Vector3 = knee_bend(hand)
	var poses: Array[Dictionary] = []
	for fraction in [0.25, 0.50, 0.75, 1.0]:
		var target_time: float = float(fraction) * actor._move_duration
		while actor.moving and actor._move_time < target_time - 0.0000001:
			actor._process(minf(1.0 / float(fps), target_time - actor._move_time))
			worst_limb = maxf(worst_limb, limb_error())
			var knee: Vector3 = actor._knees[hand].position
			var palm: Vector3 = actor._gloves[hand].position
			var bend: Vector3 = knee_bend(hand)
			if knee.distance_to(previous_knee) > 0.15:
				print("DROP_JUMP ", label, " p=", actor._move_time / actor._move_duration, " drop=", actor._motion_drop, " knee_step=", knee.distance_to(previous_knee), " knee=", knee, " ankle=", ankle_position(hand), " bend=", bend, " old_bend=", previous_bend)
			max_knee_step = maxf(max_knee_step, knee.distance_to(previous_knee))
			max_palm_step = maxf(max_palm_step, palm.distance_to(previous_palm))
			if previous_bend.length() > 0.08 and bend.length() > 0.08:
				plane_alignment = minf(plane_alignment, previous_bend.normalized().dot(bend.normalized()))
			if float(actor._motion_drop) > 0.65:
				inward = maxf(inward, -side * bend.x)
				downward = minf(downward, bend.y)
			maximum_drop = maxf(maximum_drop, float(actor._motion_drop))
			maximum_yaw = maxf(maximum_yaw, side * actor._torso.rotation.y)
			previous_knee = knee
			previous_palm = palm
			previous_bend = bend
		poses.append({"torso": actor._torso.transform, "knee": actor._knees[hand].position, "palm": actor._gloves[hand].position, "ankle": ankle_position(hand)})
	verify(worst_limb < 0.0005, label + " preserves all upper/lower limb lengths")
	verify(max_knee_step < 0.18 and max_palm_step < 0.14 and plane_alignment > 0.0, label + " has no knee-plane flip or sudden joint/hand jump")
	verify(maximum_drop > 0.65 and inward > 0.12 and downward < -0.02 and maximum_yaw > 0.35, label + " visibly turns the hip and folds the selected knee inward/down")
	verify(not actor.moving and actor.current_hold_id == 1 and actor.total_moves == 1 and is_equal_approx(actor.stamina, 91.5), label + " completes with the requested unchanged stamina cost")
	verify(contacts == 1 and arrivals == 1 and contact_error <= 0.0121 and Vector3(actor._gloves[hand].position).distance_to(START + delta + Vector3(0.0, 0.0, 0.025)) < 0.001, label + " reaches its real target with exactly one contact and arrival")
	print("DROP_METRICS ", label, " max_drop=", maximum_drop, " inward=", inward, " downward=", downward, " yaw=", maximum_yaw, " max_knee_step=", max_knee_step, " max_palm_step=", max_palm_step, " min_plane_dot=", plane_alignment, " limb_error=", worst_limb)
	actor.recover()
	actor.set_support_foot(-1)
	verify(not actor.moving and is_zero_approx(float(actor._motion_drop)) and is_zero_approx(actor._motion_turn) and is_zero_approx(actor._motion_crouch), label + " recover clears all drop-knee motion offsets")
	return {"poses": poses}

func check_main_reach_boundary() -> void:
	# Exercise the shipped controller with boundary targets rather than granting a
	# special reach fixture inside the actor. QA mode prevents progress writes.
	var game: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.world.set_process(false)
	game.climber.set_process(false)
	game.sound.set_process(false)
	game.mode = "playing"
	var maximum: float = Actor.ARM_REACH + Actor.STEP_REACH
	for hand in range(2):
		var side: float = -1.0 if hand == 0 else 1.0
		var lean: float = side * 0.90
		game.climber.support_foot = -1
		game.climber.setup({"id": 0, "position": START})
		game.climber.climbing = true
		game.climber.set_support_foot(hand)
		game.selected_support = hand
		game.balance = lean
		game.climber.set_lean(lean)
		var displayed: Vector3 = game.climber._torso.transform * Vector3(side * 0.225, 0.22, -0.02)
		var shoulder: Vector3 = game.climber.get_shoulder_position(hand)
		# Same input and same support translation, with only the drop-knee turn and
		# pelvis contribution removed for the neutral comparison.
		game.climber.support_foot = -1
		var neutral_shoulder: Vector3 = game.climber.get_shoulder_position(hand, lean) + Vector3(side * 0.045, 0.0, 0.0)
		game.climber.support_foot = hand
		for margin in [-0.02, 0.02]:
			var radius: float = maximum + float(margin)
			var y: float = START.y + 0.95
			var z: float = START.z + 0.025
			var horizontal: float = sqrt(radius * radius - pow(y - shoulder.y, 2.0) - pow(z - shoulder.z, 2.0))
			var target := Vector3(shoulder.x + side * horizontal, y, START.z)
			var fixture: Dictionary = game.world.holds[0].duplicate(true)
			var id: int = 9000 + hand * 2 + (1 if float(margin) > 0.0 else 0)
			fixture["id"] = id
			fixture["position"] = target
			fixture["support"] = -1
			game.world.holds.append(fixture)
			var info: Dictionary = game.hold_reach_info(id, hand, lean)
			verify(Vector3(info.shoulder).distance_to(displayed) < 0.00001 and absf(float(info.distance) - displayed.distance_to(Vector3(info.target))) < 0.00001, "Main reach distance is measured from the displayed prepared shoulder")
			verify(absf(float(info.max_distance) - maximum) < 0.00001 and absf(float(info.distance) - radius) < 0.00001 and bool(info.reachable) == (float(margin) < 0.0), "Drop-knee reach accepts the true inside boundary and rejects the true outside boundary with no extra range")
			var distance_reduction: float = neutral_shoulder.distance_to(Vector3(info.target)) - float(info.distance)
			print("DROP_REACH_BOUNDARY hand=", hand, " margin=", margin, " actual_distance=", info.distance, " maximum=", info.max_distance, " neutral_distance=", neutral_shoulder.distance_to(Vector3(info.target)), " reduction=", distance_reduction)
			verify(distance_reduction > 0.01, "The prepared pose shortens target distance through geometry at the same lean input")
	game.sound.shutdown()
	game.queue_free()

func run() -> void:
	if "--qa-capture" not in OS.get_cmdline_user_args():
		quit(2)
		return
	actor = Actor.new()
	root.add_child(actor)
	actor.set_process(false)
	actor.hand_contact.connect(on_contact)
	actor.reached_hold.connect(on_arrival)
	check_selection()
	check_preparation()
	for hand in range(2):
		var reference: Dictionary = {}
		for fps in [30, 60, 120]:
			var result: Dictionary = sample(hand, fps)
			if reference.is_empty():
				reference = result
			else:
				var matches: bool = true
				for index in range(reference.poses.size()):
					var expected: Dictionary = reference.poses[index]
					var actual: Dictionary = result.poses[index]
					matches = matches and expected.torso.is_equal_approx(actual.torso) and expected.knee.is_equal_approx(actual.knee) and expected.palm.is_equal_approx(actual.palm) and expected.ankle.is_equal_approx(actual.ankle)
				verify(matches, "30/60/120 FPS agree on torso, knee, ankle and palm at the same movement times")
	check_main_reach_boundary()
	actor.queue_free()
	await process_frame
	print("DROP_KNEE_RESULT checks=", checks, " failures=", failures.size())
	for failure: String in failures:
		print("FAILED: ", failure)
	quit(0 if failures.is_empty() else 1)

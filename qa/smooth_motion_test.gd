extends SceneTree
## Single-reach motion regression. Requires -- --qa-capture; no game/save is loaded.
const Actor = preload("res://scripts/climber.gd")
const START := Vector3(0.0, 2.5, 0.45)
const CASES := [Vector3(0.45, 1.2, 0.0), Vector3(1.65, 0.6, 0.0), Vector3(0.3, 2.1, 0.0)]
var checks: int = 0
var failures: Array[String] = []
var actor: Node3D

func _initialize() -> void:
	call_deferred("run")

func verify(ok: bool, label: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failures.append(label)

func begin_move(delta: Vector3, hand: int, effort: float = 8.5) -> bool:
	actor.setup({"id": 0, "position": START})
	actor.climbing = true
	# The opening step never searches; these fixtures represent a subsequent move.
	actor.total_moves = 1
	actor.set_support_foot(1 - hand)
	return actor.climb_to({"id": 1, "position": START + delta}, hand, effort)

func begin_variant(delta: Vector3, hand: int, searching: bool) -> bool:
	for attempt in range(200):
		if not begin_move(delta, hand):
			return false
		if bool(actor._searching_move) == searching:
			return true
		actor._process(actor._move_duration)
	return false

func limb_error() -> float:
	var error: float = 0.0
	for hand in range(2):
		var shoulder: Vector3 = actor.get_shoulder_position(hand)
		var elbow: Vector3 = actor._elbows[hand].position
		var palm: Vector3 = actor._gloves[hand].position
		error = maxf(error, absf(shoulder.distance_to(elbow) - 0.34))
		error = maxf(error, absf(elbow.distance_to(palm) - 0.38))
		var side: float = -1.0 if hand == 0 else 1.0
		var hip: Vector3 = actor._torso.transform * Vector3(side * 0.13, -0.29, 0)
		var knee: Vector3 = actor._knees[hand].position
		var ankle: Vector3 = actor._boots[hand].position - Vector3(0, -0.015, -0.045)
		error = maxf(error, absf(hip.distance_to(knee) - 0.43))
		error = maxf(error, absf(knee.distance_to(ankle) - 0.44))
	return error

func sample_motion(delta: Vector3, hand: int, searching: bool) -> void:
	var label: String = "%s / hand %d / %s" % [str(delta), hand, "search" if searching else "normal"]
	if not begin_variant(delta, hand, searching):
		verify(false, label + ": selected animation variant starts")
		return
	verify(actor.get_motion_name().contains("探点") == searching, label + ": only a searching move is labelled as searching")
	var old: Array[Vector3] = actor._old_hands.duplicate()
	var end: Array[Vector3] = actor._new_hands.duplicate()
	var previous: Array[Vector3] = actor._hands.duplicate()
	var visible_previous: Array[Vector3] = [actor._gloves[0].position, actor._gloves[1].position]
	var visible_advanced: Array[bool] = [false, false]
	var visible_pause_ticks: Array[int] = [0, 0]
	var visible_pause_groups: Array[int] = [0, 0]
	var has_advanced: Array[bool] = [false, false]
	var paused: Array[bool] = [false, false]
	var pause_groups: Array[int] = [0, 0]
	var reversal: float = 0.0
	var visible_reversal: float = 0.0
	var maximum_visible_step: float = 0.0
	var max_arc: float = 0.0
	var maximum_limb_error: float = 0.0
	var contact_position: Vector3
	var contact_seen: bool = false
	var contact_slip: float = 0.0
	var body_previous: Vector3 = actor._body
	var body_axis: Vector3 = (actor._new_body - actor._old_body).normalized()
	var body_reversal: float = 0.0
	var early_contact: bool = false
	for tick in range(1, 101):
		actor._process(actor._move_duration * 0.01 + 0.000001)
		var p: float = float(tick) * 0.01
		maximum_limb_error = maxf(maximum_limb_error, limb_error())
		body_reversal = minf(body_reversal, (Vector3(actor._body) - body_previous).dot(body_axis))
		body_previous = actor._body
		for i in range(2):
			var span: Vector3 = end[i] - old[i]
			var advance: float = (Vector3(actor._hands[i]) - previous[i]).dot(span.normalized()) / span.length()
			var visible_step: Vector3 = Vector3(actor._gloves[i].position) - visible_previous[i]
			var visible_progress: float = visible_step.dot(span.normalized()) / span.length()
			maximum_visible_step = maxf(maximum_visible_step, visible_step.length())
			if p >= 0.12 and p <= 0.90:
				reversal = minf(reversal, advance)
				if advance > 0.001:
					has_advanced[i] = true
					paused[i] = false
				elif has_advanced[i] and not paused[i]:
					pause_groups[i] += 1
					paused[i] = true
				visible_reversal = minf(visible_reversal, visible_progress)
				if visible_progress > 0.0005:
					visible_advanced[i] = true
					visible_pause_ticks[i] = 0
				elif visible_advanced[i]:
					visible_pause_ticks[i] += 1
					if visible_pause_ticks[i] == 3:
						visible_pause_groups[i] += 1
			var along: float = clampf((Vector3(actor._hands[i]) - old[i]).dot(span) / span.length_squared(), 0.0, 1.0)
			max_arc = maxf(max_arc, Vector3(actor._hands[i]).z - old[i].lerp(end[i], along).z)
			previous[i] = actor._hands[i]
			visible_previous[i] = actor._gloves[i].position
		var target: Vector3 = START + delta + Vector3(0, 0, 0.025)
		var palm: Vector3 = actor._gloves[hand].position
		if palm.distance_to(target) < 0.001:
			if not contact_seen:
				contact_position = palm
				contact_seen = true
				early_contact = p < 1.0
		if contact_seen:
			contact_slip = maxf(contact_slip, palm.distance_to(contact_position))
	if not searching:
		verify(pause_groups[0] <= 1 and pause_groups[1] <= 1 and reversal >= -0.0001, label + ": each hand advances in one continuous reach without repeated pauses or backwards strokes")
		verify(visible_pause_groups[0] <= 1 and visible_pause_groups[1] <= 1 and visible_reversal > -0.004, label + ": rendered hands have no repeated stop-start cycles or visible backwards strokes")
		verify(body_reversal > -0.001, label + ": the body progresses forward continuously")
	verify(maximum_visible_step < 0.1, label + ": rendered hands have no sudden jumps between sampled frames")
	verify(max_arc > 0.02, label + ": hands visibly lift away from the wall along the reach")
	verify(early_contact and contact_slip < 0.001, label + ": the hand settles onto its hold before completion and stays planted")
	verify(maximum_limb_error < 0.0005, label + ": arms and legs retain their lengths throughout the move")
	verify(not actor.moving and actor.current_hold_id == 1 and actor.total_moves == 2 and is_equal_approx(actor.stamina, 91.5) and Vector3(actor._gloves[hand].position).distance_to(START + delta + Vector3(0, 0, 0.025)) < 0.001, label + ": actual hand reaches its target with one move and the specified stamina cost")
	print("MOTION_METRICS ", label, " pause_groups=", pause_groups, " visible_pauses=", visible_pause_groups, " max_jump=", maximum_visible_step, " max_arc=", max_arc, " limb_error=", maximum_limb_error, " slip=", contact_slip)

func short_move_regression() -> void:
	var delta := Vector3(0.32, 0.20, 0.0)
	begin_variant(delta, 1, false)
	var original: Transform3D = actor._torso.transform
	var contacts: Array[Vector3] = [actor._gloves[0].position, actor._gloves[1].position]
	var early_stable: bool = actor._step_count == 1
	for p in [0.02, 0.06, 0.12, 0.25]:
		actor._process(float(p) * actor._move_duration - actor._move_time)
		early_stable = early_stable and actor._torso.transform.is_equal_approx(original)
		for hand in range(2):
			early_stable = early_stable and Vector3(actor._gloves[hand].position).distance_to(contacts[hand]) < 0.001
	verify(early_stable, "a one-step move keeps the starting torso pose and hand contacts while the first foot plants")
	var previous: Quaternion = actor._torso.basis.get_rotation_quaternion()
	var maximum_turn_step: float = 0.0
	var turn_started: bool = false
	for tick in range(30, 43):
		actor._process(float(tick) * 0.01 * actor._move_duration - actor._move_time)
		var rotation: Quaternion = actor._torso.basis.get_rotation_quaternion()
		maximum_turn_step = maxf(maximum_turn_step, previous.angle_to(rotation))
		turn_started = turn_started or original.basis.get_rotation_quaternion().angle_to(rotation) > 0.02
		previous = rotation
	verify(turn_started and maximum_turn_step < 0.025, "a one-step move starts turning gradually without a reversed blend or sudden rotation")
	actor._process(actor._move_duration)
	verify(not actor.moving and actor.current_hold_id == 1 and actor.total_moves == 2 and Vector3(actor._gloves[1].position).distance_to(START + delta + Vector3(0, 0, 0.025)) < 0.001, "the short smooth move finishes with the hand on its target")

func run() -> void:
	if "--qa-capture" not in OS.get_cmdline_user_args():
		push_error("Run this test with -- --qa-capture")
		quit(2)
		return
	actor = Actor.new()
	root.add_child(actor)
	actor.set_process(false)
	actor.setup({"id": 0, "position": START})
	actor._motion_rng.seed = 20261021
	actor.climbing = true
	actor.climb_to({"id": 1, "position": START + CASES[0]}, 1, 8.5)
	verify(not actor._searching_move, "the opening climbing move always uses a normal confident reach")
	actor._process(actor._move_duration)
	for delta: Vector3 in CASES:
		for hand in range(2):
			sample_motion(delta, hand, false)
	# Use the high reach for the rare reach-and-check variant too.
	for hand in range(2):
		sample_motion(CASES[2], hand, true)
	short_move_regression()

	# Keep consecutive moves on the same climber so opening-step protection cannot
	# hide searching, and the previous-variant guard is exercised naturally.
	actor.setup({"id": 0, "position": START})
	actor.climbing = true
	actor._motion_rng.seed = 49011
	var rare_count: int = 0
	var repeated_rare: int = 0
	var previous_rare: bool = false
	var completed: bool = true
	var costs_ok: bool = true
	for i in range(1000):
		actor.stamina = 100.0
		var next_position: Vector3 = actor.get_reach_origin() + CASES[i % CASES.size()]
		completed = actor.climb_to({"id": i + 1, "position": next_position}, i % 2, 8.5) and completed
		var rare: bool = actor._searching_move
		if i > 0 and rare:
			rare_count += 1
			if previous_rare:
				repeated_rare += 1
		previous_rare = rare
		actor._process(actor._move_duration + 0.001)
		completed = completed and not actor.moving and actor.current_hold_id == i + 1 and actor.total_moves == i + 1
		costs_ok = costs_ok and is_equal_approx(actor.stamina, 91.5)
	var ratio: float = float(rare_count) / 999.0
	verify(ratio >= 0.05 and ratio <= 0.11 and repeated_rare == 0, "1000 seeded moves keep searching near 8 percent without consecutive searches")
	verify(completed and costs_ok, "both variants complete reliably with identical move counting and requested stamina cost")
	print("SEARCH_METRICS sample=999 searching=", rare_count, " ratio=", ratio, " consecutive=", repeated_rare)

	# Different simulation rates must reach exactly the same rendered end pose.
	var ends: Array[Vector3] = []
	var timed_poses: Array[Transform3D] = []
	var timed_hands: Array[Vector3] = []
	for rate in [30, 60, 120]:
		begin_variant(CASES[1], 1, false)
		for p in [0.25, 0.50, 0.75]:
			var target_time: float = float(p) * actor._move_duration
			while actor._move_time < target_time - 0.0000001:
				actor._process(minf(1.0 / float(rate), target_time - actor._move_time))
			timed_poses.append(actor._torso.transform)
			timed_hands.append(actor._gloves[0].position)
			timed_hands.append(actor._gloves[1].position)
		var max_frames: int = ceili(actor._move_duration * float(rate)) + 2
		for frame in range(max_frames):
			if not actor.moving:
				break
			actor._process(1.0 / float(rate))
		ends.append(actor.get_body_position())
		ends.append(actor._gloves[1].position)
	verify(ends[0].is_equal_approx(ends[2]) and ends[0].is_equal_approx(ends[4]) and ends[1].is_equal_approx(ends[3]) and ends[1].is_equal_approx(ends[5]), "30, 60 and 120 FPS produce the same completed torso and hand positions")
	var timed_match: bool = true
	for i in range(3):
		for rate_index in [1, 2]:
			timed_match = timed_match and timed_poses[i].is_equal_approx(timed_poses[rate_index * 3 + i])
			for hand in range(2):
				timed_match = timed_match and timed_hands[i * 2 + hand].is_equal_approx(timed_hands[rate_index * 6 + i * 2 + hand])
	verify(timed_match, "30, 60 and 120 FPS agree on torso rotation and both visible hands at 25, 50 and 75 percent of the motion")
	actor.queue_free()
	await process_frame
	print("SMOOTH_MOTION_RESULT checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

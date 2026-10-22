extends SceneTree
## Observe rendered shoes and the actual shin ends; no save or route controller.
const Actor = preload("res://scripts/climber.gd")
const START := Vector3(0.0, 2.5, 0.45)
const SLICES: int = 360
var checks: int = 0
var failures: Array[String] = []
var actor: Node3D

func _initialize() -> void:
	call_deferred("run")

func verify(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		print("FAIL ", message)

func ankle(index: int) -> Vector3:
	return actor._shins[index].transform * Vector3(0.0, 0.5, 0.0)

func hip(index: int) -> Vector3:
	return actor._torso.transform * Vector3(-0.13 if index == 0 else 0.13, -0.29, 0.0)

func knee_plane(index: int) -> Vector3:
	var axis: Vector3 = (ankle(index) - hip(index)).normalized()
	var bend: Vector3 = actor._knees[index].position - hip(index)
	return bend - axis * bend.dot(axis)

func limb_error() -> float:
	var error: float = 0.0
	for index in range(2):
		var knee: Vector3 = actor._knees[index].position
		error = maxf(error, absf(hip(index).distance_to(knee) - 0.43))
		error = maxf(error, absf(knee.distance_to(ankle(index)) - 0.44))
	return error

func begin(style: String, hand: int, support: int, searching: bool, prepared_lean: float = 2.0) -> bool:
	var side: float = -1.0 if hand == 0 else 1.0
	var delta: Vector3
	match style:
		"front": delta = Vector3(side * 0.24, 1.25, 0.0)
		"side": delta = Vector3(side * 1.65, 0.25, 0.0)
		"high_step": delta = Vector3(side * 0.25, 2.10, 0.0)
		_: delta = Vector3(side * 0.90, 0.95, 0.0)
	for attempt in range(200):
		actor.support_foot = -1
		actor.setup({"id": 0, "position": START})
		actor.climbing = true
		actor.total_moves = 1
		actor.set_support_foot(support)
		actor.set_lean((side * 0.90 if style == "drop_knee" else 0.0) if prepared_lean > 1.0 else prepared_lean)
		if not actor.climb_to({"id": 1, "position": START + delta}, hand, 8.5):
			return false
		if bool(actor._searching_move) == searching:
			return true
		actor._process(actor._move_duration + 0.001)
	return false

func repeated_starts(points: Array[Vector3], seconds_per_sample: float) -> int:
	# Ignore slow easing at either end. A genuine restart requires a sustained
	# near-stop between two portions of visible travel, rather than one slow frame.
	var started: bool = false
	var stopped_for: float = 0.0
	var pause_origin: Vector3 = points[0]
	var restarts: int = 0
	var armed: bool = false
	for index in range(2, points.size() - 2):
		var speed: float = points[index - 2].distance_to(points[index + 2]) / (4.0 * seconds_per_sample)
		if not started:
			started = points[index].distance_to(points[0]) > 0.035 and speed > 0.15
			continue
		if speed < 0.060:
			if stopped_for == 0.0:
				pause_origin = points[index]
			stopped_for += seconds_per_sample
			armed = armed or stopped_for >= 0.055
		elif speed > 0.15:
			if armed:
				if points[index].distance_to(pause_origin) > 0.025:
					restarts += 1
					armed = false
					stopped_for = 0.0
			else:
				stopped_for = 0.0
	return restarts

func clearance_peaks(points: Array[Vector3]) -> int:
	# Measure wall clearance relative to the path's endpoints so a raised free
	# leg or sloped wall cannot masquerade as another lift-and-plant cycle.
	var span: Vector3 = points[-1] - points[0]
	span.z = 0.0
	var valley: float = 0.0
	var peak: float = 0.0
	var seeking_peak: bool = false
	var count: int = 0
	for point: Vector3 in points:
		var progress: float = clampf((point - points[0]).dot(span) / maxf(span.length_squared(), 0.0001), 0.0, 1.0)
		var height: float = point.z - lerpf(points[0].z, points[-1].z, progress)
		if not seeking_peak:
			valley = minf(valley, height)
			if height > valley + 0.018:
				seeking_peak = true
				peak = height
		else:
			peak = maxf(peak, height)
			if height < peak - 0.018:
				count += 1
				seeking_peak = false
				valley = height
	return count

func sample(style: String, hand: int, support: int, searching: bool) -> void:
	var label: String = "%s hand=%d support=%d %s" % [style, hand, support, "rare" if searching else "normal"]
	if not begin(style, hand, support, searching):
		verify(false, label + " begins")
		return
	verify(actor._motion == style, label + " selects the intended action")
	var dt: float = actor._move_duration / float(SLICES)
	var paths: Array = [Array([], TYPE_VECTOR3, "", null), Array([], TYPE_VECTOR3, "", null)]
	var initial_support: Vector3 = ankle(support) if support >= 0 else Vector3.ZERO
	var early_support_slip: float = 0.0
	var worst_limb: float = 0.0
	var largest_shoe_step: float = 0.0
	var largest_knee_step: float = 0.0
	var plane_alignment: float = 1.0
	var previous_knees: Array[Vector3] = [actor._knees[0].position, actor._knees[1].position]
	var previous_planes: Array[Vector3] = [knee_plane(0), knee_plane(1)]
	for foot in range(2):
		paths[foot].append(actor._boots[foot].position)
	for tick in range(1, SLICES + 1):
		actor._process(dt if tick < SLICES else maxf(dt, actor._move_duration - actor._move_time + 0.0000001))
		worst_limb = maxf(worst_limb, limb_error())
		if support >= 0 and float(tick) / float(SLICES) <= 0.035:
			early_support_slip = maxf(early_support_slip, ankle(support).distance_to(initial_support))
		for foot in range(2):
			var shoe: Vector3 = actor._boots[foot].position
			largest_shoe_step = maxf(largest_shoe_step, shoe.distance_to(paths[foot][-1]))
			paths[foot].append(shoe)
			var knee: Vector3 = actor._knees[foot].position
			var plane: Vector3 = knee_plane(foot)
			largest_knee_step = maxf(largest_knee_step, knee.distance_to(previous_knees[foot]))
			if plane.length() > 0.06 and previous_planes[foot].length() > 0.06:
				plane_alignment = minf(plane_alignment, plane.normalized().dot(previous_planes[foot].normalized()))
			previous_knees[foot] = knee
			previous_planes[foot] = plane
	var starts: Array[int] = []
	var peaks: Array[int] = []
	var tail_slip: float = 0.0
	var after_landing_slip: float = 0.0
	for foot in range(2):
		var path: Array[Vector3] = paths[foot]
		starts.append(repeated_starts(path, dt))
		peaks.append(clearance_peaks(path))
		var landed: bool = false
		for tick in range(ceili(0.50 * float(SLICES)), path.size()):
			if path[tick].distance_to(path[-1]) < 0.001:
				landed = true
			if landed:
				after_landing_slip = maxf(after_landing_slip, path[tick].distance_to(path[-1]))
		for tick in range(ceili(0.97 * float(SLICES)), path.size()):
			tail_slip = maxf(tail_slip, path[tick].distance_to(path[-1]))
	verify(starts[0] <= (1 if searching else 0) and starts[1] <= (1 if searching else 0), label + " has no repeated stop-and-restart foot shuffles")
	verify(peaks[0] <= 1 and peaks[1] <= 1, label + " makes at most one pronounced lift off the wall for each shoe")
	verify(early_support_slip < 0.001, label + " keeps its chosen support planted at the start")
	verify(after_landing_slip < 0.003 and tail_slip < 0.003, label + " lands before completion and remains planted")
	verify(worst_limb < 0.0005, label + " preserves real thigh and shin lengths")
	verify(largest_shoe_step < 0.04 and largest_knee_step < 0.06 and plane_alignment > 0.0, label + " has no shoe teleport or knee plane flip, including arrival")
	verify(not actor.moving and actor.current_hold_id == 1 and actor.total_moves == 2 and absf(actor.stamina - 91.5) < 0.0001, label + " preserves arrival and the specified stamina cost")
	print("FOOT_METRICS ", label, " restarts=", starts, " clearance_peaks=", peaks, " support_slip=", early_support_slip, " landed_slip=", after_landing_slip, " tail_slip=", tail_slip, " shoe_step=", largest_shoe_step, " knee_step=", largest_knee_step, " plane_dot=", plane_alignment, " limb_error=", worst_limb)
	check_idle_and_next_step(label, hand)

func check_idle_and_next_step(label: String, hand: int) -> void:
	var contacts: Array[Vector3] = [actor._boots[0].position, actor._boots[1].position]
	var slip: float = 0.0
	for tick in range(30):
		actor._process(0.25 / 30.0)
		for foot in range(2):
			slip = maxf(slip, contacts[foot].distance_to(actor._boots[foot].position))
	verify(slip < 0.001, label + " keeps both actual shoes fixed for 250ms after arrival")
	var next: Vector3 = actor.get_reach_origin() + Vector3(0.2, 1.15, 0.0)
	var next_started: bool = actor.climb_to({"id": 2, "position": next}, 1 - hand, 4.0)
	actor._process(0.0)
	var seam: float = 0.0
	for foot in range(2):
		seam = maxf(seam, contacts[foot].distance_to(actor._boots[foot].position))
	verify(next_started and seam < 0.001 and limb_error() < 0.0005, label + " begins the next action from those same rendered contacts")

func check_extreme_preparation() -> void:
	# The 2.1m upward edge is longer than a leg. The hips and feet must advance
	# together while the rendered two-bone chain obeys its physical reach cap.
	for hand in range(2):
		for support: int in [-1, 0, 1]:
			for lean: float in [-1.0, 1.0]:
				var label: String = "2.1m edge hand=%d support=%d lean=%.1f" % [hand, support, lean]
				verify(begin("high_step", hand, support, false, lean), label + " begins")
				var previous: Array[Vector3] = [actor._boots[0].position, actor._boots[1].position]
				actor._process(0.0)
				var seam: float = 0.0
				for foot in range(2):
					seam = maxf(seam, previous[foot].distance_to(actor._boots[foot].position))
				var worst_limb: float = 0.0
				var longest: float = 0.0
				var max_step: float = 0.0
				for tick in range(1, SLICES + 1):
					actor._process(actor._move_duration / float(SLICES) + 0.0000001)
					worst_limb = maxf(worst_limb, limb_error())
					for foot in range(2):
						longest = maxf(longest, hip(foot).distance_to(ankle(foot)))
						max_step = maxf(max_step, previous[foot].distance_to(actor._boots[foot].position))
						previous[foot] = actor._boots[foot].position
				verify(seam < 0.001 and worst_limb < 0.0005 and longest <= 0.8651 and max_step < 0.04, label + " keeps real leg lengths and bounded reach without shoe jumps")
				check_idle_and_next_step(label, hand)
	# A deliberately unreachable raw request proves clamping acts on the actual
	# shin endpoint, including a fully prepared hip; this is a local IK fixture.
	for support: int in [-1, 0, 1]:
		for lean: float in [-1.0, 1.0]:
			actor.support_foot = -1
			actor.setup({"id": 0, "position": START})
			actor.climbing = true
			actor.set_support_foot(support)
			actor.set_lean(lean)
			var foot: int = support if support >= 0 else 0
			var origin: Vector3 = hip(foot)
			var axis: Vector3 = Vector3(-0.3 if foot == 0 else 0.3, -1.0, 0.2).normalized()
			actor._feet[foot] = origin + axis * 2.1
			actor._update_pose()
			var actual: Vector3 = ankle(foot) - origin
			verify(absf(actual.length() - 0.865) < 0.0001 and actual.normalized().dot(axis) > 0.99999 and limb_error() < 0.0005, "raw 2.1m foot request support=%d lean=%.1f clamps the rendered ankle along its intended ray" % [support, lean])

func fps_samples(style: String, hand: int, fps: int) -> Array[Dictionary]:
	begin(style, hand, hand if style == "drop_knee" else 1 - hand, false)
	var samples: Array[Dictionary] = []
	for fraction in [0.10, 0.25, 0.50, 0.75, 0.95, 1.0]:
		var target_time: float = fraction * actor._move_duration
		while actor.moving and actor._move_time < target_time - 0.0000001:
			actor._process(minf(1.0 / float(fps), target_time - actor._move_time))
		var pose: Dictionary = {"torso": actor._torso.transform}
		for foot in range(2):
			pose["boot%d" % foot] = actor._boots[foot].position
			pose["ankle%d" % foot] = ankle(foot)
			pose["knee%d" % foot] = actor._knees[foot].position
		samples.append(pose)
	return samples

func check_summit_transition() -> void:
	for support in range(2):
		var started: bool = begin("front", support, support, false)
		actor._process(actor._move_duration + 0.001)
		var contacts: Array[Vector3] = [actor._boots[0].position, actor._boots[1].position]
		actor.celebrate(START + Vector3(0, 4.0, -1.25))
		actor._process(0.0)
		var seam: float = 0.0
		for foot in range(2):
			seam = maxf(seam, contacts[foot].distance_to(actor._boots[foot].position))
		verify(started and actor.summit_mode and seam < 0.001, "support=%d carries both rendered shoes continuously into the first summit frame" % support)
		verify(limb_error() < 0.0005, "support=%d preserves both real leg lengths on the first summit frame" % support)

func run() -> void:
	if "--qa-capture" not in OS.get_cmdline_user_args():
		quit(2)
		return
	actor = Actor.new()
	root.add_child(actor)
	actor.set_process(false)
	actor._motion_rng.seed = 72217
	for style: String in ["front", "side", "high_step", "drop_knee"]:
		for hand in range(2):
			for support: int in [-1, 0, 1]:
				if style == "drop_knee" and support != hand:
					continue
				for searching: bool in [false, true]:
					sample(style, hand, support, searching)
			var reference: Array[Dictionary] = fps_samples(style, hand, 30)
			var matches: bool = true
			for fps in [60, 120]:
				var actual: Array[Dictionary] = fps_samples(style, hand, fps)
				for tick in range(reference.size()):
					for key: String in reference[tick]:
						matches = matches and reference[tick][key].is_equal_approx(actual[tick][key])
			verify(matches, "%s hand=%d renders the same hips, knees, ankles and shoes at 30/60/120 FPS" % [style, hand])
	check_extreme_preparation()
	check_summit_transition()
	actor.queue_free()
	await process_frame
	print("FOOT_CONTINUITY_RESULT checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

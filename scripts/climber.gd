extends Node3D

signal reached_hold(hold_id: int)
signal fell
signal effort_started
signal hand_contact(hold_id: int, hand: int, kind: String)
const ARM_REACH: float = 0.715
const STEP_REACH: float = 2.10
const LEAN_SHIFT: float = 0.32
const SEARCH_CHANCE: float = 0.08
var _motion_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _searching_move: bool = false
var _previous_searching_move: bool = false
var stamina: float = 100.0
var terrain_drain: float = 0.0
var support_foot: int = -1
var _move_support_foot: int = -1
var _traverse: bool = false
var _motion: String = "front"
var _motion_direction: float = 1.0
var _motion_turn: float = 0.0
var _motion_crouch: float = 0.0
var _motion_roll: float = 0.0
var _motion_drop: float = 0.0
var _motion_drop_foot: float = 0.0
var _move_start_drop: float = 0.0
var _stance_weight: float = 0.0
var _support_feedback_visible: bool = true
var _support_marker: MeshInstance3D
var _support_material: StandardMaterial3D
var _outfit_index: int = 0
var _jacket_material: StandardMaterial3D
var _pack_material: StandardMaterial3D
var _pants_material: StandardMaterial3D
var _fabric_color: ImageTexture
var _fabric_normal: ImageTexture
var climbing: bool = false
var moving: bool = false
var current_hold_id: int = 0
var checkpoint_position: Vector3 = Vector3(0, 1, 0.45)
var checkpoint_hold_id: int = 0
var summit_mode: bool = false
var total_moves: int = 0
var _body: Vector3
var _reach: Vector3
var _hands: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _feet: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _old_hands: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _old_feet: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _new_hands: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _new_feet: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _old_body: Vector3
var _new_body: Vector3
var _target: Dictionary = {}
var _hand: int = 0
var _last_hand: int = 1
var _move_time: float = 0.0
var _effort_sent: bool = false
var _contact_pending: bool = false
var _move_start_lean: float = 0.0
var _move_duration: float = 0.90
# Distance pacing for duration and the first plant only; never repeat foot swings.
var _step_count: int = 1
var _time: float = 0.0
var _lean: float = 0.0
var _lean_target: float = 0.0
var _chalk_cooldown: float = 0.0
var _chalk_time: float = 0.0
var _summit_time: float = 0.0
var _summit_floor: Vector3 = Vector3.ZERO
var _fall_sent: bool = false
var _built: bool = false
var _torso: Node3D
var _head: Node3D
var _upper_arms: Array[MeshInstance3D] = []
var _forearms: Array[MeshInstance3D] = []
var _thighs: Array[MeshInstance3D] = []
var _shins: Array[MeshInstance3D] = []
var _gloves: Array[MeshInstance3D] = []
var _boots: Array[MeshInstance3D] = []
var _elbows: Array[MeshInstance3D] = []
var _knees: Array[MeshInstance3D] = []
var _rope: Array[MeshInstance3D] = []
var _dust: Array[MeshInstance3D] = []

func _init() -> void:
	_motion_rng.randomize()

func setup(start_hold: Dictionary) -> void:
	if not _built:
		_build_avatar()
	checkpoint_position = start_hold.get("position", Vector3(0, 1, 0.45))
	checkpoint_hold_id = int(start_hold.get("id", 0))
	total_moves = 0
	climbing = false
	_last_hand = 1
	recover()

func climb_to(hold: Dictionary, hand: int = -1, effort: float = 4.0) -> bool:
	var move_cost: float = maxf(0.0, effort)
	if moving or summit_mode or stamina < move_cost or not climbing:
		return false
	_target = hold.duplicate()
	var target: Vector3 = hold.get("position", _reach)
	_hand = 1 - _last_hand if hand < 0 else clampi(hand, 0, 1)
	_last_hand = _hand
	_old_body = _body
	_move_start_drop = stance_drop_weight(_lean)
	# Start from the rendered contacts, including the raised free foot in a stance.
	for i in range(2):
		_old_hands[i] = _gloves[i].position
		_old_feet[i] = _boots[i].position - Vector3(0, -0.015, -0.045)
	_hands = _old_hands.duplicate()
	_feet = _old_feet.duplicate()
	var side: float = -1.0 if _hand == 0 else 1.0
	_new_body = target + Vector3(-side * 0.14, -0.72, 0.49)
	_new_hands[_hand] = target + Vector3(0, 0, 0.025)
	_new_hands[1 - _hand] = target + Vector3(-side * 0.48, -0.32, 0.01)
	_new_feet[0] = _new_body + Vector3(-0.19, -0.92, -0.28)
	_new_feet[1] = _new_body + Vector3(0.19, -0.88, -0.28)
	_step_count = maxi(1, ceili(_old_body.distance_to(_new_body) / 0.40))
	var displacement: Vector3 = _new_body - _old_body
	_traverse = absf(displacement.x) > 0.45 and absf(displacement.x) > absf(displacement.y) * 0.55
	_motion = "side" if _traverse else ("high_step" if displacement.y > 1.55 else "front")
	if can_drop_knee(target, _hand):
		_motion = "drop_knee"
	_motion_direction = signf(displacement.x) if absf(displacement.x) > 0.12 else side
	# A little uncertainty is a cosmetic variation, never the default climbing gait.
	_searching_move = total_moves > 0 and not _previous_searching_move and _motion_rng.randf() < SEARCH_CHANCE
	_previous_searching_move = _searching_move
	_move_support_foot = support_foot
	_move_duration = maxf(0.90, float(_step_count) * 0.42)
	if _traverse:
		_move_duration += 0.20
	elif _motion == "high_step":
		_move_duration += 0.18
	_move_time = 0.0
	_effort_sent = false
	_contact_pending = true
	_move_start_lean = _lean
	_move_start_drop = stance_drop_weight(_lean)
	_motion_drop = _move_start_drop
	moving = true
	stamina = maxf(0.0, stamina - move_cost)
	return true

func get_reach_origin() -> Vector3:
	return _reach

func get_body_position() -> Vector3:
	return body_transform_at(_lean).origin

func get_motion_name() -> String:
	if summit_mode:
		return "翻越山顶"
	if moving:
		if _searching_move:
			return "探点落手"
		return {"front": "正身蹬起", "side": "侧身横渡", "high_step": "屈膝高踩", "drop_knee": "折膝侧伸"}.get(_motion, "正身蹬起")
	if stance_drop_weight(_lean) > 0.35:
		return "左侧转髋准备" if support_foot == 0 else "右侧转髋准备"
	return "正身待发" if support_foot < 0 else ("左脚踩稳" if support_foot == 0 else "右脚踩稳")

func can_drop_knee(target: Vector3, hand: int) -> bool:
	var side: float = -1.0 if hand == 0 else 1.0
	var span: Vector3 = target - _reach
	return support_foot == hand and span.x * side >= 0.399 and span.y >= 0.349 and span.y <= 1.601

func stance_drop_weight(lean_value: float) -> float:
	if support_foot < 0 or summit_mode or not climbing:
		return 0.0
	var side: float = -1.0 if support_foot == 0 else 1.0
	return smoothstep(0.30, 0.80, lean_value * side)

func get_foot_position(index: int) -> Vector3:
	return _boots[clampi(index, 0, 1)].global_position if _built else Vector3.ZERO

func get_support_position() -> Vector3:
	var foot: int = _move_support_foot if moving else support_foot
	return get_foot_position(foot) if foot >= 0 else get_body_position()

func _free_foot_offset(index: int, loaded: int) -> Vector3:
	if loaded < 0 or index == loaded:
		return Vector3.ZERO
	var side: float = -1.0 if index == 0 else 1.0
	return Vector3(-side * 0.055, 0.245, 0.055)

func set_support_feedback_visible(value: bool) -> void:
	_support_feedback_visible = value
	_update_support_marker()

func body_transform_at(lean_value: float) -> Transform3D:
	var weight: float = clampf(lean_value, -1.0, 1.0)
	var foot: int = _move_support_foot if moving else support_foot
	var support_shift: float = (-0.045 if foot == 0 else 0.045) if foot >= 0 else 0.0
	var side: float = -1.0 if foot == 0 else 1.0
	var drop: float = _motion_drop if moving else stance_drop_weight(weight)
	var position: Vector3 = _body + Vector3(weight * LEAN_SHIFT + support_shift, -absf(weight) * 0.025 - _motion_crouch, -absf(weight) * 0.055)
	# Bring the loaded hip to the wall and advance the same-side shoulder. Reach
	# queries share this exact transform; no artificial arm-length bonus is added.
	position += Vector3(side * 0.14, -0.055, -0.11) * drop
	var turn: float = weight * -0.14 + _motion_roll
	return Transform3D(Basis(Vector3.UP, _motion_turn + side * 0.90 * drop) * Basis(Vector3.BACK, turn), position)

func get_shoulder_position(hand: int, lean_value: float = 2.0) -> Vector3:
	var side: float = -1.0 if hand == 0 else 1.0
	return body_transform_at(_lean if lean_value > 1.0 else lean_value) * Vector3(side * 0.225, 0.22, -0.02)

func rest(delta: float) -> void:
	if not moving:
		stamina = minf(100.0, stamina + delta * 23.0)
		_fall_sent = false

func chalk() -> bool:
	if moving or summit_mode or not climbing or _chalk_cooldown > 0.0:
		return false
	_chalk_cooldown = 7.0
	_chalk_time = 0.95
	stamina = minf(100.0, stamina + 10.0)
	return true

func recover() -> void:
	_contact_pending = false
	_reach = checkpoint_position
	current_hold_id = checkpoint_hold_id
	_body = _reach + Vector3(0.10, -0.72, 0.49)
	_hands[0] = _reach + Vector3(-0.13, -0.08, 0.02)
	_hands[1] = _reach + Vector3(0.13, -0.04, 0.02)
	_feet[0] = _body + Vector3(-0.19, -0.92, -0.28)
	_feet[1] = _body + Vector3(0.19, -0.88, -0.28)
	moving = false
	summit_mode = false
	stamina = 100.0
	_fall_sent = false
	_chalk_time = 0.0
	_chalk_cooldown = 0.0
	_summit_time = 0.0
	_move_time = 0.0
	_searching_move = false
	_motion_turn = 0.0
	_motion_crouch = 0.0
	_motion_roll = 0.0
	_motion_drop = 0.0
	_motion_drop_foot = 0.0
	_move_start_drop = 0.0
	_stance_weight = 1.0 if support_foot >= 0 else 0.0
	_lean = 0.0
	_lean_target = 0.0
	_target.clear()
	for rope_part in _rope:
		rope_part.visible = true
	if _built:
		_update_pose()

func celebrate(summit_position: Vector3 = Vector3.ZERO) -> void:
	_contact_pending = false
	moving = false
	summit_mode = true
	_motion_turn = 0.0
	_motion_crouch = 0.0
	_motion_roll = 0.0
	_motion_drop = 0.0
	_motion_drop_foot = 0.0
	_move_start_drop = 0.0
	_summit_floor = summit_position if summit_position != Vector3.ZERO else _reach + Vector3(0, 1.95, -1.25)
	_summit_time = 0.0
	_chalk_time = 0.0
	for rope_part in _rope:
		rope_part.visible = false
	_old_body = _body
	_old_hands = _hands.duplicate()
	# The final climbing stance can already have a bent free leg. Carry its
	# rendered ankle into the summit pull so the mode switch cannot drop it.
	for i in range(2):
		_old_feet[i] = _boots[i].position - Vector3(0, -0.015, -0.045)
	stamina = 100.0

func set_lean(value: float) -> void:
	_lean_target = clampf(value, -1.0, 1.0)
	# Input already moves continuously. Rendering and reach must use the same pose.
	_lean = _lean_target
	if _built:
		_update_pose()

func set_support_foot(index: int) -> void:
	# Snapshot on climb_to so changing the next foothold cannot pop an active pose.
	support_foot = clampi(index, -1, 1)
	if not moving:
		_stance_weight = 1.0 if support_foot >= 0 else 0.0
	if _built:
		_update_pose()

func set_outfit(index: int) -> void:
	_outfit_index = clampi(index, 0, 2)
	if _jacket_material == null:
		return
	var jackets: Array[String] = ["e85c34", "4f8063", "80b8d5"]
	var packs: Array[String] = ["346a69", "b38c59", "405e83"]
	var trousers: Array[String] = ["253746", "263b43", "343c52"]
	_jacket_material.albedo_color = Color(jackets[_outfit_index])
	_pack_material.albedo_color = Color(packs[_outfit_index])
	_pants_material.albedo_color = Color(trousers[_outfit_index])

func _process(delta: float) -> void:
	if not _built:
		return
	_time += delta
	_chalk_cooldown = maxf(0.0, _chalk_cooldown - delta)
	_chalk_time = maxf(0.0, _chalk_time - delta)
	if summit_mode:
		_summit_time += delta
		# Pull vertically past the lip, then step onto the top before raising arms.
		var pull: float = smoothstep(0.0, 2.0, _summit_time)
		var step: float = smoothstep(1.45, 2.70, _summit_time)
		_body = _old_body.lerp(_summit_floor + Vector3(0, 1.18, 0), pull)
		_body.z = lerpf(_old_body.z, _summit_floor.z, step)
		for i in range(2):
			var side: float = -1.0 if i == 0 else 1.0
			var lip: Vector3 = Vector3(_summit_floor.x + side * 0.31, _summit_floor.y + 0.05, 0.75)
			var raised: Vector3 = _body + Vector3(side * 0.52, 0.78 + sin(_time * 2.0) * 0.035, 0.05)
			_hands[i] = _old_hands[i].lerp(lip, smoothstep(0.0, 1.2, _summit_time))
			_hands[i] = _hands[i].lerp(raised, smoothstep(1.75, 3.15, _summit_time))
			var wall_foot: Vector3 = _body + Vector3(side * 0.19, -0.88, -0.28)
			var top_foot: Vector3 = _summit_floor + Vector3(side * 0.22, 0.06, 0)
			_feet[i] = _old_feet[i].lerp(wall_foot, pull)
			_feet[i] = _feet[i].lerp(top_foot, smoothstep(1.30 + float(i) * 0.25, 2.60 + float(i) * 0.20, _summit_time))
	elif moving:
		_advance_move(delta)
	elif climbing:
		_stance_weight = move_toward(_stance_weight, 1.0 if support_foot >= 0 else 0.0, delta * 5.0)
		stamina = maxf(0.0, stamina - delta * (0.38 + maxf(0.0, terrain_drain)))
		if stamina <= 0.0 and not _fall_sent:
			_fall_sent = true
			fell.emit()
	_update_pose()
	_try_hand_contact()

func _try_hand_contact() -> void:
	if not _contact_pending or summit_mode or not climbing or _move_time < _move_duration * 0.5:
		return
	# The rendered palm includes the physical arm constraint, so raw hand timing
	# alone must not trigger the contact before the arm actually reaches the rock.
	if _gloves[_hand].position.distance_to(_new_hands[_hand]) <= 0.012:
		_contact_pending = false
		hand_contact.emit(int(_target.get("id", current_hold_id)), _hand, str(_target.get("kind", "normal")))

func _reach_progress(p: float, start: float, finish: float) -> float:
	if not _searching_move:
		return smoothstep(start, finish, p)
	# One brief check in the middle, with eased entry/exit and unchanged total time.
	var pause_start: float = 0.48
	var pause_end: float = pause_start + 0.10 / _move_duration
	return 0.5 * smoothstep(start, pause_start, p) + 0.5 * smoothstep(pause_end, finish, p)

func _advance_move(delta: float) -> void:
	_move_time += delta
	var p: float = clampf(_move_time / _move_duration, 0.0, 1.0)
	# Settle over the new footholds smoothly instead of snapping the torso at arrival.
	_lean = lerpf(_move_start_lean, 0.0, smoothstep(0.55, 0.88, p))
	_lean_target = _lean
	# Only the first foot plant uses the authored distance. Each leg then follows
	# one continuous path, rather than restarting its swing every 0.4 metres.
	var plant: float = 0.30 / float(_step_count)
	if not _effort_sent and p >= plant:
		_effort_sent = true
		effort_started.emit()
	var body_fraction: float = _reach_progress(p, plant, 0.90)
	_body = _old_body.lerp(_new_body, body_fraction)
	var turn_envelope: float = smoothstep(plant, maxf(0.28, plant + 0.10), p) * (1.0 - smoothstep(0.64, 0.88, p))
	var release_drop: float = smoothstep(plant, 0.86, p)
	_motion_drop = lerpf(_move_start_drop, 0.0, release_drop)
	_motion_drop_foot = 0.0
	if _motion == "drop_knee":
		var drop_envelope: float = smoothstep(plant, maxf(0.30, plant + 0.12), p) * (1.0 - smoothstep(0.62, 0.88, p))
		_motion_drop = lerpf(_motion_drop, 1.0, drop_envelope)
		# Transfer weight to the free foot, place the old support higher, then roll
		# its knee inward. Idle weight shifts never slide an already planted boot.
		_motion_drop_foot = smoothstep(plant + 0.16, maxf(0.46, plant + 0.30), p) * (1.0 - smoothstep(0.62, 0.88, p))
	var fold: float = sin(smoothstep(plant, 0.80, p) * PI)
	_motion_turn = _motion_direction * (0.62 if _motion == "side" else (0.20 if _motion == "high_step" else (0.04 if _motion == "drop_knee" else 0.06))) * turn_envelope
	_motion_crouch = fold * (0.085 if _motion == "high_step" else 0.025)
	_motion_roll = _motion_direction * (0.09 if _motion == "side" else 0.025) * sin(body_fraction * PI) * turn_envelope
	_body.z += sin(body_fraction * PI) * (0.045 if _motion == "high_step" else 0.025)
	var loaded_foot: int = _move_support_foot if _move_support_foot >= 0 else 1 - _hand
	var free_foot: int = 1 - loaded_foot
	for i in range(2):
		var end_foot: Vector3 = _new_feet[i] + _free_foot_offset(i, _move_support_foot)
		# Both legs follow the body closely enough to preserve their real lengths.
		# The free toe lifts first; the loaded leg stays planted until the push starts.
		var fp: float = _reach_progress(p, 0.0, 0.88) if i == free_foot else _reach_progress(p, plant, 0.93)
		_feet[i] = _old_feet[i].lerp(end_foot, fp)
		var lift: float = (0.22 if _motion == "high_step" else (0.13 if _motion == "side" else 0.095)) if i == free_foot else 0.055
		_feet[i].y += sin(fp * PI) * lift
		_feet[i].z += sin(fp * PI) * 0.045
		if i == free_foot:
			_feet[i].z += smoothstep(0.0, plant, p) * (1.0 - smoothstep(0.60, 0.88, p)) * 0.055
		# Leading hand reaches once, trailing hand follows. Lift off the rock instead
		# of sliding along it; settle both palms before the action is complete.
		var hp: float = _reach_progress(p, plant + (0.015 if i == _hand else 0.065), 0.88 if i == _hand else 0.94)
		_hands[i] = _old_hands[i].lerp(_new_hands[i], hp)
		_hands[i].z += sin(hp * PI) * (0.10 if i == _hand else 0.08)
		if _searching_move and i == _hand:
			var check_phase: float = smoothstep(0.48, 0.48 + 0.10 / _move_duration, p)
			_hands[i].x += _motion_direction * sin(check_phase * TAU) * 0.018
	if p >= 1.0:
		# A long frame can skip the contact window. Resolve the actual final pose
		# before arrival callbacks can switch to a rest or summit animation.
		_update_pose()
		_try_hand_contact()
		moving = false
		_motion_turn = 0.0
		_motion_crouch = 0.0
		_motion_roll = 0.0
		_motion_drop = 0.0
		_motion_drop_foot = 0.0
		# Finish directly in the ready stance. Converting the moving end contacts
		# into idle coordinates avoids raising the free foot again after arrival.
		_stance_weight = 1.0 if support_foot >= 0 else 0.0
		for i in range(2):
			_feet[i] = _new_feet[i] + _free_foot_offset(i, _move_support_foot) - _free_foot_offset(i, support_foot)
		_body = _new_body
		_reach = _target.get("position", _reach)
		current_hold_id = int(_target.get("id", current_hold_id))
		total_moves += 1
		if bool(_target.get("checkpoint", false)):
			checkpoint_position = _reach
			checkpoint_hold_id = current_hold_id
		reached_hold.emit(current_hold_id)

func _update_pose() -> void:
	_torso.transform = body_transform_at(_lean)
	var visual_body: Vector3 = _torso.position
	_head.rotation.y = sin(_time * 0.5) * 0.07
	for i in range(2):
		var side: float = -1.0 if i == 0 else 1.0
		var shoulder: Vector3 = get_shoulder_position(i)
		var palm: Vector3 = _hands[i]
		if _chalk_time > 0.0 and i == 1:
			palm = palm.lerp(visual_body + Vector3(0.30, -0.24, 0.30), sin((1.0 - _chalk_time / 0.95) * PI))
		# Keep the continuous reach inside the same physical arm length as idle poses.
		palm = shoulder + (palm - shoulder).limit_length(ARM_REACH)
		var elbow: Vector3 = _joint(shoulder, palm, 0.34, 0.38, Vector3(side * 0.75, -0.45, 0.5))
		_segment(_upper_arms[i], shoulder, elbow)
		_segment(_forearms[i], elbow, palm)
		_elbows[i].position = elbow
		_gloves[i].position = palm
		_gloves[i].rotation.z = side * -0.25
		var hip: Vector3 = _torso.transform * Vector3(side * 0.13, -0.29, 0)
		var foot: Vector3 = _feet[i]
		var loaded_foot: int = _move_support_foot if moving else support_foot
		var drop: float = (_motion_drop if moving else stance_drop_weight(_lean)) if i == loaded_foot else 0.0
		# Place the toe higher and outside the hip before rolling onto the shoe edge.
		# The knee can then lower inward while the two bone lengths stay unchanged.
		var raised_step: float = _motion_drop_foot if moving and i == loaded_foot else 0.0
		var toe_weight: float = 0.0
		if moving and _motion == "drop_knee" and i == loaded_foot:
			var p: float = clampf(_move_time / _move_duration, 0.0, 1.0)
			var plant: float = 0.30 / float(_step_count)
			toe_weight = smoothstep(plant + 0.02, maxf(0.32, plant + 0.20), p) * (1.0 - smoothstep(0.62, 0.88, p))
		# Move the toe outward before lifting it, avoiding a tight pivot through
		# the hip that would spin the knee plane abruptly during placement.
		foot += Vector3(side * 0.44 * toe_weight, 0.36 * raised_step, -0.025 * raised_step)
		if not moving and not summit_mode and climbing and support_foot >= 0 and i != support_foot:
			# A bent free leg makes the selected, loaded leg visible before any move.
			foot += _free_foot_offset(i, support_foot) * _stance_weight
		var foot_delta: Vector3 = foot - hip
		var ankle: Vector3 = hip + foot_delta.normalized() * clampf(foot_delta.length(), 0.04, 0.865)
		var regular_bend: Vector3 = Vector3(side * 0.035, 0.0, -1.0).normalized()
		# Rotate the knee plane around the leg axis rather than interpolating poles
		# through an axis-aligned direction, which can flip IK at the exit of a fold.
		var leg_axis: Vector3 = (ankle - hip).normalized()
		var bend_plane: Vector3 = (regular_bend - leg_axis * regular_bend.dot(leg_axis)).normalized()
		var knee_weight: float = drop * lerpf(0.20, 1.0, raised_step)
		var knee_bend: Vector3 = bend_plane.rotated(leg_axis, -side * 1.45 * knee_weight)
		var knee: Vector3 = _joint(hip, ankle, 0.43, 0.44, knee_bend)
		_segment(_thighs[i], hip, knee)
		_segment(_shins[i], knee, ankle)
		_knees[i].position = knee
		_boots[i].position = ankle + Vector3(0, -0.015, -0.045)
		_boots[i].rotation.y = -side * 0.04 + side * 0.75 * drop
		_boots[i].rotation.z = -side * 0.20 * drop
	_update_support_marker()
	_update_rope(visual_body + Vector3(0.04, -0.27, 0.14))
	for i in range(_dust.size()):
		_dust[i].visible = _chalk_time > 0.0
		var phase: float = 1.0 - _chalk_time / 0.95
		_dust[i].position = visual_body + Vector3(0.22 + sin(float(i) * 5.7) * phase * 0.32, -0.14 + cos(float(i) * 3.2) * phase * 0.24, 0.3 + phase * float(i) * 0.025)
		_dust[i].scale = Vector3.ONE * maxf(0.01, sin(phase * PI))

func _update_support_marker() -> void:
	if _support_marker == null:
		return
	var foot: int = _move_support_foot if moving else support_foot
	_support_marker.visible = _support_feedback_visible and climbing and not summit_mode and foot >= 0 and process_mode != Node.PROCESS_MODE_DISABLED
	if not _support_marker.visible:
		return
	_support_marker.position = _boots[foot].position + Vector3(0, -0.015, 0.085)
	_support_marker.scale = Vector3.ONE * (1.0 + sin(_time * 3.0) * 0.045)
	var color: Color = Color("f1c675") if foot == 0 else Color("78ded5")
	_support_material.albedo_color = color
	_support_material.emission = color

func _joint(start: Vector3, target: Vector3, upper: float, lower: float, bend: Vector3) -> Vector3:
	var difference: Vector3 = target - start
	var distance: float = maxf(difference.length(), 0.001)
	var direction: Vector3 = difference / distance
	var d: float = clampf(distance, 0.04, upper + lower - 0.005)
	var along: float = (upper * upper - lower * lower + d * d) / (2.0 * d)
	var h: float = sqrt(maxf(0.0, upper * upper - along * along))
	var perpendicular: Vector3 = bend - direction * bend.dot(direction)
	if perpendicular.length_squared() < 0.001:
		perpendicular = direction.cross(Vector3.RIGHT)
	return start + direction * along + perpendicular.normalized() * h

func _update_rope(waist: Vector3) -> void:
	var anchor: Vector3 = checkpoint_position + Vector3(0.18, -0.12, 0.03)
	var length: float = anchor.distance_to(waist)
	var previous: Vector3 = anchor
	for i in range(_rope.size()):
		var t: float = float(i + 1) / float(_rope.size())
		var point: Vector3 = anchor.lerp(waist, t)
		point.y -= sin(t * PI) * minf(1.0, length * 0.10 + 0.12)
		point.z += sin(t * PI) * 0.12
		point.x += sin(t * PI) * sin(_time * 1.5) * minf(length * 0.01, 0.08)
		_segment(_rope[i], previous, point)
		previous = point

func _mat(color: String, roughness: float = 0.8, metallic: float = 0.0) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(color)
	material.roughness = roughness
	material.metallic = metallic
	return material

func _fabric(color: String, roughness: float = 0.92) -> StandardMaterial3D:
	# One small mipmapped weave is shared by all clothing; colors remain tintable.
	if _fabric_color == null:
		var noise := FastNoiseLite.new()
		noise.seed = 47
		noise.frequency = 0.24
		var weave := Image.create(128, 128, false, Image.FORMAT_RGB8)
		var relief := Image.create(128, 128, false, Image.FORMAT_RGB8)
		for y in range(128):
			for x in range(128):
				var thread: float = sin(float(x) * PI * 0.5) * sin(float(y) * PI * 0.5)
				var grain: float = noise.get_noise_2d(float(x), float(y))
				var shade: float = 0.945 + thread * 0.018 + grain * 0.025
				weave.set_pixel(x, y, Color(shade, shade, shade))
				var height: float = 0.5 + thread * 0.045 + grain * 0.015
				relief.set_pixel(x, y, Color(height, height, height))
		weave.generate_mipmaps()
		relief.bump_map_to_normal_map(1.0)
		relief.generate_mipmaps()
		_fabric_color = ImageTexture.create_from_image(weave)
		_fabric_normal = ImageTexture.create_from_image(relief)
	var material := _mat(color, roughness)
	material.albedo_texture = _fabric_color
	material.normal_enabled = true
	material.normal_texture = _fabric_normal
	material.normal_scale = 0.22
	material.uv1_scale = Vector3(3.0, 3.0, 1.0)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return material

func _seams(parent: Node3D, paths: Array[PackedVector3Array], material: Material, radius: float = 0.003) -> void:
	# Many short stitches/cords share one mesh and one draw call.
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = 1.0
	cylinder.radial_segments = 6
	for path in paths:
		for index in range(path.size() - 1):
			var direction: Vector3 = path[index + 1] - path[index]
			var axis_y: Vector3 = direction.normalized()
			var reference: Vector3 = Vector3.FORWARD if absf(axis_y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT
			var axis_x: Vector3 = axis_y.cross(reference).normalized()
			var axis_z: Vector3 = axis_x.cross(axis_y).normalized()
			var pose := Transform3D(Basis(axis_x, axis_y * direction.length(), axis_z), (path[index] + path[index + 1]) * 0.5)
			surface.append_from(cylinder, 0, pose)
	_mesh(parent, surface.commit(), material)

func _mesh(parent: Node3D, shape: Mesh, material: Material, offset: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = shape
	instance.material_override = material
	instance.position = offset
	parent.add_child(instance)
	return instance

func _sphere(parent: Node3D, radius: float, size: Vector3, material: Material, offset: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var shape: SphereMesh = SphereMesh.new()
	shape.radius = radius
	shape.height = radius * 2.0
	shape.radial_segments = 24
	shape.rings = 12
	var instance: MeshInstance3D = _mesh(parent, shape, material, offset)
	instance.scale = size
	return instance

func _box(parent: Node3D, size: Vector3, material: Material, offset: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var shape: BoxMesh = BoxMesh.new()
	shape.size = size
	return _mesh(parent, shape, material, offset)

func _bone(parent: Node3D, radius: float, material: Material) -> MeshInstance3D:
	var shape: CylinderMesh = CylinderMesh.new()
	shape.top_radius = radius * 0.88
	shape.bottom_radius = radius
	shape.height = 1.0
	shape.radial_segments = 20
	return _mesh(parent, shape, material)

func _segment(instance: MeshInstance3D, start: Vector3, finish: Vector3) -> void:
	var direction: Vector3 = finish - start
	var length: float = maxf(direction.length(), 0.001)
	var axis_y: Vector3 = direction / length
	var reference: Vector3 = Vector3.FORWARD if absf(axis_y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT
	var axis_x: Vector3 = axis_y.cross(reference).normalized()
	var axis_z: Vector3 = axis_x.cross(axis_y).normalized()
	instance.transform = Transform3D(Basis(axis_x, axis_y * length, axis_z), (start + finish) * 0.5)

func _build_avatar() -> void:
	_built = true
	var orange: StandardMaterial3D = _fabric("e85c34", 0.86)
	var pants: StandardMaterial3D = _fabric("253746", 0.96)
	var dark: StandardMaterial3D = _mat("172330")
	var rubber := _mat("101b22", 0.98)
	var skin: StandardMaterial3D = _mat("dcc5a2")
	var rope_material: StandardMaterial3D = _mat("eac77b")
	var pack_material: StandardMaterial3D = _fabric("346a69", 0.91)
	_jacket_material = orange
	_pack_material = pack_material
	_pants_material = pants
	set_outfit(_outfit_index)
	var helmet: StandardMaterial3D = _mat("edc47c", 0.34, 0.08)
	var metal: StandardMaterial3D = _mat("bac7cb", 0.26, 0.82)
	var strap_material: StandardMaterial3D = _fabric("b9a681", 0.95)
	_torso = Node3D.new()
	_torso.name = "JacketBackpackAndHarness"
	add_child(_torso)
	_sphere(_torso, 0.27, Vector3(0.93, 1.2, 0.62), orange, Vector3(0, 0.01, 0))
	_sphere(_torso, 0.22, Vector3(0.91, 0.63, 0.68), pants, Vector3(0, -0.27, 0))
	_sphere(_torso, 0.17, Vector3(0.9, 0.55, 0.9), orange, Vector3(0, 0.30, 0.035))
	_box(_torso, Vector3(0.37, 0.05, 0.32), dark, Vector3(0, -0.24, 0))
	for side in [-1.0, 1.0]:
		_sphere(_torso, 0.082, Vector3.ONE, orange, Vector3(side * 0.225, 0.22, -0.02))
		var strap: MeshInstance3D = _box(_torso, Vector3(0.04, 0.45, 0.027), strap_material, Vector3(side * 0.14, 0.015, 0.17))
		strap.rotation.z = side * -0.12
		var leg_loop: MeshInstance3D = _box(_torso, Vector3(0.12, 0.055, 0.30), dark, Vector3(side * 0.13, -0.38, 0))
		leg_loop.rotation.z = side * 0.15
	_sphere(_torso, 0.24, Vector3(0.72, 0.98, 0.47), pack_material, Vector3(0, 0.03, 0.21))
	_box(_torso, Vector3(0.25, 0.035, 0.03), strap_material, Vector3(0, 0.02, 0.32))
	_box(_torso, Vector3(0.055, 0.10, 0.018), helmet, Vector3(0.055, 0.14, 0.33))
	_sphere(_torso, 0.075, Vector3(0.9, 0.72, 0.40), orange, Vector3(-0.04, -0.12, 0.31))
	_sphere(_torso, 0.075, Vector3(0.8, 1.0, 0.7), strap_material, Vector3(0.24, -0.27, 0.20))
	var seam_material := _mat("5b7774", 0.94)
	var pack_seams: Array[PackedVector3Array] = []
	for side in [-1.0, 1.0]:
		pack_seams.append(PackedVector3Array([Vector3(side * 0.085, -0.155, 0.258), Vector3(side * 0.121, -0.08, 0.274), Vector3(side * 0.135, 0.04, 0.281), Vector3(side * 0.115, 0.16, 0.269), Vector3(side * 0.06, 0.225, 0.25)]))
	_seams(_torso, pack_seams, seam_material, 0.003)
	var zipper: Array[PackedVector3Array] = [PackedVector3Array([Vector3(0.015, -0.03, 0.322), Vector3(0.015, 0.05, 0.324), Vector3(0.015, 0.14, 0.31), Vector3(0.015, 0.20, 0.287)])]
	_seams(_torso, zipper, dark, 0.004)
	_box(_torso, Vector3(0.012, 0.029, 0.009), metal, Vector3(0.015, 0.17, 0.303))
	var carabiner: MeshInstance3D = _bone(_torso, 0.012, metal)
	_segment(carabiner, Vector3(0.20, -0.25, 0.13), Vector3(0.23, -0.36, 0.15))
	_head = Node3D.new()
	_head.position = Vector3(0, 0.45, -0.005)
	_torso.add_child(_head)
	_sphere(_head, 0.13, Vector3(0.83, 1.07, 0.88), skin)
	_sphere(_head, 0.142, Vector3(1.0, 0.72, 1.0), dark, Vector3(0, 0.065, 0))
	_sphere(_head, 0.147, Vector3(1.0, 0.75, 1.0), helmet, Vector3(0, 0.087, 0))
	_box(_head, Vector3(0.07, 0.027, 0.018), dark, Vector3(0, 0.11, 0.14))
	var helmet_trim: Array[PackedVector3Array] = []
	for side in [-1.0, 1.0]:
		helmet_trim.append(PackedVector3Array([Vector3(side * 0.102, 0.126, 0.098), Vector3(side * 0.115, 0.147, 0.062), Vector3(side * 0.118, 0.15, 0.025)]))
		helmet_trim.append(PackedVector3Array([Vector3(side * 0.104, 0.04, -0.065), Vector3(side * 0.08, -0.075, -0.054), Vector3(side * 0.032, -0.11, -0.065)]))
	_seams(_head, helmet_trim, dark, 0.005)
	for i in range(2):
		_upper_arms.append(_bone(self, 0.080, orange))
		_forearms.append(_bone(self, 0.063, orange))
		_thighs.append(_bone(self, 0.092, pants))
		_shins.append(_bone(self, 0.067, pants))
		_gloves.append(_sphere(self, 0.062, Vector3(0.90, 1.3, 0.65), skin))
		_elbows.append(_sphere(self, 0.071, Vector3.ONE, orange))
		_knees.append(_sphere(self, 0.077, Vector3.ONE, pants))
		var boot: MeshInstance3D = _sphere(self, 0.083, Vector3(0.72, 0.63, 1.6), dark)
		_boots.append(boot)
		_box(boot, Vector3(0.08, 0.026, 0.11), helmet, Vector3(0, 0.02, -0.045))
		_sphere(boot, 0.081, Vector3(1.0, 0.24, 0.96), rubber, Vector3(0, -0.039, -0.004))
		var laces: Array[PackedVector3Array] = [PackedVector3Array([Vector3(-0.032, 0.045, -0.048), Vector3(0.032, 0.045, -0.025), Vector3(-0.032, 0.045, -0.005), Vector3(0.032, 0.043, 0.018)])]
		_seams(boot, laces, strap_material, 0.003)
	_support_material = _mat("78ded5")
	_support_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_support_material.emission_enabled = true
	_support_material.emission_energy_multiplier = 0.65
	var support_ring := TorusMesh.new()
	support_ring.inner_radius = 0.105
	support_ring.outer_radius = 0.125
	support_ring.rings = 24
	support_ring.ring_segments = 8
	_support_marker = _mesh(self, support_ring, _support_material)
	_support_marker.name = "LoadedFootRing"
	_support_marker.rotation.x = PI * 0.5
	_support_marker.visible = false
	for i in range(16):
		_rope.append(_bone(self, 0.011, rope_material))
	var chalk_material: StandardMaterial3D = _mat("e4dfcc")
	for i in range(12):
		var mote: MeshInstance3D = _sphere(self, 0.018, Vector3.ONE, chalk_material)
		mote.visible = false
		_dust.append(mote)




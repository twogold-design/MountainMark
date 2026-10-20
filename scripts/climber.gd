extends Node3D

signal reached_hold(hold_id: int)
signal fell
var stamina: float = 100.0
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
var _move_duration: float = 0.90
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
	_old_hands = _hands.duplicate()
	_old_feet = _feet.duplicate()
	var side: float = -1.0 if _hand == 0 else 1.0
	_new_body = target + Vector3(-side * 0.14, -0.78, 0.49)
	_new_hands[_hand] = target + Vector3(0, 0, 0.025)
	_new_hands[1 - _hand] = target + Vector3(-side * 0.48, -0.32, 0.01)
	_new_feet[0] = _new_body + Vector3(-0.19, -0.92, -0.28)
	_new_feet[1] = _new_body + Vector3(0.19, -0.88, -0.28)
	_step_count = maxi(1, ceili(_old_body.distance_to(_new_body) / 0.40))
	_move_duration = maxf(0.90, float(_step_count) * 0.42)
	_move_time = 0.0
	moving = true
	stamina = maxf(0.0, stamina - move_cost)
	return true

func get_reach_origin() -> Vector3:
	return _reach

func get_body_position() -> Vector3:
	return _body

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
	_reach = checkpoint_position
	current_hold_id = checkpoint_hold_id
	_body = _reach + Vector3(0.10, -0.78, 0.49)
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
	_lean = 0.0
	_lean_target = 0.0
	_target.clear()
	for rope_part in _rope:
		rope_part.visible = true
	if _built:
		_update_pose()

func celebrate(summit_position: Vector3 = Vector3.ZERO) -> void:
	moving = false
	summit_mode = true
	_summit_floor = summit_position if summit_position != Vector3.ZERO else _reach + Vector3(0, 1.95, -1.25)
	_summit_time = 0.0
	_chalk_time = 0.0
	for rope_part in _rope:
		rope_part.visible = false
	_old_body = _body
	_old_hands = _hands.duplicate()
	_old_feet = _feet.duplicate()
	stamina = 100.0

func set_lean(value: float) -> void:
	_lean_target = clampf(value, -1.0, 1.0)

func _process(delta: float) -> void:
	if not _built:
		return
	_time += delta
	_lean = lerpf(_lean, _lean_target, minf(1.0, delta * 6.0))
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
		stamina = maxf(0.0, stamina - delta * 0.38)
		if stamina <= 0.0 and not _fall_sent:
			_fall_sent = true
			fell.emit()
	_update_pose()

func _advance_move(delta: float) -> void:
	_move_time += delta
	var p: float = clampf(_move_time / _move_duration, 0.0, 1.0)
	# A long reach is a sequence of short foot placements, not a simultaneous swim.
	var step_index: int = mini(int(p * float(_step_count)), _step_count - 1)
	var phase: float = clampf(p * float(_step_count) - float(step_index), 0.0, 1.0)
	var start_fraction: float = float(step_index) / float(_step_count)
	var end_fraction: float = float(step_index + 1) / float(_step_count)
	var body_push: float = smoothstep(0.22, 0.80, phase)
	var body_fraction: float = lerpf(start_fraction, end_fraction, body_push)
	_body = _old_body.lerp(_new_body, body_fraction)
	_body.z += sin(phase * PI) * 0.025
	var lead_foot: int = (_hand + step_index) % 2
	for i in range(2):
		var start_foot: Vector3 = _old_feet[i].lerp(_new_feet[i], start_fraction)
		var end_foot: Vector3 = _old_feet[i].lerp(_new_feet[i], end_fraction)
		# Lead foot lands before the push; support foot stays fixed through its first half.
		var fp: float = smoothstep(0.0, 0.26, phase) if i == lead_foot else smoothstep(0.44, 0.96, phase)
		_feet[i] = start_foot.lerp(end_foot, fp)
		_feet[i].y += sin(fp * PI) * 0.075
		_feet[i].z += sin(fp * PI) * 0.035
		var hp: float = smoothstep(0.0, 0.76, p) if i == _hand else smoothstep(0.24, 0.98, p)
		_hands[i] = _old_hands[i].lerp(_new_hands[i], hp)
		_hands[i].z += sin(hp * PI) * 0.12
	if p >= 1.0:
		moving = false
		_body = _new_body
		_reach = _target.get("position", _reach)
		current_hold_id = int(_target.get("id", current_hold_id))
		total_moves += 1
		if bool(_target.get("checkpoint", false)):
			checkpoint_position = _reach
			checkpoint_hold_id = current_hold_id
		reached_hold.emit(current_hold_id)

func _update_pose() -> void:
	var visual_body: Vector3 = _body + Vector3(_lean * 0.17, sin(_time * 2.3) * 0.009, -absf(_lean) * 0.018)
	_torso.position = visual_body
	_torso.rotation.z = _lean * -0.14 + (sin(_move_time * 7.0) * 0.035 if moving else 0.0)
	_head.rotation.y = sin(_time * 0.5) * 0.07
	for i in range(2):
		var side: float = -1.0 if i == 0 else 1.0
		var shoulder: Vector3 = _torso.transform * Vector3(side * 0.225, 0.22, -0.02)
		var palm: Vector3 = _hands[i]
		if _chalk_time > 0.0 and i == 1:
			palm = palm.lerp(visual_body + Vector3(0.30, -0.24, 0.30), sin((1.0 - _chalk_time / 0.95) * PI))
		var elbow: Vector3 = _joint(shoulder, palm, 0.34, 0.38, Vector3(side * 0.75, -0.45, 0.5))
		_segment(_upper_arms[i], shoulder, elbow)
		_segment(_forearms[i], elbow, palm)
		_elbows[i].position = elbow
		_gloves[i].position = palm
		_gloves[i].rotation.z = side * -0.25
		var hip: Vector3 = _torso.transform * Vector3(side * 0.13, -0.29, 0)
		var foot_delta: Vector3 = _feet[i] - hip
		var ankle: Vector3 = hip + foot_delta.normalized() * clampf(foot_delta.length(), 0.04, 0.865)
		var knee: Vector3 = _joint(hip, ankle, 0.43, 0.44, Vector3(side * 0.035, 0.0, -1.0))
		_segment(_thighs[i], hip, knee)
		_segment(_shins[i], knee, ankle)
		_knees[i].position = knee
		_boots[i].position = ankle + Vector3(0, -0.015, -0.045)
		_boots[i].rotation.y = -side * 0.04
	_update_rope(visual_body + Vector3(0.04, -0.27, 0.14))
	for i in range(_dust.size()):
		_dust[i].visible = _chalk_time > 0.0
		var phase: float = 1.0 - _chalk_time / 0.95
		_dust[i].position = visual_body + Vector3(0.22 + sin(float(i) * 5.7) * phase * 0.32, -0.14 + cos(float(i) * 3.2) * phase * 0.24, 0.3 + phase * float(i) * 0.025)
		_dust[i].scale = Vector3.ONE * maxf(0.01, sin(phase * PI))

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
	shape.radial_segments = 12
	shape.rings = 6
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
	shape.radial_segments = 10
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
	var orange: StandardMaterial3D = _mat("e85c34")
	var pants: StandardMaterial3D = _mat("253746")
	var dark: StandardMaterial3D = _mat("172330")
	var skin: StandardMaterial3D = _mat("dcc5a2")
	var rope_material: StandardMaterial3D = _mat("eac77b")
	var pack_material: StandardMaterial3D = _mat("346a69")
	var helmet: StandardMaterial3D = _mat("edc47c", 0.48)
	var metal: StandardMaterial3D = _mat("bac7cb", 0.23, 0.7)
	var strap_material: StandardMaterial3D = _mat("b9a681")
	_torso = Node3D.new()
	_torso.name = "JacketBackpackAndHarness"
	add_child(_torso)
	_sphere(_torso, 0.27, Vector3(0.93, 1.2, 0.62), orange, Vector3(0, 0.01, 0))
	_sphere(_torso, 0.22, Vector3(0.91, 0.63, 0.68), pants, Vector3(0, -0.27, 0))
	_sphere(_torso, 0.17, Vector3(0.9, 0.55, 0.9), orange, Vector3(0, 0.30, 0.035))
	_box(_torso, Vector3(0.37, 0.05, 0.32), dark, Vector3(0, -0.24, 0))
	for side in [-1.0, 1.0]:
		var strap: MeshInstance3D = _box(_torso, Vector3(0.04, 0.45, 0.027), strap_material, Vector3(side * 0.14, 0.015, 0.17))
		strap.rotation.z = side * -0.12
		var leg_loop: MeshInstance3D = _box(_torso, Vector3(0.12, 0.055, 0.30), dark, Vector3(side * 0.13, -0.38, 0))
		leg_loop.rotation.z = side * 0.15
	_sphere(_torso, 0.24, Vector3(0.72, 0.98, 0.47), pack_material, Vector3(0, 0.03, 0.21))
	_box(_torso, Vector3(0.25, 0.035, 0.03), strap_material, Vector3(0, 0.02, 0.32))
	_box(_torso, Vector3(0.055, 0.10, 0.018), helmet, Vector3(0.055, 0.14, 0.33))
	_box(_torso, Vector3(0.12, 0.10, 0.07), orange, Vector3(-0.04, -0.13, 0.32))
	_sphere(_torso, 0.075, Vector3(0.8, 1.0, 0.7), strap_material, Vector3(0.24, -0.27, 0.20))
	var carabiner: MeshInstance3D = _bone(_torso, 0.012, metal)
	_segment(carabiner, Vector3(0.20, -0.25, 0.13), Vector3(0.23, -0.36, 0.15))
	_head = Node3D.new()
	_head.position = Vector3(0, 0.45, -0.005)
	_torso.add_child(_head)
	_sphere(_head, 0.13, Vector3(0.83, 1.07, 0.88), skin)
	_sphere(_head, 0.142, Vector3(1.0, 0.72, 1.0), dark, Vector3(0, 0.065, 0))
	_sphere(_head, 0.147, Vector3(1.0, 0.75, 1.0), helmet, Vector3(0, 0.087, 0))
	_box(_head, Vector3(0.07, 0.027, 0.018), dark, Vector3(0, 0.11, 0.14))
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
	for i in range(16):
		_rope.append(_bone(self, 0.011, rope_material))
	var chalk_material: StandardMaterial3D = _mat("e4dfcc")
	for i in range(12):
		var mote: MeshInstance3D = _sphere(self, 0.018, Vector3.ONE, chalk_material)
		mote.visible = false
		_dust.append(mote)




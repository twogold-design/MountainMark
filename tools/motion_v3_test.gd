extends SceneTree
const ACTOR = preload("res://scripts/climber.gd")
const SOUND = preload("res://scripts/audio.gd")
var checks: int = 0
func _initialize() -> void:
	call_deferred("_run")

func verify(ok: bool, detail: String) -> void:
	checks += 1
	if not ok:
		push_error(detail)
		quit(1)

func _run() -> void:
	var actor: Node3D = ACTOR.new()
	root.add_child(actor)
	actor.set_process(false)
	actor.set_outfit(2)
	actor.setup({"id": 0, "position": Vector3(0, 2.5, 0.45)})
	verify(actor._jacket_material.albedo_color.is_equal_approx(Color("80b8d5")), "Outfit before setup")
	for outfit in range(3):
		actor.set_outfit(outfit)
		verify(actor._pack_material.albedo_color.is_equal_approx(Color(["346a69", "b38c59", "405e83"][outfit])), "Backpack color")
	for chosen in [-1, 0, 1]:
		for direction in [-1.0, 1.0]:
			actor.setup({"id": 0, "position": Vector3(0, 2.5, 0.45)})
			actor.climbing = true
			actor.set_support_foot(chosen)
			var hand: int = 0 if direction < 0 else 1
			verify(actor.climb_to({"id": 1, "position": Vector3(direction * 1.1, 2.8, 0.45)}, hand, 6.0), "Traverse starts")
			var first_foot: int = hand if chosen < 0 else 1 - chosen
			var fixed_hand: Vector3 = actor._hands[hand]
			var fixed_foot: Vector3 = actor._feet[1 - first_foot]
			actor._process(0.20 * actor._move_duration / float(actor._step_count))
			verify(actor._hands[hand].is_equal_approx(fixed_hand), "Hand waits for foot plant")
			verify(actor._feet[1 - first_foot].is_equal_approx(fixed_foot), "Other foot stays planted")
			verify(not actor._feet[first_foot].is_equal_approx(actor._old_feet[first_foot]), "Free foot steps first while selected foot supports")
			actor.set_support_foot(1 - first_foot)
			verify(actor._move_support_foot == chosen, "Midmove selection cannot change pose")
			while actor.moving:
				actor._process(0.008)
				for i in range(2):
					var side: float = -1.0 if i == 0 else 1.0
					var hip: Vector3 = actor._torso.transform * Vector3(side * 0.13, -0.29, 0)
					var knee: Vector3 = actor._knees[i].position
					var ankle: Vector3 = actor._boots[i].position - Vector3(0, -0.015, -0.045)
					verify(absf(hip.distance_to(knee) - 0.43) < 0.0002, "Fixed thigh length")
					verify(absf(knee.distance_to(ankle) - 0.44) < 0.0002, "Fixed shin length")
					var axis: Vector3 = (ankle - hip).normalized()
					verify((knee - hip - axis * (knee - hip).dot(axis)).z <= 0.0001, "Knee bends toward wall")
			verify(actor.current_hold_id == 1, "Traverse completes")
	actor.stamina = 100.0
	actor.terrain_drain = 1.2
	actor._process(1.0)
	verify(is_equal_approx(actor.stamina, 98.42), "Terrain grip drain")
	var sound: Node = SOUND.new()
	root.add_child(sound)
	sound.set_process(false)
	sound.start_ambience()
	var hashes: Array[int] = []
	for theme in range(3):
		sound.set_route_theme(theme)
		verify(sound._route_bed.playing, "Nature loop playing")
		hashes.append(hash(sound._route_bed.stream.data))
	verify(hashes[0] != hashes[1] and hashes[1] != hashes[2], "Three distinct sound beds")
	sound.set_wind_strength(1.0)
	sound._process(1.0)
	var loud: float = sound._wind.volume_db
	sound.play_grip()
	sound._process(0.1)
	verify(sound._wind.volume_db < loud, "Grip ducks wind")
	sound.set_muted(true)
	verify(sound._route_bed.volume_db == -80.0, "Mute nature bed")
	sound.reset_ascent()
	verify(sound._wind_strength == 0.0, "Reset gust")
	sound.shutdown()
	verify(not sound._started, "Clean audio shutdown")
	print("MOTION / SOUND V3 PASS checks=", checks)
	actor.queue_free()
	sound.queue_free()
	await create_timer(0.3).timeout
	quit()

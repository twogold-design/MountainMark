extends SceneTree
## Run this external QA script against the exported PCK, not the source scene.
var failures: int = 0
var checks: int = 0

func _initialize() -> void:
	call_deferred("run")

func verify(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", label)

func run() -> void:
	if "--qa-capture" not in OS.get_cmdline_user_args():
		quit(2)
		return
	verify(ProjectSettings.get_setting("application/config/version") == "0.3.2", "packaged version")
	var game: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.climber.set_process(false)
	verify(game.has_method("hold_reach_info") and game.climber.has_method("get_motion_name") and game.hud.has_method("_draw_support_card"), "packaged geometry, motions and HUD exist together")
	verify(game.climber.has_method("_reach_progress"), "packaged actor includes the continuous reach update")
	verify(game.climber.has_signal("effort_started") and game.sound.has_method("play_exertion") and game.sound._clips.has_all(["effort_1", "effort_2", "pant", "recovery"]), "packaged exertion, breathing and rest audio assets exist")
	verify(game.climber.has_signal("hand_contact") and game.sound._clips.has_all(["grip_1", "grip_2", "grip_3", "grip_4", "grip_5", "grip_6"]), "packaged hand contacts and six grip samples exist")
	if failures > 0:
		game.sound.shutdown()
		quit(1)
		return
	game.save_data = {"completed_routes":{"0":true}}
	game.route_index = 1
	game.play_style = "journey"
	game.start_climb(false)
	game.select_support(0)
	var left_pose: Vector3 = game.climber.get_body_position()
	var right_free: float = game.climber.get_foot_position(1).y
	game.select_support(1)
	verify(game.climber.get_body_position().x > left_pose.x and game.climber.get_foot_position(1).y < right_free - 0.1, "packaged foot selection changes visible hips and free leg")
	game.choose_next()
	verify(game.preview_id in game.readable and not game.climber.moving, "packaged route reading leaves the actor still")
	var id: int = game.preview_id
	game.select_support(int(game._hold(id).get("support", -1)))
	var hand: int = game.recommended_hand(id)
	game._update_camera(1.0)
	game.attempt_hold(id, hand)
	game.balance = game.balance_target
	game.climber.set_lean(game.balance)
	game._refresh_grip_geometry()
	var aim: Dictionary = game.get_drag_aim_info()
	game.set_grip_drag(Vector2(aim.drag_anchor) - (Vector2(aim.target_screen) - Vector2(aim.origin_screen)) / game.DRAG_AMPLIFICATION)
	verify(game.grip_ready(), "packaged geometry accepts a properly supported grip")
	game._release_grip(hand)
	verify(game.climber.moving, "packaged grip starts a real climb")
	for frame: int in range(600):
		if not game.climber.moving:
			break
		game.climber._process(0.01)
	verify(game.climber.current_hold_id == id, "packaged movement arrives at the selected hold")
	var targets: Array[Vector3] = [Vector3(0.15, 3.5, 0.45), Vector3(-1.1, 2.85, 0.45), Vector3(0.2, 4.6, 0.45)]
	var names: Array[String] = ["正身蹬起", "侧身横渡", "屈膝高踩"]
	for style: int in range(3):
		game.climber.setup({"id": 0, "position": Vector3(0.0, 2.5, 0.45)})
		game.climber.climbing = true
		game.climber.set_support_foot(0)
		game.climber.climb_to({"id": id, "position": targets[style]}, 1, 0.0)
		verify(game.climber.get_motion_name() == names[style], "packaged motion " + names[style])
	game.climber.setup({"id": 0, "position": Vector3(0.0, 2.5, 0.45)})
	game.climber.climbing = true
	game.climber.set_support_foot(1)
	game.climber.set_lean(0.90)
	game.climber.climb_to({"id": 1, "position": Vector3(0.90, 3.45, 0.45)}, 1, 0.0)
	verify(game.climber.get_motion_name() == "折膝侧伸", "packaged drop knee is separate from high stepping")
	game.sound.shutdown()
	game.queue_free()
	await create_timer(0.3).timeout
	print("PACKAGE_REACH_RESULT checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)

extends SceneTree
var game: Node3D
var checks: int = 0
var failures: int = 0
func _initialize() -> void:
	call_deferred("run")
func verify(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
func screenshot(path: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(path)
func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	var original_path: String = game._save_path
	var existed: bool = FileAccess.file_exists(original_path)
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(original_path) if existed else PackedByteArray()
	game._save_path = ProjectSettings.globalize_path("res://qa/fall-feedback-save.json")
	game.start_climb(false)
	game.climber.setup(game.world.holds[4])
	game.climber.checkpoint_position = game.world.holds[0].position
	game.climber.checkpoint_hold_id = 0
	game.climber.climbing = true
	game.current_rest = false
	game._update_camera(1.0)
	var position_before: Vector3 = game.climber.get_body_position()
	game.climber.stamina = 0.0
	game.climber._process(0.01)
	verify(game.mode == "fallen" and game.falls == 1, "exhaustion opens failure state")
	verify(game.climber.get_body_position().is_equal_approx(position_before), "fall does not instantly reset position")
	verify(game.fall_reason.contains("握力耗尽") and game.fall_title.contains("没能抓稳"), "cause and failure message are explicit")
	verify(game.hud.buttons.size() == 1 and game.hud.buttons[0].text.contains("山脚"), "base camp retry button is visible")
	game.retry_after_fall()
	verify(game.mode == "fallen", "accidental immediate retry is blocked")
	game._on_fell()
	verify(game.falls == 1, "duplicate fall is ignored")
	var timer_before: float = game.elapsed
	game.attempt_hold(5, 0)
	game.choose_next()
	await create_timer(0.75).timeout
	verify(game.climber.get_body_position().is_equal_approx(position_before) and game.elapsed == timer_before and not game.grip_active, "failure screen freezes movement timer and input")
	await screenshot("res://qa/fall-feedback-base.png")
	var enter: InputEventKey = InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	game._unhandled_input(enter)
	verify(game.mode == "playing" and game.climber.current_hold_id == 0 and game.climber.stamina == 100.0, "Enter deliberately restores base camp")
	verify(game.climber.climbing and game.climber.process_mode == Node.PROCESS_MODE_INHERIT and game.hud.buttons.is_empty(), "retry restores playable controls and clears modal")
	var anchor: Dictionary = {}
	for hold: Dictionary in game.world.holds:
		if bool(hold.checkpoint) and int(hold.id) > 0:
			anchor = hold
			break
	game.climber.setup(anchor)
	game.climber.climbing = true
	game.checkpoint = int(anchor.id)
	game._on_reached(int(anchor.id))
	game.slip_streak = 2
	game._fail_grip("松手时机不对")
	verify(game.mode == "fallen" and game.fall_reason.contains("连续三次"), "third slip displays its distinct cause")
	verify(game.hud.buttons[0].text.contains("锚点") and game.checkpoint == int(anchor.id), "checkpoint return is retained instead of restarting route")
	await create_timer(0.75).timeout
	await screenshot("res://qa/fall-feedback-anchor.png")
	game.hud.buttons[0].pressed.emit()
	verify(game.mode == "playing" and game.climber.current_hold_id == int(anchor.id) and game.slip_streak == 0, "button restores the saved anchor")
	game._on_fell("主动返回")
	verify(game.mode == "fallen" and game.fall_title.contains("先退一步"), "voluntary rope return has appropriate wording")
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(game._save_path))
	verify(saved is Dictionary and int(saved.checkpoint) == int(anchor.id) and int(saved.falls) == game.falls, "failure saves anchor and protection count")
	game.return_menu()
	game.start_climb(false)
	verify(game.mode == "playing" and game.climber.process_mode == Node.PROCESS_MODE_INHERIT, "new run cannot retain frozen climber")
	verify(FileAccess.file_exists(original_path) == existed and (not existed or FileAccess.get_file_as_bytes(original_path) == bytes), "player save untouched")
	game.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	print("FALL_FEEDBACK_RESULT checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)

extends SceneTree
## Integration tests use a dedicated save; the player's save is read-only.
const TEST_SAVE: String = "res://qa/integration-save.json"
var game: Node3D
var test_view: SubViewport
var checks: int = 0
var failures: Array[String] = []
var player_save_bytes: PackedByteArray = PackedByteArray()
var player_save_existed: bool = false
var player_save_path: String = ""

func _initialize() -> void:
	call_deferred("run")

func verify(ok: bool, label: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failures.append(label)

func mount_game() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn") as PackedScene
	game = packed.instantiate() as Node3D
	test_view.add_child(game)
	game._save_path = ProjectSettings.globalize_path(TEST_SAVE)
	game.save_data = {}
	game.sound.set_muted(true)

func release_when_ready(hand: int) -> bool:
	for tick in range(440):
		var difference: float = float(game.balance_target) - float(game.balance)
		var axis: float = signf(difference) if absf(difference) > 0.012 else 0.0
		game._tick_control(0.01, axis)
		if game.grip_ready():
			game._release_grip(hand)
			return game.climber.moving
	return false
func mouse_at(point: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	test_view.push_input(event, true)
	game._update_hover()

func run() -> void:
	root.size = Vector2i(1440, 900)
	test_view = SubViewport.new()
	test_view.size = Vector2i(1440, 900)
	test_view.handle_input_locally = true
	root.add_child(test_view)
	mount_game()
	# _ready only reads save.json. All write paths are redirected before actions.
	player_save_path = game._data_path("save.json")
	player_save_existed = FileAccess.file_exists(player_save_path)
	if player_save_existed:
		player_save_bytes = FileAccess.get_file_as_bytes(player_save_path)
	await process_frame
	verify(game.mode == "menu", "scene starts in menu")
	game.start_climb(false)
	game._camera_ready = false
	game._update_camera(1.0)
	game._update_reachable()
	var origin: Vector3 = game.climber.get_reach_origin()
	var selection_ok: bool = true
	for hold: Dictionary in game.world.holds:
		var expected: bool = int(hold.id) != game.climber.current_hold_id and origin.distance_to(hold.position) <= game.REACH and float(hold.position.y) > origin.y - 0.8
		if (int(hold.id) in game.reachable) != expected:
			selection_ok = false
	verify(selection_ok and not game.reachable.is_empty(), "reachable list uses range, current-point exclusion and vertical limit")
	var chosen: int = int(game.reachable[0])
	var screen: Vector2 = game.camera.unproject_position(game._hold(chosen).position)
	mouse_at(screen)
	verify(game.hovered_id == chosen, "mouse projection selects reachable point")
	mouse_at(Vector2(-1000, -1000))
	verify(game.hovered_id == -1, "mouse away from route clears selection")
	var last_id: int = int(game.world.holds[-1].id)
	var initial_stamina: float = game.climber.stamina
	game.attempt_hold(last_id)
	game.attempt_hold(-500)
	verify(not game.climber.moving and is_equal_approx(game.climber.stamina, initial_stamina), "invalid and unreachable holds do not move or spend stamina")
	mouse_at(screen)
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	game._unhandled_input(click)
	verify(game.grip_active and not game.climber.moving, "left mouse press prepares grip without moving")
	verify(release_when_ready(0), "balanced timed release starts left-hand animation")
	await create_timer(0.10).timeout
	game.toggle_pause()
	var paused_body: Vector3 = game.climber.get_body_position()
	var paused_stamina: float = game.climber.stamina
	var paused_time: float = game.elapsed
	await create_timer(0.12).timeout
	verify(game.mode == "paused" and game.climber.get_body_position().is_equal_approx(paused_body) and is_equal_approx(game.elapsed, paused_time) and is_equal_approx(game.climber.stamina, paused_stamina), "pause freezes animation, stamina and ascent timer")
	game.attempt_hold(chosen)
	verify(game.mode == "paused", "grip attempt cannot exit pause")
	game.toggle_pause()
	for wait_frame in range(80):
		if not game.climber.moving:
			break
		await create_timer(0.05).timeout
	verify(game.mode == "playing" and not game.climber.moving and game.climber.current_hold_id == chosen and game.climber.total_moves == 1, "resume completes interrupted climb exactly once")
	game.current_rest = false
	game.climber.stamina = 40.0
	game.climber._chalk_cooldown = 0.0
	var initial_charges: int = game.chalk_charges
	game.use_chalk()
	verify(is_equal_approx(game.climber.stamina, 50.0) and game.chalk_charges == initial_charges - 1, "chalk restores ten stamina and consumes one charge")
	game.use_chalk()
	verify(is_equal_approx(game.climber.stamina, 50.0) and game.chalk_charges == initial_charges - 1, "chalk cooldown rejects repeated use without consuming another charge")
	game.climber._process(7.1)
	game.use_chalk()
	verify(game.chalk_charges == initial_charges - 2, "another limited chalk charge becomes usable after seven seconds")
	var before_falls: int = game.falls
	game.current_rest = false
	game.climber.stamina = 0.0
	game.climber._process(0.01)
	verify(game.mode == "fallen", "exhaustion presents a failure screen before recovery")
	game.fall_time = 0.7
	game.retry_after_fall()
	verify(game.falls == before_falls + 1 and game.climber.current_hold_id == game.checkpoint and game.climber.stamina == 100.0 and game.climber.climbing and not game.climber.moving, "exhaustion emits fall, restores checkpoint and permits climbing")
	var anchor: Dictionary = {}
	for hold: Dictionary in game.world.holds:
		if bool(hold.checkpoint) and int(hold.id) > 0 and float(hold.position.y) < 60.0:
			anchor = hold
			break
	verify(not anchor.is_empty(), "route contains an intermediate safety anchor")
	game.climber.setup(anchor)
	game.climber.climbing = true
	game.elapsed = 123.4
	game.falls = 2
	game.climber.total_moves = 21
	game._on_reached(int(anchor.id))
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(TEST_SAVE))
	verify(saved is Dictionary and int(saved.get("checkpoint", -1)) == int(anchor.id) and int(saved.get("moves", -1)) == 21 and bool(saved.get("in_progress", false)), "checkpoint writes progress to isolated test save")
	game.return_menu()
	game.queue_free()
	await process_frame
	await process_frame
	mount_game()
	game._load_save()
	game.start_climb(true)
	verify(game.climber.current_hold_id == int(anchor.id) and game.checkpoint == int(anchor.id) and game.climber.total_moves == 21 and game.falls == 2 and is_equal_approx(game.elapsed, 123.4), "fresh scene resumes saved checkpoint and statistics")
	game._on_fell()
	game.fall_time = 0.7
	game.retry_after_fall()
	verify(game.climber.current_hold_id == int(anchor.id) and game.falls == 3 and game.current_rest, "fall after resume returns to saved anchor")
	game.start_climb(false)
	verify(game.climber.current_hold_id == 0 and game.falls == 0 and game.climber.total_moves == 0, "new ascent resets position and run counters")
	game.elapsed = 91.5
	game.climber.total_moves = 48
	game.climber.setup(game.world.holds[-1])
	game.climber.climbing = true
	game.sound.set_muted(false)
	game._on_reached(last_id)
	verify(game.sound._summit and game.sound._music.playing, "summit starts dedicated completion music" )
	verify(game.mode == "summit" and game.climber.summit_mode and int(game.save_data.get("summits", 0)) == 1 and bool(game.save_data.get("clean_ascent", false)) and not bool(game.save_data.get("in_progress", true)), "summit records first completion, clean achievement and finished run")
	game._finish()
	verify(int(game.save_data.get("summits", 0)) == 1, "duplicate finish does not increment achievement")
	game.start_climb(false)
	verify(game.mode == "playing" and not game.climber.summit_mode and game.climber.current_hold_id == 0 and game.climber.climbing and int(game.save_data.get("summits", 0)) == 1, "replay starts climb and retains lifetime achievement")
	verify(not game.sound._summit and not game.sound._music.playing and game.sound._wind.playing and game.sound._air.playing and game.sound._grip_count == 0, "replay stops completion music and restores climbing soundscape")
	# A second completion must preserve the faster personal record.
	game.elapsed = 150.0
	game.falls = 1
	game._finish()
	verify(int(game.save_data.get("summits", 0)) == 2 and is_equal_approx(float(game.save_data.get("best_time", 0)), 91.5) and bool(game.save_data.get("clean_ascent", false)), "later slower completion preserves best time and clean achievement")
	game.return_menu()
	verify(game.mode == "menu" and not game.climber.summit_mode and not game.climber.climbing, "summit return resets avatar to idle menu")
	verify(not game.sound._summit and not game.sound._music.playing and game.sound._wind.playing and game.sound._air.playing, "returning to menu restores ambient soundscape")
	var save_unchanged: bool = FileAccess.file_exists(player_save_path) == player_save_existed
	if player_save_existed:
		save_unchanged = save_unchanged and FileAccess.get_file_as_bytes(player_save_path) == player_save_bytes
	verify(save_unchanged, "player save.json remains byte-for-byte untouched")
	game.queue_free()
	await process_frame
	await process_frame
	test_view.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	print("INTEGRATION_RESULT checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)








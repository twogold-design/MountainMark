extends SceneTree
## Real filesystem persistence, deliberately without --qa-capture.
var checks: int = 0
var failures: Array[String] = []
var game: Node3D
var packed: PackedScene
var folder: String
var disk_path: String

func _initialize() -> void:
	call_deferred("_run")

func verify(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		print("FAIL ", message)

func read_disk() -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(disk_path))
	return value if value is Dictionary else {}

func progress(data: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in ["version", "route", "checkpoint", "elapsed", "falls", "moves", "chalk_used", "run_collections", "in_progress"]:
		result[key] = data.get(key)
	return result.duplicate(true)

func spawn_game() -> void:
	game = packed.instantiate()
	root.add_child(game)
	game.set_process(false)
	game.climber.set_process(false)
	game.sound.set_process(false)

func stop_game() -> void:
	game.sound.shutdown()
	game.queue_free()
	await create_timer(0.3).timeout

func _run() -> void:
	verify("--qa-capture" not in OS.get_cmdline_user_args(), "Persistence test must really write saves")
	if not failures.is_empty():
		quit(1)
		return
	var player_path: String = ProjectSettings.globalize_path("res://.runtime/save.json")
	var player_exists: bool = FileAccess.file_exists(player_path)
	var player_bytes: PackedByteArray = FileAccess.get_file_as_bytes(player_path) if player_exists else PackedByteArray()
	var previous_environment: String = OS.get_environment("MOUNTAINMARK_DATA_DIR")
	folder = ProjectSettings.globalize_path("res://qa/.runtime/persistence-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(folder)
	disk_path = folder.path_join("save.json")
	OS.set_environment("MOUNTAINMARK_DATA_DIR", folder)
	var legacy: Dictionary = {"checkpoint":38, "elapsed":73.0, "falls":2, "moves":12, "summits":1, "best_time":125.0, "clean_ascent":true, "in_progress":true}
	var file: FileAccess = FileAccess.open(disk_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy))
	file.close()
	packed = load("res://scenes/main.tscn")
	spawn_game()
	verify(game._save_path == disk_path, "Save path redirected before ready")
	verify(game.save_data == read_disk(), "Read actual legacy disk save")
	game.start_climb(true)
	game.climber.set_process(false)
	verify(game.climber.current_hold_id == 0 and game.elapsed == 73.0, "Legacy disk save resumes safely")
	verify(game.route_unlocked(1) and game.extreme_unlocked(), "Legacy disk completion unlocks retained")
	var anchor: int = 0
	for hold: Dictionary in game.world.holds:
		if bool(hold.checkpoint) and int(hold.id) > 0:
			anchor = int(hold.id)
			break
	game.climber.setup(game._hold(anchor))
	game.climber.climbing = true
	game.elapsed = 89.5
	game.climber.total_moves = 19
	game._on_reached(anchor)
	var persisted: Dictionary = read_disk()
	verify(int(persisted.get("version",0)) == 3 and int(persisted.checkpoint) == anchor, "New anchor really writes v3 save")
	verify(float(persisted.elapsed) == 89.5 and int(persisted.moves) == 19, "Anchor persists counters")
	verify(float(persisted.best_time) == 125.0 and bool(persisted.clean_ascent), "Migration preserves historical achievements")
	var journey: Dictionary = progress(persisted)
	game.mode = "menu"
	game.play_style = "challenge"
	game.challenge_index = 0
	game.start_climb(false)
	game.climber.set_process(false)
	game.elapsed = 25.0
	game.best_precise_streak = 10
	game._save_progress()
	verify(progress(read_disk()) == journey, "Challenge save attempt cannot overwrite journey file")
	game._finish()
	persisted = read_disk()
	verify(progress(persisted) == journey, "Challenge completion preserves journey file")
	verify(persisted.get("records",{}).has("challenge_0"), "Challenge result physically persisted")
	verify(persisted.get("badges",{}).has("岩段练习生"), "Challenge badge physically persisted")
	var cards: PackedStringArray = DirAccess.get_files_at(folder.path_join("postcards"))
	verify(not cards.is_empty(), "Challenge writes isolated text postcard")
	game.mode = "menu"
	game.play_style = "extreme"
	game.route_index = 0
	game.start_climb(false)
	game.climber.set_process(false)
	game.elapsed = 160.0
	game._save_progress()
	verify(progress(read_disk()) == journey, "Extreme save attempt cannot overwrite journey file")
	game._finish()
	persisted = read_disk()
	verify(progress(persisted) == journey, "Extreme completion preserves journey file")
	verify(persisted.get("records",{}).has("ridge_extreme"), "Extreme independent record physically persisted")
	await stop_game()
	spawn_game()
	verify(game.save_data.get("records",{}).has("challenge_0") and game.save_data.get("records",{}).has("ridge_extreme"), "Restart reads independent records")
	game.start_climb(true)
	game.climber.set_process(false)
	verify(game.play_style == "journey" and game.climber.current_hold_id == anchor, "Restart resumes journey original anchor")
	verify(game.elapsed == 89.5 and game.climber.total_moves == 19, "Restart restores journey original counters")
	game.elapsed = 210.0
	game._finish()
	persisted = read_disk()
	verify(not bool(persisted.in_progress), "Journey completion closes active journey")
	verify(persisted.get("records",{}).has("ridge_journey"), "Journey completion record physically persisted")
	verify(persisted.get("completed_routes",{}).get("0",false), "Journey completion unlock physically persisted")
	var unchanged: bool = FileAccess.file_exists(player_path) == player_exists
	if player_exists:
		unchanged = unchanged and FileAccess.get_file_as_bytes(player_path) == player_bytes
	verify(unchanged, "Player save untouched byte-for-byte")
	await stop_game()
	OS.set_environment("MOUNTAINMARK_DATA_DIR", previous_environment)
	print("PERSISTENCE_V3_RESULT checks=", checks, " failures=", failures.size(), " isolated_data=", folder)
	quit(0 if failures.is_empty() else 1)
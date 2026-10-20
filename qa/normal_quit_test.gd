extends SceneTree
## Exercises the real asynchronous quit_game entry point without player-save writes.
var game: Node3D
var failures: int = 0
var checks: int = 0
var save_path: String = ""
var save_existed: bool = false
var save_bytes: PackedByteArray
var quit_started: int = 0

func _initialize() -> void:
	call_deferred("run")

func verify(ok: bool, label: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failures += 1

func run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	game = scene.instantiate() as Node3D
	root.add_child(game)
	save_path = game._save_path
	save_existed = FileAccess.file_exists(save_path)
	if save_existed:
		save_bytes = FileAccess.get_file_as_bytes(save_path)
	game._save_path = ProjectSettings.globalize_path("res://qa/normal-quit-save.json")
	game.save_data = {}
	game.start_climb(false)
	game.elapsed = 12.5
	game.climber.total_moves = 5
	await create_timer(0.1).timeout
	quit_started = Time.get_ticks_msec()
	game.quit_game()
	verify(game.mode == "quitting" and not game.climber.climbing, "normal quit prevents further climbing")
	var streams_cleared: bool = not game.sound._started and game.sound._clips.is_empty()
	for child: Node in game.sound.get_children():
		if child is AudioStreamPlayer:
			streams_cleared = streams_cleared and not child.playing and child.stream == null
	verify(streams_cleared, "normal quit stops players and releases all audio streams")
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(game._save_path))
	verify(saved is Dictionary and bool(saved.get("in_progress", false)) and int(saved.get("moves", 0)) == 5, "normal quit saves current run only to isolated test file")
	game.quit_game()
	verify(game.mode == "quitting", "duplicate quit is safely ignored")
	await create_timer(0.15).timeout
	verify(is_instance_valid(game) and game.mode == "quitting", "normal quit allows audio thread a cleanup interval")
	if failures > 0:
		quit(1)

func _finalize() -> void:
	var unchanged: bool = FileAccess.file_exists(save_path) == save_existed
	if save_existed:
		unchanged = unchanged and FileAccess.get_file_as_bytes(save_path) == save_bytes
	verify(unchanged, "normal quit leaves player save.json byte-for-byte unchanged")
	verify(quit_started > 0 and Time.get_ticks_msec() - quit_started >= 280, "normal quit completes after audio cleanup interval")
	print("NORMAL_QUIT_RESULT checks=", checks, " failures=", failures)

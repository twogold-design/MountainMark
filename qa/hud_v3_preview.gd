extends SceneTree
## Independent HUD layout smoke test. Does not load or modify player saves.
const Hud = preload("res://scripts/hud.gd")
class PreviewGame extends Node3D:
	var mode: String = "menu"
	var toast_time: float = 0.0
	var toast: String = ""
	var toast_sub: String = ""
	var active_route: Dictionary = {"name": "回声峡谷"}
	var help_open: bool = false
	var route_index: int = 0
	var play_style: String = "journey"
	var outfit_index: int = 0
	var muted: bool = false
	var save_data: Dictionary = {"in_progress": true}
	var summit_time: float = 0.0
	var elapsed: float = 821.0
	var route_height: float = 72.0
	var falls: int = 0
	var result_title: String = "山在脚下。"
	var result_detail: String = "松涛渐远，而你比出发时更高了一点。"
	var earned_badges: Array[String] = ["稳如磐石", "留有余力", "另辟蹊径"]
	var postcard_path: String = ""
	var run_collections: Array[String] = []
	var climber: Node3D
	var ui: Control
	func route_unlocked(_index: int) -> bool: return true
	func extreme_unlocked() -> bool: return false
	func route_info() -> Dictionary: return {"subtitle": "晨光穿过松林，第一道山脊就在眼前。"}
	func select_route(index: int) -> void:
		route_index = index
		ui.refresh_buttons()
	func select_style(style: String) -> void:
		play_style = style
		ui.refresh_buttons()
	func start_climb(_resume: bool) -> void: pass
	func continue_journey() -> void: pass
	func toggle_help() -> void: pass
	func open_journal() -> void: pass
	func close_journal() -> void: pass
	func cycle_outfit() -> void: pass
	func toggle_audio() -> void: pass
	func quit_game() -> void: pass
	func export_postcard() -> void: pass
	func open_postcards() -> void: pass
	func return_menu() -> void: pass
	func journal_lines() -> Array[String]:
		var lines: Array[String] = []
		for i: int in range(20):
			lines.append("【松风岩脊】" if i % 5 == 0 else "登顶记录 · 零跌落 · 已探索观景点 · 最佳 13:41")
		return lines
	func time_string(_value: float) -> String: return "13:41"
class PreviewClimber extends Node3D:
	var total_moves: int = 56
var game: PreviewGame
var ui: Control
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	root.size = Vector2i(1280, 900)
	root.content_scale_size = Vector2i(1280, 900)
	game = PreviewGame.new()
	root.add_child(game)
	game.climber = PreviewClimber.new()
	game.add_child(game.climber)
	ui = Hud.new()
	ui.game = game
	game.ui = ui
	root.add_child(ui)
	await process_frame
	assert(ui.buttons.size() == 12)
	assert(ui.buttons[4].disabled)
	ui.buttons[1].pressed.emit()
	assert(game.route_index == 1)
	await capture("menu")
	game.mode = "journal"
	ui.refresh_buttons()
	assert(ui.buttons[0].disabled)
	ui.buttons[1].pressed.emit()
	assert(ui.journal_page == 1)
	assert(ui.buttons[1].disabled)
	await capture("journal")
	game.mode = "summit"
	game.summit_time = 1.0
	ui.refresh_buttons()
	assert(ui.buttons.is_empty())
	game.summit_time = 6.0
	await process_frame
	await process_frame
	assert(ui.buttons.size() == 4)
	await capture("summit")
	print("HUD_V3_PASS: route/mode callbacks; lock states; journal pagination; summit delay; 3 rendered screens")
	quit()
func capture(label: String) -> void:
	ui.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	image.save_png("res://qa/hud-v3-" + label + ".png")
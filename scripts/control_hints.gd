extends Control
## Essential controls stay readable while the expedition HUD is hidden.
const FONT: Font = preload("res://assets/fonts/ui.ttc")
const TEXT: Color = Color("d8e1d8")
var game: Node3D
var _lines: Array[String] = []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	hide()
	refresh()

func get_hint_lines() -> Array[String]:
	if game.help_open:
		return ["Esc 关闭手册 · 【·】恢复界面", "M 声音 · F11 全屏"]
	match game.mode:
		"playing":
			return [
				"左键自动选手，右键另一手 · 点住沿淡线回拉，绿色时松手 · Q/E 选脚 · A/D 微调",
				"W 观察 · 中键/Z X 读线 · 空格 镁粉 · R 返回 · Esc 暂停 · 【·】恢复界面"
			]
		"paused":
			return ["已暂停 · Esc 继续 · 【·】恢复界面", "M 声音 · F11 全屏"]
		"fallen":
			return ["Enter 返回锚点重试 · 【·】恢复界面", "M 声音 · F11 全屏"]
		"journal":
			return ["Esc 返回 · 【·】恢复界面", "M 声音 · F11 全屏"]
		"menu":
			return ["Enter 开始攀登 · 【·】恢复界面与菜单", "M 声音 · F11 全屏"]
		_:
			return ["【·】恢复界面与操作按钮", "M 声音 · F11 全屏"]

func refresh() -> void:
	var current: Array[String] = get_hint_lines()
	if current != _lines:
		_lines = current
		queue_redraw()

func _draw() -> void:
	var width: float = minf(1020.0, size.x - 72.0)
	var wrapped: Array[String] = []
	for line: String in _lines:
		var row: String = ""
		for character: String in line:
			if not row.is_empty() and FONT.get_string_size(row + character, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x > width - 32.0:
				wrapped.append(row)
				row = ""
			row += character
		wrapped.append(row)
	var height: float = wrapped.size() * 23.0 + 20.0
	var left: float = (size.x - width) * 0.5
	var top: float = size.y - height - 30.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.06, 0.07, 0.56)
	style.set_corner_radius_all(4)
	draw_style_box(style, Rect2(left, top, width, height))
	for i: int in range(wrapped.size()):
		draw_string(FONT, Vector2(left + 16.0, top + 26.0 + i * 23.0), wrapped[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, TEXT)

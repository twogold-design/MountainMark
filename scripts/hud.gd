extends Control
## Carefully laid out immediate-mode expedition interface.
const INK: Color = Color("15292f")
const PAPER: Color = Color("f1e7d2")
const MUTED: Color = Color("a9beb9")
const GOLD: Color = Color("ebc68d")
const MINT: Color = Color("a9ddc4")
var game: Node3D
var font: Font = preload("res://assets/fonts/ui.ttc")
var buttons: Array[Button] = []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(refresh_buttons)
	refresh_buttons()

func _text(content: String, x: float, y: float, px: int = 20, color: Color = PAPER) -> void:
	draw_string(font, Vector2(x + 1, y + 1), content, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(0.025, 0.06, 0.07, color.a * 0.4))
	draw_string(font, Vector2(x, y), content, HORIZONTAL_ALIGNMENT_LEFT, -1, px, color)

func _center(content: String, x: float, y: float, px: int = 20, color: Color = PAPER) -> void:
	_text(content, x - font.get_string_size(content, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x * 0.5, y, px, color)

func _rule(x: float, y: float, width: float, color: Color = Color(0.9, 0.9, 0.8, 0.2)) -> void:
	draw_line(Vector2(x, y), Vector2(x + width, y), color, 1.0, true)

func _mountain(at: Vector2, scale_factor: float, color: Color) -> void:
	var points: PackedVector2Array = PackedVector2Array([Vector2(0, 31), Vector2(24, -14), Vector2(38, 10), Vector2(51, -5), Vector2(74, 31)])
	for i: int in range(points.size()):
		points[i] = at + points[i] * scale_factor
	draw_polyline(points, color, 2.0, true)
	draw_circle(at + Vector2(66, -19) * scale_factor, 3.0 * scale_factor, GOLD)

func _panel(rect: Rect2, alpha: float = 0.88) -> void:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.052, 0.10, 0.115, alpha)
	style.border_color = Color(0.85, 0.85, 0.73, 0.17)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	draw_style_box(style, rect)

func _draw() -> void:
	if game == null:
		return
	var w: float = size.x
	var h: float = size.y
	# Delicate top/bottom shading preserves the mountain's natural light.
	for i: int in range(16):
		var alpha: float = 0.018 * float(16 - i) / 16.0
		draw_rect(Rect2(0, 0, w, 12 + i * 12), Color(0.02, 0.05, 0.06, alpha))
		draw_rect(Rect2(0, h - 15 - i * 10, w, 15 + i * 10), Color(0.02, 0.05, 0.06, alpha))
	if game.mode == "menu":
		_draw_menu(w, h)
	elif game.mode == "summit":
		_draw_summit(w, h)
	else:
		_draw_game(w, h)
		if game.mode == "paused":
			_draw_pause(w, h)
		elif game.mode == "fallen":
			_draw_fall(w, h)
	if game.help_open:
		_draw_help(w, h)

func _draw_menu(w: float, h: float) -> void:
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(w * 0.80, 0), Vector2(w * 0.80, h), Vector2(0, h)]), PackedColorArray([Color(0.025,0.065,0.08,0.97), Color(0.025,0.065,0.08,0.0), Color(0.025,0.065,0.08,0.0), Color(0.025,0.065,0.08,0.97)]))

	_mountain(Vector2(70, 66), 0.55, PAPER)
	_text("M O U N T A I N   M A R K", 127, 77, 14)
	_text("一 段 只 属 于 你 的 向 上 旅 程", 70, h * 0.255, 17, MUTED)
	_text("山 痕", 63, h * 0.255 + 125, 110)
	_text("风很大。山很静。", 72, h * 0.255 + 183, 27)
	_text("把目光放在下一处岩点，把世界留在身后。", 72, h * 0.255 + 224, 18, MUTED)
	_rule(72, h * 0.255 + 259, 340)
	_text("01  /  风 脊", 74, h * 0.255 + 294, 16, GOLD)
	_text("72 米垂直岩壁   ·   4 段攀登   ·   单人旅程", 74, h * 0.255 + 326, 16, MUTED)
	_text("攀 登 更 新  0.2.1", 72, h - 44, 13, MUTED)
	_text("戴上耳机，听见山的呼吸。", w - 310, h - 44, 15, PAPER)
	_panel(Rect2(w - 272, 56, 208, 94), 0.4)
	_text("风 脊  /  WIND RIDGE", w - 249, 89, 13, GOLD)
	_text("海拔 2,816 m", w - 249, 126, 22)
	# The quiet expedition trace at the far right hints at the route.
	var base_x: float = w - 91
	draw_line(Vector2(base_x, h * 0.4), Vector2(base_x, h * 0.73), Color(0.94, 0.91, 0.81, 0.4), 1.0, true)
	for i: int in range(5):
		var y: float = h * 0.4 + i * h * 0.0825
		draw_circle(Vector2(base_x, y), 3.0 if i > 0 else 5.0, GOLD if i == 0 else PAPER)
	_text("峰", base_x - 8, h * 0.4 - 23, 16)
	_text("起", base_x - 8, h * 0.73 + 32, 16, MUTED)
	if int(game.save_data.get("summits", 0)) > 0:
		_text("已登顶 %d 次  ·  最佳 %s" % [int(game.save_data.summits), game.time_string(float(game.save_data.best_time))], 73, h - 87, 14, GOLD)

func _draw_game(w: float, h: float) -> void:
	# Top-left expedition card.
	_panel(Rect2(36, 32, 310, 107), 0.68)
	_mountain(Vector2(55, 58), 0.38, PAPER)
	_text("山 痕  /  WIND RIDGE", 98, 67, 13, MUTED)
	_text(game.CHAPTERS[mini(game.chapter, 4)], 55, 111, 22)
	var climbed: float = maxf(0.0, float(game.climber.get_reach_origin().y) - 1.0)
	_panel(Rect2(w - 230, 32, 194, 107), 0.68)
	_text("垂直高度", w - 211, 62, 13, MUTED)
	_text("%04.1f" % climbed, w - 213, 108, 38)
	_text("/ 72 m", w - 104, 106, 15, MUTED)
	# A tiny vertical route diagram.
	var rx: float = w - 59
	var top: float = h * 0.28
	var bottom: float = h * 0.72
	draw_line(Vector2(rx, top), Vector2(rx, bottom), Color(0.9, 0.9, 0.8, 0.26), 2.0, true)
	var prog: float = clampf(climbed / 71.0, 0.0, 1.0)
	draw_line(Vector2(rx, bottom), Vector2(rx, lerpf(bottom, top, prog)), GOLD, 2.0, true)
	for i: int in range(5):
		var y: float = lerpf(bottom, top, float(i) / 4.0)
		draw_circle(Vector2(rx, y), 3.0, GOLD if climbed >= float(i) * 18.0 else MUTED)
		draw_arc(Vector2(rx, y), 7.0, 0, TAU, 20, Color(0.9, 0.9, 0.8, 0.25), 1.0, true)
	draw_circle(Vector2(rx, lerpf(bottom, top, prog)), 5.0, PAPER)
	_text("顶", rx - 8, top - 22, 14, PAPER)
	_text("%02d%%" % int(prog * 100), rx - 20, bottom + 33, 13, MUTED)
	# Projected reachable points remain visible against complex rock geometry.
	if game.mode == "playing":
		for id: int in game.reachable:
			var hold: Dictionary = game._hold(id)
			var pos: Vector3 = hold.position
			if game.camera.is_position_behind(pos):
				continue
			var p: Vector2 = game.camera.unproject_position(pos)
			if p.y < 150 or p.y > h - 160 or p.x < 25 or p.x > w - 110:
				continue
			var hover: bool = id == game.hovered_id
			var selected: bool = game.grip_active and id == game.grip_id
			var preview: bool = id == game.preview_id
			var color: Color = MINT if selected or preview else (GOLD if bool(hold.rest) else PAPER)
			var rad: float = 24.0 if selected else (22.0 if hover else 15.0)
			draw_circle(p, rad + 3, Color(0.025, 0.08, 0.08, 0.24))
			draw_arc(p, rad, game.clock_time * 0.15, game.clock_time * 0.15 + TAU * 0.82, 42, color, 2.0 if hover else 1.3, true)
			draw_circle(p, 3, color)
			if preview and not hover and not selected:
				_text("观察目标", p.x + 23, p.y - 16, 13, MINT)
			if bool(hold.rest):
				_text("休息" if not bool(hold.checkpoint) else "锚点", p.x + 23, p.y + 6, 13, GOLD)
			if hover:
				var reach_distance: float = game.climber.get_reach_origin().distance_to(pos)
				var effort: String = "稳妥" if reach_distance < 1.7 else ("需发力" if reach_distance < 2.4 else "远点 · 费力")
				_text("按住左 / 右键准备", p.x + 29, p.y - 31, 15, PAPER)
				_text("%.1f m  ·  %s" % [reach_distance, effort], p.x + 29, p.y - 10, 12, MUTED)
	# Bottom-left grip meter, modelled after a field instrument.
	_panel(Rect2(36, h - 172, 310, 113), 0.78)
	var stamina: float = game.climber.stamina
	var color: Color = MINT if stamina > 40 else GOLD
	if stamina < 22:
		color = Color("ee896e")
	_text("握 力", 56, h - 138, 15, MUTED)
	_text("镁粉 %d / 3" % game.chalk_charges, 135, h - 138, 13, GOLD if game.chalk_charges > 0 else MUTED)
	_text("%03d" % int(stamina), 253, h - 134, 25, color)
	for i: int in range(25):
		var filled: bool = float(i) * 4.0 < stamina
		draw_rect(Rect2(56 + i * 10.7, h - 116, 7.5, 13), color if filled else Color(0.8, 0.9, 0.85, 0.13))
	var status: String = "稳住呼吸，寻找下一处岩点"
	if game.grip_active:
		status = "准备中 · 松开鼠标完成抓握"
	elif game.climber.moving:
		status = "伸手  ·  抓握  ·  蹬腿"
	elif game.current_rest:
		status = "安全休息中  ·  握力正在恢复"
	elif stamina < 30:
		status = "握力告急  ·  空格使用镁粉"
	_text(status, 56, h - 79, 13, color)
	_panel(Rect2(360, h - 119, w - 396, 83), 0.74)
	_text("按住鼠标准备 → A / D 调重心 → 双区就绪后松开", 375, h - 81, 15, PAPER)
	_text("W 观察   ·   空格 镁粉   ·   R 返回锚点   ·   Esc 暂停   ·   M 声音   ·   F11 全屏", 375, h - 52, 13, MUTED)
	_text(game.time_string(game.elapsed), w - 128, h - 91, 21, PAPER)
	if game.grip_active:
		_draw_grip_controls(w, h)
	elif game.mode == "playing" and not game.climber.moving:
		_panel(Rect2(370, h - 197, w - 406, 58), 0.56)
		var hint: String = "按住带光圈的岩点，观察蓄力与重心两个绿区。"
		if game.current_rest:
			hint = "在金色岩点休息。选好路线，再按住鼠标准备下一步。"
		if game.slip_streak > 0:
			hint = "连续失手 %d / 3 · 稳住重心再松手，第三次将触发安全绳。" % game.slip_streak
		_text(hint, 389, h - 162, 14, GOLD if game.slip_streak > 0 else MUTED)
	if game.toast_time > 0.0:
		var fade: float = minf(1.0, game.toast_time)
		var width: float = 620.0
		_panel(Rect2((w - width) * 0.5, 34, width, 89), 0.72 * fade)
		_center(game.toast, w * 0.5, 69, 22, Color(PAPER, fade))
		_center(game.toast_sub, w * 0.5, 101, 14, Color(MUTED, fade))

func _skill_bar(rect: Rect2, value: float, target: float, window: float, aligned: bool) -> void:
	draw_rect(rect, Color(0.70, 0.83, 0.81, 0.12))
	var band_left: float = clampf(target - window, 0.0, 1.0)
	var band_right: float = clampf(target + window, 0.0, 1.0)
	var band: Rect2 = Rect2(rect.position + Vector2(rect.size.x * band_left, 0), Vector2(rect.size.x * (band_right - band_left), rect.size.y))
	draw_rect(band, Color(MINT, 0.52 if aligned else 0.28))
	draw_rect(band, Color(MINT, 0.85), false, 1.0)
	var target_x: float = rect.position.x + rect.size.x * target
	draw_line(Vector2(target_x, rect.position.y + 2), Vector2(target_x, rect.end.y - 2), Color(MINT, 0.7), 1.0)
	var cursor_x: float = rect.position.x + rect.size.x * clampf(value, 0.0, 1.0)
	var cursor_color: Color = PAPER
	draw_line(Vector2(cursor_x, rect.position.y - 4), Vector2(cursor_x, rect.end.y + 4), cursor_color, 3.0, true)
	draw_colored_polygon(PackedVector2Array([Vector2(cursor_x - 4, rect.position.y - 9), Vector2(cursor_x + 4, rect.position.y - 9), Vector2(cursor_x, rect.position.y - 4)]), cursor_color)

func _draw_grip_controls(w: float, h: float) -> void:
	var panel_width: float = minf(490.0, w - 410.0)
	var left: float = w - panel_width - 130.0
	var top: float = h - 340.0
	var ready: bool = game.grip_ready()
	var power_ready: bool = absf(game.grip_power - game.grip_target) <= game.grip_window
	var balance_ready: bool = absf(game.balance - game.balance_target) <= game.balance_window
	var remaining: float = maxf(0.0, 4.5 - game.grip_time)
	_panel(Rect2(left, top, panel_width, 192), 0.93)
	var hand: String = "左手" if game.grip_hand == 0 else "右手"
	_text("双区就绪 · 现在松开" if ready else hand + " · 稳住，等待出手", left + 20, top + 28, 19, MINT if ready else PAPER)
	_text("%.1f 秒" % remaining, left + panel_width - 82, top + 27, 15, Color("ee896e") if remaining < 1.0 else MUTED)
	_rule(left + 20, top + 40, panel_width - 40, Color(MINT if ready else MUTED, 0.2))
	_text("蓄力  /  等待白针进入绿区", left + 20, top + 62, 13, MUTED)
	_text("已对准" if power_ready else "等待时机", left + panel_width - 88, top + 62, 13, MINT if power_ready else GOLD)
	_skill_bar(Rect2(left + 20, top + 76, panel_width - 40, 13), game.grip_power, game.grip_target, game.grip_window, power_ready)
	_text("重心  /  按住 A 左移 · D 右移", left + 20, top + 116, 13, MUTED)
	_text("已对准" if balance_ready else "调整重心", left + panel_width - 88, top + 116, 13, MINT if balance_ready else GOLD)
	_skill_bar(Rect2(left + 20, top + 130, panel_width - 40, 13), (game.balance + 1.0) * 0.5, (game.balance_target + 1.0) * 0.5, game.balance_window * 0.5, balance_ready)
	_text("松开%s键抓牢 · 双区都要对准" % ("左" if game.grip_hand == 0 else "右"), left + 20, top + 174, 13, MINT if ready else PAPER)
	if game.slip_streak > 0:
		_text("失手 %d / 3" % game.slip_streak, left + panel_width - 92, top + 174, 12, GOLD)

func _draw_fall(w: float, h: float) -> void:
	var fade: float = clampf(game.fall_time / 0.3, 0.0, 1.0)
	draw_rect(Rect2(0, 0, w, h), Color(0.025, 0.045, 0.055, 0.76 * fade))
	var cx: float = w * 0.5
	var cy: float = h * 0.5
	_panel(Rect2(cx - 330, cy - 225, 660, 440), 0.97)
	_center("安 全 绳 保 护", cx, cy - 169, 15, GOLD)
	_center(game.fall_title, cx, cy - 102, 38)
	_center(game.fall_reason, cx, cy - 56, 19, MUTED)
	_rule(cx - 270, cy - 24, 540)
	if game.checkpoint == 0:
		_center("尚未抵达安全锚点，将回到山脚营地。", cx, cy + 22, 18)
	else:
		var altitude: float = maxf(0.0, float(game._hold(game.checkpoint).position.y) - 1.0)
		_center("将返回 %.1f 米安全锚点，已完成的前段路线仍保留。" % altitude, cx, cy + 22, 18)
	_center("缓一口气，下一次可以更稳。", cx, cy + 61, 16, MUTED)
	_center("按 Enter 或点击按钮继续" if game.fall_time >= 0.6 else "安全绳正在收紧……", cx, cy + 188, 13, MUTED)

func _draw_pause(w: float, h: float) -> void:
	draw_rect(Rect2(0, 0, w, h), Color(0.025, 0.055, 0.065, 0.72))
	_panel(Rect2(w * 0.5 - 230, h * 0.5 - 230, 460, 460), 0.96)
	_center("山一直在这里。", w * 0.5, h * 0.5 - 150, 34)
	_center("休息片刻，再继续向上。", w * 0.5, h * 0.5 - 107, 17, MUTED)
	_rule(w * 0.5 - 167, h * 0.5 - 71, 334)

func _draw_summit(w: float, h: float) -> void:
	draw_rect(Rect2(0, 0, w, 42), Color(0.02, 0.04, 0.05, 0.92))
	draw_rect(Rect2(0, h - 42, w, 42), Color(0.02, 0.04, 0.05, 0.92))
	var fade: float = clampf((game.summit_time - 0.8) / 2.0, 0.0, 1.0)
	if fade <= 0.0:
		return
	draw_polygon(PackedVector2Array([Vector2(0,42), Vector2(840,42), Vector2(840,h-42), Vector2(0,h-42)]), PackedColorArray([Color(0.025,0.065,0.075,fade * 0.94), Color(0.025,0.065,0.075,0), Color(0.025,0.065,0.075,0), Color(0.025,0.065,0.075,fade * 0.94)]))
	_text("A S C E N T   C O M P L E T E", 72, 126, 16, Color(GOLD, fade))
	_text("山在脚下。", 68, 224, 64, Color(PAPER, fade))
	_text("而你，比出发时更高了一点。", 74, 270, 21, Color(PAPER, fade))
	_rule(74, 312, 350, Color(GOLD, fade * 0.4))
	_text("风脊峰    2,816 m", 74, 354, 26, Color(PAPER, fade))
	_text("攀登用时", 74, 411, 14, Color(MUTED, fade))
	_text(game.time_string(game.elapsed), 74, 454, 32, Color(PAPER, fade))
	_text("落手次数", 230, 411, 14, Color(MUTED, fade))
	_text(str(game.climber.total_moves), 230, 454, 32, Color(PAPER, fade))
	_text("绳索保护", 360, 411, 14, Color(MUTED, fade))
	_text(str(game.falls), 360, 454, 32, Color(PAPER, fade))
	_panel(Rect2(74, 493, 380, 84), fade * 0.62)
	var center: Vector2 = Vector2(112, 534)
	var diamond: PackedVector2Array = PackedVector2Array([center + Vector2(0,-18), center + Vector2(17,0), center + Vector2(0,18), center + Vector2(-17,0), center + Vector2(0,-18)])
	draw_polyline(diamond, Color(GOLD, fade), 2, true)
	_text("成就解锁  ·  群山之上", 148, 527, 18, Color(GOLD, fade))
	_text("一气呵成 · 全程未触发保护" if game.falls == 0 else "不止一次出发，终于抵达", 148, 553, 13, Color(MUTED, fade))
	_text("此刻，世界只剩下风。", 74, h - 99, 17, Color(PAPER, fade))

func _draw_help(w: float, h: float) -> void:
	draw_rect(Rect2(0, 0, w, h), Color(0.02, 0.05, 0.06, 0.94))
	var left: float = w * 0.5 - 390
	_text("把下一步，交给自己。", left, 146, 39)
	_text("攀登手册  /  FIELD NOTES", left, 186, 15, GOLD)
	_rule(left, 215, 780)
	var rows: Array = [
		["01", "观察路线", "W 标出建议点。带光圈的岩点可抓握，远点更费力。"],
		["02", "按住，先准备", "对准岩点按住鼠标左 / 右键，选择左 / 右手；脚自动落位。"],
		["03", "双区就绪再松手", "按住 A / D 把重心移入绿区；蓄力白针进入绿区时松开鼠标。"],
		["04", "把握 4.5 秒", "超时或未对准会失手并扣握力；连续三次失手由安全绳保护。"],
		["05", "管理镁粉与握力", "空格用镁粉，共 3 次、有冷却；锚点补满，金色岩点回复握力。"],
		["06", "一步步抵达", "高处绿区更窄。R 返回锚点；沿 72 米风脊向上，留下登顶记录。"]
	]
	for i: int in range(rows.size()):
		var y: float = 264 + i * 75
		_text(rows[i][0], left, y, 20, GOLD)
		_text(rows[i][1], left + 59, y, 21)
		_text(rows[i][2], left + 59, y + 28, 15, MUTED)
	_text("Esc 暂停   /   M 声音   /   F11 全屏     ·     进度保存在游戏目录", left, 748, 14, MUTED)

func _button(label: String, rect: Rect2, callback: Callable, primary: bool = false) -> void:
	var button: Button = Button.new()
	button.text = label
	button.position = rect.position
	button.size = rect.size
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font", font)
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", INK if primary else PAPER)
	button.add_theme_color_override("font_hover_color", INK if primary else GOLD)
	button.add_theme_color_override("font_pressed_color", INK)
	var normal: StyleBoxFlat = StyleBoxFlat.new()
	normal.bg_color = GOLD if primary else Color(0.08, 0.15, 0.17, 0.6)
	normal.border_color = Color(0.9, 0.88, 0.77, 0.28)
	normal.set_border_width_all(0 if primary else 1)
	normal.set_corner_radius_all(3)
	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = PAPER if primary else Color(0.16, 0.26, 0.28, 0.94)
	hover.border_color = GOLD
	var pressed: StyleBoxFlat = normal.duplicate()
	pressed.bg_color = GOLD
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", hover)
	button.pressed.connect(callback)
	add_child(button)
	buttons.append(button)

func refresh_buttons() -> void:
	for button: Button in buttons:
		button.hide()
		button.queue_free()
	buttons.clear()
	if game == null:
		return
	var w: float = size.x
	var h: float = size.y
	if game.help_open:
		_button("知道了，向上吧  →", Rect2(w * 0.5 + 160, 780, 230, 52), game.toggle_help, true)
		return
	match game.mode:
		"fallen":
			_button("回到山脚，再试一次" if game.checkpoint == 0 else "回到锚点，继续攀登", Rect2(w * 0.5 - 220, h * 0.5 + 103, 440, 55), game.retry_after_fall, true)
		"menu":
			var y: float = h * 0.255 + 367
			_button("开始攀登   ↗", Rect2(72, y, 255, 56), func(): game.start_climb(false), true)
			_button("攀登手册", Rect2(345, y, 145, 56), game.toggle_help)
			if bool(game.save_data.get("in_progress", false)):
				_button("继续上次旅程", Rect2(72, y + 69, 255, 44), func(): game.start_climb(true))
			_button("声音  " + ("关" if game.muted else "开"), Rect2(w - 267, h - 126, 110, 40), game.toggle_audio)
			_button("离开", Rect2(w - 143, h - 126, 78, 40), game.quit_game)
		"paused":
			_button("继续攀登   ↗", Rect2(w * 0.5 - 166, h * 0.5 - 39, 332, 53), game.toggle_pause, true)
			_button("攀登手册", Rect2(w * 0.5 - 166, h * 0.5 + 31, 158, 47), game.toggle_help)
			_button("声音  " + ("关" if game.muted else "开"), Rect2(w * 0.5 + 8, h * 0.5 + 31, 158, 47), game.toggle_audio)
			_button("保存并返回山脚", Rect2(w * 0.5 - 166, h * 0.5 + 96, 332, 47), game.return_menu)
		"summit":
			_button("再攀一次   ↗", Rect2(w - 298, h - 183, 226, 53), func(): game.start_climb(false), true)
			_button("回到山脚", Rect2(w - 298, h - 114, 226, 43), game.return_menu)





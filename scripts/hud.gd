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
var journal_page: int = 0
var _summit_buttons_visible: bool = false
const ROUTE_LABELS: Array[String] = ["松风岩脊", "回声峡谷", "云上孤峰"]
const ROUTE_MOODS: Array[String] = ["松林 · 日出 · 风蚀石阶", "瀑布 · 峡谷 · 湿壁横渡", "云海 · 阵风 · 暴露山脊"]
const ROUTE_NOTES: Array[String] = ["沿松林岩脊向上，选择绕行或直攀。", "把重心交给支撑脚，穿过峡谷水雾。", "听风停下的瞬间，越过最后一道山脊。"]
const STYLE_NAMES: Array[String] = ["登山旅程", "岩段挑战", "极限登顶"]
const STYLE_KEYS: Array[String] = ["journey", "challenge", "extreme"]
const CHALLENGE_NAMES: Array[String] = ["稳稳向上", "横渡练习", "湿壁考验"]

func _process(_delta: float) -> void:
	if game == null:
		return
	var should_show: bool = game.mode == "summit" and game.summit_time >= 4.0
	if should_show != _summit_buttons_visible:
		_summit_buttons_visible = should_show
		refresh_buttons()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(refresh_buttons)
	refresh_buttons()

func _text(content: String, x: float, y: float, px: int = 20, color: Color = PAPER) -> void:
	draw_string(font, Vector2(x + 1, y + 1), content, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(0.025, 0.06, 0.07, color.a * 0.4))
	draw_string(font, Vector2(x, y), content, HORIZONTAL_ALIGNMENT_LEFT, -1, px, color)

func _wrap_lines(content: String, width: float, px: int) -> Array[String]:
	var lines: Array[String] = []
	var line: String = ""
	for i: int in range(content.length()):
		var ch: String = content.substr(i, 1)
		if ch == "\n":
			lines.append(line)
			line = ""
			continue
		if not line.is_empty() and ch not in "，。、；：？！）】》,.!?;:" and font.get_string_size(line + ch, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > width:
			lines.append(line)
			line = ch
		else:
			line += ch
	lines.append(line)
	return lines

func _wrapped(content: String, x: float, y: float, width: float, px: int = 16, line_height: float = 23.0, color: Color = PAPER) -> void:
	var lines: Array[String] = _wrap_lines(content, width, px)
	for i: int in range(lines.size()):
		_text(lines[i], x, y + i * line_height, px, color)

func _center_wrapped(content: String, x: float, y: float, width: float, px: int, line_height: float, color: Color = PAPER) -> void:
	var lines: Array[String] = _wrap_lines(content, width, px)
	for i: int in range(lines.size()):
		_center(lines[i], x, y + i * line_height, px, color)

func _draw_toast(w: float) -> void:
	if game.toast_time <= 0.0:
		return
	var fade: float = minf(1.0, game.toast_time)
	var width: float = 530.0
	_panel(Rect2((w - width) * 0.5, 34, width, 96), 0.85 * fade)
	_center(game.toast, w * 0.5, 69, 22, Color(PAPER, fade))
	_center_wrapped(game.toast_sub, w * 0.5, 98, width - 36, 14, 20, Color(MUTED, fade))

func _journal_rows(width: float) -> Array[String]:
	var rows: Array[String] = []
	for line: String in game.journal_lines():
		rows.append_array(_wrap_lines(line, width, 17))
	return rows
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
		_draw_toast(w)
	elif game.mode == "journal":
		_draw_journal(w, h)
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
	draw_rect(Rect2(0, 0, w, h), Color(0.025, 0.065, 0.08, 0.70))
	_mountain(Vector2(64, 57), 0.55, PAPER)
	_text("M O U N T A I N   M A R K", 122, 69, 14)
	_text("山 痕", 60, 160, 70)
	_text("每一座山，都有自己的抵达方式。", 286, 149, 22, MUTED)
	_text("重 心 联 动  /  0.3.2", w - 246, 69, 14, GOLD)
	_text("01  选择你的下一座山", 64, 204, 16, GOLD)
	var card_w: float = (w - 160.0) / 3.0
	for i: int in range(3):
		var x: float = 64.0 + i * (card_w + 16.0)
		var selected: bool = game.route_index == i
		var unlocked: bool = game.route_unlocked(i)
		_panel(Rect2(x, 224, card_w, 221), 0.91 if selected else 0.66)
		if selected:
			draw_rect(Rect2(x, 224, card_w, 3), GOLD)
		_text("0%d" % (i + 1), x + 20, 256, 14, GOLD if selected else MUTED)
		_mountain(Vector2(x + card_w - 112, 269), 0.83, MINT if i == 0 else (MUTED if i == 1 else PAPER))
		_text(ROUTE_LABELS[i], x + 20, 301, 29, PAPER if unlocked else MUTED)
		_text(ROUTE_MOODS[i], x + 20, 333, 15, GOLD if selected else MUTED)
		_text(ROUTE_NOTES[i], x + 20, 362, 13, MUTED)
	_text("02  选择攀登方式", 64, 483, 16, GOLD)
	var desc: String = "自由观察、锚点续攀。沿途探索分岔，留下第一次登顶的记录。"
	if game.play_style == "challenge":
		desc = "短距离专项练习。每一段都有具体目标，跌落后可就近重试。"
	elif game.play_style == "extreme":
		desc = "更少的保护与补给，完整攀登并刷新个人纪录。每一次出手都更重要。"
	_text(desc, 64, 582, 16, MUTED)
	if game.play_style == "challenge":
		_text(game.challenge_goal_text(), 64, 684, 16, MINT)
	else:
		var info: Dictionary = game.route_info()
		_text(str(info.get("subtitle", "")), 64, 628, 23)
		_text("选择支撑脚 · 观察岩面 · 把握出手时机", 64, 662, 15, MUTED)
	_rule(64, h - 183, w - 128)
	_text("戴上耳机，听见山的呼吸。", 64, h - 42, 14, MUTED)
	_text("所有旅程与纪念都保存在本机", w - 315, h - 42, 14, MUTED)

func _draw_journal(w: float, h: float) -> void:
	draw_rect(Rect2(0, 0, w, h), Color(0.025, 0.065, 0.08, 0.91))
	_panel(Rect2(64, 54, w - 128, h - 108), 0.82)
	_text("登 山 日 志", 96, 128, 38)
	_text("走过的路，会留下痕迹。", 98, 168, 17, MUTED)
	_rule(96, 194, w - 192)
	var lines: Array[String] = _journal_rows(w - 196)
	var per_page: int = maxi(1, int((h - 360) / 33))
	var pages: int = maxi(1, ceili(float(lines.size()) / per_page))
	journal_page = clampi(journal_page, 0, pages - 1)
	if lines.is_empty():
		_text("第一座山，正在等你出发。", 98, 254, 22, MUTED)
	for i: int in range(per_page):
		var line_index: int = journal_page * per_page + i
		if line_index >= lines.size():
			break
		_text(lines[line_index], 98, 240 + i * 33, 17, GOLD if lines[line_index].begins_with("【") else PAPER)
	_text("%d / %d" % [journal_page + 1, pages], 98, h - 105, 16, MUTED)
func _draw_game(w: float, h: float) -> void:
	# Top-left expedition card.
	_panel(Rect2(36, 32, 310, 107), 0.68)
	_mountain(Vector2(55, 58), 0.38, PAPER)
	_text("山 痕  /  " + str(game.active_route.get("name", ROUTE_LABELS[game.route_index])), 98, 67, 13, MUTED)
	_text(game.CHAPTERS[mini(game.chapter, 4)], 55, 111, 20)
	var climbed: float = maxf(0.0, float(game.climber.get_reach_origin().y) - 1.0)
	_panel(Rect2(w - 230, 32, 194, 107), 0.68)
	_text("垂直高度", w - 211, 62, 13, MUTED)
	_text("%04.1f" % climbed, w - 213, 108, 38)
	_text("/ %s m" % str(game.route_height), w - 112, 106, 15, MUTED)
	# A tiny vertical route diagram.
	var rx: float = w - 59
	var top: float = h * 0.28
	var bottom: float = h * 0.72
	draw_line(Vector2(rx, top), Vector2(rx, bottom), Color(0.9, 0.9, 0.8, 0.26), 2.0, true)
	var prog: float = clampf(climbed / maxf(1.0, game.route_height), 0.0, 1.0)
	draw_line(Vector2(rx, bottom), Vector2(rx, lerpf(bottom, top, prog)), GOLD, 2.0, true)
	for i: int in range(5):
		var y: float = lerpf(bottom, top, float(i) / 4.0)
		draw_circle(Vector2(rx, y), 3.0, GOLD if climbed >= float(i) * game.route_height / 4.0 else MUTED)
		draw_arc(Vector2(rx, y), 7.0, 0, TAU, 20, Color(0.9, 0.9, 0.8, 0.25), 1.0, true)
	draw_circle(Vector2(rx, lerpf(bottom, top, prog)), 5.0, PAPER)
	_text("顶", rx - 8, top - 22, 14, PAPER)
	_text("%02d%%" % int(prog * 100), rx - 20, bottom + 33, 13, MUTED)
	if game.current_rest and game.readable.size() > 1 and game.play_style != "challenge":
		_draw_route_sketch(w)
	# Candidates remain visible while the player shifts into actual reach.
	if game.mode == "playing":
		if game.preview_id >= 0 and game.camera_reading:
			var preview_info: Dictionary = game.hold_reach_info(game.preview_id)
			var shoulder: Vector3 = preview_info.shoulder
			var preview_pos: Vector3 = preview_info.target
			if not game.camera.is_position_behind(preview_pos) and not game.camera.is_position_behind(shoulder):
				var shoulder_screen: Vector2 = game.camera.unproject_position(shoulder)
				var hold_screen: Vector2 = game.camera.unproject_position(preview_pos)
				var line_color: Color = MINT if bool(preview_info.reachable) else GOLD
				draw_line(shoulder_screen, hold_screen, Color(line_color, 0.58), 2.0, true)
				draw_circle(shoulder_screen, 4.0, Color(line_color, 0.80))
				_wrapped(game.balance_hint_for_hold(game.preview_id), clampf(shoulder_screen.x + 12.0, 25.0, w - 310.0), shoulder_screen.y - 10.0, 280.0, 12, 18, line_color)
		for id: int in game.readable:
			var hold: Dictionary = game._hold(id)
			var reach_info: Dictionary = game.hold_reach_info(id)
			var in_reach: bool = game.reachable.has(id)
			var pos: Vector3 = hold.position
			if game.camera.is_position_behind(pos):
				continue
			var p: Vector2 = game.camera.unproject_position(pos)
			if p.y < 150 or p.y > h - 160 or p.x < 25 or p.x > w - 110:
				continue
			var hover: bool = id == game.hovered_id
			var selected: bool = game.grip_active and id == game.grip_id
			var preview: bool = id == game.preview_id
			var branch: String = str(hold.get("branch", "main"))
			var branch_color: Color = MINT if branch == "safe" else (Color("f0a06a") if branch == "shortcut" else PAPER)
			var color: Color = MINT if in_reach else GOLD
			var rad: float = 24.0 if selected else (22.0 if hover else 15.0)
			draw_circle(p, rad + 3, Color(0.025, 0.08, 0.08, 0.24))
			draw_arc(p, rad, game.clock_time * 0.15, game.clock_time * 0.15 + TAU * 0.82, 42, color, 2.0 if hover else 1.3, true)
			draw_circle(p, 3, color)
			if preview and not hover and not selected:
				_text("当前可达" if in_reach else "移重心后可达", p.x + 23, p.y - 16, 13, color)
			var label_y: float = p.y + 6
			if branch in ["safe", "shortcut"]:
				_text("绕行" if branch == "safe" else "捷径", p.x + 23, label_y, 13, branch_color)
				label_y += 21
			if bool(hold.rest):
				_text("休息" if not bool(hold.checkpoint) else "锚点", p.x + 23, label_y, 13, GOLD)
				label_y += 21
			var collectible: String = str(hold.get("collectible", ""))
			if not collectible.is_empty():
				var collected: bool = game.save_data.get("collections", {}).has(collectible)
				_text("足迹已记录" if collected else "◇ 山路记录", p.x + 23, label_y, 12, MUTED if collected else GOLD)
			if hover:
				var hover_x: float = clampf(p.x + 29.0, 25.0, w - 300.0)
				var reach_status: String = "当前可达" if in_reach else "先移重心，再出手"
				if not bool(reach_info.support_ok):
					reach_status = "先按 Q / E 选择支撑脚"
				var effort: float = game.hold_effort(id, int(reach_info.hand), 0.65)
				_text(reach_status + " · 按住鼠标准备", hover_x, p.y - 31, 13, color)
				_text("预计消耗 %.1f 握力" % effort, hover_x, p.y - 10, 12, MUTED)
		if not game.climber.moving:
			_draw_foot_labels(w, h)
	# Bottom-left grip meter, modelled after a field instrument.
	_panel(Rect2(36, h - 172, 310, 113), 0.78)
	var stamina: float = game.climber.stamina
	var color: Color = MINT if stamina > 40 else GOLD
	if stamina < 22:
		color = Color("ee896e")
	if game.current_rest and not game.climber.moving and not game.grip_active:
		color = MINT
		if game.rest_feedback_time > 0.0:
			var glow: float = minf(1.0, game.rest_feedback_time) * (0.35 + 0.15 * sin(game.clock_time * 4.0))
			draw_rect(Rect2(36, h - 172, 310, 113), Color(MINT, glow), false, 2.0, true)
	_text("握 力", 56, h - 138, 15, MUTED)
	_text("挑战禁用镁粉" if game.play_style == "challenge" and game.challenge_index == 1 else "镁粉 %d / %d" % [game.chalk_charges, game.chalk_capacity()], 135, h - 138, 13, GOLD if game.chalk_charges > 0 else MUTED)
	_text("%03d" % int(stamina), 253, h - 134, 25, color)
	for i: int in range(25):
		var filled: bool = float(i) * 4.0 < stamina
		draw_rect(Rect2(56 + i * 10.7, h - 116, 7.5, 13), color if filled else Color(0.8, 0.9, 0.85, 0.13))
	var status: String = "稳住呼吸，寻找下一处岩点"
	if game.grip_active:
		status = "准备中 · 先确认支撑与双区"
	elif game.climber.moving:
		status = "踩稳  ·  蹬腿  ·  伸手"
	elif game.current_rest:
		if game.rest_feedback_time > 0.0:
			var recovered: int = maxi(0, int(stamina - game.rest_feedback_stamina))
			status = "歇稳了  ·  握力 +%d" % recovered if stamina < 99.0 else "缓过来了  ·  握力已恢复"
		else:
			status = "安全休息中  ·  握力正在恢复"
	elif stamina < 30:
		status = "握力告急  ·  空格使用镁粉"
	_text(status, 56, h - 79, 13, color)
	_panel(Rect2(360, h - 119, w - 396, 83), 0.74)
	_text("先选支撑脚 → A / D 移重心 → 按住鼠标，双区就绪后蹬腿伸手", 375, h - 81, 15, PAPER)
	_text("W 观察 · 中键 / Z X 读线 · Q / E 选脚 · 空格 镁粉 · R 返回 · Esc 暂停", 375, h - 52, 13, MUTED)
	if game.play_style != "journey":
		_text(game.time_string(game.elapsed), w - 128, 168, 21, PAPER)
	_draw_support_card()
	var weather: String = "风力 %.0f%%" % (game.wind_strength * 100.0)
	if game.chalk_protection > 0.0:
		weather += "  ·  防滑 %.0f 秒" % game.chalk_protection
	_text(weather, 55, 440, 13, GOLD)
	if game.play_style == "challenge":
		_panel(Rect2(36, 468, 310, 85), 0.75)
		_wrapped(game.challenge_goal_text(), 55, 496, 270, 13, 21, GOLD)
	if game.grip_active:
		_draw_grip_controls(w, h)
	elif game.mode == "playing" and not game.climber.moving:
		_panel(Rect2(370, h - 197, w - 406, 58), 0.56)
		var hint: String = "W 标记目标；中键 / Z X 读线。青圈当前可达，金圈先按 A / D 移重心。"
		if game.current_rest:
			hint = "在休息岩台恢复握力。选好路线，再按住鼠标准备下一步。"
		if game.slip_streak > 0:
			hint = "连续失手 %d / 3 · 稳住重心再松手，第三次将触发安全绳。" % game.slip_streak
		if game.preview_id >= 0 and game.camera_reading:
			hint = "%s · 辅助线从推荐手肩膀连向岩点；A / D 方向始终按岩壁左右。" % game.balance_hint_for_hold(game.preview_id)
		_wrapped(hint, 389, h - 174, w - 444, 14, 21, GOLD if game.slip_streak > 0 else MUTED)
	_draw_toast(w)

func _draw_support_card() -> void:
	_panel(Rect2(36, 153, 310, 302), 0.78)
	_text("支撑脚  /  先踩稳，再发力", 55, 178, 13, GOLD)
	var support: int = int(game.selected_support)
	for i: int in range(2):
		var left: float = 55.0 + float(i) * 140.0
		var selected: bool = support == i
		var accent: Color = MINT if selected else MUTED
		draw_rect(Rect2(left, 189, 132, 59), Color(MINT, 0.17) if selected else Color(MUTED, 0.05))
		draw_rect(Rect2(left, 189, 132, 59), Color(accent, 0.82 if selected else 0.24), false, 1.5)
		_text("Q" if i == 0 else "E", left + 11, 224, 26, accent)
		_text("左脚" if i == 0 else "右脚", left + 47, 214, 17, accent)
		_text("支撑中" if selected else ("待选" if support < 0 else "可移动"), left + 47, 237, 12, accent)
	var support_text: String = "自动落脚 · 按 Q / E 指定支撑脚"
	if support >= 0:
		support_text = "左脚踩稳 · 右脚可移动" if support == 0 else "右脚踩稳 · 左脚可移动"
	_text(support_text, 55, 273, 14, MINT if support >= 0 else MUTED)
	var motion: String = "踩稳支撑脚，再移重心"
	if game.climber.has_method("get_motion_name"):
		motion = str(game.climber.call("get_motion_name"))
	_wrapped("当前动作  ·  " + motion, 55, 300, 271, 14, 20, PAPER)
	_rule(55, 329, 272)
	_text("岩面观察", 55, 351, 12, MUTED)
	_wrapped(game.terrain_hint(), 55, 375, 271, 14, 21, PAPER)

func _draw_foot_labels(w: float, h: float) -> void:
	if not game.climber.has_method("get_foot_position"):
		return
	var feet: Array[Vector2] = []
	for i: int in range(2):
		var foot: Vector3 = game.climber.call("get_foot_position", i)
		if game.camera.is_position_behind(foot):
			return
		feet.append(game.camera.unproject_position(foot))
	for i: int in range(2):
		var selected: bool = int(game.selected_support) == i
		var label: String = ("Q 左脚" if i == 0 else "E 右脚") + (" · 支撑" if selected else "")
		var text_width: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		var screen_left: bool = feet[i].x <= feet[1 - i].x
		var x: float = feet[i].x - text_width - 25.0 if screen_left else feet[i].x + 25.0
		var y: float = feet[i].y + 13.0
		var rect: Rect2 = Rect2(x - 6, y - 15, text_width + 12, 23)
		if rect.position.x < 25 or rect.end.x > w - 110 or rect.position.y < 150 or rect.end.y > h - 206:
			continue
		if rect.intersects(Rect2(36, 153, 310, 302)):
			continue
		if game.grip_active:
			var panel_width: float = minf(490.0, w - 410.0)
			if rect.intersects(Rect2(w - panel_width - 130.0, h - 380.0, panel_width, 232)):
				continue
		var accent: Color = MINT if selected else MUTED
		draw_line(feet[i] + Vector2(0, 3), Vector2(rect.end.x if screen_left else rect.position.x, y - 4), Color(accent, 0.58), 1.0, true)
		_panel(rect, 0.78)
		_text(label, x, y + 1, 12, accent)

func _branch_path(first: int) -> Array[Dictionary]:
	var path: Array[Dictionary] = []
	var next_id: int = first
	var seen: Dictionary = {}
	for _i: int in range(64):
		if seen.has(next_id):
			break
		seen[next_id] = true
		var point: Dictionary = game._hold(next_id)
		path.append(point)
		if str(point.get("branch", "main")) == "main":
			break
		var links: Array = point.get("links", [])
		if links.is_empty():
			break
		next_id = int(links[0])
	return path

func _draw_route_sketch(w: float) -> void:
	var hub: Dictionary = game._hold(game.climber.current_hold_id)
	var links: Array = hub.get("links", [])
	if links.size() < 2:
		return
	var left: float = w - 366
	var top: float = 178
	_panel(Rect2(left, top, 264, 235), 0.88)
	_text("下一段 · 在这里选择", left + 16, top + 27, 14, PAPER)
	var start: Vector2 = Vector2(left + 132, top + 156)
	var finish: Vector2 = Vector2(left + 132, top + 54)
	for first in links:
		var path: Array[Dictionary] = _branch_path(int(first))
		if path.is_empty():
			continue
		var safe: bool = str(path[0].get("branch", "")) == "safe"
		var color: Color = MINT if safe else Color("f0a06a")
		var previous: Vector2 = start
		for i: int in range(path.size()):
			var t: float = float(i + 1) / float(path.size())
			var point: Vector2 = start.lerp(finish, t) + Vector2(sin(t * PI) * (-73 if safe else 73), 0)
			draw_line(previous, point, Color(color, 0.75), 1.5, true)
			draw_circle(point, 4.0 if bool(path[i].rest) else 2.4, GOLD if bool(path[i].rest) else color)
			previous = point
		_text("绕行" if safe else "捷径", left + (17 if safe else 216), top + 106, 12, color)
		_text(("绕行 %d 步 · 中途可休息" if safe else "捷径 %d 步 · 需连续发力") % path.size(), left + 17, top + (190 if safe else 215), 12, color)
	draw_circle(start, 5, PAPER)
	draw_circle(finish, 5, GOLD)
	_text("汇合", finish.x + 13, finish.y + 5, 12, GOLD)
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
	var top: float = h - 380.0
	var ready: bool = game.grip_ready()
	var power_ready: bool = absf(game.grip_power - game.grip_target) <= game.grip_window
	var reach_ready: bool = game.grip_reach_ready()
	var balance_ready: bool = absf(game.balance - game.balance_target) <= game.balance_window and reach_ready
	var remaining: float = maxf(0.0, 4.5 - game.grip_time)
	_panel(Rect2(left, top, panel_width, 232), 0.93)
	var hand: String = "左手" if game.grip_hand == 0 else "右手"
	var grip_hold: Dictionary = game._hold(game.grip_id)
	var foot: int = int(grip_hold.get("support", -1))
	var heading: String = "双区就绪 · 现在松开" if ready else hand + " · 稳住，等待出手"
	if foot >= 0 and game.selected_support != foot:
		heading = "先按 " + ("Q 选左脚支撑" if foot == 0 else "E 选右脚支撑")
	elif not reach_ready:
		heading = "还够不到 · 先按 A / D 移重心"
	elif str(grip_hold.get("kind", "")) == "wind" and game.wind_strength >= 0.72:
		heading = "阵风正强 · 等待风弱"
	_text(heading, left + 20, top + 28, 19, MINT if ready else PAPER)
	_text("%.1f 秒" % remaining, left + panel_width - 82, top + 27, 15, Color("ee896e") if remaining < 1.0 else MUTED)
	_rule(left + 20, top + 40, panel_width - 40, Color(MINT if ready else MUTED, 0.2))
	_text("蓄力  /  等待白针进入绿区", left + 20, top + 62, 13, MUTED)
	_text("已对准" if power_ready else "等待时机", left + panel_width - 88, top + 62, 13, MINT if power_ready else GOLD)
	_skill_bar(Rect2(left + 20, top + 76, panel_width - 40, 13), game.grip_power, game.grip_target, game.grip_window, power_ready)
	_text("重心  /  按住 A 左移 · D 右移", left + 20, top + 116, 13, MUTED)
	_text("已对准" if balance_ready else ("调整重心" if reach_ready else "尚未可达"), left + panel_width - 88, top + 116, 13, MINT if balance_ready else GOLD)
	_skill_bar(Rect2(left + 20, top + 130, panel_width - 40, 13), (game.balance + 1.0) * 0.5, (game.balance_target + 1.0) * 0.5, game.balance_window * 0.5, balance_ready)
	_text("%s · 预计消耗 %.1f 握力" % ["已在一步范围内" if reach_ready else "身体移近后才能出手", game.hold_effort(game.grip_id, game.grip_hand, 0.65)], left + 20, top + 172, 13, MINT if reach_ready else GOLD)
	_text("松开%s键抓牢 · 可达且双区都要对准" % ("左" if game.grip_hand == 0 else "右"), left + 20, top + 211, 13, MINT if ready else PAPER)
	if game.slip_streak > 0:
		_text("失手 %d / 3" % game.slip_streak, left + panel_width - 92, top + 211, 12, GOLD)

func _draw_fall(w: float, h: float) -> void:
	var fade: float = clampf(game.fall_time / 0.3, 0.0, 1.0)
	draw_rect(Rect2(0, 0, w, h), Color(0.025, 0.045, 0.055, 0.76 * fade))
	var cx: float = w * 0.5
	var cy: float = h * 0.5
	_panel(Rect2(cx - 330, cy - 225, 660, 440), 0.97)
	_center("安 全 绳 保 护", cx, cy - 169, 15, GOLD)
	_center(game.fall_title, cx, cy - 102, 38)
	_center_wrapped(game.fall_reason, cx, cy - 65, 550, 18, 24, MUTED)
	_rule(cx - 270, cy - 24, 540)
	if game.play_style == "challenge":
		_center("这段练习将从本段起点重新开始。", cx, cy + 22, 18)
	elif game.checkpoint == 0:
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
	if game.summit_time < 4.0:
		_center("此刻，先听一听山顶的风。", w * 0.5, h - 67, 18, PAPER)
		return
	var fade: float = clampf((game.summit_time - 4.0) / 1.2, 0.0, 1.0)
	draw_polygon(PackedVector2Array([Vector2(0,42), Vector2(850,42), Vector2(850,h-42), Vector2(0,h-42)]), PackedColorArray([Color(0.025,0.065,0.075,fade * 0.97), Color(0.025,0.065,0.075,0), Color(0.025,0.065,0.075,0), Color(0.025,0.065,0.075,fade * 0.97)]))
	_text("A S C E N T   C O M P L E T E", 72, 126, 16, Color(GOLD, fade))
	_text(game.result_title if not game.result_title.is_empty() else "山在脚下。", 68, 218, 48, Color(PAPER, fade))
	_wrapped(game.result_detail if not game.result_detail.is_empty() else "而你，比出发时更高了一点。", 74, 257, 600, 18, 25, Color(PAPER, fade))
	_rule(74, 300, 410, Color(GOLD, fade * 0.4))
	_text(str(game.active_route.get("name", ROUTE_LABELS[game.route_index])), 74, 343, 28, Color(PAPER, fade))
	_text(STYLE_NAMES[STYLE_KEYS.find(game.play_style)] + "  ·  %s 米攀登" % str(game.route_height), 74, 376, 16, Color(MUTED, fade))
	_text("攀登用时", 74, 425, 14, Color(MUTED, fade))
	_text(game.time_string(game.elapsed), 74, 468, 32, Color(PAPER, fade))
	_text("落手次数", 230, 425, 14, Color(MUTED, fade))
	_text(str(game.climber.total_moves), 230, 468, 32, Color(PAPER, fade))
	_text("绳索保护", 360, 425, 14, Color(MUTED, fade))
	_text(str(game.falls), 360, 468, 32, Color(PAPER, fade))
	_panel(Rect2(74, 500, 470, 137), fade * 0.67)
	_text("此 行 留 痕", 96, 532, 14, Color(GOLD, fade))
	var badges: String = ""
	for i: int in range(mini(3, game.earned_badges.size())):
		badges += ("  ·  " if i > 0 else "") + str(game.earned_badges[i])
	if badges.is_empty():
		badges = "不止一次出发，终于抵达。"
	_text(badges, 96, 569, 17, Color(PAPER, fade))
	_text("完整成绩与收藏已写入登山日志", 96, 607, 14, Color(MUTED, fade))
	var safe_count: int = 0
	var shortcut_count: int = 0
	for record: String in game.run_collections:
		if record.ends_with("_safe"):
			safe_count += 1
		elif record.ends_with("_shortcut"):
			shortcut_count += 1
	_text("登顶日期  ·  " + Time.get_date_string_from_system(), 74, 670, 15, Color(PAPER, fade))
	_text("沿途足迹  ·  绕行 %d 处  /  捷径 %d 处" % [safe_count, shortcut_count], 74, 701, 15, Color(MUTED, fade))
	if not game.postcard_path.is_empty():
		_text("纪念卡已保存至游戏目录 .runtime/postcards", 74, 732, 14, Color(MINT, fade))
	_text("愿你记得，自己走过的每一步。", 74, h - 99, 17, Color(PAPER, fade))
func _draw_help(w: float, h: float) -> void:
	draw_rect(Rect2(0, 0, w, h), Color(0.02, 0.05, 0.06, 0.94))
	var left: float = w * 0.5 - 390
	_text("把下一步，交给自己。", left, 146, 39)
	_text("攀登手册  /  FIELD NOTES", left, 186, 15, GOLD)
	_rule(left, 215, 780)
	var rows: Array = [
		["01", "读线，找到下一步", "W 标记目标；中键 / Z X 转镜头。青圈当前可达，金圈需移重心。"],
		["02", "先选支撑脚，再移重心", "Q / E 选左 / 右脚踩稳；A / D 移近目标，侧栏和脚边标签显示支撑脚。"],
		["03", "蹬腿伸手，双区就绪再松手", "左 / 右键选手；同侧手脚向侧上方可折膝侧伸，正上方高点用屈膝高踩。"],
		["04", "把握 4.5 秒", "超时或未对准会失手并扣握力；连续三次失手由安全绳保护。"],
		["05", "观察岩面与天气", "小岩点要连贯通过；湿壁可用空格镁粉防滑，阵风时等待风弱。"],
		["06", "把路留在日志里", "金色岩点恢复握力；R 返回锚点。探索分支与观景点，抵达山顶。"]
	]
	for i: int in range(rows.size()):
		var y: float = 264 + i * 75
		_text(rows[i][0], left, y, 20, GOLD)
		_text(rows[i][1], left + 59, y, 21)
		_wrapped(rows[i][2], left + 59, y + 28, 721, 15, 21, MUTED)
	_text("Esc 暂停   /   M 声音   /   F11 全屏     ·     进度保存在游戏目录", left, 748, 14, MUTED)

func _button(label: String, rect: Rect2, callback: Callable, primary: bool = false, locked: bool = false) -> void:
	var button: Button = Button.new()
	button.text = label
	button.disabled = locked
	button.position = rect.position
	button.size = rect.size
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font", font)
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", INK if primary else PAPER)
	button.add_theme_color_override("font_hover_color", INK if primary else GOLD)
	button.add_theme_color_override("font_pressed_color", INK)
	button.add_theme_color_override("font_disabled_color", Color(MUTED, 0.55))
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
	button.add_theme_stylebox_override("disabled", normal)
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
			_button("回到本段起点，再试一次" if game.play_style == "challenge" else ("回到山脚，再试一次" if game.checkpoint == 0 else "回到锚点，继续攀登"), Rect2(w * 0.5 - 220, h * 0.5 + 103, 440, 55), game.retry_after_fall, true)
		"menu":
			var card_w: float = (w - 160.0) / 3.0
			for i: int in range(3):
				var route_id: int = i
				var unlocked: bool = game.route_unlocked(i)
				var label: String = "已选路线  ✓" if game.route_index == i else "选择路线"
				if not unlocked:
					label = "登顶前一座山后解锁"
				_button(label, Rect2(84 + i * (card_w + 16), 389, card_w - 40, 38), func(): game.select_route(route_id), game.route_index == i, not unlocked)
			for i: int in range(3):
				var style: String = STYLE_KEYS[i]
				var locked: bool = style == "extreme" and not game.extreme_unlocked()
				var label: String = STYLE_NAMES[i] + (" · 登顶后解锁" if locked else "")
				_button(label, Rect2(64 + i * (card_w + 16), 504, card_w, 48), func(): game.select_style(style), game.play_style == style, locked)
			if game.play_style == "challenge":
				for i: int in range(3):
					var challenge_id: int = i
					_button(CHALLENGE_NAMES[i], Rect2(64 + i * 210, 609, 194, 43), func(): game.select_challenge(challenge_id), game.challenge_index == i)
			_button("开始攀登   ↗", Rect2(64, h - 148, 220, 54), func(): game.start_climb(false), true)
			_button("继续上次旅程", Rect2(296, h - 148, 190, 54), game.continue_journey, false, not bool(game.save_data.get("in_progress", false)))
			_button("攀登手册", Rect2(498, h - 148, 110, 54), game.toggle_help)
			_button("登山日志", Rect2(620, h - 148, 110, 54), game.open_journal)
			_button(["落日橙", "松林绿", "冰川蓝"][game.outfit_index] + " · 换装", Rect2(742, h - 148, 160, 54), game.cycle_outfit)
			_button("声音 " + ("关" if game.muted else "开"), Rect2(914, h - 148, 100, 54), game.toggle_audio)
			_button("离开", Rect2(1026, h - 148, 82, 54), game.quit_game)
		"journal":
			var per_page: int = maxi(1, int((h - 360) / 33))
			var pages: int = maxi(1, ceili(float(_journal_rows(w - 196).size()) / per_page))
			_button("上一页", Rect2(w * 0.5 - 150, h - 145, 130, 48), func(): journal_page = maxi(0, journal_page - 1); refresh_buttons(), false, journal_page <= 0)
			_button("下一页", Rect2(w * 0.5, h - 145, 130, 48), func(): journal_page = mini(pages - 1, journal_page + 1); refresh_buttons(), false, journal_page >= pages - 1)
			_button("返回", Rect2(w - 280, h - 145, 182, 48), game.close_journal, true)
		"paused":
			_button("继续攀登   ↗", Rect2(w * 0.5 - 166, h * 0.5 - 39, 332, 53), game.toggle_pause, true)
			_button("攀登手册", Rect2(w * 0.5 - 166, h * 0.5 + 31, 158, 47), game.toggle_help)
			_button("声音  " + ("关" if game.muted else "开"), Rect2(w * 0.5 + 8, h * 0.5 + 31, 158, 47), game.toggle_audio)
			_button("保存并返回群山" if game.play_style == "journey" else "返回群山", Rect2(w * 0.5 - 166, h * 0.5 + 96, 332, 47), game.return_menu)
		"summit":
			if game.summit_time < 4.0:
				return
			_button("保存登顶纪念卡", Rect2(w - 306, h - 321, 234, 48), game.export_postcard, true)
			_button("打开纪念卡目录", Rect2(w - 306, h - 258, 234, 48), game.open_postcards)
			_button("再攀一次   ↗", Rect2(w - 306, h - 195, 234, 48), func(): game.start_climb(false))
			_button("返回群山", Rect2(w - 306, h - 132, 234, 48), game.return_menu)

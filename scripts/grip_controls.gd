extends Control
## Direct mouse-pull aim, predicted contact and body stability in both UI modes.
const PAPER: Color = Color("f1e7d2")
const MUTED: Color = Color("a9beb9")
const GOLD: Color = Color("ebc68d")
const MINT: Color = Color("a9ddc4")
var game: Node3D
var font: Font = preload("res://assets/fonts/ui.ttc")

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	hide()

func _text(content: String, x: float, y: float, px: int = 20, color: Color = PAPER) -> void:
	draw_string(font, Vector2(x + 1, y + 1), content, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(0.025, 0.06, 0.07, color.a * 0.4))
	draw_string(font, Vector2(x, y), content, HORIZONTAL_ALIGNMENT_LEFT, -1, px, color)

func _rule(x: float, y: float, width: float, color: Color = Color(0.9, 0.9, 0.8, 0.2)) -> void:
	draw_line(Vector2(x, y), Vector2(x + width, y), color, 1.0, true)

func _panel(rect: Rect2, alpha: float = 0.88) -> void:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.052, 0.10, 0.115, alpha)
	style.border_color = Color(0.85, 0.85, 0.73, 0.17)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	draw_style_box(style, rect)

func _force_bar(rect: Rect2, value: float, desired: float, accurate: bool) -> void:
	draw_rect(rect, Color(0.70, 0.83, 0.81, 0.12))
	var fill: Rect2 = Rect2(rect.position, Vector2(rect.size.x * clampf(value, 0.0, 1.0), rect.size.y))
	draw_rect(fill, Color(MINT if accurate else GOLD, 0.76))
	var desired_x: float = rect.position.x + rect.size.x * clampf(desired, 0.0, 1.0)
	draw_line(Vector2(desired_x, rect.position.y - 3), Vector2(desired_x, rect.end.y + 3), PAPER, 2.0, true)

func _draw_drag_feedback(aim: Dictionary, ready: bool) -> void:
	if not bool(aim.get("active", false)):
		return
	var origin: Vector2 = aim.get("origin_screen", Vector2.ZERO)
	if aim.has("shoulder"):
		origin = game.camera.unproject_position(Vector3(aim.shoulder))
	var target: Vector2 = aim.get("target_screen", Vector2.ZERO)
	var predicted: Vector2 = aim.get("predicted_screen", Vector2.ZERO)
	var anchor: Vector2 = aim.get("drag_anchor", target)
	var cursor: Vector2 = aim.get("drag_cursor", anchor)
	var assisted: bool = bool(aim.get("assisted", false))
	var color: Color = MINT if ready else GOLD
	if float(aim.get("miss_distance", 0.0)) > float(aim.get("tolerance", 0.1)) * 2.0:
		color = Color("ee896e")
	# The pulled string and shot direction have opposite directions. Neither
	# endpoint is adjusted here: the main controller supplies the actual geometry.
	var ideal_cursor: Vector2 = anchor - (target - Vector2(aim.get("origin_screen", origin))) / float(game.DRAG_AMPLIFICATION)
	draw_dashed_line(anchor, ideal_cursor, Color(MINT, 0.24), 1.5, 6.0, true)
	for ring in range(3):
		draw_circle(ideal_cursor, 28.0 - float(ring) * 8.0, Color(MINT, 0.025 + float(ring) * 0.015))
	_text("向这边拉", ideal_cursor.x + 23.0, ideal_cursor.y + 18.0, 12, Color(MINT, 0.65))
	draw_line(anchor, cursor, Color(0.025, 0.06, 0.07, 0.85), 5.0, true)
	draw_line(anchor, cursor, Color(GOLD, 0.88), 2.0, true)
	draw_circle(anchor, 3.5, PAPER)
	draw_arc(cursor, 8.0, 0.0, TAU, 32, GOLD, 1.5, true)
	draw_circle(cursor, 2.5, PAPER)
	if origin.distance_to(predicted) > 1.0:
		draw_dashed_line(origin, predicted, Color(color, 0.9), 2.0, 7.0, true)
		var direction: Vector2 = origin.direction_to(predicted)
		var normal: Vector2 = direction.orthogonal()
		var tip: Vector2 = origin.lerp(predicted, 0.63)
		draw_line(tip, tip - direction * 10.0 + normal * 4.0, color, 2.0, true)
		draw_line(tip, tip - direction * 10.0 - normal * 4.0, color, 2.0, true)
	draw_circle(origin, 3.0, Color(color, 0.9))
	var target_world: Vector3 = aim.get("target", Vector3.ZERO)
	var tolerance: float = float(aim.get("tolerance", 0.1))
	var boundary := PackedVector2Array()
	var boundary_right: float = target.x
	# Accuracy is measured in metres on the wall's XY plane. Project that same
	# boundary instead of drawing an approximate circle with a fixed pixel size.
	for i in range(65):
		var angle: float = float(i) * TAU / 64.0
		var edge: Vector3 = target_world + Vector3(cos(angle), sin(angle), 0.0) * tolerance
		var screen: Vector2 = game.camera.unproject_position(edge)
		boundary.append(screen)
		boundary_right = maxf(boundary_right, screen.x)
	draw_polyline(boundary, Color(PAPER, 0.9), 1.5, true)
	_text("目标", maxf(boundary_right + 6.0, target.x + 42.0), target.y - 16.0, 12, PAPER)
	if assisted and aim.has("raw_predicted"):
		var raw: Vector2 = game.camera.unproject_position(Vector3(aim.raw_predicted))
		if raw.distance_to(predicted) > 1.0:
			draw_line(raw, predicted, Color(PAPER, 0.30), 1.0, true)
			draw_circle(raw, 2.5, Color(PAPER, 0.45))
	if target.distance_to(predicted) > 2.0:
		draw_dashed_line(target, predicted, Color(color, 0.5), 1.0, 4.0, true)
	draw_circle(predicted, 6.0, Color(color, 0.12))
	draw_arc(predicted, 7.0, 0.0, TAU, 32, color, 2.0, true)
	draw_line(predicted - Vector2(3.0, 0.0), predicted + Vector2(3.0, 0.0), color, 1.0, true)
	draw_line(predicted - Vector2(0.0, 3.0), predicted + Vector2(0.0, 3.0), color, 1.0, true)
	_text("辅助落点" if assisted else "预计落点", predicted.x + 13.0, predicted.y + 20.0, 12, color)

func _balance_bar(rect: Rect2, value: float, target: float, window: float, stable: bool) -> void:
	draw_rect(rect, Color(0.70, 0.83, 0.81, 0.12))
	var band_left: float = clampf(target - window, 0.0, 1.0)
	var band_right: float = clampf(target + window, 0.0, 1.0)
	var band: Rect2 = Rect2(rect.position + Vector2(rect.size.x * band_left, 0), Vector2(rect.size.x * (band_right - band_left), rect.size.y))
	draw_rect(band, Color(MINT, 0.52 if stable else 0.28))
	draw_rect(band, Color(MINT, 0.85), false, 1.0)
	var target_x: float = rect.position.x + rect.size.x * target
	draw_line(Vector2(target_x, rect.position.y + 2), Vector2(target_x, rect.end.y - 2), Color(MINT, 0.7), 1.0)
	var cursor_x: float = rect.position.x + rect.size.x * clampf(value, 0.0, 1.0)
	var cursor_color: Color = PAPER
	draw_line(Vector2(cursor_x, rect.position.y - 4), Vector2(cursor_x, rect.end.y + 4), cursor_color, 3.0, true)
	draw_colored_polygon(PackedVector2Array([Vector2(cursor_x - 4, rect.position.y - 9), Vector2(cursor_x + 4, rect.position.y - 9), Vector2(cursor_x, rect.position.y - 4)]), cursor_color)

func _draw() -> void:
	if game == null or not game.grip_active or game.mode != "playing" or game.help_open:
		return
	var w: float = size.x
	var h: float = size.y
	var panel_width: float = minf(490.0, w - 410.0)
	var left: float = w - panel_width - 130.0
	var top: float = h - 380.0
	var aim: Dictionary = game.get_drag_aim_info()
	var ready: bool = game.grip_ready()
	_draw_drag_feedback(aim, ready)
	var accurate: bool = bool(aim.get("accurate", false))
	var assisted: bool = bool(aim.get("assisted", false))
	var power: float = float(aim.get("power", game.grip_power))
	var desired_power: float = float(aim.get("required_power", game.grip_target))
	var angle_error: float = absf(rad_to_deg(float(aim.get("angle_error", 0.0))))
	var reach_ready: bool = game.grip_reach_ready()
	var balance_ready: bool = absf(game.balance - game.balance_target) <= game.balance_window and reach_ready
	var remaining: float = maxf(0.0, game.GRIP_HOLD_LIMIT - game.grip_time)
	_panel(Rect2(left, top, panel_width, 232), 0.93)
	var grip_hold: Dictionary = game._hold(game.grip_id)
	var foot: int = int(grip_hold.get("support", -1))
	var heading: String = ("辅助抓稳 · 松开" if assisted else "抓稳了 · 松开") if ready else "向后拉，绿色时松手"
	if accurate and not balance_ready:
		heading = "身体正在找稳 · 等圈变绿"
	elif not accurate and angle_error > 5.0:
		heading = "顺着淡色线，向后拉"
	elif not accurate:
		heading = "再向后拉一点，等圈变绿" if power < desired_power else "回收一点，等圈变绿"
	if foot >= 0 and game.selected_support != foot:
		heading = "先按 " + ("Q 选左脚支撑" if foot == 0 else "E 选右脚支撑")
	elif not reach_ready:
		heading = "身体正在找稳 · A / D 可微调"
	elif str(grip_hold.get("kind", "")) == "wind" and game.wind_strength >= 0.72:
		heading = "阵风正强 · 等待风弱"
	_text(heading, left + 20, top + 28, 19, MINT if ready else PAPER)
	_text("悬挂余时 %.1f 秒" % remaining, left + panel_width - 120, top + 27, 13, Color("ee896e") if remaining < 1.0 else MUTED)
	_rule(left + 20, top + 40, panel_width - 40, Color(MINT if ready else MUTED, 0.2))
	_text("回拉力度", left + 20, top + 62, 13, MUTED)
	_text("%d%%" % roundi(power * 100.0), left + panel_width - 78, top + 62, 13, MINT if ready else GOLD)
	_force_bar(Rect2(left + 20, top + 76, panel_width - 40, 13), power, desired_power, ready)
	_text("顺着淡线回拉，落点变绿就可以松手", left + 20, top + 103, 11, MUTED)
	_text("身体  /  自动找稳 · A/D 微调", left + 20, top + 125, 13, MUTED)
	_text("已站稳" if balance_ready else "找稳中", left + panel_width - 88, top + 125, 13, MINT if balance_ready else GOLD)
	_balance_bar(Rect2(left + 20, top + 139, panel_width - 40, 13), (game.balance + 1.0) * 0.5, (game.balance_target + 1.0) * 0.5, game.balance_window * 0.5, balance_ready)
	_text("已轻微修正落点 · 浅色小点是原始落点" if assisted else "靠近岩点会辅助抓稳，明显偏离仍会失手", left + 20, top + 172, 12, MINT if ready and assisted else MUTED)
	_text("%s · 预计消耗 %.1f 握力" % ["已在一步范围内" if reach_ready else "身体移近后才能出手", game.hold_effort(game.grip_id, game.grip_hand, 0.65)], left + 20, top + 191, 11, MUTED)
	_text("向后拉 → 绿色时松开%s键" % ("左" if game.grip_hand == 0 else "右"), left + 20, top + 215, 13, MINT if ready else PAPER)
	if game.slip_streak > 0:
		_text("失手 %d / 3" % game.slip_streak, left + panel_width - 92, top + 215, 12, GOLD)


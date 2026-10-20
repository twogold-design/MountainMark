extends RefCounted
## Explicit route edges preserve every crux and give branches real consequences.
const NAMES := ["松风岩脊", "回声峡谷", "云上孤峰"]
const IDS := ["ridge", "canyon", "summit"]
const HEIGHTS := [72.0, 90.0, 108.0]
const SUBTITLES := ["晨光松林 · 选择自己的山路", "瀑布回声 · 横渡与湿壁", "雪岩云海 · 等待风的间隙"]
const DESCRIPTIONS := ["绕行有岩台，直上更费力。沿松林与旧路标寻找山顶。", "先落脚，再移重心。沿峡谷横渡，避开湿滑或用镁粉处理。", "读懂飘带与风声，趁风弱时出手。在云海之上完成最后攀登。"]
const CHALLENGES := ["稳稳向上", "横渡练习", "湿壁考验"]

static func info(index: int) -> Dictionary:
	index = clampi(index, 0, 2)
	return {"id": IDS[index], "name": NAMES[index], "height": HEIGHTS[index], "subtitle": SUBTITLES[index], "description": DESCRIPTIONS[index]}

static func _point(holds: Array[Dictionary], p: Vector3, rest: bool = false, anchor: bool = false, kind: String = "normal", branch: String = "main", support: int = -1, collectible: String = "") -> int:
	var id: int = holds.size()
	holds.append({"id": id, "position": p, "rest": rest, "checkpoint": anchor, "kind": kind, "branch": branch, "support": support, "collectible": collectible, "links": []})
	return id

static func _link(holds: Array[Dictionary], from: int, to: int) -> void:
	holds[from].links.append(to)

static func build(index: int, style: String = "journey", challenge: int = 0) -> Dictionary:
	if style == "challenge":
		return _challenge(challenge)
	var route: Dictionary = info(index)
	var holds: Array[Dictionary] = []
	var hub: int = _point(holds, Vector3(0, 1, 0.45), true, true)
	var height: float = float(route.height)
	for section in range(6):
		var start: Vector3 = holds[hub].position
		var end_y: float = 1.0 + (height - 1.0) * float(section + 1) / 6.0
		var split: bool = section in [1, 3, 4]
		var ends: Array[int] = []
		var paths: Array = ["safe", "shortcut"] if split else ["main"]
		for branch: String in paths:
			var steps: int = ceili((end_y - start.y) / (2.15 if branch == "shortcut" else 1.35))
			var previous: int = hub
			for step in range(1, steps):
				var t: float = float(step) / float(steps)
				var offset: float = -2.9 if branch == "safe" else (1.6 if branch == "shortcut" else (2.8 if section % 2 == 0 else -2.8))
				var x: float = sin(t * PI) * offset
				if index == 1 and branch != "shortcut":
					x += sin(t * TAU) * 0.7
				var p := Vector3(x, lerpf(start.y, end_y, t), 0.45)
				var rest: bool = step == steps / 2 and branch != "shortcut"
				var kind: String = "normal"
				if branch == "shortcut":
					kind = "small"
				elif index == 1 and section % 2 == 1:
					kind = "wet"
				elif index == 1:
					kind = "traverse"
				elif index == 2 and section >= 2:
					kind = "wind"
				var support: int = -1
				if kind == "traverse" and not rest:
					support = 0 if p.x > Vector3(holds[previous].position).x else 1
				var collection: String = ""
				if split and step == steps / 2:
					collection = "%s_%d_%s" % [route.id, section, branch]
				var id: int = _point(holds, p, rest, false, "normal" if rest else kind, branch, support, collection)
				holds[id]["section"] = section
				_link(holds, previous, id)
				previous = id
			ends.append(previous)
		var anchor: bool = style != "extreme" or section == 2 or section == 5
		hub = _point(holds, Vector3(0, end_y, 0.45), true, anchor)
		for previous: int in ends:
			_link(holds, previous, hub)
	route["holds"] = holds
	route["style"] = style
	return route

static func _challenge(index: int) -> Dictionary:
	index = clampi(index, 0, 2)
	var route: Dictionary = info(1 if index > 0 else 0)
	route["name"] = CHALLENGES[index]
	route["description"] = ["连续五次精准抓握，再抵达终点。", "不用镁粉，选择支撑脚，完成横渡。", "零跌落通过湿壁；镁粉保护持续 18 秒。"][index]
	var holds: Array[Dictionary] = []
	_point(holds, Vector3(0, 1, 0.45), true, true)
	for i in range(1, 11):
		var x: float = sin(float(i) * PI / 5.0) * (2.8 if index == 1 else 1.3)
		var p := Vector3(x, 1.0 + float(i) * 1.25, 0.45)
		var rest: bool = i == 5 or i == 10
		var kind: String = "traverse" if index == 1 else ("wet" if index == 2 else "normal")
		var foot: int = (0 if x > Vector3(holds[i - 1].position).x else 1) if index == 1 and not rest else -1
		_point(holds, p, rest, false, "normal" if rest else kind, "main", foot)
		_link(holds, i - 1, i)
	route["height"] = 13.5
	route["holds"] = holds
	route["style"] = "challenge"
	return route

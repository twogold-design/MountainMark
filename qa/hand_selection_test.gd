extends SceneTree
var game: Node3D
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func verify(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("FAIL ", label)

func edge(id: int, offset: Vector3) -> void:
	var hold: Dictionary = game.world.holds[id]
	hold.position = game.climber.get_reach_origin() + offset
	hold.support = -1
	hold.kind = "normal"
	hold.rest = false
	hold.checkpoint = false
	game.readable.assign([id])
	game.wind_strength = 0.0

func ready_grip() -> void:
	game.balance = game.balance_target
	game.climber.set_lean(game.balance)
	game._refresh_grip_geometry()
	game.grip_time = 1.0
	game.grip_power = game.grip_target

func release(button: int) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = false
	game._unhandled_input(event)

func run() -> void:
	if "--qa-capture" not in OS.get_cmdline_user_args():
		quit(2)
		return
	root.size = Vector2i(1280,900)
	root.content_scale_size = Vector2i(1280,900)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.sound.set_muted(true)
	game.start_climb(false)
	game.climber.set_process(false)
	var hands: Array[int] = []
	# Repeat the same LEFT mouse button through six real preparations and moves.
	for id in range(1,7):
		edge(id,Vector3(0,1.2,0))
		game._press_mouse_grip(id,MOUSE_BUTTON_LEFT)
		verify(game.grip_active,"Left button prepares a valid grip")
		var hand: int = game.grip_hand
		hands.append(hand)
		if id > 1:
			verify(hand != hands[id-2],"Same mouse button alternates anatomical hands")
		verify(game.grip_button_name() == "左键","Release hint follows input button even for right hand")
		game.select_support(id%2)
		verify(game.grip_hand == hand,"Changing support preserves the prepared hand")
		ready_grip()
		if id == 1 and "--render-hands" in OS.get_cmdline_user_args():
			game._update_camera(1.0)
			game.hud.queue_redraw()
			await process_frame
			await RenderingServer.frame_post_draw
			verify(root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://qa/automatic-hand-ui.png")) == OK,"Rendered input hint capture")
		release(MOUSE_BUTTON_RIGHT)
		verify(game.grip_active and not game.climber.moving,"Other button release cannot commit grip")
		release(MOUSE_BUTTON_LEFT)
		verify(game.climber.moving and game.climber._hand == hand,"Released grip animates the selected hand")
		var initial: Vector3 = game.climber._gloves[hand].position
		game.climber._process(game.climber._move_duration*0.08)
		verify(game.climber._gloves[hand].position.distance_to(initial) > 0.005,"Selected rendered palm leads the near pull")
		game.climber._process(game.climber._move_duration)
		verify(game.climber._gloves[hand].position.distance_to(Vector3(game.world.holds[id].position)+Vector3(0,0,0.025)) < 0.002,"Selected hand reaches actual target")
		verify(game._grip_hand_history == hand,"Only successful move updates hand history")
	# Traverses favor the natural-side hand even if it was used last time.
	for side in [-1,1]:
		edge(7,Vector3(side*1.0,0.4,0))
		var natural: int = 0 if side < 0 else 1
		game._grip_hand_history = natural
		verify(game.recommended_hand(7) == natural,"Sideways target favors natural hand")
	# Right mouse explicitly chooses the alternative, without changing on release.
	edge(7,Vector3(0,1.2,0))
	var recommended: int = game.recommended_hand(7)
	var history: int = game._grip_hand_history
	game._press_mouse_grip(7,MOUSE_BUTTON_RIGHT)
	verify(game.grip_hand == 1-recommended and game.grip_button_name() == "右键","Right button chooses alternative and correct release hint")
	game._cancel_grip()
	verify(game._grip_button == 0 and game._grip_hand_history == history,"Cancellation clears button without advancing hand history")
	release(MOUSE_BUTTON_RIGHT)
	verify(not game.climber.moving,"Stale release after cancellation has no effect")
	game._press_mouse_grip(7,MOUSE_BUTTON_RIGHT)
	var alternate: int = game.grip_hand
	ready_grip()
	release(MOUSE_BUTTON_LEFT)
	verify(game.grip_active,"Left release cannot commit right-button preparation")
	release(MOUSE_BUTTON_RIGHT)
	verify(game.climber.moving and game.climber._hand == alternate,"Right-button override commits the chosen hand")
	game.climber._process(game.climber._move_duration)
	# Find a real edge where only one shoulder can reach at its best stance.
	var found: bool = false
	for x in [0.4,0.6,0.8,1.0,1.2]:
		for y in [2.1,2.15,2.2,2.25,2.3]:
			edge(8,Vector3(x,y,0))
			var left: bool = game.hold_reach_info(8,0).can_adjust
			var right: bool = game.hold_reach_info(8,1).can_adjust
			if left == right:
				continue
			found = true
			var usable: int = 0 if left else 1
			game._grip_hand_history = usable
			verify(game.recommended_hand(8) == usable,"Real reach takes precedence over alternation")
			game._press_mouse_grip(8,MOUSE_BUTTON_RIGHT)
			verify(not game.grip_active,"Manual override cannot force an unreachable hand")
	verify(found,"Reach-limit fixture exercises a single usable hand")
	game._reset_controls()
	verify(game._grip_hand_history == -1 and game._grip_button == 0,"Restart clears hand history and pending input")
	print("HAND_SELECTION_RESULT checks=",checks," failures=",failures.size()," repeated_left_button_hands=",hands)
	game.sound.shutdown()
	game.queue_free()
	await create_timer(0.3).timeout
	quit(0 if failures.is_empty() else 1)

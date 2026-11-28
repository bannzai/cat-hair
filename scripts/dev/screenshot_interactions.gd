extends RefCounted
## 同じ屋敷・立ち位置で、床、上着、ソファに落ちた毛と買取業者を実際に操作した前後を撮る。

const HandAim := preload("res://scripts/dev/hand_aim.gd")


## 入力が届いた瞬間の毛と HUD を残すため、フレームを保存する間だけ屋敷の時間を止める。
static func capture(tree: SceneTree, main: Node3D, snapshot: Callable) -> bool:
	var mouse_mode: Input.MouseMode = Input.get_mouse_mode()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	var ok: bool = await _capture_picking(tree, main, snapshot)
	if ok:
		ok = await _capture_trader(tree, main, snapshot)
	Input.set_mouse_mode(mouse_mode)
	return ok


## カメラが狙う毛を 1 回押し、離した直後までの絵を残す。
static func _capture_picking(tree: SceneTree, main: Node3D, snapshot: Callable) -> bool:
	for surface: StringName in [
		MansionLayout.SURFACE_FLOOR, MansionLayout.SURFACE_SUIT, MansionLayout.SURFACE_SOFA,
	]:
		if not main.get_pluck_popup_text().is_empty():
			await tree.create_timer(main.PLUCK_POPUP_SECONDS).timeout
		if await HandAim.aim_at_first_room_hair(tree, main, surface) < 0:
			push_error("撮影する %s の毛を狙えない" % surface)
			return false
		await tree.process_frame
		await tree.process_frame
		if not await snapshot.call(main, "tmp/screenshot-%s-before.png" % surface):
			return false
		await tap(tree, false)
		if not await snapshot.call(main, "tmp/screenshot-%s-after.png" % surface):
			return false
	return true


## 買取業者の前で、毛の無い空間への入力と、胸を狙った会話の入力を順に撮る。
static func _capture_trader(tree: SceneTree, main: Node3D, snapshot: Callable) -> bool:
	var trader: Vector3 = main.mansion_world.get_trader_position()
	main.player.set_spawn(trader + Vector3(1.2, 0.0, -1.3), 0.0)
	await tree.physics_frame
	await tree.physics_frame
	main.player.look_at_point(main.player.get_camera().global_position + Vector3.UP)
	await tap(tree, false)
	if not await snapshot.call(main, "tmp/screenshot-empty-after.png"):
		return false
	main.player.look_at_point(trader + Vector3.UP * 1.1)
	await tree.process_frame
	await tree.process_frame
	if not await snapshot.call(main, "tmp/screenshot-trader-before.png"):
		return false
	await tap(tree, true)
	var ok: bool = await snapshot.call(main, "tmp/screenshot-trader-after.png")
	if main.tool_shop_panel.visible:
		main.close_tool_shop()
	return ok


## 実際の左クリックまたは E 入力を送り、ゲームが 1 フレームだけ押下を観測できるようにする。
static func tap(tree: SceneTree, talk: bool) -> void:
	for pressed: bool in [true, false]:
		var event: InputEvent
		if talk:
			var key := InputEventKey.new()
			key.physical_keycode = KEY_E
			key.pressed = pressed
			event = key
		else:
			var mouse := InputEventMouseButton.new()
			mouse.button_index = MOUSE_BUTTON_LEFT
			mouse.pressed = pressed
			event = mouse
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await tree.process_frame

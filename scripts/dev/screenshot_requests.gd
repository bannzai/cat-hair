extends RefCounted
## 住人の依頼の場面の撮影 (scripts/dev/screenshot.gd から呼ぶ)。毛の上に出てきた探し物、住人の依頼の一覧の画面、
## 逃げた猫の毛の跡を撮る。

## 依頼の計算
const RequestRulesScript := preload("res://scripts/requests/request_rules.gd")
## 探し物の状態の型
const FoundItemProgressScript := preload("res://scripts/data/found_item_progress.gd")
## 探し物を撮る時に立つ、探し物から部屋の中心へ向かった水平距離 (m)。物と名前の札が画面に収まる距離
const STAND_DISTANCE_M: float = 1.4


## 3 つの場面を撮る。撮れたら空文字、失敗したら最初の失敗の理由を返す
static func capture_all(shooter: SceneTree, main: Node3D) -> String:
	var game_state: Node = main.get_game_state()
	var layout: MansionLayout = game_state.current_layout
	if layout.found_item_spots.is_empty():
		return "屋敷に探し物が無い"
	var spot: MansionLayout.FoundItemSpotDef = layout.found_item_spots[0]
	var item: FoundItemProgress = game_state.requests.find_item(spot.found_item_id)
	var surface: SurfaceHair = game_state.save_data.building_progress.find_surface_hair(
		spot.surface_id
	)
	while item.condition == FoundItemProgressScript.Condition.HIDDEN and surface.total_count() > 0:
		for color_key: Variant in surface.hair_counts.keys():
			if surface.count_for_color(color_key) > 0:
				game_state.pluck_hair(spot.surface_id, color_key)
				break
	if item.condition != FoundItemProgressScript.Condition.FOUND:
		return "探し物が毛の上に出てこない"
	var room: MansionLayout.RoomDef = _room(layout, spot.room_id)
	var toward_center: Vector3 = Vector3(
		room.center.x - spot.position.x, 0.0, room.center.z - spot.position.z
	).normalized()
	var stand: Vector3 = spot.position + toward_center * STAND_DISTANCE_M
	main.player.set_spawn(Vector3(stand.x, room.center.y, stand.z), 0.0)
	await shooter.physics_frame
	main.player.look_at_point(spot.position)
	if not await shooter._capture_frozen(main, "tmp/screenshot-found-item.png"):
		return "毛の上に出てきた探し物を保存できない"
	main.toggle_requests()
	if not main.requests.panel.visible:
		return "住人の依頼の一覧が開かない"
	if not await shooter._capture_frozen(main, "tmp/screenshot-requests.png"):
		return "住人の依頼の一覧を保存できない"
	main.toggle_requests()
	game_state.advance_time(RequestRulesScript.RUNAWAY_START_SECONDS)
	var owner_room: MansionLayout.RoomDef = RequestRulesScript.runaway_owner_room(layout)
	main.player.set_spawn(owner_room.center, 0.0)
	await shooter.physics_frame
	var trail: Array[Vector3] = RequestRulesScript.trail_points(layout)
	if trail.size() < 2 or not main.requests.get_trail_state()["visible"]:
		return "逃げた猫の毛の跡が出ない"
	main.player.look_at_point(trail[mini(3, trail.size() - 1)])
	if not await shooter._capture_frozen(main, "tmp/screenshot-runaway-trail.png"):
		return "逃げた猫の毛の跡を保存できない"
	return ""


## 部屋 room_id の定義
static func _room(layout: MansionLayout, room_id: StringName) -> MansionLayout.RoomDef:
	for room: MansionLayout.RoomDef in layout.rooms:
		if room.room_id == room_id:
			return room
	return layout.rooms[0]

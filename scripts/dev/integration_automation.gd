extends RefCounted
## 猫と掃除ロボットの入力統合テスト (scripts/dev/integration.gd から呼ぶ)。
## メインシーンを動かし、屋敷に猫が 3 匹いて時計で歩くこと、猫が落とした毛と掃除ロボットが取った毛の本数が屋敷の毛の見た目と
## 保存データで一致すること、R キーの画面で掃除ロボットを買って回る順を決められること、ブラシで猫を狙ってブラッシングできることを確かめる。

## 決まった所を順に回る動きの時刻の計算
const RouteClockScript := preload("res://scripts/automation/route_clock.gd")
## 猫の通り道・毛を落とす量・ブラッシングの計算
const CatRulesScript := preload("res://scripts/automation/cat_rules.gd")
## 掃除ロボットの値段・回る順の計算
const RobotRulesScript := preload("res://scripts/automation/robot_rules.gd")
## 手に持って使う道具の定義 (ブラシの id)
const ToolCatalogScript := preload("res://scripts/tools/tool_catalog.gd")
## 状態管理 autoload スクリプト (買う物の種類の定数を使う)
const GameStateScript := preload("res://scripts/state/game_state.gd")
## 猫を狙う時に、猫から立つ位置までの水平距離 (m。手の届く距離より十分短い)
const STAND_DISTANCE_M: float = 1.0

## 検証結果を記録する integration の SceneTree 参照
var _checker: SceneTree = null


## 猫と掃除ロボットの検証をすべて実行する (main はプレイ中のメインシーン。時計は検証の中で進める)
static func run_all(checker: SceneTree, main: Node3D, game_state: Node) -> void:
	var suite: RefCounted = load("res://scripts/dev/integration_automation.gd").new()
	suite._checker = checker
	main.auto_advance_time = false
	main.auto_advance_automation = false
	await suite._verify_cats_walk(main, game_state)
	await suite._verify_hair_sync(main, game_state)
	await suite._verify_robot_panel(main, game_state)
	await suite._verify_robot_cleaning(main, game_state)
	await suite._verify_brush_cat(main, game_state)
	main.auto_advance_automation = false


## 検証結果を integration 本体へ記録する
func _check(cond: bool, label: String) -> void:
	_checker._check(cond, label)


## 屋敷に猫が 3 匹いて、時計を進めると通り道の位置へ動き、プレイ中は時計がフレームごとに進むか
func _verify_cats_walk(main: Node3D, game_state: Node) -> void:
	var automation: AutomationController = main.automation
	var routes: Array[Dictionary] = game_state.automation.get_cat_routes()
	var placed: int = 0
	for route: Dictionary in routes:
		var cat: Node3D = automation.get_cat_node(route["cat_id"])
		if cat != null and cat.is_inside_tree() and cat.visible:
			placed += 1
	_check(routes.size() == 3 and placed == 3, "屋敷に猫が 3 匹いる (置かれた猫: %d)" % placed)
	var seconds_before: float = game_state.automation.get_seconds()
	await _checker.process_frame
	await _checker.process_frame
	_check(
		is_equal_approx(game_state.automation.get_seconds(), seconds_before),
		"時計を止めている間は猫と掃除ロボットの時計が進まない",
	)
	main.auto_advance_automation = true
	for _frame: int in range(10):
		await _checker.process_frame
	main.auto_advance_automation = false
	_check(
		game_state.automation.get_seconds() > seconds_before,
		"屋敷で遊んでいる間は時計がフレームごとに進む (%.3f → %.3f 秒)"
		% [seconds_before, game_state.automation.get_seconds()],
	)
	var route: Dictionary = routes[0]
	var cat_node: Node3D = automation.get_cat_node(route["cat_id"])
	var first_point: Vector3 = cat_node.position
	game_state.automation.advance(float(route["stops"][0]["seconds"]) + RouteClockScript.MOVE_SECONDS)
	await _checker.process_frame
	var expected: Vector3 = RouteClockScript.position_at(route, game_state.automation.get_seconds())
	_check(
		cat_node.position.is_equal_approx(expected) and cat_node.position.distance_to(first_point) > 0.5,
		"時計を進めると %s は通り道の次の所へ歩いて移る (前: %s / 今: %s / 期待: %s)"
		% [route["name"], str(first_point), str(cat_node.position), str(expected)],
	)


## 猫が毛を落とすと、屋敷の毛の見た目 (HairField) の本数と保存データの本数が同じだけ増え、落ちた毛は立ち止まった所の近くにあるか
func _verify_hair_sync(main: Node3D, game_state: Node) -> void:
	var hair_field: Node3D = main.get_node("MansionWorld").get_hair_field()
	var field_before: int = hair_field.get_remaining_count()
	var state_before: int = game_state.get_total_remaining_hairs()
	var changes: Dictionary = game_state.automation.advance(30.0)
	await _checker.process_frame
	var dropped: int = 0
	for drop: Dictionary in changes["drops"]:
		dropped += int(drop["count"])
	_check(
		dropped > 0
		and game_state.get_total_remaining_hairs() == state_before + dropped
		and hair_field.get_remaining_count() == field_before + dropped
		and hair_field.get_remaining_count() == game_state.get_total_remaining_hairs(),
		"猫が 30 秒で落とした毛 %d 本が、屋敷の毛の見た目と保存データの両方に同じ本数だけ増える (見た目: %d / 保存データ: %d)"
		% [dropped, hair_field.get_remaining_count(), game_state.get_total_remaining_hairs()],
	)
	var drop: Dictionary = changes["drops"][0] if dropped > 0 else {}
	var near_stop: int = 0
	if not drop.is_empty():
		var route: Dictionary = {}
		for candidate: Dictionary in game_state.automation.get_cat_routes():
			if candidate["cat_id"] == drop["cat_id"]:
				route = candidate
		var stop: Dictionary = CatRulesScript.stop_on_surface(route, drop["surface_id"])
		var surface_index: int = -1
		for index: int in range(game_state.current_layout.surfaces.size()):
			if game_state.current_layout.surfaces[index].surface_id == drop["surface_id"]:
				surface_index = index
		near_stop = hair_field.find_hairs_near(
			surface_index, stop["point"], AutomationController.DROP_SPREAD_M + 0.05, 100000
		).size()
	_check(
		near_stop >= int(drop.get("count", 1)),
		"猫が落とした毛は、猫が立ち止まった所から %.2f m の中にある (中の毛: %d 本)"
		% [AutomationController.DROP_SPREAD_M, near_stop],
	)


## R キーで掃除ロボットの画面が開閉し、開いている間は操作が止まって他の画面が開かず、買う・部屋を足すと回る順が変わるか
func _verify_robot_panel(main: Node3D, game_state: Node) -> void:
	var panel: RobotRoutePanel = main.robot_route_panel
	await _checker._press_physical_key(KEY_R)
	_check(
		panel.visible and not main.player.controls_enabled and not main.hand.enabled,
		"R キーで掃除ロボットの回る順の画面が開き、歩く・つまむ操作が止まる",
	)
	await _checker._press_physical_key(KEY_T)
	_check(not main.tool_shop_panel.visible, "掃除ロボットの画面が開いている間は T で道具を買う画面が開かない")
	game_state.save_data.building_progress.money = 0
	panel.refresh(game_state)
	_check(
		panel.get_buy_button().disabled,
		"お金が 300 円に足りない時は掃除ロボットを買うボタンを押せない",
	)
	game_state.save_data.building_progress.money = RobotRulesScript.ROBOT_PRICE
	panel.refresh(game_state)
	panel.get_buy_button().pressed.emit()
	await _checker.process_frame
	var robots: Array[OwnedTool] = game_state.automation.get_robots()
	_check(
		robots.size() == 1 and game_state.get_money() == 0 and robots[0].robot_room_ids.size() == 1
		and main.automation.get_robot_node_count() == 1
		and panel.get_robot_button(0) != null,
		"買うボタンで 300 円払って掃除ロボットを 1 台買い、今いる部屋を回る順にして屋敷に置かれる",
	)
	var rooms: Array[MansionLayout.RoomDef] = game_state.current_layout.rooms
	var first: StringName = robots[0].robot_room_ids[0] if not robots.is_empty() else &""
	var other: StringName = rooms[0].room_id if rooms[0].room_id != first else rooms[1].room_id
	var add_first: Button = panel.get_add_room_button(first)
	_check(
		add_first != null and add_first.disabled,
		"回る順に入っている部屋はもう一度足せない",
	)
	panel.get_add_room_button(other).pressed.emit()
	await _checker.process_frame
	_check(
		game_state.automation.get_robots()[0].robot_room_ids == [first, other]
		and panel.get_robot_button(0).text.contains("→"),
		"部屋のボタンを押すと、その部屋が回る順の最後に足される (実際: %s)"
		% str(game_state.automation.get_robots()[0].robot_room_ids),
	)
	panel.get_remove_last_button().pressed.emit()
	await _checker.process_frame
	_check(
		game_state.automation.get_robots()[0].robot_room_ids == [first],
		"「最後の部屋を外す」で足した部屋が回る順から外れる",
	)
	await _checker._press_physical_key(KEY_R)
	_check(
		not panel.visible and main.player.controls_enabled,
		"もう一度 R キーで画面が閉じ、操作が戻る",
	)


## 掃除ロボットが回る部屋に留まる間に毛を取り、在庫が増えて、屋敷の毛の見た目と保存データの本数が一致し、ロボットがその部屋にいるか
func _verify_robot_cleaning(main: Node3D, game_state: Node) -> void:
	var hair_field: Node3D = main.get_node("MansionWorld").get_hair_field()
	var stock_before: int = game_state.get_raw_hair_stock_count()
	var robot: OwnedTool = game_state.automation.get_robots()[0]
	var room: MansionLayout.RoomDef = RobotRulesScript.find_room(
		game_state.current_layout, robot.robot_room_ids[0]
	)
	# 掃除ロボットの時計を回る順の初めに合わせ、部屋に着いて輪を走り出した所から 20 秒分を進める
	var route: Dictionary = RobotRulesScript.build_route(
		game_state.current_layout, robot.robot_room_ids
	)
	var cycle: float = float(route["cycle_seconds"])
	var to_cycle_start: float = cycle - fposmod(game_state.automation.get_seconds(), cycle)
	game_state.automation.advance(to_cycle_start)
	var changes: Dictionary = game_state.automation.advance(RobotRulesScript.ROOM_SECONDS - 1.0)
	await _checker.process_frame
	var picked: int = 0
	for pick: Dictionary in changes["picks"]:
		picked += int(pick["count"])
	var robot_node: Node3D = main.automation.get_robot_node(0)
	var in_room: bool = (
		robot_node != null
		and absf(robot_node.position.x - room.center.x) < room.size.x * 0.5
		and absf(robot_node.position.z - room.center.z) < room.size.z * 0.5
	)
	_check(
		picked > 0
		and game_state.get_raw_hair_stock_count() == stock_before + picked
		and hair_field.get_remaining_count() == game_state.get_total_remaining_hairs()
		and in_room,
		"掃除ロボットは回る部屋 (%s) の中を走って毛を %d 本取り、在庫が同じだけ増え、屋敷の毛の見た目と保存データの本数が一致する (見た目: %d / 保存データ: %d)"
		% [
			room.display_name, picked, hair_field.get_remaining_count(),
			game_state.get_total_remaining_hairs()
		],
	)


## ブラシを持って猫を狙い、つまむ入力でブラッシングすると落ちる前の毛が在庫に入り、続けてもう一度は休んでいて取れないか
func _verify_brush_cat(main: Node3D, game_state: Node) -> void:
	game_state.save_data.building_progress.money = 9999
	game_state.purchase(GameStateScript.PURCHASE_TOOL, ToolCatalogScript.TOOL_BRUSH)
	main.tools.allow_uncaptured_use = true
	main.hand.allow_uncaptured_pluck = true
	await _checker._press_physical_key(
		ToolController.SELECT_KEYS[ToolCatalogScript.all_tool_ids().find(ToolCatalogScript.TOOL_BRUSH)]
	)
	var cat_id: StringName = game_state.automation.get_cat_routes()[1]["cat_id"]
	var aimed: bool = await _aim_at_cat(main, cat_id)
	var stock_before: int = game_state.get_raw_hair_stock_count()
	var hairs_before: int = game_state.get_total_remaining_hairs()
	await _press_and_release_use()
	_check(
		aimed
		and main.tools.get_selected_tool_id() == ToolCatalogScript.TOOL_BRUSH
		and game_state.get_raw_hair_stock_count() == stock_before + CatRulesScript.BRUSH_HAIRS
		and game_state.get_total_remaining_hairs() == hairs_before
		and main.tool_message_label.text.contains("ブラッシングした"),
		"ブラシで猫を狙ってつまむ入力をすると、落ちる前の毛 %d 本が在庫に入り、屋敷の毛の本数は変わらない (狙えた: %s / メッセージ: %s)"
		% [CatRulesScript.BRUSH_HAIRS, str(aimed), main.tool_message_label.text],
	)
	await _press_and_release_use()
	_check(
		game_state.get_raw_hair_stock_count() == stock_before + CatRulesScript.BRUSH_HAIRS
		and main.tool_message_label.text.contains("休んでいる"),
		"ブラッシングした直後の猫にもう一度ブラシをかけても毛は取れず「休んでいる」と出る",
	)
	main.tools.allow_uncaptured_use = false
	main.hand.allow_uncaptured_pluck = false
	Input.action_release(HandController.ACTION_PLUCK)


## 猫 cat_id の周りの 4 方向を順に試し、STAND_DISTANCE_M 離れた所に立って猫の体の中心を見る。画面中央の狙いがその猫に
## 当たったら true
func _aim_at_cat(main: Node3D, cat_id: StringName) -> bool:
	var player: FirstPersonPlayer = main.player
	for quarter: int in range(4):
		var center: Vector3 = main.automation.cat_centers()[cat_id]
		var away: Vector3 = Vector3.FORWARD.rotated(Vector3.UP, PI * 0.5 * float(quarter))
		player.set_spawn(Vector3(center.x, 0.0, center.z) + away * STAND_DISTANCE_M, 0.0)
		await _checker.physics_frame
		await _checker.physics_frame
		player.look_at_point(center)
		await _checker.physics_frame
		if main.tools.aimed_cat_id() == cat_id:
			return true
	return false


## つまむ入力を押して離す (道具を使う)
func _press_and_release_use() -> void:
	Input.action_press(HandController.ACTION_PLUCK)
	await _checker.process_frame
	await _checker.process_frame
	Input.action_release(HandController.ACTION_PLUCK)
	await _checker.process_frame
	await _checker.process_frame

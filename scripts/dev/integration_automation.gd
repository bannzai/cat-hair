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
## 屋敷の毛の描画 (面ごと・色ごとの本数を数える)
const HairFieldScript := preload("res://scripts/hair_field.gd")
## 屋敷の作りの型 (表面の種類の定数)
const MansionLayoutScript := preload("res://scripts/mansion/mansion_layout.gd")
## 面ごとの毛の型 (毛の色の並び)
const SurfaceHairScript := preload("res://scripts/data/surface_hair.gd")
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
	_check(
		game_state.automation.get_seconds() > seconds_before,
		"屋敷で遊んでいる間は時計がフレームごとに進む (%.3f → %.3f 秒)"
		% [seconds_before, game_state.automation.get_seconds()],
	)
	# タイトルに戻し、時計を進める設定のままでも進まないことを確かめる
	var stand: Vector3 = main.player.global_position
	main._set_title_mode()
	var title_seconds: float = game_state.automation.get_seconds()
	for _frame: int in range(10):
		await _checker.process_frame
	var seconds_after_title: float = game_state.automation.get_seconds()
	main.auto_advance_automation = false
	main.enter_mansion()
	main.player.set_spawn(stand, 0.0)
	await _checker.physics_frame
	_check(
		is_equal_approx(seconds_after_title, title_seconds),
		"屋敷で遊んでいない間 (タイトル) は、時計を進める設定でも時計が進まない",
	)
	var route: Dictionary = routes[0]
	var cat_node: Node3D = automation.get_cat_node(route["cat_id"])
	var first_point: Vector3 = cat_node.position
	game_state.automation.advance(float(route["stops"][0]["seconds"]) + RouteClockScript.MOVE_SECONDS)
	# process_frame で再開するのは同じフレームの各ノードの _process より前のため、位置を明示して更新してから比べる
	automation.update_positions()
	var expected: Vector3 = RouteClockScript.position_at(route, game_state.automation.get_seconds())
	_check(
		cat_node.position.is_equal_approx(expected) and cat_node.position.distance_to(first_point) > 0.5,
		"時計を進めると %s は通り道の次の所へ歩いて移る (前: %s / 今: %s / 期待: %s)"
		% [route["name"], str(first_point), str(cat_node.position), str(expected)],
	)
	await _verify_nap_posture(main, game_state)


## 猫は昼寝の所に着いて歩き終えると胴を下げて脚を隠し、昼寝の所へ歩いている間と通り道で立ち止まっている間は脚で立つか
func _verify_nap_posture(main: Node3D, game_state: Node) -> void:
	var route: Dictionary = game_state.automation.get_cat_routes()[0]
	var cat: Node3D = main.automation.get_cat_node(route["cat_id"])
	var cycle: float = float(route["cycle_seconds"])
	var nap_start: float = cycle - CatRulesScript.NAP_SECONDS
	var postures: Array[String] = []
	# 次の巡の、通り道で立ち止まった後・昼寝の所へ歩いている途中・昼寝の所に着いた後の 3 つの時刻を順に見る
	var base: float = (floori(game_state.automation.get_seconds() / cycle) + 1) * cycle
	for target: float in [
		base + RouteClockScript.MOVE_SECONDS + 1.0,
		base + nap_start + RouteClockScript.MOVE_SECONDS * 0.5,
		base + nap_start + RouteClockScript.MOVE_SECONDS + 1.0,
	]:
		game_state.automation.advance(target - game_state.automation.get_seconds())
		main.automation.update_positions()
		var body: Node3D = cat.get_node("Body")
		var legs: Node3D = cat.get_node("Legs")
		postures.append(
			"%s/%s" % ["伏せ" if body.position.y < 0.0 else "立ち", "脚あり" if legs.visible else "脚なし"]
		)
	_check(
		postures == ["立ち/脚あり", "立ち/脚あり", "伏せ/脚なし"],
		"猫は昼寝の所に着いてから伏せて脚を隠し、立ち止まっている間と昼寝の所へ歩く途中は立つ (実際: %s)"
		% str(postures),
	)


## 猫が毛を落とすと、屋敷の毛の見た目 (HairField) の本数と保存データの本数が同じだけ増え、落ちた毛は立ち止まった所の近くにあるか
func _verify_hair_sync(main: Node3D, game_state: Node) -> void:
	var hair_field: Node3D = main.get_node("MansionWorld").get_hair_field()
	# 猫の毛は面の最初の本数までしか溜まらないため、猫が立ち止まる面を先にきれいにする (手で取り切った後と同じ)。
	# 今いる部屋 (後で掃除ロボットを置く部屋) は、掃除ロボットが取る毛を残すためにきれいにしない
	var current_room: MansionLayout.RoomDef = main.get_current_room()
	var keep_room: StringName = (
		current_room.room_id if current_room != null else game_state.current_layout.rooms[0].room_id
	)
	for route: Dictionary in game_state.automation.get_cat_routes():
		for stop: Dictionary in route["stops"]:
			if stop["room_id"] != keep_room:
				_clear_surface(hair_field, game_state, stop["surface_id"])
	var field_before: int = hair_field.get_remaining_count()
	var state_before: int = game_state.get_total_remaining_hairs()
	var progress: BuildingProgress = game_state.save_data.building_progress
	var surface_before: Dictionary = {}
	for surface: SurfaceHair in progress.surface_hairs:
		surface_before[surface.surface_id] = surface.total_count()
	var changes: Dictionary = game_state.automation.advance(30.0)
	await _checker.process_frame
	var dropped: int = 0
	var dropped_by_surface: Dictionary = {}
	for drop: Dictionary in changes["drops"]:
		dropped += int(drop["count"])
		dropped_by_surface[drop["surface_id"]] = (
			int(dropped_by_surface.get(drop["surface_id"], 0)) + int(drop["count"])
		)
	var surfaces_grown: bool = not dropped_by_surface.is_empty()
	for surface_id: Variant in dropped_by_surface.keys():
		var surface: SurfaceHair = progress.find_surface_hair(StringName(surface_id))
		surfaces_grown = (
			surfaces_grown and surface != null
			and surface.total_count()
			== int(surface_before[surface_id]) + int(dropped_by_surface[surface_id])
		)
	_check(
		surfaces_grown,
		"猫が通った面 (%d 面) の毛が、その面に落とした本数だけ増える" % dropped_by_surface.size(),
	)
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
	var stand: Vector3 = main.player.global_position
	main._set_title_mode()
	await _checker._press_physical_key(KEY_R)
	var opened_in_title: bool = panel.visible
	main.enter_mansion()
	main.player.set_spawn(stand, 0.0)
	await _checker.physics_frame
	await _checker._press_physical_key(KEY_T)
	await _checker._press_physical_key(KEY_R)
	var opened_over_shop: bool = panel.visible
	await _checker._press_physical_key(KEY_T)
	_check(
		not opened_in_title and not opened_over_shop and not main.tool_shop_panel.visible,
		"タイトルにいる間と道具を買う画面を開いている間は、R キーで掃除ロボットの画面が開かない",
	)
	await _checker._press_physical_key(KEY_R)
	_check(
		panel.visible and not main.player.controls_enabled and not main.hand.enabled,
		"R キーで掃除ロボットの回る順の画面が開き、歩く・つまむ操作が止まる",
	)
	await _checker._press_physical_key(KEY_T)
	_check(not main.tool_shop_panel.visible, "掃除ロボットの画面が開いている間は T で道具を買う画面が開かない")
	game_state.save_data.building_progress.money = 0
	panel.refresh(game_state)
	var all_rooms_disabled: bool = true
	for room: MansionLayout.RoomDef in game_state.current_layout.rooms:
		all_rooms_disabled = all_rooms_disabled and panel.get_add_room_button(room.room_id).disabled
	_check(
		game_state.automation.get_robots().is_empty() and all_rooms_disabled
		and panel.get_remove_last_button().disabled and panel.get_clear_button().disabled,
		"掃除ロボットが 0 台の時は、部屋を足す・最後を外す・空にするボタンを押せない",
	)
	var echo_event: InputEventKey = InputEventKey.new()
	echo_event.physical_keycode = KEY_R
	echo_event.pressed = true
	echo_event.echo = true
	var press_event: InputEventKey = echo_event.duplicate()
	press_event.echo = false
	_check(
		main._is_key_press(press_event, KEY_R) and not main._is_key_press(echo_event, KEY_R),
		"R キーを押した瞬間だけ画面を開閉し、押しっぱなしの繰り返しでは開閉しない",
	)
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
	var add_button_before: Button = panel.get_add_room_button(other)
	var robot_button_before: Button = panel.get_robot_button(0)
	game_state.save_data.building_progress.money += 1
	game_state.state_changed.emit()
	await _checker.process_frame
	_check(
		panel.get_add_room_button(other) == add_button_before
		and panel.get_robot_button(0) == robot_button_before
		and is_instance_valid(add_button_before),
		"お金や毛の本数が変わって画面を描き直しても、部屋と台のボタンは作り直さない (押している途中の操作を消さない)",
	)
	panel.get_clear_button().pressed.emit()
	await _checker.process_frame
	_check(
		game_state.automation.get_robots()[0].robot_room_ids.is_empty()
		and not main.automation.get_robot_node(0).visible
		and panel.get_robot_button(0).text.contains("止まっている"),
		"「順を空にして止める」で回る順が空になり、止めた掃除ロボットは屋敷から見えなくなる",
	)
	panel.get_add_room_button(first).pressed.emit()
	await _checker.process_frame
	await _verify_second_robot(main, game_state, first)
	await _checker._press_physical_key(KEY_B)
	await _checker._press_physical_key(KEY_F1)
	_check(
		panel.visible and not main.hair_book_panel.visible and not main.dev_tuning_panel.visible,
		"掃除ロボットの画面が開いている間は、B で図鑑も F1 で開発者向け画面も開かない",
	)
	await _checker._press_physical_key(KEY_R)
	_check(
		not panel.visible and main.player.controls_enabled,
		"もう一度 R キーで画面が閉じ、操作が戻る",
	)
	await _checker._press_physical_key(KEY_R)
	(panel.get_node("Layout/CloseButton") as Button).pressed.emit()
	await _checker.process_frame
	_check(
		not panel.visible and main.player.controls_enabled,
		"「閉じる」ボタンでも画面が閉じ、操作が戻る",
	)


## 部屋の外で 2 台目を買うと屋敷の最初の部屋を回る順で置かれ、2 台目を選んで足した部屋は 2 台目の順にだけ入り、
## お金が足りていても 4 台持つと買うボタンを押せないか (掃除ロボットの画面を開いたまま呼ぶ)
func _verify_second_robot(main: Node3D, game_state: Node, first: StringName) -> void:
	var panel: RobotRoutePanel = main.robot_route_panel
	var rooms: Array[MansionLayout.RoomDef] = game_state.current_layout.rooms
	var stand: Vector3 = main.player.global_position
	# 屋敷のどの部屋の床の上でもない所 (屋敷の外) に立つ
	main.player.set_spawn(Vector3(-1000.0, 0.0, 1000.0), 0.0)
	await _checker.physics_frame
	var outside: bool = main.get_current_room() == null
	game_state.save_data.building_progress.money = RobotRulesScript.ROBOT_PRICE
	panel.get_buy_button().pressed.emit()
	await _checker.process_frame
	main.player.set_spawn(stand, 0.0)
	await _checker.physics_frame
	var robots: Array[OwnedTool] = game_state.automation.get_robots()
	_check(
		outside and robots.size() == 2 and robots[1].robot_room_ids == [rooms[0].room_id],
		"部屋の外で買った掃除ロボットは、屋敷の最初の部屋 (%s) を回る順で置かれる" % rooms[0].display_name,
	)
	panel.get_robot_button(1).pressed.emit()
	await _checker.process_frame
	var added: StringName = rooms[1].room_id
	panel.get_add_room_button(added).pressed.emit()
	await _checker.process_frame
	robots = game_state.automation.get_robots()
	_check(
		panel.get_selected_index() == 1
		and robots[1].robot_room_ids == [rooms[0].room_id, added]
		and robots[0].robot_room_ids == [first],
		"2 台目を選んで足した部屋は 2 台目の回る順にだけ入り、1 台目の順は変わらない",
	)
	game_state.save_data.building_progress.money = RobotRulesScript.ROBOT_PRICE * 10
	panel.refresh(game_state)
	while not panel.get_buy_button().disabled and game_state.automation.get_robots().size() < 10:
		panel.get_buy_button().pressed.emit()
		await _checker.process_frame
	_check(
		game_state.automation.get_robots().size() == RobotRulesScript.MAX_ROBOTS
		and panel.get_buy_button().disabled
		and game_state.get_money() >= RobotRulesScript.ROBOT_PRICE,
		"お金が足りていても 4 台持つと買うボタンを押せない (台数: %d / 所持金: %d 円)"
		% [game_state.automation.get_robots().size(), game_state.get_money()],
	)
	panel.get_robot_button(0).pressed.emit()
	await _checker.process_frame


## 掃除ロボットが回る部屋に留まる間に毛を取り、在庫が増えて、屋敷の毛の見た目と保存データの本数が一致し、ロボットがその部屋にいるか
func _verify_robot_cleaning(main: Node3D, game_state: Node) -> void:
	var hair_field: Node3D = main.get_node("MansionWorld").get_hair_field()
	var robot: OwnedTool = game_state.automation.get_robots()[0]
	var room: MansionLayout.RoomDef = RobotRulesScript.find_room(
		game_state.current_layout, robot.robot_room_ids[0]
	)
	# 掃除ロボットの時計を回る順の初めに合わせ、部屋に着いて輪を走り出した所から 20 秒分を進める
	var route: Dictionary = RobotRulesScript.build_route(
		game_state.current_layout, robot.robot_room_ids
	)
	var cycle: float = float(route["cycle_seconds"])
	game_state.automation.advance(cycle - fposmod(game_state.automation.get_seconds(), cycle))
	var stock_before: int = game_state.get_raw_hair_stock_count()
	var hairs_before: int = game_state.get_total_remaining_hairs()
	var changes: Dictionary = game_state.automation.advance(RobotRulesScript.ROOM_SECONDS - 1.0)
	await _checker.process_frame
	var picked: int = 0
	for pick: Dictionary in changes["picks"]:
		picked += int(pick["count"])
	var dropped: int = 0
	for drop: Dictionary in changes["drops"]:
		dropped += int(drop["count"])
	_check(
		picked > 0
		and game_state.get_total_remaining_hairs() == hairs_before + dropped - picked,
		"操作せずに時間を進めると、掃除ロボットが取った %d 本だけ屋敷の毛が減る (猫が落とした %d 本を除く)"
		% [picked, dropped],
	)
	var mismatched: Array[String] = []
	var surfaces: Array[MansionLayout.SurfaceDef] = game_state.current_layout.surfaces
	for index: int in range(surfaces.size()):
		var state_surface: SurfaceHair = game_state.save_data.building_progress.find_surface_hair(
			surfaces[index].surface_id
		)
		var state_counts: PackedInt32Array = PackedInt32Array()
		for color_id: StringName in SurfaceHairScript.STANDARD_COLORS:
			state_counts.append(state_surface.count_for_color(color_id) if state_surface != null else 0)
		if HairFieldScript.count_surface_groups(hair_field, index) != state_counts:
			mismatched.append(String(surfaces[index].surface_id))
	_check(
		mismatched.is_empty(),
		"猫が落とした毛と掃除ロボットが取った毛の後も、面ごと・色ごとの本数が見た目と保存データで一致する (合わない面: %s)"
		% str(mismatched),
	)
	var robot_node: Node3D = main.automation.get_robot_node(0)
	_check(
		picked > 0
		and game_state.get_raw_hair_stock_count() == stock_before + picked
		and hair_field.get_remaining_count() == game_state.get_total_remaining_hairs()
		and robot_node != null
		and absf(robot_node.position.x - room.center.x) < room.size.x * 0.5
		and absf(robot_node.position.z - room.center.z) < room.size.z * 0.5,
		"掃除ロボットは回る部屋 (%s) の中を走って毛を %d 本取り、在庫が同じだけ増え、屋敷の毛の見た目と保存データの本数が一致する (見た目: %d / 保存データ: %d)"
		% [
			room.display_name, picked, hair_field.get_remaining_count(),
			game_state.get_total_remaining_hairs()
		],
	)
	await _verify_pick_nearest(main, game_state, room)


## 掃除ロボットが取った毛は、取った面のうち同じ色で掃除ロボットにいちばん近い毛から消えるか。
## 面ごとの本数の一致だけでは、消す毛を選ぶ起点を取り違えても落ちないため、1 本取った時に消える毛を直接確かめる
func _verify_pick_nearest(main: Node3D, game_state: Node, room: MansionLayout.RoomDef) -> void:
	var hair_field: Node3D = main.get_node("MansionWorld").get_hair_field()
	var world: MansionWorld = main.get_node("MansionWorld")
	# 掃除ロボットを、輪を 4 分の 1 周走った所 (部屋の中心から横に離れた所) まで進める。中心のままだと、最初の部屋の
	# 中心は屋敷の原点に重なり、消す毛を選ぶ起点を原点に取り違えても同じ毛が消えて区別できないため
	var route: Dictionary = RobotRulesScript.build_route(
		game_state.current_layout, game_state.automation.get_robots()[0].robot_room_ids
	)
	var cycle: float = float(route["cycle_seconds"])
	game_state.automation.advance(
		cycle - fposmod(game_state.automation.get_seconds(), cycle)
		+ RouteClockScript.MOVE_SECONDS + RobotRulesScript.LOOP_SECONDS * 0.25
	)
	main.automation.update_positions()
	var robot_position: Vector3 = main.automation.get_robot_node(0).position
	_check(
		Vector2(robot_position.x - room.center.x, robot_position.z - room.center.z).length() > 1.0,
		"近い毛から消える検証の前に、掃除ロボットが部屋の中心から 1 m より離れている (位置: %s)"
		% str(robot_position),
	)
	var surfaces: Array[MansionLayout.SurfaceDef] = game_state.current_layout.surfaces
	var floor_index: int = -1
	for index: int in range(surfaces.size()):
		if (
			surfaces[index].room_id == room.room_id
			and surfaces[index].surface_type == MansionLayoutScript.SURFACE_FLOOR
		):
			floor_index = index
	var nearest_id: int = -1
	var nearest_color: StringName = &""
	for hair_id: int in hair_field.find_hairs_near(
		floor_index, robot_position, INF, hair_field.get_surface_remaining_count(floor_index)
	):
		nearest_id = hair_id
		nearest_color = world.get_hair_color_id(hair_id)
		break
	var farther_same_color: int = 0
	for hair_id: int in hair_field.find_hairs_near(
		floor_index, robot_position, INF, hair_field.get_surface_remaining_count(floor_index)
	):
		if hair_id != nearest_id and world.get_hair_color_id(hair_id) == nearest_color:
			farther_same_color += 1
	var surface_id: StringName = surfaces[floor_index].surface_id
	var state_surface: SurfaceHair = (
		game_state.save_data.building_progress.find_surface_hair(surface_id)
	)
	state_surface.hair_counts[nearest_color] = state_surface.count_for_color(nearest_color) - 1
	game_state.automation_advanced.emit({
		"drops": [],
		"picks": [{"robot_index": 0, "surface_id": surface_id, "color": nearest_color, "count": 1}],
	})
	var still_there: bool = hair_field.find_hairs_near(
		floor_index, robot_position, INF, hair_field.get_surface_remaining_count(floor_index)
	).has(nearest_id)
	_check(
		nearest_id >= 0 and farther_same_color > 0 and not still_there
		and hair_field.get_remaining_count() == game_state.get_total_remaining_hairs(),
		"掃除ロボットが 1 本取ると、同じ色で掃除ロボットにいちばん近い毛が消え、遠い同じ色の毛は残る (残った同じ色: %d 本)"
		% farther_same_color,
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
	# 猫とプレイヤーの間に壁を立てると、狙いの先に猫がいてもブラシは届かない
	var wall: StaticBody3D = StaticBody3D.new()
	var wall_shape: CollisionShape3D = CollisionShape3D.new()
	var wall_box: BoxShape3D = BoxShape3D.new()
	# 光線の通り道をふさぐ大きさ (幅と高さ 1 m、厚さ 5 cm)
	wall_box.size = Vector3(1.0, 1.0, 0.05)
	wall_shape.shape = wall_box
	wall.add_child(wall_shape)
	main.add_child(wall)
	var camera_position: Vector3 = main.player.get_viewport().get_camera_3d().global_position
	wall.global_position = camera_position.lerp(main.automation.cat_centers()[cat_id], 0.5)
	wall.look_at(camera_position)
	await _checker.physics_frame
	await _checker.physics_frame
	var blocked_aim: StringName = main.tools.aimed_cat_id()
	main.remove_child(wall)
	wall.free()
	await _checker.physics_frame
	_check(
		aimed and blocked_aim == &"" and main.tools.aimed_cat_id() == cat_id,
		"猫との間に壁がある時はブラシで猫を狙えず、壁を除くと狙える",
	)
	var stock_before: int = game_state.get_raw_hair_stock_count()
	var hairs_before: int = game_state.get_total_remaining_hairs()
	await _checker.press_and_release_use()
	_check(
		aimed
		and main.tools.get_selected_tool_id() == ToolCatalogScript.TOOL_BRUSH
		and game_state.get_raw_hair_stock_count() == stock_before + CatRulesScript.BRUSH_HAIRS
		and game_state.get_total_remaining_hairs() == hairs_before
		and main.tool_message_label.text.contains("ブラッシングした"),
		"ブラシで猫を狙ってつまむ入力をすると、落ちる前の毛 %d 本が在庫に入り、屋敷の毛の本数は変わらない (狙えた: %s / メッセージ: %s)"
		% [CatRulesScript.BRUSH_HAIRS, str(aimed), main.tool_message_label.text],
	)
	await _checker.press_and_release_use()
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


## surface_id の面の毛を、保存データと屋敷の毛の見た目の両方から取り除く
static func _clear_surface(hair_field: Node3D, game_state: Node, surface_id: StringName) -> void:
	var surfaces: Array[MansionLayout.SurfaceDef] = game_state.current_layout.surfaces
	for index: int in range(surfaces.size()):
		if surfaces[index].surface_id != surface_id:
			continue
		# 埋もれた毛を先に消し、描いている毛を消した時に描き足さないようにする
		for group: int in range(HairFieldScript.HairColorGroup.size()):
			HairFieldScript.remove_buried_hairs(
				hair_field, index, group, hair_field.get_surface_remaining_count(index)
			)
		for hair_id: int in hair_field.find_hairs_near(
			index, surfaces[index].center, INF, hair_field.get_surface_remaining_count(index)
		):
			hair_field.remove_hair(hair_id)
	var surface: SurfaceHair = game_state.save_data.building_progress.find_surface_hair(surface_id)
	if surface != null:
		for color_id: Variant in surface.hair_counts.keys():
			surface.hair_counts[color_id] = 0

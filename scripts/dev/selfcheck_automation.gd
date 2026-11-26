extends RefCounted
## 猫 (通り道・毛を落とす量・面の上限・ブラッシング) と掃除ロボット (値段・回る順・毛を取る量) の計算と、
## GameState の時計を進める・掃除ロボットを買う・回る順を変える・猫をブラッシングする入口の検証スイート
## (scripts/dev/selfcheck.gd から呼ぶ)。

## 決まった所を順に回る動きの時刻の計算
const RouteClockScript := preload("res://scripts/automation/route_clock.gd")
## 猫の通り道・毛を落とす量・ブラッシングの計算
const CatRulesScript := preload("res://scripts/automation/cat_rules.gd")
## 掃除ロボットの値段・回る順・毛を取る量の計算
const RobotRulesScript := preload("res://scripts/automation/robot_rules.gd")
## 手に持って使う道具の定義 (ブラシの id)
const ToolCatalogScript := preload("res://scripts/tools/tool_catalog.gd")
## 屋敷レイアウト型スクリプト (表面の種類)
const MansionLayoutScript := preload("res://scripts/mansion/mansion_layout.gd")
## 面ごとの毛データ型スクリプト (毛の色の id)
const SurfaceHairScript := preload("res://scripts/data/surface_hair.gd")
## 毛・加工品在庫データ型スクリプト (毛のままの形の id)
const HairStockScript := preload("res://scripts/data/hair_stock.gd")
## 屋敷の毛の描画 (猫が落とした毛を足す)
const HairFieldScript := preload("res://scripts/hair_field.gd")
## 撮影と録画で、見たい所との間に家具を挟まずに立つ所を選ぶ手順
const ViewPointScript := preload("res://scripts/dev/view_point.gd")
## 状態管理 autoload スクリプト
const GameStateScript := preload("res://scripts/state/game_state.gd")
## selfcheck が使う一時セーブファイルパス (GameState の初期化だけに使い、保存はしない)
const TEST_SAVE_PATH: String = "user://selfcheck_automation_save_data.json"

## 検証結果を記録する selfcheck の SceneTree 参照
var _checker: SceneTree = null


## 猫と掃除ロボットの検証をすべて実行する
static func run_all(checker: SceneTree) -> void:
	var suite: RefCounted = load("res://scripts/dev/selfcheck_automation.gd").new()
	suite._checker = checker
	suite._check_route_clock()
	suite._check_cat_rules()
	suite._check_robot_rules()
	suite._check_game_state_cats()
	suite._check_game_state_robots()
	suite._check_game_state_brush()
	suite._check_layout_geometry()
	suite._check_robot_position()
	suite._check_automation_reset()
	suite._check_hair_field_add()
	suite._check_capped_order()
	suite._check_surface_choice()
	suite._check_empty_inputs()
	suite._check_picks_only_notify()
	suite._check_view_point()
	suite._check_door_path()


## 判定を selfcheck 本体に記録する
func _check(cond: bool, label: String) -> void:
	_checker._check(cond, label)


## 一巡の秒数・時刻ごとの留まる所・移る途中の位置・出来事の回数 (区間の分け方で変わらない) を確かめる
func _check_route_clock() -> void:
	var stops: Array[Dictionary] = [
		{"point": Vector3(0.0, 0.0, 0.0), "seconds": 8.0},
		{"point": Vector3(4.0, 0.0, 0.0), "seconds": 6.0},
	]
	var route: Dictionary = RouteClockScript.make_route(stops)
	_check(is_equal_approx(float(route["cycle_seconds"]), 14.0), "一巡の秒数は留まる秒数の和 (8 + 6 = 14)")
	_check(
		RouteClockScript.stop_index_at(route, 0.0) == 0
		and RouteClockScript.stop_index_at(route, 7.99) == 0
		and RouteClockScript.stop_index_at(route, 8.0) == 1
		and RouteClockScript.stop_index_at(route, 13.99) == 1
		and RouteClockScript.stop_index_at(route, 14.0) == 0
		and RouteClockScript.stop_index_at(route, 24.0) == 1,
		"留まる所は 8 秒で 2 か所目へ移り、14 秒で一巡して最初に戻る (24 秒は 2 巡目の 10 秒 → 2 か所目)",
	)
	var halfway: Vector3 = RouteClockScript.position_at(
		route, 8.0 + RouteClockScript.MOVE_SECONDS * 0.5
	)
	_check(
		RouteClockScript.position_at(route, 8.0).is_equal_approx(Vector3(0.0, 0.0, 0.0))
		and halfway.is_equal_approx(Vector3(2.0, 0.0, 0.0))
		and RouteClockScript.position_at(route, 12.0).is_equal_approx(Vector3(4.0, 0.0, 0.0)),
		"2 か所目に着いた瞬間は前の所、移る秒数の半分で中間、移り終えた後は 2 か所目にいる (実際の中間: %s)"
		% str(halfway),
	)
	var whole: Dictionary = RouteClockScript.ticks_between(route, 0.0, 14.0, 2.0)
	_check(
		int(whole.get(0, 0)) == 4 and int(whole.get(1, 0)) == 3,
		"2 秒ごとの出来事は 1 巡で 8 秒の所に 4 回、6 秒の所に 3 回 (実際: %s)" % str(whole),
	)
	var long_total: Dictionary = RouteClockScript.ticks_between(route, 0.0, 100.0, 2.0)
	var split_total: Dictionary = {}
	var cuts: Array[float] = [0.0, 0.3, 5.0, 8.0, 8.1, 37.7, 64.0, 100.0]
	for cut_index: int in range(cuts.size() - 1):
		var part: Dictionary = RouteClockScript.ticks_between(
			route, cuts[cut_index], cuts[cut_index + 1], 2.0
		)
		for key: Variant in part.keys():
			split_total[key] = int(split_total.get(key, 0)) + int(part[key])
	_check(
		long_total == split_total and int(long_total.get(0, 0)) + int(long_total.get(1, 0)) > 0,
		"出来事の回数は区間を細かく分けて足しても、まとめて求めた回数と同じ (まとめて: %s / 分けて: %s)"
		% [str(long_total), str(split_total)],
	)
	_check(
		RouteClockScript.ticks_between(route, 5.0, 5.0, 2.0).is_empty()
		and RouteClockScript.ticks_between(route, 6.0, 5.0, 2.0).is_empty()
		and RouteClockScript.ticks_between(route, 0.0, 14.0, 0.0).is_empty()
		and RouteClockScript.ticks_between(RouteClockScript.make_route([]), 0.0, 14.0, 2.0).is_empty()
		and RouteClockScript.stop_index_at(RouteClockScript.make_route([]), 3.0) == -1,
		"時間が進まない・戻る・間隔が 0・道のりが空の時は出来事が起きない",
	)


## 屋敷の作りから組んだ猫の通り道 (3 匹・全部屋を 1 回ずつ・家具に重ならない・昼寝の面)、毛を落とす量、
## 面の上限、狙った猫の決め方を確かめる
func _check_cat_rules() -> void:
	var state: Node = GameStateScript.new()
	state.initialize_from_storage(TEST_SAVE_PATH, PackedStringArray(["--hair-count=300"]))
	var layout: MansionLayout = state.current_layout
	var routes: Array[Dictionary] = CatRulesScript.build_routes(layout)
	var colors: Array[StringName] = []
	for route: Dictionary in routes:
		colors.append(route["color"])
	_check(
		routes.size() == 3
		and colors == [
			SurfaceHairScript.COLOR_WHITE, SurfaceHairScript.COLOR_BLACK, SurfaceHairScript.COLOR_CALICO
		],
		"猫は 3 匹で、白・黒・三毛の毛を落とす",
	)
	for route: Dictionary in routes:
		var walk_rooms: Dictionary = {}
		var naps: int = 0
		var blocked: int = 0
		var nap_type_ok: bool = true
		for stop: Dictionary in route["stops"]:
			if bool(stop["nap"]):
				naps += 1
				var nap_surface: MansionLayout.SurfaceDef = layout.find_surface(stop["surface_id"])
				nap_type_ok = (
					nap_surface != null and nap_surface.surface_type in CatRulesScript.NAP_SURFACE_TYPES
				)
			else:
				walk_rooms[stop["room_id"]] = true
				if CatRulesScript.is_blocked(layout, stop["room_id"], stop["point"]):
					blocked += 1
		_check(
			walk_rooms.size() == layout.rooms.size()
			and naps == 1
			and nap_type_ok
			and blocked == 0,
			"%s の通り道は全 %d 部屋を 1 回ずつ通り、家具に重ならず、ソファかカーペットで 1 回昼寝する (通った部屋: %d / 昼寝: %d / 家具に重なる所: %d)"
			% [route["name"], layout.rooms.size(), walk_rooms.size(), naps, blocked],
		)
	_check(
		routes[0]["stops"][0]["room_id"] != routes[1]["stops"][0]["room_id"],
		"1 匹目と 2 匹目は別の部屋から歩き出す (同じ所に重ならない)",
	)
	var route: Dictionary = routes[0]
	var expected_per_cycle: int = 0
	for stop: Dictionary in route["stops"]:
		expected_per_cycle += floori(float(stop["seconds"]) / CatRulesScript.DROP_INTERVAL_SECONDS)
	var cycle_drops: Dictionary = CatRulesScript.drops_between(
		route, 0.0, float(route["cycle_seconds"])
	)
	var dropped: int = 0
	for key: Variant in cycle_drops.keys():
		dropped += int(cycle_drops[key])
	var nap_stop: Dictionary = route["stops"][route["stops"].size() - 1]
	_check(
		dropped == expected_per_cycle
		and int(cycle_drops.get(nap_stop["surface_id"], 0))
		>= floori(CatRulesScript.NAP_SECONDS / CatRulesScript.DROP_INTERVAL_SECONDS),
		"猫は 1 巡で立ち止まった秒数 ÷ 2 秒の本数を落とし、昼寝の面には 24 秒 ÷ 2 秒 = 12 本以上落ちる (実際: %d / 期待: %d)"
		% [dropped, expected_per_cycle],
	)
	_check(
		CatRulesScript.room_for_drops(10, 100) == 90
		and CatRulesScript.room_for_drops(100, 100) == 0
		and CatRulesScript.room_for_drops(130, 100) == 0
		and CatRulesScript.room_for_drops(0, 5) == CatRulesScript.MIN_SURFACE_CAP
		and CatRulesScript.room_for_drops(39, 0) == 1,
		"猫の毛は面の最初の本数 (40 本未満の面は 40 本) まで溜まり、それ以上は落ちない",
	)
	var centers: Dictionary = {
		&"near": Vector3(0.0, 0.0, -1.0),
		&"far": Vector3(0.0, 0.0, -1.8),
		&"side": Vector3(0.5, 0.0, -0.5),
		&"behind": Vector3(0.0, 0.0, 1.0),
	}
	_check(
		CatRulesScript.cat_on_ray(centers, Vector3.ZERO, Vector3.FORWARD, 2.5) == &"near"
		and CatRulesScript.cat_on_ray(
			{&"far": centers[&"far"]}, Vector3.ZERO, Vector3.FORWARD, 1.5
		) == &""
		and CatRulesScript.cat_on_ray(
			{&"side": centers[&"side"], &"behind": centers[&"behind"]}, Vector3.ZERO, Vector3.FORWARD, 2.5
		) == &"",
		"ブラシは光線の先のいちばん手前の猫を狙い、手の届く距離の外・光線から 35 cm より外・後ろの猫は狙わない",
	)
	_check(
		CatRulesScript.build_routes(null).is_empty(),
		"屋敷が無い時は猫の通り道を作らない",
	)
	state.free()


## 掃除ロボットの回る順の道のり、毛を取る回数、取る毛の選び方、台ごとの時刻のずれを確かめる
func _check_robot_rules() -> void:
	var state: Node = GameStateScript.new()
	state.initialize_from_storage(TEST_SAVE_PATH, PackedStringArray(["--hair-count=300"]))
	var layout: MansionLayout = state.current_layout
	var first: StringName = layout.rooms[0].room_id
	var second: StringName = layout.rooms[1].room_id
	var route: Dictionary = RobotRulesScript.build_route(layout, [first, &"no_such_room", second])
	_check(
		route["stops"].size() == 2
		and route["stops"][1]["room_id"] == second
		and is_equal_approx(float(route["cycle_seconds"]), RobotRulesScript.ROOM_SECONDS * 2.0),
		"回る順のうち屋敷に無い部屋は飛ばし、1 部屋に 20 秒ずつ留まる",
	)
	var picks: Dictionary = RobotRulesScript.picks_between(
		route, 0.0, RobotRulesScript.ROOM_SECONDS * 2.0
	)
	_check(
		int(picks.get(first, 0)) == 20 and int(picks.get(second, 0)) == 20,
		"掃除ロボットは 1 部屋に留まる 20 秒で毛を 1 秒に 1 本、20 本取る (実際: %s)" % str(picks),
	)
	_check(
		RobotRulesScript.picks_between(RobotRulesScript.build_route(layout, []), 0.0, 100.0).is_empty(),
		"回る順が空の掃除ロボットは毛を取らない",
	)
	var candidates: Array[Dictionary] = [
		{
			"surface_id": &"a",
			"counts": {SurfaceHairScript.COLOR_WHITE: 3, SurfaceHairScript.COLOR_BLACK: 1},
		},
		{
			"surface_id": &"b",
			"counts": {SurfaceHairScript.COLOR_WHITE: 2, SurfaceHairScript.COLOR_BLACK: 5},
		},
	]
	var empty_candidates: Array[Dictionary] = [
		{"surface_id": &"a", "counts": {SurfaceHairScript.COLOR_WHITE: 0}}
	]
	_check(
		RobotRulesScript.choose_pick(candidates)
		== {"surface_id": &"b", "color": SurfaceHairScript.COLOR_BLACK}
		and RobotRulesScript.choose_pick(empty_candidates).is_empty(),
		"掃除ロボットは残りがいちばん多い面のいちばん多い色の毛を取り、毛が無ければ何も取らない",
	)
	_check(
		is_equal_approx(RobotRulesScript.robot_time(0, 10.0), 10.0)
		and is_equal_approx(
			RobotRulesScript.robot_time(2, 10.0), 10.0 + RobotRulesScript.PHASE_STEP_SECONDS * 2.0
		),
		"2 台目以降の掃除ロボットは 5 秒ずつずらして動く",
	)
	state.free()


## GameState の時計を進めると、猫が通り道の面に毛を落とし (面の上限まで)、時間の刻み方で落ちる量が変わらないか
func _check_game_state_cats() -> void:
	var stepped: Node = GameStateScript.new()
	stepped.initialize_from_storage(TEST_SAVE_PATH, PackedStringArray(["--hair-count=300"]))
	var whole: Node = GameStateScript.new()
	whole.initialize_from_storage(TEST_SAVE_PATH, PackedStringArray(["--hair-count=300"]))
	var before: int = whole.get_total_remaining_hairs()
	var notified: Array[int] = [0, 0]
	whole.state_changed.connect(func() -> void: notified[0] += 1)
	whole.automation_advanced.connect(func(_changes: Dictionary) -> void: notified[1] += 1)
	var changes: Dictionary = whole.automation.advance(30.0)
	var dropped: int = 0
	for drop: Dictionary in changes["drops"]:
		dropped += int(drop["count"])
	for _step: int in range(300):
		stepped.automation.advance(0.1)
	_check(
		dropped > 0
		and whole.get_total_remaining_hairs() == before + dropped
		and stepped.get_total_remaining_hairs() == whole.get_total_remaining_hairs()
		and changes["picks"].is_empty()
		and notified == [1, 1],
		(
			"時計を 30 秒進めると猫が毛を落として屋敷の毛が落ちた本数だけ増え、"
			+ "0.1 秒ずつ 300 回進めても同じ本数になり、通知は 1 回ずつ "
			+ "(落ちた本数: %d / まとめて: %d / 刻んで: %d / 通知: %s)"
		)
		% [
			dropped, whole.get_total_remaining_hairs(), stepped.get_total_remaining_hairs(),
			str(notified)
		],
	)
	_check(
		is_equal_approx(whole.automation.get_seconds(), 30.0)
		and whole.automation.advance(0.0)["drops"].is_empty()
		and whole.automation.advance(-5.0)["drops"].is_empty()
		and is_equal_approx(whole.automation.get_seconds(), 30.0),
		"時計は進めた秒数だけ進み、0 秒・負の秒数では進まず毛も落ちない",
	)
	var route: Dictionary = whole.automation.get_cat_routes()[0]
	var nap_surface_id: StringName = route["stops"][route["stops"].size() - 1]["surface_id"]
	var nap_surface: SurfaceHair = whole.save_data.building_progress.find_surface_hair(nap_surface_id)
	var cap: int = maxi(
		int(whole.automation.get_initial_surface_hairs(nap_surface_id)), CatRulesScript.MIN_SURFACE_CAP
	)
	nap_surface.hair_counts[SurfaceHairScript.COLOR_WHITE] = (
		nap_surface.count_for_color(SurfaceHairScript.COLOR_WHITE) + cap - nap_surface.total_count()
	)
	whole.automation.advance(float(route["cycle_seconds"]) * 3.0)
	_check(
		nap_surface.total_count() == cap,
		"上限まで毛が溜まった面には、猫が何巡しても毛が増えない (上限: %d / 実際: %d)"
		% [cap, nap_surface.total_count()],
	)
	stepped.free()
	whole.free()


## 掃除ロボットを買う・回る順を変える入口と、回る部屋の床とカーペットから毛を取って在庫に入れることを確かめる
func _check_game_state_robots() -> void:
	var state: Node = GameStateScript.new()
	state.initialize_from_storage(TEST_SAVE_PATH, PackedStringArray(["--hair-count=300"]))
	var automation: RefCounted = state.automation
	var layout: MansionLayout = state.current_layout
	var first: StringName = layout.rooms[0].room_id
	var second: StringName = layout.rooms[1].room_id
	_check(
		not automation.buy_robot(first) and automation.get_robots().is_empty() and state.get_money() == 0,
		"はじめからの 0 円では掃除ロボットを買えない",
	)
	state.save_data.building_progress.money = RobotRulesScript.ROBOT_PRICE - 1
	_check(not automation.buy_robot(first), "値段 300 円に 1 円足りない時は掃除ロボットを買えない")
	state.save_data.building_progress.money = RobotRulesScript.ROBOT_PRICE
	_check(
		not automation.buy_robot(&"no_such_room")
		and state.get_money() == RobotRulesScript.ROBOT_PRICE,
		"屋敷に無い部屋を回る掃除ロボットは買えず、お金も減らない",
	)
	var bought: bool = automation.buy_robot(first)
	var robots: Array[OwnedTool] = automation.get_robots()
	_check(
		bought and state.get_money() == 0 and robots.size() == 1
		and robots[0].tool_id == RobotRulesScript.ROBOT_TOOL_ID
		and robots[0].robot_room_ids == [first],
		"300 円で掃除ロボットを 1 台買うと所持金が 0 円になり、買った部屋だけを回る順で置かれる",
	)
	state.save_data.building_progress.money = RobotRulesScript.ROBOT_PRICE * 10
	for _extra: int in range(RobotRulesScript.MAX_ROBOTS + 1):
		automation.buy_robot(first)
	_check(
		automation.get_robots().size() == RobotRulesScript.MAX_ROBOTS,
		"掃除ロボットは上限の 4 台までしか買えない (実際: %d 台)" % automation.get_robots().size(),
	)
	var duplicate_route: Array[StringName] = [first, second, first]
	var unknown_route: Array[StringName] = [first, &"no_such_room"]
	var good_route: Array[StringName] = [second, first]
	var empty_route: Array[StringName] = []
	_check(
		not automation.set_robot_route(0, duplicate_route)
		and not automation.set_robot_route(0, unknown_route)
		and not automation.set_robot_route(RobotRulesScript.MAX_ROBOTS, good_route)
		and automation.get_robots()[0].robot_room_ids == [first],
		"同じ部屋が 2 回ある順・屋敷に無い部屋の順・無い台への順は受け付けず、回る順が変わらない",
	)
	_check(
		automation.set_robot_route(0, good_route)
		and automation.get_robots()[0].robot_room_ids == good_route
		and automation.set_robot_route(1, empty_route)
		and automation.get_robots()[1].robot_room_ids.is_empty(),
		"回る順は部屋を並べ替えて決められ、空にすると止まる",
	)
	state.free()

	var cleaner: Node = GameStateScript.new()
	# 1 部屋の床とカーペットに、20 秒で取る 20 本より多く毛がある本数
	cleaner.initialize_from_storage(TEST_SAVE_PATH, PackedStringArray(["--hair-count=3000"]))
	var cleaner_automation: RefCounted = cleaner.automation
	cleaner.save_data.building_progress.money = RobotRulesScript.ROBOT_PRICE
	cleaner_automation.buy_robot(cleaner.current_layout.rooms[0].room_id)
	var before_hairs: int = cleaner.get_total_remaining_hairs()
	var before_stock: int = cleaner.get_raw_hair_stock_count()
	var changes: Dictionary = cleaner_automation.advance(RobotRulesScript.ROOM_SECONDS)
	var picked: int = 0
	var picked_types_ok: bool = true
	for pick: Dictionary in changes["picks"]:
		picked += int(pick["count"])
		var surface_def: MansionLayout.SurfaceDef = cleaner.current_layout.find_surface(
			pick["surface_id"]
		)
		picked_types_ok = (
			picked_types_ok and surface_def != null
			and surface_def.room_id == cleaner.current_layout.rooms[0].room_id
			and surface_def.surface_type in RobotRulesScript.CLEAN_SURFACE_TYPES
		)
	var dropped: int = 0
	for drop: Dictionary in changes["drops"]:
		dropped += int(drop["count"])
	_check(
		picked == 20 and picked_types_ok
		and cleaner.get_raw_hair_stock_count() == before_stock + picked
		and cleaner.get_total_remaining_hairs() == before_hairs + dropped - picked,
		(
			"掃除ロボットは回る部屋に 20 秒留まる間に床とカーペットから毛を 20 本取り、在庫が 20 本増え、"
			+ "屋敷の毛は猫が落とした分を足して 20 本減る (取った: %d / 在庫の増え: %d)"
		)
		% [picked, cleaner.get_raw_hair_stock_count() - before_stock],
	)
	cleaner.free()


## ブラシで猫をブラッシングすると落ちる前の毛が在庫に入り、休んでいる間は毛を落とさず、ブラシもかけられないか
func _check_game_state_brush() -> void:
	var state: Node = GameStateScript.new()
	state.initialize_from_storage(TEST_SAVE_PATH, PackedStringArray(["--hair-count=300"]))
	var automation: RefCounted = state.automation
	var cat_id: StringName = automation.get_cat_routes()[0]["cat_id"]
	_check(
		automation.brush_cat(cat_id) == 0 and state.get_raw_hair_stock_count() == 0,
		"ブラシを持っていない時は猫をブラッシングできない",
	)
	state.save_data.building_progress.money = 9999
	state.purchase(GameStateScript.PURCHASE_TOOL, ToolCatalogScript.TOOL_BRUSH)
	var stock_before: int = state.get_raw_hair_stock_count()
	_check(
		automation.brush_cat(&"no_such_cat") == 0 and state.get_raw_hair_stock_count() == stock_before,
		"いない猫はブラッシングできない",
	)
	var taken: int = automation.brush_cat(cat_id)
	var white_raw: int = 0
	for stock: HairStock in state.save_data.building_progress.hair_stocks:
		if stock.form == HairStockScript.FORM_RAW and stock.hair_color == SurfaceHairScript.COLOR_WHITE:
			white_raw += stock.count
	_check(
		taken == CatRulesScript.BRUSH_HAIRS
		and state.get_raw_hair_stock_count() == stock_before + CatRulesScript.BRUSH_HAIRS
		and white_raw == CatRulesScript.BRUSH_HAIRS
		and automation.is_cat_resting(cat_id),
		"白い猫をブラッシングすると白い毛 5 本が在庫に入り、猫は休みに入る",
	)
	_check(
		automation.brush_cat(cat_id) == 0
		and state.get_raw_hair_stock_count() == stock_before + CatRulesScript.BRUSH_HAIRS,
		"休んでいる猫にはもう一度ブラシをかけられない",
	)
	var resting_drops: Dictionary = automation.advance(CatRulesScript.BRUSH_REST_SECONDS - 0.5)
	var brushed_cat_dropped: bool = false
	for drop: Dictionary in resting_drops["drops"]:
		brushed_cat_dropped = brushed_cat_dropped or drop["cat_id"] == cat_id
	_check(
		not brushed_cat_dropped and not resting_drops["drops"].is_empty(),
		"ブラッシングした猫は休んでいる 10 秒の間は毛を落とさず、ほかの猫は落とす",
	)
	automation.advance(1.0)
	_check(
		not automation.is_cat_resting(cat_id)
		and automation.brush_cat(cat_id) == CatRulesScript.BRUSH_HAIRS,
		"休み終わった猫にはまたブラシをかけられる",
	)
	state.free()


## 部屋 1 つと物 2 つ (ソファ・カーペット) の作った屋敷で、家具と壁際の判定、家具を避けて立ち止まる所、
## 部屋を歩く順を、座標の決まった入力で確かめる
func _check_layout_geometry() -> void:
	var layout: MansionLayout = MansionLayout.new()
	for grid: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]:
		var room: MansionLayout.RoomDef = MansionLayout.RoomDef.new()
		room.room_id = StringName("room_%d_%d" % [grid.x, grid.y])
		room.grid_x = grid.x
		room.grid_z = grid.y
		room.center = Vector3(float(grid.x) * 6.0, 0.0, -float(grid.y) * 6.0)
		room.size = Vector3(6.0, 3.0, 6.0)
		layout.rooms.append(room)
	var sofa: MansionLayout.ObjectDef = MansionLayout.ObjectDef.new()
	sofa.room_id = &"room_0_0"
	sofa.object_kind = MansionLayoutScript.OBJECT_SOFA
	sofa.position = Vector3(1.0, 0.0, 1.0)
	sofa.size = Vector3(1.0, 1.0, 1.0)
	layout.objects.append(sofa)
	var carpet: MansionLayout.ObjectDef = MansionLayout.ObjectDef.new()
	carpet.room_id = &"room_0_0"
	carpet.object_kind = MansionLayoutScript.OBJECT_CARPET
	carpet.position = Vector3(-1.0, 0.0, -1.0)
	carpet.size = Vector3(2.0, 0.02, 2.0)
	layout.objects.append(carpet)
	_check(
		CatRulesScript.is_blocked(layout, &"room_0_0", Vector3(1.0, 0.0, 1.0))
		and CatRulesScript.is_blocked(layout, &"room_0_0", Vector3(1.75, 0.0, 1.0))
		and not CatRulesScript.is_blocked(layout, &"room_0_0", Vector3(1.85, 0.0, 1.0))
		and CatRulesScript.is_blocked(layout, &"room_0_0", Vector3(2.75, 0.0, -2.0))
		and not CatRulesScript.is_blocked(layout, &"room_0_0", Vector3(2.65, 0.0, -2.0))
		and not CatRulesScript.is_blocked(layout, &"room_0_0", Vector3(-1.0, 0.0, -1.0))
		and CatRulesScript.is_blocked(layout, &"room_0_0", Vector3(-2.0, 0.0, 2.75))
		and not CatRulesScript.is_blocked(layout, &"room_0_0", Vector3(-2.0, 0.0, 2.65))
		and not CatRulesScript.is_blocked(layout, &"room_0_0", Vector3(1.0, 0.0, -0.5)),
		"家具の判定は 1 m のソファの中心と縁から 25 cm を塞ぎ 35 cm は通し、X・Z どちらの壁からも 25 cm を塞ぎ"
		+ " 35 cm は通し、X だけソファの幅に入る所と上に乗れるカーペットは塞がない",
	)
	var spot: Vector3 = CatRulesScript.free_point(layout, layout.rooms[0], Vector2(1.0, 1.0))
	_check(
		not CatRulesScript.is_blocked(layout, &"room_0_0", spot)
		and spot.is_equal_approx(Vector3(-1.0, 0.0, 1.0)),
		"ソファに重なる立ち止まる所 (1, 1) は 90 度回した (-1, 1) にずらす (実際: %s)" % str(spot),
	)
	var crowded: MansionLayout.ObjectDef = MansionLayout.ObjectDef.new()
	crowded.room_id = &"room_1_0"
	crowded.object_kind = MansionLayoutScript.OBJECT_TABLE
	crowded.position = Vector3(6.0, 0.0, 0.0)
	crowded.size = Vector3(4.0, 1.0, 4.0)
	layout.objects.append(crowded)
	_check(
		CatRulesScript.free_point(layout, layout.rooms[1], Vector2(1.0, 1.0)).is_equal_approx(
			layout.rooms[1].center
		),
		"どの向きもずれを半分にしても家具に重なる部屋では、部屋の中心で立ち止まる",
	)
	_check(
		CatRulesScript.walk_order(layout, 1) == [1, 0, 2]
		and CatRulesScript.walk_order(layout, 2) == [2, 0, 1]
		and CatRulesScript.walk_order(MansionLayout.new(), 0).is_empty(),
		"部屋は隣り合う部屋へ進み、隣が通った部屋だけの時は添字の小さい残りの部屋へ移る (部屋が無ければ空)",
	)


## 掃除ロボットの位置が、部屋へ移る途中は前の部屋との間、着いた後は部屋の中心の周りの 8 の字の輪の上にあり、
## 回る部屋が無ければ原点か
func _check_robot_position() -> void:
	var stops: Array[Dictionary] = [
		{"point": Vector3(0.0, 0.0, 0.0), "seconds": 20.0, "room_id": &"a"},
		{"point": Vector3(6.0, 0.0, 0.0), "seconds": 20.0, "room_id": &"b"},
	]
	var route: Dictionary = RouteClockScript.make_route(stops)
	var sizes: Dictionary = {&"a": Vector3(6.0, 3.0, 4.0), &"b": Vector3(6.0, 3.0, 4.0)}
	var moving: Vector3 = RobotRulesScript.position_at(
		route, 20.0 + RouteClockScript.MOVE_SECONDS * 0.5, sizes
	)
	var quarter: Vector3 = RobotRulesScript.position_at(
		route, 20.0 + RouteClockScript.MOVE_SECONDS + RobotRulesScript.LOOP_SECONDS * 0.25, sizes
	)
	var three_quarter: Vector3 = RobotRulesScript.position_at(
		route, 20.0 + RouteClockScript.MOVE_SECONDS + RobotRulesScript.LOOP_SECONDS * 0.75, sizes
	)
	var eighth: Vector3 = RobotRulesScript.position_at(
		route, 20.0 + RouteClockScript.MOVE_SECONDS + RobotRulesScript.LOOP_SECONDS * 0.125, sizes
	)
	var before_leaving: Vector3 = RobotRulesScript.position_at(route, 39.999, sizes)
	_check(
		before_leaving.distance_to(Vector3(6.0, 0.0, 0.0)) < 0.01,
		"掃除ロボットは部屋を出る直前に輪を回り終えて部屋の中心へ戻り、次の部屋へ跳ばずに移り出す (実際: %s)"
		% str(before_leaving),
	)
	var reach_x: float = 3.0 * RobotRulesScript.LOOP_RATIO
	_check(
		moving.is_equal_approx(Vector3(3.0, 0.0, 0.0))
		and quarter.is_equal_approx(Vector3(6.0 + reach_x, 0.0, 0.0))
		and three_quarter.is_equal_approx(Vector3(6.0 - reach_x, 0.0, 0.0))
		and absf(eighth.z) > 0.1
		and RobotRulesScript.position_at(RouteClockScript.make_route([]), 5.0, sizes) == Vector3.ZERO,
		(
			"掃除ロボットは移る途中に部屋の間、着いた後は中心から左右に部屋の半幅の 55%% まで 8 の字に走り、"
			+ "回る部屋が無ければ原点 (途中: %s / 4 分の 1 周: %s / 4 分の 3 周: %s)"
		) % [str(moving), str(quarter), str(three_quarter)],
	)


## 屋敷を組み直すと猫と掃除ロボットの時計と休みが 0 に戻り、読み込み前と負の台の入口は何も変えないか
func _check_automation_reset() -> void:
	var fresh: Node = GameStateScript.new()
	_check(
		fresh.automation.advance(10.0)["drops"].is_empty()
		and is_equal_approx(fresh.automation.get_seconds(), 0.0),
		"保存データを読む前は時計が進まず、毛も落ちない",
	)
	fresh.free()
	var state: Node = GameStateScript.new()
	state.initialize_from_storage(TEST_SAVE_PATH, PackedStringArray(["--hair-count=300"]))
	var automation: RefCounted = state.automation
	state.save_data.building_progress.money = 9999
	state.purchase(GameStateScript.PURCHASE_TOOL, ToolCatalogScript.TOOL_BRUSH)
	var cat_id: StringName = automation.get_cat_routes()[0]["cat_id"]
	automation.advance(7.0)
	automation.brush_cat(cat_id)
	automation.buy_robot(state.current_layout.rooms[0].room_id)
	var room_ids: Array[StringName] = [state.current_layout.rooms[0].room_id]
	_check(
		not automation.set_robot_route(-1, room_ids),
		"負の台の添字では回る順を変えない",
	)
	state.apply_tuning_and_rebuild(state.get_tuning().duplicate(), false)
	_check(
		is_equal_approx(automation.get_seconds(), 0.0) and not automation.is_cat_resting(cat_id),
		"屋敷を組み直すと時計が 0 に戻り、ブラッシングの後の休みも消える",
	)
	state.free()


## 毛を足す入口が、0 本の面にも足せて、枠を超えると広げても前の毛の位置と色を保ち、面の矩形の中に置くか
func _check_hair_field_add() -> void:
	var field: Node3D = HairFieldScript.new()
	field.add_surface("floor", Vector3(-1.0, 0.0, -1.0), Vector3(1.0, 0.0, 1.0), 1.0)
	var counts: Array[PackedInt32Array] = [PackedInt32Array([0, 0, 0])]
	field.populate_with_group_counts(counts, 3)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 5
	var center: Vector3 = Vector3(0.2, 0.0, -0.3)
	var first_id: int = HairFieldScript.add_hair(field, 0, center, 0.1, 1, rng)
	var first_near: PackedInt32Array = field.find_hairs_near(0, center, 0.11, 10)
	var added: int = 1
	for _i: int in range(39):
		if HairFieldScript.add_hair(field, 0, center, 0.1, 1, rng) != HairFieldScript.INVALID_SLOT:
			added += 1
	_check(
		first_id != HairFieldScript.INVALID_SLOT
		and first_near.size() == 1
		and added == 40
		and field.get_remaining_count() == 40
		and HairFieldScript.count_surface_groups(field, 0) == PackedInt32Array([0, 40, 0])
		and field.find_hairs_near(0, center, 0.11, 100).size() == 40
		and field.find_hairs_near(0, center, 0.11, 100).has(first_id),
		"0 本の面に黒の毛を 40 本足すと、枠を広げても 40 本すべてが足した所から 10 cm の中に黒で残り、"
		+ "最初の毛も同じ所にある (足せた本数: %d / 残り: %d)" % [added, field.get_remaining_count()],
	)
	HairFieldScript.add_hair(field, 0, Vector3(5.0, 0.0, 5.0), 0.0, 0, rng)
	_check(
		field.find_hairs_near(0, Vector3(1.0, 0.0, 1.0), 0.01, 10).size() == 1
		and HairFieldScript.add_hair(field, 3, center, 0.1, 0, rng) == HairFieldScript.INVALID_SLOT
		and HairFieldScript.add_hair(field, -1, center, 0.1, 0, rng) == HairFieldScript.INVALID_SLOT
		and field.get_remaining_count() == 41,
		"面の外の所に足す毛は面の角に収め、無い面には足さない",
	)
	field.free()
	var excluded_field: Node3D = HairFieldScript.new()
	# 面の右半分 (x > 0) を毛を置かない範囲にする
	var exclusions: Array[Dictionary] = [{
		"inverse": Transform3D(Basis.IDENTITY, Vector3(0.5, 0.0, 0.0)).affine_inverse(),
		"half": Vector2(0.5, 0.5),
	}]
	excluded_field.add_oriented_surface(
		"floor", Transform3D(HairFieldScript.UPWARD_BASIS, Vector3.ZERO), Vector2(2.0, 1.0), 1.0,
		exclusions
	)
	excluded_field.populate_with_group_counts(counts, 3)
	for _i: int in range(30):
		HairFieldScript.add_hair(excluded_field, 0, Vector3(0.05, 0.0, 0.0), 0.4, 0, rng)
	# 置いた毛の位置は CPU 側の配列 (MultiMesh と同じ値) から読む
	var bucket: Dictionary = excluded_field._buckets[0]
	var inside: int = 0
	for slot: int in range((bucket["multimesh"] as MultiMesh).visible_instance_count):
		if (bucket["transforms"][slot] as Transform3D).origin.x >= 0.0:
			inside += 1
	_check(
		excluded_field.get_remaining_count() == 30 and inside == 0,
		"毛を置かない範囲 (家具の下) に掛かる所に足す毛は、範囲の外へ置き直す (範囲の中の本数: %d)" % inside,
	)
	excluded_field.free()


## 猫が毛を落とす面が上限に達していて掃除ロボットが同じ部屋で取る時も、時間の刻み方で本数と在庫が変わらないか
## (取った後に空いた分へ、後の時刻に落ちる毛が入る)
func _check_capped_order() -> void:
	var results: Array[String] = []
	# 刻みは 2 進数で割り切れる値にし、足し合わせた時計がちょうど 60 秒になるようにする
	for step: float in [60.0, 1.0, 0.25]:
		var state: Node = GameStateScript.new()
		state.initialize_from_storage(TEST_SAVE_PATH, PackedStringArray(["--hair-count=300"]))
		var automation: RefCounted = state.automation
		for route: Dictionary in automation.get_cat_routes():
			for stop: Dictionary in route["stops"]:
				var surface: SurfaceHair = state.save_data.building_progress.find_surface_hair(
					stop["surface_id"]
				)
				var cap: int = maxi(
					automation.get_initial_surface_hairs(stop["surface_id"]),
					CatRulesScript.MIN_SURFACE_CAP,
				)
				surface.hair_counts[SurfaceHairScript.COLOR_WHITE] = (
					surface.count_for_color(SurfaceHairScript.COLOR_WHITE) + cap - surface.total_count()
				)
		state.save_data.building_progress.money = RobotRulesScript.ROBOT_PRICE
		automation.buy_robot(automation.get_cat_routes()[0]["stops"][0]["room_id"])
		for _i: int in range(roundi(60.0 / step)):
			automation.advance(step)
		results.append(
			"%d/%d" % [state.get_total_remaining_hairs(), state.get_raw_hair_stock_count()]
		)
		state.free()
	_check(
		results[0] == results[1] and results[1] == results[2],
		"上限の面で猫と掃除ロボットが同じ部屋にいても、60 秒を 1 回・1 秒ずつ・0.25 秒ずつ進めた本数と在庫が同じ"
		+ " (残り/在庫: %s)" % str(results),
	)


## 猫の足元の面 (カーペットの上ならカーペット、外と片方の軸だけ入る所は床) と、昼寝の面 (上を向いたソファを
## カーペットより先に選び、上を向いていないソファの面は選ばず、どちらも無ければ null) を、座標の決まった屋敷で確かめる。
## 回転した家具が向きどおりの範囲を塞ぐことも確かめる
func _check_surface_choice() -> void:
	var layout: MansionLayout = MansionLayout.new()
	var room: MansionLayout.RoomDef = MansionLayout.RoomDef.new()
	room.room_id = &"r"
	room.size = Vector3(6.0, 3.0, 6.0)
	layout.rooms.append(room)
	var floor_surface: MansionLayout.SurfaceDef = _surface(&"floor", MansionLayoutScript.SURFACE_FLOOR)
	floor_surface.extents = Vector2(6.0, 6.0)
	var carpet: MansionLayout.SurfaceDef = _surface(&"carpet", MansionLayoutScript.SURFACE_CARPET)
	carpet.center = Vector3(1.0, 0.02, 1.0)
	carpet.extents = Vector2(2.0, 1.0)
	layout.surfaces.append(floor_surface)
	layout.surfaces.append(carpet)
	var under: Array[StringName] = []
	for point: Vector3 in [
		Vector3(1.5, 0.0, 1.2), Vector3(-1.0, 0.0, -1.0), Vector3(1.5, 0.0, 2.0), Vector3(2.5, 0.0, 1.2)
	]:
		under.append(CatRulesScript.surface_under(layout, &"r", point).surface_id)
	_check(
		under == [&"carpet", &"floor", &"floor", &"floor"],
		"猫の足元はカーペットの中ならカーペット、外・X だけ入る所・Z だけ入る所は床 (実際: %s)" % str(under),
	)
	_check(
		CatRulesScript.nap_surface_for(layout, 0) == carpet,
		"ソファが無い屋敷では、上を向いたカーペットで昼寝する",
	)
	var sofa_back: MansionLayout.SurfaceDef = _surface(&"sofa_back", MansionLayoutScript.SURFACE_SOFA)
	sofa_back.basis = Basis(Vector3.RIGHT, PI * 0.5)
	layout.surfaces.append(sofa_back)
	_check(
		CatRulesScript.nap_surface_for(layout, 0) == carpet,
		"上を向いていないソファの面 (背もたれ) では昼寝せず、カーペットを選ぶ",
	)
	var sofa_seat: MansionLayout.SurfaceDef = _surface(&"sofa_seat", MansionLayoutScript.SURFACE_SOFA)
	layout.surfaces.append(sofa_seat)
	_check(
		CatRulesScript.nap_surface_for(layout, 0) == sofa_seat,
		"上を向いたソファの座面があれば、カーペットより先にソファで昼寝する",
	)
	var bare: MansionLayout = MansionLayout.new()
	bare.rooms.append(room)
	bare.surfaces.append(floor_surface)
	_check(
		CatRulesScript.nap_surface_for(bare, 0) == null,
		"ソファもカーペットも無い屋敷では昼寝の面が無い (null)",
	)
	var turned: MansionLayout.ObjectDef = MansionLayout.ObjectDef.new()
	turned.room_id = &"r"
	turned.object_kind = MansionLayoutScript.OBJECT_TABLE
	turned.size = Vector3(2.0, 1.0, 0.2)
	turned.rotation_y = PI * 0.5
	layout.objects.append(turned)
	_check(
		CatRulesScript.is_blocked(layout, &"r", Vector3(0.0, 0.0, 0.9))
		and not CatRulesScript.is_blocked(layout, &"r", Vector3(0.9, 0.0, 0.0)),
		"90 度回した細長い家具は、回した向き (Z) の範囲を塞ぎ、回す前の向き (X) の範囲は塞がない",
	)


## 部屋が 0 の屋敷・留まる秒数の合計が 0 の道のりでは、通り道も留まる所も出来事も無いか
func _check_empty_inputs() -> void:
	var zero_route: Dictionary = RouteClockScript.make_route([
		{"point": Vector3.ZERO, "seconds": 0.0}, {"point": Vector3.ONE, "seconds": 0.0}
	])
	_check(
		CatRulesScript.build_routes(MansionLayout.new()).is_empty()
		and RouteClockScript.stop_index_at(zero_route, 3.0) == -1
		and RouteClockScript.ticks_between(zero_route, 0.0, 10.0, 1.0).is_empty(),
		"部屋が 0 の屋敷では猫の通り道を作らず、留まる秒数の合計が 0 の道のりでは留まる所も出来事も無い",
	)


## 猫が毛を落とさず掃除ロボットが毛を取るだけの間も、state_changed と automation_advanced が 1 回ずつ通知されるか
func _check_picks_only_notify() -> void:
	var state: Node = GameStateScript.new()
	state.initialize_from_storage(TEST_SAVE_PATH, PackedStringArray(["--hair-count=3000"]))
	var automation: RefCounted = state.automation
	state.save_data.building_progress.money = 9999
	state.purchase(GameStateScript.PURCHASE_TOOL, ToolCatalogScript.TOOL_BRUSH)
	for route: Dictionary in automation.get_cat_routes():
		automation.brush_cat(route["cat_id"])
	automation.buy_robot(state.current_layout.rooms[0].room_id)
	var notified: Array[int] = [0, 0]
	state.state_changed.connect(func() -> void: notified[0] += 1)
	state.automation_advanced.connect(func(_changes: Dictionary) -> void: notified[1] += 1)
	var changes: Dictionary = automation.advance(CatRulesScript.BRUSH_REST_SECONDS - 1.0)
	_check(
		changes["drops"].is_empty() and not changes["picks"].is_empty() and notified == [1, 1],
		"猫が全員休んでいて掃除ロボットだけが毛を取った時も、通知が 1 回ずつ出る (通知: %s)" % str(notified),
	)
	state.free()


## 部屋 r の、中心が原点で上を向いた幅 1 m の面 (検証用)
static func _surface(surface_id: StringName, surface_type: StringName) -> MansionLayout.SurfaceDef:
	var surface: MansionLayout.SurfaceDef = MansionLayout.SurfaceDef.new()
	surface.surface_id = surface_id
	surface.room_id = &"r"
	surface.surface_type = surface_type
	return surface


## 撮影で立つ所が、望む向きが塞がれていれば次の向きへ回り、望む向きが水平に決まらない時は後ろ (+Z) を使い、
## どの向きも塞がる時は望む向きの所を返すか
func _check_view_point() -> void:
	var layout: MansionLayout = MansionLayout.new()
	var room: MansionLayout.RoomDef = MansionLayout.RoomDef.new()
	room.room_id = &"r"
	room.size = Vector3(6.0, 3.0, 6.0)
	layout.rooms.append(room)
	var open_spot: Vector3 = ViewPointScript.clear_spot(layout, room, Vector3.ZERO, 1.0, Vector3.UP)
	var shelf: MansionLayout.ObjectDef = MansionLayout.ObjectDef.new()
	shelf.room_id = &"r"
	shelf.object_kind = MansionLayoutScript.OBJECT_TABLE
	shelf.position = Vector3(1.0, 0.0, 0.0)
	shelf.size = Vector3(0.2, 1.0, 0.2)
	layout.objects.append(shelf)
	var turned_spot: Vector3 = ViewPointScript.clear_spot(
		layout, room, Vector3.ZERO, 1.0, Vector3.RIGHT
	)
	var crowded: MansionLayout.ObjectDef = MansionLayout.ObjectDef.new()
	crowded.room_id = &"r"
	crowded.object_kind = MansionLayoutScript.OBJECT_TABLE
	crowded.size = Vector3(5.0, 1.0, 5.0)
	layout.objects.append(crowded)
	var blocked_spot: Vector3 = ViewPointScript.clear_spot(
		layout, room, Vector3.ZERO, 1.0, Vector3.RIGHT
	)
	_check(
		open_spot.is_equal_approx(Vector3(0.0, 0.0, 1.0))
		and turned_spot.is_equal_approx(Vector3(1.0, 0.0, -1.0).normalized())
		and blocked_spot.is_equal_approx(Vector3(1.0, 0.0, 0.0)),
		"真上を望むと後ろに立ち、右が家具で塞がれば 45 度回した所に立ち、どこも塞がれば望む右に立つ"
		+ " (後ろ: %s / 回した所: %s / 塞がる時: %s)" % [open_spot, turned_spot, blocked_spot],
	)


## 斜めに離れた部屋 (隣り合わない部屋) へ移る掃除ロボットが、壁を通らずドアの開口部を通って移るか。
## 移る途中の位置を細かく見て、どの位置もどれかの部屋の中にあり、部屋が変わる所が隣り合う部屋のドアの幅の中か
func _check_door_path() -> void:
	var layout: MansionLayout = MansionLayout.new()
	for grid: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]:
		var room: MansionLayout.RoomDef = MansionLayout.RoomDef.new()
		room.room_id = StringName("room_%d_%d" % [grid.x, grid.y])
		room.grid_x = grid.x
		room.grid_z = grid.y
		room.center = Vector3(float(grid.x) * 6.0, 0.0, -float(grid.y) * 6.0)
		room.size = Vector3(6.0, 3.0, 6.0)
		layout.rooms.append(room)
	var room_ids: Array[StringName] = [&"room_1_0", &"room_0_1"]
	var route: Dictionary = RobotRulesScript.build_route(layout, room_ids)
	var problems: Array[String] = []
	var previous_room: MansionLayout.RoomDef = null
	var previous_point: Vector3 = Vector3.ZERO
	var samples: int = 200
	for sample: int in range(samples + 1):
		var point: Vector3 = RouteClockScript.position_at(
			route,
			RobotRulesScript.ROOM_SECONDS + RouteClockScript.MOVE_SECONDS * float(sample) / float(samples),
		)
		var here: MansionLayout.RoomDef = null
		for room: MansionLayout.RoomDef in layout.rooms:
			if (
				absf(point.x - room.center.x) <= room.size.x * 0.5
				and absf(point.z - room.center.z) <= room.size.z * 0.5
			):
				here = room
		if here == null:
			problems.append("部屋の外 %s" % str(point))
		elif previous_room != null and here != previous_room:
			var door: Vector3 = (previous_room.center + here.center) * 0.5
			if (
				absi(here.grid_x - previous_room.grid_x) + absi(here.grid_z - previous_room.grid_z) != 1
				or previous_point.lerp(point, 0.5).distance_to(door)
				> MansionLayoutScript.DOOR_WIDTH_M * 0.5
			):
				problems.append("壁を通る %s → %s" % [str(previous_point), str(point)])
		previous_room = here
		previous_point = point
	_check(
		problems.is_empty()
		and RouteClockScript.position_at(route, RobotRulesScript.ROOM_SECONDS).is_equal_approx(
			Vector3(6.0, 0.0, 0.0)
		)
		and RouteClockScript.position_at(
			route, RobotRulesScript.ROOM_SECONDS + RouteClockScript.MOVE_SECONDS
		).is_equal_approx(Vector3(0.0, 0.0, -6.0)),
		"斜めに離れた部屋へ移る掃除ロボットは、壁を通らずドアを通って移り、前の部屋の中心から次の部屋の中心に着く"
		+ " (問題: %s)" % str(problems),
	)

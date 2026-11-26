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
				var nap_surface: MansionLayout.SurfaceDef = _find_surface(layout, stop["surface_id"])
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
		var surface_def: MansionLayout.SurfaceDef = _find_surface(
			cleaner.current_layout, pick["surface_id"]
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


## layout の面のうち surface_id の面 (無ければ null)
static func _find_surface(
	layout: MansionLayout, surface_id: StringName
) -> MansionLayout.SurfaceDef:
	for surface: MansionLayout.SurfaceDef in layout.surfaces:
		if surface.surface_id == surface_id:
			return surface
	return null

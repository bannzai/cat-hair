extends RefCounted
## GameState が持つ、猫と掃除ロボットの状態と入口 (GameState.automation)。
## 本数・お金・買った掃除ロボットの正は GameState の保存データで、ここが持つのは保存しない状態 (時計・猫の通り道・
## ブラッシングの後で休み終わる時刻・面ごとの最初の毛の本数) だけ。ゲームを閉じている間の進行は作らないため、
## 時計は起動のたびと屋敷を組み直すたびに 0 から始める (猫は通り道の最初の所、掃除ロボットは回る順の最初の部屋から動き出す)。

## 買った道具 1 つのデータ型スクリプト
const OwnedToolScript := preload("res://scripts/data/owned_tool.gd")
## 手に持って使う道具の定義 (ブラシの id)
const ToolCatalogScript := preload("res://scripts/tools/tool_catalog.gd")
## 猫の通り道・毛を落とす量・ブラッシングの計算
const CatRulesScript := preload("res://scripts/automation/cat_rules.gd")
## 掃除ロボットの値段・回る順・毛を取る量の計算
const RobotRulesScript := preload("res://scripts/automation/robot_rules.gd")

## 保存データ・屋敷の作り・お金と在庫の入口を持つ GameState (Node のため参照の循環で解放が止まらない)
var _game_state: Node = null
## 面ごとの最初の毛の本数 (surface_id -> int。猫が落とす毛の上限に使う)
var _initial_surface_hairs: Dictionary = {}
## 猫ごとの通り道 (CatRules.build_routes の戻り値)
var _cat_routes: Array[Dictionary] = []
## 猫と掃除ロボットの時計 (秒)。屋敷で遊んでいる間だけ進む
var _seconds: float = 0.0
## ブラッシングした猫が休み終わる時計の時刻 (cat_id -> 秒)
var _rest_until: Dictionary = {}


## game_state は持ち主の GameState
func _init(game_state: Node) -> void:
	_game_state = game_state


## 屋敷を組み直した時に、面ごとの最初の毛の本数 (surface_id -> int) と屋敷の作りから猫の通り道を求め直し、時計を 0 に戻す
func reset(layout: MansionLayout, initial_surface_hairs: Dictionary) -> void:
	_initial_surface_hairs = initial_surface_hairs.duplicate()
	_cat_routes = CatRulesScript.build_routes(layout)
	_seconds = 0.0
	_rest_until.clear()


## 時計を delta_seconds 秒進める。猫は立ち止まった面に毛を落とし (面の上限まで)、
## 掃除ロボットは回る順の今の部屋の床とカーペットから毛を取って在庫 (毛のまま) に入れる。
## 戻り値は {"drops": [{"cat_id", "surface_id", "color", "count"}],
## "picks": [{"robot_index", "surface_id", "color", "count"}]}。
## 毛が増減した時だけ GameState の state_changed と automation_advanced を 1 回ずつ通知する
func advance(delta_seconds: float) -> Dictionary:
	var changes: Dictionary = {"drops": [], "picks": []}
	if _progress() == null or _game_state.current_layout == null:
		return changes
	var before: float = _seconds
	_seconds = before + maxf(0.0, delta_seconds)
	for route: Dictionary in _cat_routes:
		_drop_cat_hairs(route, before, changes["drops"])
	var robots: Array[OwnedTool] = get_robots()
	for robot_index: int in range(robots.size()):
		_pick_robot_hairs(robot_index, robots[robot_index], before, changes["picks"])
	if not changes["drops"].is_empty() or not changes["picks"].is_empty():
		_game_state.state_changed.emit()
		_game_state.automation_advanced.emit(changes)
	return changes


## 時計 (秒) を返す
func get_seconds() -> float:
	return _seconds


## 猫ごとの通り道 (CatRules.build_routes の戻り値) を返す
func get_cat_routes() -> Array[Dictionary]:
	return _cat_routes


## 猫がブラッシングの後で休んでいる (毛を落とさず、もう一度ブラシをかけられない) か
func is_cat_resting(cat_id: StringName) -> bool:
	return CatRulesScript.is_resting(float(_rest_until.get(cat_id, -INF)), _seconds)


## ブラシで猫をブラッシングし、落ちる前の毛 (CatRules.BRUSH_HAIRS 本、猫の毛の色) を在庫 (毛のまま) に入れる。
## ブラシを持っていない・いない猫・休んでいる猫の時は何も変えずに 0 を返す。戻り値は在庫に入れた本数
func brush_cat(cat_id: StringName) -> int:
	if _game_state.find_owned_tool(ToolCatalogScript.TOOL_BRUSH) == null or is_cat_resting(cat_id):
		return 0
	for route: Dictionary in _cat_routes:
		if route["cat_id"] == cat_id:
			_game_state._add_raw_stock(route["color"], &"", CatRulesScript.BRUSH_HAIRS)
			_rest_until[cat_id] = _seconds + CatRulesScript.BRUSH_REST_SECONDS
			_game_state.state_changed.emit()
			return CatRulesScript.BRUSH_HAIRS
	return 0


## 買った掃除ロボットを買った順に返す (同じ掃除ロボットを何台も持てるため、1 台ずつ別の OwnedTool)
func get_robots() -> Array[OwnedTool]:
	var robots: Array[OwnedTool] = []
	if _progress() != null:
		for owned: OwnedTool in _progress().owned_tools:
			if owned != null and owned.tool_id == RobotRulesScript.ROBOT_TOOL_ID:
				robots.append(owned)
	return robots


## 掃除ロボットを 1 台買い、first_room_id の部屋だけを回る順にして置く。屋敷に無い部屋・上限の台数・お金が足りない時は
## 何も変えずに false
func buy_robot(first_room_id: StringName) -> bool:
	var layout: MansionLayout = _game_state.current_layout
	if (
		layout == null
		or RobotRulesScript.find_room(layout, first_room_id) == null
		or get_robots().size() >= RobotRulesScript.MAX_ROBOTS
		or not _game_state._spend(RobotRulesScript.ROBOT_PRICE)
	):
		return false
	var owned: OwnedTool = OwnedToolScript.new()
	owned.tool_id = RobotRulesScript.ROBOT_TOOL_ID
	owned.level = 1
	owned.robot_room_ids.append(first_room_id)
	_progress().owned_tools.append(owned)
	_game_state.state_changed.emit()
	return true


## robot_index 台目 (get_robots の並び) の掃除ロボットが回る部屋の順を room_ids にする。無い台・屋敷に無い部屋・
## 同じ部屋が 2 回ある順の時は何も変えずに false。空の順は止めておく (どの部屋も回らない) 意味で受け付ける
func set_robot_route(robot_index: int, room_ids: Array[StringName]) -> bool:
	var robots: Array[OwnedTool] = get_robots()
	var layout: MansionLayout = _game_state.current_layout
	if robot_index < 0 or robot_index >= robots.size() or layout == null:
		return false
	var seen: Dictionary = {}
	for room_id: StringName in room_ids:
		if seen.has(room_id) or RobotRulesScript.find_room(layout, room_id) == null:
			return false
		seen[room_id] = true
	robots[robot_index].robot_room_ids = room_ids.duplicate()
	_game_state.state_changed.emit()
	return true


## 面ごとの最初の毛の本数のうち surface_id の本数 (猫が落とす毛の上限の計算と、検証が上限を求める時に使う)
func get_initial_surface_hairs(surface_id: StringName) -> int:
	return int(_initial_surface_hairs.get(surface_id, 0))


## GameState の保存データの進行 (読み込み前は null)
func _progress() -> BuildingProgress:
	var save_data: SaveData = _game_state.save_data
	return save_data.building_progress if save_data != null else null


## 猫 1 匹の通り道で、時計の before から今までに落ちた毛を面に足し、足した分を drops に書く。
## 休んでいる間 (ブラッシングの後) の分は落とさない
func _drop_cat_hairs(route: Dictionary, before: float, drops: Array) -> void:
	var cat_id: StringName = route["cat_id"]
	var start: float = maxf(before, float(_rest_until.get(cat_id, -INF)))
	if start >= _seconds:
		return
	var color_id: StringName = route["color"]
	var by_surface: Dictionary = CatRulesScript.drops_between(route, start, _seconds)
	for surface_key: Variant in by_surface.keys():
		var surface_id: StringName = StringName(surface_key)
		var surface: SurfaceHair = _progress().find_surface_hair(surface_id)
		if surface == null:
			continue
		var count: int = mini(
			int(by_surface[surface_key]),
			CatRulesScript.room_for_drops(surface.total_count(), get_initial_surface_hairs(surface_id)),
		)
		if count <= 0:
			continue
		surface.hair_counts[color_id] = surface.count_for_color(color_id) + count
		drops.append(
			{"cat_id": cat_id, "surface_id": surface_id, "color": color_id, "count": count}
		)


## 掃除ロボット 1 台が時計の before から今までに取った毛を、回る順の部屋の床とカーペットから減らして在庫に入れ、
## 取った分を picks に書く (面と色が同じ分はまとめる)
func _pick_robot_hairs(robot_index: int, robot: OwnedTool, before: float, picks: Array) -> void:
	var layout: MansionLayout = _game_state.current_layout
	var route: Dictionary = RobotRulesScript.build_route(layout, robot.robot_room_ids)
	var by_room: Dictionary = RobotRulesScript.picks_between(
		route,
		RobotRulesScript.robot_time(robot_index, before),
		RobotRulesScript.robot_time(robot_index, _seconds),
	)
	for room_key: Variant in by_room.keys():
		var cleanable: Array[SurfaceHair] = []
		for surface_def: MansionLayout.SurfaceDef in layout.surfaces:
			if (
				surface_def.room_id == StringName(room_key)
				and surface_def.surface_type in RobotRulesScript.CLEAN_SURFACE_TYPES
			):
				var surface: SurfaceHair = _progress().find_surface_hair(surface_def.surface_id)
				if surface != null:
					cleanable.append(surface)
		# 取った本数を面の id -> 色 -> 本数でまとめる
		var taken: Dictionary = {}
		for _pick: int in range(int(by_room[room_key])):
			var candidates: Array[Dictionary] = []
			for surface: SurfaceHair in cleanable:
				candidates.append({"surface_id": surface.surface_id, "counts": surface.hair_counts})
			var pick: Dictionary = RobotRulesScript.choose_pick(candidates)
			if pick.is_empty():
				break
			var picked: SurfaceHair = _progress().find_surface_hair(pick["surface_id"])
			picked.hair_counts[pick["color"]] = picked.count_for_color(pick["color"]) - 1
			_game_state._add_raw_stock(pick["color"], &"")
			var by_color: Dictionary = taken.get_or_add(pick["surface_id"], {})
			by_color[pick["color"]] = int(by_color.get(pick["color"], 0)) + 1
		for surface_key: Variant in taken.keys():
			for color_key: Variant in taken[surface_key].keys():
				picks.append({
					"robot_index": robot_index,
					"surface_id": StringName(surface_key),
					"color": StringName(color_key),
					"count": int(taken[surface_key][color_key]),
				})

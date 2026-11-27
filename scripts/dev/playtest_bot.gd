extends RefCounted
## 自動テストプレイの bot (make simulate と make playtest が使う)。メインシーンのゲームの様子を
## playtest_bot_policy.gd の形にまとめ、方針が選んだ 1 手を本編と同じ入口 (手・道具・買う・売る・掃除ロボット) で行い、
## 1 手にかかる人の秒 (方針の *_SECONDS) だけゲームの時計を進める。毎フレームの時計は使わない
## (main.auto_advance_time と auto_advance_automation を false にしてから使う)。
## 狙いは画面中央の光線ではなく取る毛の根元を直接渡すため、家具の陰の毛にも手が届く (人より少し有利)。
## 目線は取る毛・猫・買取業者へ向け直すので、録画 (make playtest) には bot の動きが映る。

## 次の 1 手を選ぶ方針
const PolicyScript := preload("res://scripts/dev/playtest_bot_policy.gd")
## 毛の描画・管理 (描いている毛の本数の合計を使う)
const HairFieldScript := preload("res://scripts/hair_field.gd")
## 手に持って使う道具の定義
const ToolCatalogScript := preload("res://scripts/tools/tool_catalog.gd")
## 手に持って使う道具のルールの計算
const ToolRulesScript := preload("res://scripts/tools/tool_rules.gd")
## 手で毛を取る時のルールの計算 (手の強化の id)
const HandRulesScript := preload("res://scripts/hand/hand_rules.gd")
## 掃除代・機嫌の計算 (ご機嫌の線)
const EconomyRulesScript := preload("res://scripts/economy/economy_rules.gd")
## 在庫の売値の計算
const ProcessingRulesScript := preload("res://scripts/economy/processing_rules.gd")
## 掃除ロボットの道具の id
const RobotRulesScript := preload("res://scripts/automation/robot_rules.gd")
## 状態管理 autoload スクリプト (買う物の種類の定数を使う)
const GameStateScript := preload("res://scripts/state/game_state.gd")
## 見たい所との間に家具を挟まずに立つ所を選ぶ手順
const ViewPointScript := preload("res://scripts/dev/view_point.gd")
## 位置がどの部屋の中かを調べる (LookPrototypeRoom.room_at)
const LookPrototypeRoomScript := preload("res://scripts/look/look_prototype_room.gd")

## 時計を一度に進める最大の秒。機嫌は 1 回の呼び出しの時点のきれいさへ近づくため、まとめて進めすぎない長さ
const CLOCK_STEP_SECONDS: float = 1.0
## 取る毛・猫から離れて立つ水平の距離 (m。手の届く距離より短い)
const STAND_DISTANCE_M: float = 0.9
## 部屋ごとにかける道具を使う時に、部屋の中心から離れて立つ距離の割合 (部屋の短い辺の半分に対する比率)。
## 中心と壁の中ほどに立ち、録画に部屋の床が広く映る値
const ROOM_VIEW_RATIO: float = 0.5
## 買取業者から離れて立つ距離 (m。main.TRADER_RANGE_M より短い)
const TRADER_STAND_M: float = 1.2
## 経過を記録する間隔 (ゲーム内の秒)。住人が掃除代を払うたびの所持金の変わり方が見えるよう、払う間隔にそろえる
const SAMPLE_INTERVAL_SECONDS: float = EconomyRulesScript.PAYMENT_INTERVAL_SECONDS

## 節目の名前: 最初の道具を買った
const MILESTONE_FIRST_TOOL: String = "first_tool"
## 節目の名前: 最初の掃除ロボットを置いた
const MILESTONE_FIRST_ROBOT: String = "first_robot"
## 節目の名前: 住人全員がご機嫌になった
const MILESTONE_ALL_HAPPY: String = "all_happy"

## 遊ぶメインシーン (scripts/main.gd)
var _main: Node3D = null
## 本数とお金の正を持つ GameState
var _game_state: Node = null
## 節目の名前 -> 着いたゲーム内の秒
var _milestones: Dictionary = {}
## 買った物の記録 ({"seconds", "purchase_kind", "item_id"} の並び)
var _purchases: Array[Dictionary] = []
## SAMPLE_INTERVAL_SECONDS ごとの経過の記録
var _samples: Array[Dictionary] = []
## 1 手の種類 (+ 道具の id) -> かけたゲーム内の秒の合計
var _seconds_by_action: Dictionary = {}
## 1 手の種類 -> 行った回数
var _count_by_action: Dictionary = {}
## 道具の id -> その道具で取った本数の合計 (手を除く)
var _removed_by_tool: Dictionary = {}
## 「道具の id: 文言」 -> 道具を使って 1 本も取れなかった回数
var _empty_results: Dictionary = {}
## 最後に毛を取った部屋 (別の部屋に移る時に歩く秒を足す)
var _last_room_id: StringName = &""
## 次に経過を記録するゲーム内の秒
var _next_sample_seconds: float = 0.0


## メインシーン main (屋敷に入った後) を受け取り、取りこぼしと珍しい毛の抽選のシードを seed_value に固定する
func setup(main: Node3D, seed_value: int) -> void:
	_main = main
	_game_state = main.get_game_state()
	main.hand.set_rng_seed(seed_value)
	main.tools.set_rng_seed(seed_value + 1)
	main.big_tools.set_rng_seed(seed_value + 2)
	_record_sample()


## 遊んだゲーム内の秒
func elapsed_seconds() -> float:
	return _game_state.save_data.building_progress.elapsed_seconds


## 3 つの節目 (最初の道具・最初の掃除ロボット・住人全員のご機嫌) にすべて着いたか
func all_milestones_reached() -> bool:
	return _milestones.has_all([MILESTONE_FIRST_TOOL, MILESTONE_FIRST_ROBOT, MILESTONE_ALL_HAPPY])


## 次の 1 手を選んで行い、その手の秒だけ時計を進める。行った 1 手 (方針の戻り値に、かけた秒 "seconds" を足した物) を返す
func step() -> Dictionary:
	var action: Dictionary = PolicyScript.choose_action(snapshot())
	var seconds: float = _execute(action)
	action["seconds"] = seconds
	var key: String = String(action["kind"])
	if action.has("tool_id"):
		key += ":" + String(action["tool_id"])
	_seconds_by_action[key] = float(_seconds_by_action.get(key, 0.0)) + seconds
	_count_by_action[key] = int(_count_by_action.get(key, 0)) + 1
	_advance_clock(seconds)
	return action


## ゲームの様子を方針の形 (playtest_bot_policy.gd の先頭のコメント) にまとめる
func snapshot() -> Dictionary:
	var progress: BuildingProgress = _game_state.save_data.building_progress
	var layout: MansionLayout = _game_state.current_layout
	var owned: Dictionary = {}
	for tool: OwnedTool in progress.owned_tools:
		if tool == null or tool.tool_id == RobotRulesScript.ROBOT_TOOL_ID:
			continue
		owned[tool.tool_id] = {"level": tool.level, "consumable_count": tool.consumable_count}
	var area_by_room: Dictionary = {}
	var covered_by_room: Dictionary = {}
	for surface: MansionLayout.SurfaceDef in layout.surfaces:
		area_by_room[surface.room_id] = (
			float(area_by_room.get(surface.room_id, 0.0)) + surface.extents.x * surface.extents.y
		)
		var covered: Dictionary = covered_by_room.get(surface.room_id, {})
		for tool_id: StringName in PolicyScript.ROOM_TOOL_IDS:
			if not ToolRulesScript.covers_surface(tool_id, surface.surface_type):
				continue
			var entry: Dictionary = covered.get(tool_id, {"hairs": 0, "surfaces": 0})
			entry["hairs"] = (
				int(entry["hairs"])
				+ progress.find_surface_hair(surface.surface_id).total_count()
			)
			entry["surfaces"] = int(entry["surfaces"]) + 1
			covered[tool_id] = entry
		covered_by_room[surface.room_id] = covered
	var rooms: Array[Dictionary] = []
	for room: MansionLayout.RoomDef in layout.rooms:
		var status: Dictionary = _game_state.get_room_status(room.room_id)
		rooms.append({
			"room_id": room.room_id,
			"hair_count": int(status["hair_count"]),
			"cleanliness": float(status["cleanliness"]),
			"mood": float(status["mood"]),
			"area_m2": float(area_by_room.get(room.room_id, 0.0)),
			"covered": covered_by_room.get(room.room_id, {}),
		})
	var ready_cat_ids: Array[StringName] = []
	for route: Dictionary in _game_state.automation.get_cat_routes():
		if not _game_state.automation.is_cat_resting(route["cat_id"]):
			ready_cat_ids.append(route["cat_id"])
	return {
		"money": _game_state.get_money(),
		"stock_value": ProcessingRulesScript.stock_value(progress.hair_stocks),
		"owned": owned,
		"hand_levels": {
			HandRulesScript.UPGRADE_DEXTERITY:
			_game_state.get_hand_upgrade_level(HandRulesScript.UPGRADE_DEXTERITY),
			HandRulesScript.UPGRADE_GRAB_COUNT:
			_game_state.get_hand_upgrade_level(HandRulesScript.UPGRADE_GRAB_COUNT),
		},
		"robots": _game_state.automation.get_robots().size(),
		"rooms": rooms,
		"ready_cat_ids": ready_cat_ids,
	}


## 集計 (simulate.json の中身): 節目の秒と分、買った物、経過、1 手の種類ごとの秒と回数、最後の様子
func report() -> Dictionary:
	var milestone_minutes: Dictionary = {}
	for milestone: Variant in _milestones.keys():
		milestone_minutes[milestone] = snappedf(float(_milestones[milestone]) / 60.0, 0.01)
	return {
		"elapsed_seconds": snappedf(elapsed_seconds(), 0.01),
		"milestone_seconds": _milestones,
		"milestone_minutes": milestone_minutes,
		"purchases": _purchases,
		"samples": _samples,
		"seconds_by_action": _seconds_by_action,
		"count_by_action": _count_by_action,
		"removed_by_tool": _removed_by_tool,
		"empty_results": _empty_results,
		"final": _sample(),
	}


## 1 手 action を行い、かかったゲーム内の秒を返す
func _execute(action: Dictionary) -> float:
	match action["kind"]:
		PolicyScript.ACTION_CLEAN:
			return _clean(action["tool_id"], action["room_id"])
		PolicyScript.ACTION_BUY:
			if _game_state.purchase(action["purchase_kind"], action["item_id"]):
				_record_purchase(action["purchase_kind"], action["item_id"])
		PolicyScript.ACTION_BUY_ROBOT:
			_buy_robot()
		PolicyScript.ACTION_SELL:
			_face(_game_state.current_layout, _main.mansion_world.get_trader_position(), TRADER_STAND_M)
			_game_state.sell_hair_stocks()
		PolicyScript.ACTION_HAUL:
			_game_state.haul_with_dump_truck()
		PolicyScript.ACTION_BRUSH:
			var cat: Node3D = _main.automation.get_cat_node(action["cat_id"])
			if cat != null:
				_face(_game_state.current_layout, cat.global_position, STAND_DISTANCE_M)
			_main.tools.brush_cat(action["cat_id"])
	return PolicyScript.action_seconds(action, 0.0)


## 道具 tool_id で部屋 room_id の毛を 1 回取り、かかった秒を返す (前と別の部屋なら歩く秒を足す)
func _clean(tool_id: StringName, room_id: StringName) -> float:
	var seconds: float = 0.0
	if _last_room_id != &"" and _last_room_id != room_id:
		seconds += PolicyScript.ROOM_MOVE_SECONDS
	_last_room_id = room_id
	var action: Dictionary = {"kind": PolicyScript.ACTION_CLEAN, "tool_id": tool_id}
	if ToolCatalogScript.find_tool(tool_id).get("kind") in [
		ToolCatalogScript.KIND_ROOM, ToolCatalogScript.KIND_SHEET
	]:
		var room: MansionLayout.RoomDef = RobotRulesScript.find_room(_game_state.current_layout, room_id)
		_main.player.set_spawn(
			ViewPointScript.clear_spot(
				_game_state.current_layout, room, room.center,
				minf(room.size.x, room.size.z) * 0.5 * ROOM_VIEW_RATIO, Vector3.BACK
			),
			0.0,
		)
		_main.player.look_at_point(room.center)
		_main.tools.select_tool(tool_id)
		_record_tool_result(_main.tools.use_selected_tool())
		return seconds + PolicyScript.action_seconds(action, 0.0)
	var target: Dictionary = _hair_target(room_id, tool_id)
	if target.is_empty():
		return seconds + PolicyScript.action_seconds({"kind": PolicyScript.ACTION_WAIT}, 0.0)
	_face(_game_state.current_layout, target["point"], STAND_DISTANCE_M)
	if tool_id == ToolCatalogScript.TOOL_HAND:
		_main.tools.select_tool(ToolCatalogScript.TOOL_HAND)
		var hand: HandController = _main.hand
		if not hand.begin_pull_at(target):
			return seconds + PolicyScript.action_seconds(action, 0.0)
		var pull: float = hand.get_pull_duration()
		hand.advance_pull(pull)
		return seconds + PolicyScript.action_seconds(action, pull)
	_main.tools.select_tool(tool_id)
	_record_tool_result(_main.tools.use_selected_tool_at(target))
	return seconds + PolicyScript.action_seconds(action, 0.0)


## 道具を使った結果 result (ToolController.use_selected_tool_at の戻り値) を、取った本数と、
## 1 本も取れなかった時の文言の回数に数える (所要時間が伸びた理由を simulate.json で追えるようにする)
func _record_tool_result(result: Dictionary) -> void:
	var key: String = String(result.get("tool_id", &""))
	_removed_by_tool[key] = int(_removed_by_tool.get(key, 0)) + int(result.get("removed", 0))
	if int(result.get("removed", 0)) <= 0:
		var message: String = "%s: %s" % [key, str(result.get("message", ""))]
		_empty_results[message] = int(_empty_results.get(message, 0)) + 1


## 部屋 room_id の表面のうち、道具 tool_id で取れる見込みの本数 (残り × 取りこぼさない割合) がいちばん多い表面で、
## 毛がいちばん集まっている所を狙う点 ({"surface_index", "point"}) にする。取れる見込みのある表面が無ければ空。
## 道具は表面の種類で取りこぼしの割合が違い (ToolRules.miss_ratio)、残りの本数だけで選ぶと取りにくい表面を狙い続ける。
## また道具は範囲の最後の 1 本を残す (ToolRules.touchable_count) ため、毛のまばらな所を狙うと 1 本も取れない
func _hair_target(room_id: StringName, tool_id: StringName) -> Dictionary:
	var world: MansionWorld = _main.mansion_world
	var hair_field: Node3D = world.get_hair_field()
	var owned: OwnedTool = _game_state.find_owned_tool(tool_id)
	var best_index: int = -1
	var best_expected: float = 0.0
	for surface_index: int in range(hair_field.get_surface_count()):
		var surface: MansionLayout.SurfaceDef = world.get_surface_def(surface_index)
		if surface == null or surface.room_id != room_id:
			continue
		var expected: float = float(hair_field.get_surface_remaining_count(surface_index))
		if owned != null:
			expected *= 1.0 - ToolRulesScript.miss_ratio(tool_id, owned.level, surface.surface_type)
		if expected > best_expected:
			best_expected = expected
			best_index = surface_index
	if best_index < 0:
		return {}
	return {"surface_index": best_index, "point": _densest_point(best_index, _reach_radius(tool_id))}


## 道具 tool_id が 1 回で毛に届く半径 (m。手はつまむ半径)
static func _reach_radius(tool_id: StringName) -> float:
	if tool_id == ToolCatalogScript.TOOL_HAND:
		return HandController.GRAB_RADIUS_M
	return float(ToolCatalogScript.find_tool(tool_id)["radius_m"])


## 表面 surface_index の描いている毛を一辺 radius × 2 の升目に分け、いちばん多く入った升目の毛のうち、根元の平均にいちばん近い毛の根元を返す
## (道具の範囲に入る本数が多い所の近似。毛が無ければ表面の 0 番目の毛の点)
func _densest_point(surface_index: int, radius: float) -> Vector3:
	var hair_field: Node3D = _main.mansion_world.get_hair_field()
	# 升目の一辺の下限 1 cm。半径 0 の道具で 0 で割らないための値で、
	# いちばん小さい手のつまむ範囲 (直径 16 cm) より十分小さい
	var cell_size: float = maxf(0.01, radius * 2.0)
	var points_by_cell: Dictionary = {}
	var best_cell: Vector3i = Vector3i.ZERO
	var best_count: int = 0
	for slot: int in range(hair_field.get_surface_visible_instance_count(surface_index)):
		var point: Vector3 = hair_field.get_hair_transform(
			hair_field.get_hair_id_at_slot(surface_index, slot)
		).origin
		var cell: Vector3i = Vector3i((point / cell_size).floor())
		var points: Array = points_by_cell.get(cell, [])
		points.append(point)
		points_by_cell[cell] = points
		if points.size() > best_count:
			best_count = points.size()
			best_cell = cell
	if best_count <= 0:
		return hair_field.get_hair_transform(hair_field.get_hair_id_at_slot(surface_index, 0)).origin
	# 升目の平均の点の近くに毛があるとは限らない (対角の隅に分かれている等) ため、平均にいちばん近い実在の毛の根元を狙う。
	# 実在の毛を狙えば、手は少なくともその 1 本をつまめ、同じ取れない点を狙い続けない
	var mean: Vector3 = Vector3.ZERO
	for point: Vector3 in points_by_cell[best_cell]:
		mean += point
	mean /= float(best_count)
	var nearest: Vector3 = points_by_cell[best_cell][0]
	for point: Vector3 in points_by_cell[best_cell]:
		if point.distance_squared_to(mean) < nearest.distance_squared_to(mean):
			nearest = point
	return nearest


## 掃除ロボットを 1 台買い、きれいさがいちばん低い部屋から全部屋を順に回らせる
func _buy_robot() -> void:
	var rooms: Array[MansionLayout.RoomDef] = _game_state.current_layout.rooms
	var first_room_id: StringName = PolicyScript.dirtiest_room(snapshot()).get(
		"room_id", rooms[0].room_id
	)
	if not _game_state.automation.buy_robot(first_room_id):
		return
	var start: int = 0
	for index: int in range(rooms.size()):
		if rooms[index].room_id == first_room_id:
			start = index
	var route: Array[StringName] = []
	for offset: int in range(rooms.size()):
		route.append(rooms[(start + offset) % rooms.size()].room_id)
	_game_state.automation.set_robot_route(_game_state.automation.get_robots().size() - 1, route)
	_record_purchase(PolicyScript.PURCHASE_ROBOT, RobotRulesScript.ROBOT_TOOL_ID)


## 見たい所 target から水平に distance 離れた、家具を挟まない所に立って target を向く
func _face(layout: MansionLayout, target: Vector3, distance: float) -> void:
	var room: MansionLayout.RoomDef = LookPrototypeRoomScript.room_at(layout, target)
	var spot: Vector3 = target + Vector3.BACK * distance
	if room != null:
		spot = ViewPointScript.clear_spot(
			layout, room, target, distance, _main.player.global_position - target
		)
	_main.player.set_spawn(Vector3(spot.x, 0.0, spot.z), 0.0)
	_main.player.look_at_point(target)


## 買った物を記録し、最初の道具・最初の掃除ロボットの節目を付ける
func _record_purchase(purchase_kind: StringName, item_id: StringName) -> void:
	_purchases.append({
		"seconds": snappedf(elapsed_seconds(), 0.01),
		"purchase_kind": String(purchase_kind),
		"item_id": String(item_id),
	})
	if purchase_kind == GameStateScript.PURCHASE_TOOL:
		_mark(MILESTONE_FIRST_TOOL)
	elif purchase_kind == PolicyScript.PURCHASE_ROBOT:
		_mark(MILESTONE_FIRST_ROBOT)


## 節目 milestone に初めて着いた時の秒を記録する (2 回目以降は変えない)
func _mark(milestone: String) -> void:
	if not _milestones.has(milestone):
		_milestones[milestone] = snappedf(elapsed_seconds(), 0.01)


## 時計を seconds 秒、CLOCK_STEP_SECONDS ずつ進め、住人全員のご機嫌と経過の記録を見る
func _advance_clock(seconds: float) -> void:
	var left: float = seconds
	while left > 0.0:
		var step_seconds: float = minf(CLOCK_STEP_SECONDS, left)
		_main.advance_play_clock(step_seconds)
		left -= step_seconds
		if _everyone_happy():
			_mark(MILESTONE_ALL_HAPPY)
		if elapsed_seconds() >= _next_sample_seconds:
			_record_sample()


## 住人全員がご機嫌か
func _everyone_happy() -> bool:
	for room: MansionLayout.RoomDef in _game_state.current_layout.rooms:
		if not EconomyRulesScript.is_happy(float(_game_state.get_room_status(room.room_id)["mood"])):
			return false
	return true


## 今の経過を記録し、次に記録する秒を決める
func _record_sample() -> void:
	_samples.append(_sample())
	_next_sample_seconds = elapsed_seconds() + SAMPLE_INTERVAL_SECONDS


## 今の経過 (秒・お金・在庫の額・残りの毛・部屋ごとの機嫌・掃除ロボットの台数)
func _sample() -> Dictionary:
	var moods: Dictionary = {}
	for room: MansionLayout.RoomDef in _game_state.current_layout.rooms:
		moods[String(room.room_id)] = snappedf(
			float(_game_state.get_room_status(room.room_id)["mood"]), 0.001
		)
	return {
		"seconds": snappedf(elapsed_seconds(), 0.01),
		"money": _game_state.get_money(),
		"stock_value": ProcessingRulesScript.stock_value(
			_game_state.save_data.building_progress.hair_stocks
		),
		"remaining_hairs": _game_state.get_total_remaining_hairs(),
		"drawn_hairs": HairFieldScript.count_drawn_hairs(_main.mansion_world.get_hair_field()),
		"moods": moods,
		"robots": _game_state.automation.get_robots().size(),
	}

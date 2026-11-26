extends RefCounted
## 掃除ロボットの値段・回る順・毛を取る量の計算 (純粋な計算。3D の形は AutomationView が描く)。
## 掃除ロボットは買った 1 台ずつ (OwnedTool) が回る部屋の順 (OwnedTool.robot_room_ids) を持ち、その順に 1 部屋ずつ
## 決まった秒数留まって、部屋の床とカーペットの毛を一定の間隔で 1 本ずつ取る。取った毛は在庫 (毛のまま) に入る。

## 屋敷の作りの型 (表面の種類の定数)
const MansionLayoutScript := preload("res://scripts/mansion/mansion_layout.gd")
## 面ごとの毛の型 (毛の色の並び)
const SurfaceHairScript := preload("res://scripts/data/surface_hair.gd")
## 決まった所を順に回る動きの時刻の計算
const RouteClockScript := preload("res://scripts/automation/route_clock.gd")

## 掃除ロボットの道具の id (OwnedTool.tool_id。手に持たないため、手に持つ道具の表 ToolCatalog には入れない)
const ROBOT_TOOL_ID: StringName = &"cleaning_robot"
## 表示名
const ROBOT_NAME: String = "掃除ロボット"
## 1 台の値段 (円)。手に持つ道具でいちばん高い掃除機 (400 円) より安く、何台か買い足して回る順を組める値段
const ROBOT_PRICE: int = 300
## 持てる台数の上限。回る順を決める画面に 1 台ずつ並べて選べる数
const MAX_ROBOTS: int = 4
## 回る順の 1 部屋に留まる秒数
const ROOM_SECONDS: float = 20.0
## 部屋に留まっている間に毛を 1 本取る間隔 (秒)
const PICK_INTERVAL_SECONDS: float = 1.0
## 2 台目以降の掃除ロボットの時刻のずれ (秒)。同じ順で回る 2 台が重ならないようにずらす
const PHASE_STEP_SECONDS: float = 5.0
## 毛を取る面の種類 (床に置いて走る掃除ロボットが届く面)
const CLEAN_SURFACE_TYPES: Array[StringName] = [
	MansionLayoutScript.SURFACE_FLOOR, MansionLayoutScript.SURFACE_CARPET
]
## 部屋の中で走る輪の大きさ (部屋の半幅に対する比率)。壁と家具の手前を回る大きさ
const LOOP_RATIO: float = 0.55
## 部屋の中で走る輪を 1 周する秒数
const LOOP_SECONDS: float = 10.0


## 回る順 (部屋の id の並び) から RouteClock の道のりを組み立てる。stops の要素は {"point": 部屋の中心の床, "seconds", "room_id"}。
## 屋敷に無い部屋の id は飛ばす
static func build_route(layout: MansionLayout, room_ids: Array[StringName]) -> Dictionary:
	var stops: Array[Dictionary] = []
	if layout != null:
		for room_id: StringName in room_ids:
			var room: MansionLayout.RoomDef = find_room(layout, room_id)
			if room != null:
				stops.append({"point": room.center, "seconds": ROOM_SECONDS, "room_id": room_id})
	return RouteClockScript.make_route(stops)


## 屋敷の部屋のうち room_id の部屋を返す (無ければ null)
static func find_room(layout: MansionLayout, room_id: StringName) -> MansionLayout.RoomDef:
	for room: MansionLayout.RoomDef in layout.rooms:
		if room.room_id == room_id:
			return room
	return null


## robot_index 台目 (0 始まり) の掃除ロボットにとっての時刻 (屋敷で遊んだ時間に台ごとのずれを足す)
static func robot_time(robot_index: int, automation_seconds: float) -> float:
	return automation_seconds + PHASE_STEP_SECONDS * float(robot_index)


## 時刻 t0 より後から t1 まで (t0 < 時刻 ≦ t1) に掃除ロボットが毛を取る回数を、部屋の id ごとに返す (room_id -> int)
static func picks_between(route: Dictionary, t0: float, t1: float) -> Dictionary:
	var result: Dictionary = {}
	var ticks: Dictionary = RouteClockScript.ticks_between(route, t0, t1, PICK_INTERVAL_SECONDS)
	for stop_index: Variant in ticks.keys():
		var room_id: StringName = route["stops"][int(stop_index)]["room_id"]
		result[room_id] = int(result.get(room_id, 0)) + int(ticks[stop_index])
	return result


## 次に取る毛を選ぶ。candidates は部屋の毛を取る面の {"surface_id", "counts": SurfaceHair.hair_counts} の並び。
## 残りの本数がいちばん多い面の、いちばん多い色を選ぶ (同じ数なら並びの先)。戻り値は {"surface_id", "color"}、毛が無ければ空
static func choose_pick(candidates: Array[Dictionary]) -> Dictionary:
	var best: Dictionary = {}
	var best_total: int = 0
	for candidate: Dictionary in candidates:
		var counts: Dictionary = candidate["counts"]
		var total: int = 0
		var top_color: StringName = &""
		var top_count: int = 0
		for color_id: StringName in SurfaceHairScript.STANDARD_COLORS:
			var count: int = int(counts.get(color_id, 0))
			total += maxi(0, count)
			if count > top_count:
				top_count = count
				top_color = color_id
		if total > best_total:
			best_total = total
			best = {"surface_id": candidate["surface_id"], "color": top_color}
	return best


## 時刻 t の掃除ロボットの位置。部屋に着いてから RouteClock.MOVE_SECONDS 秒は前の部屋の中心から移り、
## その後は部屋の中心の周りを 8 の字の輪で走る。room_sizes は room_id -> 部屋の大きさ (Vector3)。回る部屋が無ければ原点
static func position_at(route: Dictionary, t: float, room_sizes: Dictionary) -> Vector3:
	var index: int = RouteClockScript.stop_index_at(route, t)
	if index < 0:
		return Vector3.ZERO
	var in_stop: float = RouteClockScript.seconds_in_stop(route, t)
	if in_stop < RouteClockScript.MOVE_SECONDS:
		return RouteClockScript.position_at(route, t)
	var stop: Dictionary = route["stops"][index]
	var size: Vector3 = room_sizes.get(stop["room_id"], Vector3.ZERO)
	var angle: float = TAU * (in_stop - RouteClockScript.MOVE_SECONDS) / LOOP_SECONDS
	# 輪は中心から始まる 8 の字 (角度 0 で中心) にし、部屋に着いた所 (中心) から途切れずに走り出す
	return (stop["point"] as Vector3) + Vector3(
		sin(angle) * size.x * 0.5 * LOOP_RATIO, 0.0, sin(angle * 2.0) * size.z * 0.25 * LOOP_RATIO
	)

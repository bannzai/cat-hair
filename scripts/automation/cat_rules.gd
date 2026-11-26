extends RefCounted
## 猫の通り道・昼寝の場所・毛を落とす量・ブラッシングの計算 (純粋な計算。3D の猫の形は AutomationController が描く)。
## 猫は屋敷の作りから決まる通り道を、屋敷で遊んでいる時間に合わせて繰り返し歩き、立ち止まった面に一定の間隔で毛を落とす。
## 通り道は保存せず、屋敷の作り (MansionLayout) から毎回同じものを組み立てる。

## 屋敷の作りの型 (表面の種類の定数)
const MansionLayoutScript := preload("res://scripts/mansion/mansion_layout.gd")
## 面ごとの毛の型 (毛の色の id)
const SurfaceHairScript := preload("res://scripts/data/surface_hair.gd")
## 決まった所を順に回る動きの時刻の計算
const RouteClockScript := preload("res://scripts/automation/route_clock.gd")

## 屋敷に住む猫。id は通り道とブラッシングの記録の鍵、color は落とす毛の色 (SurfaceHair の色の id)。
## offset は部屋の中で立ち止まる所の、部屋の中心からのずれ (m)。3 匹が同じ所に重ならないようにずらす
const CATS: Array[Dictionary] = [
	{
		"id": &"shiratama",
		"name": "しらたま",
		"color": SurfaceHairScript.COLOR_WHITE,
		"offset": Vector2(-0.9, 0.7),
	},
	{
		"id": &"kuromame",
		"name": "くろまめ",
		"color": SurfaceHairScript.COLOR_BLACK,
		"offset": Vector2(1.0, -0.6),
	},
	{
		"id": &"mike",
		"name": "みけ",
		"color": SurfaceHairScript.COLOR_CALICO,
		"offset": Vector2(0.4, 1.1),
	},
]
## 通り道の 1 部屋に立ち止まる秒数。プレイヤーが部屋に入ってから猫に気付き、近づいてブラシをかけられる長さ。値は仮で、自動テストプレイ (issue #13) で調整する。
const WALK_STOP_SECONDS: float = 8.0
## 昼寝の場所で寝ている秒数。通り道の 1 部屋より長く、寝ている面に毛が溜まって見える長さ
const NAP_SECONDS: float = 24.0
## 立ち止まっている間に毛を 1 本落とす間隔 (秒)。猫 3 匹で 1 秒に 1.5 本ほど落ち、掃除ロボット 1 台 (RobotRules.PICK_INTERVAL_SECONDS ごとに
## 1 本) では追いつかず、2 台で上回る量にした。値は仮で、
## 自動テストプレイ (issue #13) で調整する。
const DROP_INTERVAL_SECONDS: float = 2.0
## 昼寝に使う面の種類 (猫が寝そべる、上を向いた柔らかい面)。見つかった種類の順に選ぶ
const NAP_SURFACE_TYPES: Array[StringName] = [
	MansionLayoutScript.SURFACE_SOFA, MansionLayoutScript.SURFACE_CARPET
]
## 面が上を向いているとみなす、面の法線と真上の向きの内積の下限 (約 25 度までの傾き。ソファの座面は通し、背もたれ・側面を外す)
const UPWARD_DOT_MIN: float = 0.9
## 立ち止まる所を家具から離す余白 (m)。猫の体が家具にめり込まない幅
const FURNITURE_MARGIN_M: float = 0.3
## 1 つの面に溜まる毛の上限の下限 (本)。面の最初の本数がこれより少なくても、ここまでは落ちる。最初の毛が少ない屋敷 (開発者画面で本数を下げた時) でも、猫が 1 か所に立ち止まる 8
## 秒の落とす量 (4 本) の 10 回分は溜まって見える数にした
const MIN_SURFACE_CAP: int = 40
## ブラッシング 1 回で取れる毛の本数。手で 1 本ずつ抜くより多く、粘着ローラーの 1 回 (範囲の毛を何本も取る) より少ない量にした。値は仮で、自動テストプレイ (issue #13)
## で調整する。
const BRUSH_HAIRS: int = 5
## ブラッシングした猫が毛を落とさず、もう一度ブラッシングもできない秒数。続けてブラシをかけ続けるだけの遊び方にならない長さ。値は仮で、自動テストプレイ (issue #13) で調整する。
const BRUSH_REST_SECONDS: float = 10.0
## 狙いの光線から猫の体の中心までの距離がこれ以内なら、その猫を狙っているとみなす (m)。胴の長さ (0.42 m) の約 8 割で、頭から尾のどこを狙っても当たる幅
const AIM_RADIUS_M: float = 0.35
## 猫の体の中心の、足元からの高さ (m)。AutomationController の胴の中心の高さ (CAT_LEG_LENGTH_M + CAT_BODY_RADIUS_M) より少し下の、
## 胴の中ほど
const BODY_CENTER_HEIGHT_M: float = 0.18


## 屋敷の作りから猫ごとの通り道を組み立てる。戻り値の要素は RouteClock の道のりに
## "cat_id"・"name"・"color" を足した辞書で、stops の要素は {"point", "seconds", "surface_id", "room_id", "nap"}。
## 部屋が無い屋敷では空
static func build_routes(layout: MansionLayout) -> Array[Dictionary]:
	var routes: Array[Dictionary] = []
	if layout == null or layout.rooms.is_empty():
		return routes
	for cat_index: int in range(CATS.size()):
		var cat_def: Dictionary = CATS[cat_index]
		var start_room: int = cat_index % layout.rooms.size()
		var stops: Array[Dictionary] = []
		for room_index: int in walk_order(layout, start_room):
			var room: MansionLayout.RoomDef = layout.rooms[room_index]
			var point: Vector3 = free_point(layout, room, cat_def["offset"])
			var surface: MansionLayout.SurfaceDef = surface_under(layout, room.room_id, point)
			if surface == null:
				continue
			stops.append({
				"point": Vector3(point.x, surface.center.y, point.z),
				"seconds": WALK_STOP_SECONDS,
				"surface_id": surface.surface_id,
				"room_id": room.room_id,
				"nap": false,
			})
		var nap_surface: MansionLayout.SurfaceDef = nap_surface_for(layout, start_room)
		if nap_surface != null:
			stops.append({
				"point": nap_surface.center,
				"seconds": NAP_SECONDS,
				"surface_id": nap_surface.surface_id,
				"room_id": nap_surface.room_id,
				"nap": true,
			})
		var route: Dictionary = RouteClockScript.make_route(stops)
		route["cat_id"] = cat_def["id"]
		route["name"] = cat_def["name"]
		route["color"] = cat_def["color"]
		routes.append(route)
	return routes


## 部屋を歩く順 (部屋の添字の並び)。start_room から始め、隣り合う (グリッドで辺を共有する) まだ通っていない部屋へ進み、
## 隣に無ければ添字の小さい部屋へ移る。どの部屋も 1 回ずつ通る
static func walk_order(layout: MansionLayout, start_room: int) -> Array[int]:
	var order: Array[int] = []
	var room_count: int = layout.rooms.size()
	if room_count == 0:
		return order
	var current: int = clampi(start_room, 0, room_count - 1)
	var visited: Dictionary = {}
	while current >= 0:
		order.append(current)
		visited[current] = true
		var here: MansionLayout.RoomDef = layout.rooms[current]
		var next: int = -1
		for candidate: int in range(room_count):
			var other: MansionLayout.RoomDef = layout.rooms[candidate]
			if (
				not visited.has(candidate)
				and absi(other.grid_x - here.grid_x) + absi(other.grid_z - here.grid_z) == 1
			):
				next = candidate
				break
		if next < 0:
			for candidate: int in range(room_count):
				if not visited.has(candidate):
					next = candidate
					break
		current = next
	return order


## 部屋の中で猫が立ち止まる所。部屋の中心から offset ずらした所を、家具 (余白 FURNITURE_MARGIN_M 込み) に重ならない所まで
## 90 度ずつ回して探す。どの向きも家具に重なる時は部屋の中心からのずれを半分にして探し直し、それでも無ければ部屋の中心
static func free_point(
	layout: MansionLayout, room: MansionLayout.RoomDef, offset: Vector2
) -> Vector3:
	for shrink: float in [1.0, 0.5]:
		for quarter: int in range(4):
			var turned: Vector2 = offset.rotated(PI * 0.5 * float(quarter)) * shrink
			var point: Vector3 = room.center + Vector3(turned.x, 0.0, turned.y)
			if not is_blocked(layout, room.room_id, point):
				return point
	return room.center


## point が部屋の家具 (床の上の占有範囲を FURNITURE_MARGIN_M 広げた範囲。上に乗れるカーペットは除く) か
## 壁際 (同じ余白) に入るか
static func is_blocked(layout: MansionLayout, room_id: StringName, point: Vector3) -> bool:
	for room: MansionLayout.RoomDef in layout.rooms:
		if room.room_id == room_id and (
			absf(point.x - room.center.x) > room.size.x * 0.5 - FURNITURE_MARGIN_M
			or absf(point.z - room.center.z) > room.size.z * 0.5 - FURNITURE_MARGIN_M
		):
			return true
	for furniture: MansionLayout.ObjectDef in layout.objects:
		if furniture.room_id != room_id or furniture.object_kind == MansionLayoutScript.OBJECT_CARPET:
			continue
		var local: Vector3 = (
			Transform3D(Basis(Vector3.UP, furniture.rotation_y), furniture.position).affine_inverse() * point
		)
		if (
			absf(local.x) <= furniture.size.x * 0.5 + FURNITURE_MARGIN_M
			and absf(local.z) <= furniture.size.z * 0.5 + FURNITURE_MARGIN_M
		):
			return true
	return false


## 部屋の中の point に立った猫の足元の面 (カーペットの上ならカーペット、それ以外は床) を返す。床が無い部屋は null
static func surface_under(
	layout: MansionLayout, room_id: StringName, point: Vector3
) -> MansionLayout.SurfaceDef:
	var floor_surface: MansionLayout.SurfaceDef = null
	for surface: MansionLayout.SurfaceDef in layout.surfaces:
		if surface.room_id != room_id:
			continue
		if surface.surface_type == MansionLayoutScript.SURFACE_FLOOR:
			floor_surface = surface
		elif surface.surface_type == MansionLayoutScript.SURFACE_CARPET and _contains(surface, point):
			return surface
	return floor_surface


## 猫が昼寝する面。NAP_SURFACE_TYPES の順に、start_room の部屋から順に探し、最初に見つかった上を向いた面を返す
## (どの部屋にも無ければ null)
static func nap_surface_for(layout: MansionLayout, start_room: int) -> MansionLayout.SurfaceDef:
	var room_count: int = layout.rooms.size()
	for nap_type: StringName in NAP_SURFACE_TYPES:
		for step: int in range(room_count):
			var room_id: StringName = layout.rooms[(start_room + step) % room_count].room_id
			for surface: MansionLayout.SurfaceDef in layout.surfaces:
				if (
					surface.room_id == room_id
					and surface.surface_type == nap_type
					and surface.basis.y.normalized().dot(Vector3.UP) >= UPWARD_DOT_MIN
				):
					return surface
	return null


## 時刻 from_seconds より後から to_seconds まで (from_seconds < 時刻 ≦ to_seconds) に猫が落とす毛の本数を、面の id ごとに返す
## (surface_id -> int)。
## 毛は立ち止まった所ごとに、着いてから DROP_INTERVAL_SECONDS 秒ごとに 1 本落ちる
static func drops_between(
	route: Dictionary, from_seconds: float, to_seconds: float
) -> Dictionary:
	var result: Dictionary = {}
	var ticks: Dictionary = RouteClockScript.ticks_between(
		route, from_seconds, to_seconds, DROP_INTERVAL_SECONDS
	)
	for stop_index: Variant in ticks.keys():
		var surface_id: StringName = route["stops"][int(stop_index)]["surface_id"]
		result[surface_id] = int(result.get(surface_id, 0)) + int(ticks[stop_index])
	return result


## 通り道の中で surface_id の面に立ち止まる所 (毛を落とす所) を返す。通り道に無い面は空の辞書
static func stop_on_surface(route: Dictionary, surface_id: StringName) -> Dictionary:
	for stop: Dictionary in route["stops"]:
		if stop["surface_id"] == surface_id:
			return stop
	return {}


## 猫が落とした毛を足してよい本数。面の毛の上限 (最初の本数と MIN_SURFACE_CAP の大きい方) から今の本数を引いた数 (0 以上)
static func room_for_drops(current_count: int, initial_count: int) -> int:
	return maxi(0, maxi(initial_count, MIN_SURFACE_CAP) - current_count)


## 時刻 now に、rest_until (ブラッシングで休む終わりの時刻) までの間で、猫が休んでいる (毛を落とさず、ブラシをかけられない) か
static func is_resting(rest_until: float, now: float) -> bool:
	return now < rest_until


## 光線 (from から direction の向きへ reach の距離まで) に体の中心が AIM_RADIUS_M 以内で近い猫のうち、いちばん手前の猫の id。
## cat_centers は cat_id -> 体の中心のワールド座標。どの猫も狙えていなければ空
static func cat_on_ray(
	cat_centers: Dictionary, from: Vector3, direction: Vector3, reach: float
) -> StringName:
	var best_id: StringName = &""
	var best_along: float = INF
	var unit: Vector3 = direction.normalized()
	for cat_id: Variant in cat_centers.keys():
		var to_cat: Vector3 = (cat_centers[cat_id] as Vector3) - from
		var along: float = to_cat.dot(unit)
		if along < 0.0 or along > reach:
			continue
		if (to_cat - unit * along).length() <= AIM_RADIUS_M and along < best_along:
			best_along = along
			best_id = StringName(cat_id)
	return best_id


## 面の矩形 (局所 X / Z の全幅 extents) の中に point が入るか (面の法線の向きの距離は見ない)
static func _contains(surface: MansionLayout.SurfaceDef, point: Vector3) -> bool:
	var local: Vector3 = surface.frame().affine_inverse() * point
	return absf(local.x) <= surface.extents.x * 0.5 and absf(local.z) <= surface.extents.y * 0.5

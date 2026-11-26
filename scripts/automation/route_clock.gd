extends RefCounted
## 決まった所を順に回り、1 か所に決まった秒数ずつ留まる動き (猫の通り道・掃除ロボットの回る順) の時刻の計算 (純粋な計算)。
## 道のりは {"cycle_seconds": 一巡の秒数, "stops": [{"point": 留まる所のワールド座標, "seconds": 留まる秒数, ...}]} の形で、
## 時刻 0 に最初の所に着き、一巡したら最初の所へ戻って繰り返す。

## 留まる所へ前の所から移る秒数 (留まる秒数の初めに含める)。隣の部屋 (中心どうし 6 m ほど) へ歩いて移って見える長さで、
## 立ち止まる 8 秒の 4 分の 1 に収めた。離れた部屋へ移る時も同じ秒数で、ドアを通る道のりを速く歩く
const MOVE_SECONDS: float = 2.0


## stops の留まる秒数を足した一巡の秒数を入れた道のりを返す
static func make_route(stops: Array[Dictionary]) -> Dictionary:
	var cycle: float = 0.0
	for stop: Dictionary in stops:
		cycle += maxf(0.0, float(stop["seconds"]))
	return {"cycle_seconds": cycle, "stops": stops}


## 時刻 clock_seconds に留まっている所の添字を返す (道のりが空なら -1)
static func stop_index_at(route: Dictionary, clock_seconds: float) -> int:
	var stops: Array = route["stops"]
	var cycle: float = float(route["cycle_seconds"])
	if stops.is_empty() or cycle <= 0.0:
		return -1
	var local: float = fposmod(clock_seconds, cycle)
	var end: float = 0.0
	for index: int in range(stops.size()):
		end += float(stops[index]["seconds"])
		if local < end:
			return index
	return stops.size() - 1


## 時刻 clock_seconds に今の所に着いてから経った秒数 (道のりが空なら 0)
static func seconds_in_stop(route: Dictionary, clock_seconds: float) -> float:
	var index: int = stop_index_at(route, clock_seconds)
	if index < 0:
		return 0.0
	var stops: Array = route["stops"]
	var start: float = 0.0
	for before: int in range(index):
		start += float(stops[before]["seconds"])
	return fposmod(clock_seconds, float(route["cycle_seconds"])) - start


## 時刻 clock_seconds の位置。着いてから MOVE_SECONDS 秒は前の所から歩いて移り、その後は留まる所にいる (道のりが空なら原点)。
## 留まる所に "path" (前の所からの経由点の並び。connect_through_doors が入れる) があればその折れ線に沿って移り、
## 無ければ前の所から直線で移る
static func position_at(route: Dictionary, clock_seconds: float) -> Vector3:
	var index: int = stop_index_at(route, clock_seconds)
	if index < 0:
		return Vector3.ZERO
	var stops: Array = route["stops"]
	var progress: float = clampf(seconds_in_stop(route, clock_seconds) / MOVE_SECONDS, 0.0, 1.0)
	if stops[index].has("path"):
		return point_on_path(stops[index]["path"], progress)
	return (stops[(index - 1 + stops.size()) % stops.size()]["point"] as Vector3).lerp(
		stops[index]["point"], progress
	)


## 道のりの各留まる所に、前の所 (一巡の最初は最後の所) から移る経由点の並び "path" を入れる。
## 部屋が違う時は、前の部屋の中心から隣り合う部屋をドア (隣り合う部屋の中心どうしの真ん中の、壁の開口部) を通って
## 次の部屋の中心へ進む。各留まる所に "room_id" が要る
static func connect_through_doors(layout: MansionLayout, route: Dictionary) -> void:
	var stops: Array = route["stops"]
	for index: int in range(stops.size()):
		var previous: Dictionary = stops[(index - 1 + stops.size()) % stops.size()]
		stops[index]["path"] = door_path(
			layout, previous["point"], previous["room_id"], stops[index]["point"], stops[index]["room_id"]
		)


## from_room_id の部屋の from_point から to_room_id の部屋の to_point まで、壁を通らずに歩く経由点の並び (両端を含む)。
## 同じ部屋なら直線、違う部屋ならグリッドで隣り合う部屋をたどる最短の部屋の並び (幅優先) の中心とドアを通る。
## 部屋がつながっていない時は直線
static func door_path(
	layout: MansionLayout,
	from_point: Vector3,
	from_room_id: StringName,
	to_point: Vector3,
	to_room_id: StringName,
) -> Array[Vector3]:
	var path: Array[Vector3] = [from_point]
	if from_room_id != to_room_id:
		var rooms: Array[MansionLayout.RoomDef] = _room_chain(layout, from_room_id, to_room_id)
		for chain_index: int in range(rooms.size()):
			if chain_index > 0:
				path.append((rooms[chain_index - 1].center + rooms[chain_index].center) * 0.5)
			path.append(rooms[chain_index].center)
	path.append(to_point)
	return path


## 経由点の並び path の、全長に対する割合 progress (0〜1) の所
static func point_on_path(path: Array, progress: float) -> Vector3:
	var total: float = 0.0
	for index: int in range(1, path.size()):
		total += (path[index - 1] as Vector3).distance_to(path[index])
	if total <= 0.0:
		return path[path.size() - 1]
	var left: float = total * progress
	for index: int in range(1, path.size()):
		var length: float = (path[index - 1] as Vector3).distance_to(path[index])
		if left <= length and length > 0.0:
			return (path[index - 1] as Vector3).lerp(path[index], left / length)
		left -= length
	return path[path.size() - 1]


## from_room_id から to_room_id まで、グリッドで隣り合う部屋 (辺を共有する部屋) をたどる最短の部屋の並び (両端を含む)。
## つながっていない時と、どちらかの部屋が無い時は空
static func _room_chain(
	layout: MansionLayout, from_room_id: StringName, to_room_id: StringName
) -> Array[MansionLayout.RoomDef]:
	var chain: Array[MansionLayout.RoomDef] = []
	var start: int = -1
	for index: int in range(layout.rooms.size()):
		if layout.rooms[index].room_id == from_room_id:
			start = index
	if start < 0:
		return chain
	# 部屋の添字 -> 1 つ前にたどった部屋の添字
	var came_from: Dictionary = {start: -1}
	var queue: Array[int] = [start]
	var goal: int = -1
	while not queue.is_empty() and goal < 0:
		var here: int = queue.pop_front()
		if layout.rooms[here].room_id == to_room_id:
			goal = here
			break
		for other: int in range(layout.rooms.size()):
			if (
				not came_from.has(other)
				and absi(layout.rooms[other].grid_x - layout.rooms[here].grid_x)
				+ absi(layout.rooms[other].grid_z - layout.rooms[here].grid_z) == 1
			):
				came_from[other] = here
				queue.append(other)
	var step: int = goal
	while step >= 0:
		chain.push_front(layout.rooms[step])
		step = int(came_from[step])
	return chain


## 時刻 from_seconds より後から to_seconds まで (from_seconds < 時刻 ≦ to_seconds) に、留まった所ごとに起きる出来事の回数を返す
## (留まる所の添字 -> 回数)。
## 出来事は、所に着いてから interval 秒ごと (着いて interval 秒後・2 × interval 秒後…) に 1 回起き、留まる秒数を超えると起きない。
## 区間を分けて求めた回数の和は、まとめて求めた回数と同じになる (時間の刻み方で回数が変わらない)
static func ticks_between(
	route: Dictionary, from_seconds: float, to_seconds: float, interval: float
) -> Dictionary:
	var result: Dictionary = {}
	var stops: Array = route["stops"]
	var cycle: float = float(route["cycle_seconds"])
	if to_seconds <= from_seconds or stops.is_empty() or cycle <= 0.0 or interval <= 0.0:
		return result
	for cycle_index: int in range(floori(from_seconds / cycle), floori(to_seconds / cycle) + 1):
		var stop_start: float = float(cycle_index) * cycle
		for index: int in range(stops.size()):
			var seconds: float = float(stops[index]["seconds"])
			var low: float = clampf(from_seconds - stop_start, 0.0, seconds)
			var high: float = clampf(to_seconds - stop_start, 0.0, seconds)
			stop_start += seconds
			var count: int = floori(high / interval) - floori(low / interval)
			if count > 0:
				result[index] = int(result.get(index, 0)) + count
	return result

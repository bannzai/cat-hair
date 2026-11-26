extends RefCounted
## 決まった所を順に回り、1 か所に決まった秒数ずつ留まる動き (猫の通り道・掃除ロボットの回る順) の時刻の計算 (純粋な計算)。
## 道のりは {"cycle_seconds": 一巡の秒数, "stops": [{"point": 留まる所のワールド座標, "seconds": 留まる秒数, ...}]} の形で、
## 時刻 0 に最初の所に着き、一巡したら最初の所へ戻って繰り返す。

## 留まる所へ前の所から移る秒数 (留まる秒数の初めに含める)。隣の部屋 (中心どうし 6 m ほど) へ歩いて移って見える長さで、立ち止まる 8 秒の 4 分の 1 に収めた
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


## 時刻 clock_seconds の位置。着いてから MOVE_SECONDS 秒は前の所から歩いて移り、その後は留まる所にいる (道のりが空なら原点)
static func position_at(route: Dictionary, clock_seconds: float) -> Vector3:
	var index: int = stop_index_at(route, clock_seconds)
	if index < 0:
		return Vector3.ZERO
	var stops: Array = route["stops"]
	return (stops[(index - 1 + stops.size()) % stops.size()]["point"] as Vector3).lerp(
		stops[index]["point"],
		clampf(seconds_in_stop(route, clock_seconds) / MOVE_SECONDS, 0.0, 1.0),
	)


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

class_name MansionTuning
extends Resource
## 屋敷の作りを決める開発者向けの調整値。
## 屋敷の組み立てはこの値を入力にし、セーブデータとコマンドライン引数から復元できる。

const MIN_HAIR_COUNT: int = 0
const MAX_HAIR_COUNT: int = 10000000
const DEFAULT_HAIR_COUNT: int = 12000

const MIN_FOUND_ITEM_COUNT: int = 0
const MAX_FOUND_ITEM_COUNT: int = 200
const DEFAULT_FOUND_ITEM_COUNT: int = 5

const MIN_ROOM_SIZE_M: float = 4.0
const MAX_ROOM_SIZE_M: float = 16.0
const DEFAULT_ROOM_SIZE_M: float = 6.0

const MIN_OBJECT_COUNT: int = 0
const MAX_OBJECT_COUNT: int = 200
const DEFAULT_OBJECT_COUNT: int = 16

const MIN_ROOM_COUNT: int = 1
const MAX_ROOM_COUNT: int = 16
const DEFAULT_ROOM_COUNT: int = 4

## 屋敷全体の毛の総本数
@export var hair_count: int = DEFAULT_HAIR_COUNT
## 屋敷に埋める探し物の数
@export var found_item_count: int = DEFAULT_FOUND_ITEM_COUNT
## 屋敷の広さを決める 1 部屋の基準幅 (m)
@export var room_size_m: float = DEFAULT_ROOM_SIZE_M
## 屋敷に置く物 (家具・カーペット・ソファ・住人の服等) の総数
@export var object_count: int = DEFAULT_OBJECT_COUNT
## 屋敷の 1 階の部屋数
@export var room_count: int = DEFAULT_ROOM_COUNT


## すべての値を許容範囲に丸めた新しい調整値を返す
func clamped() -> MansionTuning:
	var result: MansionTuning = MansionTuning.new()
	result.hair_count = clampi(hair_count, MIN_HAIR_COUNT, MAX_HAIR_COUNT)
	result.found_item_count = clampi(found_item_count, MIN_FOUND_ITEM_COUNT, MAX_FOUND_ITEM_COUNT)
	result.room_size_m = clampf(room_size_m, MIN_ROOM_SIZE_M, MAX_ROOM_SIZE_M)
	result.object_count = clampi(object_count, MIN_OBJECT_COUNT, MAX_OBJECT_COUNT)
	result.room_count = clampi(room_count, MIN_ROOM_COUNT, MAX_ROOM_COUNT)
	return result


## 別の調整値とすべての値が一致するか
func equals(other: MansionTuning) -> bool:
	if other == null:
		return false
	return (
		hair_count == other.hair_count
		and found_item_count == other.found_item_count
		and is_equal_approx(room_size_m, other.room_size_m)
		and object_count == other.object_count
		and room_count == other.room_count
	)


## JSON 保存用の辞書に変換する
func to_dict() -> Dictionary:
	var safe: MansionTuning = clamped()
	return {
		"hair_count": safe.hair_count,
		"found_item_count": safe.found_item_count,
		"room_size_m": safe.room_size_m,
		"object_count": safe.object_count,
		"room_count": safe.room_count,
	}


## 辞書から調整値を復元する。不正な値や欠損がある場合は null を返す
static func from_dict(data: Variant) -> MansionTuning:
	if not (data is Dictionary):
		return null
	var dict: Dictionary = data
	for key: String in [
		"hair_count",
		"found_item_count",
		"room_size_m",
		"object_count",
		"room_count",
	]:
		if not dict.has(key):
			return null
		var val: Variant = dict[key]
		if not (val is int or val is float):
			return null
	var tuning: MansionTuning = MansionTuning.new()
	tuning.hair_count = int(dict["hair_count"])
	tuning.found_item_count = int(dict["found_item_count"])
	tuning.room_size_m = float(dict["room_size_m"])
	tuning.object_count = int(dict["object_count"])
	tuning.room_count = int(dict["room_count"])
	return tuning.clamped()


## コマンドライン引数 (--hair-count=... 等) を base に上書きした調整値を返す。
## 指定が 1 つも無い場合は base の複製を返す。
static func from_cmdline_args(
	args: PackedStringArray,
	base: MansionTuning = null,
) -> MansionTuning:
	var result: MansionTuning = base.clamped() if base != null else MansionTuning.new()
	for arg: String in args:
		if arg.begins_with("--hair-count="):
			var raw: String = arg.substr("--hair-count=".length())
			if raw.is_valid_int():
				result.hair_count = raw.to_int()
		elif arg.begins_with("--found-item-count="):
			var raw: String = arg.substr("--found-item-count=".length())
			if raw.is_valid_int():
				result.found_item_count = raw.to_int()
		elif arg.begins_with("--room-size="):
			var raw: String = arg.substr("--room-size=".length())
			if raw.is_valid_float():
				result.room_size_m = raw.to_float()
		elif arg.begins_with("--object-count="):
			var raw: String = arg.substr("--object-count=".length())
			if raw.is_valid_int():
				result.object_count = raw.to_int()
		elif arg.begins_with("--room-count="):
			var raw: String = arg.substr("--room-count=".length())
			if raw.is_valid_int():
				result.room_count = raw.to_int()
	return result.clamped()


## 引数の中に調整値の上書き指定が 1 つ以上含まれているか
static func has_cmdline_override(args: PackedStringArray) -> bool:
	for arg: String in args:
		if (
			arg.begins_with("--hair-count=")
			or arg.begins_with("--found-item-count=")
			or arg.begins_with("--room-size=")
			or arg.begins_with("--object-count=")
			or arg.begins_with("--room-count=")
		):
			return true
	return false

class_name MansionTuning
extends Resource
## 屋敷の作りを決める開発者向けの調整値。
## 屋敷の組み立てはこの値を入力にし、セーブデータとコマンドライン引数から復元できる。

## 境界テスト要件 (毛 0 本で組み立て可能) を満たす最小値
const MIN_HAIR_COUNT: int = 0
## PROJECT.md の「数百万本」を余裕をもって試せる上限 (1,000 万本)
const MAX_HAIR_COUNT: int = 10000000
## 既定の毛の本数。屋敷が毛で溢れていると数字で伝わる 9,999,999 本 (owner の指示。issue #65)。
## 1 本ずつ描くのは HairField.draw_budget の本数までで、残りは埋もれた毛として数だけ持つ
const DEFAULT_HAIR_COUNT: int = 9999999

## 探し物を置かない境界テストを許す最小値
const MIN_FOUND_ITEM_COUNT: int = 0
## 最大 16 部屋に対して各部屋 10 個超まで試験配置できる上限
const MAX_FOUND_ITEM_COUNT: int = 200
## 既定 4 部屋に対して 1 部屋あたり 1〜2 個の探し物が入る初期値
const DEFAULT_FOUND_ITEM_COUNT: int = 5

## ドア幅 1.8m と左右の壁・家具の配置余白を確保できる最小部屋幅 (m)
const MIN_ROOM_SIZE_M: float = 4.0
## 一人称カメラの遠平面 120m 内に最大 4x4 部屋が収まる 1 部屋幅の上限 (m)
const MAX_ROOM_SIZE_M: float = 16.0
## 家具 4 個前後を置いても中央のカーペットと通路が確保できる標準部屋幅 (m)
const DEFAULT_ROOM_SIZE_M: float = 6.0

## 床表面のみで屋敷を組み立てる境界テストを許す最小値
const MIN_OBJECT_COUNT: int = 0
## 最大 16 部屋に 1 部屋あたり十数個まで家具を試験配置できる上限
const MAX_OBJECT_COUNT: int = 200
## 既定 4 部屋に 1 部屋あたり 4 個の家具・布を均等配置できる初期値
const DEFAULT_OBJECT_COUNT: int = 16

## 屋敷として成立する最小部屋数 (境界要件: 部屋 1 つ)
const MIN_ROOM_COUNT: int = 1
## 4x4 グリッドの 1 階構成として移動・描画負荷を抑えられる上限
const MAX_ROOM_COUNT: int = 16
## 2x2 グリッドで複数部屋のドア開口と隣室の見通しを確認できる初期値
const DEFAULT_ROOM_COUNT: int = 4

## 毛の総本数を上書きするコマンドライン引数プレフィックス
const ARG_HAIR_COUNT: String = "--hair-count="
## 埋める探し物の数を上書きするコマンドライン引数プレフィックス
const ARG_FOUND_ITEM_COUNT: String = "--found-item-count="
## 1 部屋の基準幅 (m) を上書きするコマンドライン引数プレフィックス
const ARG_ROOM_SIZE: String = "--room-size="
## 物の総数を上書きするコマンドライン引数プレフィックス
const ARG_OBJECT_COUNT: String = "--object-count="
## 部屋数を上書きするコマンドライン引数プレフィックス
const ARG_ROOM_COUNT: String = "--room-count="
## 調整値の上書きに使う全コマンドライン引数プレフィックス一覧 (単一情報源)
const CMDLINE_ARG_PREFIXES: Array[String] = [
	ARG_HAIR_COUNT,
	ARG_FOUND_ITEM_COUNT,
	ARG_ROOM_SIZE,
	ARG_OBJECT_COUNT,
	ARG_ROOM_COUNT,
]

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
func equals(other_tuning: MansionTuning) -> bool:
	if other_tuning == null:
		return false
	return (
		hair_count == other_tuning.hair_count
		and found_item_count == other_tuning.found_item_count
		and is_equal_approx(room_size_m, other_tuning.room_size_m)
		and object_count == other_tuning.object_count
		and room_count == other_tuning.room_count
	)


## JSON 保存用の辞書に変換する
func to_dict() -> Dictionary:
	var safe_tuning: MansionTuning = clamped()
	return {
		"hair_count": safe_tuning.hair_count,
		"found_item_count": safe_tuning.found_item_count,
		"room_size_m": safe_tuning.room_size_m,
		"object_count": safe_tuning.object_count,
		"room_count": safe_tuning.room_count,
	}


## 辞書から調整値を復元する。不正な値や欠損がある場合は null を返す
static func from_dict(raw_tuning_dict: Variant) -> MansionTuning:
	if not (raw_tuning_dict is Dictionary):
		return null
	var tuning_dict: Dictionary = raw_tuning_dict
	for field_key: String in [
		"hair_count",
		"found_item_count",
		"room_size_m",
		"object_count",
		"room_count",
	]:
		if not tuning_dict.has(field_key):
			return null
		var field_value: Variant = tuning_dict[field_key]
		if not (field_value is int or field_value is float):
			return null
	var tuning: MansionTuning = MansionTuning.new()
	tuning.hair_count = int(tuning_dict["hair_count"])
	tuning.found_item_count = int(tuning_dict["found_item_count"])
	tuning.room_size_m = float(tuning_dict["room_size_m"])
	tuning.object_count = int(tuning_dict["object_count"])
	tuning.room_count = int(tuning_dict["room_count"])
	return tuning.clamped()


## コマンドライン引数 (--hair-count=... 等) を base_tuning に上書きした調整値を返す。
## 指定が 1 つも無い場合は base_tuning の複製を返す。
static func from_cmdline_args(
	cmdline_args: PackedStringArray,
	base_tuning: MansionTuning = null,
) -> MansionTuning:
	var result: MansionTuning = (
		base_tuning.clamped() if base_tuning != null else MansionTuning.new()
	)
	for arg: String in cmdline_args:
		if arg.begins_with(ARG_HAIR_COUNT):
			var raw_int: String = arg.substr(ARG_HAIR_COUNT.length())
			if raw_int.is_valid_int():
				result.hair_count = raw_int.to_int()
		elif arg.begins_with(ARG_FOUND_ITEM_COUNT):
			var raw_int: String = arg.substr(ARG_FOUND_ITEM_COUNT.length())
			if raw_int.is_valid_int():
				result.found_item_count = raw_int.to_int()
		elif arg.begins_with(ARG_ROOM_SIZE):
			var raw_float: String = arg.substr(ARG_ROOM_SIZE.length())
			if raw_float.is_valid_float():
				result.room_size_m = raw_float.to_float()
		elif arg.begins_with(ARG_OBJECT_COUNT):
			var raw_int: String = arg.substr(ARG_OBJECT_COUNT.length())
			if raw_int.is_valid_int():
				result.object_count = raw_int.to_int()
		elif arg.begins_with(ARG_ROOM_COUNT):
			var raw_int: String = arg.substr(ARG_ROOM_COUNT.length())
			if raw_int.is_valid_int():
				result.room_count = raw_int.to_int()
	return result.clamped()


## 引数の中に調整値の上書き指定が 1 つ以上含まれているか
static func has_cmdline_override(cmdline_args: PackedStringArray) -> bool:
	for arg: String in cmdline_args:
		for prefix: String in CMDLINE_ARG_PREFIXES:
			if arg.begins_with(prefix):
				return true
	return false

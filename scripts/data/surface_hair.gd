class_name SurfaceHair
extends Resource
## 建物の中の 1 つの面 (居間の床・ソファ・住人のスーツ等) に残っている毛の本数。

## 標準の毛の色 (白・黒・三毛)
const COLOR_WHITE: StringName = &"white"
const COLOR_BLACK: StringName = &"black"
const COLOR_CALICO: StringName = &"calico"
const STANDARD_COLORS: Array[StringName] = [COLOR_WHITE, COLOR_BLACK, COLOR_CALICO]

## 建物のどの面か
@export var surface_id: StringName = &""
## 色 (白・黒・三毛) ごとの残り本数 (StringName -> int)
@export var hair_counts: Dictionary = {}


## この面に残っている毛の合計本数を返す
func total_count() -> int:
	var total: int = 0
	for color_key: Variant in hair_counts.keys():
		total += maxi(0, int(hair_counts[color_key]))
	return total


## 指定した色の毛の本数を返す
func count_for_color(color_id: StringName) -> int:
	if not hair_counts.has(color_id):
		return 0
	return maxi(0, int(hair_counts[color_id]))


## JSON 保存用の辞書に変換する
func to_dict() -> Dictionary:
	var counts_out: Dictionary = {}
	for color_key: Variant in hair_counts.keys():
		counts_out[String(color_key)] = maxi(0, int(hair_counts[color_key]))
	return {
		"surface_id": String(surface_id),
		"hair_counts": counts_out,
	}


## 辞書から復元する。不正な構造の場合は null を返す
static func from_dict(data: Variant) -> SurfaceHair:
	if not (data is Dictionary):
		return null
	var dict: Dictionary = data
	if not (dict.get("surface_id") is String):
		return null
	var raw_counts: Variant = dict.get("hair_counts")
	if not (raw_counts is Dictionary):
		return null
	var item: SurfaceHair = SurfaceHair.new()
	item.surface_id = StringName(dict["surface_id"])
	var counts_dict: Dictionary = raw_counts
	for color_key: Variant in counts_dict.keys():
		if not (color_key is String):
			return null
		var val: Variant = counts_dict[color_key]
		if not (val is int or val is float):
			return null
		item.hair_counts[StringName(color_key)] = maxi(0, int(val))
	return item

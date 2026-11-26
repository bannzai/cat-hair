class_name SurfaceHair
extends Resource
## 建物の中の 1 つの面 (居間の床・ソファ・住人のスーツ等) に残っている毛の本数。

## 標準の毛の色 (白・黒・三毛。PROJECT.md「道具」の毛の加工機の色仕分けに対応)
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
static func from_dict(raw_surface_dict: Variant) -> SurfaceHair:
	if not (raw_surface_dict is Dictionary):
		return null
	var surface_dict: Dictionary = raw_surface_dict
	if not (surface_dict.get("surface_id") is String):
		return null
	var raw_counts: Variant = surface_dict.get("hair_counts")
	if not (raw_counts is Dictionary):
		return null
	var surface_hair: SurfaceHair = SurfaceHair.new()
	surface_hair.surface_id = StringName(surface_dict["surface_id"])
	var counts_dict: Dictionary = raw_counts
	for color_key: Variant in counts_dict.keys():
		if not (color_key is String):
			return null
		var count_value: Variant = counts_dict[color_key]
		if not (count_value is int or count_value is float):
			return null
		surface_hair.hair_counts[StringName(color_key)] = maxi(0, int(count_value))
	return surface_hair

class_name BuildingRecord
extends Resource
## 終えた建物 1 つの成績。

## どの建物か (屋敷・ホテル・猫島・街全体)
@export var building_id: StringName = &""
## 住人全員がご機嫌になるまでにかかった時間 (秒)。表示するだけで報酬には効かない
@export var clear_seconds: float = 0.0
## 住人に返した探し物の数。持ち越す手の強化の量に効く
@export var returned_found_item_count: int = 0


## JSON 保存用の辞書に変換する
func to_dict() -> Dictionary:
	return {
		"building_id": String(building_id),
		"clear_seconds": maxf(0.0, clear_seconds),
		"returned_found_item_count": maxi(0, returned_found_item_count),
	}


## 辞書から復元する。不正な構造の場合は null を返す
static func from_dict(data: Variant) -> BuildingRecord:
	if not (data is Dictionary):
		return null
	var dict: Dictionary = data
	if not (dict.get("building_id") is String):
		return null
	var raw_seconds: Variant = dict.get("clear_seconds")
	var raw_returned: Variant = dict.get("returned_found_item_count")
	if not (raw_seconds is int or raw_seconds is float):
		return null
	if not (raw_returned is int or raw_returned is float):
		return null
	var record: BuildingRecord = BuildingRecord.new()
	record.building_id = StringName(dict["building_id"])
	record.clear_seconds = maxf(0.0, float(raw_seconds))
	record.returned_found_item_count = maxi(0, int(raw_returned))
	return record

class_name FoundItemProgress
extends Resource
## 探し物 1 つの状態。

## 探し物の状態
enum Condition {
	## 毛の山の中にあり、まだ見つけていない
	HIDDEN = 0,
	## 見つけたが、毛が付いたまま
	FOUND = 1,
	## 合う道具で毛を取り切った
	CLEAN = 2,
	## 合わない道具で取って傷めた
	DAMAGED = 3,
}

## どの探し物か (FoundItemDef の id)
@export var found_item_id: StringName = &""
## 今の状態
@export var condition: Condition = Condition.HIDDEN
## 持ち主の住人に返したか
@export var is_returned: bool = false


## JSON 保存用の辞書に変換する
func to_dict() -> Dictionary:
	return {
		"found_item_id": String(found_item_id),
		"condition": int(condition),
		"is_returned": is_returned,
	}


## 辞書から復元する。不正な構造の場合は null を返す
static func from_dict(data: Variant) -> FoundItemProgress:
	if not (data is Dictionary):
		return null
	var dict: Dictionary = data
	if not (dict.get("found_item_id") is String):
		return null
	var raw_cond: Variant = dict.get("condition")
	if not (raw_cond is int or raw_cond is float):
		return null
	var cond_int: int = int(raw_cond)
	if cond_int < Condition.HIDDEN or cond_int > Condition.DAMAGED:
		return null
	var raw_returned: Variant = dict.get("is_returned")
	if not (raw_returned is bool):
		return null
	var progress: FoundItemProgress = FoundItemProgress.new()
	progress.found_item_id = StringName(dict["found_item_id"])
	progress.condition = cond_int as Condition
	progress.is_returned = raw_returned
	return progress

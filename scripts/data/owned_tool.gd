class_name OwnedTool
extends Resource
## 買った道具 1 つ。同じ掃除ロボットを 2 台買った時に別々の巡回順を持てるよう 1 件ずつ保持する。

## どの道具か (ToolDef の id)
@export var tool_id: StringName = &""
## 道具のレベル (購入直後は 1)。上げると取りこぼしが減る
@export var level: int = 1
## 消耗品の残り (粘着ローラーの紙の枚数等)。消耗品の無い道具は 0
@export var consumable_count: int = 0
## 掃除ロボットが回る部屋 (回る順)。掃除ロボットでない道具は空
@export var robot_room_ids: Array[StringName] = []


## JSON 保存用の辞書に変換する
func to_dict() -> Dictionary:
	var rooms_out: Array[String] = []
	for room_id: StringName in robot_room_ids:
		rooms_out.append(String(room_id))
	return {
		"tool_id": String(tool_id),
		"level": maxi(1, level),
		"consumable_count": maxi(0, consumable_count),
		"robot_room_ids": rooms_out,
	}


## 辞書から復元する。不正な構造の場合は null を返す
static func from_dict(raw_tool_dict: Variant) -> OwnedTool:
	if not (raw_tool_dict is Dictionary):
		return null
	var tool_dict: Dictionary = raw_tool_dict
	if not (tool_dict.get("tool_id") is String):
		return null
	var raw_level: Variant = tool_dict.get("level")
	var raw_consumable: Variant = tool_dict.get("consumable_count")
	var raw_rooms: Variant = tool_dict.get("robot_room_ids")
	if not (raw_level is int or raw_level is float):
		return null
	if not (raw_consumable is int or raw_consumable is float):
		return null
	if not (raw_rooms is Array):
		return null
	var owned_tool: OwnedTool = OwnedTool.new()
	owned_tool.tool_id = StringName(tool_dict["tool_id"])
	owned_tool.level = maxi(1, int(raw_level))
	owned_tool.consumable_count = maxi(0, int(raw_consumable))
	for room_entry: Variant in raw_rooms:
		if not (room_entry is String):
			return null
		owned_tool.robot_room_ids.append(StringName(room_entry))
	return owned_tool

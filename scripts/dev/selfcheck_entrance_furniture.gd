extends RefCounted
## 玄関でつまむ対象の家具を検証する。


## 同じ家具が別の部屋や玄関の二巡目にもある配置で、入口側の机と壁掛けになる一着を確かめる。
static func run(checker: SceneTree, layout: MansionLayout) -> void:
	var entrance: MansionLayout.RoomDef = layout.rooms[0]
	var found_jacket: bool = false
	for obj: MansionLayout.ObjectDef in layout.objects:
		if obj.object_kind == MansionLayout.OBJECT_SUIT_RACK:
			if obj.room_id == entrance.room_id and not found_jacket:
				checker._check(obj.wall_mounted and obj.position.y > 0.0
					and obj.position.z < entrance.center.z and is_zero_approx(obj.rotation_y),
					"玄関の最初のスーツは奥の壁に持ち上げて掛ける")
				found_jacket = true
			else:
				checker._check(not obj.wall_mounted and is_zero_approx(obj.position.y),
					"別室と玄関の二着目以降のスーツは床に置く")
	checker._check(found_jacket, "玄関に壁掛けのスーツがある")
	for room_index: int in [0, 6]:
		var table: MansionLayout.ObjectDef = layout.objects[2 * layout.rooms.size() + room_index]
		checker._check(table.object_kind == MansionLayout.OBJECT_TABLE and (
			(table.position.z > layout.rooms[room_index].center.z) == (room_index == 0)),
			"同じ配置順の机は玄関だけ入口側へ寄せる")

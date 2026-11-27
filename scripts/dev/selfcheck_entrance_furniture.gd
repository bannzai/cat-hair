extends RefCounted
## 玄関でつまむ対象の家具を検証する。


## 同じ家具が別の部屋や玄関の二巡目にもある配置で、入口側の机と壁掛けになる一着を確かめる。
static func run(checker: SceneTree, layout: MansionLayout) -> void:
	if layout.rooms.size() < 7:
		checker._check(false, "玄関と同じ配置順を比較できる 7 部屋以上の検証用屋敷がある")
		return
	var entrance: MansionLayout.RoomDef = layout.rooms[0]
	var original_weight: float = MansionBuilder.FLOOR_HAIR_WEIGHT
	for obj: MansionLayout.ObjectDef in layout.objects:
		if obj.room_id == entrance.room_id:
			for preset: Dictionary in MansionBuilder.OBJECT_PRESETS:
				if preset["kind"] == obj.object_kind:
					original_weight += float(preset["weight"])
	var spread_weight: float = 0.0
	for surface: MansionLayout.SurfaceDef in layout.surfaces:
		if surface.room_id == entrance.room_id:
			spread_weight += surface.hair_weight
	checker._check(is_equal_approx(original_weight, spread_weight), "再配分で玄関全体の毛の重みを保つ")
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
	# 玄関と、同じ並びの家具を持つ別室で最初の机を比較する。
	for room_index: int in [0, 6]:
		var room: MansionLayout.RoomDef = layout.rooms[room_index]
		var found_table: bool = false
		for obj: MansionLayout.ObjectDef in layout.objects:
			if obj.room_id == room.room_id and obj.object_kind == MansionLayout.OBJECT_TABLE:
				checker._check((obj.position.z > room.center.z) == (room_index == 0),
					"同じ配置順の机は玄関だけ入口側へ寄せる")
				found_table = true
				break
		checker._check(found_table, "比較する部屋に机がある")

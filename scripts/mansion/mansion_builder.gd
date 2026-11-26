class_name MansionBuilder
extends RefCounted
## 調整値 (MansionTuning) を入力にして、屋敷 1 階のレイアウトと初期進行状態を
## 決定論的に組み立てる純粋ロジック。

const MansionTuningScript := preload("res://scripts/data/mansion_tuning.gd")
const MansionLayoutScript := preload("res://scripts/mansion/mansion_layout.gd")
const BuildingProgressScript := preload("res://scripts/data/building_progress.gd")
const SurfaceHairScript := preload("res://scripts/data/surface_hair.gd")
const FoundItemProgressScript := preload("res://scripts/data/found_item_progress.gd")

## 部屋名のプリセット (1 階)
const ROOM_PRESETS: Array[Dictionary] = [
	{"id": &"hall", "name": "玄関ホール"},
	{"id": &"living", "name": "居間"},
	{"id": &"study", "name": "書斎"},
	{"id": &"dining", "name": "食堂"},
	{"id": &"parlor", "name": "応接間"},
	{"id": &"bedroom", "name": "寝室"},
	{"id": &"guest_room", "name": "客間"},
	{"id": &"corridor", "name": "廊下"},
]

## 配置する物のプリセット。床・カーペット・ソファ・家具・住人のスーツ・ニットが揃う順
const OBJECT_PRESETS: Array[Dictionary] = [
	{
		"kind": &"carpet",
		"surface_type": MansionLayoutScript.SURFACE_CARPET,
		"size": Vector3(2.4, 0.03, 1.8),
		"weight": 2.2,
	},
	{
		"kind": &"sofa",
		"surface_type": MansionLayoutScript.SURFACE_SOFA,
		"size": Vector3(1.8, 0.85, 0.85),
		"weight": 1.8,
	},
	{
		"kind": &"table",
		"surface_type": MansionLayoutScript.SURFACE_FURNITURE,
		"size": Vector3(1.2, 0.72, 0.75),
		"weight": 1.0,
	},
	{
		"kind": &"suit_rack",
		"surface_type": MansionLayoutScript.SURFACE_SUIT,
		"size": Vector3(0.75, 1.55, 0.45),
		"weight": 1.3,
	},
	{
		"kind": &"knit_chair",
		"surface_type": MansionLayoutScript.SURFACE_KNIT,
		"size": Vector3(0.7, 0.85, 0.7),
		"weight": 1.4,
	},
	{
		"kind": &"sideboard",
		"surface_type": MansionLayoutScript.SURFACE_FURNITURE,
		"size": Vector3(1.4, 0.9, 0.5),
		"weight": 1.0,
	},
]

## 部屋内の相対スロット (部屋中心からの割合、-0.5..0.5。ドア開口と南側スポーンを避ける)
const ROOM_SLOTS: Array[Dictionary] = [
	{"rx": 0.0, "rz": -0.05, "rot": 0.0},
	{"rx": -0.27, "rz": -0.27, "rot": 0.0},
	{"rx": 0.27, "rz": -0.27, "rot": PI},
	{"rx": 0.27, "rz": 0.22, "rot": -PI * 0.5},
	{"rx": -0.27, "rz": 0.22, "rot": PI * 0.5},
	{"rx": -0.28, "rz": -0.04, "rot": PI * 0.5},
	{"rx": 0.28, "rz": -0.04, "rot": -PI * 0.5},
	{"rx": 0.0, "rz": -0.30, "rot": 0.0},
]


## 調整値から屋敷 1 階のレイアウトを組み立てる
static func build_layout(raw_tuning: MansionTuning) -> MansionLayout:
	var safe_tuning: MansionTuning = (
		raw_tuning.clamped() if raw_tuning != null else MansionTuningScript.new()
	)
	var layout: MansionLayout = MansionLayoutScript.new()
	layout.tuning = safe_tuning
	_build_rooms(layout, safe_tuning)
	_build_objects_and_surfaces(layout, safe_tuning)
	_build_found_item_spots(layout, safe_tuning)
	_configure_spawn(layout, safe_tuning)
	return layout


## 調整値とレイアウトから、新しい建物の初期進行状態を生成する
static func build_initial_progress(
	layout: MansionLayout,
	tuning: MansionTuning,
) -> BuildingProgress:
	var safe_tuning: MansionTuning = (
		tuning.clamped() if tuning != null else MansionTuningScript.new()
	)
	var progress: BuildingProgress = BuildingProgressScript.new()
	progress.building_id = BuildingProgressScript.BUILDING_MANSION
	progress.elapsed_seconds = 0.0
	progress.money = 0
	progress.surface_hairs = _distribute_hairs(layout, safe_tuning.hair_count)
	progress.hair_stocks = []
	progress.owned_tools = []
	progress.resident_moods = _build_initial_resident_moods(layout)
	progress.found_items = _build_initial_found_items(layout)
	return progress


## 部屋グリッドと隣接ドア開口を組み立てる
static func _build_rooms(layout: MansionLayout, tuning: MansionTuning) -> void:
	var count: int = tuning.room_count
	var cols: int = maxi(1, ceili(sqrt(float(count))))
	var room_size: float = tuning.room_size_m
	var grid_map: Dictionary = {}

	for idx: int in range(count):
		var gx: int = idx % cols
		var gz: int = idx / cols
		grid_map[Vector2i(gx, gz)] = idx

	for idx: int in range(count):
		var gx: int = idx % cols
		var gz: int = idx / cols
		var room: MansionLayout.RoomDef = MansionLayoutScript.RoomDef.new()
		if idx < ROOM_PRESETS.size():
			room.room_id = ROOM_PRESETS[idx]["id"]
			room.display_name = ROOM_PRESETS[idx]["name"]
		else:
			room.room_id = StringName("room_%d" % idx)
			room.display_name = "部屋 %d" % (idx + 1)
		room.grid_x = gx
		room.grid_z = gz
		room.center = Vector3(float(gx) * room_size, 0.0, -float(gz) * room_size)
		room.size = Vector3(room_size, MansionLayoutScript.CEILING_HEIGHT_M, room_size)
		room.open_north = grid_map.has(Vector2i(gx, gz + 1))
		room.open_south = grid_map.has(Vector2i(gx, gz - 1))
		room.open_east = grid_map.has(Vector2i(gx + 1, gz))
		room.open_west = grid_map.has(Vector2i(gx - 1, gz))
		layout.rooms.append(room)

		var floor_surface: MansionLayout.SurfaceDef = MansionLayoutScript.SurfaceDef.new()
		floor_surface.surface_id = StringName("%s_floor" % String(room.room_id))
		floor_surface.room_id = room.room_id
		floor_surface.surface_type = MansionLayoutScript.SURFACE_FLOOR
		floor_surface.center = Vector3(room.center.x, 0.01, room.center.z)
		floor_surface.extents = Vector2(maxf(1.0, room_size - 0.6), maxf(1.0, room_size - 0.6))
		floor_surface.hair_weight = 2.5
		layout.surfaces.append(floor_surface)


## 物を各部屋へ決定論的に配置し、それぞれの表面を登録する
static func _build_objects_and_surfaces(layout: MansionLayout, tuning: MansionTuning) -> void:
	var room_count: int = layout.rooms.size()
	if room_count == 0 or tuning.object_count <= 0:
		return
	var per_room_counts: Array[int] = []
	per_room_counts.resize(room_count)
	per_room_counts.fill(0)

	for obj_idx: int in range(tuning.object_count):
		var room_idx: int = obj_idx % room_count
		var room: MansionLayout.RoomDef = layout.rooms[room_idx]
		var local_idx: int = per_room_counts[room_idx]
		per_room_counts[room_idx] = local_idx + 1

		var preset_idx: int = (local_idx + room_idx) % OBJECT_PRESETS.size()
		var preset: Dictionary = OBJECT_PRESETS[preset_idx]
		var obj: MansionLayout.ObjectDef = MansionLayoutScript.ObjectDef.new()
		obj.object_id = StringName("obj_%d_%s" % [obj_idx, String(preset["kind"])])
		obj.room_id = room.room_id
		obj.object_kind = preset["kind"]
		obj.surface_type = preset["surface_type"]
		var raw_size: Vector3 = preset["size"]
		var max_footprint: float = maxf(0.5, room.size.x * 0.34)
		var fit_scale: float = minf(1.0, max_footprint / maxf(raw_size.x, raw_size.z))
		obj.size = Vector3(raw_size.x * fit_scale, raw_size.y, raw_size.z * fit_scale)

		var slot: Dictionary = ROOM_SLOTS[local_idx % ROOM_SLOTS.size()]
		var ring: int = local_idx / ROOM_SLOTS.size()
		var ring_shrink: float = pow(0.75, float(ring))
		var offset_x: float = float(slot["rx"]) * room.size.x * ring_shrink
		var offset_z: float = float(slot["rz"]) * room.size.z * ring_shrink
		if ring > 0:
			offset_x += (0.28 if (ring % 2 == 1) else -0.28)
			offset_z += (0.22 if ((local_idx % 2) == 0) else -0.22)
		var margin_x: float = maxf(0.35, obj.size.x * 0.5 + 0.2)
		var margin_z: float = maxf(0.35, obj.size.z * 0.5 + 0.2)
		var limit_x: float = maxf(0.1, room.size.x * 0.5 - margin_x)
		var limit_z: float = maxf(0.1, room.size.z * 0.5 - margin_z)
		offset_x = clampf(offset_x, -limit_x, limit_x)
		offset_z = clampf(offset_z, -limit_z, limit_z)

		obj.position = Vector3(room.center.x + offset_x, 0.0, room.center.z + offset_z)
		obj.rotation_y = float(slot["rot"])
		layout.objects.append(obj)

		var surface: MansionLayout.SurfaceDef = MansionLayoutScript.SurfaceDef.new()
		surface.surface_id = StringName("%s_surface" % String(obj.object_id))
		surface.room_id = room.room_id
		surface.surface_type = obj.surface_type
		surface.center = Vector3(obj.position.x, obj.size.y + 0.01, obj.position.z)
		surface.extents = Vector2(maxf(0.3, obj.size.x * 0.85), maxf(0.3, obj.size.z * 0.85))
		surface.hair_weight = float(preset["weight"])
		layout.surfaces.append(surface)


## 調整値で指定された数だけ、探し物の置き場所を決定論的に割り当てる
static func _build_found_item_spots(layout: MansionLayout, tuning: MansionTuning) -> void:
	if layout.surfaces.is_empty() or tuning.found_item_count <= 0:
		return
	var candidate_surfaces: Array[MansionLayout.SurfaceDef] = []
	for surface: MansionLayout.SurfaceDef in layout.surfaces:
		if surface.surface_type != MansionLayoutScript.SURFACE_FLOOR:
			candidate_surfaces.append(surface)
	if candidate_surfaces.is_empty():
		candidate_surfaces = layout.surfaces

	for idx: int in range(tuning.found_item_count):
		var surface: MansionLayout.SurfaceDef = candidate_surfaces[idx % candidate_surfaces.size()]
		var spot: MansionLayout.FoundItemSpotDef = MansionLayoutScript.FoundItemSpotDef.new()
		spot.found_item_id = StringName("found_item_%d" % idx)
		spot.room_id = surface.room_id
		spot.surface_id = surface.surface_id
		var angle: float = float(idx) * 2.3999632
		var radius_scale: float = 0.25 if idx < candidate_surfaces.size() else 0.38
		var jitter_x: float = cos(angle) * surface.extents.x * radius_scale
		var jitter_z: float = sin(angle) * surface.extents.y * radius_scale
		spot.position = Vector3(
			surface.center.x + jitter_x,
			surface.center.y + 0.05,
			surface.center.z + jitter_z,
		)
		layout.found_item_spots.append(spot)


## 一人称プレイヤーの初期スポーン位置を部屋 0 の南側寄りに設定し、部屋中央へ向ける
static func _configure_spawn(layout: MansionLayout, tuning: MansionTuning) -> void:
	if layout.rooms.is_empty():
		layout.spawn_position = Vector3.ZERO
		layout.spawn_yaw = 0.0
		return
	var first_room: MansionLayout.RoomDef = layout.rooms[0]
	var spawn_z_offset: float = maxf(0.9, tuning.room_size_m * 0.36)
	layout.spawn_position = Vector3(
		first_room.center.x,
		0.05,
		first_room.center.z + spawn_z_offset,
	)
	layout.spawn_yaw = 0.0


## 全表面へ毛を厳密に total_hair_count 本だけ決定論的に分配する
static func _distribute_hairs(
	layout: MansionLayout,
	total_hair_count: int,
) -> Array[SurfaceHair]:
	var result: Array[SurfaceHair] = []
	if layout.surfaces.is_empty():
		return result
	var safe_total: int = maxi(0, total_hair_count)
	var total_weight: float = 0.0
	for surface: MansionLayout.SurfaceDef in layout.surfaces:
		total_weight += maxf(0.01, surface.hair_weight)

	var allocated: Array[int] = []
	allocated.resize(layout.surfaces.size())
	var assigned_sum: int = 0
	for i: int in range(layout.surfaces.size()):
		var w: float = maxf(0.01, layout.surfaces[i].hair_weight)
		var share: int = int(floor(float(safe_total) * (w / total_weight)))
		allocated[i] = share
		assigned_sum += share

	var remainder: int = safe_total - assigned_sum
	var cursor: int = 0
	while remainder > 0:
		allocated[cursor % allocated.size()] += 1
		remainder -= 1
		cursor += 1

	for i: int in range(layout.surfaces.size()):
		var surface: MansionLayout.SurfaceDef = layout.surfaces[i]
		var entry: SurfaceHair = SurfaceHairScript.new()
		entry.surface_id = surface.surface_id
		entry.hair_counts = _split_by_color(allocated[i], i)
		result.append(entry)
	return result


## 1 面の本数を 3 色 (白・黒・三毛) に合計一致で分ける
static func _split_by_color(surface_total: int, surface_index: int) -> Dictionary:
	var white_count: int = 0
	var black_count: int = 0
	var calico_count: int = 0
	if surface_total > 0:
		var mode: int = surface_index % 3
		if mode == 0:
			white_count = int(floor(float(surface_total) * 0.5))
			black_count = int(floor(float(surface_total) * 0.3))
			calico_count = surface_total - white_count - black_count
		elif mode == 1:
			black_count = int(floor(float(surface_total) * 0.5))
			calico_count = int(floor(float(surface_total) * 0.3))
			white_count = surface_total - black_count - calico_count
		else:
			calico_count = int(floor(float(surface_total) * 0.45))
			white_count = int(floor(float(surface_total) * 0.35))
			black_count = surface_total - calico_count - white_count
	return {
		SurfaceHairScript.COLOR_WHITE: white_count,
		SurfaceHairScript.COLOR_BLACK: black_count,
		SurfaceHairScript.COLOR_CALICO: calico_count,
	}


## 各部屋に対応する住人の初期機嫌辞書を生成する
static func _build_initial_resident_moods(layout: MansionLayout) -> Dictionary:
	var moods: Dictionary = {}
	for room: MansionLayout.RoomDef in layout.rooms:
		var resident_id: StringName = StringName("resident_%s" % String(room.room_id))
		moods[resident_id] = 0.5
	return moods


## 探し物の置き場所ごとに対応する初期進捗 (HIDDEN) を生成する
static func _build_initial_found_items(layout: MansionLayout) -> Array[FoundItemProgress]:
	var items: Array[FoundItemProgress] = []
	for spot: MansionLayout.FoundItemSpotDef in layout.found_item_spots:
		var progress: FoundItemProgress = FoundItemProgressScript.new()
		progress.found_item_id = spot.found_item_id
		progress.condition = FoundItemProgressScript.Condition.HIDDEN
		progress.is_returned = false
		items.append(progress)
	return items

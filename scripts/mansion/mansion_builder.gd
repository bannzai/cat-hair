class_name MansionBuilder
extends RefCounted
## 調整値 (MansionTuning) を入力にして、屋敷 1 階のレイアウトと初期進行状態を
## 決定論的に組み立てる純粋ロジック。

## 開発者向け調整値型スクリプト
const MansionTuningScript := preload("res://scripts/data/mansion_tuning.gd")
## 屋敷レイアウト型スクリプト
const MansionLayoutScript := preload("res://scripts/mansion/mansion_layout.gd")
## 建物進行データ型スクリプト
const BuildingProgressScript := preload("res://scripts/data/building_progress.gd")
## 面ごとの毛データ型スクリプト
const SurfaceHairScript := preload("res://scripts/data/surface_hair.gd")
## 探し物進捗データ型スクリプト
const FoundItemProgressScript := preload("res://scripts/data/found_item_progress.gd")

## 床の毛分配重み。部屋全面を占める最大面積のため家具・布より大きく設定
const FLOOR_HAIR_WEIGHT: float = 2.5
## 住人の初期機嫌 (0.0 不機嫌 〜 1.0 ご機嫌の中間値。開始時点で増減の余地を残す)
const INITIAL_RESIDENT_MOOD: float = 0.5
## ソファ表面 (座面) の高さ比率。MansionWorld の座面メッシュ高さ比率の単一情報源
const SOFA_SEAT_HEIGHT_RATIO: float = 0.56
## 3 色分配で面インデックスに応じて主色・次点色へ割り振る比率 (3 色すべてが混ざりつつ偏りが見える値)
const PRIMARY_COLOR_RATIO_STANDARD: float = 0.50
## 3 色分配で標準パターンの次点色へ割り振る比率
const SECONDARY_COLOR_RATIO_STANDARD: float = 0.30
## 3 色分配で三毛主色パターンの主色へ割り振る比率
const PRIMARY_COLOR_RATIO_CALICO: float = 0.45
## 3 色分配で三毛主色パターンの次点色へ割り振る比率
const SECONDARY_COLOR_RATIO_CALICO: float = 0.35
## 家具 1 個の水平サイズを部屋幅の約 1/3 以下に収め、歩ける通路を残すための上限比率
const OBJECT_MAX_FOOTPRINT_RATIO: float = 0.34
## 1 部屋に 9 個目以降の家具を置く時に内側リングへ寄せる縮小比率 (周回ごとの重なりを避ける)
const RING_SHRINK_FACTOR: float = 0.75
## 内側リング配置時に X 軸へ交互にずらす距離 (m。家具どうしの完全一致を避ける)
const RING_STAGGER_X_M: float = 0.28
## 内側リング配置時に Z 軸へ交互にずらす距離 (m。家具どうしの完全一致を避ける)
const RING_STAGGER_Z_M: float = 0.22
## 家具と壁の間に確保する最小の余白 (m。壁の厚みとプレイヤー接触のゆとり)
const WALL_CLEARANCE_M: float = 0.20
## 家具サイズに関わらず壁際から離す下限距離 (m)
const MIN_WALL_MARGIN_M: float = 0.35
## 家具天面の縁から毛がはみ出さないよう表面範囲を絞る比率
const SURFACE_HAIR_EXTENT_RATIO: float = 0.85
## 探し物の置き場所を同一面内で均等分散させる黄金角 (ラジアン。約 137.5 度)
const GOLDEN_ANGLE_RAD: float = 2.3999632
## 探し物 1 周目の配置半径比率 (表面中央寄りに収める)
const SPOT_RADIUS_FIRST_PASS: float = 0.25
## 探し物 2 周目以降の配置半径比率 (1 周目と重ならない外周寄り)
const SPOT_RADIUS_OVERFLOW: float = 0.38
## 探し物置き場所を表面からわずかに浮かせて埋没を防ぐ高さオフセット (m)
const SPOT_HEIGHT_OFFSET_M: float = 0.05
## 初期スポーンを部屋中心から南側 (+Z) へ寄せる比率 (南壁を避けつつ部屋中央を見渡せる位置)
const SPAWN_BACK_OFFSET_RATIO: float = 0.36
## 最小部屋幅でも部屋中央から離して視界を確保するスポーン後方オフセット下限 (m)
const MIN_SPAWN_BACK_OFFSET_M: float = 0.9

## 屋敷 1 階の部屋名プリセット (先頭から順に使用し、9 部屋目以降は連番)
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

## 配置する物のプリセット。
## size は一般的な家具の標準寸法 (m)、weight は面積と布の毛の付きやすさによる分配相対比。
## 床・カーペット・ソファ・家具・住人のスーツ・ニットの全表面種別が揃う順で定義する。
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

## 部屋内の相対配置スロット (部屋中心からの割合、-0.5..0.5)。
## 4 壁中央のドア開口と南側 (+Z) の初期スポーン位置を避けた 8 位置。
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


## 部屋グリッドと隣接ドア開口および床表面を組み立てる
static func _build_rooms(layout: MansionLayout, tuning: MansionTuning) -> void:
	var room_total: int = tuning.room_count
	var grid_columns: int = maxi(1, ceili(sqrt(float(room_total))))
	var room_width: float = tuning.room_size_m
	var grid_cells: Dictionary = {}

	for room_idx: int in range(room_total):
		grid_cells[Vector2i(room_idx % grid_columns, room_idx / grid_columns)] = room_idx

	for room_idx: int in range(room_total):
		var grid_x: int = room_idx % grid_columns
		var grid_z: int = room_idx / grid_columns
		var room: MansionLayout.RoomDef = MansionLayoutScript.RoomDef.new()
		if room_idx < ROOM_PRESETS.size():
			room.room_id = ROOM_PRESETS[room_idx]["id"]
			room.display_name = ROOM_PRESETS[room_idx]["name"]
		else:
			room.room_id = StringName("room_%d" % room_idx)
			room.display_name = "部屋 %d" % (room_idx + 1)
		room.grid_x = grid_x
		room.grid_z = grid_z
		room.center = Vector3(float(grid_x) * room_width, 0.0, -float(grid_z) * room_width)
		room.size = Vector3(room_width, MansionLayoutScript.CEILING_HEIGHT_M, room_width)
		room.open_north = grid_cells.has(Vector2i(grid_x, grid_z + 1))
		room.open_south = grid_cells.has(Vector2i(grid_x, grid_z - 1))
		room.open_east = grid_cells.has(Vector2i(grid_x + 1, grid_z))
		room.open_west = grid_cells.has(Vector2i(grid_x - 1, grid_z))
		layout.rooms.append(room)

		var floor_surface: MansionLayout.SurfaceDef = MansionLayoutScript.SurfaceDef.new()
		floor_surface.surface_id = StringName("%s_floor" % String(room.room_id))
		floor_surface.room_id = room.room_id
		floor_surface.surface_type = MansionLayoutScript.SURFACE_FLOOR
		floor_surface.center = Vector3(room.center.x, 0.01, room.center.z)
		floor_surface.extents = Vector2(maxf(1.0, room_width - 0.6), maxf(1.0, room_width - 0.6))
		floor_surface.hair_weight = FLOOR_HAIR_WEIGHT
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

		var preset: Dictionary = OBJECT_PRESETS[(local_idx + room_idx) % OBJECT_PRESETS.size()]
		var obj: MansionLayout.ObjectDef = MansionLayoutScript.ObjectDef.new()
		obj.object_id = StringName("obj_%d_%s" % [obj_idx, String(preset["kind"])])
		obj.room_id = room.room_id
		obj.object_kind = preset["kind"]
		obj.surface_type = preset["surface_type"]
		var raw_size: Vector3 = preset["size"]
		var fit_scale: float = minf(
			1.0,
			maxf(0.5, room.size.x * OBJECT_MAX_FOOTPRINT_RATIO) / maxf(raw_size.x, raw_size.z),
		)
		obj.size = Vector3(raw_size.x * fit_scale, raw_size.y, raw_size.z * fit_scale)

		var slot: Dictionary = ROOM_SLOTS[local_idx % ROOM_SLOTS.size()]
		var ring: int = local_idx / ROOM_SLOTS.size()
		var ring_shrink: float = pow(RING_SHRINK_FACTOR, float(ring))
		var offset_x: float = float(slot["rx"]) * room.size.x * ring_shrink
		var offset_z: float = float(slot["rz"]) * room.size.z * ring_shrink
		if ring > 0:
			offset_x += RING_STAGGER_X_M if (ring % 2 == 1) else -RING_STAGGER_X_M
			offset_z += RING_STAGGER_Z_M if ((local_idx % 2) == 0) else -RING_STAGGER_Z_M
		var limit_x: float = maxf(
			0.1,
			room.size.x * 0.5 - maxf(MIN_WALL_MARGIN_M, obj.size.x * 0.5 + WALL_CLEARANCE_M),
		)
		var limit_z: float = maxf(
			0.1,
			room.size.z * 0.5 - maxf(MIN_WALL_MARGIN_M, obj.size.z * 0.5 + WALL_CLEARANCE_M),
		)
		offset_x = clampf(offset_x, -limit_x, limit_x)
		offset_z = clampf(offset_z, -limit_z, limit_z)

		obj.position = Vector3(room.center.x + offset_x, 0.0, room.center.z + offset_z)
		obj.rotation_y = float(slot["rot"])
		layout.objects.append(obj)

		var surface: MansionLayout.SurfaceDef = MansionLayoutScript.SurfaceDef.new()
		surface.surface_id = StringName("%s_surface" % String(obj.object_id))
		surface.room_id = room.room_id
		surface.surface_type = obj.surface_type
		surface.center = Vector3(
			obj.position.x,
			(obj.size.y * SOFA_SEAT_HEIGHT_RATIO if obj.object_kind == &"sofa" else obj.size.y)
			+ 0.01,
			obj.position.z,
		)
		surface.extents = Vector2(
			maxf(0.3, obj.size.x * SURFACE_HAIR_EXTENT_RATIO),
			maxf(0.3, obj.size.z * SURFACE_HAIR_EXTENT_RATIO),
		)
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

	for spot_idx: int in range(tuning.found_item_count):
		var surface: MansionLayout.SurfaceDef = (
			candidate_surfaces[spot_idx % candidate_surfaces.size()]
		)
		var spot: MansionLayout.FoundItemSpotDef = MansionLayoutScript.FoundItemSpotDef.new()
		spot.found_item_id = StringName("found_item_%d" % spot_idx)
		spot.room_id = surface.room_id
		spot.surface_id = surface.surface_id
		var angle_rad: float = float(spot_idx) * GOLDEN_ANGLE_RAD
		var radius_scale: float = (
			SPOT_RADIUS_FIRST_PASS
			if spot_idx < candidate_surfaces.size()
			else SPOT_RADIUS_OVERFLOW
		)
		spot.position = Vector3(
			surface.center.x + cos(angle_rad) * surface.extents.x * radius_scale,
			surface.center.y + SPOT_HEIGHT_OFFSET_M,
			surface.center.z + sin(angle_rad) * surface.extents.y * radius_scale,
		)
		layout.found_item_spots.append(spot)


## 一人称プレイヤーの初期スポーン位置を部屋 0 の南側寄りに設定し、部屋中央へ向ける
static func _configure_spawn(layout: MansionLayout, tuning: MansionTuning) -> void:
	if layout.rooms.is_empty():
		layout.spawn_position = Vector3.ZERO
		layout.spawn_yaw = 0.0
		return
	var first_room: MansionLayout.RoomDef = layout.rooms[0]
	layout.spawn_position = Vector3(
		first_room.center.x,
		0.05,
		first_room.center.z
		+ maxf(MIN_SPAWN_BACK_OFFSET_M, tuning.room_size_m * SPAWN_BACK_OFFSET_RATIO),
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
	for surface_idx: int in range(layout.surfaces.size()):
		var share: int = int(
			floor(
				float(safe_total)
				* (maxf(0.01, layout.surfaces[surface_idx].hair_weight) / total_weight)
			)
		)
		allocated[surface_idx] = share
		assigned_sum += share

	var remainder: int = safe_total - assigned_sum
	var cursor: int = 0
	while remainder > 0:
		allocated[cursor % allocated.size()] += 1
		remainder -= 1
		cursor += 1

	for surface_idx: int in range(layout.surfaces.size()):
		var entry: SurfaceHair = SurfaceHairScript.new()
		entry.surface_id = layout.surfaces[surface_idx].surface_id
		entry.hair_counts = _split_by_color(allocated[surface_idx], surface_idx)
		result.append(entry)
	return result


## 1 面の本数を 3 色 (白・黒・三毛) に合計一致で分ける
static func _split_by_color(surface_total: int, surface_index: int) -> Dictionary:
	var white_count: int = 0
	var black_count: int = 0
	var calico_count: int = 0
	if surface_total > 0:
		var color_pattern: int = surface_index % 3
		if color_pattern == 0:
			white_count = int(floor(float(surface_total) * PRIMARY_COLOR_RATIO_STANDARD))
			black_count = int(floor(float(surface_total) * SECONDARY_COLOR_RATIO_STANDARD))
			calico_count = surface_total - white_count - black_count
		elif color_pattern == 1:
			black_count = int(floor(float(surface_total) * PRIMARY_COLOR_RATIO_STANDARD))
			calico_count = int(floor(float(surface_total) * SECONDARY_COLOR_RATIO_STANDARD))
			white_count = surface_total - black_count - calico_count
		else:
			calico_count = int(floor(float(surface_total) * PRIMARY_COLOR_RATIO_CALICO))
			white_count = int(floor(float(surface_total) * SECONDARY_COLOR_RATIO_CALICO))
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
		moods[StringName("resident_%s" % String(room.room_id))] = INITIAL_RESIDENT_MOOD
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

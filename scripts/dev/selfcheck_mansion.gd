extends RefCounted
## 屋敷生成・調整値・セーブデータ・プレイヤー純粋判定の検証スイート (scripts/dev/selfcheck.gd から呼ぶ)。

## メインシーンスクリプト (format_hair_count の検証に使用)
const MainScript := preload("res://scripts/main.gd")
## 開発者向け調整値データ型スクリプト
const MansionTuningScript := preload("res://scripts/data/mansion_tuning.gd")
## 屋敷レイアウト型スクリプト
const MansionLayoutScript := preload("res://scripts/mansion/mansion_layout.gd")
## 屋敷ビルダーロジックスクリプト
const MansionBuilderScript := preload("res://scripts/mansion/mansion_builder.gd")
## 3D 屋敷構築ノードスクリプト
const MansionWorldScript := preload("res://scripts/mansion/mansion_world.gd")
## 一人称プレイヤーノードスクリプト
const FirstPersonPlayerScript := preload("res://scripts/player/first_person_player.gd")
## 開発者向け調整パネルスクリプト (刻み値丸め回帰検証に使用)
const DevTuningPanelScript := preload("res://scripts/ui/dev_tuning_panel.gd")
## セーブデータ全体型スクリプト
const SaveDataScript := preload("res://scripts/data/save_data.gd")
## 建物進行データ型スクリプト
const BuildingProgressScript := preload("res://scripts/data/building_progress.gd")
## 終えた建物成績データ型スクリプト
const BuildingRecordScript := preload("res://scripts/data/building_record.gd")
## 毛・加工品在庫データ型スクリプト
const HairStockScript := preload("res://scripts/data/hair_stock.gd")
## 所持道具データ型スクリプト
const OwnedToolScript := preload("res://scripts/data/owned_tool.gd")
## 探し物進捗データ型スクリプト
const FoundItemProgressScript := preload("res://scripts/data/found_item_progress.gd")
## 面ごとの毛データ型スクリプト
const SurfaceHairScript := preload("res://scripts/data/surface_hair.gd")
## JSON 保存ストレージスクリプト
const SaveStorageScript := preload("res://scripts/state/save_storage.gd")
## 状態管理 autoload スクリプト
const GameStateScript := preload("res://scripts/state/game_state.gd")
## 次の建物へ進む決まり (成績が 1 つある保存データの今いる建物の作り)
const BuildingRulesScript := preload("res://scripts/building/building_rules.gd")

## selfcheck が使う一時セーブファイルパス
const TEST_SAVE_PATH: String = "user://selfcheck_save_data.json"

## 検証結果を記録する selfcheck の SceneTree 参照
var _checker: SceneTree = null


## 屋敷・調整値・セーブ・プレイヤー関連の純粋検証をすべて実行する
static func run_all(checker: SceneTree) -> void:
	var suite: RefCounted = load("res://scripts/dev/selfcheck_mansion.gd").new()
	suite._checker = checker
	suite._check_mansion_builder_default()
	suite._check_mansion_builder_changes_and_large_scale()
	suite._check_mansion_builder_boundaries()
	suite._check_tuning_equals_and_cmdline_args()
	suite._check_dev_tuning_panel_preserves_unaligned_values()
	suite._check_world_hair_and_light_limits()
	suite._check_player_mouse_predicates()
	suite._check_save_and_load_roundtrip()
	suite._check_save_missing_corrupted_and_clamping()
	suite._check_game_state_override_reconcile_and_notifications()
	suite._check_game_state_and_builder_edge_cases()
	suite._check_format_hair_count()
	SaveStorageScript.delete_save_file(TEST_SAVE_PATH)


## 検証結果を親の selfcheck へ委譲して記録する
func _check(cond: bool, label: String) -> void:
	_checker._check(cond, label)


## 既定の調整値で屋敷を組み立てた時、すべての要素数が調整値と一致し表面種別が揃うか
func _check_mansion_builder_default() -> void:
	var tuning: MansionTuning = MansionTuningScript.new()
	var layout: MansionLayout = MansionBuilderScript.build_layout(tuning)
	var progress: BuildingProgress = MansionBuilderScript.build_initial_progress(layout, tuning)

	_check(layout.rooms.size() == tuning.room_count, "部屋数が調整値と一致する")
	_check(layout.objects.size() == tuning.object_count, "物の数が調整値と一致する")
	_check(layout.found_item_spots.size() == tuning.found_item_count, "探し物の置き場所数が一致する")
	_check(progress.found_items.size() == tuning.found_item_count, "初期進捗の探し物数が一致する")
	_check(progress.total_remaining_hairs() == tuning.hair_count, "毛の総本数が調整値と一致する")
	_check(
		layout.surfaces.size() == tuning.room_count + tuning.object_count,
		"表面数が部屋数 + 物の数と一致する",
	)
	var found_types: Dictionary = {}
	for surface: MansionLayout.SurfaceDef in layout.surfaces:
		found_types[surface.surface_type] = true
	var req_types: Array[StringName] = [
		MansionLayoutScript.SURFACE_FLOOR, MansionLayoutScript.SURFACE_CARPET,
		MansionLayoutScript.SURFACE_SOFA, MansionLayoutScript.SURFACE_KNIT,
		MansionLayoutScript.SURFACE_SUIT, MansionLayoutScript.SURFACE_FURNITURE,
	]
	for required_type: StringName in req_types:
		_check(found_types.has(required_type), "表面の種類 %s が含まれる" % String(required_type))
	_check(
		layout.rooms[0].open_east and layout.rooms[1].open_west
		and layout.rooms[0].open_north and layout.rooms[2].open_south,
		"隣接部屋 0-1 (東西) と 0-2 (南北) の間にドア開口がある",
	)
	_check(
		layout.find_surface(layout.surfaces[0].surface_id) == layout.surfaces[0]
		and layout.find_surface(&"missing_surface") == null,
		"MansionLayout.find_surface が一致面と不在面を返す",
	)
	var rotated_checked: bool = false
	for obj: MansionLayout.ObjectDef in layout.objects:
		if absf(sin(obj.rotation_y)) > 0.5 and not is_equal_approx(obj.size.x, obj.size.z):
			var obj_surface: MansionLayout.SurfaceDef = layout.find_surface(
				StringName("%s_surface" % String(obj.object_id))
			)
			var face_size: Vector2 = MansionBuilderScript.object_surface_local_face(
				obj.object_kind, obj.size
			)["size"]
			var expected_x: float = maxf(
				MansionBuilderScript.MIN_SURFACE_EXTENT_M,
				face_size.x * MansionBuilderScript.SURFACE_HAIR_EXTENT_RATIO,
			)
			var expected_z: float = maxf(
				MansionBuilderScript.MIN_SURFACE_EXTENT_M,
				face_size.y * MansionBuilderScript.SURFACE_HAIR_EXTENT_RATIO,
			)
			var object_x_axis: Vector3 = Basis(Vector3.UP, obj.rotation_y).x
			_check(
				obj_surface != null
				and is_equal_approx(obj_surface.extents.x, expected_x)
				and is_equal_approx(obj_surface.extents.y, expected_z)
				and obj_surface.basis.x.is_equal_approx(object_x_axis),
				"90 度回転した家具 %s の表面の枠が物と同じ向きに回る" % String(obj.object_id),
			)
			rotated_checked = true
			break
	_check(rotated_checked, "既定レイアウトに 90 度回転かつ非正方形の家具が存在し検証できた")
	var sideboard_checked: bool = false
	for obj: MansionLayout.ObjectDef in layout.objects:
		if obj.object_kind == MansionLayoutScript.OBJECT_SIDEBOARD:
			var sb_surface: MansionLayout.SurfaceDef = layout.find_surface(
				StringName("%s_surface" % String(obj.object_id))
			)
			var expected_y: float = obj.size.y + MansionBuilderScript.SIDEBOARD_TOP_TRIM_HEIGHT_M
			_check(
				sb_surface != null and is_equal_approx(sb_surface.center.y, expected_y),
				"サイドボード表面高さが TopTrim 上面に一致する",
			)
			sideboard_checked = true
			break
	_check(sideboard_checked, "既定レイアウトにサイドボードが存在し天板高さを検証できた")


## 調整値変更・最大部屋数 (16 部屋・9 部屋目以降の連番 ID)・内側リング配置 (ring > 0)・物 200 個を検証する
func _check_mansion_builder_changes_and_large_scale() -> void:
	var custom: MansionTuning = MansionTuningScript.new()
	custom.room_count = 6
	custom.room_size_m = 9.0
	custom.object_count = 23
	custom.hair_count = 54321
	custom.found_item_count = 9
	var layout: MansionLayout = MansionBuilderScript.build_layout(custom)
	var progress: BuildingProgress = MansionBuilderScript.build_initial_progress(layout, custom)

	_check(layout.rooms.size() == 6, "変更後の部屋数が 6")
	_check(layout.objects.size() == 23, "変更後の物の数が 23")
	_check(layout.found_item_spots.size() == 9, "変更後の探し物置き場所数が 9")
	_check(progress.total_remaining_hairs() == 54321, "変更後の毛の総本数が 54321")
	_check(
		is_equal_approx(layout.total_floor_area(), 6.0 * 9.0 * 9.0)
		and layout.total_floor_area()
		> MansionBuilderScript.build_layout(MansionTuningScript.new()).total_floor_area(),
		"広さを広げると総床面積が計算通り増える",
	)

	# 最大 16 部屋 (9 部屋目以降は room_%d 命名) と物 200 個の上限を組み立てる
	var max_tuning: MansionTuning = MansionTuningScript.new()
	max_tuning.room_count = MansionTuningScript.MAX_ROOM_COUNT
	max_tuning.object_count = MansionTuningScript.MAX_OBJECT_COUNT
	max_tuning.found_item_count = MansionTuningScript.MAX_FOUND_ITEM_COUNT
	max_tuning.hair_count = 50000
	var max_layout: MansionLayout = MansionBuilderScript.build_layout(max_tuning)
	_check(max_layout.rooms.size() == MansionTuningScript.MAX_ROOM_COUNT, "最大 16 部屋を組み立てられる")
	_check(max_layout.rooms[8].room_id == &"room_8", "9 部屋目に連番 ID room_8 が付く")
	_check(max_layout.rooms[15].room_id == &"room_15", "16 部屋目に連番 ID room_15 が付く")
	_check(
		max_layout.objects.size() == MansionTuningScript.MAX_OBJECT_COUNT,
		"物の上限 200 個を組み立てられる",
	)

	# 最小部屋幅 (4.0m) に 12 個配置し、家具外縁が壁内に収まり 9 個目以降が 1 周目と重ならないことを検証
	var dense_tuning: MansionTuning = MansionTuningScript.new()
	dense_tuning.room_count = 1
	dense_tuning.object_count = 12
	dense_tuning.room_size_m = MansionTuningScript.MIN_ROOM_SIZE_M
	var dense_layout: MansionLayout = MansionBuilderScript.build_layout(dense_tuning)
	var half_room: float = MansionTuningScript.MIN_ROOM_SIZE_M * 0.5
	var all_edges_inside: bool = true
	for obj: MansionLayout.ObjectDef in dense_layout.objects:
		var half_extent: float = maxf(obj.size.x, obj.size.z) * 0.5
		if (
			absf(obj.position.x) + half_extent > half_room
			or absf(obj.position.z) + half_extent > half_room
		):
			all_edges_inside = false
	_check(
		dense_layout.objects.size() == 12
		and all_edges_inside
		and dense_layout.objects[8].position.distance_to(dense_layout.objects[0].position) > 0.1,
		"最小幅の 12 個配置で全家具外縁が壁内に収まり ring > 0 が 1 周目と重ならない",
	)
	var door_cases: Array[Array] = [[3, 24], [4, 20], [5, 92], [3, 79], [9, 120]]
	var all_doors_clear: bool = true
	var depth: float = MansionBuilderScript.DOOR_CORRIDOR_DEPTH_M - 0.005
	var hw: float = MansionBuilderScript.DOOR_CORRIDOR_HALF_WIDTH_M - 0.005
	for door_case: Array in door_cases:
		var dt: MansionTuning = MansionTuningScript.new()
		dt.room_count = int(door_case[0])
		dt.room_size_m = MansionTuningScript.MIN_ROOM_SIZE_M
		dt.object_count = int(door_case[1])
		var dl: MansionLayout = MansionBuilderScript.build_layout(dt)
		var room_map: Dictionary = {}
		for r: MansionLayout.RoomDef in dl.rooms:
			room_map[r.room_id] = r
		for obj: MansionLayout.ObjectDef in dl.objects:
			if obj.object_kind == MansionLayoutScript.OBJECT_CARPET:
				continue
			var rm: MansionLayout.RoomDef = room_map[obj.room_id]
			var c_rot: float = absf(cos(obj.rotation_y))
			var s_rot: float = absf(sin(obj.rotation_y))
			var hx: float = (c_rot * obj.size.x + s_rot * obj.size.z) * 0.5
			var hz: float = (s_rot * obj.size.x + c_rot * obj.size.z) * 0.5
			var lx: float = obj.position.x - rm.center.x
			var lz: float = obj.position.z - rm.center.z
			var blocked: bool = (
				absf(lx) + hx > half_room or absf(lz) + hz > half_room
				or (rm.open_north and lz - hz < -half_room + depth and absf(lx) < hw + hx)
				or (rm.open_south and lz + hz > half_room - depth and absf(lx) < hw + hx)
				or (rm.open_east and lx + hx > half_room - depth and absf(lz) < hw + hz)
				or (rm.open_west and lx - hx < -half_room + depth and absf(lz) < hw + hz)
			)
			if blocked:
				all_doors_clear = false
	_check(all_doors_clear, "最小幅 4m の全検証構成・全部屋・4 方向ドアで衝突家具が壁内に収まり通路を塞がない")


## 境界値 (最小・最大・下限未満・上限超過) で組み立てとクランプが正しく動くか検証する
func _check_mansion_builder_boundaries() -> void:
	var minimal: MansionTuning = MansionTuningScript.new()
	minimal.room_count = 1
	minimal.hair_count = 0
	minimal.object_count = 0
	minimal.found_item_count = 0
	minimal.room_size_m = MansionTuningScript.MIN_ROOM_SIZE_M
	var min_layout: MansionLayout = MansionBuilderScript.build_layout(minimal)
	var min_progress: BuildingProgress = MansionBuilderScript.build_initial_progress(
		min_layout,
		minimal,
	)

	_check(min_layout.rooms.size() == 1, "境界最小値で部屋数 1")
	_check(min_layout.objects.size() == 0, "境界最小値で物の数 0")
	_check(min_layout.surfaces.size() == 1, "境界最小値でも床表面が 1 つある")
	_check(min_layout.found_item_spots.size() == 0, "境界最小値で探し物置き場所 0")
	_check(min_progress.total_remaining_hairs() == 0, "境界最小値で毛の総本数 0")
	var only_room: MansionLayout.RoomDef = min_layout.rooms[0]
	_check(
		not only_room.open_north
		and not only_room.open_south
		and not only_room.open_east
		and not only_room.open_west,
		"部屋 1 つの時は 4 方向すべての壁が閉じている",
	)

	var floor_only: MansionTuning = MansionTuningScript.new()
	floor_only.room_count = 1
	floor_only.object_count = 0
	floor_only.hair_count = 7
	floor_only.found_item_count = 3
	var floor_layout: MansionLayout = MansionBuilderScript.build_layout(floor_only)
	var floor_progress: BuildingProgress = MansionBuilderScript.build_initial_progress(
		floor_layout,
		floor_only,
	)
	_check(floor_layout.found_item_spots.size() == 3, "物 0 個でも探し物 3 個を床に置ける")
	_check(floor_progress.total_remaining_hairs() == 7, "物 0 個でも毛 7 本が床へ分配される")

	var below_min: MansionTuning = MansionTuningScript.new()
	below_min.room_count = 0
	below_min.hair_count = -50
	below_min.object_count = -3
	below_min.found_item_count = -2
	below_min.room_size_m = MansionTuningScript.MIN_ROOM_SIZE_M - 1.5
	var clamped_min: MansionTuning = below_min.clamped()
	_check(
		clamped_min.room_count == MansionTuningScript.MIN_ROOM_COUNT
		and clamped_min.hair_count == MansionTuningScript.MIN_HAIR_COUNT
		and clamped_min.object_count == MansionTuningScript.MIN_OBJECT_COUNT
		and clamped_min.found_item_count == MansionTuningScript.MIN_FOUND_ITEM_COUNT
		and is_equal_approx(clamped_min.room_size_m, MansionTuningScript.MIN_ROOM_SIZE_M),
		"5 項目すべての下限未満が最小値へクランプされる",
	)

	var above_max: MansionTuning = MansionTuningScript.new()
	above_max.room_count = MansionTuningScript.MAX_ROOM_COUNT + 1
	above_max.hair_count = MansionTuningScript.MAX_HAIR_COUNT + 1
	above_max.object_count = MansionTuningScript.MAX_OBJECT_COUNT + 1
	above_max.found_item_count = MansionTuningScript.MAX_FOUND_ITEM_COUNT + 1
	above_max.room_size_m = MansionTuningScript.MAX_ROOM_SIZE_M + 1.0
	var clamped_max: MansionTuning = above_max.clamped()
	_check(
		clamped_max.room_count == MansionTuningScript.MAX_ROOM_COUNT
		and clamped_max.hair_count == MansionTuningScript.MAX_HAIR_COUNT
		and clamped_max.object_count == MansionTuningScript.MAX_OBJECT_COUNT
		and clamped_max.found_item_count == MansionTuningScript.MAX_FOUND_ITEM_COUNT
		and is_equal_approx(clamped_max.room_size_m, MansionTuningScript.MAX_ROOM_SIZE_M),
		"5 項目すべての上限超過が最大値へクランプされる",
	)


## MansionTuning.equals・from_dict 異常系・コマンドライン引数解析の各単独分岐を検証する
func _check_tuning_equals_and_cmdline_args() -> void:
	var base: MansionTuning = MansionTuningScript.new()
	_check(base.equals(MansionTuningScript.new()), "同じ値の MansionTuning で equals が true")
	_check(not base.equals(null), "null との equals が false")

	for prop_diff: Array in [
		["hair_count", base.hair_count + 1],
		["found_item_count", base.found_item_count + 1],
		["room_size_m", base.room_size_m + 1.0],
		["object_count", base.object_count + 1],
		["room_count", base.room_count + 1],
	]:
		var diff_tuning: MansionTuning = base.clamped()
		diff_tuning.set(prop_diff[0], prop_diff[1])
		_check(not base.equals(diff_tuning), "項目 %s の差異で equals が false" % prop_diff[0])

	# MansionTuning.from_dict の各キー単独欠損と非数値型違い
	var base_dict: Dictionary = base.to_dict()
	for field_key: String in [
		"hair_count",
		"found_item_count",
		"room_size_m",
		"object_count",
		"room_count",
	]:
		var missing_field: Dictionary = base_dict.duplicate(true)
		missing_field.erase(field_key)
		_check(
			MansionTuningScript.from_dict(missing_field) == null,
			"MansionTuning.from_dict で %s 欠損時は null" % field_key,
		)
		var wrong_type: Dictionary = base_dict.duplicate(true)
		wrong_type[field_key] = "invalid"
		_check(
			MansionTuningScript.from_dict(wrong_type) == null,
			"MansionTuning.from_dict で %s 非数値時は null" % field_key,
		)

	for single_arg: String in [
		"--hair-count=100",
		"--found-item-count=1",
		"--room-size=5.0",
		"--object-count=2",
		"--room-count=2",
	]:
		_check(
			MansionTuningScript.has_cmdline_override(PackedStringArray([single_arg])),
			"単独引数 %s で has_cmdline_override が true" % single_arg,
		)

	var parsed: MansionTuning = MansionTuningScript.from_cmdline_args(PackedStringArray([
		"--hair-count=321", "--found-item-count=2", "--room-size=8.5",
		"--object-count=7", "--room-count=3",
	]))
	_check(
		parsed.hair_count == 321 and parsed.found_item_count == 2
		and is_equal_approx(parsed.room_size_m, 8.5)
		and parsed.object_count == 7 and parsed.room_count == 3,
		"コマンドライン引数 5 項目すべてが反映される",
	)
	var fallback: MansionTuning = MansionTuningScript.from_cmdline_args(PackedStringArray([
		"--hair-count=bad", "--found-item-count=bad", "--room-size=bad",
		"--object-count=bad", "--room-count=bad", "--room-count=", "--unrelated=1",
	]))
	_check(
		fallback.equals(MansionTuningScript.new())
		and not MansionTuningScript.has_cmdline_override(PackedStringArray(["--other=1"])),
		"全 5 項目への不正・空・無関係な引数では既定値が保たれる",
	)


## 開発者向け調整パネルが矢印刻みに合わない値 (321 本・5.3m) を丸めずに保持することを検証する
func _check_dev_tuning_panel_preserves_unaligned_values() -> void:
	var panel: DevTuningPanel = DevTuningPanelScript.new()
	var custom_tuning: MansionTuning = MansionTuningScript.new()
	custom_tuning.hair_count = 321
	custom_tuning.room_size_m = 5.375
	custom_tuning.found_item_count = 7
	custom_tuning.object_count = 11
	custom_tuning.room_count = 3
	panel.load_from_tuning(custom_tuning)
	var roundtripped: MansionTuning = panel.build_tuning_from_inputs()
	panel.room_size_spin.value = 5.38
	var edited: MansionTuning = panel.build_tuning_from_inputs()
	_check(
		roundtripped.hair_count == 321
		and is_equal_approx(roundtripped.room_size_m, 5.375)
		and is_equal_approx(edited.room_size_m, 5.38),
		"DevTuningPanel が 5.375m の非丸め保持と 5.38m への明示編集の両方を正しく反映する",
	)
	panel.free()


## MansionWorld の毛の本数の境界と室内ライト数上限の境界を検証する
func _check_world_hair_and_light_limits() -> void:
	var world: MansionWorld = MansionWorldScript.new()
	_rebuild_world_case(world, 1, 0, 100)
	_check(world.get_hair_field().get_remaining_count() == 100, "1 面 100 本の屋敷で毛が 100 本置かれる")
	_rebuild_world_case(world, 1, 0, 0)
	_check(world.get_hair_field().get_remaining_count() == 0, "毛 0 本の屋敷では毛が 0 本")
	_rebuild_world_case(world, MansionWorldScript.MAX_ROOM_LIGHTS, 0, 100)
	_check(
		world.get_room_light_count() == MansionWorldScript.MAX_ROOM_LIGHTS,
		"上限ちょうど部屋数でライト数が上限値と一致する",
	)
	var seven_layout: MansionLayout = _rebuild_world_case(
		world,
		MansionWorldScript.MAX_ROOM_LIGHTS + 1,
		0,
		100,
	)
	_check(
		world.get_room_light_count() == MansionWorldScript.MAX_ROOM_LIGHTS,
		"上限 + 1 部屋でもライト数が MAX_ROOM_LIGHTS に抑えられる",
	)
	world.rebuild(seven_layout, null)
	_check(world.get_hair_field().get_remaining_count() == 0, "progress=null で毛が 0 本")
	world.free()



## 指定パラメータで MansionWorld を再構築してレイアウトを返す (上限境界テスト用ヘルパー)
func _rebuild_world_case(
	world: MansionWorld,
	rooms: int,
	objects: int,
	hairs: int,
) -> MansionLayout:
	var t: MansionTuning = MansionTuningScript.new()
	t.room_count = rooms
	t.object_count = objects
	t.hair_count = hairs
	var l: MansionLayout = MansionBuilderScript.build_layout(t)
	world.rebuild(l, MansionBuilderScript.build_initial_progress(l, t))
	return l


## FirstPersonPlayer のマウス捕捉・視点適用・Esc 解放の各純粋判定を検証する
func _check_player_mouse_predicates() -> void:
	var left_press: InputEventMouseButton = InputEventMouseButton.new()
	left_press.button_index = MOUSE_BUTTON_LEFT
	left_press.pressed = true
	var left_release: InputEventMouseButton = InputEventMouseButton.new()
	left_release.button_index = MOUSE_BUTTON_LEFT
	left_release.pressed = false
	var right_press: InputEventMouseButton = InputEventMouseButton.new()
	right_press.button_index = MOUSE_BUTTON_RIGHT
	right_press.pressed = true
	_check(
		FirstPersonPlayerScript.should_capture_mouse(left_press)
		and not FirstPersonPlayerScript.should_capture_mouse(left_release)
		and not FirstPersonPlayerScript.should_capture_mouse(right_press),
		"should_capture_mouse が左ボタン押下だけを true にする",
	)
	_check(
		FirstPersonPlayerScript.should_apply_mouse_motion(Input.MOUSE_MODE_CAPTURED, false)
		and FirstPersonPlayerScript.should_apply_mouse_motion(Input.MOUSE_MODE_VISIBLE, true)
		and not FirstPersonPlayerScript.should_apply_mouse_motion(Input.MOUSE_MODE_VISIBLE, false),
		"should_apply_mouse_motion が捕捉中または許可フラグ時のみ true になる",
	)
	var esc_event: InputEventKey = InputEventKey.new()
	esc_event.physical_keycode = KEY_ESCAPE
	esc_event.pressed = true
	var other_event: InputEventKey = InputEventKey.new()
	other_event.physical_keycode = KEY_W
	other_event.pressed = true
	_check(
		FirstPersonPlayerScript.should_release_mouse(esc_event)
		and not FirstPersonPlayerScript.should_release_mouse(other_event),
		"should_release_mouse が Esc キー押下だけを true にする",
	)


## セーブして読み戻すと、面ごと・色ごとの毛の本数とお金・全進捗フィールドの中身が一致するか検証する
func _check_save_and_load_roundtrip() -> void:
	SaveStorageScript.delete_save_file(TEST_SAVE_PATH)
	var save_fixture: SaveData = _create_rich_save_fixture()
	_check(
		SaveStorageScript.save_to_path(save_fixture, TEST_SAVE_PATH) == OK,
		"セーブファイルの保存が成功する",
	)
	var loaded: SaveData = SaveStorageScript.load_from_path(TEST_SAVE_PATH)
	_check(loaded != null, "保存したセーブデータを読み戻せる")
	if loaded == null:
		return

	var loaded_progress: BuildingProgress = loaded.building_progress
	_check(
		loaded_progress.money == 4321
		and is_equal_approx(loaded_progress.elapsed_seconds, 123.5)
		and loaded.tuning.equals(save_fixture.tuning),
		"所持金 (4321)・経過時間・調整値が一致する",
	)
	_check(
		loaded_progress.surface_hairs.size() == save_fixture.building_progress.surface_hairs.size(),
		"復元後の表面配列件数が一致する",
	)
	if not loaded_progress.surface_hairs.is_empty():
		var first_surface: SurfaceHair = loaded_progress.surface_hairs[0]
		_check(
			first_surface.surface_id == save_fixture.building_progress.surface_hairs[0].surface_id
			and first_surface.count_for_color(SurfaceHairScript.COLOR_WHITE) == 42
			and first_surface.count_for_color(SurfaceHairScript.COLOR_BLACK) == 17
			and first_surface.count_for_color(SurfaceHairScript.COLOR_CALICO) == 9,
			"先頭の面 id と 3 色の毛本数がすべて一致する",
		)
	_check(
		loaded_progress.hair_stocks.size() == 1
		and loaded_progress.hair_stocks[0].hair_color == SurfaceHairScript.COLOR_WHITE
		and loaded_progress.hair_stocks[0].rare_hair_id == &"golden_hair"
		and loaded_progress.hair_stocks[0].form == HairStockScript.FORM_FELT
		and loaded_progress.hair_stocks[0].count == 3,
		"毛・加工品在庫の全項目が一致する",
	)
	_check(
		loaded.hand_upgrade_levels.get(&"dexterity", 0) == 3
		and loaded.hand_upgrade_levels.get(&"pinch_count", 0) == 2
		and loaded.found_rare_hair_ids == [&"whisker", &"golden_hair"],
		"持ち越す手の強化レベル 2 種と図鑑の珍しい毛 id 要素が一致する",
	)
	_check(
		loaded.building_records.size() == 1
		and loaded.building_records[0].building_id == &"mansion"
		and is_equal_approx(loaded.building_records[0].clear_seconds, 3600.0)
		and loaded.building_records[0].returned_found_item_count == 5,
		"終えた建物の成績の全フィールドが一致する",
	)
	_check(
		loaded_progress.owned_tools.size() == 1
		and loaded_progress.owned_tools[0].tool_id == &"cleaning_robot"
		and loaded_progress.owned_tools[0].level == 2
		and loaded_progress.owned_tools[0].consumable_count == 4
		and loaded_progress.owned_tools[0].robot_room_ids == [&"hall", &"living"],
		"買った道具とロボット巡回順の全要素が一致する",
	)
	_check(
		is_equal_approx(loaded_progress.resident_moods.get(&"resident_hall", -1.0), 0.75)
		and loaded_progress.found_items.size() == save_fixture.building_progress.found_items.size()
		and loaded_progress.found_items[0].condition == FoundItemProgressScript.Condition.CLEAN
		and loaded_progress.found_items[0].is_returned,
		"住人の機嫌と探し物の件数・状態・返却フラグが一致する",
	)


## 保存データ不在・破損・全 from_dict 異常系・負値や機嫌範囲外のクランプを検証する
func _check_save_missing_corrupted_and_clamping() -> void:
	SaveStorageScript.delete_save_file(TEST_SAVE_PATH)
	_check(SaveStorageScript.load_from_path(TEST_SAVE_PATH) == null, "保存データ不在時は null")
	var missing_save_state: Node = GameStateScript.new()
	missing_save_state.initialize_from_storage(TEST_SAVE_PATH)
	_check(
		not missing_save_state.loaded_from_save
		and missing_save_state.get_total_remaining_hairs()
		== MansionTuningScript.DEFAULT_HAIR_COUNT,
		"保存データが無い時に既定値で新しく始められる",
	)
	missing_save_state.free()

	for bad_payload: String in ["{broken json", "", "[1,2]", "null", "123"]:
		var file: FileAccess = FileAccess.open(TEST_SAVE_PATH, FileAccess.WRITE)
		_check(file != null, "破損テスト用ファイル (%s) を開ける" % bad_payload)
		if file == null:
			continue
		var wrote_bad: bool = file.store_string(bad_payload)
		file.close()
		_check(wrote_bad, "破損テスト用ペイロード (%s) を書き込める" % bad_payload)
		var corrupted_save_state: Node = GameStateScript.new()
		corrupted_save_state.initialize_from_storage(TEST_SAVE_PATH)
		_check(
			SaveStorageScript.load_from_path(TEST_SAVE_PATH) == null
			and not corrupted_save_state.loaded_from_save
			and corrupted_save_state.current_layout != null,
			"壊れたファイル (%s) で null を返し新しく始められる" % bad_payload,
		)
		corrupted_save_state.free()

	var valid_dict: Dictionary = _create_rich_save_fixture().to_dict()

	# 有効辞書で schema_version を 0 / 1.5 / 2 / 文字列 / 欠損に変更 (未対応・不正スキーマ判定を通す)
	for bad_version: Variant in [0, 1.5, 2, "1"]:
		var bad_ver_dict: Dictionary = valid_dict.duplicate(true)
		bad_ver_dict["schema_version"] = bad_version
		_check(SaveDataScript.from_dict(bad_ver_dict) == null, "不正 schema_version で null")
	var missing_ver_dict: Dictionary = valid_dict.duplicate(true)
	missing_ver_dict.erase("schema_version")
	_check(SaveDataScript.from_dict(missing_ver_dict) == null, "schema_version 欠損で null")

	# 1 フィールドずつ壊した異常系群
	var mutated: Dictionary = valid_dict.duplicate(true)
	mutated.erase("tuning")
	_check(SaveDataScript.from_dict(mutated) == null, "部分破損 (tuning欠損) で null を返す")
	for top_bad: Array in [
		["tuning", "x", "tuning型違い"],
		["found_rare_hair_ids", [1], "rare要素非文字"],
		["hand_upgrade_levels", {"a": "x"}, "upgrade非数値"],
		["hand_upgrade_levels", "not_dict", "hand_upgrade_levels非辞書"],
		["building_records", "not_array", "building_records非配列"],
	]:
		mutated = valid_dict.duplicate(true)
		mutated[top_bad[0]] = top_bad[1]
		_check(SaveDataScript.from_dict(mutated) == null, "部分破損 (%s) で null を返す" % top_bad[2])
	for bp_bad: Array in [
		["money", "x", "money型違い"],
		["elapsed_seconds", "x", "elapsed型違い"],
		["resident_moods", "not_dict", "resident_moods非辞書"],
		["surface_hairs", "not_array", "surface_hairs非配列"],
		["hair_stocks", "not_array", "hair_stocks非配列"],
		["owned_tools", "not_array", "owned_tools非配列"],
		["found_items", "not_array", "found_items非配列"],
	]:
		mutated = valid_dict.duplicate(true)
		mutated["building_progress"][bp_bad[0]] = bp_bad[1]
		_check(SaveDataScript.from_dict(mutated) == null, "部分破損 (%s) で null を返す" % bp_bad[2])
	mutated = valid_dict.duplicate(true)
	mutated["building_records"][0]["clear_seconds"] = "x"
	_check(SaveDataScript.from_dict(mutated) == null, "部分破損 (record秒非数値) で null を返す")
	mutated = valid_dict.duplicate(true)
	mutated["building_progress"]["surface_hairs"][0]["hair_counts"]["white"] = "x"
	_check(SaveDataScript.from_dict(mutated) == null, "部分破損 (hair_counts非数値) で null を返す")
	mutated = valid_dict.duplicate(true)
	mutated["building_progress"]["resident_moods"]["resident_hall"] = "x"
	_check(SaveDataScript.from_dict(mutated) == null, "部分破損 (mood非数値) で null を返す")
	mutated = valid_dict.duplicate(true)
	mutated["building_progress"]["owned_tools"][0]["robot_room_ids"] = [9]
	_check(SaveDataScript.from_dict(mutated) == null, "部分破損 (robot_room非文字) で null を返す")
	mutated = valid_dict.duplicate(true)
	mutated["building_progress"]["found_items"][0]["is_returned"] = "yes"
	_check(SaveDataScript.from_dict(mutated) == null, "部分破損 (is_returned非bool) で null を返す")
	for bad_condition: int in [-1, 4]:
		mutated = valid_dict.duplicate(true)
		mutated["building_progress"]["found_items"][0]["condition"] = bad_condition
		_check(
			SaveDataScript.from_dict(mutated) == null,
			"部分破損 (condition=%d) で null を返す" % bad_condition,
		)
	for bad_stock_field: String in ["hair_color", "rare_hair_id", "form", "count"]:
		mutated = valid_dict.duplicate(true)
		mutated["building_progress"]["hair_stocks"][0][bad_stock_field] = (
			"x" if bad_stock_field == "count" else 1
		)
		_check(
			SaveDataScript.from_dict(mutated) == null,
			"部分破損 (HairStock.%s 型違い) で null を返す" % bad_stock_field,
		)

	# 各データ型の非文字列 ID・非配列・非辞書・非数値フィールドの拒否分岐を網羅する
	_check(BuildingProgressScript.from_dict({"building_id": 1}) == null, "building_id 非文字を拒否")
	for bad_surface: Dictionary in [
		{"surface_id": 1, "hair_counts": {}},
		{"surface_id": "a", "hair_counts": []},
	]:
		_check(SurfaceHairScript.from_dict(bad_surface) == null, "SurfaceHair 不正辞書を拒否")
	for bad_tool: Dictionary in [
		{"tool_id": 1, "level": 1, "consumable_count": 0, "robot_room_ids": []},
		{"tool_id": "a", "level": "x", "consumable_count": 0, "robot_room_ids": []},
		{"tool_id": "a", "level": 1, "consumable_count": "x", "robot_room_ids": []},
		{"tool_id": "a", "level": 1, "consumable_count": 0, "robot_room_ids": "not_array"},
	]:
		_check(OwnedToolScript.from_dict(bad_tool) == null, "OwnedTool 不正辞書を拒否")
	for bad_found: Dictionary in [
		{"found_item_id": 1, "condition": 0, "is_returned": false},
		{"found_item_id": "a", "condition": "x", "is_returned": false},
	]:
		_check(FoundItemProgressScript.from_dict(bad_found) == null, "FoundItem 不正辞書を拒否")
	for bad_record: Dictionary in [
		{"building_id": 1, "clear_seconds": 1.0, "returned_found_item_count": 0},
		{"building_id": "a", "clear_seconds": 1.0, "returned_found_item_count": "x"},
	]:
		_check(BuildingRecordScript.from_dict(bad_record) == null, "BuildingRecord 不正辞書を拒否")

	# 負値と機嫌範囲外の丸め境界
	var clamp_dict: Dictionary = valid_dict.duplicate(true)
	clamp_dict["building_progress"]["money"] = -50
	clamp_dict["building_progress"]["elapsed_seconds"] = -10.0
	clamp_dict["building_progress"]["surface_hairs"][0]["hair_counts"]["white"] = -5
	clamp_dict["building_progress"]["hair_stocks"][0]["count"] = -3
	clamp_dict["building_progress"]["owned_tools"][0]["level"] = 0
	clamp_dict["building_progress"]["resident_moods"]["resident_hall"] = 1.8
	clamp_dict["building_progress"]["resident_moods"]["resident_living"] = -0.4
	clamp_dict["building_records"][0]["returned_found_item_count"] = -2
	var clamped_save: SaveData = SaveDataScript.from_dict(clamp_dict)
	_check(
		clamped_save != null
		and clamped_save.building_progress.money == 0
		and is_equal_approx(clamped_save.building_progress.elapsed_seconds, 0.0)
		and clamped_save.building_progress.surface_hairs[0].count_for_color(
			SurfaceHairScript.COLOR_WHITE
		)
		== 0
		and clamped_save.building_progress.hair_stocks[0].count == 0
		and clamped_save.building_progress.owned_tools[0].level == 1
		and is_equal_approx(clamped_save.building_progress.resident_moods[&"resident_hall"], 1.0)
		and is_equal_approx(clamped_save.building_progress.resident_moods[&"resident_living"], 0.0)
		and clamped_save.building_records[0].returned_found_item_count == 0,
		"負値・レベル 0・機嫌範囲外が安全範囲に丸められる",
	)


## GameState の引数上書き・全 3 種 ID 照合 (_reconcile_progress_with_layout)・終了通知条件を検証する
func _check_game_state_override_reconcile_and_notifications() -> void:
	SaveStorageScript.delete_save_file(TEST_SAVE_PATH)

	# 1. save_data が null の時の終了通知と、別通知で保存されないこと
	var empty_state: Node = GameStateScript.new()
	empty_state.save_path = TEST_SAVE_PATH
	empty_state.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	_check(
		not SaveStorageScript.has_save_file(TEST_SAVE_PATH),
		"save_data が null なら終了通知で保存ファイルを作らない",
	)
	empty_state.initialize_from_storage(TEST_SAVE_PATH)
	empty_state.notification(Node.NOTIFICATION_PARENTED)
	_check(
		not SaveStorageScript.has_save_file(TEST_SAVE_PATH),
		"終了要求以外の通知では保存ファイルを作らない",
	)
	empty_state.free()

	# 2. 保存データなし + 引数上書きあり
	var state_no_save: Node = GameStateScript.new()
	state_no_save.initialize_from_storage(
		TEST_SAVE_PATH,
		PackedStringArray(["--hair-count=777", "--room-count=2"]),
	)
	_check(
		not state_no_save.loaded_from_save
		and state_no_save.launched_with_cmdline_override
		and state_no_save.get_total_remaining_hairs() == 777
		and state_no_save.get_tuning().room_count == 2,
		"保存データなし + 引数上書きで指定値の屋敷を組み立てる",
	)
	state_no_save.free()

	# 3. 保存データあり + 引数上書きあり: 既存セーブの調整値を土台に上書きし、終了通知で既存セーブを壊さない
	var saved_fixture: SaveData = _create_rich_save_fixture()
	saved_fixture.tuning.room_size_m = 9.0
	saved_fixture.building_progress.money = 5555
	SaveStorageScript.save_to_path(saved_fixture, TEST_SAVE_PATH)

	var state_override: Node = GameStateScript.new()
	state_override.initialize_from_storage(
		TEST_SAVE_PATH,
		PackedStringArray(["--room-count=1", "--hair-count=300"]),
	)
	state_override.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	var after_override_close: SaveData = SaveStorageScript.load_from_path(TEST_SAVE_PATH)
	_check(
		not state_override.loaded_from_save
		and state_override.get_tuning().room_count == 1
		and is_equal_approx(state_override.get_tuning().room_size_m, 9.0)
		and state_override.get_total_remaining_hairs() == 300
		and after_override_close != null
		and after_override_close.building_progress.money == 5555,
		"引数上書き起動は保存調整値を土台に作り直し終了通知で既存セーブを上書きしない",
	)
	# persist=false は上書きフラグを維持し終了通知でも保存せず、persist=true で解除・保存有効化する
	state_override.apply_tuning_and_rebuild(null, false)
	state_override.save_data.building_progress.money = 6666
	state_override.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	_check(
		state_override.launched_with_cmdline_override
		and SaveStorageScript.load_from_path(TEST_SAVE_PATH).building_progress.money == 5555,
		"引数上書き後の persist=false 再構築は自動保存抑止を維持する",
	)
	var persist_tuning: MansionTuning = MansionTuningScript.new()
	persist_tuning.room_count = 3
	persist_tuning.hair_count = 456
	state_override.apply_tuning_and_rebuild(persist_tuning, true)
	var after_persist_rebuild: SaveData = SaveStorageScript.load_from_path(TEST_SAVE_PATH)
	_check(
		after_persist_rebuild != null and after_persist_rebuild.tuning.hair_count == 456,
		"persist=true 再構築が終了通知より前に新しい調整値を保存ファイルへ書き出す",
	)
	state_override.save_data.building_progress.money = 7777
	state_override.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	_check(
		not state_override.launched_with_cmdline_override
		and SaveStorageScript.load_from_path(TEST_SAVE_PATH).building_progress.money == 7777,
		"引数上書き後の persist=true 再構築で自動保存が再び有効になる",
	)
	state_override.initialize_from_storage(TEST_SAVE_PATH, PackedStringArray(["--room-count=1"]))
	state_override.start_new_game()
	state_override.save_data.building_progress.money = 8888
	state_override.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	_check(
		not state_override.launched_with_cmdline_override
		and SaveStorageScript.load_from_path(TEST_SAVE_PATH).building_progress.money == 8888,
		"引数上書き後の start_new_game で自動保存が再び有効になる",
	)
	state_override.free()

	# 4. _reconcile_progress_with_layout: 一致保持
	var consistent_save: SaveData = _create_rich_save_fixture()
	consistent_save.building_progress.money = 777
	SaveStorageScript.save_to_path(consistent_save, TEST_SAVE_PATH)
	var state_consistent: Node = GameStateScript.new()
	state_consistent.initialize_from_storage(TEST_SAVE_PATH)
	_check(
		state_consistent.loaded_from_save and state_consistent.get_money() == 777,
		"面・探し物・住人が一致する保存データは loaded_from_save=true で所持金 777 を保持する",
	)
	state_consistent.free()

	# 5. _reconcile_progress_with_layout: 面の件数過多 / 面 ID 不一致 / 探し物不一致 / 住人不一致
	var extra_surface_save: SaveData = _create_rich_save_fixture()
	var dup_surface: SurfaceHair = SurfaceHairScript.new()
	dup_surface.surface_id = extra_surface_save.building_progress.surface_hairs[0].surface_id
	extra_surface_save.building_progress.surface_hairs.append(dup_surface)
	_assert_reconcile_resets("面 ID 重複あり", extra_surface_save)
	var wrong_surface_id_save: SaveData = _create_rich_save_fixture()
	wrong_surface_id_save.building_progress.surface_hairs[0].surface_id = &"unknown_surface"
	_assert_reconcile_resets("面 ID 不一致", wrong_surface_id_save)
	var extra_item_save: SaveData = _create_rich_save_fixture()
	var dup_item: FoundItemProgress = FoundItemProgressScript.new()
	dup_item.found_item_id = extra_item_save.building_progress.found_items[0].found_item_id
	extra_item_save.building_progress.found_items.append(dup_item)
	_assert_reconcile_resets("探し物 ID 重複あり", extra_item_save)
	var wrong_item_id_save: SaveData = _create_rich_save_fixture()
	wrong_item_id_save.building_progress.found_items[0].found_item_id = &"unknown_item"
	_assert_reconcile_resets("探し物 ID 不一致", wrong_item_id_save)
	var extra_resident_save: SaveData = _create_rich_save_fixture()
	extra_resident_save.building_progress.resident_moods[&"resident_extra"] = 0.5
	_assert_reconcile_resets("住人件数過多", extra_resident_save)
	var wrong_resident_save: SaveData = _create_rich_save_fixture()
	wrong_resident_save.building_progress.resident_moods.erase(&"resident_hall")
	wrong_resident_save.building_progress.resident_moods[&"resident_unknown"] = 0.5
	_assert_reconcile_resets("住人キー不一致", wrong_resident_save)


## 不整合な保存データを読み込んだ時に進行が作り直され loaded_from_save=false になることを検証する
func _assert_reconcile_resets(case_label: String, broken_save: SaveData) -> void:
	broken_save.building_progress.money = 888
	_check(
		SaveStorageScript.save_to_path(broken_save, TEST_SAVE_PATH) == OK,
		"不整合フィクスチャ (%s) の保存が成功する" % case_label,
	)
	var state_reconciled: Node = GameStateScript.new()
	state_reconciled.initialize_from_storage(TEST_SAVE_PATH)
	_check(
		not state_reconciled.loaded_from_save and state_reconciled.get_money() == 0,
		"レイアウト不整合 (%s) で進行を作り直し loaded_from_save=false にする" % case_label,
	)
	state_reconciled.free()


## GameState / SaveStorage / MansionBuilder の null・エラー・未保存分岐を検証する
func _check_game_state_and_builder_edge_cases() -> void:
	SaveStorageScript.delete_save_file(TEST_SAVE_PATH)
	_check(
		SaveStorageScript.save_to_path(null, TEST_SAVE_PATH) == ERR_INVALID_PARAMETER,
		"SaveStorage.save_to_path(null) が ERR_INVALID_PARAMETER を返す",
	)
	_check(
		SaveStorageScript.save_to_path(
			_create_rich_save_fixture(),
			"user://nonexistent_dir_xyz/save.json",
		)
		!= OK,
		"存在しないディレクトリへの保存がエラーを返す",
	)

	var null_layout: MansionLayout = MansionBuilderScript.build_layout(null)
	var null_progress: BuildingProgress = MansionBuilderScript.build_initial_progress(
		null_layout,
		null,
	)
	_check(
		null_layout.rooms.size() == MansionTuningScript.DEFAULT_ROOM_COUNT
		and null_progress.total_remaining_hairs() == MansionTuningScript.DEFAULT_HAIR_COUNT,
		"build_layout(null) / build_initial_progress(..., null) が既定値で組み立てる",
	)

	var state: Node = GameStateScript.new()
	state.save_path = TEST_SAVE_PATH
	# save_data == null の場合の全アクセサと保存エラー
	_check(state.save_current_state() == ERR_UNCONFIGURED, "save_data=null の保存が ERR_UNCONFIGURED")
	_check(
		state.get_tuning().equals(MansionTuningScript.new())
		and state.get_total_remaining_hairs() == 0
		and state.get_money() == 0
		and state.get_surface_hair_count(&"hall_floor") == 0,
		"save_data=null の各アクセサが安全に既定値 / 0 を返す",
	)

	# save_data はあるが tuning / building_progress が null の片側分岐
	state.save_data = SaveDataScript.new()
	_check(
		state.get_tuning().equals(MansionTuningScript.new())
		and state.get_total_remaining_hairs() == 0
		and state.get_money() == 0
		and state.get_surface_hair_count(&"hall_floor") == 0,
		"tuning=null / building_progress=null の各アクセサが安全に既定値 / 0 を返す",
	)

	# apply_tuning_and_rebuild(null, false) は保存せず既定値で再構築する
	state.save_data = null
	state.apply_tuning_and_rebuild(null, false)
	_check(
		not SaveStorageScript.has_save_file(TEST_SAVE_PATH)
		and state.get_total_remaining_hairs() == MansionTuningScript.DEFAULT_HAIR_COUNT
		and state.get_surface_hair_count(&"hall_floor") > 0
		and state.get_surface_hair_count(&"missing_surface") == 0,
		"apply_tuning_and_rebuild(null, false) と get_surface_hair_count が正しく動く",
	)

	# start_new_game(custom_tuning) が指定値で新規作成・保存する
	var custom_start: MansionTuning = MansionTuningScript.new()
	custom_start.room_count = 1
	custom_start.hair_count = 99
	state.start_new_game(custom_start)
	_check(
		SaveStorageScript.has_save_file(TEST_SAVE_PATH)
		and state.get_tuning().room_count == 1
		and state.get_total_remaining_hairs() == 99,
		"start_new_game(custom_tuning) が指定値で新規開始して保存する",
	)
	state.free()


## 毛の本数の 3 桁区切り整形を検証する
func _check_format_hair_count() -> void:
	_check(MainScript.format_hair_count(0) == "0", "0 の整形が '0'")
	_check(MainScript.format_hair_count(999) == "999", "999 の整形が '999'")
	_check(MainScript.format_hair_count(1000) == "1,000", "1000 の整形が '1,000'")
	_check(MainScript.format_hair_count(1234567) == "1,234,567", "1234567 の整形が '1,234,567'")
	_check(MainScript.format_hair_count(-5) == "0", "負の値の整形が '0'")


## 全フィールドに検証用の値を入れた SaveData のテストフィクスチャを生成する
func _create_rich_save_fixture() -> SaveData:
	# 全フィールドのフィクスチャ構築
	var tuning: MansionTuning = MansionTuningScript.new()
	tuning.room_count = 2
	tuning.object_count = 4
	tuning.hair_count = 250
	tuning.found_item_count = 2
	tuning.room_size_m = 7.0
	# 成績が 1 つ (屋敷を終えた) あるため、今いるのは 2 つ目の建物 (調整値から求めた作り)
	var hotel_tuning: MansionTuning = BuildingRulesScript.building_tuning(tuning, 1)
	var layout: MansionLayout = MansionBuilderScript.build_layout(hotel_tuning)
	var progress: BuildingProgress = MansionBuilderScript.build_initial_progress(layout, hotel_tuning)
	progress.building_id = BuildingRulesScript.BUILDING_HOTEL
	progress.money = 4321
	progress.elapsed_seconds = 123.5
	progress.surface_hairs[0].hair_counts[SurfaceHairScript.COLOR_WHITE] = 42
	progress.surface_hairs[0].hair_counts[SurfaceHairScript.COLOR_BLACK] = 17
	progress.surface_hairs[0].hair_counts[SurfaceHairScript.COLOR_CALICO] = 9
	progress.resident_moods[&"resident_hall"] = 0.75
	var stock: HairStock = HairStockScript.new()
	stock.hair_color = SurfaceHairScript.COLOR_WHITE
	stock.rare_hair_id = &"golden_hair"
	stock.form = HairStockScript.FORM_FELT
	stock.count = 3
	progress.hair_stocks.append(stock)
	var tool: OwnedTool = OwnedToolScript.new()
	tool.tool_id = &"cleaning_robot"
	tool.level = 2
	tool.consumable_count = 4
	tool.robot_room_ids = [&"hall", &"living"]
	progress.owned_tools.append(tool)
	progress.found_items[0].condition = FoundItemProgressScript.Condition.CLEAN
	progress.found_items[0].is_returned = true
	var record: BuildingRecord = BuildingRecordScript.new()
	record.building_id = &"mansion"
	record.clear_seconds = 3600.0
	record.returned_found_item_count = 5
	var save: SaveData = SaveDataScript.new()
	save.hand_upgrade_levels = {&"dexterity": 3, &"pinch_count": 2}
	save.found_rare_hair_ids = [&"whisker", &"golden_hair"]
	save.building_records = [record]
	save.building_progress = progress
	save.tuning = tuning
	return save

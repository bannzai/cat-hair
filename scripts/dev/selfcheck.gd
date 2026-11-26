extends "res://scripts/dev/headless_check.gd"
## 純粋なロジックとプロジェクト設定の検証 (headless)。ゲームのルールの計算を足したら、ここに検証を足す。
## 実行方法は AGENTS.md「検証方法」を参照。

const MainScript := preload("res://scripts/main.gd")
const MansionTuningScript := preload("res://scripts/data/mansion_tuning.gd")
const MansionLayoutScript := preload("res://scripts/mansion/mansion_layout.gd")
const MansionBuilderScript := preload("res://scripts/mansion/mansion_builder.gd")
const MansionWorldScript := preload("res://scripts/mansion/mansion_world.gd")
const SaveDataScript := preload("res://scripts/data/save_data.gd")
const BuildingRecordScript := preload("res://scripts/data/building_record.gd")
const HairStockScript := preload("res://scripts/data/hair_stock.gd")
const OwnedToolScript := preload("res://scripts/data/owned_tool.gd")
const FoundItemProgressScript := preload("res://scripts/data/found_item_progress.gd")
const SurfaceHairScript := preload("res://scripts/data/surface_hair.gd")
const SaveStorageScript := preload("res://scripts/state/save_storage.gd")
const GameStateScript := preload("res://scripts/state/game_state.gd")

## プロジェクト設定のメインシーンに入っているべきパス
const MAIN_SCENE_PATH: String = "res://scenes/main.tscn"
## プロジェクト設定の名前に入っているべき値 (ゲームの題名)
const PROJECT_NAME: String = "Oh My Fur!"
## selfcheck が使う一時セーブファイルパス
const TEST_SAVE_PATH: String = "user://selfcheck_save_data.json"


## 検証をすべて実行して終える
func _initialize() -> void:
	_check_project_settings()
	_check_main_scene_loads()
	_check_mansion_builder_default()
	_check_mansion_builder_changes_with_tuning()
	_check_mansion_builder_boundaries()
	_check_tuning_equals_and_cmdline_args()
	_check_visual_hair_limits()
	_check_save_and_load_roundtrip()
	_check_save_missing_and_corrupted()
	_check_game_state_cmdline_override_and_reconcile()
	_check_format_hair_count()
	SaveStorageScript.delete_save_file(TEST_SAVE_PATH)
	_finish()


## プロジェクト設定の名前・メインシーン・autoload・入力アクションが想定どおりか
func _check_project_settings() -> void:
	var main_scene: String = ProjectSettings.get_setting("application/run/main_scene", "")
	_check(
		main_scene == MAIN_SCENE_PATH,
		"application/run/main_scene が %s (実際: %s)" % [MAIN_SCENE_PATH, main_scene],
	)
	var project_name: String = ProjectSettings.get_setting("application/config/name", "")
	_check(
		project_name == PROJECT_NAME,
		"application/config/name が %s (実際: %s)" % [PROJECT_NAME, project_name],
	)
	var autoload_path: String = ProjectSettings.get_setting("autoload/GameState", "")
	_check(
		autoload_path.ends_with("res://scripts/state/game_state.gd"),
		"autoload/GameState が game_state.gd を指す (実際: %s)" % autoload_path,
	)
	for action_name: String in [
		"move_forward",
		"move_back",
		"move_left",
		"move_right",
		"toggle_dev_panel",
		"save_game",
	]:
		_check(
			InputMap.has_action(action_name),
			"入力アクション %s が定義されている" % action_name,
		)


## メインシーンがロードでき、PackedScene が返るか
func _check_main_scene_loads() -> void:
	_check(
		load(MAIN_SCENE_PATH) is PackedScene,
		"%s が PackedScene としてロードできる" % MAIN_SCENE_PATH,
	)


## 既定の調整値で屋敷を組み立てた時、すべての要素数が調整値と一致し表面種別が揃うか
func _check_mansion_builder_default() -> void:
	var tuning: MansionTuning = MansionTuningScript.new()
	var layout: MansionLayout = MansionBuilderScript.build_layout(tuning)
	var progress: BuildingProgress = MansionBuilderScript.build_initial_progress(layout, tuning)

	_check(
		layout.rooms.size() == tuning.room_count,
		"部屋数が調整値と一致する (%d == %d)" % [layout.rooms.size(), tuning.room_count],
	)
	_check(
		layout.objects.size() == tuning.object_count,
		"物の数が調整値と一致する (%d == %d)" % [layout.objects.size(), tuning.object_count],
	)
	_check(
		layout.found_item_spots.size() == tuning.found_item_count,
		"探し物の置き場所数が調整値と一致する (%d == %d)"
		% [layout.found_item_spots.size(), tuning.found_item_count],
	)
	_check(
		progress.found_items.size() == tuning.found_item_count,
		"初期進捗の探し物数が調整値と一致する (%d == %d)"
		% [progress.found_items.size(), tuning.found_item_count],
	)
	_check(
		progress.total_remaining_hairs() == tuning.hair_count,
		"毛の総本数が調整値と一致する (%d == %d)"
		% [progress.total_remaining_hairs(), tuning.hair_count],
	)
	var expected_surfaces: int = tuning.room_count + tuning.object_count
	_check(
		layout.surfaces.size() == expected_surfaces,
		"表面数が部屋数 + 物の数と一致する (%d == %d)"
		% [layout.surfaces.size(), expected_surfaces],
	)
	var found_types: Dictionary = {}
	for surface: MansionLayout.SurfaceDef in layout.surfaces:
		found_types[surface.surface_type] = true
	for required_type: StringName in [
		MansionLayoutScript.SURFACE_FLOOR,
		MansionLayoutScript.SURFACE_CARPET,
		MansionLayoutScript.SURFACE_SOFA,
		MansionLayoutScript.SURFACE_KNIT,
		MansionLayoutScript.SURFACE_SUIT,
		MansionLayoutScript.SURFACE_FURNITURE,
	]:
		_check(
			found_types.has(required_type),
			"表面の種類 %s が屋敷に含まれる" % String(required_type),
		)
	_check(
		layout.rooms[0].open_east and layout.rooms[1].open_west,
		"隣接する部屋 0 と部屋 1 の間にドア開口がある",
	)


## 調整値を変えると部屋数・広さ・物の数・毛の本数・探し物の数がすべて変化するか
func _check_mansion_builder_changes_with_tuning() -> void:
	var base_layout: MansionLayout = MansionBuilderScript.build_layout(MansionTuningScript.new())

	var custom: MansionTuning = MansionTuningScript.new()
	custom.room_count = 6
	custom.room_size_m = 9.0
	custom.object_count = 23
	custom.hair_count = 54321
	custom.found_item_count = 9

	var layout: MansionLayout = MansionBuilderScript.build_layout(custom)
	var progress: BuildingProgress = MansionBuilderScript.build_initial_progress(layout, custom)

	_check(layout.rooms.size() == 6, "変更後の部屋数が 6 (実際: %d)" % layout.rooms.size())
	_check(layout.objects.size() == 23, "変更後の物の数が 23 (実際: %d)" % layout.objects.size())
	_check(
		layout.found_item_spots.size() == 9,
		"変更後の探し物置き場所数が 9 (実際: %d)" % layout.found_item_spots.size(),
	)
	_check(
		progress.total_remaining_hairs() == 54321,
		"変更後の毛の総本数が 54321 (実際: %d)" % progress.total_remaining_hairs(),
	)
	_check(
		is_equal_approx(layout.total_floor_area(), 6.0 * 9.0 * 9.0),
		"変更後の総床面積が 486.0 m^2 (実際: %.2f)" % layout.total_floor_area(),
	)
	_check(
		layout.total_floor_area() > base_layout.total_floor_area(),
		"広さを広げると総床面積が増える",
	)


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

	# 下限未満のクランプ (5 項目すべて)
	var below_min: MansionTuning = MansionTuningScript.new()
	below_min.room_count = 0
	below_min.hair_count = -50
	below_min.object_count = -3
	below_min.found_item_count = -2
	below_min.room_size_m = MansionTuningScript.MIN_ROOM_SIZE_M - 1.5
	var clamped_min: MansionTuning = below_min.clamped()
	_check(clamped_min.room_count == MansionTuningScript.MIN_ROOM_COUNT, "部屋数下限未満が 1 に丸められる")
	_check(clamped_min.hair_count == MansionTuningScript.MIN_HAIR_COUNT, "毛本数下限未満が 0 に丸められる")
	_check(clamped_min.object_count == MansionTuningScript.MIN_OBJECT_COUNT, "物数下限未満が 0 に丸められる")
	_check(
		clamped_min.found_item_count == MansionTuningScript.MIN_FOUND_ITEM_COUNT,
		"探し物数下限未満が 0 に丸められる",
	)
	_check(
		is_equal_approx(clamped_min.room_size_m, MansionTuningScript.MIN_ROOM_SIZE_M),
		"広さ下限未満が MIN_ROOM_SIZE_M に丸められる",
	)

	# 上限ちょうどと上限 + 1 のクランプ (5 項目すべて)
	var above_max: MansionTuning = MansionTuningScript.new()
	above_max.room_count = MansionTuningScript.MAX_ROOM_COUNT + 1
	above_max.hair_count = MansionTuningScript.MAX_HAIR_COUNT + 1
	above_max.object_count = MansionTuningScript.MAX_OBJECT_COUNT + 1
	above_max.found_item_count = MansionTuningScript.MAX_FOUND_ITEM_COUNT + 1
	above_max.room_size_m = MansionTuningScript.MAX_ROOM_SIZE_M + 1.0
	var clamped_max: MansionTuning = above_max.clamped()
	_check(
		clamped_max.room_count == MansionTuningScript.MAX_ROOM_COUNT,
		"部屋数上限 + 1 が MAX_ROOM_COUNT に丸められる",
	)
	_check(
		clamped_max.hair_count == MansionTuningScript.MAX_HAIR_COUNT,
		"毛本数上限 + 1 が MAX_HAIR_COUNT に丸められる",
	)
	_check(
		clamped_max.object_count == MansionTuningScript.MAX_OBJECT_COUNT,
		"物数上限 + 1 が MAX_OBJECT_COUNT に丸められる",
	)
	_check(
		clamped_max.found_item_count == MansionTuningScript.MAX_FOUND_ITEM_COUNT,
		"探し物数上限 + 1 が MAX_FOUND_ITEM_COUNT に丸められる",
	)
	_check(
		is_equal_approx(clamped_max.room_size_m, MansionTuningScript.MAX_ROOM_SIZE_M),
		"広さ上限超過が MAX_ROOM_SIZE_M に丸められる",
	)


## MansionTuning.equals とコマンドライン引数解析の各項目単独分岐を検証する
func _check_tuning_equals_and_cmdline_args() -> void:
	var base: MansionTuning = MansionTuningScript.new()
	_check(base.equals(MansionTuningScript.new()), "同じ値の MansionTuning で equals が true")
	_check(not base.equals(null), "null との equals が false")

	var diff_hair: MansionTuning = base.clamped()
	diff_hair.hair_count += 1
	_check(not base.equals(diff_hair), "hair_count だけ異なると equals が false")

	var diff_found: MansionTuning = base.clamped()
	diff_found.found_item_count += 1
	_check(not base.equals(diff_found), "found_item_count だけ異なると equals が false")

	var diff_size: MansionTuning = base.clamped()
	diff_size.room_size_m += 1.0
	_check(not base.equals(diff_size), "room_size_m だけ異なると equals が false")

	var diff_object: MansionTuning = base.clamped()
	diff_object.object_count += 1
	_check(not base.equals(diff_object), "object_count だけ異なると equals が false")

	var diff_room: MansionTuning = base.clamped()
	diff_room.room_count += 1
	_check(not base.equals(diff_room), "room_count だけ異なると equals が false")

	# 5 つのコマンドライン引数がそれぞれ単独で has_cmdline_override = true になる
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

	var all_args: PackedStringArray = PackedStringArray([
		"--hair-count=321",
		"--found-item-count=2",
		"--room-size=8.5",
		"--object-count=7",
		"--room-count=3",
	])
	var parsed: MansionTuning = MansionTuningScript.from_cmdline_args(all_args)
	_check(parsed.hair_count == 321, "引数 --hair-count=321 が反映される")
	_check(parsed.found_item_count == 2, "引数 --found-item-count=2 が反映される")
	_check(is_equal_approx(parsed.room_size_m, 8.5), "引数 --room-size=8.5 が反映される")
	_check(parsed.object_count == 7, "引数 --object-count=7 が反映される")
	_check(parsed.room_count == 3, "引数 --room-count=3 が反映される")

	var invalid_args: PackedStringArray = PackedStringArray([
		"--hair-count=not_a_number",
		"--room-size=bad",
		"--unrelated=1",
	])
	var fallback: MansionTuning = MansionTuningScript.from_cmdline_args(invalid_args)
	_check(
		fallback.hair_count == MansionTuningScript.DEFAULT_HAIR_COUNT,
		"不正な整数引数では既定値が保たれる",
	)
	_check(
		is_equal_approx(fallback.room_size_m, MansionTuningScript.DEFAULT_ROOM_SIZE_M),
		"不正な浮動小数引数では既定値が保たれる",
	)
	_check(
		not MansionTuningScript.has_cmdline_override(PackedStringArray(["--other=1"])),
		"無関係な引数だけで has_cmdline_override が false",
	)


## MansionWorld の仮描画毛インスタンス数が面上限・全体上限・0 本の境界を守るか検証する
func _check_visual_hair_limits() -> void:
	var world: MansionWorld = MansionWorldScript.new()

	# 既定値 (12,000 本): 1 以上かつ全体上限以下
	var default_tuning: MansionTuning = MansionTuningScript.new()
	var default_layout: MansionLayout = MansionBuilderScript.build_layout(default_tuning)
	var default_progress: BuildingProgress = MansionBuilderScript.build_initial_progress(
		default_layout,
		default_tuning,
	)
	world.rebuild(default_layout, default_progress)
	var rendered_default: int = world.get_rendered_hair_instance_count()
	_check(
		rendered_default > 0
		and rendered_default <= MansionWorldScript.MAX_VISUAL_HAIRS_TOTAL,
		"既定屋敷の仮毛描画数が 1..%d の範囲内 (実際: %d)"
		% [MansionWorldScript.MAX_VISUAL_HAIRS_TOTAL, rendered_default],
	)

	# 1 面のみ・100 本: 面あたり上限 (45) に収まる
	var single_surface_tuning: MansionTuning = MansionTuningScript.new()
	single_surface_tuning.room_count = 1
	single_surface_tuning.object_count = 0
	single_surface_tuning.hair_count = 100
	var single_layout: MansionLayout = MansionBuilderScript.build_layout(single_surface_tuning)
	var single_progress: BuildingProgress = MansionBuilderScript.build_initial_progress(
		single_layout,
		single_surface_tuning,
	)
	world.rebuild(single_layout, single_progress)
	_check(
		world.get_rendered_hair_instance_count()
		== MansionWorldScript.MAX_VISUAL_HAIRS_PER_SURFACE,
		"1 面 100 本の仮毛描画数が面上限 %d と一致する (実際: %d)"
		% [
			MansionWorldScript.MAX_VISUAL_HAIRS_PER_SURFACE,
			world.get_rendered_hair_instance_count(),
		],
	)

	# 毛 0 本: 仮毛インスタンス数 0
	var zero_tuning: MansionTuning = MansionTuningScript.new()
	zero_tuning.room_count = 1
	zero_tuning.object_count = 0
	zero_tuning.hair_count = 0
	var zero_layout: MansionLayout = MansionBuilderScript.build_layout(zero_tuning)
	var zero_progress: BuildingProgress = MansionBuilderScript.build_initial_progress(
		zero_layout,
		zero_tuning,
	)
	world.rebuild(zero_layout, zero_progress)
	_check(
		world.get_rendered_hair_instance_count() == 0,
		"毛 0 本の屋敷では仮毛描画数が 0",
	)
	world.free()


## セーブして読み戻すと、面ごと・色ごとの毛の本数とお金・全進捗フィールドの中身が一致するか検証する
func _check_save_and_load_roundtrip() -> void:
	SaveStorageScript.delete_save_file(TEST_SAVE_PATH)
	var save_fixture: SaveData = _create_rich_save_fixture()

	var save_error: Error = SaveStorageScript.save_to_path(save_fixture, TEST_SAVE_PATH)
	_check(save_error == OK, "セーブファイルの保存が成功する (err=%d)" % save_error)

	var loaded: SaveData = SaveStorageScript.load_from_path(TEST_SAVE_PATH)
	_check(loaded != null, "保存したセーブデータを読み戻せる")
	if loaded == null:
		return

	_check(loaded.building_progress.money == 4321, "所持金が一致する (4321)")
	_check(
		is_equal_approx(loaded.building_progress.elapsed_seconds, 123.5),
		"経過時間が一致する (123.5)",
	)
	_check(loaded.tuning.equals(save_fixture.tuning), "保存した調整値が一致する")
	_check(
		loaded.building_progress.surface_hairs.size()
		== save_fixture.building_progress.surface_hairs.size(),
		"表面数が一致する",
	)
	var first_surface: SurfaceHair = loaded.building_progress.surface_hairs[0]
	_check(
		first_surface.surface_id == save_fixture.building_progress.surface_hairs[0].surface_id,
		"先頭の面 id が一致する",
	)
	_check(
		first_surface.count_for_color(SurfaceHairScript.COLOR_WHITE) == 42,
		"面の白毛本数が一致する (42)",
	)
	_check(
		first_surface.count_for_color(SurfaceHairScript.COLOR_BLACK) == 17,
		"面の黒毛本数が一致する (17)",
	)
	_check(
		first_surface.count_for_color(SurfaceHairScript.COLOR_CALICO) == 9,
		"面の三毛本数が一致する (9)",
	)
	_check(
		loaded.building_progress.hair_stocks.size() == 1
		and loaded.building_progress.hair_stocks[0].hair_color == SurfaceHairScript.COLOR_WHITE
		and loaded.building_progress.hair_stocks[0].rare_hair_id == &"golden_hair"
		and loaded.building_progress.hair_stocks[0].form == HairStockScript.FORM_FELT
		and loaded.building_progress.hair_stocks[0].count == 3,
		"毛・加工品在庫の色・珍しい毛 id・形・個数がすべて一致する",
	)
	_check(
		loaded.hand_upgrade_levels.get(&"dexterity", 0) == 3
		and loaded.hand_upgrade_levels.get(&"pinch_count", 0) == 2,
		"持ち越す手の強化レベル 2 種が一致する",
	)
	_check(
		loaded.found_rare_hair_ids.size() == 2
		and loaded.found_rare_hair_ids[0] == &"whisker"
		and loaded.found_rare_hair_ids[1] == &"golden_hair",
		"図鑑の珍しい毛 id 要素が一致する",
	)
	_check(
		loaded.building_records.size() == 1
		and loaded.building_records[0].building_id == &"mansion"
		and is_equal_approx(loaded.building_records[0].clear_seconds, 3600.0)
		and loaded.building_records[0].returned_found_item_count == 5,
		"終えた建物の成績の全フィールドが一致する",
	)
	_check(
		loaded.building_progress.owned_tools.size() == 1
		and loaded.building_progress.owned_tools[0].tool_id == &"cleaning_robot"
		and loaded.building_progress.owned_tools[0].level == 2
		and loaded.building_progress.owned_tools[0].consumable_count == 4
		and loaded.building_progress.owned_tools[0].robot_room_ids == [&"hall", &"living"],
		"買った道具とロボット巡回順の全要素が一致する",
	)
	_check(
		is_equal_approx(loaded.building_progress.resident_moods.get(&"resident_hall", -1.0), 0.75),
		"住人の機嫌の値が一致する (0.75)",
	)
	_check(
		loaded.building_progress.found_items[0].condition
		== FoundItemProgressScript.Condition.CLEAN
		and loaded.building_progress.found_items[0].is_returned,
		"探し物の状態と返却フラグが一致する",
	)


## 保存データが無い時・全体破損・部分破損のそれぞれでエラーなく新しく始められるか検証する
func _check_save_missing_and_corrupted() -> void:
	SaveStorageScript.delete_save_file(TEST_SAVE_PATH)
	_check(
		SaveStorageScript.load_from_path(TEST_SAVE_PATH) == null,
		"保存データが無い時は null を返す",
	)
	var missing_save_state: Node = GameStateScript.new()
	missing_save_state.initialize_from_storage(TEST_SAVE_PATH)
	_check(
		not missing_save_state.loaded_from_save
		and missing_save_state.save_data != null
		and missing_save_state.get_total_remaining_hairs()
		== MansionTuningScript.DEFAULT_HAIR_COUNT,
		"保存データが無い時に既定値で新しく始められる",
	)
	missing_save_state.free()

	for bad_payload: String in [
		"{broken json",
		"",
		"{\"schema_version\": 999}",
	]:
		var file: FileAccess = FileAccess.open(TEST_SAVE_PATH, FileAccess.WRITE)
		file.store_string(bad_payload)
		file.close()
		_check(
			SaveStorageScript.load_from_path(TEST_SAVE_PATH) == null,
			"壊れた保存データ (%s) で null を返す" % bad_payload,
		)
		var corrupted_save_state: Node = GameStateScript.new()
		corrupted_save_state.initialize_from_storage(TEST_SAVE_PATH)
		_check(
			not corrupted_save_state.loaded_from_save
			and corrupted_save_state.current_layout != null,
			"壊れた保存データ (%s) でも新しく始められる" % bad_payload,
		)
		corrupted_save_state.free()

	# 有効な SaveData 辞書をベースに 1 フィールドだけ壊した部分破損テスト群
	var valid_dict: Dictionary = _create_rich_save_fixture().to_dict()

	var missing_tuning: Dictionary = valid_dict.duplicate(true)
	missing_tuning.erase("tuning")
	_check(SaveDataScript.from_dict(missing_tuning) == null, "tuning 欠損で null を返す")

	var bad_tuning_type: Dictionary = valid_dict.duplicate(true)
	bad_tuning_type["tuning"] = "not_a_dict"
	_check(SaveDataScript.from_dict(bad_tuning_type) == null, "tuning 型違いで null を返す")

	var bad_rare_elem: Dictionary = valid_dict.duplicate(true)
	bad_rare_elem["found_rare_hair_ids"] = [123]
	_check(
		SaveDataScript.from_dict(bad_rare_elem) == null,
		"found_rare_hair_ids に数値要素があると null を返す",
	)

	var bad_cond_low: Dictionary = valid_dict.duplicate(true)
	bad_cond_low["building_progress"]["found_items"][0]["condition"] = -1
	_check(
		SaveDataScript.from_dict(bad_cond_low) == null,
		"FoundItemProgress.condition = -1 で null を返す",
	)

	var bad_cond_high: Dictionary = valid_dict.duplicate(true)
	bad_cond_high["building_progress"]["found_items"][0]["condition"] = 4
	_check(
		SaveDataScript.from_dict(bad_cond_high) == null,
		"FoundItemProgress.condition = 4 で null を返す",
	)

	for bad_stock_field: String in ["hair_color", "rare_hair_id", "form"]:
		var bad_stock: Dictionary = valid_dict.duplicate(true)
		bad_stock["building_progress"]["hair_stocks"][0][bad_stock_field] = 999
		_check(
			SaveDataScript.from_dict(bad_stock) == null,
			"HairStock.%s が数値だと null を返す" % bad_stock_field,
		)


## GameState のコマンドライン引数上書き分岐と面一覧照合 (_reconcile_progress_with_layout) を検証する
func _check_game_state_cmdline_override_and_reconcile() -> void:
	SaveStorageScript.delete_save_file(TEST_SAVE_PATH)

	# 1. 保存データなし + 引数上書きあり
	var state_no_save: Node = GameStateScript.new()
	state_no_save.initialize_from_storage(
		TEST_SAVE_PATH,
		PackedStringArray(["--hair-count=777", "--room-count=2"]),
	)
	_check(
		not state_no_save.loaded_from_save
		and state_no_save.get_tuning().hair_count == 777
		and state_no_save.get_tuning().room_count == 2
		and state_no_save.get_total_remaining_hairs() == 777,
		"保存データなし + 引数上書きで指定値の屋敷を組み立てる",
	)
	state_no_save.free()

	# 2. 保存データあり + 引数上書きあり (保存済み room_size_m=9.0 を保ちつつ room_count=1 で上書き)
	var saved_fixture: SaveData = _create_rich_save_fixture()
	saved_fixture.tuning.room_size_m = 9.0
	SaveStorageScript.save_to_path(saved_fixture, TEST_SAVE_PATH)

	var state_override: Node = GameStateScript.new()
	state_override.initialize_from_storage(
		TEST_SAVE_PATH,
		PackedStringArray(["--room-count=1", "--hair-count=300"]),
	)
	_check(
		not state_override.loaded_from_save
		and state_override.get_tuning().room_count == 1
		and is_equal_approx(state_override.get_tuning().room_size_m, 9.0)
		and state_override.get_total_remaining_hairs() == 300,
		"保存データあり + 引数上書きで保存調整値を土台に引数優先で作り直す",
	)
	state_override.free()

	# 3. _reconcile_progress_with_layout: 面一致時は所持金と毛本数を保持する
	var consistent_save: SaveData = _create_rich_save_fixture()
	consistent_save.building_progress.money = 777
	SaveStorageScript.save_to_path(consistent_save, TEST_SAVE_PATH)
	var state_consistent: Node = GameStateScript.new()
	state_consistent.initialize_from_storage(TEST_SAVE_PATH)
	_check(
		state_consistent.loaded_from_save and state_consistent.get_money() == 777,
		"面一覧がレイアウトと一致する保存データは所持金 777 を保持する",
	)
	state_consistent.free()

	# 4. _reconcile_progress_with_layout: 面の件数が食い違う時は進行を作り直す
	var wrong_count_save: SaveData = _create_rich_save_fixture()
	wrong_count_save.building_progress.money = 888
	wrong_count_save.building_progress.surface_hairs.pop_back()
	SaveStorageScript.save_to_path(wrong_count_save, TEST_SAVE_PATH)
	var state_wrong_count: Node = GameStateScript.new()
	state_wrong_count.initialize_from_storage(TEST_SAVE_PATH)
	_check(
		state_wrong_count.get_money() == 0
		and state_wrong_count.save_data.building_progress.surface_hairs.size()
		== state_wrong_count.current_layout.surfaces.size(),
		"面の件数が食い違う保存データは進行を作り直す",
	)
	state_wrong_count.free()

	# 5. _reconcile_progress_with_layout: 件数は同じだが surface_id が食い違う時は進行を作り直す
	var wrong_id_save: SaveData = _create_rich_save_fixture()
	wrong_id_save.building_progress.money = 999
	wrong_id_save.building_progress.surface_hairs[0].surface_id = &"unknown_surface_id"
	SaveStorageScript.save_to_path(wrong_id_save, TEST_SAVE_PATH)
	var state_wrong_id: Node = GameStateScript.new()
	state_wrong_id.initialize_from_storage(TEST_SAVE_PATH)
	_check(
		state_wrong_id.get_money() == 0
		and state_wrong_id.save_data.building_progress.find_surface_hair(&"unknown_surface_id")
		== null,
		"surface_id が食い違う保存データは進行を作り直す",
	)
	state_wrong_id.free()


## 毛の本数の 3 桁区切り整形を検証する
func _check_format_hair_count() -> void:
	_check(MainScript.format_hair_count(0) == "0", "0 の整形が '0'")
	_check(MainScript.format_hair_count(999) == "999", "999 の整形が '999'")
	_check(MainScript.format_hair_count(1000) == "1,000", "1000 の整形が '1,000'")
	_check(MainScript.format_hair_count(1234567) == "1,234,567", "1234567 の整形が '1,234,567'")
	_check(MainScript.format_hair_count(-5) == "0", "負の値の整形が '0'")


## 全フィールドに検証用の値を入れた SaveData のテストフィクスチャを生成する
func _create_rich_save_fixture() -> SaveData:
	var tuning: MansionTuning = MansionTuningScript.new()
	tuning.room_count = 2
	tuning.object_count = 4
	tuning.hair_count = 250
	tuning.found_item_count = 2
	tuning.room_size_m = 7.0

	var layout: MansionLayout = MansionBuilderScript.build_layout(tuning)
	var progress: BuildingProgress = MansionBuilderScript.build_initial_progress(layout, tuning)
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

extends "res://scripts/dev/headless_check.gd"
## 純粋なロジックとプロジェクト設定の検証 (headless)。ゲームのルールの計算を足したら、ここに検証を足す。
## 実行方法は AGENTS.md「検証方法」を参照。

const MainScript := preload("res://scripts/main.gd")
const MansionTuningScript := preload("res://scripts/data/mansion_tuning.gd")
const MansionLayoutScript := preload("res://scripts/mansion/mansion_layout.gd")
const MansionBuilderScript := preload("res://scripts/mansion/mansion_builder.gd")
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
	_check_cmdline_args_parsing()
	_check_save_and_load_roundtrip()
	_check_save_missing_and_corrupted()
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
	# 2x2 配置の部屋 0 と部屋 1 は東西でドア開口が対称につながる
	_check(
		layout.rooms[0].open_east and layout.rooms[1].open_west,
		"隣接する部屋 0 と部屋 1 の間にドア開口がある",
	)


## 調整値を変えると部屋数・広さ・物の数・毛の本数・探し物の数がすべて変化するか
func _check_mansion_builder_changes_with_tuning() -> void:
	var base_tuning: MansionTuning = MansionTuningScript.new()
	var base_layout: MansionLayout = MansionBuilderScript.build_layout(base_tuning)

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


## 境界値 (部屋 1 つ・毛 0 本・物 0 個・探し物 0 個) と範囲外値のクランプを検証する
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

	# 物 0 個でも探し物と毛を床へ正しく割り当てられる
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

	# 範囲外の値は安全にクランプされる
	var out_of_range: MansionTuning = MansionTuningScript.new()
	out_of_range.room_count = 0
	out_of_range.hair_count = -50
	out_of_range.object_count = -3
	out_of_range.found_item_count = -2
	out_of_range.room_size_m = 999.0
	var clamped: MansionTuning = out_of_range.clamped()
	_check(clamped.room_count == MansionTuningScript.MIN_ROOM_COUNT, "部屋数 0 が最小値 1 に丸められる")
	_check(clamped.hair_count == MansionTuningScript.MIN_HAIR_COUNT, "毛 -50 が 0 に丸められる")
	_check(clamped.object_count == 0, "物の数 -3 が 0 に丸められる")
	_check(clamped.found_item_count == 0, "探し物 -2 が 0 に丸められる")
	_check(
		is_equal_approx(clamped.room_size_m, MansionTuningScript.MAX_ROOM_SIZE_M),
		"広さ 999.0 が上限に丸められる",
	)


## コマンドライン引数から調整値を上書きできること・不正値を無視することを検証する
func _check_cmdline_args_parsing() -> void:
	var args: PackedStringArray = PackedStringArray([
		"--hair-count=321",
		"--found-item-count=2",
		"--room-size=8.5",
		"--object-count=7",
		"--room-count=3",
	])
	_check(
		MansionTuningScript.has_cmdline_override(args),
		"調整値引数ありで has_cmdline_override が true",
	)
	var parsed: MansionTuning = MansionTuningScript.from_cmdline_args(args)
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


## セーブして読み戻すと、面ごと・色ごとの毛の本数とお金・各種進捗が一致することを検証する
func _check_save_and_load_roundtrip() -> void:
	SaveStorageScript.delete_save_file(TEST_SAVE_PATH)
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
	# 面ごと・色ごとの固有値を明示的に設定して一致を確かめる
	progress.surface_hairs[0].hair_counts[SurfaceHairScript.COLOR_WHITE] = 42
	progress.surface_hairs[0].hair_counts[SurfaceHairScript.COLOR_BLACK] = 17
	progress.surface_hairs[0].hair_counts[SurfaceHairScript.COLOR_CALICO] = 9

	var stock: HairStock = HairStockScript.new()
	stock.hair_color = SurfaceHairScript.COLOR_WHITE
	stock.rare_hair_id = &"golden_hair"
	stock.form = HairStockScript.FORM_FELT
	stock.count = 3
	progress.hair_stocks.append(stock)

	var tool: OwnedTool = OwnedToolScript.new()
	tool.tool_id = &"cleaning_robot"
	tool.level = 2
	tool.consumable_count = 0
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

	var err: Error = SaveStorageScript.save_to_path(save, TEST_SAVE_PATH)
	_check(err == OK, "セーブファイルの保存が成功する (err=%d)" % err)

	var loaded: SaveData = SaveStorageScript.load_from_path(TEST_SAVE_PATH)
	_check(loaded != null, "保存したセーブデータを読み戻せる")
	if loaded == null:
		return

	_check(loaded.building_progress.money == 4321, "所持金が一致する (4321)")
	_check(loaded.tuning.equals(tuning), "保存した調整値が一致する")
	_check(
		loaded.building_progress.surface_hairs.size() == progress.surface_hairs.size(),
		"表面数が一致する",
	)
	var first_surface: SurfaceHair = loaded.building_progress.surface_hairs[0]
	_check(
		first_surface.surface_id == progress.surface_hairs[0].surface_id,
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
		loaded.hand_upgrade_levels.get(&"dexterity", 0) == 3,
		"持ち越す手の強化レベルが一致する",
	)
	_check(loaded.found_rare_hair_ids.size() == 2, "図鑑の珍しい毛が一致する")
	_check(loaded.building_records.size() == 1, "終えた建物の成績が一致する")
	_check(
		loaded.building_progress.owned_tools.size() == 1
		and loaded.building_progress.owned_tools[0].robot_room_ids.size() == 2,
		"買った道具とロボット巡回順が一致する",
	)
	_check(
		loaded.building_progress.found_items[0].condition
		== FoundItemProgressScript.Condition.CLEAN
		and loaded.building_progress.found_items[0].is_returned,
		"探し物の状態と返却フラグが一致する",
	)


## 保存データが無い時・壊れている時にエラーなく新しく始められることを検証する
func _check_save_missing_and_corrupted() -> void:
	SaveStorageScript.delete_save_file(TEST_SAVE_PATH)
	_check(
		SaveStorageScript.load_from_path(TEST_SAVE_PATH) == null,
		"保存データが無い時は null を返す",
	)
	var gs_missing: Node = GameStateScript.new()
	gs_missing.initialize_from_storage(TEST_SAVE_PATH)
	_check(
		not gs_missing.loaded_from_save
		and gs_missing.save_data != null
		and gs_missing.get_total_remaining_hairs() == MansionTuningScript.DEFAULT_HAIR_COUNT,
		"保存データが無い時に既定値で新しく始められる",
	)
	gs_missing.free()

	for bad_payload: String in [
		"{broken json",
		"",
		"{\"schema_version\": 999}",
		"{\"schema_version\": 1, \"tuning\": \"not_a_dict\"}",
	]:
		var file: FileAccess = FileAccess.open(TEST_SAVE_PATH, FileAccess.WRITE)
		file.store_string(bad_payload)
		file.close()
		_check(
			SaveStorageScript.load_from_path(TEST_SAVE_PATH) == null,
			"壊れた保存データ (%s) で null を返す" % bad_payload,
		)
		var gs_corrupt: Node = GameStateScript.new()
		gs_corrupt.initialize_from_storage(TEST_SAVE_PATH)
		_check(
			not gs_corrupt.loaded_from_save and gs_corrupt.current_layout != null,
			"壊れた保存データ (%s) でも新しく始められる" % bad_payload,
		)
		gs_corrupt.free()


## 毛の本数の 3 桁区切り整形を検証する
func _check_format_hair_count() -> void:
	_check(MainScript.format_hair_count(0) == "0", "0 の整形が '0'")
	_check(MainScript.format_hair_count(999) == "999", "999 の整形が '999'")
	_check(MainScript.format_hair_count(1000) == "1,000", "1000 の整形が '1,000'")
	_check(MainScript.format_hair_count(1234567) == "1,234,567", "1234567 の整形が '1,234,567'")
	_check(MainScript.format_hair_count(-5) == "0", "負の値の整形が '0'")

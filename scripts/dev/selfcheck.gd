extends "res://scripts/dev/headless_check.gd"
## 純粋なロジックとプロジェクト設定の検証 (headless)。ゲームのルールの計算を足したら、ここに検証を足す。
## 実行方法は AGENTS.md「検証方法」を参照。

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
	_check_mansion_builder_changes_and_large_scale()
	_check_mansion_builder_boundaries()
	_check_tuning_equals_and_cmdline_args()
	_check_visual_hair_and_light_limits()
	_check_player_mouse_capture_predicate()
	_check_save_and_load_roundtrip()
	_check_save_missing_corrupted_and_clamping()
	_check_game_state_override_reconcile_and_notifications()
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
	for required_type: StringName in [
		MansionLayoutScript.SURFACE_FLOOR,
		MansionLayoutScript.SURFACE_CARPET,
		MansionLayoutScript.SURFACE_SOFA,
		MansionLayoutScript.SURFACE_KNIT,
		MansionLayoutScript.SURFACE_SUIT,
		MansionLayoutScript.SURFACE_FURNITURE,
	]:
		_check(found_types.has(required_type), "表面の種類 %s が含まれる" % String(required_type))
	_check(
		layout.rooms[0].open_east and layout.rooms[1].open_west,
		"隣接する部屋 0 と部屋 1 の間にドア開口がある",
	)


## 調整値変更・最大部屋数 (16 部屋・9 部屋目以降の連番 ID)・内側リング配置 (ring > 0)・物 200 個を検証する
func _check_mansion_builder_changes_and_large_scale() -> void:
	var base_layout: MansionLayout = MansionBuilderScript.build_layout(MansionTuningScript.new())

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
		and layout.total_floor_area() > base_layout.total_floor_area(),
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

	# 1 部屋に 12 個配置し、9 個目以降 (ring > 0) もすべて部屋の壁内に収まることを確認
	var dense_tuning: MansionTuning = MansionTuningScript.new()
	dense_tuning.room_count = 1
	dense_tuning.object_count = 12
	dense_tuning.room_size_m = 6.0
	var dense_layout: MansionLayout = MansionBuilderScript.build_layout(dense_tuning)
	var all_inside: bool = true
	for obj: MansionLayout.ObjectDef in dense_layout.objects:
		if absf(obj.position.x) >= 3.0 or absf(obj.position.z) >= 3.0:
			all_inside = false
	_check(dense_layout.objects.size() == 12 and all_inside, "ring > 0 の 12 個配置が部屋境界内に収まる")


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

	var diff_hair: MansionTuning = base.clamped()
	diff_hair.hair_count += 1
	var diff_found: MansionTuning = base.clamped()
	diff_found.found_item_count += 1
	var diff_size: MansionTuning = base.clamped()
	diff_size.room_size_m += 1.0
	var diff_object: MansionTuning = base.clamped()
	diff_object.object_count += 1
	var diff_room: MansionTuning = base.clamped()
	diff_room.room_count += 1
	_check(
		not base.equals(diff_hair)
		and not base.equals(diff_found)
		and not base.equals(diff_size)
		and not base.equals(diff_object)
		and not base.equals(diff_room),
		"5 項目のどれか 1 項目だけ異なると equals が false",
	)

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

	var all_args: PackedStringArray = PackedStringArray([
		"--hair-count=321",
		"--found-item-count=2",
		"--room-size=8.5",
		"--object-count=7",
		"--room-count=3",
	])
	var parsed: MansionTuning = MansionTuningScript.from_cmdline_args(all_args)
	_check(
		parsed.hair_count == 321
		and parsed.found_item_count == 2
		and is_equal_approx(parsed.room_size_m, 8.5)
		and parsed.object_count == 7
		and parsed.room_count == 3,
		"コマンドライン引数 5 項目すべてが反映される",
	)
	var fallback: MansionTuning = MansionTuningScript.from_cmdline_args(
		PackedStringArray(["--hair-count=bad", "--room-size=bad", "--unrelated=1"])
	)
	_check(
		fallback.equals(MansionTuningScript.new())
		and not MansionTuningScript.has_cmdline_override(PackedStringArray(["--other=1"])),
		"不正・無関係な引数では既定値が保たれ上書き扱いにならない",
	)


## MansionWorld の仮毛描画数上限と室内ライト数上限の境界を検証する
func _check_visual_hair_and_light_limits() -> void:
	var world: MansionWorld = MansionWorldScript.new()

	var default_tuning: MansionTuning = MansionTuningScript.new()
	var default_layout: MansionLayout = MansionBuilderScript.build_layout(default_tuning)
	world.rebuild(
		default_layout,
		MansionBuilderScript.build_initial_progress(default_layout, default_tuning),
	)
	_check(
		world.get_rendered_hair_instance_count() > 0
		and world.get_rendered_hair_instance_count()
		<= MansionWorldScript.MAX_VISUAL_HAIRS_TOTAL,
		"既定屋敷の仮毛描画数が全体上限内に収まる",
	)

	var single_surface_tuning: MansionTuning = MansionTuningScript.new()
	single_surface_tuning.room_count = 1
	single_surface_tuning.object_count = 0
	single_surface_tuning.hair_count = 100
	var single_layout: MansionLayout = MansionBuilderScript.build_layout(single_surface_tuning)
	world.rebuild(
		single_layout,
		MansionBuilderScript.build_initial_progress(single_layout, single_surface_tuning),
	)
	_check(
		world.get_rendered_hair_instance_count()
		== MansionWorldScript.MAX_VISUAL_HAIRS_PER_SURFACE,
		"1 面 100 本の仮毛描画数が面あたり上限と一致する",
	)

	var zero_tuning: MansionTuning = MansionTuningScript.new()
	zero_tuning.room_count = 1
	zero_tuning.object_count = 0
	zero_tuning.hair_count = 0
	var zero_layout: MansionLayout = MansionBuilderScript.build_layout(zero_tuning)
	world.rebuild(
		zero_layout,
		MansionBuilderScript.build_initial_progress(zero_layout, zero_tuning),
	)
	_check(world.get_rendered_hair_instance_count() == 0, "毛 0 本の屋敷では仮毛描画数が 0")

	# 室内ライト数上限境界: 部屋数 6 で 6 灯、部屋数 7 でも MAX_ROOM_LIGHTS 灯
	var six_rooms: MansionTuning = MansionTuningScript.new()
	six_rooms.room_count = MansionWorldScript.MAX_ROOM_LIGHTS
	six_rooms.object_count = 0
	var six_layout: MansionLayout = MansionBuilderScript.build_layout(six_rooms)
	world.rebuild(six_layout, MansionBuilderScript.build_initial_progress(six_layout, six_rooms))
	_check(
		world.get_room_light_count() == MansionWorldScript.MAX_ROOM_LIGHTS,
		"上限ちょうど部屋数でライト数が上限値と一致する",
	)

	var seven_rooms: MansionTuning = MansionTuningScript.new()
	seven_rooms.room_count = MansionWorldScript.MAX_ROOM_LIGHTS + 1
	seven_rooms.object_count = 0
	var seven_layout: MansionLayout = MansionBuilderScript.build_layout(seven_rooms)
	world.rebuild(
		seven_layout,
		MansionBuilderScript.build_initial_progress(seven_layout, seven_rooms),
	)
	_check(
		world.get_room_light_count() == MansionWorldScript.MAX_ROOM_LIGHTS,
		"上限 + 1 部屋でもライト数が MAX_ROOM_LIGHTS に抑えられる",
	)
	world.free()


## FirstPersonPlayer.should_capture_mouse の左押下・左解放・右押下を検証する
func _check_player_mouse_capture_predicate() -> void:
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
		FirstPersonPlayerScript.should_capture_mouse(left_press),
		"左ボタン押下でマウス捕捉対象になる",
	)
	_check(
		not FirstPersonPlayerScript.should_capture_mouse(left_release),
		"左ボタン解放ではマウス捕捉対象にならない",
	)
	_check(
		not FirstPersonPlayerScript.should_capture_mouse(right_press),
		"右ボタン押下ではマウス捕捉対象にならない",
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

	_check(loaded.building_progress.money == 4321, "所持金が一致する (4321)")
	_check(is_equal_approx(loaded.building_progress.elapsed_seconds, 123.5), "経過時間が一致する")
	_check(loaded.tuning.equals(save_fixture.tuning), "保存した調整値が一致する")
	var first_surface: SurfaceHair = loaded.building_progress.surface_hairs[0]
	_check(
		first_surface.surface_id == save_fixture.building_progress.surface_hairs[0].surface_id
		and first_surface.count_for_color(SurfaceHairScript.COLOR_WHITE) == 42
		and first_surface.count_for_color(SurfaceHairScript.COLOR_BLACK) == 17
		and first_surface.count_for_color(SurfaceHairScript.COLOR_CALICO) == 9,
		"先頭の面 id と 3 色の毛本数がすべて一致する",
	)
	_check(
		loaded.building_progress.hair_stocks.size() == 1
		and loaded.building_progress.hair_stocks[0].hair_color == SurfaceHairScript.COLOR_WHITE
		and loaded.building_progress.hair_stocks[0].rare_hair_id == &"golden_hair"
		and loaded.building_progress.hair_stocks[0].form == HairStockScript.FORM_FELT
		and loaded.building_progress.hair_stocks[0].count == 3,
		"毛・加工品在庫の全項目が一致する",
	)
	_check(
		loaded.hand_upgrade_levels.get(&"dexterity", 0) == 3
		and loaded.hand_upgrade_levels.get(&"pinch_count", 0) == 2,
		"持ち越す手の強化レベル 2 種が一致する",
	)
	_check(
		loaded.found_rare_hair_ids == [&"whisker", &"golden_hair"],
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
		"住人の機嫌の値が一致する",
	)
	_check(
		loaded.building_progress.found_items[0].condition
		== FoundItemProgressScript.Condition.CLEAN
		and loaded.building_progress.found_items[0].is_returned,
		"探し物の状態と返却フラグが一致する",
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

	for bad_payload: String in ["{broken json", ""]:
		var file: FileAccess = FileAccess.open(TEST_SAVE_PATH, FileAccess.WRITE)
		file.store_string(bad_payload)
		file.close()
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

	# 有効辞書で schema_version だけ 0 / 2 に変更 (未対応スキーマ判定を通す)
	for bad_version: int in [0, 2]:
		var bad_ver_dict: Dictionary = valid_dict.duplicate(true)
		bad_ver_dict["schema_version"] = bad_version
		_check(
			SaveDataScript.from_dict(bad_ver_dict) == null,
			"有効辞書の schema_version=%d は null を返す" % bad_version,
		)

	# 1 フィールドずつ壊した異常系群
	var mutated: Dictionary = valid_dict.duplicate(true)
	mutated.erase("tuning")
	_check(SaveDataScript.from_dict(mutated) == null, "部分破損 (tuning欠損) で null を返す")

	mutated = valid_dict.duplicate(true)
	mutated["tuning"] = "x"
	_check(SaveDataScript.from_dict(mutated) == null, "部分破損 (tuning型違い) で null を返す")

	mutated = valid_dict.duplicate(true)
	mutated["found_rare_hair_ids"] = [1]
	_check(SaveDataScript.from_dict(mutated) == null, "部分破損 (rare要素非文字) で null を返す")

	mutated = valid_dict.duplicate(true)
	mutated["hand_upgrade_levels"] = {"a": "x"}
	_check(SaveDataScript.from_dict(mutated) == null, "部分破損 (upgrade非数値) で null を返す")

	mutated = valid_dict.duplicate(true)
	mutated["building_records"][0]["clear_seconds"] = "x"
	_check(SaveDataScript.from_dict(mutated) == null, "部分破損 (record秒非数値) で null を返す")

	mutated = valid_dict.duplicate(true)
	mutated["building_progress"]["money"] = "x"
	_check(SaveDataScript.from_dict(mutated) == null, "部分破損 (money型違い) で null を返す")

	mutated = valid_dict.duplicate(true)
	mutated["building_progress"]["elapsed_seconds"] = "x"
	_check(SaveDataScript.from_dict(mutated) == null, "部分破損 (elapsed型違い) で null を返す")

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
	var extra_surface: SurfaceHair = SurfaceHairScript.new()
	extra_surface.surface_id = &"extra_surface"
	extra_surface_save.building_progress.surface_hairs.append(extra_surface)
	_assert_reconcile_resets("面に余分な要素あり", extra_surface_save)

	var wrong_surface_id_save: SaveData = _create_rich_save_fixture()
	wrong_surface_id_save.building_progress.surface_hairs[0].surface_id = &"unknown_surface"
	_assert_reconcile_resets("面 ID 不一致", wrong_surface_id_save)

	var extra_item_save: SaveData = _create_rich_save_fixture()
	var extra_item: FoundItemProgress = FoundItemProgressScript.new()
	extra_item.found_item_id = &"extra_item"
	extra_item_save.building_progress.found_items.append(extra_item)
	_assert_reconcile_resets("探し物件数過多", extra_item_save)

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
	SaveStorageScript.save_to_path(broken_save, TEST_SAVE_PATH)
	var state_reconciled: Node = GameStateScript.new()
	state_reconciled.initialize_from_storage(TEST_SAVE_PATH)
	_check(
		not state_reconciled.loaded_from_save and state_reconciled.get_money() == 0,
		"レイアウト不整合 (%s) で進行を作り直し loaded_from_save=false にする" % case_label,
	)
	state_reconciled.free()


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

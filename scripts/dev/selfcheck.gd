extends "res://scripts/dev/headless_check.gd"
## 純粋なロジックとプロジェクト設定の検証 (headless)。ゲームのルールの計算を足したら、ここに検証を足す。
## 屋敷・セーブ・調整値の検証は scripts/dev/selfcheck_mansion.gd、手で毛を取るルールと毛の照会の検証は
## scripts/dev/selfcheck_hand.gd、道具・お金・機嫌と掃除代の検証は scripts/dev/selfcheck_tools.gd、猫と掃除ロボットの検証は
## scripts/dev/selfcheck_automation.gd、大型の道具と加工の検証は scripts/dev/selfcheck_big_tools.gd に分割して実行する。
## 実行方法は AGENTS.md「検証方法」を参照。

## プロジェクト設定のメインシーンに入っているべきパス
const MAIN_SCENE_PATH: String = "res://scenes/main.tscn"
## 毛の描画の試作シーンのパス
const HAIR_PROTOTYPE_SCENE_PATH: String = "res://scenes/hair_prototype.tscn"
## プロジェクト設定の名前に入っているべき値 (ゲームの題名)
const PROJECT_NAME: String = "Oh My Fur!"
## プロジェクト設定のレンダラ (ADR 0002 で Forward+ に決定)
const RENDERING_METHOD: String = "forward_plus"
## プロジェクト設定のフレームレートの上限 (documents/DIRECTION.md「決めたこと」の 2026-11-27 の行で 60 に決定)
const MAX_FPS: int = 60
## fps と 1 フレームの時間の表示 (文言の組み立ての検証用)
const PerfOverlayScript := preload("res://scripts/ui/perf_overlay.gd")
## プロジェクト設定の音声バスレイアウトのパス
const BUS_LAYOUT_PATH: String = "res://default_bus_layout.tres"
## プロジェクト設定の AudioManager autoload の値
const AUDIO_MANAGER_AUTOLOAD: String = "*res://scripts/audio/audio_manager.gd"
## プロジェクト設定の GameState autoload の値
const GAME_STATE_AUTOLOAD: String = "*res://scripts/state/game_state.gd"
## 毛の描画ノードのスクリプト
const HairFieldScript := preload("res://scripts/hair_field.gd")
## ベンチマークスクリプト (純粋関数の単体検証用)
const HairbenchScript := preload("res://scripts/dev/hairbench.gd")
## 開発者向け調整値データ型 (既定の毛の本数の検証用)
const MansionTuningScript := preload("res://scripts/data/mansion_tuning.gd")
## メインシーンのスクリプト (残り本数の表示の整形の検証用)
const MainScript := preload("res://scripts/main.gd")
## 屋敷の 1 フレームの時間のベンチマーク (集計の純粋関数の検証用)
const ScenebenchScript := preload("res://scripts/dev/scenebench.gd")
## 音声カタログ (純粋関数)
const AudioCatalog := preload("res://scripts/audio/audio_catalog.gd")
## 音声設定の保存・読み込み・バス適用
const AudioSettings := preload("res://scripts/audio/audio_settings.gd")
## 起動録画スクリプト (引数解釈・録画フレーム計算の純粋関数)
const MovieScript := preload("res://scripts/dev/movie.gd")
## 屋敷・セーブ・調整値・プレイヤー純粋判定の検証スイート
const SelfcheckMansion := preload("res://scripts/dev/selfcheck_mansion.gd")
## 見た目の試作 (部屋・手・画面の表示) の検証スイート
const SelfcheckLook := preload("res://scripts/dev/selfcheck_look.gd")
## 手で毛を取るルール・毛の照会・表面の向きの検証スイート
const SelfcheckHand := preload("res://scripts/dev/selfcheck_hand.gd")
## 道具・お金・機嫌と掃除代・道具を買う画面の検証スイート
const SelfcheckTools := preload("res://scripts/dev/selfcheck_tools.gd")
## 猫と掃除ロボットの検証スイート
const SelfcheckAutomation := preload("res://scripts/dev/selfcheck_automation.gd")
## 大型の道具 (吸引車・粘着シート・アンドロイド・加工機・ダンプカー) と加工の検証スイート
const SelfcheckBigTools := preload("res://scripts/dev/selfcheck_big_tools.gd")


## 検証をすべて実行して終える
func _initialize() -> void:
	_check_project_settings()
	_check_main_scene_loads()
	_check_hair_prototype_loads()
	_check_hair_allocate_counts()
	_check_hair_mesh_shape()
	_check_hair_color_variety()
	_check_hair_field_populate_and_remove()
	_check_hairbench_helpers()
	_check_audio_bus_layout()
	_check_audio_catalog()
	_check_audio_settings_persistence()
	_check_audio_settings_bus_mute()
	_check_audio_manager_guards()
	_check_movie_frame_calculations()
	SelfcheckMansion.run_all(self)
	SelfcheckLook.run_all(self)
	SelfcheckHand.run_all(self)
	SelfcheckTools.run_all(self)
	SelfcheckAutomation.run_all(self)
	SelfcheckBigTools.run_all(self)
	_finish()


## プロジェクト設定の名前・メインシーン・レンダラ・音声設定・autoload・入力アクションが想定どおりか
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
	var rendering_method: String = ProjectSettings.get_setting(
		"rendering/renderer/rendering_method", ""
	)
	_check(
		rendering_method == RENDERING_METHOD,
		"rendering/renderer/rendering_method が %s (実際: %s)"
		% [RENDERING_METHOD, rendering_method]
	)
	var max_fps: int = ProjectSettings.get_setting("application/run/max_fps", 0)
	_check(max_fps == MAX_FPS, "application/run/max_fps が %d (実際: %d)" % [MAX_FPS, max_fps])
	var vsync_mode: int = ProjectSettings.get_setting("display/window/vsync/vsync_mode", -1)
	_check(
		vsync_mode == DisplayServer.VSYNC_ENABLED,
		"display/window/vsync/vsync_mode が Enabled (実際: %d)" % vsync_mode,
	)
	var perf_text: String = PerfOverlayScript.format_metrics(59.6, 16.78, 3.21, 4.5, 9.04)
	_check(
		perf_text == "60 fps   1 フレーム 16.8 ms   処理 3.2 ms   描画 CPU 4.5 ms / GPU 9.0 ms",
		"fps と 1 フレームの時間の表示の文言 (実際: %s)" % perf_text,
	)
	_check(
		is_equal_approx(PerfOverlayScript.frame_ms_from_fps(50.0), 20.0)
		and PerfOverlayScript.frame_ms_from_fps(0.0) == 0.0
		and PerfOverlayScript.frame_ms_from_fps(-1.0) == 0.0,
		"fps から 1 フレームの時間を出し、fps がまだ 0 の時は 0 にする",
	)
	_check_scenebench_summarize()
	# 既定の毛の本数は issue #56 で決めた 120,000 本で、残り本数の表示では桁区切りで出る
	_check(
		MansionTuningScript.DEFAULT_HAIR_COUNT == 120000
		and MainScript.format_hair_count(MansionTuningScript.DEFAULT_HAIR_COUNT) == "120,000",
		"既定の毛の本数が 120,000 で、表示が「120,000」 (実際: %d)" % MansionTuningScript.DEFAULT_HAIR_COUNT,
	)
	var bus_layout: String = ProjectSettings.get_setting("audio/buses/default_bus_layout", "")
	_check(
		bus_layout == BUS_LAYOUT_PATH,
		"audio/buses/default_bus_layout が %s (実際: %s)" % [BUS_LAYOUT_PATH, bus_layout],
	)
	var audio_autoload: String = ProjectSettings.get_setting("autoload/AudioManager", "")
	_check(
		audio_autoload == AUDIO_MANAGER_AUTOLOAD,
		"autoload/AudioManager が %s (実際: %s)" % [AUDIO_MANAGER_AUTOLOAD, audio_autoload],
	)
	var state_autoload: String = ProjectSettings.get_setting("autoload/GameState", "")
	_check(
		state_autoload == GAME_STATE_AUTOLOAD,
		"autoload/GameState が %s (実際: %s)" % [GAME_STATE_AUTOLOAD, state_autoload],
	)
	for action_name: String in [
		"move_forward",
		"move_back",
		"move_left",
		"move_right",
		"toggle_dev_panel",
		"save_game",
		"release_mouse",
		"pluck_hair",
		"toggle_hair_book",
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


## 毛の試作シーンがロードでき、PackedScene が返るか
func _check_hair_prototype_loads() -> void:
	_check(
		load(HAIR_PROTOTYPE_SCENE_PATH) is PackedScene,
		"%s が PackedScene としてロードできる" % HAIR_PROTOTYPE_SCENE_PATH
	)


## 表面ごとの本数配分 (正常系・端数・境界値・非正重み混在・異常系)
func _check_hair_allocate_counts() -> void:
	var weights: PackedFloat32Array = PackedFloat32Array([0.82, 0.18])
	var normal: PackedInt32Array = HairFieldScript.allocate_counts(1000, weights)
	_check(
		normal.size() == 2 and normal[0] == 820 and normal[1] == 180,
		"1000 本を 0.82:0.18 で配分すると [820, 180] (実際: %s)" % [str(normal)]
	)

	var fractional_counts: PackedInt32Array = HairFieldScript.allocate_counts(7, weights)
	_check(
		fractional_counts.size() == 2
		and fractional_counts[0] + fractional_counts[1] == 7
		and fractional_counts[0] == 6
		and fractional_counts[1] == 1,
		"端数のある 7 本の合計が 7 で [6, 1] (実際: %s)" % [str(fractional_counts)]
	)

	var single_hair_counts: PackedInt32Array = HairFieldScript.allocate_counts(1, weights)
	_check(
		single_hair_counts.size() == 2
		and single_hair_counts[0] == 1
		and single_hair_counts[1] == 0,
		"1 本の時は重みが大きい面に配分され合計 1 (実際: %s)" % [str(single_hair_counts)]
	)

	var zero: PackedInt32Array = HairFieldScript.allocate_counts(0, weights)
	_check(
		zero.size() == 2 and zero[0] == 0 and zero[1] == 0,
		"0 本の時は [0, 0] (実際: %s)" % [str(zero)]
	)

	var negative: PackedInt32Array = HairFieldScript.allocate_counts(-10, weights)
	_check(
		negative.size() == 2 and negative[0] == 0 and negative[1] == 0,
		"負の本数の時は [0, 0] (実際: %s)" % [str(negative)]
	)

	_check(
		HairFieldScript.allocate_counts(100, PackedFloat32Array()).is_empty(),
		"重み配列が空なら空配列を返す"
	)

	var zero_weights: PackedInt32Array = HairFieldScript.allocate_counts(
		100, PackedFloat32Array([0.0, 0.0])
	)
	_check(
		zero_weights.size() == 2 and zero_weights[0] == 0 and zero_weights[1] == 0,
		"重み合計が 0 なら [0, 0]"
	)

	# 非正の重み (0 や負) と正の重みが混在しても端数が非正の面に配られないこと
	var mixed_weights: PackedInt32Array = HairFieldScript.allocate_counts(
		5, PackedFloat32Array([0.0, -2.0, 1.0, 1.0])
	)
	_check(
		mixed_weights.size() == 4
		and mixed_weights[0] == 0
		and mixed_weights[1] == 0
		and mixed_weights[2] + mixed_weights[3] == 5,
		"非正の重み混在時に 0/負重みの面は 0 本で合計 5 (実際: %s)" % [str(mixed_weights)]
	)


## 屋敷の 1 フレームの時間のベンチマークの集計 (中央値・最小・最大・平均) が空・奇数個・偶数個で正しいか
func _check_scenebench_summarize() -> void:
	var empty: Dictionary = ScenebenchScript.summarize([])
	_check(
		empty["median"] == 0.0 and empty["min"] == 0.0 and empty["max"] == 0.0 and empty["avg"] == 0.0,
		"scenebench の集計: 空なら全部 0 (実際: %s)" % str(empty),
	)
	var single: Dictionary = ScenebenchScript.summarize([7.0])
	_check(
		single["median"] == 7.0 and single["min"] == 7.0 and single["max"] == 7.0,
		"scenebench の集計: 1 個ならその値 (実際: %s)" % str(single),
	)
	var odd: Dictionary = ScenebenchScript.summarize([9.0, 1.0, 5.0])
	_check(
		odd["median"] == 5.0 and odd["min"] == 1.0 and odd["max"] == 9.0 and odd["avg"] == 5.0,
		"scenebench の集計: 順不同の奇数個は真ん中の値 (実際: %s)" % str(odd),
	)
	var even: Dictionary = ScenebenchScript.summarize([4.0, 1.0, 10.0, 2.0])
	_check(
		even["median"] == 3.0 and even["min"] == 1.0 and even["max"] == 10.0 and even["avg"] == 4.25,
		"scenebench の集計: 偶数個は真ん中 2 つの平均 (実際: %s)" % str(even),
	)


## 1 本の毛メッシュが細い曲がった形状 (複数頂点・横と高さのカーブあり) であるか
func _check_hair_mesh_shape() -> void:
	var mesh: ArrayMesh = HairFieldScript.build_hair_mesh()
	_check(mesh.get_surface_count() == 1, "毛メッシュに 1 サーフェスある")
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	_check(vertices.size() == 5, "毛メッシュの頂点数が 5 (実際: %d)" % vertices.size())
	_check(indices.size() == 9, "毛メッシュのインデックス数が 9 = 3 三角形 (実際: %d)" % indices.size())
	var max_x: float = 0.0
	var max_y: float = 0.0
	var max_z: float = 0.0
	for vertex: Vector3 in vertices:
		max_x = maxf(max_x, absf(vertex.x))
		max_y = maxf(max_y, vertex.y)
		max_z = maxf(max_z, vertex.z)
	_check(
		max_x > 0.005 and max_y > 0.003 and max_z > 0.03,
		"毛メッシュが長さ・曲がり・浮きを持つ (x=%.4f y=%.4f z=%.4f)" % [max_x, max_y, max_z]
	)
	# 根元と中ほどの断面の幅ベクトルが同じ向きを向き、根元でリボンがねじれないこと
	_check(
		(vertices[1] - vertices[0]).dot(vertices[3] - vertices[2]) > 0.0,
		"毛メッシュの隣接断面の幅方向が一貫しねじれが無い"
	)
	var mesh_aabb: AABB = HairFieldScript.compute_mesh_aabb(mesh)
	_check(
		mesh_aabb.size.z > 0.03
		and HairFieldScript.compute_mesh_aabb(null) == AABB()
		and HairFieldScript.compute_mesh_aabb(ArrayMesh.new()) == AABB(),
		"compute_mesh_aabb が頂点配列から非空の AABB を計算し null と 0 サーフェスで空 AABB を返す"
	)
	_check(
		HairFieldScript.compute_aabb_min_transformed_y(
			Basis.from_euler(Vector3(0.14, 0.0, 0.0)), mesh_aabb
		)
		< 0.0,
		"下向きピッチ 0.14 rad で compute_aabb_min_transformed_y が負の下界を返す"
	)


## 毛の色に白・黒・三毛の 3 系統が含まれるか
func _check_hair_color_variety() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 42
	var counts: Dictionary = {
		HairFieldScript.HairColorGroup.WHITE: 0,
		HairFieldScript.HairColorGroup.BLACK: 0,
		HairFieldScript.HairColorGroup.CALICO: 0,
	}
	for _i: int in range(300):
		var group: int = HairFieldScript.classify_hair_color(HairFieldScript.pick_hair_color(rng))
		counts[group] = int(counts[group]) + 1
	_check(
		int(counts[HairFieldScript.HairColorGroup.WHITE]) > 40
		and int(counts[HairFieldScript.HairColorGroup.BLACK]) > 40
		and int(counts[HairFieldScript.HairColorGroup.CALICO]) > 40,
		"300 サンプルに白・黒・三毛が混在する (実際: %s)" % [str(counts)]
	)


## HairField の配置・再配置・公開照会・swap-remove (移動先スロット検証含む)・異常系
func _check_hair_field_populate_and_remove() -> void:
	# 表面未登録 + 正の本数の分岐
	var empty_field: Node3D = HairFieldScript.new()
	_check(empty_field.populate(10) == 0, "表面未登録で正の本数を渡しても配置数 0")
	empty_field.free()

	# 重みがすべて 0 の表面のみ登録された場合の actual_total <= 0 の分岐
	var zero_weight_field: Node3D = HairFieldScript.new()
	zero_weight_field.add_surface("floor", Vector3(-1.0, 0.0, -1.0), Vector3(1.0, 0.0, 1.0), 0.0)
	_check(zero_weight_field.populate(10) == 0, "全表面の重みが 0 なら配置数 0")
	zero_weight_field.free()

	var field: Node3D = HairFieldScript.new()
	field.add_surface("floor", Vector3(-1.0, 0.0, -1.0), Vector3(1.0, 0.0, 1.0), 0.7)
	field.add_surface("sofa", Vector3(-0.5, 0.4, -0.5), Vector3(0.5, 0.4, 0.5), 0.3)

	# 0 本の異常・境界系
	_check(field.populate(0) == 0, "0 本指定では配置数 0")
	_check(not field.remove_hair(0), "0 本の状態で remove_hair(0) は false")

	# 10 本配置 (floor 7 本: ID 0..6, sofa 3 本: ID 7..9)
	_check(field.populate(10, 12345) == 10 and field.get_remaining_count() == 10, "10 本配置できる")
	# 配置した毛が Identity ではなく実座標と非透明色を持ち、全頂点が表面高さ以上に収まること
	var hair_vertices: PackedVector3Array = HairFieldScript.build_hair_mesh().surface_get_arrays(0)[
		Mesh.ARRAY_VERTEX
	]
	var all_above_surface: bool = true
	var all_opaque_color: bool = true
	for hair_id: int in range(10):
		var surface_y: float = 0.0 if hair_id < 7 else 0.4
		var xform: Transform3D = field.get_hair_transform(hair_id)
		if field.get_hair_color(hair_id).a < 0.99:
			all_opaque_color = false
		for vertex: Vector3 in hair_vertices:
			if (xform * vertex).y < surface_y:
				all_above_surface = false
	_check(all_above_surface, "配置したすべての毛の全頂点が表面 Y 以上に収まる")
	_check(all_opaque_color, "配置したすべての毛が非透明色を持つ (headless でも色保持)")
	_check(
		field.get_surface_remaining_count(0) == 7
		and field.get_surface_remaining_count(1) == 3,
		"表面ごとの残り本数が [7, 3]"
	)
	_check(
		field.get_surface_visible_instance_count(0) == 7
		and field.get_surface_visible_instance_count(1) == 3,
		"表面ごとに MultiMesh の visible_instance_count が [7, 3]"
	)

	# 範囲外の表面番号と存在しない毛 ID の照会
	_check(
		field.get_surface_remaining_count(-1) == 0
		and field.get_surface_remaining_count(2) == 0
		and field.get_surface_visible_instance_count(-1) == 0
		and field.get_surface_visible_instance_count(2) == 0,
		"範囲外の表面番号 (-1 / 上限+1) に対する照会は 0"
	)
	_check(
		field.get_hair_transform(-1) == Transform3D.IDENTITY
		and field.get_hair_transform(99) == Transform3D.IDENTITY
		and field.get_hair_color(-1) == HairFieldScript.INVALID_COLOR
		and field.get_hair_color(99) == HairFieldScript.INVALID_COLOR
		and field.get_hair_slot(-1) == HairFieldScript.INVALID_SLOT
		and field.get_hair_slot(10) == HairFieldScript.INVALID_SLOT
		and field.get_hair_id_at_slot(0, 6) == 6
		and field.get_hair_id_at_slot(-1, 0) == HairFieldScript.INVALID_SLOT
		and field.get_hair_id_at_slot(2, 0) == HairFieldScript.INVALID_SLOT
		and field.get_hair_id_at_slot(0, -1) == HairFieldScript.INVALID_SLOT
		and field.get_hair_id_at_slot(0, 7) == HairFieldScript.INVALID_SLOT,
		"存在しない ID・スロットの照会が既定値 / INVALID_SLOT を返す"
	)
	# get_multimesh_slot_transform / color の範囲外 4 境界 (surface < 0 / >= 上限, slot < 0 / >= visible)
	_check(
		field.get_multimesh_slot_transform(-1, 0) == Transform3D.IDENTITY
		and field.get_multimesh_slot_transform(2, 0) == Transform3D.IDENTITY
		and field.get_multimesh_slot_transform(0, -1) == Transform3D.IDENTITY
		and field.get_multimesh_slot_transform(0, 7) == Transform3D.IDENTITY
		and field.get_multimesh_slot_color(-1, 0) == HairFieldScript.INVALID_COLOR
		and field.get_multimesh_slot_color(2, 0) == HairFieldScript.INVALID_COLOR
		and field.get_multimesh_slot_color(0, -1) == HairFieldScript.INVALID_COLOR
		and field.get_multimesh_slot_color(0, 7) == HairFieldScript.INVALID_COLOR,
		"get_multimesh_slot_transform / color の範囲外 4 境界が既定値を返す"
	)

	# swap される末尾の毛 (ID 6) と次末尾 (ID 5) の位置・色を控え、中間の ID 2 を削除する
	var id6_xform_before: Transform3D = field.get_hair_transform(6)
	var id6_color_before: Color = field.get_hair_color(6)
	var id5_xform_before: Transform3D = field.get_hair_transform(5)
	var id5_color_before: Color = field.get_hair_color(5)
	_check(field.remove_hair(2), "中間の毛 ID 2 を 1 本削除できる")
	_check(field.get_remaining_count() == 9, "1 本削除後に残り本数が 9")
	_check(
		not field.has_hair(2) and field.get_hair_slot(2) == HairFieldScript.INVALID_SLOT,
		"削除した ID 2 は存在しない"
	)
	_check(
		field.get_hair_transform(2) == Transform3D.IDENTITY
		and field.get_hair_color(2) == HairFieldScript.INVALID_COLOR,
		"削除済み ID 2 の Transform/Color 照会は Identity / INVALID_COLOR"
	)
	_check(
		field.get_surface_remaining_count(0) == 6
		and field.get_surface_remaining_count(1) == 3,
		"削除した表面の残り本数だけが 1 減る"
	)
	_check(
		field.get_surface_visible_instance_count(0) == 6
		and field.get_surface_visible_instance_count(1) == 3,
		"削除した表面の visible_instance_count だけが 1 減る"
	)
	# _id_to_slot[last_id] = slot の更新が壊れていれば ID 6 が旧スロット 6 (非可視範囲) のままになり落ちる
	_check(
		field.get_hair_slot(6) == 2
		and field.get_hair_slot(6) < field.get_surface_visible_instance_count(0),
		"末尾から移動した ID 6 のスロットが 2 (可視範囲内) に更新される"
	)
	_check(
		field.has_hair(6)
		and field.get_hair_transform(6).is_equal_approx(id6_xform_before)
		and field.get_hair_color(6).is_equal_approx(id6_color_before),
		"swap-remove 後も移動した毛 (ID 6) の Transform と色が保たれる"
	)

	# 移動した ID 6 を続けて削除しても ID 5 がスロット 2 に移り Transform/色が保たれること
	_check(field.remove_hair(6), "移動後の ID 6 を続けて削除できる")
	_check(
		field.get_hair_slot(5) == 2
		and field.get_hair_transform(5).is_equal_approx(id5_xform_before)
		and field.get_hair_color(5).is_equal_approx(id5_color_before),
		"ID 6 削除後に ID 5 がスロット 2 へ移り Transform と色が保たれる"
	)

	# 重複削除・範囲外 ID の異常系
	_check(not field.remove_hair(2), "同じ ID の重複削除は false")
	_check(not field.remove_hair(-1), "負の ID の削除は false")
	_check(not field.remove_hair(10), "上限 + 1 (ID 10) の削除は false")
	_check(field.get_remaining_count() == 8, "失敗した削除で本数が変わらない")

	# 毛が残っている状態から再 populate して古い MultiMeshInstance3D が解放・置換されること
	_check(
		field.populate(4, 999) == 4
		and field.get_remaining_count() == 4
		and field.get_child_count() == 2,
		"再 populate で子ノードが増えず 2 表面・4 本に置き換わる"
	)

	# 残り全本数を削除して 0 本にする境界確認
	var removed_rest: int = 0
	for hair_id: int in range(4):
		if field.remove_hair(hair_id):
			removed_rest += 1
	_check(removed_rest == 4 and field.get_remaining_count() == 0, "残り 4 本を全削除して 0 本")
	_check(
		field.get_surface_visible_instance_count(0) == 0
		and field.get_surface_visible_instance_count(1) == 0,
		"全削除後に両表面の visible_instance_count が 0"
	)
	_check(not field.remove_hair(0), "全削除後の再削除は false")

	field.free()


## hairbench.gd の純粋関数 (入力解析・輝度判定・成否判定・JSON 書出) の正常系・異常系・境界値
func _check_hairbench_helpers() -> void:
	# parse_counts: 空文字・空白・無効のみ・0/負数・混在・正常
	_check(
		HairbenchScript.parse_counts("") == HairbenchScript.DEFAULT_COUNTS,
		"parse_counts 空文字は既定の本数配列を返す"
	)
	_check(
		HairbenchScript.parse_counts("   ") == HairbenchScript.DEFAULT_COUNTS,
		"parse_counts 空白のみは既定の本数配列を返す"
	)
	_check(
		HairbenchScript.parse_counts("abc,0,-5, ") == HairbenchScript.DEFAULT_COUNTS,
		"parse_counts 全トークン無効 (非数値/0/負数) は既定値に戻る"
	)
	var mixed_counts: Array[int] = HairbenchScript.parse_counts(" 500, bad, 0, -1, 2500 ")
	_check(
		mixed_counts == [500, 2500],
		"parse_counts 有効・無効混在時は正の整数のみ抽出する (実際: %s)" % [str(mixed_counts)]
	)

	# env_or_default
	_check(
		HairbenchScript.env_or_default("", "fallback") == "fallback"
		and HairbenchScript.env_or_default("   ", "fallback") == "fallback"
		and HairbenchScript.env_or_default(" value ", "fallback") == "value",
		"env_or_default が空・空白で fallback、値ありでトリム済みを返す"
	)

	# sample_luminance: 真っ黒・真っ白・単色・明暗あり・空画像
	var black_img: Image = Image.create(64, 36, false, Image.FORMAT_RGB8)
	black_img.fill(Color(0.0, 0.0, 0.0))
	_check(
		not bool(HairbenchScript.sample_luminance(black_img)["not_blank"]),
		"sample_luminance は真っ黒画像を not_blank=false と判定する"
	)

	var white_img: Image = Image.create(64, 36, false, Image.FORMAT_RGB8)
	white_img.fill(Color(1.0, 1.0, 1.0))
	_check(
		not bool(HairbenchScript.sample_luminance(white_img)["not_blank"]),
		"sample_luminance は真っ白画像を not_blank=false と判定する"
	)

	var flat_img: Image = Image.create(64, 36, false, Image.FORMAT_RGB8)
	flat_img.fill(Color(0.5, 0.5, 0.5))
	_check(
		not bool(HairbenchScript.sample_luminance(flat_img)["not_blank"]),
		"sample_luminance は単色中間グレー画像をコントラスト不足で not_blank=false と判定する"
	)

	# コントラストはあるのに平均輝度だけが下限 0.02 以下の画像 (576 サンプル中 1 点だけ白: mean ≈ 0.0017)
	var mostly_black_img: Image = Image.create(64, 36, false, Image.FORMAT_RGB8)
	mostly_black_img.fill(Color(0.0, 0.0, 0.0))
	mostly_black_img.fill_rect(Rect2i(0, 0, 2, 2), Color(1.0, 1.0, 1.0))
	_check(
		not bool(HairbenchScript.sample_luminance(mostly_black_img)["not_blank"]),
		"sample_luminance はコントラスト有でも平均輝度 <= 0.02 で not_blank=false"
	)

	# コントラストはあるのに平均輝度だけが上限 0.98 以上の画像 (576 サンプル中 1 点だけ黒: mean ≈ 0.998)
	var mostly_white_img: Image = Image.create(64, 36, false, Image.FORMAT_RGB8)
	mostly_white_img.fill(Color(1.0, 1.0, 1.0))
	mostly_white_img.fill_rect(Rect2i(0, 0, 2, 2), Color(0.0, 0.0, 0.0))
	_check(
		not bool(HairbenchScript.sample_luminance(mostly_white_img)["not_blank"]),
		"sample_luminance はコントラスト有でも平均輝度 >= 0.98 で not_blank=false"
	)

	var varied_img: Image = Image.create(64, 36, false, Image.FORMAT_RGB8)
	varied_img.fill(Color(0.2, 0.2, 0.2))
	varied_img.fill_rect(Rect2i(32, 0, 32, 36), Color(0.8, 0.8, 0.8))
	_check(
		bool(HairbenchScript.sample_luminance(varied_img)["not_blank"]),
		"sample_luminance は明暗差のある画像を not_blank=true と判定する"
	)

	_check(
		not bool(HairbenchScript.sample_luminance(Image.new())["not_blank"])
		and not bool(HairbenchScript.sample_luminance(null)["not_blank"]),
		"sample_luminance は 0x0 画像と null を not_blank=false と判定する"
	)

	# select_measure_frame_target: 閾値ちょうど・直前・2 フレーム目以降
	_check(
		HairbenchScript.select_measure_frame_target(
			0, HairbenchScript.SLOW_FRAME_THRESHOLD_MS, HairbenchScript.MEASURE_FRAMES_MAX
		)
		== HairbenchScript.MEASURE_FRAMES_SLOW,
		"初回フレームが閾値ちょうどで計測フレーム数を MEASURE_FRAMES_SLOW に減らす"
	)
	_check(
		HairbenchScript.select_measure_frame_target(
			0, HairbenchScript.SLOW_FRAME_THRESHOLD_MS - 0.01, HairbenchScript.MEASURE_FRAMES_MAX
		)
		== HairbenchScript.MEASURE_FRAMES_MAX,
		"初回フレームが閾値未満なら計測フレーム数を維持する"
	)
	_check(
		HairbenchScript.select_measure_frame_target(
			1, HairbenchScript.SLOW_FRAME_THRESHOLD_MS + 500.0, HairbenchScript.MEASURE_FRAMES_MAX
		)
		== HairbenchScript.MEASURE_FRAMES_MAX,
		"2 フレーム目以降が遅くても計測フレーム数は減らさない"
	)

	# evaluate_single_remove: 4 条件それぞれの単一偽
	_check(
		HairbenchScript.evaluate_single_remove(true, 10, 9, false, true),
		"evaluate_single_remove は全条件成立で true"
	)
	_check(
		not HairbenchScript.evaluate_single_remove(false, 10, 9, false, true),
		"evaluate_single_remove は removed=false で false"
	)
	_check(
		not HairbenchScript.evaluate_single_remove(true, 10, 10, false, true),
		"evaluate_single_remove は本数が減っていなければ false"
	)
	_check(
		not HairbenchScript.evaluate_single_remove(true, 10, 9, true, true),
		"evaluate_single_remove は対象 ID が残っていれば false"
	)
	_check(
		not HairbenchScript.evaluate_single_remove(true, 10, 9, false, false),
		"evaluate_single_remove は multimesh_synced=false で false"
	)

	# evaluate_rendered: 4 条件それぞれの単一偽
	_check(
		HairbenchScript.evaluate_rendered(100, 100, OK, true, true),
		"evaluate_rendered は全条件成立で true"
	)
	_check(
		not HairbenchScript.evaluate_rendered(99, 100, OK, true, true),
		"evaluate_rendered は配置本数不一致で false"
	)
	_check(
		not HairbenchScript.evaluate_rendered(100, 100, ERR_CANT_OPEN, true, true),
		"evaluate_rendered は PNG 保存失敗で false"
	)
	_check(
		not HairbenchScript.evaluate_rendered(100, 100, OK, false, true),
		"evaluate_rendered は not_blank=false で false"
	)
	_check(
		not HairbenchScript.evaluate_rendered(100, 100, OK, true, false),
		"evaluate_rendered は single_remove_ok=false で false"
	)

	# should_abort_step: JSON 書き込み失敗と描画失敗それぞれの独立判定
	_check(
		not HairbenchScript.should_abort_step(true, true),
		"should_abort_step は書き込み成功・描画成功なら続行 (false)"
	)
	_check(
		HairbenchScript.should_abort_step(false, true),
		"should_abort_step は描画成功でも JSON 書き込み失敗だけで打ち切る (true)"
	)
	_check(
		HairbenchScript.should_abort_step(true, false),
		"should_abort_step は書き込み成功でも描画失敗だけで打ち切る (true)"
	)
	_check(
		HairbenchScript.should_abort_step(false, false),
		"should_abort_step は両方失敗で打ち切る (true)"
	)

	# write_json: 空パス失敗と正常書き込み
	_check(not HairbenchScript.write_json("", {"ok": true}), "write_json は空パスで false")
	var temp_json_path: String = "tmp/selfcheck-hairbench-write-test.json"
	_check(
		HairbenchScript.write_json(temp_json_path, {"count": 42}),
		"write_json は有効パスへ書き込める"
	)
	_check(
		FileAccess.get_file_as_string(temp_json_path).contains("\"count\": 42"),
		"write_json の出力に JSON の内容が含まれる"
	)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("res://" + temp_json_path))


## BGM と効果音のバスが別々に定義され、効果音が BGM より大きい音量設定になっているか
func _check_audio_bus_layout() -> void:
	var bgm_bus_index: int = AudioServer.get_bus_index(AudioCatalog.BUS_BGM)
	var sfx_bus_index: int = AudioServer.get_bus_index(AudioCatalog.BUS_SFX)
	_check(bgm_bus_index >= 0, "AudioServer に BGM バスがある (index: %d)" % bgm_bus_index)
	_check(sfx_bus_index >= 0, "AudioServer に SFX バスがある (index: %d)" % sfx_bus_index)
	_check(bgm_bus_index != sfx_bus_index, "BGM バスと SFX バスが別々である")
	if bgm_bus_index >= 0 and sfx_bus_index >= 0:
		var bgm_db: float = AudioServer.get_bus_volume_db(bgm_bus_index)
		var sfx_db: float = AudioServer.get_bus_volume_db(sfx_bus_index)
		_check(
			bgm_db < sfx_db,
			"効果音を目立たせるため BGM 音量 (%s dB) < SFX 音量 (%s dB)" % [bgm_db, sfx_db],
		)


## 場面名・出来事名から音声パスを選ぶ純粋関数の正常系・異常系・境界値・実ファイル存在確認
func _check_audio_catalog() -> void:
	var expected_bgm: Dictionary = {
		"title": "res://assets/audio/bgm_title.ogg",
		"mansion": "res://assets/audio/bgm_mansion.ogg",
	}
	var expected_sfx: Dictionary = {
		"pluck_hair": "res://assets/audio/sfx_pluck_hair.ogg",
		"earn_money": "res://assets/audio/sfx_earn_money.ogg",
		"buy_tool": "res://assets/audio/sfx_buy_tool.ogg",
		"button": "res://assets/audio/sfx_button.ogg",
	}
	_check(
		AudioCatalog.all_bgm_names().size() == expected_bgm.size(),
		"BGM 登録数が %d 件 (実際: %d)" % [expected_bgm.size(), AudioCatalog.all_bgm_names().size()],
	)
	_check(
		AudioCatalog.all_sfx_names().size() == expected_sfx.size(),
		"効果音登録数が %d 件 (実際: %d)" % [expected_sfx.size(), AudioCatalog.all_sfx_names().size()],
	)
	for scene_name: String in expected_bgm.keys():
		var expected_path: String = String(expected_bgm[scene_name])
		var actual_path: String = AudioCatalog.resolve_bgm_path(scene_name)
		_check(
			actual_path == expected_path,
			"BGM '%s' のパスが %s (実際: %s)" % [scene_name, expected_path, actual_path],
		)
		_check(
			ResourceLoader.exists(actual_path) and load(actual_path) is AudioStream,
			"BGM '%s' の素材 %s が AudioStream として読み込める" % [scene_name, actual_path],
		)
	for event_name: String in expected_sfx.keys():
		var expected_path: String = String(expected_sfx[event_name])
		var actual_path: String = AudioCatalog.resolve_sfx_path(event_name)
		_check(
			actual_path == expected_path,
			"効果音 '%s' のパスが %s (実際: %s)" % [event_name, expected_path, actual_path],
		)
		_check(
			ResourceLoader.exists(actual_path) and load(actual_path) is AudioStream,
			"効果音 '%s' の素材 %s が AudioStream として読み込める" % [event_name, actual_path],
		)
	for bad_bgm: String in ["", "unknown", "TITLE", "title ", "button", "pluck_hair"]:
		_check(
			AudioCatalog.resolve_bgm_path(bad_bgm).is_empty(),
			"未登録の BGM 名 '%s' は空文字を返す" % bad_bgm,
		)
	for bad_sfx: String in ["", "unknown", "BUTTON", "pluck_hair ", "title", "mansion"]:
		_check(
			AudioCatalog.resolve_sfx_path(bad_sfx).is_empty(),
			"未登録の効果音名 '%s' は空文字を返す" % bad_sfx,
		)


## ConfigFile による設定の保存・読み戻し (正常系 4 パターン + 異常系・境界値)
func _check_audio_settings_persistence() -> void:
	var test_path: String = ProjectSettings.globalize_path("res://tmp/selfcheck-audio-settings.cfg")
	remove_file_if_exists(test_path)

	var defaults: RefCounted = AudioSettings.new()
	_check(defaults.bgm_enabled and defaults.sfx_enabled, "音声設定の初期値は BGM・効果音ともオン")

	for pair: Array in [[false, true], [true, false], [false, false], [true, true]]:
		var expected_bgm: bool = bool(pair[0])
		var expected_sfx: bool = bool(pair[1])
		_check(
			AudioSettings.new(expected_bgm, expected_sfx).save_to_path(test_path) == OK,
			"設定 (%s, %s) の保存が OK" % [expected_bgm, expected_sfx],
		)
		var reader: RefCounted = AudioSettings.new(not expected_bgm, not expected_sfx)
		_check(
			reader.load_from_path(test_path) == OK,
			"設定 (%s, %s) の読み込みが OK" % [expected_bgm, expected_sfx],
		)
		_check(
			reader.bgm_enabled == expected_bgm and reader.sfx_enabled == expected_sfx,
			"保存した (%s, %s) を読み戻せる (実際: %s, %s)"
			% [expected_bgm, expected_sfx, reader.bgm_enabled, reader.sfx_enabled],
		)

	var empty_writer: RefCounted = AudioSettings.new(false, false)
	_check(
		empty_writer.save_to_path("") == ERR_INVALID_PARAMETER,
		"空パスへの保存は ERR_INVALID_PARAMETER を返す",
	)
	_check(
		empty_writer.load_from_path("") == ERR_INVALID_PARAMETER,
		"空パスからの読み込みは ERR_INVALID_PARAMETER を返す",
	)
	_check(
		empty_writer.bgm_enabled and empty_writer.sfx_enabled,
		"空パス読み込み失敗時は既定値 (オン, オン) に戻る",
	)

	remove_file_if_exists(test_path)
	var missing_reader: RefCounted = AudioSettings.new(false, false)
	_check(missing_reader.load_from_path(test_path) != OK, "存在しない設定ファイルの読み込みはエラーを返す")
	_check(
		missing_reader.bgm_enabled and missing_reader.sfx_enabled,
		"存在しない設定ファイルの読み込み時は既定値 (オン, オン) に戻る",
	)

	_write_raw_text(test_path, "[other]\nvalue=1\n")
	var other_section_reader: RefCounted = AudioSettings.new(false, false)
	_check(
		other_section_reader.load_from_path(test_path) == OK,
		"audio セクションが無い設定ファイルはエラーなく読み込める",
	)
	_check(
		other_section_reader.bgm_enabled and other_section_reader.sfx_enabled,
		"audio セクションが無い設定ファイルは既定値 (オン, オン) になる",
	)

	_write_raw_text(test_path, "[audio]\nbgm_enabled=false\nsfx_enabled=\"bad\"\n")
	var partial_type_reader: RefCounted = AudioSettings.new(true, false)
	_check(partial_type_reader.load_from_path(test_path) == OK, "sfx 不正型混在ファイルは安全に読める")
	_check(
		(not partial_type_reader.bgm_enabled) and partial_type_reader.sfx_enabled,
		"正常な bgm_enabled=false は保持し、不正型の sfx_enabled は既定値 true になる",
	)

	_write_raw_text(test_path, "[audio]\nbgm_enabled=\"bad\"\nsfx_enabled=false\n")
	var bgm_type_reader: RefCounted = AudioSettings.new(false, true)
	_check(bgm_type_reader.load_from_path(test_path) == OK, "bgm 不正型混在ファイルは安全に読める")
	_check(
		bgm_type_reader.bgm_enabled and (not bgm_type_reader.sfx_enabled),
		"不正型の bgm_enabled は既定値 true になり、正常な sfx_enabled=false は保持する",
	)

	_write_raw_text(test_path, "[audio]\nsfx_enabled=false\n")
	var missing_key_reader: RefCounted = AudioSettings.new(false, true)
	_check(missing_key_reader.load_from_path(test_path) == OK, "片方欠落ファイルは安全に読める")
	_check(
		missing_key_reader.bgm_enabled and (not missing_key_reader.sfx_enabled),
		"欠落した bgm_enabled は既定値 true、存在する sfx_enabled=false は保持する",
	)

	remove_file_if_exists(test_path)


## AudioSettings.apply_to_audio_server が BGM・SFX バスを個別に消音できるか
func _check_audio_settings_bus_mute() -> void:
	var bgm_bus_index: int = AudioServer.get_bus_index(AudioCatalog.BUS_BGM)
	var sfx_bus_index: int = AudioServer.get_bus_index(AudioCatalog.BUS_SFX)
	if bgm_bus_index < 0 or sfx_bus_index < 0:
		return
	AudioSettings.apply_to_audio_server(false, true)
	_check(
		AudioServer.is_bus_mute(bgm_bus_index) and not AudioServer.is_bus_mute(sfx_bus_index),
		"BGM オフ・効果音オンで BGM バスだけ消音になる",
	)
	AudioSettings.apply_to_audio_server(true, false)
	_check(
		(not AudioServer.is_bus_mute(bgm_bus_index)) and AudioServer.is_bus_mute(sfx_bus_index),
		"BGM オン・効果音オフで SFX バスだけ消音になる",
	)
	AudioSettings.apply_to_audio_server(false, false)
	_check(
		AudioServer.is_bus_mute(bgm_bus_index) and AudioServer.is_bus_mute(sfx_bus_index),
		"両方オフで BGM・SFX バスとも消音になる",
	)
	AudioSettings.apply_to_audio_server(true, true)
	_check(
		(not AudioServer.is_bus_mute(bgm_bus_index))
		and (not AudioServer.is_bus_mute(sfx_bus_index)),
		"両方オンで BGM・SFX バスとも消音解除になる",
	)


## AudioManager の null tree ガードと _ready() 前の未準備ガードを確認する
func _check_audio_manager_guards() -> void:
	_check(AudioManagerScript.resolve(null) == null, "AudioManager.resolve(null) は null を返す")
	_check(
		not AudioManagerScript.play_button_sfx(null),
		"AudioManager.play_button_sfx(null) は false を返す",
	)
	var unready_manager: AudioManagerScript = AudioManagerScript.new()
	_check(
		not unready_manager.play_bgm(AudioCatalog.BGM_TITLE),
		"tree 追加前 (_bgm_player 未準備) の play_bgm は false を返す",
	)
	_check(
		not unready_manager.play_sfx(AudioCatalog.SFX_BUTTON),
		"tree 追加前 (_sfx_players 未準備) の play_sfx は false を返す",
	)
	unready_manager.free()


## scripts/dev/movie.gd のコマンドライン引数解釈と録画フレーム数計算の境界値を確認する
func _check_movie_frame_calculations() -> void:
	var valid_options: Dictionary = MovieScript.parse_movie_options(
		PackedStringArray(["--frames=150", "--fps=30"])
	)
	_check(
		int(valid_options.get("total_frames", -1)) == 150
		and int(valid_options.get("fps", -1)) == 30,
		"--frames=150 --fps=30 が正しく解釈される",
	)
	for bad_option_args: PackedStringArray in [
		PackedStringArray(["--fps=30"]),
		PackedStringArray(["--frames=", "--fps=30"]),
		PackedStringArray(["--frames=0", "--fps=30"]),
		PackedStringArray(["--frames=-5", "--fps=30"]),
		PackedStringArray(["--frames=abc", "--fps=30"]),
		PackedStringArray(["--frames=150"]),
		PackedStringArray(["--frames=150", "--fps="]),
		PackedStringArray(["--frames=150", "--fps=0"]),
		PackedStringArray(["--frames=150", "--fps=-1"]),
		PackedStringArray(["--frames=150", "--fps=abc"]),
		PackedStringArray([]),
		PackedStringArray(["--other=10"]),
		PackedStringArray(["--frames=0", "--fps=0"]),
	]:
		_check(
			MovieScript.parse_movie_options(bad_option_args).is_empty(),
			"不正・欠落オプション %s は空辞書を返す" % str(bad_option_args),
		)
	_check(MovieScript.calc_release_frames(30) == 10, "30 fps の解放待ちフレーム数が 10")
	_check(MovieScript.calc_release_frames(60) == 17, "60 fps の解放待ちフレーム数が 17")
	_check(MovieScript.calc_release_frames(0) == 3, "0 fps 下限の解放待ちフレーム数が 3")
	_check(MovieScript.calc_min_total_frames(10) == 13, "release=10 の最小必要フレーム数が 13")
	_check(MovieScript.calc_record_frames(1, 10) == 0, "total=1 (予算不足) は 0 を返す")
	_check(MovieScript.calc_record_frames(12, 10) == 0, "total=12 (境界未満) は 0 を返す")
	_check(MovieScript.calc_record_frames(13, 10) == 1, "total=13 (境界) は 1 を返す")
	_check(MovieScript.calc_record_frames(14, 10) == 2, "total=14 (境界 + 1) は 2 を返す")
	_check(MovieScript.calc_record_frames(150, 10) == 138, "total=150, release=10 は 138 を返す")


## 異常系テスト用に任意の文字列をファイルへ書き出す
func _write_raw_text(path: String, content: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(content)
		file.close()

extends "res://scripts/dev/headless_check.gd"
## 純粋なロジックとプロジェクト設定の検証 (headless)。ゲームのルールの計算を足したら、ここに検証を足す。
## 実行方法は AGENTS.md「検証方法」を参照。

## プロジェクト設定のメインシーンに入っているべきパス
const MAIN_SCENE_PATH: String = "res://scenes/main.tscn"
## 毛の描画の試作シーンのパス
const HAIR_PROTOTYPE_SCENE_PATH: String = "res://scenes/hair_prototype.tscn"
## プロジェクト設定の名前に入っているべき値 (ゲームの題名)
const PROJECT_NAME: String = "Oh My Fur!"
## プロジェクト設定のレンダラ (ADR 0002 で Forward+ に決定)
const RENDERING_METHOD: String = "forward_plus"
## 毛の描画ノードのスクリプト
const HairFieldScript := preload("res://scripts/hair_field.gd")
## ベンチマークスクリプト (純粋関数の単体検証用)
const HairbenchScript := preload("res://scripts/dev/hairbench.gd")


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
	_finish()


## プロジェクト設定の名前・メインシーン・レンダラが想定どおりか
func _check_project_settings() -> void:
	var main_scene: String = ProjectSettings.get_setting("application/run/main_scene", "")
	_check(
		main_scene == MAIN_SCENE_PATH,
		"application/run/main_scene が %s (実際: %s)" % [MAIN_SCENE_PATH, main_scene]
	)
	var project_name: String = ProjectSettings.get_setting("application/config/name", "")
	_check(
		project_name == PROJECT_NAME,
		"application/config/name が %s (実際: %s)" % [PROJECT_NAME, project_name]
	)
	var rendering_method: String = ProjectSettings.get_setting(
		"rendering/renderer/rendering_method", ""
	)
	_check(
		rendering_method == RENDERING_METHOD,
		"rendering/renderer/rendering_method が %s (実際: %s)"
		% [RENDERING_METHOD, rendering_method]
	)


## メインシーンがロードでき、PackedScene が返るか
func _check_main_scene_loads() -> void:
	_check(
		load(MAIN_SCENE_PATH) is PackedScene,
		"%s が PackedScene としてロードできる" % MAIN_SCENE_PATH
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

	var frac: PackedInt32Array = HairFieldScript.allocate_counts(7, weights)
	_check(
		frac.size() == 2 and frac[0] + frac[1] == 7 and frac[0] == 6 and frac[1] == 1,
		"端数のある 7 本の合計が 7 で [6, 1] (実際: %s)" % [str(frac)]
	)

	var one: PackedInt32Array = HairFieldScript.allocate_counts(1, weights)
	_check(
		one.size() == 2 and one[0] == 1 and one[1] == 0,
		"1 本の時は重みが大きい面に配分され合計 1 (実際: %s)" % [str(one)]
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


## 1 本の毛メッシュが細い曲がった形状 (複数頂点・横と高さのカーブあり) であるか
func _check_hair_mesh_shape() -> void:
	var mesh: ArrayMesh = HairFieldScript.build_hair_mesh()
	_check(mesh.get_surface_count() == 1, "毛メッシュに 1 サーフェスある")
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	_check(vertices.size() == 7, "毛メッシュの頂点数が 7 (実際: %d)" % vertices.size())
	_check(indices.size() == 15, "毛メッシュのインデックス数が 15 = 5 三角形 (実際: %d)" % indices.size())
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
	var placed: int = field.populate(10, 12345)
	_check(placed == 10 and field.get_remaining_count() == 10, "10 本配置できる")
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
		and field.get_hair_color(-1) == Color(0.0, 0.0, 0.0, 0.0)
		and field.get_hair_color(99) == Color(0.0, 0.0, 0.0, 0.0),
		"存在しない ID の Transform/Color 照会は Identity / 透明黒"
	)

	# swap される末尾の毛 (ID 6) と次末尾 (ID 5) の位置・色を控え、中間の ID 2 を削除する
	var id6_xform_before: Transform3D = field.get_hair_transform(6)
	var id6_color_before: Color = field.get_hair_color(6)
	var id5_xform_before: Transform3D = field.get_hair_transform(5)
	var id5_color_before: Color = field.get_hair_color(5)
	_check(field.remove_hair(2), "中間の毛 ID 2 を 1 本削除できる")
	_check(field.get_remaining_count() == 9, "1 本削除後に残り本数が 9")
	_check(not field.has_hair(2) and field.get_hair_slot(2) == -1, "削除した ID 2 は存在しない")
	_check(
		field.get_hair_transform(2) == Transform3D.IDENTITY
		and field.get_hair_color(2) == Color(0.0, 0.0, 0.0, 0.0),
		"削除済み ID 2 の Transform/Color 照会は Identity / 透明黒"
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
	var repopulated: int = field.populate(4, 999)
	_check(
		repopulated == 4
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

	# evaluate_single_remove: 3 条件それぞれの単一偽
	_check(
		HairbenchScript.evaluate_single_remove(true, 10, 9, false),
		"evaluate_single_remove は全条件成立で true"
	)
	_check(
		not HairbenchScript.evaluate_single_remove(false, 10, 9, false),
		"evaluate_single_remove は removed=false で false"
	)
	_check(
		not HairbenchScript.evaluate_single_remove(true, 10, 10, false),
		"evaluate_single_remove は本数が減っていなければ false"
	)
	_check(
		not HairbenchScript.evaluate_single_remove(true, 10, 9, true),
		"evaluate_single_remove は対象 ID が残っていれば false"
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

	# write_json: 空パス失敗と正常書き込み
	_check(not HairbenchScript.write_json("", {"ok": true}), "write_json は空パスで false")
	var temp_json_path: String = "tmp/selfcheck-hairbench-write-test.json"
	_check(
		HairbenchScript.write_json(temp_json_path, {"count": 42}),
		"write_json は有効パスへ書き込める"
	)
	var written_text: String = FileAccess.get_file_as_string(temp_json_path)
	_check(written_text.contains("\"count\": 42"), "write_json の出力に JSON の内容が含まれる")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("res://" + temp_json_path))

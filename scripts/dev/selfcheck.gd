extends "res://scripts/dev/headless_check.gd"
## 純粋なロジックとプロジェクト設定の検証 (headless)。ゲームのルールの計算を足したら、ここに検証を足す。
## 実行方法は AGENTS.md「検証方法」を参照。

## プロジェクト設定のメインシーンに入っているべきパス
const MAIN_SCENE_PATH: String = "res://scenes/main.tscn"
## 毛の描画の試作シーンのパス
const HAIR_PROTOTYPE_SCENE_PATH: String = "res://scenes/hair_prototype.tscn"
## プロジェクト設定の名前に入っているべき値 (ゲームの題名)
const PROJECT_NAME: String = "Oh My Fur!"
## 毛の描画ノードのスクリプト
const HairFieldScript := preload("res://scripts/hair_field.gd")


## 検証をすべて実行して終える
func _initialize() -> void:
	_check_project_settings()
	_check_main_scene_loads()
	_check_hair_prototype_loads()
	_check_hair_allocate_counts()
	_check_hair_mesh_shape()
	_check_hair_color_variety()
	_check_hair_field_populate_and_remove()
	_finish()


## プロジェクト設定の名前とメインシーンが想定どおりか
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


## 表面ごとの本数配分 (正常系・端数・境界値・異常系)
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

	var empty_weights: PackedInt32Array = HairFieldScript.allocate_counts(
		100, PackedFloat32Array()
	)
	_check(empty_weights.is_empty(), "重み配列が空なら空配列を返す")

	var zero_weights: PackedInt32Array = HairFieldScript.allocate_counts(
		100, PackedFloat32Array([0.0, 0.0])
	)
	_check(
		zero_weights.size() == 2 and zero_weights[0] == 0 and zero_weights[1] == 0,
		"重み合計が 0 なら [0, 0]"
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
	for v: Vector3 in vertices:
		max_x = maxf(max_x, absf(v.x))
		max_y = maxf(max_y, v.y)
		max_z = maxf(max_z, v.z)
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


## HairField の配置と 1 本削除 (swap-remove の整合性・境界値・異常系)
func _check_hair_field_populate_and_remove() -> void:
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
		field.get_surface_visible_instance_count(0) == 7
		and field.get_surface_visible_instance_count(1) == 3,
		"表面ごとに MultiMesh の visible_instance_count が [7, 3]"
	)

	# swap される末尾の毛 (ID 6) の位置と色を控え、中間の ID 2 を削除する
	var id6_xform_before: Transform3D = field.get_hair_transform(6)
	var id6_color_before: Color = field.get_hair_color(6)
	_check(field.remove_hair(2), "中間の毛 ID 2 を 1 本削除できる")
	_check(field.get_remaining_count() == 9, "1 本削除後に残り本数が 9")
	_check(not field.has_hair(2), "削除した ID 2 は存在しない")
	_check(
		field.get_surface_visible_instance_count(0) == 6
		and field.get_surface_visible_instance_count(1) == 3,
		"削除した表面の visible_instance_count だけが 1 減る"
	)
	_check(
		field.has_hair(6)
		and field.get_hair_transform(6).is_equal_approx(id6_xform_before)
		and field.get_hair_color(6).is_equal_approx(id6_color_before),
		"swap-remove 後も別の毛 (ID 6) の Transform と色が保たれる"
	)

	# 重複削除・範囲外 ID の異常系
	_check(not field.remove_hair(2), "同じ ID の重複削除は false")
	_check(not field.remove_hair(-1), "負の ID の削除は false")
	_check(not field.remove_hair(10), "上限 + 1 (ID 10) の削除は false")
	_check(field.get_remaining_count() == 9, "失敗した削除で本数が変わらない")

	# 先頭・末尾を含む残り全本数を削除して 0 本にする境界確認
	var removed_rest: int = 0
	for hair_id: int in range(10):
		if field.remove_hair(hair_id):
			removed_rest += 1
	_check(removed_rest == 9 and field.get_remaining_count() == 0, "残り 9 本を全削除して 0 本")
	_check(
		field.get_surface_visible_instance_count(0) == 0
		and field.get_surface_visible_instance_count(1) == 0,
		"全削除後に両表面の visible_instance_count が 0"
	)
	_check(not field.remove_hair(0), "全削除後の再削除は false")

	field.free()

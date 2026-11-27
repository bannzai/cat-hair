extends Node3D
## 部屋の表面ごとに MultiMesh で猫の毛を描画・管理するノード。
## MultiMesh はインスタンス単位のカリングを行わない (出典:
## https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html ) ため、
## 表面ごとに MultiMeshInstance3D を分けてフラスタムカリングが効くようにする。
## 手で 1 本抜く時は末尾インスタンスとの swap-remove で O(1) に消す。
## 表面は「面の枠 (Transform3D) の局所 XZ 平面上の矩形」で、局所 +Y が面の外向きの法線になる。
## 枠を回すと縦の面 (スーツの前身頃) や回転した家具の天面にも毛を置ける。
## 毛の総本数が draw_budget を超える時は、表面ごとに本数に比例した本数だけを 1 本ずつ描き、残りは
## 「埋もれた毛」として表面ごと・色の系統ごとの本数だけを持つ。描いている毛を消すと、埋もれた毛から 1 本を
## その表面のどこかに描き足す (本数は 1 本ずつ数え、描く本数と 1 本ずつの配列の大きさは draw_budget で頭打ちにする)。

## 毛の色の系統 (白・黒・三毛)
enum HairColorGroup {
	WHITE,
	BLACK,
	CALICO,
}

## 再現性のある配置に使う既定シード (試作決定日 2026-11-26 を採用し実行ごとにぶれない配置にする)
const DEFAULT_SEED: int = 20261126
## 表面との Z ファイトを防ぐ浮き量 (m。床・ソファのメッシュ面から 1.2 mm 浮かせる)
const SURFACE_LIFT_M: float = 0.0012
## 1 本の毛の基準長 (m。猫の一般的な抜け毛 4〜5 cm を写実寄りスケールで再現)
const HAIR_LENGTH_M: float = 0.048
## 1 本の毛の根元幅 (m。1280x720 でカメラから約 1 m の距離で 2〜3 px になり視認できる太さ)
const HAIR_BASE_WIDTH_M: float = 0.0028
## 白系統の累積確率境界 (白 34% / 黒 33% / 三毛 33% のほぼ均等 3 分割にする)
const COLOR_WHITE_THRESHOLD: float = 0.34
## 黒系統の累積確率境界 (0.34〜0.67 の 33% を黒系統に割り当てる)
const COLOR_BLACK_THRESHOLD: float = 0.67
## 三毛系統内での茶オレンジの累積確率境界 (55% を茶オレンジにし、三毛らしさを際立たせる)
const CALICO_ORANGE_THRESHOLD: float = 0.55
## 三毛系統内でのこげ茶の累積確率境界 (0.55〜0.85 の 30% をこげ茶、残り 15% をクリームにする)
const CALICO_BROWN_THRESHOLD: float = 0.85
## 色分類で三毛 (有彩色) と判定する最小彩度差 (pick_hair_color の白 0.03・黒 0.02 と三毛最小 0.18 の中間)
const CALICO_MIN_CHROMA: float = 0.08
## 色分類で白と判定する最小最大チャンネル値 (pick_hair_color の黒最大 0.16 と白最小 0.89 の中間より白寄り)
const WHITE_MIN_CHANNEL: float = 0.75
## 削除済み・未登録の毛 ID または範囲外スロットを表す番兵値
const INVALID_SLOT: int = -1
## 存在しない毛 ID または範囲外スロットに対する番兵色 (透明黒。実在の毛は alpha=1.0 のため区別可能)
const INVALID_COLOR: Color = Color(0.0, 0.0, 0.0, 0.0)
## 除外範囲 (家具の下の床等) に当たった時に配置をやり直す上限回数。
## 部屋の床の 6 割が家具で覆われていても 64 回とも外れる確率は 0.6^64 ≈ 6e-15 で、
## 上限に達した時は最後の候補にそのまま置く (配置本数を SurfaceHair の本数と必ず一致させるため)
const EXCLUSION_RETRY_LIMIT: int = 64
## 表面の向きを変えない時の面の局所基底 (+Y が上向きの法線)
const UPWARD_BASIS: Basis = Basis.IDENTITY
## 1 本ずつ描く毛の本数の既定の上限 (屋敷全体)。決めた計測は ADR 0002 の 2026-11-27 (issue #65) の追記
const DEFAULT_DRAW_BUDGET: int = 240000

## 1 本ずつ描く毛の本数の上限 (屋敷全体。0 以下は上限なし)。populate の前に設定する
var draw_budget: int = DEFAULT_DRAW_BUDGET
## 登録済みの配置表面定義 (name / transform / rect_min / rect_max / weight / exclusions)
var _surfaces: Array[Dictionary] = []
## 生成済みの表面ごとのバケット (instance / multimesh / hair_ids / transforms / colors / buried / draw_cap)。
## 表面ごとの描いている本数は multimesh.visible_instance_count を唯一の SSOT とする。
## buried は描いていない埋もれた毛の HairColorGroup ごとの本数、draw_cap は埋もれた毛を描き足して保つ描く本数
var _buckets: Array[Dictionary] = []
## 埋もれた毛を描き足す時の位置と色の乱数 (populate のシードから決まる)
var _refill_rng: RandomNumberGenerator = RandomNumberGenerator.new()
## hair_id -> 表面インデックスの逆引き配列 (INVALID_SLOT = -1 は削除済み)
var _id_to_surface: PackedInt32Array = PackedInt32Array()
## hair_id -> 表面内スロット番号の逆引き配列 (INVALID_SLOT = -1 は削除済み)
var _id_to_slot: PackedInt32Array = PackedInt32Array()
## 部屋全体で現在残っている毛の総本数
var _remaining_count: int = 0
## 全表面で共有する 1 本の毛メッシュ
var _hair_mesh: ArrayMesh = null
## _hair_mesh のローカル AABB (毛を面から持ち上げる高さの計算に使う。メッシュを作った時に 1 回だけ求める)
var _hair_aabb: AABB = AABB()
## 全表面で共有する毛マテリアル
var _hair_material: StandardMaterial3D = null


## 総本数を表面ごとの重みに応じて整数配分する (合計は必ず total_count と一致)。
## total_count <= 0 や重みの合計が 0 以下の時はすべて 0 を返す。
static func allocate_counts(
	total_count: int, weights: PackedFloat32Array
) -> PackedInt32Array:
	var result: PackedInt32Array = PackedInt32Array()
	var surface_count: int = weights.size()
	if surface_count == 0:
		return result
	result.resize(surface_count)
	if total_count <= 0:
		for i: int in range(surface_count):
			result[i] = 0
		return result

	var weight_sum: float = 0.0
	for i: int in range(surface_count):
		weight_sum += maxf(weights[i], 0.0)
	if weight_sum <= 0.0:
		for i: int in range(surface_count):
			result[i] = 0
		return result

	var remainders: PackedFloat32Array = PackedFloat32Array()
	remainders.resize(surface_count)
	var assigned: int = 0
	for i: int in range(surface_count):
		var exact: float = float(total_count) * (maxf(weights[i], 0.0) / weight_sum)
		var floor_val: int = int(floor(exact))
		result[i] = floor_val
		remainders[i] = exact - float(floor_val)
		assigned += floor_val

	var leftover: int = total_count - assigned
	while leftover > 0:
		var best_idx: int = -1
		var best_rem: float = -1.0
		for i: int in range(surface_count):
			if weights[i] > 0.0 and remainders[i] > best_rem:
				best_rem = remainders[i]
				best_idx = i
		if best_idx < 0:
			break
		result[best_idx] += 1
		remainders[best_idx] = -1.0
		leftover -= 1

	return result


## 白・黒・三毛 (茶・こげ茶・クリーム白) の 3 系統から毛の色を 1 つ選ぶ
static func pick_hair_color(rng: RandomNumberGenerator) -> Color:
	var roll: float = rng.randf()
	if roll < COLOR_WHITE_THRESHOLD:
		return pick_hair_color_in_group(rng, HairColorGroup.WHITE)
	if roll < COLOR_BLACK_THRESHOLD:
		return pick_hair_color_in_group(rng, HairColorGroup.BLACK)
	return pick_hair_color_in_group(rng, HairColorGroup.CALICO)


## 指定した系統 (HairColorGroup) の中で毛の色を 1 つ選ぶ
static func pick_hair_color_in_group(rng: RandomNumberGenerator, group: int) -> Color:
	if group == HairColorGroup.WHITE:
		# 白 (完全な純白 1.0 を避け、自然な明度差 0.89〜0.96 を付ける)
		var brightness: float = rng.randf_range(0.89, 0.96)
		return Color(brightness, brightness - 0.01, brightness - 0.03, 1.0)
	if group == HairColorGroup.BLACK:
		# 黒 (影と完全に同化しないよう明度 0.07〜0.14 の濃いチャコールにする)
		var brightness: float = rng.randf_range(0.07, 0.14)
		return Color(brightness, brightness, brightness + 0.02, 1.0)
	# 三毛 (茶オレンジ・こげ茶・クリームの混在。床の茶・ソファの紺の両方で視認できる彩度帯を採用)
	var calico_roll: float = rng.randf()
	if calico_roll < CALICO_ORANGE_THRESHOLD:
		# 茶トラ寄りの暖色オレンジ (R 0.72〜0.84, G 0.38〜0.49, B 0.14〜0.22)
		return Color(
			rng.randf_range(0.72, 0.84),
			rng.randf_range(0.38, 0.49),
			rng.randf_range(0.14, 0.22),
			1.0
		)
	if calico_roll < CALICO_BROWN_THRESHOLD:
		# 濃い焦げ茶 (R 0.32〜0.42, G 0.18〜0.25, B 0.09〜0.14)
		return Color(
			rng.randf_range(0.32, 0.42),
			rng.randf_range(0.18, 0.25),
			rng.randf_range(0.09, 0.14),
			1.0
		)
	# クリーム白 (純白より黄味を帯びさせ、三毛の明るい毛と白猫の毛を区別しやすくする)
	return Color(0.93, 0.86, 0.74, 1.0)


## 色が白・黒・三毛のどの系統に属するかを判定する (テスト用。pick_hair_color の値域に対応)
static func classify_hair_color(color: Color) -> int:
	var max_channel: float = maxf(color.r, maxf(color.g, color.b))
	var min_channel: float = minf(color.r, minf(color.g, color.b))
	if max_channel - min_channel >= CALICO_MIN_CHROMA:
		return HairColorGroup.CALICO
	if max_channel >= WHITE_MIN_CHANNEL:
		return HairColorGroup.WHITE
	return HairColorGroup.BLACK


## field の指定した表面に残っている毛 (描いている毛と埋もれた毛) を色の系統ごとに数え、HairColorGroup 順の 3 要素で返す
static func count_surface_groups(field: Node3D, surface_index: int) -> PackedInt32Array:
	var counts: PackedInt32Array = field._buried_counts(surface_index).duplicate()
	for slot: int in range(field.get_surface_visible_instance_count(surface_index)):
		var hair_id: int = field.get_hair_id_at_slot(surface_index, slot)
		counts[classify_hair_color(field.get_hair_color(hair_id))] += 1
	return counts


## field の表面 surface_index の埋もれた毛 (描いていない毛) から、色の系統 group の毛を最大 count 本消し、
## 消した本数を返す。描いている同じ色の毛が足りない時に、GameState と同じ本数を減らすために使う
## (掃除ロボットが取った毛・部屋ごとにかける道具)。公開の関数の数の上限に収めるため add_hair と同じく field を受け取る
static func remove_buried_hairs(field: Node3D, surface_index: int, group: int, count: int) -> int:
	return field._remove_buried(surface_index, group, count)


## field の表面 surface_index の埋もれた毛の HairColorGroup ごとの本数 (3 要素の複製。範囲外・未配置は 0)
static func buried_group_counts(field: Node3D, surface_index: int) -> PackedInt32Array:
	return field._buried_counts(surface_index).duplicate()


## 系統ごとの本数 counts (合計 1 以上) から、本数に比例した確率で系統を 1 つ選ぶ
static func pick_buried_group(counts: PackedInt32Array, rng: RandomNumberGenerator) -> int:
	var roll: int = rng.randi_range(0, _sum(counts) - 1)
	var group: int = 0
	while roll >= counts[group]:
		roll -= counts[group]
		group += 1
	return group


## 1 本の猫の毛のメッシュ (2 セグメント・5 頂点・3 三角形の細い曲がった先細り形状) を作る。
## 3 セグメント・5 三角形だった形から真ん中の点を抜き、毛 1 本の三角形を 4 割減らした
## (issue #56 の CI の計測で、毛 24 万本の部屋に入った直後の 1 フレームが 411 ms から 353 ms に減った)
static func build_hair_mesh() -> ArrayMesh:
	# 根元 (p0) から先端 (p2) へ弧を描く制御点 (直線ではなく曲がった抜け毛として 1 本ずつ視認でき、先端は床近くへ
	# 戻る形状)。中ほどの p1 は、3 セグメントの時の 2 つの中間点 (長さの 35%・70% で横 4.5/8.0 mm・高さ 4.2/5.6 mm)
	# のあいだで弧の膨らみが減らないよう、長さの 50% で両者の平均よりわずかに外側に置き、根元と先端は前と同じにした
	var p0: Vector3 = Vector3(0.0, 0.0, 0.0)
	var p1: Vector3 = Vector3(0.0065, 0.0052, HAIR_LENGTH_M * 0.5)
	var p2: Vector3 = Vector3(0.0042, 0.0018, HAIR_LENGTH_M)

	# 先細りの幅。中ほどの幅は、3 セグメントの時の 1/3 (0.44)・2/3 (0.30) の幅の平均に近い値にし、
	# 長さの 50% での太さを前の形と揃えた
	var w0: float = HAIR_BASE_WIDTH_M * 0.5
	var w1: float = HAIR_BASE_WIDTH_M * 0.38

	var right0: Vector3 = (p1 - p0).cross(Vector3.UP).normalized()
	var right1: Vector3 = (p2 - p0).cross(Vector3.UP).normalized()

	var vertices: PackedVector3Array = PackedVector3Array([
		p0 - right0 * w0,
		p0 + right0 * w0,
		p1 - right1 * w1,
		p1 + right1 * w1,
		p2,
	])

	var normal_up: Vector3 = Vector3(0.0, 1.0, 0.0)
	var normals: PackedVector3Array = PackedVector3Array([
		normal_up,
		normal_up,
		normal_up,
		normal_up,
		normal_up,
	])

	var indices: PackedInt32Array = PackedInt32Array([
		0, 1, 2,
		1, 3, 2,
		2, 3, 4,
	])

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## MultiMesh のインスタンス色をそのまま描画する両面マテリアルを作る
static func build_hair_material() -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# 獣毛の控えめな艶 (完全マット 1.0 を避け、鏡面ギラつきを抑える 0.72)
	material.roughness = 0.72
	material.metallic = 0.0
	return material


## ArrayMesh の頂点配列から直接ローカル AABB を計算する (headless の Dummy レンダラでも確実に動作)
static func compute_mesh_aabb(mesh: ArrayMesh) -> AABB:
	if mesh == null or mesh.get_surface_count() == 0:
		return AABB()
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	if vertices.is_empty():
		return AABB()
	var min_vec: Vector3 = vertices[0]
	var max_vec: Vector3 = vertices[0]
	for vertex: Vector3 in vertices:
		min_vec = min_vec.min(vertex)
		max_vec = max_vec.max(vertex)
	return AABB(min_vec, max_vec - min_vec)


## ローカル AABB を basis で変換した時の全頂点 Y 座標の厳密な下界を O(1) で計算する
static func compute_aabb_min_transformed_y(basis: Basis, local_aabb: AABB) -> float:
	var min_pt: Vector3 = local_aabb.position
	var max_pt: Vector3 = local_aabb.end
	return (
		minf(basis.x.y * min_pt.x, basis.x.y * max_pt.x)
		+ minf(basis.y.y * min_pt.y, basis.y.y * max_pt.y)
		+ minf(basis.z.y * min_pt.z, basis.z.y * max_pt.z)
	)


## 毛を配置する表面 (ワールド軸に沿った矩形の上面。高さは bounds_min.y) を登録する
func add_surface(
	surface_name: String, bounds_min: Vector3, bounds_max: Vector3, weight: float
) -> void:
	_surfaces.append({
		"name": surface_name,
		"transform": Transform3D(UPWARD_BASIS, Vector3(0.0, bounds_min.y, 0.0)),
		"rect_min": Vector2(bounds_min.x, bounds_min.z),
		"rect_max": Vector2(bounds_max.x, bounds_max.z),
		"weight": weight,
		"exclusions": [],
	})


## 向きの付いた表面を登録する。surface_transform の原点が面の中心、局所 +Y が面の外向きの法線、
## size が局所 X / Z の全幅。exclusions は毛を置かない範囲 (家具の下の床等) で、
## 各要素は {"inverse": ワールド → 範囲の局所の Transform3D, "half": 局所 X / Z の半幅 Vector2}
func add_oriented_surface(
	surface_name: String,
	surface_transform: Transform3D,
	size: Vector2,
	weight: float,
	exclusions: Array[Dictionary] = [],
) -> void:
	_surfaces.append({
		"name": surface_name,
		"transform": surface_transform,
		"rect_min": -size * 0.5,
		"rect_max": size * 0.5,
		"weight": weight,
		"exclusions": exclusions,
	})


## 登録済みの表面へ、表面ごと・色の系統ごとに指定した本数の毛を配置し、配置できた本数を返す。
## counts_by_surface[i] は表面 i の HairColorGroup ごとの本数 (要素数 3)。足りない表面は 0 本にする
func populate_with_group_counts(
	counts_by_surface: Array[PackedInt32Array], seed_value: int = DEFAULT_SEED
) -> int:
	clear()
	if _surfaces.is_empty():
		return 0
	var group_counts_by_surface: Array[PackedInt32Array] = []
	var totals: PackedFloat32Array = PackedFloat32Array()
	var total: int = 0
	for surface_idx: int in range(_surfaces.size()):
		var group_counts: PackedInt32Array = PackedInt32Array()
		group_counts.resize(HairColorGroup.size())
		group_counts.fill(0)
		if surface_idx < counts_by_surface.size():
			var given: PackedInt32Array = counts_by_surface[surface_idx]
			for group: int in range(mini(given.size(), HairColorGroup.size())):
				group_counts[group] = maxi(0, given[group])
		var surface_total: int = 0
		for count: int in group_counts:
			surface_total += count
		group_counts_by_surface.append(group_counts)
		totals.append(float(surface_total))
		total += surface_total
	var drawn_by_surface: PackedInt32Array = _drawn_counts(totals, total)
	# 0 本の時も表面ごとの枠を作る (毛を取り切った屋敷を開き直した後も、猫が落とした毛を add_hair で足せるようにする)
	_prepare_shared_resources(_sum(drawn_by_surface))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	_refill_rng.seed = seed_value + 1
	var next_id: int = 0
	for surface_idx: int in range(_surfaces.size()):
		var group_counts: PackedInt32Array = group_counts_by_surface[surface_idx]
		var drawn: int = drawn_by_surface[surface_idx]
		# 描く本数を色の系統の本数に比例して分ける (全部描く時は系統の本数そのまま)
		var drawn_groups: PackedInt32Array = (
			group_counts
			if drawn >= int(totals[surface_idx])
			else allocate_counts(drawn, _to_weights(group_counts))
		)
		var groups: PackedInt32Array = PackedInt32Array()
		var buried: PackedInt32Array = PackedInt32Array()
		for group: int in range(HairColorGroup.size()):
			for _i: int in range(drawn_groups[group]):
				groups.append(group)
			buried.append(group_counts[group] - drawn_groups[group])
		_buckets.append(_create_surface_bucket(
			surface_idx, _surfaces[surface_idx], groups.size(), rng, next_id, groups, buried
		))
		next_id += groups.size()
	_remaining_count = total
	return total


## 登録済みの表面へ合計 total_count 本の毛を配置し、配置できた本数を返す
func populate(total_count: int, seed_value: int = DEFAULT_SEED) -> int:
	clear()
	if total_count <= 0 or _surfaces.is_empty():
		return 0

	var weights: PackedFloat32Array = PackedFloat32Array()
	weights.resize(_surfaces.size())
	for i: int in range(_surfaces.size()):
		weights[i] = float(_surfaces[i]["weight"])

	var counts: PackedInt32Array = allocate_counts(total_count, weights)
	var actual_total: int = _sum(counts)
	if actual_total <= 0:
		return 0
	var drawn_by_surface: PackedInt32Array = _drawn_counts(_to_weights(counts), actual_total)

	_prepare_shared_resources(_sum(drawn_by_surface))

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	_refill_rng.seed = seed_value + 1
	var next_id: int = 0
	# 描く毛の色は pick_hair_color の乱数で選び、埋もれた毛は同じ確率の比で系統に分ける
	var group_weights: PackedFloat32Array = PackedFloat32Array([
		COLOR_WHITE_THRESHOLD,
		COLOR_BLACK_THRESHOLD - COLOR_WHITE_THRESHOLD,
		1.0 - COLOR_BLACK_THRESHOLD,
	])

	for surface_idx: int in range(_surfaces.size()):
		var drawn: int = drawn_by_surface[surface_idx]
		_buckets.append(_create_surface_bucket(
			surface_idx, _surfaces[surface_idx], drawn, rng, next_id, PackedInt32Array(),
			allocate_counts(counts[surface_idx] - drawn, group_weights)
		))
		next_id += drawn

	_remaining_count = actual_total
	return actual_total


## 指定した毛 ID を 1 本だけ消す (O(1) swap-remove)。消せたら true。
## その表面に埋もれた毛があれば、1 本を表面のどこかに描き足す (残り本数は 1 減る)
func remove_hair(hair_id: int) -> bool:
	if hair_id < 0 or hair_id >= _id_to_slot.size():
		return false
	if _id_to_slot[hair_id] < 0:
		return false
	var surface_index: int = _erase_drawn(hair_id)
	_remaining_count -= 1
	_draw_buried_hair(surface_index)
	return true


## 描いている毛 hair_id (描いていることを確かめ済み) を末尾の毛との swap-remove で描かなくし、その表面の添字を返す。
## 残り本数と埋もれた毛は変えない
func _erase_drawn(hair_id: int) -> int:
	var slot: int = _id_to_slot[hair_id]
	var surface_index: int = _id_to_surface[hair_id]
	var bucket: Dictionary = _buckets[surface_index]
	var multimesh: MultiMesh = bucket["multimesh"]
	var hair_ids: PackedInt32Array = bucket["hair_ids"]
	var last_slot: int = multimesh.visible_instance_count - 1

	if slot != last_slot:
		var last_id: int = hair_ids[last_slot]
		var transforms: Array[Transform3D] = bucket["transforms"]
		var colors: PackedColorArray = bucket["colors"]
		var moved_transform: Transform3D = transforms[last_slot]
		var moved_color: Color = colors[last_slot]
		transforms[slot] = moved_transform
		colors[slot] = moved_color
		multimesh.set_instance_transform(slot, moved_transform)
		multimesh.set_instance_color(slot, moved_color)
		hair_ids[slot] = last_id
		_id_to_slot[last_id] = slot
		bucket["colors"] = colors

	bucket["hair_ids"] = hair_ids
	multimesh.visible_instance_count = last_slot
	_id_to_slot[hair_id] = INVALID_SLOT
	_id_to_surface[hair_id] = INVALID_SLOT
	return surface_index


## 表面 surface_index に埋もれた毛があり、描いている本数が draw_cap より少なければ、埋もれた毛から 1 本
## (系統は埋もれた毛の本数に比例した抽選) を表面のどこかに描き足す。残り本数は変えない
func _draw_buried_hair(surface_index: int) -> void:
	var bucket: Dictionary = _buckets[surface_index]
	var buried: PackedInt32Array = bucket["buried"]
	var buried_total: int = _sum(buried)
	if (
		buried_total <= 0
		or (bucket["multimesh"] as MultiMesh).visible_instance_count >= int(bucket["draw_cap"])
	):
		return
	var group: int = pick_buried_group(buried, _refill_rng)
	buried[group] -= 1
	bucket["buried"] = buried
	var xform: Transform3D = _random_hair_transform(_surfaces[surface_index], _hair_aabb, _refill_rng)
	_place_hair(surface_index, xform, pick_hair_color_in_group(_refill_rng, group))


## 表面 surface_index の埋もれた毛から系統 group の毛を最大 count 本消し、消した本数を返す (remove_buried_hairs の本体)
func _remove_buried(surface_index: int, group: int, count: int) -> int:
	if (
		surface_index < 0 or surface_index >= _buckets.size()
		or group < 0 or group >= HairColorGroup.size()
	):
		return 0
	var bucket: Dictionary = _buckets[surface_index]
	var buried: PackedInt32Array = bucket["buried"]
	var removed: int = clampi(count, 0, buried[group])
	buried[group] -= removed
	bucket["buried"] = buried
	_remaining_count -= removed
	return removed


## field の表面 surface_index の、point (ワールド座標) から面に沿って spread 以内のどこかに、色の系統 group の毛を
## 1 本足し、足した毛の ID を返す (猫が落とした毛)。point は面の矩形の中に収め、置けない時 (表面が無い・未配置) は
## INVALID_SLOT。MultiMesh の枠が足りない時は枠を倍に広げて、CPU 側の配列から今の毛を置き直す。
## 埋もれた毛がある表面で描いている本数が draw_cap に達している時は、描いている毛を 1 本 (乱数で選ぶ) 埋もれた毛へ戻してから
## 落とした毛を描く (描く本数を draw_budget で頭打ちに保ち、落とした毛は見せるため)。
## 公開の関数の数の上限 (gdlint の max-public-methods) に収めるため、count_surface_groups と同じく field を受け取る形にする
static func add_hair(
	field: Node3D,
	surface_index: int,
	point: Vector3,
	spread: float,
	group: int,
	rng: RandomNumberGenerator,
) -> int:
	return field._add_hair(surface_index, point, spread, group, rng)


## add_hair の本体
func _add_hair(
	surface_index: int, point: Vector3, spread: float, group: int, rng: RandomNumberGenerator
) -> int:
	if surface_index < 0 or surface_index >= _buckets.size() or _hair_mesh == null:
		return INVALID_SLOT
	var bucket: Dictionary = _buckets[surface_index]
	var buried: PackedInt32Array = bucket["buried"]
	var multimesh: MultiMesh = bucket["multimesh"]
	if _sum(buried) > 0 and multimesh.visible_instance_count >= int(bucket["draw_cap"]):
		# 描く本数を上限に保ったまま落とした毛を見せるため、描いている毛を 1 本 (乱数で選ぶ) 埋もれた毛へ戻す
		var swapped_slot: int = rng.randi_range(0, multimesh.visible_instance_count - 1)
		var swapped_id: int = (bucket["hair_ids"] as PackedInt32Array)[swapped_slot]
		buried[classify_hair_color((bucket["colors"] as PackedColorArray)[swapped_slot])] += 1
		bucket["buried"] = buried
		_erase_drawn(swapped_id)
	var spec: Dictionary = _surfaces[surface_index]
	var surface_transform: Transform3D = spec["transform"]
	var rect_min: Vector2 = spec["rect_min"]
	var rect_max: Vector2 = spec["rect_max"]
	var local_point: Vector3 = surface_transform.affine_inverse() * point
	var basis: Basis = random_hair_basis(rng)
	var local_xform: Transform3D = Transform3D(
		basis, Vector3(0.0, hair_lift(basis, _hair_aabb, rng), 0.0)
	)
	var xform: Transform3D = Transform3D()
	for _retry: int in range(EXCLUSION_RETRY_LIMIT + 1):
		var angle: float = rng.randf_range(0.0, TAU)
		var distance: float = spread * sqrt(rng.randf())
		local_xform.origin.x = clampf(local_point.x + cos(angle) * distance, rect_min.x, rect_max.x)
		local_xform.origin.z = clampf(local_point.z + sin(angle) * distance, rect_min.y, rect_max.y)
		xform = surface_transform * local_xform
		if not _is_excluded(xform.origin, spec["exclusions"]):
			break
	var hair_id: int = _place_hair(surface_index, xform, pick_hair_color_in_group(rng, group))
	_remaining_count += 1
	return hair_id


## 表面 surface_index の描いている毛の末尾に、xform と color の毛を 1 本描き、新しい毛 ID を返す (残り本数は変えない)。
## MultiMesh の枠が足りない時は枠を倍に広げて、CPU 側の配列から今の毛を置き直す
func _place_hair(surface_index: int, xform: Transform3D, color: Color) -> int:
	var bucket: Dictionary = _buckets[surface_index]
	var multimesh: MultiMesh = bucket["multimesh"]
	var slot: int = multimesh.visible_instance_count
	if slot >= multimesh.instance_count:
		# 倍に広げて置き直す回数を本数の log に抑える。0 本の面の最初の枠は、猫が 1 か所に立ち止まる間に落とす 4 本の
		# 数回分 (16 本) にし、立ち止まるたびに広げ直さない
		_grow_bucket(bucket, maxi(16, multimesh.instance_count * 2))
	var hair_id: int = _id_to_slot.size()
	_id_to_slot.append(slot)
	_id_to_surface.append(surface_index)
	var hair_ids: PackedInt32Array = bucket["hair_ids"]
	var colors: PackedColorArray = bucket["colors"]
	hair_ids[slot] = hair_id
	colors[slot] = color
	(bucket["transforms"] as Array[Transform3D])[slot] = xform
	bucket["hair_ids"] = hair_ids
	bucket["colors"] = colors
	multimesh = bucket["multimesh"]
	multimesh.visible_instance_count = slot + 1
	multimesh.set_instance_transform(slot, xform)
	multimesh.set_instance_color(slot, color)
	return hair_id


## 毛 1 本の向きと大きさ (面の局所座標の Basis) を乱数で決める。
## 向きは水平 360 度、傾きは表面から不自然に立たない ±0.14〜0.18 rad、
## 長さ 0.75〜1.35 倍・幅 0.85〜1.25 倍で抜け毛の個体差を出す
static func random_hair_basis(rng: RandomNumberGenerator) -> Basis:
	var scale_len: float = rng.randf_range(0.75, 1.35)
	# 乱数を引く順 (長さ・傾き 3 つ・幅) を変えると同じ種で置く毛の位置が変わるため、引く順を文で固定する
	var basis: Basis = Basis.from_euler(Vector3(
		rng.randf_range(-0.14, 0.14),
		rng.randf_range(0.0, TAU),
		rng.randf_range(-0.18, 0.18)
	))
	return basis.scaled_local(Vector3(rng.randf_range(0.85, 1.25), scale_len, scale_len))


## basis で置いた毛の根元を、面 (局所 Y = 0) から持ち上げる高さ。回転・スケール後に先端や根元が表面の下へ
## 潜らないよう最小 Y 分だけ持ち上げ、重なり合う毛同士の Z ファイトを避けるため最大 1.8 mm の微差を乱数で付ける
static func hair_lift(basis: Basis, local_aabb: AABB, rng: RandomNumberGenerator) -> float:
	return (
		SURFACE_LIFT_M
		- minf(compute_aabb_min_transformed_y(basis, local_aabb), 0.0)
		+ rng.randf_range(0.0, 0.0018)
	)


## 表面の MultiMesh の枠を capacity 本に広げ、CPU 側の配列 (transforms / colors) から今の毛を置き直す。
## MultiMesh は instance_count を変えると中身が消えるため置き直す
func _grow_bucket(bucket: Dictionary, capacity: int) -> void:
	var multimesh: MultiMesh = bucket["multimesh"]
	var visible_count: int = multimesh.visible_instance_count
	var transforms: Array[Transform3D] = bucket["transforms"]
	var colors: PackedColorArray = bucket["colors"]
	var hair_ids: PackedInt32Array = bucket["hair_ids"]
	transforms.resize(capacity)
	colors.resize(capacity)
	hair_ids.resize(capacity)
	multimesh.instance_count = capacity
	multimesh.visible_instance_count = visible_count
	for slot: int in range(visible_count):
		multimesh.set_instance_transform(slot, transforms[slot])
		multimesh.set_instance_color(slot, colors[slot])
	bucket["colors"] = colors
	bucket["hair_ids"] = hair_ids


## すべての毛と生成済み MultiMeshInstance3D を解放する
func clear() -> void:
	for bucket: Dictionary in _buckets:
		var instance: MultiMeshInstance3D = bucket["instance"]
		if is_instance_valid(instance):
			if instance.get_parent() == self:
				remove_child(instance)
			instance.free()
	_buckets.clear()
	_id_to_surface = PackedInt32Array()
	_id_to_slot = PackedInt32Array()
	_remaining_count = 0


## 現在の残り毛本数を返す
func get_remaining_count() -> int:
	return _remaining_count


## 登録済み表面の数を返す
func get_surface_count() -> int:
	return _surfaces.size()


## 指定した表面の残り毛本数 (描いている毛と埋もれた毛の合計) を返す
func get_surface_remaining_count(surface_index: int) -> int:
	return get_surface_visible_instance_count(surface_index) + _sum(_buried_counts(surface_index))


## 指定した表面の MultiMesh の visible_instance_count を返す
func get_surface_visible_instance_count(surface_index: int) -> int:
	if surface_index < 0 or surface_index >= _buckets.size():
		return 0
	return (_buckets[surface_index]["multimesh"] as MultiMesh).visible_instance_count


## 指定した表面の指定スロットにある毛 ID を返す (範囲外は INVALID_SLOT = -1)
func get_hair_id_at_slot(surface_index: int, slot: int) -> int:
	if surface_index < 0 or surface_index >= _buckets.size():
		return INVALID_SLOT
	var bucket: Dictionary = _buckets[surface_index]
	if slot < 0 or slot >= (bucket["multimesh"] as MultiMesh).visible_instance_count:
		return INVALID_SLOT
	return (bucket["hair_ids"] as PackedInt32Array)[slot]


## 指定した表面の MultiMesh 本体から指定スロットの Transform3D を直接読む (描画付き検証用)
func get_multimesh_slot_transform(surface_index: int, slot: int) -> Transform3D:
	if surface_index < 0 or surface_index >= _buckets.size():
		return Transform3D.IDENTITY
	var multimesh: MultiMesh = _buckets[surface_index]["multimesh"]
	if slot < 0 or slot >= multimesh.visible_instance_count:
		return Transform3D.IDENTITY
	return multimesh.get_instance_transform(slot)


## 指定した表面の MultiMesh 本体から指定スロットの色を直接読む (描画付き検証用)
func get_multimesh_slot_color(surface_index: int, slot: int) -> Color:
	if surface_index < 0 or surface_index >= _buckets.size():
		return INVALID_COLOR
	var multimesh: MultiMesh = _buckets[surface_index]["multimesh"]
	if slot < 0 or slot >= multimesh.visible_instance_count:
		return INVALID_COLOR
	return multimesh.get_instance_color(slot)


## 指定した毛 ID が現在存在していれば true
func has_hair(hair_id: int) -> bool:
	if hair_id < 0 or hair_id >= _id_to_slot.size():
		return false
	return _id_to_slot[hair_id] >= 0


## 指定した毛 ID の現在の表面内スロット番号を返す (存在しない場合は INVALID_SLOT = -1)
func get_hair_slot(hair_id: int) -> int:
	if hair_id < 0 or hair_id >= _id_to_slot.size():
		return INVALID_SLOT
	return _id_to_slot[hair_id]


## 指定した毛 ID の現在の Transform3D を返す (存在しない場合は Identity)
func get_hair_transform(hair_id: int) -> Transform3D:
	if not has_hair(hair_id):
		return Transform3D.IDENTITY
	return (_buckets[_id_to_surface[hair_id]]["transforms"] as Array[Transform3D])[
		_id_to_slot[hair_id]
	]


## 指定した毛 ID の現在の色を返す (存在しない場合は INVALID_COLOR)
func get_hair_color(hair_id: int) -> Color:
	if not has_hair(hair_id):
		return INVALID_COLOR
	return (_buckets[_id_to_surface[hair_id]]["colors"] as PackedColorArray)[
		_id_to_slot[hair_id]
	]


## from から direction 向きの半直線が表から当たる表面のうち、max_distance 以内で最も近いものを返す。
## 当たれば {"surface_index", "point", "distance"}、どこにも当たらなければ空の辞書
func intersect_surfaces(from: Vector3, direction: Vector3, max_distance: float) -> Dictionary:
	var best: Dictionary = {}
	var dir: Vector3 = direction.normalized()
	for surface_idx: int in range(_surfaces.size()):
		var spec: Dictionary = _surfaces[surface_idx]
		var surface_transform: Transform3D = spec["transform"]
		var normal: Vector3 = surface_transform.basis.y.normalized()
		var facing: float = dir.dot(normal)
		if facing >= -0.0001:
			continue
		var distance: float = (surface_transform.origin - from).dot(normal) / facing
		if distance < 0.0 or distance > max_distance:
			continue
		if not best.is_empty() and distance >= float(best["distance"]):
			continue
		var point: Vector3 = from + dir * distance
		var local: Vector3 = surface_transform.affine_inverse() * point
		var rect_min: Vector2 = spec["rect_min"]
		var rect_max: Vector2 = spec["rect_max"]
		if (
			local.x < rect_min.x or local.x > rect_max.x
			or local.z < rect_min.y or local.z > rect_max.y
		):
			continue
		best = {"surface_index": surface_idx, "point": point, "distance": distance}
	return best


## 指定した表面で、根元が point から radius 以内にある毛 ID を近い順に最大 max_count 本返す
func find_hairs_near(
	surface_index: int, point: Vector3, radius: float, max_count: int
) -> PackedInt32Array:
	var result: PackedInt32Array = PackedInt32Array()
	if surface_index < 0 or surface_index >= _buckets.size() or max_count <= 0:
		return result
	var bucket: Dictionary = _buckets[surface_index]
	var transforms: Array[Transform3D] = bucket["transforms"]
	var hair_ids: PackedInt32Array = bucket["hair_ids"]
	var candidates: Array[Vector2] = []
	var radius_sq: float = radius * radius
	for slot: int in range((bucket["multimesh"] as MultiMesh).visible_instance_count):
		var dist_sq: float = transforms[slot].origin.distance_squared_to(point)
		if dist_sq <= radius_sq:
			candidates.append(Vector2(dist_sq, float(hair_ids[slot])))
	candidates.sort()
	for candidate: Vector2 in candidates:
		if result.size() >= max_count:
			break
		result.append(int(candidate.y))
	return result


## 指定した毛の見た目だけを display_transform に変える (伸びる演出用。照会用の transform は変えない)
func set_hair_display_transform(hair_id: int, display_transform: Transform3D) -> void:
	if not has_hair(hair_id):
		return
	var multimesh: MultiMesh = _buckets[_id_to_surface[hair_id]]["multimesh"]
	multimesh.set_instance_transform(_id_to_slot[hair_id], display_transform)


## 共有メッシュ・マテリアルを用意し、毛 ID の逆引き配列を total 本分確保する
func _prepare_shared_resources(total: int) -> void:
	if _hair_mesh == null:
		_hair_mesh = build_hair_mesh()
		_hair_aabb = compute_mesh_aabb(_hair_mesh)
	if _hair_material == null:
		_hair_material = build_hair_material()
	_id_to_surface.resize(total)
	_id_to_slot.resize(total)


## 表面ごとの本数 totals (合計 total) から、表面ごとに 1 本ずつ描く本数を返す。合計が draw_budget 以下 (か上限なし)
## なら全部描き、超える時は draw_budget を表面の本数に比例して分ける
func _drawn_counts(totals: PackedFloat32Array, total: int) -> PackedInt32Array:
	if draw_budget <= 0 or total <= draw_budget:
		var all_counts: PackedInt32Array = PackedInt32Array()
		for count: float in totals:
			all_counts.append(int(count))
		return all_counts
	return allocate_counts(draw_budget, totals)


## 表面 surface_index の埋もれた毛の HairColorGroup ごとの本数 (範囲外・未配置は 0 の 3 要素)
func _buried_counts(surface_index: int) -> PackedInt32Array:
	if surface_index < 0 or surface_index >= _buckets.size():
		var zeros: PackedInt32Array = PackedInt32Array()
		zeros.resize(HairColorGroup.size())
		zeros.fill(0)
		return zeros
	return _buckets[surface_index]["buried"]


## 整数の列の合計
static func _sum(values: PackedInt32Array) -> int:
	var total: int = 0
	for value: int in values:
		total += value
	return total


## 整数の列を allocate_counts の重みの形にする
static func _to_weights(values: PackedInt32Array) -> PackedFloat32Array:
	var weights: PackedFloat32Array = PackedFloat32Array()
	for value: int in values:
		weights.append(float(value))
	return weights


## 表面 spec の矩形のどこかに置く毛 1 本の Transform3D を乱数で決める (除外範囲に当たれば EXCLUSION_RETRY_LIMIT 回まで
## 置き直す)。乱数を引く順 (向き・X・持ち上げ・Z、置き直しは X・Z) を変えると同じ種で置く毛の位置が変わるため、順を文で固定する
static func _random_hair_transform(
	spec: Dictionary, local_aabb: AABB, rng: RandomNumberGenerator
) -> Transform3D:
	var surface_transform: Transform3D = spec["transform"]
	var rect_min: Vector2 = spec["rect_min"]
	var rect_max: Vector2 = spec["rect_max"]
	var exclusions: Array = spec["exclusions"]
	var basis: Basis = random_hair_basis(rng)
	var local_xform: Transform3D = Transform3D(basis, Vector3(
		rng.randf_range(rect_min.x, rect_max.x),
		hair_lift(basis, local_aabb, rng),
		rng.randf_range(rect_min.y, rect_max.y)
	))
	var xform: Transform3D = surface_transform * local_xform
	var retries: int = 0
	while retries < EXCLUSION_RETRY_LIMIT and _is_excluded(xform.origin, exclusions):
		local_xform.origin.x = rng.randf_range(rect_min.x, rect_max.x)
		local_xform.origin.z = rng.randf_range(rect_min.y, rect_max.y)
		xform = surface_transform * local_xform
		retries += 1
	return xform


## 表面の局所 XZ 上の点がワールド座標で除外範囲のどれかに入るか
static func _is_excluded(world_point: Vector3, exclusions: Array) -> bool:
	for exclusion: Dictionary in exclusions:
		var local: Vector3 = (exclusion["inverse"] as Transform3D) * world_point
		var half: Vector2 = exclusion["half"]
		if absf(local.x) <= half.x and absf(local.z) <= half.y:
			return true
	return false


## 1 表面分の MultiMeshInstance3D とバケットを生成し、乱数シードに従って count 本の毛を描く。
## groups が空なら色の系統も乱数で選び、空でなければ slot ごとに groups[slot] の系統で色を選ぶ。
## buried は描かない埋もれた毛の HairColorGroup ごとの本数で、描いている毛を消した時に描き足す元になる。
## MultiMesh.get_instance_transform/color は headless (Dummy レンダラ) で既定値を返すため、
## CPU 側の transforms / colors 配列にも同値を保持して swap-remove と照会を統一する。
func _create_surface_bucket(
	surface_idx: int,
	spec: Dictionary,
	count: int,
	rng: RandomNumberGenerator,
	start_id: int,
	groups: PackedInt32Array,
	buried: PackedInt32Array,
) -> Dictionary:
	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = _hair_mesh
	multimesh.instance_count = count
	multimesh.visible_instance_count = count

	var hair_ids: PackedInt32Array = PackedInt32Array()
	hair_ids.resize(count)
	var transforms: Array[Transform3D] = []
	transforms.resize(count)
	var colors: PackedColorArray = PackedColorArray()
	colors.resize(count)

	for slot: int in range(count):
		var hair_id: int = start_id + slot
		hair_ids[slot] = hair_id
		_id_to_surface[hair_id] = surface_idx
		_id_to_slot[hair_id] = slot

		var xform: Transform3D = _random_hair_transform(spec, _hair_aabb, rng)
		var color: Color = (
			pick_hair_color(rng)
			if groups.is_empty()
			else pick_hair_color_in_group(rng, groups[slot])
		)
		transforms[slot] = xform
		colors[slot] = color
		multimesh.set_instance_transform(slot, xform)
		multimesh.set_instance_color(slot, color)

	var multimesh_instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
	multimesh_instance.name = "HairSurface_%s" % str(spec["name"])
	multimesh_instance.multimesh = multimesh
	multimesh_instance.material_override = _hair_material
	multimesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(multimesh_instance)

	return {
		"instance": multimesh_instance,
		"multimesh": multimesh,
		"hair_ids": hair_ids,
		"transforms": transforms,
		"colors": colors,
		"buried": buried,
		"draw_cap": count,
	}

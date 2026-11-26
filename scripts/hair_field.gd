extends Node3D
## 部屋の表面ごとに MultiMesh で猫の毛を描画・管理するノード。
## MultiMesh はインスタンス単位のカリングを行わない (出典:
## https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html ) ため、
## 表面ごとに MultiMeshInstance3D を分けてフラスタムカリングが効くようにする。
## 手で 1 本抜く時は末尾インスタンスとの swap-remove で O(1) に消す。

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

## 登録済みの配置表面定義 (name / bounds_min / bounds_max / weight)
var _surfaces: Array[Dictionary] = []
## 生成済みの表面ごとのバケット (instance / multimesh / hair_ids / transforms / colors)。
## 表面ごとの有効本数は multimesh.visible_instance_count を唯一の SSOT とする
var _buckets: Array[Dictionary] = []
## hair_id -> 表面インデックスの逆引き配列 (INVALID_SLOT = -1 は削除済み)
var _id_to_surface: PackedInt32Array = PackedInt32Array()
## hair_id -> 表面内スロット番号の逆引き配列 (INVALID_SLOT = -1 は削除済み)
var _id_to_slot: PackedInt32Array = PackedInt32Array()
## 部屋全体で現在残っている毛の総本数
var _remaining_count: int = 0
## 全表面で共有する 1 本の毛メッシュ
var _hair_mesh: ArrayMesh = null
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
		# 白 (完全な純白 1.0 を避け、自然な明度差 0.89〜0.96 を付ける)
		var brightness: float = rng.randf_range(0.89, 0.96)
		return Color(brightness, brightness - 0.01, brightness - 0.03, 1.0)
	if roll < COLOR_BLACK_THRESHOLD:
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


## 1 本の猫の毛のメッシュ (3 セグメント・7 頂点・5 三角形の細い曲がった先細り形状) を作る
static func build_hair_mesh() -> ArrayMesh:
	# 根元 (p0) から先端 (p3) へ横最大 8 mm・高さ最大 5.6 mm の緩やかな弧を描く制御点
	# (直線ではなく曲がった抜け毛として 1 本ずつ視認でき、先端は床近くへ戻る形状)
	var p0: Vector3 = Vector3(0.0, 0.0, 0.0)
	var p1: Vector3 = Vector3(0.0045, 0.0042, HAIR_LENGTH_M * 0.35)
	var p2: Vector3 = Vector3(0.0080, 0.0056, HAIR_LENGTH_M * 0.70)
	var p3: Vector3 = Vector3(0.0042, 0.0018, HAIR_LENGTH_M)

	# 根元半幅 0.50 → 1/3 で 0.44 → 2/3 で 0.30 → 先端 0.0 の段階的テーパーで先細りにする
	var w0: float = HAIR_BASE_WIDTH_M * 0.5
	var w1: float = HAIR_BASE_WIDTH_M * 0.44
	var w2: float = HAIR_BASE_WIDTH_M * 0.30

	var right0: Vector3 = (p1 - p0).cross(Vector3.UP).normalized()
	var right1: Vector3 = (p2 - p0).cross(Vector3.UP).normalized()
	var right2: Vector3 = (p3 - p1).cross(Vector3.UP).normalized()

	var vertices: PackedVector3Array = PackedVector3Array([
		p0 - right0 * w0,
		p0 + right0 * w0,
		p1 - right1 * w1,
		p1 + right1 * w1,
		p2 - right2 * w2,
		p2 + right2 * w2,
		p3,
	])

	var normal_up: Vector3 = Vector3(0.0, 1.0, 0.0)
	var normals: PackedVector3Array = PackedVector3Array([
		normal_up,
		normal_up,
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
		3, 5, 4,
		4, 5, 6,
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


## 毛を配置する表面 (矩形の上面) を登録する
func add_surface(
	surface_name: String, bounds_min: Vector3, bounds_max: Vector3, weight: float
) -> void:
	_surfaces.append({
		"name": surface_name,
		"bounds_min": bounds_min,
		"bounds_max": bounds_max,
		"weight": weight,
	})


## 登録済みの表面へ合計 total_count 本の毛を配置し、配置できた本数を返す
func populate(total_count: int, seed_value: int = DEFAULT_SEED) -> int:
	clear()
	if total_count <= 0 or _surfaces.is_empty():
		return 0

	if _hair_mesh == null:
		_hair_mesh = build_hair_mesh()
	if _hair_material == null:
		_hair_material = build_hair_material()

	var weights: PackedFloat32Array = PackedFloat32Array()
	weights.resize(_surfaces.size())
	for i: int in range(_surfaces.size()):
		weights[i] = float(_surfaces[i]["weight"])

	var counts: PackedInt32Array = allocate_counts(total_count, weights)
	var actual_total: int = 0
	for count_for_surface: int in counts:
		actual_total += count_for_surface
	if actual_total <= 0:
		return 0

	_id_to_surface.resize(actual_total)
	_id_to_slot.resize(actual_total)

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var next_id: int = 0

	for surface_idx: int in range(_surfaces.size()):
		var count: int = counts[surface_idx]
		_buckets.append(_create_surface_bucket(
			surface_idx, _surfaces[surface_idx], count, rng, next_id
		))
		next_id += count

	_remaining_count = actual_total
	return actual_total


## 指定した毛 ID を 1 本だけ消す (O(1) swap-remove)。消せたら true
func remove_hair(hair_id: int) -> bool:
	if hair_id < 0 or hair_id >= _id_to_slot.size():
		return false
	var slot: int = _id_to_slot[hair_id]
	if slot < 0:
		return false
	var bucket: Dictionary = _buckets[_id_to_surface[hair_id]]
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
	_remaining_count -= 1
	return true


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


## 指定した表面の残り毛本数を返す (MultiMesh の visible_instance_count を SSOT とする)
func get_surface_remaining_count(surface_index: int) -> int:
	return get_surface_visible_instance_count(surface_index)


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


## 1 表面分の MultiMeshInstance3D とバケットを生成し、乱数シードに従って毛を配置する。
## MultiMesh.get_instance_transform/color は headless (Dummy レンダラ) で既定値を返すため、
## CPU 側の transforms / colors 配列にも同値を保持して swap-remove と照会を統一する。
func _create_surface_bucket(
	surface_idx: int,
	spec: Dictionary,
	count: int,
	rng: RandomNumberGenerator,
	start_id: int
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

	var bounds_min: Vector3 = spec["bounds_min"]
	var bounds_max: Vector3 = spec["bounds_max"]
	var base_y: float = bounds_min.y + SURFACE_LIFT_M
	var local_aabb: AABB = compute_mesh_aabb(_hair_mesh)

	for slot: int in range(count):
		var hair_id: int = start_id + slot
		hair_ids[slot] = hair_id
		_id_to_surface[hair_id] = surface_idx
		_id_to_slot[hair_id] = slot

		# 向きは水平 360 度、傾きは表面から不自然に立たない ±0.14〜0.18 rad、
		# 長さ 0.75〜1.35 倍・幅 0.85〜1.25 倍で抜け毛の個体差を出す
		var scale_len: float = rng.randf_range(0.75, 1.35)
		var basis: Basis = Basis.from_euler(Vector3(
			rng.randf_range(-0.14, 0.14),
			rng.randf_range(0.0, TAU),
			rng.randf_range(-0.18, 0.18)
		))
		basis = basis.scaled(Vector3(rng.randf_range(0.85, 1.25), scale_len, scale_len))
		# 回転・スケール後に先端や根元が表面の下へ潜らないよう最小 Y 分だけ持ち上げる。
		# 重なり合う毛同士の Z ファイトを避けるため高さに最大 1.8 mm の微差を付ける
		var xform: Transform3D = Transform3D(basis, Vector3(
			rng.randf_range(bounds_min.x, bounds_max.x),
			base_y
			- minf(compute_aabb_min_transformed_y(basis, local_aabb), 0.0)
			+ rng.randf_range(0.0, 0.0018),
			rng.randf_range(bounds_min.z, bounds_max.z)
		))
		var color: Color = pick_hair_color(rng)
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
	}

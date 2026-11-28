extends RefCounted
## 買取業者の体と手足の形状を検証する。

## 屋敷ビルダーロジックスクリプト
const MansionBuilderScript := preload("res://scripts/mansion/mansion_builder.gd")
## 屋敷のノードを組み立てるスクリプト
const MansionWorldScript := preload("res://scripts/mansion/mansion_world.gd")
## 屋敷の生成パラメータのスクリプト
const MansionTuningScript := preload("res://scripts/data/mansion_tuning.gd")
## 人の体の部品を作る関数
const HumanParts := preload("res://scripts/human/human_parts.gd")
## 位置を同じとみなす誤差 (m)。部品の寸法 (mm 単位) より十分小さく、浮動小数の丸めより大きい値
const POSITION_TOLERANCE_M: float = 0.0001
## 検証結果を記録する selfcheck の SceneTree 参照
var _checker: SceneTree = null


## 人の形の検証をすべて実行する
static func run_all(checker: SceneTree) -> void:
	var suite: RefCounted = load("res://scripts/dev/selfcheck_human.gd").new()
	suite._checker = checker
	suite._check_limb_ends_and_shadow()
	suite._check_trader_body()


## 検証結果を selfcheck 本体へ記録する
func _check(cond: bool, label: String) -> void:
	_checker._check(cond, label)


## add_limb のカプセルの両端の丸みの中心が、斜め・真下向きの 2 点に重なり、長さ 0 では回らず、
## 球・直方体が渡した中心・大きさで置かれ、マテリアルと影を落とすかが引数どおりになるか
func _check_limb_ends_and_shadow() -> void:
	var parent_node: Node3D = Node3D.new()
	var part_material: StandardMaterial3D = StandardMaterial3D.new()
	var ends_ok: bool = true
	for points: Array[Vector3] in [
		[Vector3(0.1, 0.2, -0.3), Vector3(-0.2, 0.5, 0.4)] as Array[Vector3],
		[Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, 0.0)] as Array[Vector3],
		[Vector3(0.3, 0.1, 0.0), Vector3(-0.1, -0.2, -0.5)] as Array[Vector3],
	]:
		if not _limb_ends_match(
			HumanParts.add_limb(parent_node, "Limb", points[0], points[1], 0.05, null, true),
			points[0], points[1],
		):
			ends_ok = false
	_check(ends_ok, "add_limb のカプセルの両端の丸みの中心が、斜め・真下向き・下へ斜めの 2 点に重なる")
	var zero_limb: MeshInstance3D = HumanParts.add_limb(
		parent_node, "Zero", Vector3(0.1, 0.1, 0.1), Vector3(0.1, 0.1, 0.1), 0.02, part_material,
		false,
	)
	_check(
		zero_limb.quaternion.is_equal_approx(Quaternion.IDENTITY)
		and zero_limb.position.is_equal_approx(Vector3(0.1, 0.1, 0.1)),
		"add_limb は長さ 0 の 2 点では回さず、その点に置く",
	)
	var sphere: MeshInstance3D = HumanParts.add_sphere(
		parent_node, "Sphere", Vector3(0.1, 0.2, 0.3), 0.15, Vector3(1.0, 2.0, 1.0), part_material,
		true,
	)
	var box: MeshInstance3D = HumanParts.add_box(
		parent_node, "Box", Vector3(-0.1, 0.4, 0.2), Vector3(0.3, 0.2, 0.1), part_material, false
	)
	_check(
		sphere.position.is_equal_approx(Vector3(0.1, 0.2, 0.3))
		and is_equal_approx((sphere.mesh as SphereMesh).radius, 0.15)
		and is_equal_approx((sphere.mesh as SphereMesh).height, 0.3)
		and sphere.scale.is_equal_approx(Vector3(1.0, 2.0, 1.0))
		and box.position.is_equal_approx(Vector3(-0.1, 0.4, 0.2))
		and (box.mesh as BoxMesh).size.is_equal_approx(Vector3(0.3, 0.2, 0.1)),
		"add_sphere・add_box は、渡した中心・半径・倍率・大きさで部品を置く",
	)
	_check(
		sphere.material_override == part_material
		and box.material_override == part_material
		and zero_limb.material_override == part_material,
		"人の体の部品は、渡したマテリアルで塗る",
	)
	_check(
		sphere.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		and (
			HumanParts.add_limb(
				parent_node, "ShadowLimb", Vector3.ZERO, Vector3.UP, 0.05, part_material, true
			).cast_shadow
			== GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		)
		and (
			HumanParts.add_box(
				parent_node, "ShadowBox", Vector3.ZERO, Vector3.ONE, part_material, true
			).cast_shadow
			== GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		)
		and box.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		and zero_limb.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"人の体の部品は、影を落とす引数が true の時だけ影を落とす",
	)
	parent_node.free()


## カプセルの部品 limb の両端の丸みの中心が、2 点 from・to に (どちらの向きでも) 重なるかを返す
static func _limb_ends_match(limb: MeshInstance3D, from: Vector3, to: Vector3) -> bool:
	var ends: Array[Vector3] = _limb_ends(limb)
	return (
		(
			ends[0].distance_to(from) < POSITION_TOLERANCE_M
			and ends[1].distance_to(to) < POSITION_TOLERANCE_M
		)
		or (
			ends[0].distance_to(to) < POSITION_TOLERANCE_M
			and ends[1].distance_to(from) < POSITION_TOLERANCE_M
		)
	)


## カプセルの部品 limb の、両端の丸みの中心の位置 (親の局所座標) を返す
static func _limb_ends(limb: MeshInstance3D) -> Array[Vector3]:
	var capsule: CapsuleMesh = limb.mesh as CapsuleMesh
	var half_axis: Vector3 = limb.quaternion * Vector3.UP * (capsule.height * 0.5 - capsule.radius)
	return [limb.position + half_axis, limb.position - half_axis]


## 買取業者が頭・胴・左右の腕と脚を持ち、頭が胴より上・胴が脚より上にあり、顔 (鼻) を部屋の中 (-Z) へ向けているか
func _check_trader_body() -> void:
	var tuning: MansionTuning = MansionTuningScript.new()
	tuning.room_count = 1
	tuning.object_count = 0
	var world: MansionWorld = MansionWorldScript.new()
	# 毛は買取業者の形に関わらないため、進行状態を渡さず毛 0 本で組み立てる
	world.rebuild(MansionBuilderScript.build_layout(tuning), null)
	var body: Node3D = world.get_node_or_null("Trader/Body")
	var parts_ok: bool = body != null
	if parts_ok:
		for part_name: String in [
			"Head", "Torso", "Hips", "Shoulders", "Neck", "Nose", "Hair", "Cap", "CapBrim",
			"LeftUpperArm", "RightUpperArm", "LeftForearm", "RightForearm", "LeftHand", "RightHand",
			"LeftLeg", "RightLeg", "LeftShoe", "RightShoe", "LeftEye", "RightEye", "LeftEar",
			"RightEar",
		]:
			if not body.get_node_or_null(part_name) is MeshInstance3D:
				parts_ok = false
	_check(
		parts_ok,
		"買取業者は頭・胴・腰・肩・首・顔 (鼻・目・耳)・髪・帽子と、左右の腕 (上腕・前腕・手)・脚・靴を持つ",
	)
	if parts_ok:
		var head: Node3D = body.get_node("Head")
		_check(
			head.position.y > body.get_node("Torso").position.y
			and body.get_node("Torso").position.y > body.get_node("LeftLeg").position.y
			and body.get_node("Torso").position.y > body.get_node("RightLeg").position.y
			# 頭は半径 0.5 の球を伸ばした部品で、倍率の Y の半分が頭の上端までの高さ
			# 頭の上端は背の高さ (帽子を除く) にそろえて置いた。背の高さは円柱だった時と同じ 1.6 m
			and absf(head.position.y + head.scale.y * 0.5 - 1.6) < POSITION_TOLERANCE_M
			and is_equal_approx(MansionWorldScript.TRADER_HEIGHT_M, 1.6)
			and body.get_node("Nose").position.z < head.position.z,
			"買取業者の頭は胴より上で上端が背の高さ 1.6 m にあり、胴は左右の脚より上にあり、顔を部屋の中 (-Z) へ向けている",
		)
		var shoe: MeshInstance3D = body.get_node("LeftShoe")
		_check(
			absf(shoe.position.y - (shoe.mesh as BoxMesh).size.y * 0.5) < POSITION_TOLERANCE_M,
			"買取業者の足元 (靴の底) は、立つ位置の原点 (床の高さ) にある",
		)
		var sides_ok: bool = true
		for part_name: String in ["UpperArm", "Forearm", "Hand", "Leg"]:
			if not (
				body.get_node("Left" + part_name).position.x < 0.0
				and body.get_node("Right" + part_name).position.x > 0.0
			):
				sides_ok = false
		_check(sides_ok, "買取業者の左の腕と脚は -X の側、右は +X の側に分かれて付いている")
		_check(
			body.get_node("Torso").cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			and body.get_node("Nose").cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"買取業者の胴は影を落とし、顔の小さな部品 (鼻) は影を落とさない",
		)
	world.free()

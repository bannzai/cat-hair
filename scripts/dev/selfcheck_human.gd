extends RefCounted
## 人の形 (画面に映る自分の手と腕・買取業者の体) の検証 (scripts/dev/selfcheck.gd から呼ぶ)。
## 描画は確かめず (CI の撮影で目視する)、置いたモデルの骨と範囲と、つまむ動きで指先が近づくことを確かめる。

## 画面に映る手のスクリプト
const HandViewScript := preload("res://scripts/player/hand_view.gd")
## 屋敷ビルダーロジックスクリプト
const MansionBuilderScript := preload("res://scripts/mansion/mansion_builder.gd")
## 屋敷のノードを組み立てるスクリプト
const MansionWorldScript := preload("res://scripts/mansion/mansion_world.gd")
## 屋敷の生成パラメータのスクリプト
const MansionTuningScript := preload("res://scripts/data/mansion_tuning.gd")
## 物の種別ごとのモデルと、モデルの範囲を測る関数
const FurnitureModels := preload("res://scripts/mansion/furniture_models.gd")
## 長さを同じとみなす誤差 (m)。モデルを合わせる寸法 (cm 単位) より十分小さく、浮動小数の丸めより大きい値
const POSITION_TOLERANCE_M: float = 0.001
## 閉じた親指と人差し指の先の中心どうしの距離の上限 (m)。2 本の先の太さの和 (約 1.5 cm) より近ければ触れて見える
const PINCH_CLOSED_MAX_M: float = 0.015
## 開いた親指と人差し指の先の中心どうしの距離の下限 (m)。毛をつまむ前に指の間が開いて見える幅 (約 4 cm)
const PINCH_OPEN_MIN_M: float = 0.04
## 自動化で走る掃除ロボットを作るスクリプト
const AutomationControllerScript := preload("res://scripts/automation/automation_controller.gd")
## 買取業者のモデル (顔・頭・耳・口・目の材質に写真のテクスチャが残っていないかを確かめる)
const TRADER_SCENE: PackedScene = preload("res://assets/models/buyer.glb")
## 写真から作られていた顔・頭・耳・口・目の材質の名前 (scripts/assets/convert_models.py の BUYER_FLAT_COLORS の鍵と同じ
## 名前を、実装の定数を読まずにここに書く。変換で名前が変わると見つからず落ちる)
const TRADER_PHOTO_MATERIAL_NAMES: Array[String] = [
	"headHDmale.000", "ear", "mouth2.000", "eye.000"
]
## 腕のモデル (肌の材質を確かめる)
const ARMS_SCENE: PackedScene = preload("res://assets/models/first_person_arms.glb")
## 腕の肌の粗さ。scripts/assets/convert_models.py の SKIN_ROUGHNESS と同じ値を、変換の定数を読まずにここに書く
## (Godot は Python の定数を読めず、glb の値と比べるため)
const ARM_SKIN_ROUGHNESS: float = 0.65
## 隠した骨とみなす縮めの上限。hand_view.gd の HIDDEN_BONE_SCALE より大きく、見える大きさ (1) より十分小さい
const HIDDEN_SCALE_MAX: float = 0.01

## 検証結果を記録する selfcheck の SceneTree 参照
var _checker: SceneTree = null


## 人の形の検証をすべて実行する
static func run_all(checker: SceneTree) -> void:
	var suite: RefCounted = load("res://scripts/dev/selfcheck_human.gd").new()
	suite._checker = checker
	suite._check_hand_view_shape_and_pinch()
	suite._check_trader_body()
	suite._check_trader_face_is_not_photo()
	suite._check_arm_skin_material()
	suite._check_furniture_models_fit_box()
	suite._check_robot_bumper_faces_forward()


## 検証結果を selfcheck 本体へ記録する
func _check(cond: bool, label: String) -> void:
	_checker._check(cond, label)


## 手が指の骨付きの腕のモデルで、引き始めは親指と人差し指の先が離れ、引く途中 (進み具合 1/3 以降) と
## 引き終えた時は 2 本の先が触れるか
func _check_hand_view_shape_and_pinch() -> void:
	# selfcheck は _initialize から同期で走り、root がまだツリーに入っていないため、手はツリーに入れずに
	# 作った時点のモデル (hand_view.gd の _init で置く) と、手の局所座標での位置で確かめる
	var hand: Node3D = HandViewScript.new()
	var skeletons: Array[Node] = hand.find_children("*", "Skeleton3D", true, false)
	var bones_ok: bool = skeletons.size() == 1
	if bones_ok:
		# 期待する骨は実装の定数から取らずにここに書き、モデルを替えて骨の名前が変わると落ちるようにする
		for bone_name: String in ["hand.R", "thumb.01.R", "thumb.03.R", "f_index.01.R", "f_index.03.R"]:
			if (skeletons[0] as Skeleton3D).find_bone(bone_name) < 0:
				bones_ok = false
	_check(bones_ok, "画面の手は、右手の親指と人差し指の骨を持つ腕のモデルで描く")
	var shadows_off: bool = true
	for part: Node in hand.find_children("*", "MeshInstance3D", true, false):
		if (part as MeshInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			shadows_off = false
	_check(shadows_off, "画面の手の部品は、カメラの近くで画面を暗くしないよう影を落とさない")
	if not bones_ok:
		hand.free()
		return
	_check(
		hand.position.is_equal_approx(HandViewScript.REST_POSITION)
		and is_equal_approx(hand.get_pull_progress(), 0.0),
		"作った直後の画面の手は、引いていない位置 (REST_POSITION) にある",
	)
	var skeleton: Skeleton3D = skeletons[0] as Skeleton3D
	hand.set_pull_progress(0.0)
	var open_tips: Dictionary = hand.get_fingertips()
	var open_distance: float = (open_tips["index"] as Vector3).distance_to(open_tips["thumb"])
	var open_index_pose: Quaternion = skeleton.get_bone_pose_rotation(
		skeleton.find_bone("f_index.01.R")
	)
	var open_thumb_pose: Quaternion = skeleton.get_bone_pose_rotation(
		skeleton.find_bone("thumb.01.R")
	)
	hand.set_pull_progress(1.0 / 3.0)
	_check(
		not skeleton.get_bone_pose_rotation(skeleton.find_bone("f_index.01.R")).is_equal_approx(
			open_index_pose
		)
		and not skeleton.get_bone_pose_rotation(skeleton.find_bone("thumb.01.R")).is_equal_approx(
			open_thumb_pose
		),
		"つまむ時は、モデルの親指と人差し指の付け根の骨の姿勢を回す",
	)
	var closed_tips: Dictionary = hand.get_fingertips()
	var closed_distance: float = (closed_tips["index"] as Vector3).distance_to(closed_tips["thumb"])
	_check(
		(open_tips["index"] as Vector3).y > (closed_tips["index"] as Vector3).y
		and (open_tips["thumb"] as Vector3).x < (closed_tips["thumb"] as Vector3).x,
		"毛をつまむ前は、人差し指の先を手の甲の側 (上) へ起こし、親指の先を外 (-X) へ開く",
	)
	var forward_tips: Dictionary = _fingertips_from_bone_poses(hand, skeleton)
	_check(
		(forward_tips["index"] as Vector3).distance_to(forward_tips["thumb"]) <= PINCH_CLOSED_MAX_M
		and (forward_tips["index"] as Vector3).is_equal_approx(closed_tips["index"])
		and (forward_tips["thumb"] as Vector3).is_equal_approx(closed_tips["thumb"]),
		"骨に設定した姿勢から順に辿って求めた指先も、閉じた時に触れ、手が返す指先の位置と一致する",
	)
	var forearm: int = skeleton.find_bone("forearm.R")
	_check(
		skeleton.get_bone_pose_scale(skeleton.find_bone("clavicle.L")).x <= HIDDEN_SCALE_MAX
		and skeleton.get_bone_pose_scale(skeleton.find_bone("hand.L.control")).x <= HIDDEN_SCALE_MAX
		and skeleton.get_bone_pose_scale(skeleton.find_bone("clavicle.R")).x <= HIDDEN_SCALE_MAX
		# 右の前腕と手は縮めない (休みの姿勢の倍率 1)。0.5 は縮めた骨 (HIDDEN_SCALE_MAX 以下) と取り違えない中ほどの値
		and skeleton.get_bone_parent(forearm) == -1
		and skeleton.get_bone_pose_scale(forearm).x > 0.5
		and skeleton.get_bone_pose_scale(skeleton.find_bone("hand.R")).x > 0.5
		and hand.get_node_or_null("Sleeve") is MeshInstance3D,
		"画面の手は左腕・左手・右の上腕の骨を縮めて隠し、右の前腕を残して肩から肘を袖で結ぶ",
	)
	hand.set_pull_progress(1.0)
	var pulled_tips: Dictionary = hand.get_fingertips()
	var pulled_distance: float = (pulled_tips["index"] as Vector3).distance_to(pulled_tips["thumb"])
	_check(
		open_distance >= PINCH_OPEN_MIN_M
		and closed_distance <= PINCH_CLOSED_MAX_M
		and is_equal_approx(pulled_distance, closed_distance),
		(
			"引き始めは親指と人差し指の先が %.3f m 以上離れ、引く途中 (1/3) と引き終えた時は %.3f m 以内に触れる"
			+ " (開き %.4f・途中 %.4f・終わり %.4f)"
		) % [PINCH_OPEN_MIN_M, PINCH_CLOSED_MAX_M, open_distance, closed_distance, pulled_distance],
	)
	hand.free()


## 骨に設定した姿勢 (get_bone_pose_rotation) から、親の休みの姿勢を辿って親指と人差し指の先を求め、手の局所座標で返す。
## 手の実装の計算 (get_fingertips) を使わず、骨に実際に入った回転から求める (付け根の骨だけを回し、先の骨は休みの姿勢)
func _fingertips_from_bone_poses(hand: Node3D, skeleton: Skeleton3D) -> Dictionary:
	var skeleton_to_hand: Transform3D = (
		hand.get_node("Arms").transform
		* FurnitureModels.transform_to_ancestor(skeleton, hand.get_node("Arms"))
	)
	var tips: Dictionary = {}
	for pair: Array in [
		["index", "f_index.01.R", "f_index.03.R"], ["thumb", "thumb.01.R", "thumb.03.R"]
	]:
		var root: int = skeleton.find_bone(pair[1])
		# 付け根の骨の局所での先の骨の先 (休みの姿勢の付け根の骨から見た位置) を、姿勢を入れた付け根の骨で動かす
		tips[pair[0]] = skeleton_to_hand * (
			(
				skeleton.get_bone_global_rest(skeleton.get_bone_parent(root))
				* Transform3D(
					Basis(skeleton.get_bone_pose_rotation(root)), skeleton.get_bone_rest(root).origin
				)
			)
			* (
				skeleton.get_bone_global_rest(root).affine_inverse()
				* _rest_bone_tip(skeleton, skeleton.find_bone(pair[2]))
			)
		)
	return tips


## 骨 bone の先の位置 (骨の空間。休みの姿勢)。子の骨があればその付け根、無ければ骨の +Y へ親からの長さだけ伸ばした位置
func _rest_bone_tip(skeleton: Skeleton3D, bone: int) -> Vector3:
	var children: PackedInt32Array = skeleton.get_bone_children(bone)
	var rest: Transform3D = skeleton.get_bone_global_rest(bone)
	if children.size() > 0:
		return skeleton.get_bone_global_rest(children[0]).origin
	return rest.origin + rest.basis.y.normalized() * skeleton.get_bone_rest(bone).origin.length()


## 腕のモデル (commit した first_person_arms.glb) の材質が、肌の写真を貼った金属でない肌か (変換で FBX の金属の値を
## 消した。消し忘れると肌が銅のように光る)
func _check_arm_skin_material() -> void:
	var model: Node3D = ARMS_SCENE.instantiate() as Node3D
	var skin_ok: bool = true
	var surfaces: int = 0
	for mesh_node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mesh_node as MeshInstance3D).mesh
		for surface: int in range(mesh.get_surface_count()):
			var material: StandardMaterial3D = mesh.surface_get_material(surface) as StandardMaterial3D
			surfaces += 1
			if (
				material == null
				or material.albedo_texture == null
				or not is_zero_approx(material.metallic)
				or absf(material.roughness - ARM_SKIN_ROUGHNESS) > 0.01
			):
				skin_ok = false
	_check(
		surfaces > 0 and skin_ok,
		"腕のモデルの材質は肌の写真を貼り、金属でなく (metallic 0)、粗さ %.2f の肌 (面 %d 個)"
		% [ARM_SKIN_ROUGHNESS, surfaces],
	)
	model.free()


## 買取業者のモデルの顔・頭・耳・口・目の材質に、写真のテクスチャが残っていないか (Steam で売る物に実在の人の顔を
## 出さないため単色に差し替えた。issue #15)
func _check_trader_face_is_not_photo() -> void:
	var model: Node3D = TRADER_SCENE.instantiate() as Node3D
	var found: Dictionary = {}
	var textured: Array[String] = []
	for mesh_node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mesh_node as MeshInstance3D).mesh
		for surface: int in range(mesh.get_surface_count()):
			var material: StandardMaterial3D = mesh.surface_get_material(surface) as StandardMaterial3D
			if material == null or not TRADER_PHOTO_MATERIAL_NAMES.has(material.resource_name):
				continue
			found[material.resource_name] = true
			if material.albedo_texture != null:
				textured.append(material.resource_name)
	_check(
		found.size() == TRADER_PHOTO_MATERIAL_NAMES.size() and textured.is_empty(),
		"買取業者の顔・頭・耳・口・目の材質 (%d / %d 個) に写真のテクスチャが無い (残っている: %s)"
		% [found.size(), TRADER_PHOTO_MATERIAL_NAMES.size(), ", ".join(textured)],
	)
	model.free()


## 既製のモデルで描く家具を、物の箱に合わせて置いた時、モデルの範囲が箱とそろい (大きさが同じ・底が 0・中心が原点)、
## モデルの無い種別では作らないか
func _check_furniture_models_fit_box() -> void:
	var box: Vector3 = Vector3(1.2, 0.7, 0.5)
	var fits_ok: bool = true
	var detail: PackedStringArray = []
	for kind: StringName in FurnitureModels.SCENES.keys():
		var fitted: Node3D = FurnitureModels.instantiate_fitted(kind, box)
		var bounds: AABB = fitted.transform * FurnitureModels.merged_mesh_aabb(fitted)
		var center: Vector3 = bounds.get_center()
		if (
			not bounds.size.is_equal_approx(box)
			or absf(bounds.position.y) > POSITION_TOLERANCE_M
			or absf(center.x) > POSITION_TOLERANCE_M
			or absf(center.z) > POSITION_TOLERANCE_M
		):
			fits_ok = false
			detail.append("%s: %s" % [kind, bounds])
		fitted.free()
	_check(
		FurnitureModels.SCENES.size() == 4 and fits_ok,
		"家具のモデル 4 種は、物の箱にちょうど収まり、底が床で中心が原点にそろう (ずれ: %s)" % ", ".join(detail),
	)
	# 範囲の合わせ方を、手で求めた範囲と比べる: 位置 (1, 0, 0)・倍率 2 の 1 m の箱 (範囲 x 0..2, y -1..1, z -1..1) と、
	# 位置 (0, 3, 0) の親の下の 1 m の箱 (範囲 x -0.5..0.5, y 2.5..3.5, z -0.5..0.5) を合わせると
	# x -0.5..2, y -1..3.5, z -1..1
	var probe_root: Node3D = Node3D.new()
	var scaled_box: MeshInstance3D = MeshInstance3D.new()
	scaled_box.mesh = BoxMesh.new()
	scaled_box.position = Vector3(1.0, 0.0, 0.0)
	scaled_box.scale = Vector3.ONE * 2.0
	probe_root.add_child(scaled_box)
	var raised_parent: Node3D = Node3D.new()
	raised_parent.position = Vector3(0.0, 3.0, 0.0)
	probe_root.add_child(raised_parent)
	var raised_box: MeshInstance3D = MeshInstance3D.new()
	raised_box.mesh = BoxMesh.new()
	raised_parent.add_child(raised_box)
	_check(
		FurnitureModels.merged_mesh_aabb(probe_root).is_equal_approx(
			AABB(Vector3(-0.5, -1.0, -1.0), Vector3(2.5, 4.5, 2.0))
		),
		"モデルの範囲は、子孫の全部のメッシュを親の位置・倍率を辿って合わせた範囲になる (%s)"
		% FurnitureModels.merged_mesh_aabb(probe_root),
	)
	# 祖先に着く前に Node3D でない親に当たる時は、そこまでの変換で止まる (素の Node の下の位置 (0, 3, 0) の親 → 子の
	# 位置 (1, 0, 0) なら (1, 3, 0)。祖先 probe_root の位置 (5, 0, 0) は足さない)
	var plain_parent: Node = Node.new()
	var mid: Node3D = Node3D.new()
	mid.position = Vector3(0.0, 3.0, 0.0)
	plain_parent.add_child(mid)
	var leaf: Node3D = Node3D.new()
	leaf.position = Vector3(1.0, 0.0, 0.0)
	mid.add_child(leaf)
	probe_root.position = Vector3(5.0, 0.0, 0.0)
	_check(
		FurnitureModels.transform_to_ancestor(leaf, probe_root).origin.is_equal_approx(
			Vector3(1.0, 3.0, 0.0)
		)
		and FurnitureModels.transform_to_ancestor(raised_box, probe_root).origin.is_equal_approx(
			Vector3(0.0, 3.0, 0.0)
		),
		"祖先への変換は、祖先に着いたら祖先の位置を含めずに止まり、Node3D でない親に当たったらそこで止まる",
	)
	plain_parent.free()
	probe_root.free()
	var empty_node: Node3D = Node3D.new()
	_check(
		FurnitureModels.instantiate_fitted(&"carpet", box) == null
		and FurnitureModels.merged_mesh_aabb(empty_node).size == Vector3.ZERO,
		"モデルの無い種別 (カーペット) では作らず、メッシュの無いノードの範囲は大きさ 0",
	)
	empty_node.free()


## 自動化で走る掃除ロボットの前の緩衝材が、走る向き (局所の -Z) の側にあるか
func _check_robot_bumper_faces_forward() -> void:
	var controller: Node3D = AutomationControllerScript.new()
	var robot: Node3D = controller._build_robot(0)
	var bumper: Node3D = robot.get_node_or_null("Body/Bumper")
	_check(
		bumper != null
		and (FurnitureModels.transform_to_ancestor(bumper, robot).origin.z < 0.0),
		"自動化で走る掃除ロボットの緩衝材は、走る向き (局所の -Z) の側にある",
	)
	robot.free()
	controller.free()


## 買取業者がモデルで描かれ、足元が床 (立つ位置の原点) にあり、背の高さが 1.6 m で、影を落とすか
func _check_trader_body() -> void:
	var tuning: MansionTuning = MansionTuningScript.new()
	tuning.room_count = 1
	tuning.object_count = 0
	var world: MansionWorld = MansionWorldScript.new()
	# 毛は買取業者の形に関わらないため、進行状態を渡さず毛 0 本で組み立てる
	world.rebuild(MansionBuilderScript.build_layout(tuning), null)
	var body: Node3D = world.get_node_or_null("Trader/Body")
	var meshes: Array[Node] = (
		[] if body == null else body.find_children("*", "MeshInstance3D", true, false)
	)
	_check(meshes.size() > 0, "買取業者は体のモデルで描く")
	if meshes.size() > 0:
		# 立つ位置 (Trader) の局所座標での体の範囲。Trader の札は体の外のため含めない
		var bounds: AABB = body.transform * FurnitureModels.merged_mesh_aabb(body)
		_check(
			absf(bounds.position.y) < POSITION_TOLERANCE_M
			and absf(bounds.end.y - 1.6) < POSITION_TOLERANCE_M
			and is_equal_approx(MansionWorldScript.TRADER_HEIGHT_M, 1.6),
			"買取業者の足元は立つ位置の原点 (床の高さ) にあり、頭の上端は背の高さ 1.6 m にある (下端 %.4f・上端 %.4f)"
			% [bounds.position.y, bounds.end.y],
		)
		# 立った人の体は腕や靴で左右前後に非対称なため、中心のずれは人の肩幅の 1/4 ほどの 0.1 m まで許す
		_check(
			absf(bounds.get_center().x) < 0.1 and absf(bounds.get_center().z) < 0.1,
			"買取業者の体の中心は、立つ位置の真上にある",
		)
		# モデルは glTF の +Z に顔を向ける。体の +Z が立つ位置の局所の -Z (部屋の中・札と同じ向き) を向いているか。
		# -0.5 は向きの単位ベクトルが -Z から 60 度以内にあることで、横 (90 度) や後ろを向いた時と見分けられる値
		_check(
			(body.basis * Vector3.BACK).normalized().z < -0.5,
			"買取業者のモデルの顔 (glTF の +Z) は、部屋の中 (立つ位置の局所の -Z) を向く",
		)
		var shadows_on: bool = true
		for mesh_node: Node in meshes:
			if (mesh_node as MeshInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				shadows_on = false
		_check(shadows_on, "買取業者の体は影を落とす")
	world.free()

extends Node3D
## 画面に映る自分の右手と腕。体の右肩から袖で腕を結び、つまんだ毛の先端に親指と人差し指を合わせる。
## 手は既製の 3D モデル (OpenGameArt の CC0 の腕の模型。指の骨付き。変換は scripts/assets/convert_models.py、
## 出典は assets/CREDITS.md) の右手で、ひじで折れる袖と手首へ細くなる前腕は基本の形で結ぶ (モデルの前腕は手と一緒に
## 動く硬い棒で、毛へ伸ばした手を肩からの視線の上で覆ったため。PR #69 の撮影)。モデルは変換で右手の頂点だけにしてある。
## 局所座標では手のひらを下 (-Y)・指先を奥 (-Z)・親指を左 (-X) に向け、指の付け根 (人差し指と小指の付け根の中点) を
## 原点に置き、手首から肘の側を手前 (+Z) に伸ばす。
## 腕の寸法・角度は、床と縦面の撮影で根元と指先を同時に追えるよう調整した値。

## 指に持たせる毛も、面の毛と同じメッシュで描く。
const HairFieldScript := preload("res://scripts/hair_field.gd")
## 人の体の部品を作る関数 (肩から肘の袖)
const HumanParts := preload("res://scripts/human/human_parts.gd")
## モデルの範囲と祖先への変換を測る関数
const FurnitureModels := preload("res://scripts/mansion/furniture_models.gd")
## 腕のモデル (glTF の骨の名前は Rigify の名前。右は末尾が .R)
const ARMS_SCENE: PackedScene = preload("res://assets/models/first_person_arms.glb")

## 肩につなぐ前の手の初期位置
const REST_POSITION: Vector3 = Vector3(0.30, -0.55, 0.0)
## 下ろした手が体の脇で下を向く角度。
const REST_ROTATION: Vector3 = Vector3(-1.2, 0.15, 0.0)
## 照準を右手で覆わず、毛先の左右に指が見える向き。
const PINCH_ROTATION: Vector3 = Vector3(-0.64, 0.65, -0.78)
## 一人称の腕が壁際で途切れないよう、腕と持った毛だけの描画深度を手前に寄せる。
const ARM_Z_CLIP_SCALE: float = 0.8
## 肩から肘までの上腕の長さ (m)。
const UPPER_ARM_M: float = 0.32
## 肘から手首までの前腕の長さ (m)。
const FOREARM_M: float = 0.27
## つまんだ時にも肘の曲がりを残す、肩から手首までの距離 (m)。
const BENT_REACH_M: float = 0.53
## 腕を下ろす前に、閉じた指先で抜いた毛をひと目確かめられる間を置く。
const SHOW_HAIR_SECONDS: float = 0.16
## 抜けた瞬間と腕を下ろす動きを別々に追える時間。
const RETURN_SECONDS: float = 0.24
## つまむ前の親指と人差し指の開き (rad)。閉じた形から、人差し指を手の甲の側へ起こし親指を外へ開く角度
const FINGER_OPEN_RAD: float = 0.55
## 肌の色 (右の前腕と体の左腕。右手はモデルの写真の肌)
const SKIN_COLOR: Color = Color(0.69, 0.45, 0.34)
## 袖の色
const SLEEVE_COLOR: Color = Color(0.25, 0.32, 0.45)
## 人差し指と小指の付け根の間の幅 (m)。大人の手の指の付け根の並び (人差し指から小指の中心まで) 5〜6 cm の見当で、
## モデルをこの幅になるよう縦横の釣り合いを保って縮める
const KNUCKLE_SPAN_M: float = 0.055
## 右手の手首の骨の名前
const WRIST_BONE: String = "hand.R"
## 右手の人差し指の付け根の骨の名前 (つまむ時に回す)
const INDEX_ROOT_BONE: String = "f_index.01.R"
## 右手の人差し指の先の骨の名前
const INDEX_TIP_BONE: String = "f_index.03.R"
## 右手の小指の付け根の骨の名前 (指の付け根の並びの向きと幅を測る)
const PINKY_ROOT_BONE: String = "f_pinky.01.R"
## 右手の親指の付け根の骨の名前 (つまむ時に回す)
const THUMB_ROOT_BONE: String = "thumb.01.R"
## 右手の親指の先の骨の名前
const THUMB_TIP_BONE: String = "thumb.03.R"

## 引いている進み具合 (0 = 開いた手、1 = つまんで引き終えた手)
var _pull_progress: float = 0.0
## 腕のモデルの骨
var _skeleton: Skeleton3D = null
## 骨の空間から手の局所座標への変換 (モデルの縮めと向きを含む)
var _skeleton_to_hand: Transform3D = Transform3D.IDENTITY
## 閉じた時に親指と人差し指の付け根の骨を回す回転 (骨の空間。休みの姿勢からの回転。骨の名前から引く)
var _closed_turns: Dictionary = {}
## 開く時に親指と人差し指を回す軸 (骨の空間。骨の名前から引く)。人差し指は手の +X (先を手の甲の側へ起こす)、
## 親指は手の +Y (先を外の -X へ開く)
var _open_axes: Dictionary = {}
## 今、親指と人差し指の付け根の骨に掛けている回転 (骨の空間。休みの姿勢からの回転。骨の名前から引く)
var _current_turns: Dictionary = {}
## 人差し指の先の位置の目印 (手の局所座標。指を回すたびに置き直す)
var _index_tip: Node3D
## 親指の先の位置の目印
var _thumb_tip: Node3D
## 手首の位置 (手の局所座標。手の骨の付け根)
var _wrist: Vector3 = Vector3.ZERO
## 体に追従する腕の付け根。
var _shoulder: Node3D
## 肩と肘の間を覆う袖。
var _sleeve: MeshInstance3D
## 肘から手首までの前腕。
var _forearm: MeshInstance3D
## 袖の上下をつなぐ肘の丸み。
var _elbow: MeshInstance3D
## 肘から袖口までを覆う布。
var _lower_sleeve: MeshInstance3D
## 袖口に付く折り返し。
var _cuff: MeshInstance3D
## 抜いた直後だけ指先に残す毛。
var _plucked: MeshInstance3D
## 抜いた毛を見せてから手を下ろすアニメーション。
var _retract: Tween


## 作った時に手を組み立てる (ツリーに入る前から骨と指先を辿れるようにするため、_ready ではなくここで組む)
func _init() -> void:
	_build()
	set_pull_progress(_pull_progress)


## つまむ動きが終わったら、引き切るまで指を閉じて保つ。指を閉じた割合を返す
func set_pull_progress(progress: float, reach_end: float = 1.0 / 3.0) -> float:
	_pull_progress = clampf(progress, 0.0, 1.0)
	var reach: float = smoothstep(0.0, reach_end, _pull_progress)
	_open_fingers(1.0 - reach)
	return reach


## 開き具合を 0 (閉) から 1 (開) の範囲で、親指と人差し指の付け根の骨に掛け、指先の目印を置き直す
func _open_fingers(amount: float) -> void:
	for bone_name: String in [INDEX_ROOT_BONE, THUMB_ROOT_BONE]:
		var turn: Quaternion = (
			Quaternion(_open_axes[bone_name] as Vector3, FINGER_OPEN_RAD * amount)
			* (_closed_turns[bone_name] as Quaternion)
		)
		_current_turns[bone_name] = turn
		var bone: int = _skeleton.find_bone(bone_name)
		_skeleton.set_bone_pose_rotation(
			bone,
			(
				_skeleton.get_bone_global_rest(_skeleton.get_bone_parent(bone)).basis.inverse()
				* Basis(turn)
				* _skeleton.get_bone_global_rest(bone).basis
			).get_rotation_quaternion()
		)
	# 指先の目印は骨の今の姿勢 (get_bone_global_pose) から読まない: ツリーの外で作った手では、set_bone_pose_rotation の
	# 後も get_bone_global_pose から求めた指先の距離が 0.0695 m のまま変わらなかった
	# (実測: PR #69 の CI の run 45949682800 の selfcheck)。付け根に掛けた回転で休みの姿勢の先を回して求める
	_index_tip.position = _skeleton_to_hand * _turned_tip(INDEX_ROOT_BONE, INDEX_TIP_BONE)
	_thumb_tip.position = _skeleton_to_hand * _turned_tip(THUMB_ROOT_BONE, THUMB_TIP_BONE)


## 右肩を起点にして腕を下ろす。手・袖ともカメラを回しても体に付いて歩く
func attach_to_shoulder(shoulder: Node3D) -> void:
	_shoulder = shoulder
	if _plucked != null:
		return
	_plucked = MeshInstance3D.new()
	_plucked.name = "PluckedHair"
	_plucked.mesh = HairFieldScript.build_hair_mesh()
	var held_material: StandardMaterial3D = HairFieldScript.build_hair_material()
	_set_arm_depth(held_material)
	_plucked.material_override = held_material
	_plucked.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_plucked.hide()
	add_child(_plucked)
	_rest()


## 人差し指と親指の先が触れる位置 (ワールド座標)
func get_pinch_position() -> Vector3:
	return (_index_tip.global_position + _thumb_tip.global_position) * 0.5


## 親指と人差し指の先の位置を、手の局所座標で返す
func get_fingertips() -> Dictionary:
	return {"index": _index_tip.position, "thumb": _thumb_tip.position}


## 肩から対象へ腕を伸ばし、指が閉じたら対象の毛と一緒に引く
func pinch_at(tip: Vector3, reach_end: float, progress: float) -> void:
	if _retract != null:
		_retract.kill()
		_retract = null
	_plucked.hide()
	var reach: float = set_pull_progress(progress, reach_end)
	var rest: Transform3D = _rest_transform()
	var pinch_basis: Basis = get_parent_node_3d().global_basis * Basis.from_euler(PINCH_ROTATION)
	var hand_scale: float = lerpf(1.0, _reach_scale(tip, pinch_basis), reach)
	global_basis = rest.basis.slerp(pinch_basis, reach).scaled(Vector3.ONE * hand_scale)
	var tip_offset: Vector3 = get_pinch_position() - global_position
	global_position = rest.origin.lerp(tip - tip_offset, reach)
	_pose_arm()


## 肘の曲がる範囲で視線と指先が交わる距離を求め、実際の毛先までの倍率を返す。
func _reach_scale(tip: Vector3, pinch_basis: Basis) -> float:
	var eye: Vector3 = get_parent_node_3d().global_position
	var ray: Vector3 = eye.direction_to(tip)
	if ray.is_zero_approx():
		return 1.0
	var wrist_offset: Vector3 = pinch_basis * (_wrist - to_local(get_pinch_position()))
	var offset: Vector3 = eye + wrist_offset - _shoulder.global_position
	var chord: float = sqrt(maxf(
		0.0, BENT_REACH_M * BENT_REACH_M - offset.slide(ray).length_squared()
	))
	# 手が目に触れるほど近い角度では、手のひらが画面をふさがない奥行きを保つ。
	return maxf(1.0, eye.distance_to(tip) / maxf(0.32, chord - offset.dot(ray)))


## 実際に抜けた毛のメッシュを同じ姿勢・色で指に持たせ、持ち上げてから腕を下ろす
func show_plucked(pose: Transform3D, color: Color) -> void:
	_plucked.global_transform = pose
	(_plucked.material_override as StandardMaterial3D).albedo_color = color
	_plucked.show()
	_pull_progress = 0.0
	_retract = create_tween()
	var snap: Vector3 = get_parent_node_3d().global_basis * Vector3(0.055, 0.045, 0.12)
	_retract.tween_method(_lift_step, global_position, global_position + snap, 0.075)
	_retract.tween_interval(SHOW_HAIR_SECONDS)
	_retract.tween_callback(_start_return)


## 抜いた毛を持ち上げる間も、動いた手首から肩まで腕を結ぶ。
func _lift_step(wrist_position: Vector3) -> void:
	global_position = wrist_position
	_pose_arm()


## 毛から指を離し、現在の姿勢から腕を下ろす
func return_to_side() -> void:
	_pull_progress = 0.0
	if _retract != null:
		_retract.kill()
	if _shoulder != null:
		_start_return()


## 毛を隠して指を開き、その姿勢から肩の脇まで戻す。
func _start_return() -> void:
	_plucked.hide()
	_open_fingers(1.0)
	_retract = create_tween()
	_retract.tween_method(_return_step.bind(global_transform), 0.0, 1.0, RETURN_SECONDS)
	_retract.tween_callback(_rest)


## 戻り始めの姿勢 start と現在の肩の間を、経過割合 weight で補間する。
func _return_step(weight: float, start: Transform3D) -> void:
	global_transform = start.interpolate_with(_rest_transform(), smoothstep(0.0, 1.0, weight))
	_pose_arm()


## 下ろした手が腰の外側に来る、右肩を基準にしたワールド姿勢。
func _rest_transform() -> Transform3D:
	return _shoulder.global_transform * Transform3D(
		Basis.from_euler(REST_ROTATION), Vector3(0.032, -0.65, -0.13)
	)


## 手を肩基準の待機姿勢に戻し、戻る動きの管理を終える。
func _rest() -> void:
	_retract = null
	_pull_progress = 0.0
	_open_fingers(1.0)
	global_transform = _rest_transform()
	_pose_arm()


## 手を下ろして歩く間も、体から肩と腕が離れないよう追従させる。
func _process(_delta: float) -> void:
	if _shoulder == null:
		return
	if _retract == null and _pull_progress == 0.0:
		global_transform = _rest_transform()
	_pose_arm()


## 指先を毛に合わせたまま、肩・肘・手首の三角形を上腕と前腕の長さから求める。
func _pose_arm() -> void:
	# 目を中心に全体を相似拡大すると、画面上の肩は元の位置に留まり、遠い面でも腕だけが伸びない。
	var eye: Vector3 = get_parent_node_3d().global_position
	var shoulder: Vector3 = to_local(
		eye + (_shoulder.global_position - eye) * global_basis.x.length()
	)
	var span: Vector3 = _wrist - shoulder
	var distance: float = maxf(span.length(), 0.001)
	var axis: Vector3 = span / distance
	var along: float = clampf(
		(distance * distance + UPPER_ARM_M * UPPER_ARM_M - FOREARM_M * FOREARM_M)
		/ (2.0 * distance), 0.0, UPPER_ARM_M
	)
	var bend: Vector3 = global_basis.inverse() * _shoulder.global_basis * Vector3(1, -0.65, 0.4)
	var elbow: Vector3 = shoulder + axis * along
	var offset: float = sqrt(maxf(0.0, UPPER_ARM_M * UPPER_ARM_M - along * along))
	elbow += bend.slide(axis).normalized() * offset
	_fit_arm_section(_sleeve, shoulder, elbow)
	var sleeve_end: Vector3 = elbow.lerp(_wrist, 0.48)
	_fit_arm_section(_lower_sleeve, elbow, sleeve_end)
	_fit_arm_section(_cuff, elbow.lerp(sleeve_end, 0.80), sleeve_end)
	_fit_arm_section(_forearm, sleeve_end, _wrist)
	_elbow.position = elbow


## 筒の両端を関節に合わせる。輪郭の太さはメッシュで決まり、長さだけを変える。
static func _fit_arm_section(part: MeshInstance3D, start: Vector3, end: Vector3) -> void:
	var direction: Vector3 = end - start
	part.position = (start + end) * 0.5
	part.quaternion = Quaternion(Vector3.UP, direction.normalized())
	part.scale = Vector3(1.0, direction.length(), 1.0)


## 上腕、袖口、前腕を、それぞれ先端に向かって細くなる形で作る。
func _arm_section(part_name: String, base_radius: float, end_radius: float,
		material: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.height = 1.0
	mesh.bottom_radius = base_radius
	mesh.top_radius = end_radius
	var part := MeshInstance3D.new()
	part.name = part_name
	part.mesh = mesh
	part.material_override = material
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(part)
	return part


## 現在の引いている進み具合を返す
func get_pull_progress() -> float:
	return _pull_progress


## 深度だけを変えるので、指先は画面で毛先に重なり、指や袖同士の前後関係も保たれる。
## 出典: https://github.com/godotengine/godot/blob/4.7-stable/doc/classes/BaseMaterial3D.xml#L489
static func _set_arm_depth(material: StandardMaterial3D) -> void:
	material.use_z_clip_scale = true
	material.z_clip_scale = ARM_Z_CLIP_SCALE


## 付け根の骨 root_bone を今の回転で回した時の、先の骨 tip_bone の先の位置 (骨の空間)
func _turned_tip(root_bone: String, tip_bone: String) -> Vector3:
	var head: Vector3 = _bone_head(root_bone)
	return head + (_current_turns[root_bone] as Quaternion) * (_bone_tip(tip_bone) - head)


## 腕のモデルを置き、左腕と右の上腕を隠し、手の向きと大きさを合わせ、閉じた時の指の姿勢を求め、袖と指先の目印を足す
## (影は落とさない。カメラの近くで画面を暗くしないため)
func _build() -> void:
	position = REST_POSITION
	rotation = REST_ROTATION
	var model: Node3D = ARMS_SCENE.instantiate() as Node3D
	model.name = "Arms"
	add_child(model)
	_skeleton = model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	# 手のモデルの材質も袖と同じ描画深度にし、壁際で手首から先だけが壁に隠れないようにする
	for mesh_node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var hand_mesh: MeshInstance3D = mesh_node as MeshInstance3D
		hand_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for surface: int in range(hand_mesh.mesh.get_surface_count()):
			var hand_material: StandardMaterial3D = (
				hand_mesh.mesh.surface_get_material(surface).duplicate() as StandardMaterial3D
			)
			_set_arm_depth(hand_material)
			hand_mesh.set_surface_override_material(surface, hand_material)
	# 手の局所の向きを骨の空間で作る: 指先の向き (手首から指の付け根) を -Z、小指から人差し指の向きを -X にする
	var index_root: Vector3 = _bone_head(INDEX_ROOT_BONE)
	var pinky_root: Vector3 = _bone_head(PINKY_ROOT_BONE)
	var knuckles: Vector3 = (index_root + pinky_root) * 0.5
	var forward: Vector3 = (knuckles - _bone_head(WRIST_BONE)).normalized()
	var to_index: Vector3 = (index_root - pinky_root)
	var x_axis: Vector3 = -(to_index - forward * to_index.dot(forward)).normalized()
	var z_axis: Vector3 = -forward
	var hand_frame: Basis = Basis(x_axis, z_axis.cross(x_axis), z_axis)
	var scale_factor: float = KNUCKLE_SPAN_M / to_index.length()
	# 骨の空間の点 p は、手の局所で hand_frame^-1 * (p - knuckles) * scale_factor の位置に来るようにする
	_skeleton_to_hand = Transform3D(
		hand_frame.inverse().scaled(Vector3.ONE * scale_factor),
		hand_frame.inverse() * (-knuckles) * scale_factor,
	)
	model.transform = (
		_skeleton_to_hand
		* FurnitureModels.transform_to_ancestor(_skeleton, model).affine_inverse()
	)
	_wrist = _skeleton_to_hand * _bone_head(WRIST_BONE)

	var skin: StandardMaterial3D = StandardMaterial3D.new()
	skin.albedo_color = SKIN_COLOR
	skin.roughness = 0.8
	var sleeve: StandardMaterial3D = StandardMaterial3D.new()
	sleeve.albedo_color = SLEEVE_COLOR
	sleeve.roughness = 0.9
	var cuff: StandardMaterial3D = sleeve.duplicate()
	cuff.albedo_color = SLEEVE_COLOR.lightened(0.13)
	for material: StandardMaterial3D in [skin, sleeve, cuff]:
		_set_arm_depth(material)
	_sleeve = _arm_section("Sleeve", 0.071, 0.053, sleeve)
	_lower_sleeve = _arm_section("LowerSleeve", 0.053, 0.042, sleeve)
	_cuff = _arm_section("Cuff", 0.045, 0.043, cuff)
	_forearm = _arm_section("Forearm", 0.035, 0.027, skin)
	_elbow = HumanParts.add_sphere(self, "Elbow", Vector3.ZERO, 0.053, Vector3.ONE, sleeve, false)
	_index_tip = Node3D.new()
	_index_tip.name = "IndexTip"
	add_child(_index_tip)
	_thumb_tip = Node3D.new()
	_thumb_tip.name = "ThumbTip"
	add_child(_thumb_tip)

	_closed_turns = _solve_pinch()
	_open_axes = {
		INDEX_ROOT_BONE: (hand_frame * Vector3.RIGHT).normalized(),
		THUMB_ROOT_BONE: (hand_frame * Vector3.UP).normalized(),
	}


## 親指と人差し指の付け根の骨を、それぞれ付け根の周りに回して、2 本の先が 1 点で触れる回転 (骨の空間) を返す。
## 指の曲がり (付け根から先の骨の休みの姿勢) は変えず、指を丸ごと回す。2 本の先が付け根から届く距離の球が交わる円の上で、
## 休みの姿勢の 2 本の先の中点に最も近い点を触れる点にする
func _solve_pinch() -> Dictionary:
	var thumb_base: Vector3 = _bone_head(THUMB_ROOT_BONE)
	var index_base: Vector3 = _bone_head(INDEX_ROOT_BONE)
	var thumb_tip: Vector3 = _bone_tip(THUMB_TIP_BONE)
	var index_tip: Vector3 = _bone_tip(INDEX_TIP_BONE)
	var thumb_reach: float = thumb_base.distance_to(thumb_tip)
	var index_reach: float = index_base.distance_to(index_tip)
	var axis: Vector3 = index_base - thumb_base
	var base_distance: float = axis.length()
	axis /= base_distance
	var along: float = (
		(thumb_reach * thumb_reach - index_reach * index_reach + base_distance * base_distance)
		/ (2.0 * base_distance)
	)
	var middle: Vector3 = (thumb_tip + index_tip) * 0.5 - thumb_base
	var contact: Vector3 = (
		thumb_base
		+ axis * along
		+ (
			(middle - axis * middle.dot(axis)).normalized()
			* sqrt(maxf(0.0, thumb_reach * thumb_reach - along * along))
		)
	)
	return {
		THUMB_ROOT_BONE: Quaternion(
			(thumb_tip - thumb_base).normalized(), (contact - thumb_base).normalized()
		),
		INDEX_ROOT_BONE: Quaternion(
			(index_tip - index_base).normalized(), (contact - index_base).normalized()
		),
	}


## 骨の付け根の位置 (骨の空間。休みの姿勢)
func _bone_head(bone_name: String) -> Vector3:
	return _skeleton.get_bone_global_rest(_skeleton.find_bone(bone_name)).origin


## 骨の先の位置 (骨の空間。休みの姿勢)。glTF の骨は先の位置を持たないため、子の骨があればその付け根、
## 無ければ親から自分への長さだけ骨の +Y へ伸ばした位置とする (Blender の骨は +Y が付け根から先の向き)
func _bone_tip(bone_name: String) -> Vector3:
	var bone: int = _skeleton.find_bone(bone_name)
	var children: PackedInt32Array = _skeleton.get_bone_children(bone)
	var rest: Transform3D = _skeleton.get_bone_global_rest(bone)
	if not children.is_empty():
		return _skeleton.get_bone_global_rest(children[0]).origin
	return rest.origin + rest.basis.y.normalized() * _skeleton.get_bone_rest(bone).origin.length()

extends Node3D
## 一人称カメラの子に置き、画面の右下に映る自分の右手と腕。毛を引いている間は親指と人差し指を閉じて手前へ引く。
## 形は既製の 3D モデル (OpenGameArt の CC0 の腕の模型。指の骨付き。変換は scripts/assets/convert_models.py、
## 出典は assets/CREDITS.md) の右腕で、左腕は骨を縮めて隠す。
## 局所座標では手のひらを下 (-Y)・指先を奥 (-Z)・親指を左 (-X) に向け、指の付け根 (人差し指と小指の付け根の中点) を
## 原点に置き、手首から肘の側を手前 (+Z) に伸ばす。
## 位置・距離・角度は、CI の 1280x720 の撮影で手首から先が画面の右下 1/4 に収まり、引く動きが見て分かる
## 大きさにした仮の値 (実機での見え方は「ユーザー作業の一覧」issue #5 の項目で確かめる)。

## モデルの範囲と祖先への変換を測る関数
const FurnitureModels := preload("res://scripts/mansion/furniture_models.gd")
## 腕のモデル (glTF の骨の名前は Rigify の名前。右は末尾が .R)
const ARMS_SCENE: PackedScene = preload("res://assets/models/first_person_arms.glb")
## 手を置く位置 (カメラの局所座標。画面の右下に手首から先が映る位置)
const REST_POSITION: Vector3 = Vector3(0.2, -0.2, -0.42)
## 手の向き (手のひらを下に、指先を画面の奥・やや左に向ける)
const REST_ROTATION: Vector3 = Vector3(-0.35, 0.35, 0.0)
## 引き終わる時に手を手前へ引く距離 (m。カメラの局所 +Z)
const PULL_BACK_M: float = 0.07
## 引き終わる時に手を持ち上げる距離 (m)
const PULL_UP_M: float = 0.03
## 人差し指と小指の付け根の間の幅 (m)。大人の手の指の付け根の並び (人差し指から小指の中心まで) 5〜6 cm の見当で、
## モデルをこの幅になるよう縦横の釣り合いを保って縮める
const KNUCKLE_SPAN_M: float = 0.055
## つまむ前の親指と人差し指の開き (rad)。閉じた形から、人差し指を手の甲の側へ起こし親指を外へ開く角度
const FINGER_OPEN_RAD: float = 0.55
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
## 隠す左腕の付け根の骨 (この骨を縮めると、子の前腕・手・指も縮む)
const HIDDEN_ARM_BONE: String = "upper_arm.L"
## 隠す骨の縮め方。0 にすると骨の行列が逆にできず警告が出る場合があるため、見えないほど小さい値にする
const HIDDEN_BONE_SCALE: float = 0.0001

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


## 作った時に手を組み立てる (ツリーに入る前から骨と指先を辿れるようにするため、_ready ではなくここで組む)
func _init() -> void:
	_build()
	set_pull_progress(_pull_progress)


## 引いている進み具合 (0〜1) に合わせて指の開きと手の位置を変える
func set_pull_progress(progress: float) -> void:
	_pull_progress = clampf(progress, 0.0, 1.0)
	position = REST_POSITION + Vector3(0.0, PULL_UP_M, PULL_BACK_M) * _pull_progress
	if _skeleton == null:
		return
	# 引き始めの 1/3 で閉じ切り、残りは閉じたまま手前へ引く
	var open_amount: float = 1.0 - minf(1.0, _pull_progress * 3.0)
	for bone_name: String in [INDEX_ROOT_BONE, THUMB_ROOT_BONE]:
		var turn: Quaternion = (
			Quaternion(_open_axes[bone_name] as Vector3, FINGER_OPEN_RAD * open_amount)
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


## 現在の引いている進み具合を返す
func get_pull_progress() -> float:
	return _pull_progress


## 親指 (THUMB_TIP_BONE の先) と人差し指 (INDEX_TIP_BONE の先) の先の位置を、手の局所座標で返す。
## 指の付け根の骨に掛けた回転 (_current_turns) で休みの姿勢の先を回して求める。骨の今の姿勢
## (get_bone_global_pose) は読まない: ツリーの外で作った手では、set_bone_pose_rotation の後も get_bone_global_pose から
## 求めた指先の距離が 0.0695 m のまま変わらなかった (実測: PR #69 の CI の run 45949682800 の selfcheck)
func get_fingertips() -> Dictionary:
	return {
		"index": _skeleton_to_hand * _turned_tip(INDEX_ROOT_BONE, INDEX_TIP_BONE),
		"thumb": _skeleton_to_hand * _turned_tip(THUMB_ROOT_BONE, THUMB_TIP_BONE),
	}


## 付け根の骨 root_bone を今の回転で回した時の、先の骨 tip_bone の先の位置 (骨の空間)
func _turned_tip(root_bone: String, tip_bone: String) -> Vector3:
	var head: Vector3 = _bone_head(root_bone)
	return head + (_current_turns[root_bone] as Quaternion) * (_bone_tip(tip_bone) - head)


## 腕のモデルを置き、左腕を隠し、手の向きと大きさを合わせ、閉じた時の指の姿勢を求める (影は落とさない。
## カメラの近くで画面を暗くしないため)
func _build() -> void:
	rotation = REST_ROTATION
	var model: Node3D = ARMS_SCENE.instantiate() as Node3D
	model.name = "Arms"
	add_child(model)
	_skeleton = model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	for mesh_node: Node in model.find_children("*", "MeshInstance3D", true, false):
		(mesh_node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_skeleton.set_bone_pose_scale(
		_skeleton.find_bone(HIDDEN_ARM_BONE), Vector3.ONE * HIDDEN_BONE_SCALE
	)

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
	var pose: Transform3D = _skeleton.get_bone_global_rest(bone)
	if not children.is_empty():
		return _skeleton.get_bone_global_rest(children[0]).origin
	return pose.origin + pose.basis.y.normalized() * _skeleton.get_bone_rest(bone).origin.length()


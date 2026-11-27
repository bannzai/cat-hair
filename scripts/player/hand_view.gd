extends Node3D
## 体の右肩から手首へ腕を結び、つまんだ毛の先端に親指と人差し指を合わせる。
## 腕と手の寸法・角度・色は、床と縦面の撮影で根元と指先を同時に追えるよう調整した値。

## 指に持たせる毛も、面の毛と同じメッシュで描く。
const HairFieldScript := preload("res://scripts/hair_field.gd")
## 人の体の部品を作る関数
const HumanParts := preload("res://scripts/human/human_parts.gd")

## 肩につなぐ前の手の初期位置
const REST_POSITION: Vector3 = Vector3(0.30, -0.55, 0.0)
## 下ろした手が体の脇で下を向く角度。
const REST_ROTATION: Vector3 = Vector3(-1.2, 0.15, 0.0)
## 照準を右手で覆わず、毛先の左右に指が見える向き。
const PINCH_ROTATION: Vector3 = Vector3(-0.40, 1.05, -0.28)
## 腕を下ろす前に、閉じた指先で抜いた毛をひと目確かめられる間を置く。
const SHOW_HAIR_SECONDS: float = 0.16
## 抜けた瞬間と腕を下ろす動きを別々に追える時間。
const RETURN_SECONDS: float = 0.24
## つまむ前の親指と人差し指の開き (rad)
const FINGER_OPEN_RAD: float = 0.55
## 肌の色
const SKIN_COLOR: Color = Color(0.93, 0.74, 0.62)
## 袖の色
const SLEEVE_COLOR: Color = Color(0.25, 0.32, 0.45)
## 親指以外の 4 本の指のノード名 (人差し指・中指・薬指・小指の順。下の指ごとの表も同じ順)
const FINGER_NAMES: Array[String] = ["IndexFinger", "MiddleFinger", "RingFinger", "LittleFinger"]
## 親指以外の 4 本の指の、付け根の左右の位置 (m)
const FINGER_BASE_X_M: Array[float] = [-0.027, -0.009, 0.009, 0.026]
## 親指以外の 4 本の指の、付け根から指先への 3 節の長さ (m。
## 大人の手の指の長さ 6〜8 cm を、中指を最も長く、小指を最も短くして割り振った見当)
const FINGER_SEGMENT_M: Array[Vector3] = [
	Vector3(0.038, 0.024, 0.02),
	Vector3(0.042, 0.027, 0.021),
	Vector3(0.039, 0.025, 0.02),
	Vector3(0.031, 0.02, 0.017),
]
## 親指以外の 4 本の指の太さ (半径 m。大人の指の幅 1.5〜1.8 cm の見当で、
## 中指を最も太く、小指を最も細くした。付け根の間隔 1.8 cm に対して指どうしの隙間がほとんど空かず、揃えた指に見える)
const FINGER_RADIUS_M: Array[float] = [0.0085, 0.0088, 0.0082, 0.0072]
## 親指以外の 4 本の指の関節 1 つごとの曲げ (rad。
## 人差し指はつまむために伸ばし気味に、ほかの 3 本は力を抜いて手のひらの側へ軽く曲げる)
const FINGER_CURL_RAD: Array[float] = [0.18, 0.38, 0.45, 0.5]
## 親指の付け根 (手首の近くの、手のひらの左下) から指先への 3 節の長さ (m)。付け根の骨を含む親指の長さ 11〜12 cm の見当で、
## 閉じた時に指先が人差し指の先に届く長さ (下の THUMB_AIM と合わせ、2 本の先の中心が約 7 mm まで近づく。
## 指の太さの和より近く、先どうしが触れて見える。scripts/dev/selfcheck_human.gd が組み立てた手で確かめる)
const THUMB_SEGMENT_M: Vector3 = Vector3(0.05, 0.038, 0.03)
## 親指の付け根の位置 (手首の近くの、手のひらの左下)
const THUMB_BASE_POSITION: Vector3 = Vector3(-0.036, -0.012, 0.045)
## 親指を閉じた時に向ける向き (付け根から、閉じた人差し指の先の少し左下へ向かう向き)
const THUMB_AIM: Vector3 = Vector3(0.0, -0.0135, -0.122)
## 親指の関節 1 つごとの、人差し指の側 (+X) への曲げ (rad。強く曲げると先が人差し指の先から右へ外れるため、わずかにする)
const THUMB_CURL_RAD: float = 0.02

## 引いている進み具合 (0 = 開いた手、1 = つまんで引き終えた手)
var _pull_progress: float = 0.0
## 人差し指の付け根のノード (開き具合で回す)
var _index_finger: Node3D = null
## 親指の付け根のノード (開き具合で回す)
var _thumb: Node3D = null

## 人差し指の末節の先端。
var _index_tip: Node3D
## 親指の末節の先端。
var _thumb_tip: Node3D
## 体に追従する腕の付け根。
var _shoulder: Node3D
## 肩と肘の間を覆う袖。
var _sleeve: MeshInstance3D
## 肘から手首までの前腕。
var _forearm: MeshInstance3D
## 抜いた直後だけ指先に残す毛。
var _plucked: MeshInstance3D
## 抜いた毛を見せてから手を下ろすアニメーション。
var _retract: Tween


## 作った時に手の形を組み立てる (ツリーに入る前から指の部品を辿れるようにするため、_ready ではなくここで組む)
func _init() -> void:
	_build()
	set_pull_progress(_pull_progress)


## つまむ動きが終わったら、引き切るまで指を閉じて保つ。指を閉じた割合を返す
func set_pull_progress(progress: float, reach_end: float = 1.0 / 3.0) -> float:
	_pull_progress = clampf(progress, 0.0, 1.0)
	var reach: float = smoothstep(0.0, reach_end, _pull_progress)
	_open_fingers(1.0 - reach)
	return reach


## 開き具合を 0（閉）から 1（開）の範囲で両指に反映する。
func _open_fingers(amount: float) -> void:
	var open_rad: float = FINGER_OPEN_RAD * amount
	# 開いている時は人差し指を手の甲の側 (+Y) へ起こし、親指を外 (-X) へ開く。閉じると 2 本の先が近づく
	_index_finger.rotation = Vector3(open_rad * 0.5, 0.0, 0.0)
	_thumb.rotation = Vector3(0.0, open_rad, 0.0)


## 右肩を起点にして腕を下ろす。手・袖ともカメラを回しても体に付いて歩く
func attach_to_shoulder(shoulder: Node3D) -> void:
	_shoulder = shoulder
	if _plucked != null:
		return
	_plucked = MeshInstance3D.new()
	_plucked.name = "PluckedHair"
	_plucked.mesh = HairFieldScript.build_hair_mesh()
	_plucked.material_override = HairFieldScript.build_hair_material()
	_plucked.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_plucked.hide()
	add_child(_plucked)
	_rest()


## 描画した人差し指と親指の腹が触れる位置（ワールド座標）
func get_pinch_position() -> Vector3:
	return (_index_tip.global_position + _thumb_tip.global_position) * 0.5


## 肩から対象へ腕を伸ばし、指が閉じたら対象の毛と一緒に引く
func pinch_at(tip: Vector3, reach_end: float, progress: float) -> void:
	if _retract != null:
		_retract.kill()
		_retract = null
	_plucked.hide()
	var reach: float = set_pull_progress(progress, reach_end)
	var rest: Transform3D = _rest_transform()
	var pinch_basis: Basis = get_parent_node_3d().global_basis * Basis.from_euler(PINCH_ROTATION)
	global_basis = rest.basis.slerp(pinch_basis, reach)
	var tip_offset: Vector3 = get_pinch_position() - global_position
	global_position = rest.origin.lerp(tip - tip_offset, reach)
	_pose_arm()


## 実際に抜けた毛のメッシュを同じ姿勢・色で指に持たせ、持ち上げてから腕を下ろす
func show_plucked(pose: Transform3D, color: Color) -> void:
	_plucked.global_transform = pose
	(_plucked.material_override as StandardMaterial3D).albedo_color = color
	_plucked.show()
	_pull_progress = 0.0
	_retract = create_tween()
	var snap: Vector3 = get_parent_node_3d().global_basis * Vector3(0.055, 0.045, 0.12)
	_retract.tween_property(self, "global_position", global_position + snap, 0.075)
	_retract.tween_interval(SHOW_HAIR_SECONDS)
	_retract.tween_callback(_start_return)


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


## 下ろした手が腰の外側に来る、右肩を基準にしたワールド姿勢。
func _rest_transform() -> Transform3D:
	return _shoulder.global_transform * Transform3D(
		Basis.from_euler(REST_ROTATION), Vector3(0.065, -0.54, -0.07)
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


## 手首から肩への途中に肘の曲がりを残し、どの面でも腕が途中で切れないようにする
func _pose_arm() -> void:
	var wrist := Vector3(0.0, 0.0, 0.085)
	var shoulder: Vector3 = to_local(_shoulder.global_position)
	var elbow: Vector3 = shoulder.lerp(wrist, 0.51)
	elbow += global_basis.inverse() * _shoulder.global_basis * Vector3(0.11, -0.08, 0.02)
	HumanParts.pose_limb(_sleeve, shoulder, elbow)
	HumanParts.pose_limb(_forearm, elbow, wrist)


## 現在の引いている進み具合を返す
func get_pull_progress() -> float:
	return _pull_progress


## 袖・前腕・手のひら・指を組み立てる (影は落とさない。カメラの近くで画面を暗くしないため)
func _build() -> void:
	position = REST_POSITION
	rotation = REST_ROTATION
	var skin: StandardMaterial3D = StandardMaterial3D.new()
	skin.albedo_color = SKIN_COLOR
	skin.roughness = 0.8
	var sleeve: StandardMaterial3D = StandardMaterial3D.new()
	sleeve.albedo_color = SLEEVE_COLOR
	sleeve.roughness = 0.9

	# 袖は手首の少し手前から肘の側へ、画面の外まで伸ばす。前腕は袖口から手首まで見える
	_sleeve = HumanParts.add_limb(
		self, "Sleeve", Vector3(0.0, 0.006, 0.15), Vector3(0.0, 0.02, 0.42), 0.042, sleeve, false
	)
	_forearm = HumanParts.add_limb(
		self, "Forearm", Vector3(0.0, 0.0, 0.085), Vector3(0.0, 0.006, 0.17), 0.026, skin, false
	)
	# 手のひらは平たく潰した球で、指の付け根の関節の並び (拳の山) を横に渡したカプセルで足す
	HumanParts.add_sphere(
		self, "Palm", Vector3(0.0, 0.0, 0.04), 0.5, Vector3(0.078, 0.03, 0.1), skin, false
	)
	HumanParts.add_limb(
		self, "Knuckles", Vector3(-0.027, 0.002, 0.0), Vector3(0.026, 0.002, 0.0), 0.011, skin, false
	)
	# 親指の付け根のふくらみ
	HumanParts.add_sphere(
		self, "ThumbBase", Vector3(-0.026, -0.008, 0.045), 0.5, Vector3(0.032, 0.026, 0.05), skin, false
	)
	for finger_idx: int in range(FINGER_NAMES.size()):
		var finger_root: Node3D = Node3D.new()
		finger_root.name = FINGER_NAMES[finger_idx]
		finger_root.position = Vector3(FINGER_BASE_X_M[finger_idx], 0.0, 0.0)
		add_child(finger_root)
		var tip: Node3D = _add_finger_segments(
			finger_root, FINGER_SEGMENT_M[finger_idx], FINGER_RADIUS_M[finger_idx],
			Vector3(-FINGER_CURL_RAD[finger_idx], 0.0, 0.0), skin,
		)
		if finger_idx == 0:
			_index_finger = finger_root
			_index_tip = tip
	_thumb = Node3D.new()
	_thumb.name = "Thumb"
	_thumb.position = THUMB_BASE_POSITION
	add_child(_thumb)
	var thumb_aim: Node3D = Node3D.new()
	thumb_aim.name = "Aim"
	thumb_aim.basis = Basis.looking_at(THUMB_AIM, Vector3.UP)
	_thumb.add_child(thumb_aim)
	# 親指は人差し指より太い (半径 1 cm 強)
	_thumb_tip = _add_finger_segments(
		thumb_aim, THUMB_SEGMENT_M, 0.0105, Vector3(0.0, -THUMB_CURL_RAD, 0.0), skin
	)


## 付け根 root から局所の -Z へ、長さ segment_lengths の 3 節の指を足す。節ごとに関節で joint_bend だけ曲げ、
## 先の節ほど細くする
static func _add_finger_segments(
	root: Node3D, segment_lengths: Vector3, radius: float, joint_bend: Vector3, skin: Material
) -> Node3D:
	var joint: Node3D = root
	for segment_idx: int in range(3):
		var bent: Node3D = Node3D.new()
		bent.name = "Joint%d" % segment_idx
		bent.rotation = joint_bend
		joint.add_child(bent)
		var length: float = segment_lengths[segment_idx]
		# 先の節ほど 1 割ずつ細くし、指先がすぼまって見えるようにする
		HumanParts.add_limb(
			bent, "Segment", Vector3.ZERO, Vector3(0.0, 0.0, -length),
			radius * (1.0 - 0.1 * float(segment_idx)), skin, false,
		)
		var tip: Node3D = Node3D.new()
		tip.name = "End"
		tip.position = Vector3(0.0, 0.0, -length)
		bent.add_child(tip)
		joint = tip
	return joint

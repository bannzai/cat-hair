extends Node3D
## 体の右肩から手首へ腕を結び、つまんだ毛の先端に親指と人差し指を合わせる。
## つまむ指の腹、手首へ細くなる前腕、ひじで折れる袖を一続きに描く。

## 指に持たせる毛も、面の毛と同じメッシュで描く。
const HairFieldScript := preload("res://scripts/hair_field.gd")
## 人の体の部品を作る関数
const HumanParts := preload("res://scripts/human/human_parts.gd")

## 肩につなぐ前の手の初期位置
const REST_POSITION: Vector3 = Vector3(0.30, -0.55, 0.0)
## 下ろした手が体の脇で下を向く角度。
const REST_ROTATION: Vector3 = Vector3(-1.2, 0.15, 0.0)
## 照準を右手で覆わず、毛先の左右に指が見える向き。
const PINCH_ROTATION: Vector3 = Vector3(-0.16, 0.83, -0.57)
## 肩から肘、肘から手首までの長さ (m)。
const UPPER_ARM_M: float = 0.32
const FOREARM_M: float = 0.27
## つまんだ時にも肘の曲がりを残す、肩から手首までの距離 (m)。
const BENT_REACH_M: float = 0.53
## 腕が手のひらにつながる位置。
const WRIST: Vector3 = Vector3(0.0, 0.0, 0.082)
## 腕を下ろす前に、閉じた指先で抜いた毛をひと目確かめられる間を置く。
const SHOW_HAIR_SECONDS: float = 0.16
## 抜けた瞬間と腕を下ろす動きを別々に追える時間。
const RETURN_SECONDS: float = 0.24
## つまむ前の親指と人差し指の開き (rad)
const FINGER_OPEN_RAD: float = 0.55
## 肌の色
const SKIN_COLOR: Color = Color(0.69, 0.45, 0.34)
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
## 指ごとの 3 関節の角度 (rad)。人差し指の先を親指に向け、残る指は手のひらの内側に畳む。
const FINGER_CURL_RAD: Array[Vector3] = [
	Vector3(0.07, 0.73, 0.65), Vector3(0.63, 1.04, 0.78),
	Vector3(0.76, 1.06, 0.79), Vector3(0.85, 1.10, 0.78),
]

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
## 肘の出っ張りと、袖の端の折り返し。
var _elbow: MeshInstance3D
var _cuff: MeshInstance3D
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
	var wrist_offset: Vector3 = pinch_basis * (WRIST - to_local(get_pinch_position()))
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
	var span: Vector3 = WRIST - shoulder
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
	_fit_arm_section(_forearm, elbow, WRIST)
	_fit_arm_section(_cuff, shoulder.lerp(elbow, 0.90), elbow)
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


## 袖・前腕・手のひら・指を組み立てる (影は落とさない。カメラの近くで画面を暗くしないため)
func _build() -> void:
	position = REST_POSITION
	rotation = REST_ROTATION
	var skin: StandardMaterial3D = StandardMaterial3D.new()
	skin.albedo_color = SKIN_COLOR
	skin.roughness = 0.8
	var nail := StandardMaterial3D.new()
	nail.albedo_color = Color(0.77, 0.54, 0.47)
	nail.roughness = 0.55
	var sleeve: StandardMaterial3D = StandardMaterial3D.new()
	sleeve.albedo_color = SLEEVE_COLOR
	sleeve.roughness = 0.9

	var cuff: StandardMaterial3D = sleeve.duplicate()
	cuff.albedo_color = SLEEVE_COLOR.lightened(0.13)
	_sleeve = _arm_section("Sleeve", 0.071, 0.053, sleeve)
	_cuff = _arm_section("Cuff", 0.056, 0.054, cuff)
	_forearm = _arm_section("Forearm", 0.043, 0.027, skin)
	_elbow = HumanParts.add_sphere(self, "Elbow", Vector3.ZERO, 0.044, Vector3.ONE, skin, false)
	# 手のひらは平たく潰した球で、指の付け根の関節の並び (拳の山) を横に渡したカプセルで足す
	HumanParts.add_sphere(
		self, "Palm", Vector3(0.0, 0.0, 0.04), 0.5, Vector3(0.084, 0.042, 0.113), skin, false
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
			Vector3.LEFT, FINGER_CURL_RAD[finger_idx], skin, nail,
		)
		if finger_idx == 0:
			_index_finger = finger_root
			_index_tip = tip
	_thumb = Node3D.new()
	_thumb.name = "Thumb"
	_thumb.position = Vector3(-0.026, 0.0, 0.022)
	add_child(_thumb)
	var thumb_aim: Node3D = Node3D.new()
	thumb_aim.name = "Aim"
	thumb_aim.rotation.x = -0.50
	_thumb.add_child(thumb_aim)
	# 親指は人差し指より太い (半径 1 cm 強)
	_thumb_tip = _add_finger_segments(
		thumb_aim, Vector3(0.04, 0.041, 0.042), 0.011, Vector3.UP,
		Vector3(0.98, -0.93, -0.93), skin, nail
	)


## 付け根 root から局所の -Z へ、長さ segment_lengths の 3 節の指を足す。関節で指ごとの角度だけ曲げ、
## 先の節ほど細くする
static func _add_finger_segments(
	root: Node3D, segment_lengths: Vector3, radius: float, bend_axis: Vector3,
	joint_angles: Vector3, skin: Material, nail: Material
) -> Node3D:
	var joint: Node3D = root
	for segment_idx: int in range(3):
		var bent: Node3D = Node3D.new()
		bent.name = "Joint%d" % segment_idx
		bent.rotation = bend_axis * joint_angles[segment_idx]
		joint.add_child(bent)
		var length: float = segment_lengths[segment_idx]
		# 先の節ほど 1 割ずつ細くし、指先がすぼまって見えるようにする
		HumanParts.add_limb(
			bent, "Segment", Vector3.ZERO, Vector3(0.0, 0.0, -length),
			radius * (1.0 - 0.1 * float(segment_idx)), skin, false,
		)
		if segment_idx == 2:
			HumanParts.add_sphere(bent, "Nail", Vector3(0.0, radius * 0.75, -length * 0.78),
				0.5, Vector3(radius * 1.2, radius * 0.36, radius * 1.6), nail, false)
		var tip: Node3D = Node3D.new()
		tip.name = "End"
		tip.position = Vector3(0.0, 0.0, -length)
		bent.add_child(tip)
		joint = tip
	return joint

class_name FirstPersonHand
extends Node3D
## 一人称カメラの子に置く、プレイヤー自身の右手 (Godot の基本の形を組み合わせた見た目の試作)。
## 手の原点は手首で、指先はカメラの前方 (-Z) を向く。毛をつまんで引いている途中の構図 (pinch) を取れる。

## 平常時の手首の位置 (カメラ基準 m)。1280x720 で画面の右下に手の甲と指が収まる位置
const IDLE_POSITION: Vector3 = Vector3(0.17, -0.14, -0.42)
## 平常時の手首の回転 (rad)。指先を前やや下・内側へ向け、上から手の甲が見え、袖が画面の右下の端へ抜ける角度
const IDLE_ROTATION: Vector3 = Vector3(-0.15, 0.15, 0.0)
## つまむ時の手首の位置 (カメラ基準 m)。画面の中央やや右下で、指先が視線の先の床へ向く位置
const PINCH_POSITION: Vector3 = Vector3(0.07, -0.10, -0.34)
## つまむ時の手首の回転 (rad)。カメラを床へ約 50 度向けた時に指先が床の毛へ向き、袖が画面の下の端へ抜ける角度
const PINCH_ROTATION: Vector3 = Vector3(0.05, 0.20, 0.0)
## 平常時の 4 本の指の曲げ (rad)。力を抜いた手の軽い曲がり
const IDLE_FINGER_CURL: float = 0.35
## つまむ時に人差し指以外の 3 本を握り込む曲げ (rad)
const PINCH_FOLDED_FINGER_CURL: float = 1.25
## つまむ時の人差し指の曲げ (rad)。親指の先と指先が合う曲げ
const PINCH_INDEX_CURL: float = 0.55
## 平常時の親指の回転 (rad)。人差し指の横に添えて内側へ軽く倒した向き
const THUMB_IDLE_ROTATION: Vector3 = Vector3(-0.1, -0.7, -0.4)
## つまむ時の親指の回転 (rad)。親指の先を曲げた人差し指の先へ寄せる向き
const THUMB_PINCH_ROTATION: Vector3 = Vector3(-0.35, -0.55, -0.9)
## 親指の長さ (m)。成人の親指の長さ約 6 cm
const THUMB_LENGTH_M: float = 0.060
## 指の太さ (半径 m)。成人の指の太さ約 1.8 cm
const FINGER_RADIUS_M: float = 0.009
## 人差し指〜小指の長さ (m)。成人の指の長さ 6〜8 cm
const FINGER_LENGTHS_M: Array[float] = [0.075, 0.082, 0.078, 0.062]
## 人差し指〜小指の付け根の横位置 (m)。手のひらの幅 8.5 cm に 4 本を並べる間隔
const FINGER_BASE_X_M: Array[float] = [-0.029, -0.010, 0.010, 0.029]
## 手のひらの寸法 (幅・厚み・長さ m)。成人の手のひらの標準寸法
const PALM_SIZE_M: Vector3 = Vector3(0.085, 0.028, 0.095)
## 袖の半径 (m)。手首の太さに合わせたニットの袖口
const SLEEVE_RADIUS_M: float = 0.032
## 袖の長さ (m)。手首から画面の下の端の外まで腕が続いて見える長さ (短いと袖が缶のように浮いて見える)
const SLEEVE_LENGTH_M: float = 0.24
## 肌の色。写実寄りの明るい肌の色 (彩度を抑え、照明の色を受けやすい値)
const SKIN_COLOR: Color = Color(0.86, 0.66, 0.54)
## 袖 (ニット) の色。屋敷の照明で肌との明暗差が付く濃い灰青
const SLEEVE_COLOR: Color = Color(0.20, 0.22, 0.26)
## 引っ張られて伸びた毛の色。床・手の両方の上で見える明るい白
const STRETCHED_HAIR_COLOR: Color = Color(0.95, 0.93, 0.88)
## 伸びた毛の太さ (半径 m)。誇張して 1280x720 で 2〜3 px に見える太さ (実物の毛は 0.03 mm)
const STRETCHED_HAIR_RADIUS_M: float = 0.0013
## 伸びた毛の根元を指先の真下から少しずらす量 (m)。真下だと手の影に隠れるため
const STRETCHED_HAIR_ROOT_OFFSET: Vector3 = Vector3(0.02, 0.0, 0.04)
## 伸びた毛の根元を床から浮かせる量 (m)。床の面と重なってちらつくのを防ぐ
const STRETCHED_HAIR_FLOOR_LIFT_M: float = 0.002

## 毛をつまんで引いている途中の構図か
var _is_pinching: bool = false
## 伸びた毛の根元を置く床の高さ (ワールド座標 m)
var _floor_y: float = 0.0
## 指 4 本の根元ノード (曲げの回転を持つ)。人差し指から小指の順
var _finger_roots: Array[Node3D] = []
## 親指の根元ノード
var _thumb_root: Node3D = null
## 人差し指と親指の先が合う点 (毛をつまむ点)
var _pinch_point: Node3D = null
## 指先から床へ伸びた 1 本の毛 (つまんでいる間だけ見える)
var _stretched_hair: MeshInstance3D = null


## インスタンス生成時に手・指・袖・伸びた毛のノードを組み立てる
func _init() -> void:
	name = "FirstPersonHand"
	_build_hand()
	# 平常の構図では伸びた毛を出さないため、床の高さは使わない
	set_pinch_pose(false, 0.0)


## つまんでいる間、伸びた毛を指先と床の間に張り直す (手がカメラと一緒に動くため毎フレーム)
func _process(_delta: float) -> void:
	if _is_pinching and is_inside_tree():
		_update_stretched_hair()


## 毛をつまんで引いている途中の構図 (true) と平常の構図 (false) を切り替える。floor_y は伸びた毛の根元の床の高さ
func set_pinch_pose(enabled: bool, floor_y: float) -> void:
	_is_pinching = enabled
	_floor_y = floor_y
	position = PINCH_POSITION if enabled else IDLE_POSITION
	rotation = PINCH_ROTATION if enabled else IDLE_ROTATION
	for finger_index: int in range(_finger_roots.size()):
		var curl: float = IDLE_FINGER_CURL
		if enabled:
			curl = PINCH_INDEX_CURL if finger_index == 0 else PINCH_FOLDED_FINGER_CURL
		_finger_roots[finger_index].rotation = Vector3(-curl, 0.0, 0.0)
	_thumb_root.rotation = THUMB_PINCH_ROTATION if enabled else THUMB_IDLE_ROTATION
	_stretched_hair.visible = enabled
	if enabled and is_inside_tree():
		_update_stretched_hair()


## 毛をつまんで引いている途中の構図か
func is_pinching() -> bool:
	return _is_pinching


## 伸びた毛が見えているか
func is_stretched_hair_visible() -> bool:
	return _stretched_hair.visible


## 伸びた毛の両端 [指先側, 床側] のワールド座標を返す。tree に入っていない時は空配列
func get_stretched_hair_endpoints() -> PackedVector3Array:
	if not is_inside_tree():
		return PackedVector3Array()
	var top: Vector3 = _pinch_point.global_position
	return PackedVector3Array([top, _stretched_hair_root(top)])


## 伸びた毛のメッシュ (高さ 1 の円柱) の今のワールドの transform
func get_stretched_hair_transform() -> Transform3D:
	return _stretched_hair.global_transform


## 指先の位置から、伸びた毛の床側の端の位置を返す
func _stretched_hair_root(top: Vector3) -> Vector3:
	return Vector3(
		top.x + STRETCHED_HAIR_ROOT_OFFSET.x,
		_floor_y + STRETCHED_HAIR_FLOOR_LIFT_M,
		top.z + STRETCHED_HAIR_ROOT_OFFSET.z,
	)


## 高さ 1 の円柱メッシュを、指先から床までの線分に重なるよう伸ばして置く
func _update_stretched_hair() -> void:
	var top: Vector3 = _pinch_point.global_position
	var bottom: Vector3 = _stretched_hair_root(top)
	var axis: Vector3 = top - bottom
	var length: float = axis.length()
	if length <= 0.0:
		_stretched_hair.visible = false
		return
	var up: Vector3 = axis / length
	var side: Vector3 = up.cross(Vector3.FORWARD)
	# 毛がほぼ前後 (Z) を向く時は外積が 0 に近く向きが定まらないため、別の軸で作り直す。0.0001 は長さ 0.01 (角度約 0.6 度)
	if side.length_squared() < 0.0001:
		side = up.cross(Vector3.RIGHT)
	side = side.normalized()
	_stretched_hair.global_transform = Transform3D(
		Basis(side, up * length, side.cross(up)),
		(top + bottom) * 0.5,
	)


## 手のひら・指・親指・袖・伸びた毛のノードを生成して子に置く
func _build_hand() -> void:
	# 粗さ: 肌は 0.55 (わずかに艶のある皮膚)、袖は 0.95 (光を返さない毛糸)、毛は 0.6 (照明で白く光りすぎない艶)
	var skin: StandardMaterial3D = make_material(SKIN_COLOR, 0.55)

	var palm_mesh: BoxMesh = BoxMesh.new()
	palm_mesh.size = PALM_SIZE_M
	_add_mesh(self, "Palm", palm_mesh, skin, Vector3(0.0, 0.0, -PALM_SIZE_M.z * 0.5), Vector3.ZERO)

	for finger_index: int in range(FINGER_LENGTHS_M.size()):
		var finger_root: Node3D = Node3D.new()
		finger_root.name = "Finger%d" % finger_index
		finger_root.position = Vector3(FINGER_BASE_X_M[finger_index], 0.0, -PALM_SIZE_M.z)
		add_child(finger_root)
		_add_finger_segment(finger_root, FINGER_LENGTHS_M[finger_index], skin)
		_finger_roots.append(finger_root)

	_thumb_root = Node3D.new()
	_thumb_root.name = "Thumb"
	# 親指の付け根は手のひらの左端 (右手を手の甲側から見て)、手首から 3 cm 先のやや下
	_thumb_root.position = Vector3(-PALM_SIZE_M.x * 0.5, -0.004, -0.030)
	add_child(_thumb_root)
	_add_finger_segment(_thumb_root, THUMB_LENGTH_M, skin)

	# 人差し指の先 (曲げた指の先端) をつまむ点にする
	_pinch_point = Node3D.new()
	_pinch_point.name = "PinchPoint"
	_pinch_point.position = Vector3(0.0, 0.0, -FINGER_LENGTHS_M[0])
	_finger_roots[0].add_child(_pinch_point)

	var sleeve_mesh: CylinderMesh = CylinderMesh.new()
	sleeve_mesh.top_radius = SLEEVE_RADIUS_M
	# 袖は肘の側へ 8% 太くし、腕が先細りに見えるようにする
	sleeve_mesh.bottom_radius = SLEEVE_RADIUS_M * 1.08
	sleeve_mesh.height = SLEEVE_LENGTH_M
	_add_mesh(
		self,
		"Sleeve",
		sleeve_mesh,
		make_material(SLEEVE_COLOR, 0.95),
		# 袖口を手首から 1 cm 肘の側へ離し、手のひらの付け根と重ならないようにする
		Vector3(0.0, 0.0, SLEEVE_LENGTH_M * 0.5 + 0.01),
		Vector3(PI * 0.5, 0.0, 0.0),
	)

	var hair_mesh: CylinderMesh = CylinderMesh.new()
	# 毛は指先の側を 7 割の太さにして、毛先へ細くなる形にする
	hair_mesh.top_radius = STRETCHED_HAIR_RADIUS_M * 0.7
	hair_mesh.bottom_radius = STRETCHED_HAIR_RADIUS_M
	hair_mesh.height = 1.0
	# 2〜3 px の太さでは断面の角が見えないため、6 角形・途中の輪なしの最少の頂点にする
	hair_mesh.radial_segments = 6
	hair_mesh.rings = 1
	_stretched_hair = MeshInstance3D.new()
	_stretched_hair.name = "StretchedHair"
	_stretched_hair.mesh = hair_mesh
	_stretched_hair.material_override = make_material(STRETCHED_HAIR_COLOR, 0.6)
	_stretched_hair.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_stretched_hair.top_level = true
	add_child(_stretched_hair)


## 指 1 本 (根元から -Z へ伸びるカプセル) を finger_root の子に置く
func _add_finger_segment(finger_root: Node3D, length: float, skin: StandardMaterial3D) -> void:
	var capsule: CapsuleMesh = CapsuleMesh.new()
	capsule.radius = FINGER_RADIUS_M
	capsule.height = length
	# CapsuleMesh の軸は Y。X 軸まわりに -90 度回して -Z へ向ける
	_add_mesh(
		finger_root,
		"Segment",
		capsule,
		skin,
		Vector3(0.0, 0.0, -length * 0.5),
		Vector3(-PI * 0.5, 0.0, 0.0),
	)


## 影を落とさないメッシュノードを parent_node の子に置く (カメラに付く手が部屋に影を落とすと不自然なため)
func _add_mesh(
	parent_node: Node3D,
	node_name: String,
	mesh: Mesh,
	surface_material: Material,
	mesh_position: Vector3,
	mesh_rotation: Vector3,
) -> void:
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.name = node_name
	mesh_instance.mesh = mesh
	mesh_instance.material_override = surface_material
	mesh_instance.position = mesh_position
	mesh_instance.rotation = mesh_rotation
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent_node.add_child(mesh_instance)


## 指定色と粗さの StandardMaterial3D を生成する (見た目の試作の部屋・手で共通に使う)
static func make_material(albedo_color: Color, roughness_value: float) -> StandardMaterial3D:
	var surface_material: StandardMaterial3D = StandardMaterial3D.new()
	surface_material.albedo_color = albedo_color
	surface_material.roughness = roughness_value
	return surface_material

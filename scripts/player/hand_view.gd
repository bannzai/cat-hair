extends Node3D
## 一人称カメラの子に置き、画面の右下に映る自分の手。毛を引いている間は親指と人差し指を閉じて手前へ引く。
## 形は直方体の組み合わせで、見た目の素材を足す時はこのノードの子を差し替える。

## 手を置く位置 (カメラの局所座標。画面の右下に手首から先が映る位置)
const REST_POSITION: Vector3 = Vector3(0.2, -0.2, -0.42)
## 手の向き (手のひらを下に、指先を画面の奥・やや左に向ける)
const REST_ROTATION: Vector3 = Vector3(-0.35, 0.35, 0.0)
## 引き終わる時に手を手前へ引く距離 (m。カメラの局所 +Z)
const PULL_BACK_M: float = 0.07
## 引き終わる時に手を持ち上げる距離 (m)
const PULL_UP_M: float = 0.03
## つまむ前の親指と人差し指の開き (rad)
const FINGER_OPEN_RAD: float = 0.55
## 肌の色
const SKIN_COLOR: Color = Color(0.93, 0.74, 0.62)
## 袖の色
const SLEEVE_COLOR: Color = Color(0.25, 0.32, 0.45)

## 引いている進み具合 (0 = 開いた手、1 = つまんで引き終えた手)
var _pull_progress: float = 0.0
## 人差し指の付け根のノード (開き具合で回す)
var _index_finger: Node3D = null
## 親指の付け根のノード (開き具合で回す)
var _thumb: Node3D = null


## ツリーに入った時に手の形を組み立てる
func _ready() -> void:
	if _index_finger == null:
		_build()
	set_pull_progress(_pull_progress)


## 引いている進み具合 (0〜1) に合わせて指の開きと手の位置を変える
func set_pull_progress(progress: float) -> void:
	_pull_progress = clampf(progress, 0.0, 1.0)
	position = REST_POSITION + Vector3(0.0, PULL_UP_M, PULL_BACK_M) * _pull_progress
	if _index_finger == null:
		return
	var open_rad: float = FINGER_OPEN_RAD * (1.0 - minf(1.0, _pull_progress * 3.0))
	_index_finger.rotation = Vector3(-open_rad * 0.5, 0.0, 0.0)
	_thumb.rotation = Vector3(0.0, open_rad, 0.0)


## 現在の引いている進み具合を返す
func get_pull_progress() -> float:
	return _pull_progress


## 袖・手のひら・指を直方体で組み立てる
func _build() -> void:
	rotation = REST_ROTATION
	var skin: StandardMaterial3D = StandardMaterial3D.new()
	skin.albedo_color = SKIN_COLOR
	skin.roughness = 0.8
	var sleeve: StandardMaterial3D = StandardMaterial3D.new()
	sleeve.albedo_color = SLEEVE_COLOR
	sleeve.roughness = 0.9

	_add_box(self, "Sleeve", Vector3(0.0, 0.0, 0.16), Vector3(0.085, 0.07, 0.14), sleeve)
	_add_box(self, "Palm", Vector3(0.0, 0.0, 0.04), Vector3(0.075, 0.025, 0.09), skin)
	for finger_idx: int in range(3):
		_add_box(
			self,
			"Finger%d" % finger_idx,
			Vector3(0.012 - 0.022 * float(finger_idx), -0.004, -0.035),
			Vector3(0.016, 0.018, 0.06),
			skin,
		)
	_index_finger = Node3D.new()
	_index_finger.name = "IndexFinger"
	_index_finger.position = Vector3(0.03, 0.0, -0.005)
	add_child(_index_finger)
	_add_box(_index_finger, "Bone", Vector3(0.0, 0.0, -0.04), Vector3(0.016, 0.018, 0.08), skin)
	_thumb = Node3D.new()
	_thumb.name = "Thumb"
	_thumb.position = Vector3(0.04, -0.01, 0.04)
	add_child(_thumb)
	_add_box(_thumb, "Bone", Vector3(0.0, 0.0, -0.035), Vector3(0.018, 0.018, 0.06), skin)


## 直方体のメッシュを親ノードへ追加する (影は落とさない。カメラの近くで画面を暗くしないため)
static func _add_box(
	parent_node: Node3D, node_name: String, box_position: Vector3, box_size: Vector3,
	box_material: Material,
) -> void:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = box_size
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = box_material
	instance.position = box_position
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent_node.add_child(instance)

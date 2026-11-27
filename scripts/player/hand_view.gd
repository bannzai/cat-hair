extends Node3D
## 一人称カメラの子に置き、画面の右下に映る自分の右手と腕。毛を引いている間は親指と人差し指を閉じて手前へ引く。
## 形は Godot の基本の形 (カプセル・球) の組み合わせで、袖の付いた前腕・手のひら・5 本の指 (どれも 3 節) を持つ。
## 局所座標では手のひらを下 (-Y)・指先を奥 (-Z)・親指を左 (-X) に向け、手首から肘の側を手前 (+Z) に伸ばす。
## 位置・距離・角度・色は、CI の 1280x720 の撮影で手首から先が画面の右下 1/4 に収まり、引く動きが見て分かる
## 大きさにした仮の値 (実機での見え方は「ユーザー作業の一覧」issue #5 の項目で確かめる)。

## 人の体の部品を作る関数
const HumanParts := preload("res://scripts/human/human_parts.gd")

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


## 作った時に手の形を組み立てる (ツリーに入る前から指の部品を辿れるようにするため、_ready ではなくここで組む)
func _init() -> void:
	_build()
	set_pull_progress(_pull_progress)


## 引いている進み具合 (0〜1) に合わせて指の開きと手の位置を変える
func set_pull_progress(progress: float) -> void:
	_pull_progress = clampf(progress, 0.0, 1.0)
	position = REST_POSITION + Vector3(0.0, PULL_UP_M, PULL_BACK_M) * _pull_progress
	if _index_finger == null:
		return
	var open_rad: float = FINGER_OPEN_RAD * (1.0 - minf(1.0, _pull_progress * 3.0))
	# 開いている時は人差し指を手の甲の側 (+Y) へ起こし、親指を外 (-X) へ開く。閉じると 2 本の先が近づく
	_index_finger.rotation = Vector3(open_rad * 0.5, 0.0, 0.0)
	_thumb.rotation = Vector3(0.0, open_rad, 0.0)


## 現在の引いている進み具合を返す
func get_pull_progress() -> float:
	return _pull_progress


## 袖・前腕・手のひら・指を組み立てる (影は落とさない。カメラの近くで画面を暗くしないため)
func _build() -> void:
	rotation = REST_ROTATION
	var skin: StandardMaterial3D = StandardMaterial3D.new()
	skin.albedo_color = SKIN_COLOR
	skin.roughness = 0.8
	var sleeve: StandardMaterial3D = StandardMaterial3D.new()
	sleeve.albedo_color = SLEEVE_COLOR
	sleeve.roughness = 0.9

	# 袖は手首の少し手前から肘の側へ、画面の外まで伸ばす。前腕は袖口から手首まで見える
	HumanParts.add_limb(
		self, "Sleeve", Vector3(0.0, 0.006, 0.15), Vector3(0.0, 0.02, 0.42), 0.042, sleeve, false
	)
	HumanParts.add_limb(
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
		_add_finger_segments(
			finger_root, FINGER_SEGMENT_M[finger_idx], FINGER_RADIUS_M[finger_idx],
			Vector3(-FINGER_CURL_RAD[finger_idx], 0.0, 0.0), skin,
		)
		if finger_idx == 0:
			_index_finger = finger_root
	_thumb = Node3D.new()
	_thumb.name = "Thumb"
	_thumb.position = THUMB_BASE_POSITION
	add_child(_thumb)
	var thumb_aim: Node3D = Node3D.new()
	thumb_aim.name = "Aim"
	thumb_aim.basis = Basis.looking_at(THUMB_AIM, Vector3.UP)
	_thumb.add_child(thumb_aim)
	# 親指は人差し指より太い (半径 1 cm 強)
	_add_finger_segments(
		thumb_aim, THUMB_SEGMENT_M, 0.0105, Vector3(0.0, -THUMB_CURL_RAD, 0.0), skin
	)


## 付け根 root から局所の -Z へ、長さ segment_lengths の 3 節の指を足す。節ごとに関節で joint_bend だけ曲げ、
## 先の節ほど細くする
static func _add_finger_segments(
	root: Node3D, segment_lengths: Vector3, radius: float, joint_bend: Vector3, skin: Material
) -> void:
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

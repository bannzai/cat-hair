extends RefCounted
## 人の形 (画面に映る自分の手と腕・買取業者の体) の検証 (scripts/dev/selfcheck.gd から呼ぶ)。
## 描画は確かめず (CI の撮影で目視する)、組み立てたノードの部品と、つまむ動きで指先が近づくことを確かめる。

## 画面に映る手のスクリプト
const HandViewScript := preload("res://scripts/player/hand_view.gd")
## 屋敷ビルダーロジックスクリプト
const MansionBuilderScript := preload("res://scripts/mansion/mansion_builder.gd")
## 屋敷のノードを組み立てるスクリプト
const MansionWorldScript := preload("res://scripts/mansion/mansion_world.gd")
## 屋敷の生成パラメータのスクリプト
const MansionTuningScript := preload("res://scripts/data/mansion_tuning.gd")
## 閉じた親指と人差し指の先の中心どうしの距離の上限 (m)。2 本の先の太さの和 (約 1.5 cm) より近ければ触れて見える
const PINCH_CLOSED_MAX_M: float = 0.015
## 開いた親指と人差し指の先の中心どうしの距離の下限 (m)。毛をつまむ前に指の間が開いて見える幅 (約 4 cm)
const PINCH_OPEN_MIN_M: float = 0.04

## 検証結果を記録する selfcheck の SceneTree 参照
var _checker: SceneTree = null


## 人の形の検証をすべて実行する
static func run_all(checker: SceneTree) -> void:
	var suite: RefCounted = load("res://scripts/dev/selfcheck_human.gd").new()
	suite._checker = checker
	suite._check_hand_view_shape_and_pinch()
	suite._check_trader_body()


## 検証結果を selfcheck 本体へ記録する
func _check(cond: bool, label: String) -> void:
	_checker._check(cond, label)


## 手が袖・前腕・手のひらと 3 節ずつの 5 本の指を持ち、引き始めは親指と人差し指の先が離れ、
## 引く途中 (進み具合 1/3 以降) と引き終えた時は 2 本の先が触れるか
func _check_hand_view_shape_and_pinch() -> void:
	# selfcheck は _initialize から同期で走り、root がまだツリーに入っていないため、手はツリーに入れずに
	# 作った時点の部品 (hand_view.gd の _init で組み立てる) と、手の局所座標での位置で確かめる
	var hand: Node3D = HandViewScript.new()
	var fingers_ok: bool = true
	for finger_name: String in HandViewScript.FINGER_NAMES + ["Thumb"]:
		var finger: Node3D = hand.get_node_or_null(finger_name)
		# コードで作ったノードは owner を持たないため、owner の無い子も数える (owned = false)
		if finger == null or finger.find_children("Segment", "MeshInstance3D", true, false).size() != 3:
			fingers_ok = false
	_check(
		fingers_ok
		and hand.get_node_or_null("Sleeve") is MeshInstance3D
		and hand.get_node_or_null("Forearm") is MeshInstance3D
		and hand.get_node_or_null("Palm") is MeshInstance3D,
		"画面の手は袖・前腕・手のひらと、3 節ずつの 5 本の指 (親指・人差し指・中指・薬指・小指) を持つ",
	)
	hand.set_pull_progress(0.0)
	var open_distance: float = _pinch_distance(hand)
	hand.set_pull_progress(1.0 / 3.0)
	var closed_distance: float = _pinch_distance(hand)
	hand.set_pull_progress(1.0)
	var pulled_distance: float = _pinch_distance(hand)
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


## 親指と人差し指の、いちばん先の節の端どうしの距離 (m。手の局所座標) を返す
static func _pinch_distance(hand: Node3D) -> float:
	return _finger_tip(hand, hand.get_node("IndexFinger")).distance_to(
		_finger_tip(hand, hand.get_node("Thumb"))
	)


## 指の付け根 finger から辿った、いちばん先の節の端 (End) の位置を、手 hand の局所座標で返す
static func _finger_tip(hand: Node3D, finger: Node3D) -> Vector3:
	var ends: Array[Node] = finger.find_children("End", "Node3D", true, false)
	var deepest: Node3D = ends[0]
	for end: Node in ends:
		if _depth_below(hand, end) > _depth_below(hand, deepest):
			deepest = end
	var to_hand: Transform3D = Transform3D.IDENTITY
	var node: Node3D = deepest
	while node != hand:
		to_hand = node.transform * to_hand
		node = node.get_parent()
	return to_hand.origin


## node から祖先 ancestor までの親の段数を返す
static func _depth_below(ancestor: Node, node: Node) -> int:
	var depth: int = 0
	while node != ancestor:
		node = node.get_parent()
		depth += 1
	return depth


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
			"Head", "Torso", "LeftUpperArm", "RightUpperArm", "LeftForearm", "RightForearm",
			"LeftHand", "RightHand", "LeftLeg", "RightLeg", "Nose",
		]:
			if not body.get_node_or_null(part_name) is MeshInstance3D:
				parts_ok = false
	_check(parts_ok, "買取業者は頭・胴・左右の腕 (上腕・前腕・手) と脚・鼻を持つ")
	if parts_ok:
		var head: Node3D = body.get_node("Head")
		_check(
			head.position.y > body.get_node("Torso").position.y
			and body.get_node("Torso").position.y > body.get_node("LeftLeg").position.y
			and head.position.y < MansionWorldScript.TRADER_HEIGHT_M
			and body.get_node("Nose").position.z < head.position.z,
			"買取業者の頭は胴より上・背の高さより下、胴は脚より上にあり、顔を部屋の中 (-Z) へ向けている",
		)
	world.free()

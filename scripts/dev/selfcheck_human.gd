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
	_check(
		(closed_tips["index"] as Vector3).z < 0.0 and (closed_tips["thumb"] as Vector3).z < 0.0,
		"閉じた親指と人差し指の先は、指の付け根 (手の原点) より奥 (-Z) にある",
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
		_check(
			absf(bounds.get_center().x) < 0.1 and absf(bounds.get_center().z) < 0.1,
			"買取業者の体の中心は、立つ位置の真上にある",
		)
		var shadows_on: bool = true
		for mesh_node: Node in meshes:
			if (mesh_node as MeshInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				shadows_on = false
		_check(shadows_on, "買取業者の体は影を落とす")
	world.free()

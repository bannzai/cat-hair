extends RefCounted
## 1 本ずつ描く毛の本数の上限 (HairField.draw_budget) と埋もれた毛の検証スイート (scripts/dev/selfcheck.gd から呼ぶ)。
## 上限を小さくして、描く本数が上限で頭打ちになり、残り本数は埋もれた毛を含めて 1 本ずつ数え、描いている毛を消すと
## 埋もれた毛から描き足し、部屋ごとにかける道具が埋もれた毛からも取ることを確かめる (issue #65)。

## 毛を 1 本ずつ持って描くノードのスクリプト
const HairFieldScript := preload("res://scripts/hair_field.gd")
## JSON 保存ストレージスクリプト (一時セーブファイルの後片付けに使う)
const SaveStorageScript := preload("res://scripts/state/save_storage.gd")
## 状態管理 autoload スクリプト
const GameStateScript := preload("res://scripts/state/game_state.gd")
## 3D 屋敷構築ノードスクリプト
const MansionWorldScript := preload("res://scripts/mansion/mansion_world.gd")
## 手に持って使う道具の定義 (部屋ごとにかける道具の id)
const ToolCatalogScript := preload("res://scripts/tools/tool_catalog.gd")
## selfcheck が使う一時セーブファイルパス (GameState の初期化だけに使い、保存はしない)
const TEST_SAVE_PATH: String = "user://selfcheck_hair_budget_save_data.json"
## 毛の描画ベンチマーク (測る本数ごとの描く本数の上限の決め方)
const HairbenchScript := preload("res://scripts/dev/hairbench.gd")
## 屋敷の 1 フレームの時間のベンチマーク (組み直した後の本数の前提の判定)
const ScenebenchScript := preload("res://scripts/dev/scenebench.gd")
## 面の毛の色の id (白) を使う
const SurfaceHairScript := preload("res://scripts/data/surface_hair.gd")
## 検証で使う小さな描く本数の上限 (100 本の面で、描く毛と埋もれた毛の両方を 1 本ずつ追って数えられる本数)
const SMALL_BUDGET: int = 10
## 屋敷を組む検証で使う描く本数の上限。既定の屋敷 (4 部屋・数十の面) の全部の面に数本ずつ配られて描く毛が残り、
## 吸引車が 1 面で触れる本数 (max_hairs) より描いている毛が少ない面ができて埋もれた毛の経路を通る本数
const WORLD_BUDGET: int = 100

## 検証結果を記録する selfcheck の SceneTree 参照
var _checker: SceneTree = null


## 描く本数の上限と埋もれた毛の検証をすべて実行する
static func run_all(checker: SceneTree) -> void:
	var suite: RefCounted = load("res://scripts/dev/selfcheck_hair_budget.gd").new()
	suite._checker = checker
	suite._check_group_counts_over_budget()
	suite._check_remove_refills_until_buried_runs_out()
	suite._check_floor_fur_after_cleaning()
	suite._check_floor_fur_density_limits()
	suite._check_plucked_spot_stays_clear()
	suite._check_refill_on_tiny_surface()
	suite._check_add_and_remove_buried()
	suite._check_populate_over_budget_and_unlimited()
	suite._check_budget_boundary()
	suite._check_every_surface_with_hairs_is_drawn()
	suite._check_hair_ids_are_reused()
	suite._check_surfaces_over_budget()
	suite._check_remove_buried_out_of_range()
	# 埋もれた毛が十分にある屋敷と、描いている毛より少ない屋敷 (描き足しで先に尽きやすい) の両方で確かめる
	suite._check_room_tool_takes_buried(6000)
	suite._check_room_tool_takes_buried(130)
	suite._check_robot_pick_takes_buried()
	suite._check_drop_on_fully_drawn_surface()
	suite._check_bench_budget_rules()


## 表面ごとの色の系統の本数の列を、populate_with_group_counts が受け取る型付きの配列にして返す
static func _counts(rows: Array) -> Array[PackedInt32Array]:
	var typed: Array[PackedInt32Array] = []
	typed.assign(rows)
	return typed


## 同じ種と描画枠で床の毛を置く。埋もれた本数だけを変えて、掃除の途中と再読み込みした時の形を比べる。
static func _make_floor_with_buried(buried: int) -> Node3D:
	var field := HairFieldScript.new()
	field.draw_budget = 256
	field.add_oriented_surface("floor", Transform3D.IDENTITY, Vector2(2, 2), 1.0, [], true)
	field.populate_with_group_counts(_counts([PackedInt32Array([field.draw_budget + buried, 0, 0])]))
	return field


## 山の一部が床面より下がったとき、床に移った毛もまだ山に乗る毛も、同じ残り本数で置き直した形に一致するか。
func _check_floor_fur_after_cleaning() -> void:
	var field: Node3D = _make_floor_with_buried(56000)
	var reloaded: Node3D = _make_floor_with_buried(28000)
	var bare: Node3D = _make_floor_with_buried(0)
	HairFieldScript.remove_buried_hairs(field, 0, HairFieldScript.HairColorGroup.WHITE, 28000)
	var flat_count: int = 0
	var slope_count: int = 0
	var flat_ok: bool = true
	var slope_ok: bool = true
	for slot: int in range(field.get_surface_visible_instance_count(0)):
		var hair_id: int = field.get_hair_id_at_slot(0, slot)
		var actual: Transform3D = field.get_hair_transform(hair_id)
		var expected: Transform3D = reloaded.get_hair_transform(hair_id)
		var flat: Transform3D = bare.get_hair_transform(hair_id)
		if expected.is_equal_approx(flat):
			flat_count += 1
			flat_ok = flat_ok and actual.is_equal_approx(flat)
			flat_ok = flat_ok and (actual * HairFieldScript.HAIR_TIP).y > 0.0
		elif not expected.basis.is_equal_approx(flat.basis):
			slope_count += 1
			slope_ok = slope_ok and actual.is_equal_approx(expected)
	_check(flat_count > 0 and flat_ok, "山から床に下りた毛は床の傾きに戻り、毛先が床の上にある")
	_check(slope_count > 0 and slope_ok, "山に残った毛は掃除後の山肌に沿って傾く")
	field.free()
	reloaded.free()
	bare.free()


## 層が床下に隠れる最少の本数と、層が最も厚くなる本数を超えた側で、毛の根元と照準の当たる高さを確かめる。
func _check_floor_fur_density_limits() -> void:
	var bare: Node3D = _make_floor_with_buried(0)
	var one: Node3D = _make_floor_with_buried(1)
	var layer: FloorFur = one.get_child(0).get_child(0) as FloorFur
	_check(layer != null and not layer.visible and _same_floor_roots_and_hits(one, bare),
		"埋もれた毛が 1 本の層は床の下に隠れ、各根元と照準の交点は裸の床と一致する")
	one.free()
	bare.free()
	var full: Node3D = _make_floor_with_buried(56000)
	# 1 本だけ超えた場合と、厚みの丸め幅を十分に超えた場合の両方で飽和を確かめる。
	for buried: int in [56001, 112000]:
		var extra: Node3D = _make_floor_with_buried(buried)
		_check(_same_floor_roots_and_hits(extra, full),
			"埋もれた毛が %d 本の床は、飽和する 56,000 本の床と各根元・照準の交点が一致する" % buried)
		extra.free()
	full.free()


## 同じ種の床どうしで、各毛の姿勢と、その真上から狙ったときの表面の交点が一致するか。
static func _same_floor_roots_and_hits(actual: Node3D, expected: Node3D) -> bool:
	var slots: int = expected.get_surface_visible_instance_count(0)
	if slots == 0 or actual.get_surface_visible_instance_count(0) != slots:
		return false
	for slot: int in range(slots):
		var hair_id: int = expected.get_hair_id_at_slot(0, slot)
		var pose: Transform3D = expected.get_hair_transform(hair_id)
		if not pose.is_equal_approx(actual.get_hair_transform(hair_id)):
			return false
		var eye: Vector3 = pose.origin + Vector3.UP
		var hit: Dictionary = actual.intersect_surfaces(eye, Vector3.DOWN, 2.0)
		var target: Dictionary = expected.intersect_surfaces(eye, Vector3.DOWN, 2.0)
		if hit.is_empty() or target.is_empty() or not hit["point"].is_equal_approx(target["point"]):
			return false
	return true


## 検証結果を selfcheck 本体へ記録する
func _check(cond: bool, label: String) -> void:
	_checker._check(cond, label)


## 2 面 (毛の本数 0 の面を含む) の field を作り、白 30・黒 30・三毛 40 本を 1 面目に置く (上限 SMALL_BUDGET)
static func _make_field() -> Node3D:
	var field: Node3D = HairFieldScript.new()
	field.draw_budget = SMALL_BUDGET
	field.add_oriented_surface("floor", Transform3D.IDENTITY, Vector2(2.0, 2.0), 1.0)
	field.add_oriented_surface(
		"rug", Transform3D(Basis.IDENTITY, Vector3(5.0, 0.0, 0.0)), Vector2(1.0, 1.0), 1.0
	)
	var counts: Array[PackedInt32Array] = [PackedInt32Array([30, 30, 40]), PackedInt32Array([0, 0, 0])]
	field.populate_with_group_counts(counts, 3)
	return field


## 上限を超える本数を色の系統ごとに置くと、描くのは上限までで、残り本数と系統ごとの本数は置いた本数のままか
func _check_group_counts_over_budget() -> void:
	var field: Node3D = _make_field()
	var buried: PackedInt32Array = HairFieldScript.buried_group_counts(field, 0)
	_check(
		field.get_remaining_count() == 100
		and field.get_surface_remaining_count(0) == 100
		and field.get_surface_visible_instance_count(0) == SMALL_BUDGET
		and field.get_surface_visible_instance_count(1) == 0
		and buried[0] + buried[1] + buried[2] == 100 - SMALL_BUDGET
		and HairFieldScript.count_surface_groups(field, 0) == PackedInt32Array([30, 30, 40]),
		"上限 10 本で 100 本を置くと 10 本だけ描き、残り 100 本・系統ごとに白 30・黒 30・三毛 40 本のまま (描いている %d 本・埋もれた %s)"
		% [field.get_surface_visible_instance_count(0), str(buried)],
	)
	field.free()


## 描いている毛を 1 本消すたびに残り本数が 1 減り、埋もれた毛がある間は描いている本数が変わらず、
## 埋もれた毛が尽きると描いている本数が減っていき、最後は 0 本になるか
func _check_remove_refills_until_buried_runs_out() -> void:
	var field: Node3D = _make_field()
	var first_id: int = field.get_hair_id_at_slot(0, 0)
	_check(
		field.remove_hair(first_id)
		and not field.has_hair(first_id)
		and field.get_remaining_count() == 99
		and field.get_surface_visible_instance_count(0) == SMALL_BUDGET,
		"描いている毛を 1 本消すと残り 99 本になり、埋もれた毛から 1 本描き足して 10 本のまま",
	)
	var counts_match: bool = true
	var visible_kept: bool = true
	for removed: int in range(2, 101):
		field.remove_hair(field.get_hair_id_at_slot(0, 0))
		var left: int = 100 - removed
		var groups: PackedInt32Array = HairFieldScript.count_surface_groups(field, 0)
		if field.get_remaining_count() != left or groups[0] + groups[1] + groups[2] != left:
			counts_match = false
		if field.get_surface_visible_instance_count(0) != mini(SMALL_BUDGET, left):
			visible_kept = false
	_check(
		counts_match and visible_kept and field.get_remaining_count() == 0
		and field.get_surface_visible_instance_count(0) == 0,
		"1 本ずつ 100 本消すと残り本数は 1 本ずつ減り、描いている本数は埋もれた毛が尽きるまで 10 本のまま、最後は 0 本",
	)
	field.free()


## 1 本ずつつまんだ直後、描き足す毛の根元が抜いた場所を埋めないか
func _check_plucked_spot_stays_clear() -> void:
	var field: Node3D = HairFieldScript.new()
	field.draw_budget = 1
	field.add_oriented_surface("seat", Transform3D.IDENTITY, Vector2(0.15, 0.15), 1.0)
	field.populate(100)
	var clear: bool = true
	for _index: int in range(99):
		var id: int = field.get_hair_id_at_slot(0, 0)
		var root: Vector3 = field.get_hair_transform(id).origin
		field.remove_hair(id)
		var next_id: int = field.get_hair_id_at_slot(0, 0)
		var next: Vector3 = field.get_hair_transform(next_id).origin
		if root.distance_to(next) < HairFieldScript.HAIR_LENGTH_M:
			clear = false
	_check(clear, "抜いた位置から毛 1 本の長さの範囲には、次の毛の根元を描き足さない")
	field.free()


## 抜いた位置から毛の長さだけ離れられない面でも、上限回数で探索を終え、残った毛を描く。
func _check_refill_on_tiny_surface() -> void:
	var field: Node3D = HairFieldScript.new()
	field.draw_budget = 1
	field.add_oriented_surface("seat", Transform3D.IDENTITY,
		Vector2.ONE * HairFieldScript.HAIR_LENGTH_M * 0.01, 1.0)
	field.populate(2)
	field.remove_hair(field.get_hair_id_at_slot(0, 0))
	_check(field.get_surface_visible_instance_count(0) == 1
		and field.get_surface_remaining_count(0) == 1, "小さい面でも埋もれた最後の毛を 1 本描く")
	field.free()


## 上限に達した面に猫が落とした毛は落とした所に描き、描いていた別の 1 本を埋もれた毛へ戻すか。毛の無い面には描くか。
## 埋もれた毛からは系統ごとに取れるか
func _check_add_and_remove_buried() -> void:
	var field: Node3D = _make_field()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 5
	var white_before: int = (
		HairFieldScript.count_surface_groups(field, 0)[HairFieldScript.HairColorGroup.WHITE]
	)
	var dropped_id: int = HairFieldScript.add_hair(
		field, 0, Vector3.ZERO, 0.1, HairFieldScript.HairColorGroup.WHITE, rng
	)
	var buried_after: PackedInt32Array = HairFieldScript.buried_group_counts(field, 0)
	_check(
		dropped_id >= 0 and field.has_hair(dropped_id)
		and field.get_hair_transform(dropped_id).origin.distance_to(Vector3.ZERO) < 0.2
		and field.get_remaining_count() == 101
		and field.get_surface_visible_instance_count(0) == SMALL_BUDGET
		and buried_after[0] + buried_after[1] + buried_after[2] == 100 - SMALL_BUDGET + 1
		and HairFieldScript.count_surface_groups(field, 0)[HairFieldScript.HairColorGroup.WHITE]
		== white_before + 1,
		"描く本数が上限の面に落とした白い毛は落とした所に描き、描いていた 1 本を埋もれた毛へ戻して 10 本のまま、残り 101 本・白が 1 本増える",
	)
	var drawn_id: int = HairFieldScript.add_hair(
		field, 1, Vector3(5.0, 0.0, 0.0), 0.1, HairFieldScript.HairColorGroup.BLACK, rng
	)
	_check(
		drawn_id >= 0 and field.has_hair(drawn_id)
		and field.get_surface_visible_instance_count(1) == 1 and field.get_remaining_count() == 102,
		"埋もれた毛の無い面に落とした毛は描く",
	)
	var calico_buried: int = HairFieldScript.buried_group_counts(field, 0)[
		HairFieldScript.HairColorGroup.CALICO
	]
	var removed: int = HairFieldScript.remove_buried_hairs(
		field, 0, HairFieldScript.HairColorGroup.CALICO, 1000
	)
	_check(
		removed == calico_buried and removed > 0
		and field.get_remaining_count() == 102 - removed
		and HairFieldScript.buried_group_counts(field, 0)[HairFieldScript.HairColorGroup.CALICO] == 0
		and HairFieldScript.remove_buried_hairs(field, 0, 99, 1) == 0
		and HairFieldScript.remove_buried_hairs(field, 9, 0, 1) == 0,
		"埋もれた三毛の毛を多めに取ると、ある本数 (%d 本) だけ取り、範囲外の系統・面からは取らない" % calico_buried,
	)
	field.free()


## 本数を表面の重みで分ける置き方でも描くのは上限までで、上限を外すと全部描くか
func _check_populate_over_budget_and_unlimited() -> void:
	var field: Node3D = HairFieldScript.new()
	field.draw_budget = SMALL_BUDGET
	field.add_oriented_surface("a", Transform3D.IDENTITY, Vector2(1.0, 1.0), 1.0)
	field.add_oriented_surface(
		"b", Transform3D(Basis.IDENTITY, Vector3(3.0, 0.0, 0.0)), Vector2(1.0, 1.0), 1.0
	)
	var placed: int = field.populate(100, 4)
	var groups_a: PackedInt32Array = HairFieldScript.count_surface_groups(field, 0)
	_check(
		placed == 100 and field.get_remaining_count() == 100
		and field.get_surface_visible_instance_count(0) == 5
		and field.get_surface_visible_instance_count(1) == 5
		and field.get_surface_remaining_count(0) == 50
		and groups_a[0] + groups_a[1] + groups_a[2] == 50,
		"上限 10 本で 100 本を 2 面に分けると、5 本ずつ描いて残りは 50 本ずつ",
	)
	field.draw_budget = 0
	field.populate(100, 4)
	_check(
		field.get_surface_visible_instance_count(0) == 50
		and HairFieldScript.buried_group_counts(field, 0) == PackedInt32Array([0, 0, 0]),
		"上限を外す (0) と全部描き、埋もれた毛は無い",
	)
	field.free()


## 総本数が上限ちょうどなら全部描き、上限 + 1 本なら上限まで描いて 1 本を埋もれた毛にするか
func _check_budget_boundary() -> void:
	var field: Node3D = HairFieldScript.new()
	field.draw_budget = SMALL_BUDGET
	field.add_oriented_surface("a", Transform3D.IDENTITY, Vector2(1.0, 1.0), 1.0)
	field.populate_with_group_counts(_counts([PackedInt32Array([SMALL_BUDGET, 0, 0])]), 6)
	var at_budget_buried: PackedInt32Array = HairFieldScript.buried_group_counts(field, 0)
	field.populate_with_group_counts(_counts([PackedInt32Array([SMALL_BUDGET + 1, 0, 0])]), 6)
	_check(
		at_budget_buried == PackedInt32Array([0, 0, 0])
		and field.get_surface_visible_instance_count(0) == SMALL_BUDGET
		and HairFieldScript.buried_group_counts(field, 0) == PackedInt32Array([1, 0, 0])
		and field.get_remaining_count() == SMALL_BUDGET + 1,
		"上限ちょうどの本数は全部描き、上限 + 1 本は上限まで描いて白 1 本を埋もれた毛にする",
	)
	field.free()


## 総本数が上限を超えても、毛のある面には 1 本以上の描く枠を配るか (比例だけで配ると本数の少ない面が 0 本になり、
## その面の毛を手でも狙った所にかける道具でも取れなくなる)。毛の無い面には配らず、配った本数は面の本数を超えないか
func _check_every_surface_with_hairs_is_drawn() -> void:
	var field: Node3D = HairFieldScript.new()
	field.draw_budget = SMALL_BUDGET
	field.add_oriented_surface("big", Transform3D.IDENTITY, Vector2(2.0, 2.0), 1.0)
	field.add_oriented_surface(
		"tiny", Transform3D(Basis.IDENTITY, Vector3(5.0, 0.0, 0.0)), Vector2(1.0, 1.0), 1.0
	)
	field.add_oriented_surface(
		"empty", Transform3D(Basis.IDENTITY, Vector3(9.0, 0.0, 0.0)), Vector2(1.0, 1.0), 1.0
	)
	field.populate_with_group_counts(
		_counts([
			PackedInt32Array([1000, 0, 0]), PackedInt32Array([0, 1, 0]), PackedInt32Array([0, 0, 0])
		]),
		8
	)
	_check(
		field.get_surface_visible_instance_count(1) == 1
		and field.get_surface_visible_instance_count(2) == 0
		and HairFieldScript.count_drawn_hairs(field) <= SMALL_BUDGET
		and field.get_surface_visible_instance_count(0) == SMALL_BUDGET - 1,
		"上限 10 本で 1,000 本の面と 1 本の面と 0 本の面に配ると、1 本の面に 1 本・0 本の面に 0 本・残り 9 本を大きい面に描く (%d / %d / %d)"
		% [
			field.get_surface_visible_instance_count(0),
			field.get_surface_visible_instance_count(1),
			field.get_surface_visible_instance_count(2),
		],
	)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 9
	var dropped_id: int = HairFieldScript.add_hair(
		field, 2, Vector3(9.0, 0.0, 0.0), 0.1, HairFieldScript.HairColorGroup.WHITE, rng
	)
	_check(
		dropped_id >= 0 and field.has_hair(dropped_id)
		and field.get_surface_visible_instance_count(2) == 1
		and field.get_surface_remaining_count(2) == 1,
		"毛の無かった面に落とした毛は描き、その面の残りは 1 本",
	)
	field.free()


## 埋もれた毛から描き足し続けても、消した毛の ID を使い直して毛の ID が描く本数と ID_REUSE_DELAY の合計ほどで
## 頭打ちになるか。消した直後の ID は別の毛に付かないか。使い直し済みの列を詰めた後 (ID_REUSE_DELAY の 3 倍を消すと
## 20,001 本目で 1 回詰め、その後も約 1 万本を使い直す) も、描いている毛の ID が重ならず、ID から引いた表面と位置が
## 合うか。clear の後に置き直すと ID が 0 から振られるか
func _check_hair_ids_are_reused() -> void:
	var field: Node3D = HairFieldScript.new()
	field.draw_budget = SMALL_BUDGET
	field.add_oriented_surface("a", Transform3D.IDENTITY, Vector2(2.0, 2.0), 1.0)
	var removals: int = HairFieldScript.ID_REUSE_DELAY * 3
	field.populate_with_group_counts(_counts([PackedInt32Array([removals + SMALL_BUDGET, 0, 0])]), 5)
	var max_id: int = 0
	var fresh_id_kept_free: bool = true
	var ids_consistent: bool = true
	for _i: int in range(removals):
		var hair_id: int = field.get_hair_id_at_slot(0, 0)
		field.remove_hair(hair_id)
		if field.has_hair(hair_id):
			fresh_id_kept_free = false
		var seen: Dictionary = {}
		for slot: int in range(field.get_surface_visible_instance_count(0)):
			var drawn_id: int = field.get_hair_id_at_slot(0, slot)
			max_id = maxi(max_id, drawn_id)
			if seen.has(drawn_id) or not field.has_hair(drawn_id):
				ids_consistent = false
			seen[drawn_id] = true
	_check(
		fresh_id_kept_free and ids_consistent
		and max_id < SMALL_BUDGET + HairFieldScript.ID_REUSE_DELAY + 1
		and field.get_surface_visible_instance_count(0) == SMALL_BUDGET
		and field.get_remaining_count() == SMALL_BUDGET,
		"%d 本を 1 本ずつ消して描き足すと、消した直後の ID は別の毛に付かず、描いている毛の ID は重ならず、%d 未満に収まる (最大 %d)"
		% [removals, SMALL_BUDGET + HairFieldScript.ID_REUSE_DELAY + 1, max_id],
	)
	field.populate_with_group_counts(_counts([PackedInt32Array([SMALL_BUDGET * 2, 0, 0])]), 5)
	var max_after_clear: int = 0
	for slot: int in range(field.get_surface_visible_instance_count(0)):
		max_after_clear = maxi(max_after_clear, field.get_hair_id_at_slot(0, slot))
	_check(
		max_after_clear == SMALL_BUDGET - 1,
		"置き直すと毛の ID は 0 から振り直され、描いている %d 本の ID の最大は %d (実際 %d)"
		% [SMALL_BUDGET, SMALL_BUDGET - 1, max_after_clear],
	)
	field.free()


## 毛のある面の数が上限ちょうどの時と上限 + 1 の時も、各面に 1 本ずつ描き、残り本数はそのままか
## (上限 + 1 の時は描く本数が上限を 1 本超える)
func _check_surfaces_over_budget() -> void:
	for surface_count: int in [SMALL_BUDGET, SMALL_BUDGET + 1]:
		var field: Node3D = HairFieldScript.new()
		field.draw_budget = SMALL_BUDGET
		var rows: Array = []
		for index: int in range(surface_count):
			field.add_oriented_surface(
				"s%d" % index,
				Transform3D(Basis.IDENTITY, Vector3(float(index) * 3.0, 0.0, 0.0)),
				Vector2(1.0, 1.0),
				1.0,
			)
			rows.append(PackedInt32Array([5, 0, 0]))
		field.populate_with_group_counts(_counts(rows), 3)
		var each_drawn_once: bool = true
		for index: int in range(surface_count):
			if field.get_surface_visible_instance_count(index) != 1:
				each_drawn_once = false
		_check(
			each_drawn_once
			and HairFieldScript.count_drawn_hairs(field) == surface_count
			and field.get_remaining_count() == surface_count * 5,
			"上限 %d 本で毛 5 本の面が %d 面ある時、各面に 1 本ずつ描き (計 %d 本)、残りは %d 本のまま"
			% [SMALL_BUDGET, surface_count, HairFieldScript.count_drawn_hairs(field), surface_count * 5],
		)
		field.free()


## 全部の毛を描いている面 (埋もれた毛が無い) に落とした毛は、描いている毛を埋もれた毛へ戻さずに描き足すか
func _check_drop_on_fully_drawn_surface() -> void:
	var field: Node3D = HairFieldScript.new()
	field.draw_budget = SMALL_BUDGET
	field.add_oriented_surface("a", Transform3D.IDENTITY, Vector2(1.0, 1.0), 1.0)
	field.populate_with_group_counts(_counts([PackedInt32Array([0, SMALL_BUDGET, 0])]), 7)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 11
	HairFieldScript.add_hair(field, 0, Vector3.ZERO, 0.1, HairFieldScript.HairColorGroup.WHITE, rng)
	_check(
		field.get_surface_visible_instance_count(0) == SMALL_BUDGET + 1
		and HairFieldScript.buried_group_counts(field, 0) == PackedInt32Array([0, 0, 0])
		and HairFieldScript.count_surface_groups(field, 0) == PackedInt32Array([1, SMALL_BUDGET, 0]),
		"埋もれた毛が無く描く枠ちょうどの面に落とした白い毛は描き足し、描いている毛は 11 本・埋もれた毛は 0 本",
	)
	field.free()


## 埋もれた毛を取る時、負や範囲外の面・系統からは取らないか
func _check_remove_buried_out_of_range() -> void:
	var field: Node3D = _make_field()
	_check(
		HairFieldScript.remove_buried_hairs(field, -1, 0, 1) == 0
		and HairFieldScript.remove_buried_hairs(field, 0, -1, 1) == 0
		and HairFieldScript.remove_buried_hairs(field, 0, HairFieldScript.HairColorGroup.size(), 1) == 0
		and HairFieldScript.remove_buried_hairs(field, 2, 0, 1) == 0
		and HairFieldScript.remove_buried_hairs(field, 0, 0, -5) == 0
		and field.get_remaining_count() == 100,
		"負の面・負の系統・範囲外の面と系統・負の本数では埋もれた毛を取らず、残りは 100 本のまま",
	)
	field.free()


## hair_count 本の屋敷の GameState を作る (お金は道具を買える額にする。保存はしない)
static func _make_budget_state(hair_count: int) -> Node:
	SaveStorageScript.delete_save_file(TEST_SAVE_PATH)
	var state: Node = GameStateScript.new()
	state.initialize_from_storage(
		TEST_SAVE_PATH, PackedStringArray(["--hair-count=%d" % hair_count])
	)
	state.save_data.building_progress.money = 100000
	return state


## state の屋敷を、描く本数の上限 WORLD_BUDGET で組んだ MansionWorld を返す
static func _make_budget_world(state: Node) -> MansionWorld:
	var world: MansionWorld = MansionWorldScript.new()
	world.hair_draw_budget = WORLD_BUDGET
	world.rebuild(state.current_layout, state.save_data.building_progress)
	return world


## 面ごと・色ごとの残り本数が、全部の面で HairField と GameState で同じか
static func _surface_counts_match(state: Node, world: MansionWorld) -> bool:
	var hair_field: Node3D = world.get_hair_field()
	for surface_index: int in range(hair_field.get_surface_count()):
		var saved: SurfaceHair = state.save_data.building_progress.find_surface_hair(
			world.get_surface_def(surface_index).surface_id
		)
		var groups: PackedInt32Array = HairFieldScript.count_surface_groups(hair_field, surface_index)
		for group: int in range(groups.size()):
			if groups[group] != saved.count_for_color(SurfaceHairScript.STANDARD_COLORS[group]):
				return false
	return true


## 吸引車が埋もれた毛からも取る時、GameState と HairField の本数が面ごと・色ごとに合うか (hair_count 本の屋敷。130 本では
## 埋もれた毛が描いている毛より少なく、描いている毛を先に消すと描き足しが計画した埋もれた毛を使い切る)
func _check_room_tool_takes_buried(hair_count: int) -> void:
	var state: Node = _make_budget_state(hair_count)
	var world: MansionWorld = _make_budget_world(state)
	var hair_field: Node3D = world.get_hair_field()
	var truck: StringName = ToolCatalogScript.TOOL_SUCTION_TRUCK
	state.purchase(GameStateScript.PURCHASE_TOOL, truck)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 12
	var drawn_before: int = HairFieldScript.count_drawn_hairs(hair_field)
	_check(
		drawn_before > 0 and drawn_before <= WORLD_BUDGET
		and hair_field.get_remaining_count() == hair_count,
		"描く本数の上限 %d 本で %d 本の屋敷を組むと、描くのは上限までで残りは %d 本 (描いている %d 本)"
		% [WORLD_BUDGET, hair_count, hair_count, drawn_before],
	)
	var plan: Dictionary = ToolController.plan_room_removal(
		world, state.current_layout.rooms[0].room_id, truck, 1, rng
	)
	var removed: int = state.apply_tool_sweep(truck, plan["counts_by_surface"])
	ToolController.apply_room_removal(world, plan)
	var visible_taken: int = (plan["removed_ids"] as PackedInt32Array).size()
	_check(
		removed > visible_taken and visible_taken > 0
		and hair_field.get_remaining_count() == state.get_total_remaining_hairs()
		and _surface_counts_match(state, world),
		"%d 本の屋敷で吸引車は描いている毛 (%d 本) より多い %d 本を取り、HairField の残り本数が面ごと・色ごとに GameState と同じ (%d / %d 本)"
		% [
			hair_count, visible_taken, removed,
			hair_field.get_remaining_count(), state.get_total_remaining_hairs(),
		],
	)
	world.free()
	state.free()
	SaveStorageScript.delete_save_file(TEST_SAVE_PATH)


## 掃除ロボットが面の白い毛を全部 (描いている白と埋もれた白の合計) 取ると、白だけが 0 本になるか。埋もれた白をちょうど
## 使い切る本数なので、描いている毛を先に消すと描き足しが埋もれた白を先に使い、白が残る
func _check_robot_pick_takes_buried() -> void:
	var state: Node = _make_budget_state(6000)
	var world: MansionWorld = _make_budget_world(state)
	var hair_field: Node3D = world.get_hair_field()
	var white: int = HairFieldScript.HairColorGroup.WHITE
	var groups_before: PackedInt32Array = HairFieldScript.count_surface_groups(hair_field, 0)
	AutomationController.remove_picked_hairs(
		world, 0, SurfaceHairScript.COLOR_WHITE, groups_before[white], Vector3.ZERO
	)
	var groups_after: PackedInt32Array = HairFieldScript.count_surface_groups(hair_field, 0)
	_check(
		groups_before[white] > hair_field.get_surface_visible_instance_count(0)
		and groups_after[white] == 0
		and groups_after[HairFieldScript.HairColorGroup.BLACK]
		== groups_before[HairFieldScript.HairColorGroup.BLACK]
		and groups_after[HairFieldScript.HairColorGroup.CALICO]
		== groups_before[HairFieldScript.HairColorGroup.CALICO],
		"掃除ロボットが面の白 %d 本を全部取ると白は 0 本になり、黒・三毛は変わらない (取った後の白 %d 本)"
		% [groups_before[white], groups_after[white]],
	)
	world.free()
	state.free()
	SaveStorageScript.delete_save_file(TEST_SAVE_PATH)


## hairbench は 1,000,000 本までは全部描き 1,000,001 本からは既定の上限で描くか、scenebench の本数の前提の判定は
## 置いた本数が合い描いた本数が上限ちょうどまでの時だけ通るか。期待値の 1,000,000 本は issue #6 の要件の最大の本数
func _check_bench_budget_rules() -> void:
	_check(
		HairbenchScript.draw_budget_for(1000000) == 0
		and HairbenchScript.draw_budget_for(1000001) == HairFieldScript.DEFAULT_DRAW_BUDGET
		and HairbenchScript.draw_budget_for(10000000) == HairFieldScript.DEFAULT_DRAW_BUDGET,
		"hairbench は 1,000,000 本まで上限なし (0)、1,000,001 本と 10,000,000 本は既定の上限で描く",
	)
	_check(
		HairbenchScript.parse_counts("invalid", ScenebenchScript.DEFAULT_DRAW_BUDGETS)
		== ScenebenchScript.DEFAULT_DRAW_BUDGETS
		and HairbenchScript.parse_counts("", ScenebenchScript.DEFAULT_DRAW_BUDGETS)
		== ScenebenchScript.DEFAULT_DRAW_BUDGETS
		and HairbenchScript.parse_counts(" 5000 ", ScenebenchScript.DEFAULT_DRAW_BUDGETS)
		== [5000],
		"scenebench の上限の指定が無効・空なら scenebench の既定の上限を使い、正の数ならそれを使う",
	)
	_check(
		ScenebenchScript.is_budget_entry_ok(100, 100, 50, 50)
		and not ScenebenchScript.is_budget_entry_ok(100, 100, 51, 50)
		and not ScenebenchScript.is_budget_entry_ok(99, 100, 50, 50),
		"scenebench の本数の前提は、描いた本数が上限ちょうどなら通り、上限 + 1 本か置いた本数の不足なら通らない",
	)

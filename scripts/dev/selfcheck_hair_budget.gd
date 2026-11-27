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
## 検証で使う小さな描く本数の上限
const SMALL_BUDGET: int = 10

## 検証結果を記録する selfcheck の SceneTree 参照
var _checker: SceneTree = null


## 描く本数の上限と埋もれた毛の検証をすべて実行する
static func run_all(checker: SceneTree) -> void:
	var suite: RefCounted = load("res://scripts/dev/selfcheck_hair_budget.gd").new()
	suite._checker = checker
	suite._check_group_counts_over_budget()
	suite._check_remove_refills_until_buried_runs_out()
	suite._check_add_and_remove_buried()
	suite._check_populate_over_budget_and_unlimited()
	suite._check_budget_boundary()
	suite._check_drop_on_surface_without_drawn_hairs()
	suite._check_remove_buried_out_of_range()
	# 埋もれた毛が十分にある屋敷と、描いている毛より少ない屋敷 (描き足しで先に尽きやすい) の両方で確かめる
	suite._check_room_tool_takes_buried(6000)
	suite._check_room_tool_takes_buried(130)
	suite._check_robot_pick_takes_buried()


## 表面ごとの色の系統の本数の列を、populate_with_group_counts が受け取る型付きの配列にして返す
static func _counts(rows: Array) -> Array[PackedInt32Array]:
	var typed: Array[PackedInt32Array] = []
	typed.assign(rows)
	return typed


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


## 上限に達した面に猫が落とした毛は埋もれた毛に数え、毛の無い面には描き、埋もれた毛からは系統ごとに取れるか
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


## 上限の配分で描く本数が 0 になった面 (埋もれた毛だけがある面) に落とした毛は、戻す毛が無いのでそのまま描くか
func _check_drop_on_surface_without_drawn_hairs() -> void:
	var field: Node3D = HairFieldScript.new()
	field.draw_budget = SMALL_BUDGET
	field.add_oriented_surface("big", Transform3D.IDENTITY, Vector2(2.0, 2.0), 1.0)
	field.add_oriented_surface(
		"tiny", Transform3D(Basis.IDENTITY, Vector3(5.0, 0.0, 0.0)), Vector2(1.0, 1.0), 1.0
	)
	field.populate_with_group_counts(
		_counts([PackedInt32Array([1000, 0, 0]), PackedInt32Array([0, 1, 0])]), 8
	)
	var tiny_drawn: int = field.get_surface_visible_instance_count(1)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 9
	var dropped_id: int = HairFieldScript.add_hair(
		field, 1, Vector3(5.0, 0.0, 0.0), 0.1, HairFieldScript.HairColorGroup.WHITE, rng
	)
	_check(
		tiny_drawn == 0
		and dropped_id >= 0 and field.has_hair(dropped_id)
		and field.get_surface_visible_instance_count(1) == 1
		and field.get_surface_remaining_count(1) == 2
		and HairFieldScript.count_surface_groups(field, 1) == PackedInt32Array([1, 1, 0]),
		"描く本数が 0 の面 (埋もれた黒 1 本) に落とした白い毛は描き、残り 2 本・白 1・黒 1 (描いていた本数 %d)"
		% tiny_drawn,
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


## 描く本数の上限 100 本で hair_count 本の屋敷を組み、GameState と HairField を返す (お金は道具を買える額にする)
static func _make_budget_world(hair_count: int) -> Array:
	SaveStorageScript.delete_save_file(TEST_SAVE_PATH)
	var state: Node = GameStateScript.new()
	state.initialize_from_storage(
		TEST_SAVE_PATH, PackedStringArray(["--hair-count=%d" % hair_count])
	)
	var world: MansionWorld = MansionWorldScript.new()
	world.hair_draw_budget = 100
	world.rebuild(state.current_layout, state.save_data.building_progress)
	state.save_data.building_progress.money = 100000
	return [state, world]


## 面ごとの残り本数が HairField と GameState で全部の面で同じか
static func _surface_counts_match(state: Node, world: MansionWorld) -> bool:
	var hair_field: Node3D = world.get_hair_field()
	for surface_index: int in range(hair_field.get_surface_count()):
		if (
			hair_field.get_surface_remaining_count(surface_index)
			!= state.get_surface_hair_count(world.get_surface_def(surface_index).surface_id)
		):
			return false
	return true


## 吸引車が埋もれた毛からも取る時、GameState と HairField の本数が面ごとに合うか (hair_count 本の屋敷。130 本では
## 埋もれた毛が描いている毛より少なく、描いている毛を先に消すと描き足しが計画した埋もれた毛を使い切る)
func _check_room_tool_takes_buried(hair_count: int) -> void:
	var made: Array = _make_budget_world(hair_count)
	var state: Node = made[0]
	var world: MansionWorld = made[1]
	var hair_field: Node3D = world.get_hair_field()
	var truck: StringName = ToolCatalogScript.TOOL_SUCTION_TRUCK
	state.purchase(GameStateScript.PURCHASE_TOOL, truck)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 12
	var drawn_before: int = 0
	for surface_index: int in range(hair_field.get_surface_count()):
		drawn_before += hair_field.get_surface_visible_instance_count(surface_index)
	_check(
		drawn_before > 0 and drawn_before <= 100 and hair_field.get_remaining_count() == hair_count,
		"描く本数の上限 100 本で %d 本の屋敷を組むと、描くのは 100 本までで残りは %d 本 (描いている %d 本)"
		% [hair_count, hair_count, drawn_before],
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
		"%d 本の屋敷で吸引車は描いている毛 (%d 本) より多い %d 本を取り、HairField の残り本数が面ごとに GameState と同じ (%d / %d 本)"
		% [
			hair_count, visible_taken, removed,
			hair_field.get_remaining_count(), state.get_total_remaining_hairs(),
		],
	)
	world.free()
	state.free()
	SaveStorageScript.delete_save_file(TEST_SAVE_PATH)


## 掃除ロボットが描いている同じ色の毛より多く取った時、足りない分を埋もれた毛から取り、色ごとの本数が合うか
func _check_robot_pick_takes_buried() -> void:
	var made: Array = _make_budget_world(6000)
	var state: Node = made[0]
	var world: MansionWorld = made[1]
	var hair_field: Node3D = world.get_hair_field()
	var white: int = HairFieldScript.HairColorGroup.WHITE
	var groups_before: PackedInt32Array = HairFieldScript.count_surface_groups(hair_field, 0)
	var drawn_white: int = 0
	for slot: int in range(hair_field.get_surface_visible_instance_count(0)):
		if world.get_hair_color_id(hair_field.get_hair_id_at_slot(0, slot)) == &"white":
			drawn_white += 1
	var count: int = drawn_white + 3
	AutomationController.remove_picked_hairs(world, 0, &"white", count, Vector3.ZERO)
	var groups_after: PackedInt32Array = HairFieldScript.count_surface_groups(hair_field, 0)
	_check(
		groups_before[white] > count
		and groups_after[white] == groups_before[white] - count
		and groups_after[HairFieldScript.HairColorGroup.BLACK]
		== groups_before[HairFieldScript.HairColorGroup.BLACK]
		and hair_field.get_surface_remaining_count(0)
		== groups_before[0] + groups_before[1] + groups_before[2] - count,
		"掃除ロボットが描いている白 (%d 本) より 3 本多く取ると、白だけが %d 本減る (白 %d → %d 本)"
		% [drawn_white, count, groups_before[white], groups_after[white]],
	)
	world.free()
	state.free()
	SaveStorageScript.delete_save_file(TEST_SAVE_PATH)

extends RefCounted
## 手で毛を取るルール (引く時間・手の強化・珍しい毛・図鑑)・GameState の 1 本取り・HairField の照会と向きの付いた表面・
## 物の毛が乗る面の検証スイート (scripts/dev/selfcheck.gd から呼ぶ)。

## 手で毛を取る時のルールの計算
const HandRulesScript := preload("res://scripts/hand/hand_rules.gd")
## 狙った毛をつまんで抜く操作 (毛を伸ばす見た目の純粋関数を使う)
const HandControllerScript := preload("res://scripts/hand/hand_controller.gd")
## 毛を 1 本ずつ持って描くノードのスクリプト
const HairFieldScript := preload("res://scripts/hair_field.gd")
## 屋敷レイアウト型スクリプト
const MansionLayoutScript := preload("res://scripts/mansion/mansion_layout.gd")
## 屋敷ビルダーロジックスクリプト
const MansionBuilderScript := preload("res://scripts/mansion/mansion_builder.gd")
## 面ごとの毛データ型スクリプト
const SurfaceHairScript := preload("res://scripts/data/surface_hair.gd")
## 毛・加工品在庫データ型スクリプト
const HairStockScript := preload("res://scripts/data/hair_stock.gd")
## JSON 保存ストレージスクリプト (一時セーブファイルの後片付けに使う)
const SaveStorageScript := preload("res://scripts/state/save_storage.gd")
## 状態管理 autoload スクリプト
const GameStateScript := preload("res://scripts/state/game_state.gd")
## 3D 屋敷構築ノードスクリプト
const MansionWorldScript := preload("res://scripts/mansion/mansion_world.gd")
## 開発者向け調整値データ型スクリプト
const MansionTuningScript := preload("res://scripts/data/mansion_tuning.gd")
## 図鑑の画面のスクリプト
const HairBookPanelScript := preload("res://scripts/ui/hair_book_panel.gd")
## selfcheck が使う一時セーブファイルパス (GameState の初期化だけに使い、保存はしない)
const TEST_SAVE_PATH: String = "user://selfcheck_hand_save_data.json"

## 検証結果を記録する selfcheck の SceneTree 参照
var _checker: SceneTree = null


## 手で毛を取る関連の検証をすべて実行する
static func run_all(checker: SceneTree) -> void:
	var suite: RefCounted = load("res://scripts/dev/selfcheck_hand.gd").new()
	suite._checker = checker
	suite._check_pull_seconds()
	suite._check_grab_count_and_levels()
	suite._check_rare_hair_roll()
	suite._check_register_rare_hair()
	suite._check_game_state_pluck_hair()
	suite._check_oriented_surface_and_queries()
	suite._check_group_counts_and_exclusions()
	suite._check_object_surface_faces()
	suite._check_world_hairs_match_progress()
	suite._check_stretched_hair_transform()
	suite._check_hair_book_panel()


## 検証結果を selfcheck 本体へ記録する
func _check(cond: bool, label: String) -> void:
	_checker._check(cond, label)


## 表面の種類と器用さの段から引く時間が決まり、絡む面ほど長く、強化で短くなり、下限で止まるか
func _check_pull_seconds() -> void:
	var floor_seconds: float = HandRulesScript.pull_seconds(MansionLayoutScript.SURFACE_FLOOR, 0)
	var knit_seconds: float = HandRulesScript.pull_seconds(MansionLayoutScript.SURFACE_KNIT, 0)
	var carpet_seconds: float = HandRulesScript.pull_seconds(MansionLayoutScript.SURFACE_CARPET, 0)
	_check(
		is_equal_approx(floor_seconds, 0.45)
		and is_equal_approx(carpet_seconds, 1.0)
		and is_equal_approx(knit_seconds, 1.3),
		"強化なしの引く時間が床 0.45 秒・カーペット 1.0 秒・ニット 1.3 秒",
	)
	_check(
		knit_seconds > carpet_seconds and carpet_seconds > floor_seconds,
		"毛が繊維に絡む面ほど引く時間が長い (ニット > カーペット > 床)",
	)
	_check(
		is_equal_approx(
			HandRulesScript.pull_seconds(MansionLayoutScript.SURFACE_KNIT, 1), 1.3 * 0.85
		)
		and is_equal_approx(
			HandRulesScript.pull_seconds(MansionLayoutScript.SURFACE_KNIT, 2), 1.3 * 0.85 * 0.85
		),
		"器用さ 1 段で 15% ずつ引く時間が短くなる",
	)
	_check(
		is_equal_approx(
			HandRulesScript.pull_seconds(MansionLayoutScript.SURFACE_FLOOR, 100),
			HandRulesScript.MIN_PULL_SECONDS,
		),
		"器用さを上げ続けても引く時間は下限 MIN_PULL_SECONDS で止まる",
	)
	_check(
		is_equal_approx(HandRulesScript.pull_seconds(MansionLayoutScript.SURFACE_FLOOR, -3), 0.45)
		and is_equal_approx(
			HandRulesScript.pull_seconds(&"unknown_surface", 0),
			HandRulesScript.DEFAULT_PULL_SECONDS,
		),
		"負の段は 0 段として扱い、表に無い面は既定の引く時間になる",
	)


## 一度につまめる本数が段に応じて増え、上下限で止まり、段の辞書の読み取りが欠落・負値に耐えるか
func _check_grab_count_and_levels() -> void:
	_check(
		HandRulesScript.grab_count(0) == 1
		and HandRulesScript.grab_count(2) == 3
		and HandRulesScript.grab_count(-5) == 1
		and HandRulesScript.grab_count(999) == HandRulesScript.MAX_GRAB_COUNT,
		"つまめる本数は 0 段で 1 本、2 段で 3 本、負の段で 1 本、上限で MAX_GRAB_COUNT",
	)
	_check(
		HandRulesScript.upgrade_level({}, HandRulesScript.UPGRADE_DEXTERITY) == 0
		and HandRulesScript.upgrade_level(
			{HandRulesScript.UPGRADE_DEXTERITY: 3}, HandRulesScript.UPGRADE_DEXTERITY
		) == 3
		and HandRulesScript.upgrade_level(
			{HandRulesScript.UPGRADE_GRAB_COUNT: -2}, HandRulesScript.UPGRADE_GRAB_COUNT
		) == 0,
		"手の強化の段は無ければ 0、あればその値、負値は 0 として読む",
	)


## 珍しい毛の抽選が確率の区間の境界どおりに種類を返し、色で出る種類が絞られるか
func _check_rare_hair_roll() -> void:
	var whisker_chance: float = 1.0 / 400.0
	var tricolor_chance: float = 1.0 / 250.0
	var golden_chance: float = 1.0 / 1500.0
	_check(
		HandRulesScript.roll_rare_hair(SurfaceHairScript.COLOR_CALICO, 0.0)
		== HandRulesScript.RARE_WHISKER
		and HandRulesScript.roll_rare_hair(SurfaceHairScript.COLOR_CALICO, whisker_chance * 0.999)
		== HandRulesScript.RARE_WHISKER,
		"乱数がヒゲの区間 [0, 1/400) に入るとヒゲになる",
	)
	_check(
		HandRulesScript.roll_rare_hair(SurfaceHairScript.COLOR_CALICO, whisker_chance)
		== HandRulesScript.RARE_TRICOLOR
		and HandRulesScript.roll_rare_hair(
			SurfaceHairScript.COLOR_CALICO, whisker_chance + tricolor_chance * 0.999
		) == HandRulesScript.RARE_TRICOLOR,
		"三毛の毛では、ヒゲの区間のすぐ後ろが三毛の 3 色そろいの区間になる",
	)
	_check(
		HandRulesScript.roll_rare_hair(SurfaceHairScript.COLOR_WHITE, whisker_chance)
		== HandRulesScript.RARE_GOLDEN
		and HandRulesScript.roll_rare_hair(
			SurfaceHairScript.COLOR_WHITE, whisker_chance + golden_chance
		) == &"",
		"白い毛では三毛の 3 色そろいが出ず、ヒゲの後ろが金色の毛の区間になり、その後ろはふつうの毛",
	)
	_check(
		HandRulesScript.roll_rare_hair(SurfaceHairScript.COLOR_CALICO, 0.5) == &""
		and HandRulesScript.roll_rare_hair(SurfaceHairScript.COLOR_BLACK, 0.999999) == &"",
		"乱数が珍しい毛の区間の外ならふつうの毛 (空)",
	)
	_check(
		is_equal_approx(
			HandRulesScript.rare_chance_for_color(SurfaceHairScript.COLOR_CALICO),
			whisker_chance + tricolor_chance + golden_chance,
		)
		and is_equal_approx(
			HandRulesScript.rare_chance_for_color(SurfaceHairScript.COLOR_BLACK),
			whisker_chance + golden_chance,
		),
		"色ごとの珍しい毛の確率の合計が表の確率の和 (三毛は 3 種類、黒は 2 種類)",
	)
	_check(
		HandRulesScript.rare_hair_name(HandRulesScript.RARE_WHISKER) == "猫のヒゲ"
		and HandRulesScript.rare_hair_name(&"missing") == "",
		"珍しい毛の表示名を表から引け、表に無い id は空文字",
	)


## 図鑑への登録が新しい種類だけを 1 回載せ、空と重複を載せないか
func _check_register_rare_hair() -> void:
	var found: Array[StringName] = []
	var first: bool = HandRulesScript.register_rare_hair(found, HandRulesScript.RARE_GOLDEN)
	var duplicate: bool = HandRulesScript.register_rare_hair(found, HandRulesScript.RARE_GOLDEN)
	var empty: bool = HandRulesScript.register_rare_hair(found, &"")
	_check(
		first and not duplicate and not empty
		and found.size() == 1 and found[0] == HandRulesScript.RARE_GOLDEN,
		"図鑑には新しい珍しい毛だけが 1 回載り、重複と空は載らない",
	)


## GameState.pluck_hair が面の本数を 1 減らし、毛のままの在庫を色と珍しさごとに 1 足し、図鑑に載せるか
func _check_game_state_pluck_hair() -> void:
	var state: Node = GameStateScript.new()
	state.initialize_from_storage(TEST_SAVE_PATH, PackedStringArray(["--hair-count=300"]))
	var surface: SurfaceHair = state.save_data.building_progress.surface_hairs[0]
	var color_id: StringName = SurfaceHairScript.COLOR_WHITE
	for candidate: StringName in SurfaceHairScript.STANDARD_COLORS:
		if surface.count_for_color(candidate) > 0:
			color_id = candidate
			break
	var before_surface: int = surface.count_for_color(color_id)
	var before_total: int = state.get_total_remaining_hairs()
	var notified: Array[int] = [0]
	state.state_changed.connect(func() -> void: notified[0] += 1)

	var normal: Dictionary = state.pluck_hair(surface.surface_id, color_id)
	var normal_again: Dictionary = state.pluck_hair(surface.surface_id, color_id)
	_check(
		bool(normal["plucked"]) and not bool(normal["new_rare"]) and bool(normal_again["plucked"])
		and surface.count_for_color(color_id) == before_surface - 2
		and state.get_total_remaining_hairs() == before_total - 2
		and state.get_raw_hair_stock_count() == 2
		and state.save_data.building_progress.hair_stocks.size() == 1
		and notified[0] == 2,
		"ふつうの毛を 2 本取ると面と総数が 2 減り、毛のままの在庫 1 件に 2 本まとまり、変化を 2 回知らせる",
	)

	var rare: Dictionary = state.pluck_hair(surface.surface_id, color_id, HandRulesScript.RARE_WHISKER)
	var rare_again: Dictionary = state.pluck_hair(
		surface.surface_id, color_id, HandRulesScript.RARE_WHISKER
	)
	var rare_stock: HairStock = null
	for stock: HairStock in state.save_data.building_progress.hair_stocks:
		if stock.rare_hair_id == HandRulesScript.RARE_WHISKER:
			rare_stock = stock
	_check(
		bool(rare["new_rare"]) and not bool(rare_again["new_rare"])
		and state.get_found_rare_hair_ids().size() == 1
		and state.get_found_rare_hair_ids()[0] == HandRulesScript.RARE_WHISKER
		and rare_stock != null and rare_stock.count == 2
		and rare_stock.form == HairStockScript.FORM_RAW and rare_stock.hair_color == color_id,
		"珍しい毛は別の在庫に入り、初めての 1 本だけが図鑑に新しく載る",
	)

	var missing_surface: Dictionary = state.pluck_hair(&"missing_surface", color_id)
	var empty_color: Dictionary = state.pluck_hair(surface.surface_id, &"no_such_color")
	_check(
		not bool(missing_surface["plucked"]) and not bool(empty_color["plucked"])
		and state.get_raw_hair_stock_count() == 4 and notified[0] == 4,
		"無い面・残っていない色の毛は取れず、在庫も通知も変わらない",
	)

	state.set_hand_upgrade_level(HandRulesScript.UPGRADE_DEXTERITY, 2)
	state.set_hand_upgrade_level(HandRulesScript.UPGRADE_GRAB_COUNT, -1)
	_check(
		state.get_hand_upgrade_level(HandRulesScript.UPGRADE_DEXTERITY) == 2
		and state.get_hand_upgrade_level(HandRulesScript.UPGRADE_GRAB_COUNT) == 0
		and state.save_data.hand_upgrade_levels.has(HandRulesScript.UPGRADE_DEXTERITY),
		"手の強化の段を保存データの hand_upgrade_levels に書き、負値は 0 にする",
	)
	state.free()
	SaveStorageScript.delete_save_file(TEST_SAVE_PATH)

	var empty_state: Node = GameStateScript.new()
	_check(
		not bool(empty_state.pluck_hair(&"any", SurfaceHairScript.COLOR_WHITE)["plucked"])
		and empty_state.get_raw_hair_stock_count() == 0
		and empty_state.get_hand_upgrade_level(HandRulesScript.UPGRADE_DEXTERITY) == 0
		and empty_state.get_found_rare_hair_ids().is_empty(),
		"save_data が null の GameState では毛を取れず、在庫・強化・図鑑は空として読む",
	)
	empty_state.free()


## 向きを付けた表面 (縦の面) に毛が面の上へ置かれ、光線の当たり判定と近くの毛の検索が面の向きどおりに動くか
func _check_oriented_surface_and_queries() -> void:
	var field: Node3D = HairFieldScript.new()
	# 原点 (0, 1, 0) の縦の面。法線は +Z、面の局所 X は世界の X、局所 Z は世界の -Y
	field.add_oriented_surface(
		"wall_face",
		Transform3D(MansionBuilderScript.FRONT_FACING_BASIS, Vector3(0.0, 1.0, 0.0)),
		Vector2(0.6, 0.4),
		1.0,
	)
	field.add_surface("floor", Vector3(-1.0, 0.0, -1.0), Vector3(1.0, 0.0, 1.0), 1.0)
	var counts: Array[PackedInt32Array] = [
		PackedInt32Array([10, 10, 10]), PackedInt32Array([5, 0, 0])
	]
	_check(field.populate_with_group_counts(counts, 7) == 35, "表面ごと・色ごとに指定した本数 35 本を置く")

	var on_face: bool = true
	for slot: int in range(field.get_surface_visible_instance_count(0)):
		var root: Vector3 = field.get_hair_transform(field.get_hair_id_at_slot(0, slot)).origin
		if (
			root.z < 0.0 or root.z > 0.01
			or absf(root.x) > 0.3 + 0.0001
			or absf(root.y - 1.0) > 0.2 + 0.0001
		):
			on_face = false
	_check(on_face, "縦の面の毛の根元が面の前 (法線 +Z 側 1cm 以内) で、面の矩形の中にある")

	var hit: Dictionary = field.intersect_surfaces(Vector3(0.1, 1.05, 2.0), Vector3(0, 0, -1), 5.0)
	_check(
		not hit.is_empty() and int(hit["surface_index"]) == 0
		and is_equal_approx(float(hit["distance"]), 2.0)
		and (hit["point"] as Vector3).is_equal_approx(Vector3(0.1, 1.05, 0.0)),
		"正面から縦の面へ向けた光線が距離 2m の面上の点に当たる",
	)
	_check(
		field.intersect_surfaces(Vector3(0.1, 1.05, -2.0), Vector3(0, 0, 1), 5.0).is_empty(),
		"面の裏から向けた光線は当たらない",
	)
	_check(
		field.intersect_surfaces(Vector3(0.1, 1.05, 2.0), Vector3(0, 0, -1), 1.5).is_empty(),
		"届く距離より遠い面には当たらない",
	)
	_check(
		field.intersect_surfaces(Vector3(0.5, 1.05, 2.0), Vector3(0, 0, -1), 5.0).is_empty(),
		"面の矩形の外 (x=0.5) を通る光線は当たらない",
	)
	var floor_hit: Dictionary = field.intersect_surfaces(
		Vector3(0.5, 1.6, 0.5), Vector3(0, -1, 0), 5.0
	)
	_check(
		not floor_hit.is_empty() and int(floor_hit["surface_index"]) == 1
		and is_equal_approx(float(floor_hit["distance"]), 1.6),
		"真下へ向けた光線が床の面に 1.6m で当たる",
	)

	var target_id: int = field.get_hair_id_at_slot(0, 0)
	var target_root: Vector3 = field.get_hair_transform(target_id).origin
	var nearest: PackedInt32Array = field.find_hairs_near(0, target_root, 0.05, 1)
	var many: PackedInt32Array = field.find_hairs_near(0, Vector3(0, 1, 0), 10.0, 100)
	_check(
		nearest.size() == 1 and nearest[0] == target_id,
		"毛の根元を狙うと、つまめる 1 本はその毛になる",
	)
	_check(
		many.size() == 30
		and field.get_hair_transform(many[0]).origin.distance_to(Vector3(0, 1, 0))
		<= field.get_hair_transform(many[29]).origin.distance_to(Vector3(0, 1, 0)),
		"半径内の毛を近い順に返し、その面の毛だけ (30 本) を返す",
	)
	_check(
		field.find_hairs_near(0, Vector3(5, 5, 5), 0.05, 3).is_empty()
		and field.find_hairs_near(-1, target_root, 1.0, 3).is_empty()
		and field.find_hairs_near(0, target_root, 1.0, 0).is_empty(),
		"半径内に毛が無い・面の添字が範囲外・本数 0 なら空を返す",
	)

	var rest: Transform3D = field.get_hair_transform(target_id)
	field.set_hair_display_transform(target_id, Transform3D(Basis.IDENTITY, Vector3(9, 9, 9)))
	var changed_display: bool = field.get_multimesh_slot_transform(0, 0).origin == Vector3(9, 9, 9)
	var kept_rest: bool = field.get_hair_transform(target_id) == rest
	field.set_hair_display_transform(target_id, rest)
	_check(
		kept_rest and field.get_hair_transform(target_id) == rest
		and (changed_display or DisplayServer.get_name() == "headless"),
		"伸ばす見た目を変えても照会用の位置は変わらず、元に戻せる",
	)
	field.free()


## 色ごとの本数で置いた毛の系統が指定どおりで、除外範囲 (物の下) に毛を置かないか
func _check_group_counts_and_exclusions() -> void:
	var field: Node3D = HairFieldScript.new()
	var under_box: Dictionary = {
		"inverse": Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 0.0)).affine_inverse(),
		"half": Vector2(0.5, 1.0),
	}
	var exclusions: Array[Dictionary] = [under_box]
	field.add_oriented_surface("floor", Transform3D.IDENTITY, Vector2(2.0, 2.0), 1.0, exclusions)
	var counts: Array[PackedInt32Array] = [PackedInt32Array([3, 5, 7])]
	field.populate_with_group_counts(counts, 11)
	var group_counts: PackedInt32Array = HairFieldScript.count_surface_groups(field, 0)
	_check(
		group_counts == PackedInt32Array([3, 5, 7]) and field.get_remaining_count() == 15,
		"色の系統ごとに白 3・黒 5・三毛 7 本を置く",
	)
	var outside: bool = true
	for slot: int in range(field.get_surface_visible_instance_count(0)):
		var root: Vector3 = field.get_hair_transform(field.get_hair_id_at_slot(0, slot)).origin
		if absf(root.x) <= 0.5:
			outside = false
	_check(outside, "除外範囲 (x が -0.5〜0.5 の帯) に毛を置かない")

	var short_counts: Array[PackedInt32Array] = []
	_check(
		field.populate_with_group_counts(short_counts) == 0 and field.get_remaining_count() == 0,
		"表面ごとの本数が足りない時は 0 本として扱う",
	)
	field.free()


## 物の毛が乗る面が、ソファは肘掛けの内側の座面、スーツは上着の前面 (縦)、ニットは背もたれより手前になるか
func _check_object_surface_faces() -> void:
	var sofa_size: Vector3 = Vector3(2.0, 0.85, 0.9)
	var sofa: Dictionary = MansionBuilderScript.object_surface_local_face(
		MansionLayoutScript.OBJECT_SOFA, sofa_size
	)
	var sofa_center: Vector3 = sofa["center"]
	var sofa_face: Vector2 = sofa["size"]
	var arm_inner_x: float = (
		MansionBuilderScript.SOFA_ARM_OFFSET_RATIO - MansionBuilderScript.SOFA_ARM_WIDTH_RATIO * 0.5
	) * sofa_size.x
	var back_front_z: float = (
		MansionBuilderScript.SOFA_BACKREST_OFFSET_RATIO
		+ MansionBuilderScript.SOFA_BACKREST_DEPTH_RATIO * 0.5
	) * sofa_size.z
	_check(
		is_equal_approx(sofa_center.y, sofa_size.y * MansionBuilderScript.SOFA_SEAT_HEIGHT_RATIO)
		and is_equal_approx(sofa_face.x * 0.5, arm_inner_x)
		and is_equal_approx(sofa_center.z - sofa_face.y * 0.5, back_front_z)
		and is_equal_approx(sofa_center.z + sofa_face.y * 0.5, sofa_size.z * 0.5),
		"ソファの面は座面の高さで、肘掛けの内側・背もたれの前端から前の縁まで",
	)

	var suit_size: Vector3 = Vector3(0.6, 1.8, 0.5)
	var suit: Dictionary = MansionBuilderScript.object_surface_local_face(
		MansionLayoutScript.OBJECT_SUIT_RACK, suit_size
	)
	var suit_basis: Basis = suit["basis"]
	var jacket_front_z: float = MansionBuilderScript.SUIT_JACKET_SIZE_RATIO.z * suit_size.z * 0.5
	_check(
		suit_basis.y.is_equal_approx(Vector3(0, 0, 1))
		and is_equal_approx((suit["center"] as Vector3).z, jacket_front_z)
		and is_equal_approx(
			(suit["center"] as Vector3).y,
			MansionBuilderScript.SUIT_JACKET_CENTER_RATIO.y * suit_size.y,
		)
		and is_equal_approx(
			(suit["size"] as Vector2).y, MansionBuilderScript.SUIT_JACKET_SIZE_RATIO.y * suit_size.y
		),
		"スーツの面は上着の前面で、法線が物の前 (+Z) を向く縦の面",
	)

	var chair_size: Vector3 = Vector3(0.7, 1.0, 0.7)
	var knit: Dictionary = MansionBuilderScript.object_surface_local_face(
		MansionLayoutScript.OBJECT_KNIT_CHAIR, chair_size
	)
	var chair_back_front: float = (
		MansionBuilderScript.CHAIR_BACK_CENTER_RATIO.z * chair_size.z
		+ MansionBuilderScript.CHAIR_BACK_SIZE_RATIO.z * chair_size.z * 0.5
	)
	var throw_top: float = (
		MansionBuilderScript.KNIT_THROW_CENTER_RATIO.y * chair_size.y
		+ MansionBuilderScript.KNIT_THROW_SIZE_RATIO.y * chair_size.y * 0.5
	)
	_check(
		is_equal_approx((knit["center"] as Vector3).y, throw_top)
		and is_equal_approx(
			(knit["center"] as Vector3).z - (knit["size"] as Vector2).y * 0.5, chair_back_front
		)
		and (knit["size"] as Vector2).y > 0.0,
		"ニットの面は掛け布の上面で、椅子の背もたれの前端より手前",
	)

	var table: Dictionary = MansionBuilderScript.object_surface_local_face(
		MansionLayoutScript.OBJECT_TABLE, Vector3(1.2, 0.75, 0.8)
	)
	var sideboard: Dictionary = MansionBuilderScript.object_surface_local_face(
		MansionLayoutScript.OBJECT_SIDEBOARD, Vector3(1.2, 0.9, 0.45)
	)
	_check(
		(table["center"] as Vector3).is_equal_approx(Vector3(0.0, 0.75, 0.0))
		and (table["size"] as Vector2).is_equal_approx(Vector2(1.2, 0.8))
		and is_equal_approx(
			(sideboard["center"] as Vector3).y, 0.9 + MansionBuilderScript.SIDEBOARD_TOP_TRIM_HEIGHT_M
		),
		"テーブルの面は天板の上面全体、サイドボードは装飾縁の上面",
	)

	var layout: MansionLayout = MansionBuilderScript.build_layout(null)
	var all_faces_match: bool = true
	for obj: MansionLayout.ObjectDef in layout.objects:
		var surface: MansionLayout.SurfaceDef = layout.find_surface(
			StringName("%s_surface" % String(obj.object_id))
		)
		var face: Dictionary = MansionBuilderScript.object_surface_local_face(
			obj.object_kind, obj.size
		)
		var object_frame: Transform3D = Transform3D(Basis(Vector3.UP, obj.rotation_y), obj.position)
		if (
			surface == null
			or not surface.center.is_equal_approx(object_frame * (face["center"] as Vector3))
			or not surface.basis.y.is_equal_approx(object_frame.basis * (face["basis"] as Basis).y)
		):
			all_faces_match = false
	_check(all_faces_match, "既定屋敷の物の表面が、物の位置と向きで回した面の中心・法線と一致する")


## MansionWorld の毛 (HairField) が SurfaceHair と面ごと・色ごとに同じ本数で、床の毛が物の真下に無いか
func _check_world_hairs_match_progress() -> void:
	var tuning: MansionTuning = MansionTuningScript.new()
	tuning.room_count = 4
	tuning.object_count = 16
	tuning.hair_count = 12000
	var layout: MansionLayout = MansionBuilderScript.build_layout(tuning)
	var progress: BuildingProgress = MansionBuilderScript.build_initial_progress(layout, tuning)
	var world: MansionWorld = MansionWorldScript.new()
	world.rebuild(layout, progress)
	var hair_field: Node3D = world.get_hair_field()
	var counts_match: bool = hair_field.get_remaining_count() == 12000
	for surface_idx: int in range(layout.surfaces.size()):
		var surface_hair: SurfaceHair = progress.find_surface_hair(
			layout.surfaces[surface_idx].surface_id
		)
		var group_counts: PackedInt32Array = HairFieldScript.count_surface_groups(
			hair_field, surface_idx
		)
		for group: int in range(MansionWorldScript.HAIR_COLOR_BY_GROUP.size()):
			if group_counts[group] != surface_hair.count_for_color(
				MansionWorldScript.HAIR_COLOR_BY_GROUP[group]
			):
				counts_match = false
	_check(counts_match, "既定屋敷の HairField の本数が面ごと・色ごとに SurfaceHair と一致する (計 12000)")
	_check(
		MansionWorldScript.HAIR_COLOR_BY_GROUP[HairFieldScript.HairColorGroup.WHITE]
		== SurfaceHairScript.COLOR_WHITE
		and MansionWorldScript.HAIR_COLOR_BY_GROUP[HairFieldScript.HairColorGroup.BLACK]
		== SurfaceHairScript.COLOR_BLACK
		and MansionWorldScript.HAIR_COLOR_BY_GROUP[HairFieldScript.HairColorGroup.CALICO]
		== SurfaceHairScript.COLOR_CALICO,
		"HairField の色の系統と SurfaceHair の色が同じ並びで対応する",
	)
	_check(_floor_hairs_clear_of_objects(layout, hair_field), "床の毛が同じ部屋の物の真下に置かれない")
	var first_hair: int = hair_field.get_hair_id_at_slot(0, 0)
	_check(
		world.get_hair_color_id(first_hair)
		== MansionWorldScript.HAIR_COLOR_BY_GROUP[
			HairFieldScript.classify_hair_color(hair_field.get_hair_color(first_hair))
		]
		and world.get_hair_color_id(-1) == &""
		and world.get_surface_def(0) == layout.surfaces[0]
		and world.get_surface_def(-1) == null,
		"屋敷から毛の色 (SurfaceHair の色) と表面の定義を引け、無い毛・面は空と null",
	)
	world.free()


## 床の表面の毛の根元が、同じ部屋の物の床の占有範囲の内側に 1 本も無いか
func _floor_hairs_clear_of_objects(layout: MansionLayout, hair_field: Node3D) -> bool:
	for surface_idx: int in range(layout.surfaces.size()):
		var surface: MansionLayout.SurfaceDef = layout.surfaces[surface_idx]
		if surface.surface_type != MansionLayoutScript.SURFACE_FLOOR:
			continue
		for slot: int in range(hair_field.get_surface_visible_instance_count(surface_idx)):
			var root: Vector3 = hair_field.get_hair_transform(
				hair_field.get_hair_id_at_slot(surface_idx, slot)
			).origin
			for obj: MansionLayout.ObjectDef in layout.objects:
				if obj.room_id != surface.room_id:
					continue
				var local: Vector3 = (
					Transform3D(Basis(Vector3.UP, obj.rotation_y), obj.position).affine_inverse()
					* root
				)
				if (
					absf(local.x) < obj.size.x * 0.5 - 0.001
					and absf(local.z) < obj.size.z * 0.5 - 0.001
				):
					return false
	return true


## 引いている毛の見た目が、根元を保ったまま面の法線へ起き、長く・太くなるか
func _check_stretched_hair_transform() -> void:
	var rest: Transform3D = Transform3D(Basis.IDENTITY, Vector3(1.0, 0.0, 2.0))
	var at_zero: Transform3D = HandControllerScript.stretched_hair_transform(rest, Vector3.UP, 0.0)
	var at_one: Transform3D = HandControllerScript.stretched_hair_transform(rest, Vector3.UP, 1.0)
	_check(at_zero.is_equal_approx(rest), "進み具合 0 では配置時と同じ見た目")
	_check(
		at_one.origin.is_equal_approx(rest.origin)
		and is_equal_approx(at_one.basis.z.length(), HandControllerScript.MAX_STRETCH_RATIO)
		and is_equal_approx(at_one.basis.x.length(), HandControllerScript.PULL_WIDTH_RATIO)
		and at_one.basis.z.normalized().dot(Vector3.UP) > 0.9,
		"引き終える時は根元を保ったまま、長さ 2.2 倍・幅 3 倍で法線 (上) へ起きる",
	)
	var over: Transform3D = HandControllerScript.stretched_hair_transform(rest, Vector3.UP, 5.0)
	_check(over.is_equal_approx(at_one), "進み具合が 1 を超えても 1 と同じ見た目")


## 図鑑の画面が、見つけた珍しい毛だけ名前を出し、見つけた数を数えるか
func _check_hair_book_panel() -> void:
	var panel: PanelContainer = HairBookPanelScript.new()
	var none: Array[StringName] = []
	panel.refresh(none)
	var empty_texts: PackedStringArray = panel.get_entry_texts()
	_check(
		panel.get_summary_text() == "見つけた珍しい毛: 0 / 3 種類"
		and empty_texts.size() == 3
		and empty_texts[0] == "・%s" % HairBookPanelScript.UNKNOWN_TEXT,
		"何も見つけていない図鑑は 0 / 3 種類で、すべて ？？？",
	)
	var found: Array[StringName] = [HandRulesScript.RARE_GOLDEN]
	panel.refresh(found)
	var texts: PackedStringArray = panel.get_entry_texts()
	_check(
		panel.get_summary_text() == "見つけた珍しい毛: 1 / 3 種類"
		and texts[2] == "・金色の毛"
		and texts[0] == "・%s" % HairBookPanelScript.UNKNOWN_TEXT,
		"金色の毛を見つけた図鑑は 1 / 3 種類で、金色の毛だけ名前が出る",
	)
	panel.free()

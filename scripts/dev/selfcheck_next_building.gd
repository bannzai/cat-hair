extends RefCounted
## 次の建物へ進む決まり (scripts/building/building_rules.gd) と入口 (GameState.next_building) の検証スイート
## (scripts/dev/selfcheck.gd から呼ぶ)。進める条件 (住人全員がご機嫌の時だけ)、持ち越す物と置いていく物、
## 探し物を返した数が持ち越す手の強化に効くことを確かめる。

## 検証する決まり
const BuildingRulesScript := preload("res://scripts/building/building_rules.gd")
## 状態管理 autoload スクリプト (買う物の種類の定数を使う)
const GameStateScript := preload("res://scripts/state/game_state.gd")
## JSON 保存ストレージスクリプト (一時セーブを消す)
const SaveStorageScript := preload("res://scripts/state/save_storage.gd")
## 開発者向け調整値データ型スクリプト
const MansionTuningScript := preload("res://scripts/data/mansion_tuning.gd")
## 建物進行データ型スクリプト (屋敷の id)
const BuildingProgressScript := preload("res://scripts/data/building_progress.gd")
## 探し物進捗データ型スクリプト
const FoundItemProgressScript := preload("res://scripts/data/found_item_progress.gd")
## 掃除代・機嫌の計算 (ご機嫌の線)
const EconomyRulesScript := preload("res://scripts/economy/economy_rules.gd")
## 屋敷に入った時の住人の機嫌
const MansionBuilderScript := preload("res://scripts/mansion/mansion_builder.gd")
## 手で毛を取る時のルールの計算 (手の強化の id)
const HandRulesScript := preload("res://scripts/hand/hand_rules.gd")
## 手に持って使う道具のルールの計算 (手の強化の段の上限)
const ToolRulesScript := preload("res://scripts/tools/tool_rules.gd")
## 手に持って使う道具の定義
const ToolCatalogScript := preload("res://scripts/tools/tool_catalog.gd")
## この検証だけが使う一時セーブのパス
const TEST_SAVE_PATH: String = "user://selfcheck_next_building_save_data.json"
## 検証の屋敷の毛の本数 (組み立てを軽くする本数)
const TEST_HAIR_COUNT: int = 400
## 検証の屋敷の部屋の数。2 にしたのは、住人が 2 人以上いて「1 人でもご機嫌でなければ進めない」を確かめられる最小の数のため
const TEST_ROOM_COUNT: int = 2
## 道具を買えるよう持たせる所持金 (integration からも使う)
const PLENTY_OF_MONEY: int = 1000000

## 検証結果を記録する selfcheck の SceneTree 参照
var _checker: SceneTree = null


## 次の建物へ進む決まりの検証をすべて実行する
static func run_all(checker: SceneTree) -> void:
	var suite: RefCounted = load("res://scripts/dev/selfcheck_next_building.gd").new()
	suite._checker = checker
	suite._check_building_order()
	suite._check_building_tuning()
	suite._check_advance_condition()
	suite._check_record()
	suite._check_carried_hand_upgrades()
	suite._check_game_state_advance()
	suite._check_last_building_and_new_game()
	suite._check_advance_without_progress()


## 検証結果を selfcheck 本体へ記録する
func _check(cond: bool, label: String) -> void:
	_checker._check(cond, label)


## 建物の並び (屋敷 → ホテル → 猫島 → 街全体) と、終えた数からの今いる建物・次の建物の有無
func _check_building_order() -> void:
	_check(
		BuildingRulesScript.BUILDING_ORDER == [
			BuildingProgressScript.BUILDING_MANSION,
			BuildingRulesScript.BUILDING_HOTEL,
			BuildingRulesScript.BUILDING_CAT_ISLAND,
			BuildingRulesScript.BUILDING_CITY,
		],
		"建物の並びは 屋敷 → ホテル → 猫島 → 街全体",
	)
	_check(
		BuildingRulesScript.building_id_at(0) == BuildingProgressScript.BUILDING_MANSION
		and BuildingRulesScript.building_id_at(1) == BuildingRulesScript.BUILDING_HOTEL
		and BuildingRulesScript.building_id_at(9) == BuildingRulesScript.BUILDING_CITY
		and BuildingRulesScript.building_index(-1) == 0,
		"終えた建物の数で今いる建物が決まり、最後の建物より先には進まない",
	)
	_check(
		BuildingRulesScript.has_next_building(0)
		and BuildingRulesScript.has_next_building(2)
		and not BuildingRulesScript.has_next_building(3)
		and not BuildingRulesScript.has_next_building(-1),
		"街全体 (最後の建物) の次の建物は無い",
	)
	_check(
		BuildingRulesScript.building_name(BuildingRulesScript.BUILDING_HOTEL) == "ホテル"
		and BuildingRulesScript.building_name(&"unknown") == "unknown",
		"建物の表示名 (並びに無い id はそのまま)",
	)


## 次の建物の作り: 最初の屋敷は調整値のまま、建物が進むごとに部屋が増え、毛・物・探し物が部屋の数に比例する
func _check_building_tuning() -> void:
	var base: MansionTuning = MansionTuningScript.new()
	base.hair_count = 1000
	base.room_count = 4
	base.object_count = 8
	base.found_item_count = 4
	_check(
		BuildingRulesScript.building_tuning(base, 0).equals(base),
		"最初の屋敷は開発者向けの調整値のままの作り",
	)
	var hotel: MansionTuning = BuildingRulesScript.building_tuning(base, 1)
	_check(
		hotel.room_count == 4 + BuildingRulesScript.EXTRA_ROOMS_PER_BUILDING
		and hotel.hair_count == 1500
		and hotel.object_count == 12
		and hotel.found_item_count == 6
		and is_equal_approx(hotel.room_size_m, base.room_size_m),
		"2 つ目の建物は部屋が 2 つ増え、毛・物・探し物が部屋の数に比例して増える (実際: %s)" % str(hotel.to_dict()),
	)
	var crowded_tuning: MansionTuning = base.clamped()
	crowded_tuning.room_count = MansionTuningScript.MAX_ROOM_COUNT
	_check(
		BuildingRulesScript.building_tuning(crowded_tuning, 3).equals(crowded_tuning),
		"部屋の数が上限の時は、次の建物も同じ作り (上限で丸める)",
	)
	_check(base.hair_count == 1000 and base.room_count == 4, "元の調整値は変えない")
	var near_max_tuning: MansionTuning = base.clamped()
	near_max_tuning.hair_count = MansionTuningScript.MAX_HAIR_COUNT
	near_max_tuning.object_count = MansionTuningScript.MAX_OBJECT_COUNT
	near_max_tuning.found_item_count = MansionTuningScript.MAX_FOUND_ITEM_COUNT
	var near_max_hotel: MansionTuning = BuildingRulesScript.building_tuning(near_max_tuning, 1)
	_check(
		near_max_hotel.room_count == 4 + BuildingRulesScript.EXTRA_ROOMS_PER_BUILDING
		and near_max_hotel.hair_count == MansionTuningScript.MAX_HAIR_COUNT
		and near_max_hotel.object_count == MansionTuningScript.MAX_OBJECT_COUNT
		and near_max_hotel.found_item_count == MansionTuningScript.MAX_FOUND_ITEM_COUNT,
		"部屋の数に比例させた毛・物・探し物の数は、それぞれの上限で丸める (実際: %s)"
		% str(near_max_hotel.to_dict()),
	)
	_check(
		BuildingRulesScript.building_tuning(null, 0).equals(MansionTuningScript.new().clamped()),
		"調整値が無い時は、既定の調整値の屋敷の作りを使う",
	)


## 進める条件: 住人全員がご機嫌の時だけ (ご機嫌の線ちょうどは進める、1 人でも下なら進めない)
func _check_advance_condition() -> void:
	var happy_mood_line: float = EconomyRulesScript.HAPPY_MOOD
	_check(
		BuildingRulesScript.can_advance(0, [happy_mood_line, 1.0])
		and not BuildingRulesScript.can_advance(0, [1.0, happy_mood_line - 0.001])
		and not BuildingRulesScript.can_advance(0, [MansionBuilderScript.INITIAL_RESIDENT_MOOD])
		and not BuildingRulesScript.can_advance(0, Array([], TYPE_FLOAT, &"", null)),
		"住人全員がご機嫌の時だけ進める (線ちょうどは進め、1 人でも下か住人がいなければ進めない)",
	)
	_check(
		BuildingRulesScript.can_advance(2, [1.0])
		and not BuildingRulesScript.can_advance(3, [1.0]),
		"最後の建物 (街全体) では全員がご機嫌でも次へは進まない",
	)


## 成績: かかった時間と、住人に返した探し物の数 (返していない物は数えない。探し物が無ければ 0)
func _check_record() -> void:
	var progress: BuildingProgress = BuildingProgressScript.new()
	progress.elapsed_seconds = 4321.5
	_check(
		BuildingRulesScript.make_record(progress).returned_found_item_count == 0,
		"探し物がまだ無い時は、返した数を 0 として扱う",
	)
	var negative_elapsed_progress: BuildingProgress = BuildingProgressScript.new()
	negative_elapsed_progress.elapsed_seconds = -5.0
	_check(
		BuildingRulesScript.make_record(negative_elapsed_progress).clear_seconds == 0.0,
		"遊んだ時間が負の値の時も、成績のかかった時間は 0 秒にする",
	)
	for returned: bool in [true, false, true]:
		var item: FoundItemProgress = FoundItemProgressScript.new()
		item.condition = FoundItemProgressScript.Condition.CLEAN
		item.is_returned = returned
		progress.found_items.append(item)
	var record: BuildingRecord = BuildingRulesScript.make_record(progress)
	_check(
		record.building_id == BuildingProgressScript.BUILDING_MANSION
		and is_equal_approx(record.clear_seconds, 4321.5)
		and record.returned_found_item_count == 2,
		"成績は建物の id・遊んだ時間・住人に返した探し物の数 (見つけただけの物は数えない)",
	)


## 持ち越す手の強化: 買った段はそのまま残り、返した探し物 1 つにつき 1 段をいちばん低い強化に足す (上限まで)
func _check_carried_hand_upgrades() -> void:
	var bought: Dictionary = {
		HandRulesScript.UPGRADE_DEXTERITY: 2, HandRulesScript.UPGRADE_GRAB_COUNT: 0
	}
	var none_returned: Dictionary = BuildingRulesScript.carried_hand_upgrades(bought, 0)
	_check(
		HandRulesScript.upgrade_level(none_returned, HandRulesScript.UPGRADE_DEXTERITY) == 2
		and HandRulesScript.upgrade_level(none_returned, HandRulesScript.UPGRADE_GRAB_COUNT) == 0,
		"探し物を返していなくても、買った手の強化の段はそのまま持ち越す",
	)
	var three_returned: Dictionary = BuildingRulesScript.carried_hand_upgrades(bought, 3)
	_check(
		HandRulesScript.upgrade_level(three_returned, HandRulesScript.UPGRADE_DEXTERITY) == 3
		and HandRulesScript.upgrade_level(three_returned, HandRulesScript.UPGRADE_GRAB_COUNT) == 2,
		"返した探し物 3 つで 3 段を、段の低い強化から足す (実際: %s)" % str(three_returned),
	)
	_check(
		HandRulesScript.upgrade_level(bought, HandRulesScript.UPGRADE_DEXTERITY) == 2
		and HandRulesScript.upgrade_level(bought, HandRulesScript.UPGRADE_GRAB_COUNT) == 0,
		"持ち越しの計算は元の段を変えない",
	)
	var previous_total: int = -1
	var increasing: bool = true
	for returned: int in range(6):
		var carried: Dictionary = BuildingRulesScript.carried_hand_upgrades(bought, returned)
		var total: int = (
			HandRulesScript.upgrade_level(carried, HandRulesScript.UPGRADE_DEXTERITY)
			+ HandRulesScript.upgrade_level(carried, HandRulesScript.UPGRADE_GRAB_COUNT)
		)
		increasing = increasing and total == 2 + returned and total > previous_total
		previous_total = total
	_check(increasing, "返した探し物が多いほど、持ち越す手の強化の段が多い")
	var max_level: int = ToolRulesScript.MAX_HAND_UPGRADE_LEVEL
	var near_max_levels: Dictionary = BuildingRulesScript.carried_hand_upgrades(
		{
			HandRulesScript.UPGRADE_DEXTERITY: max_level,
			HandRulesScript.UPGRADE_GRAB_COUNT: max_level - 1,
		},
		5
	)
	_check(
		HandRulesScript.upgrade_level(near_max_levels, HandRulesScript.UPGRADE_DEXTERITY)
		== max_level
		and HandRulesScript.upgrade_level(near_max_levels, HandRulesScript.UPGRADE_GRAB_COUNT)
		== max_level,
		"持ち越しで足す段は上限 (%d 段) を超えない" % max_level,
	)


## GameState の入口: 全員がご機嫌でない時は何も変えず、ご機嫌の時に進むと手の強化・図鑑・成績を残し、
## お金・道具・在庫を置いていき、次の建物の作り (部屋が増えた屋敷) で毛と機嫌が戻る。読み戻しても同じ
func _check_game_state_advance() -> void:
	var state: Node = _new_state()
	var base_tuning: MansionTuning = state.get_tuning().clamped()
	var progress: BuildingProgress = state.save_data.building_progress
	progress.money = PLENTY_OF_MONEY
	_check(
		state.purchase(GameStateScript.PURCHASE_TOOL, ToolCatalogScript.TOOL_PACKING_TAPE)
		and state.purchase(GameStateScript.PURCHASE_HAND_UPGRADE, HandRulesScript.UPGRADE_GRAB_COUNT),
		"検証の前提: 道具と手の強化を買える",
	)
	state.save_data.found_rare_hair_ids.append(HandRulesScript.RARE_WHISKER)
	progress.found_items[0].is_returned = true
	progress.elapsed_seconds = 3600.0
	var surface: SurfaceHair = progress.surface_hairs[0]
	state.pluck_hair(surface.surface_id, surface.hair_counts.keys()[0])
	var money_before: int = progress.money

	_check(
		not state.next_building.can_advance() and state.next_building.advance() == null,
		"住人がご機嫌でない時 (屋敷に入った時の機嫌) は進めない",
	)
	_check(
		state.save_data.building_progress == progress
		and progress.money == money_before
		and state.save_data.building_records.is_empty(),
		"進めない時は何も変えない",
	)
	make_everyone_happy(state)
	progress.resident_moods[progress.resident_moods.keys()[0]] = EconomyRulesScript.HAPPY_MOOD - 0.01
	_check(not state.next_building.can_advance(), "1 人でもご機嫌でなければ進めない")
	make_everyone_happy(state)
	_check(state.next_building.can_advance(), "住人全員がご機嫌なら進める")

	var record: BuildingRecord = state.next_building.advance()
	var next_tuning: MansionTuning = BuildingRulesScript.building_tuning(base_tuning, 1)
	_check(
		record != null
		and record.building_id == BuildingProgressScript.BUILDING_MANSION
		and is_equal_approx(record.clear_seconds, 3600.0)
		and record.returned_found_item_count == 1
		and state.save_data.building_records.size() == 1,
		"進むと屋敷の成績 (かかった時間・返した探し物の数) を記録する",
	)
	var next_progress: BuildingProgress = state.save_data.building_progress
	_check(
		next_progress.building_id == BuildingRulesScript.BUILDING_HOTEL
		and state.current_layout.rooms.size() == next_tuning.room_count
		and state.get_total_remaining_hairs() == next_tuning.hair_count
		and next_progress.elapsed_seconds == 0.0,
		"進んだ先は次の建物の作りで、残りの毛が最初の本数に戻る (残り %d 本、期待 %d 本)"
		% [state.get_total_remaining_hairs(), next_tuning.hair_count],
	)
	_check(
		next_progress.money == 0
		and next_progress.owned_tools.is_empty()
		and next_progress.hair_stocks.is_empty()
		and state.find_owned_tool(ToolCatalogScript.TOOL_PACKING_TAPE) == null,
		"お金・道具・在庫は置いていく (次の建物でも手で取るところから始める)",
	)
	var initial_mood_everywhere: bool = true
	for mood: float in state.next_building.resident_moods():
		initial_mood_everywhere = (
			initial_mood_everywhere and is_equal_approx(mood, MansionBuilderScript.INITIAL_RESIDENT_MOOD)
		)
	_check(
		initial_mood_everywhere and not state.next_building.can_advance(),
		"次の建物の住人は入った時の機嫌から始まり、すぐには進めない",
	)
	_check(
		state.get_hand_upgrade_level(HandRulesScript.UPGRADE_GRAB_COUNT) == 1
		and state.get_hand_upgrade_level(HandRulesScript.UPGRADE_DEXTERITY) == 1
		and state.get_found_rare_hair_ids() == [HandRulesScript.RARE_WHISKER]
		and state.get_tuning().equals(base_tuning),
		"買った手の強化と返した探し物 1 つ分の 1 段・図鑑を持ち越し、開発者向けの調整値は最初の屋敷のまま",
	)

	var reloaded: Node = GameStateScript.new()
	reloaded.initialize_from_storage(TEST_SAVE_PATH)
	_check(
		reloaded.loaded_from_save
		and reloaded.save_data.building_progress.building_id == BuildingRulesScript.BUILDING_HOTEL
		and reloaded.current_layout.rooms.size() == next_tuning.room_count
		and reloaded.get_total_remaining_hairs() == next_tuning.hair_count
		and reloaded.get_money() == 0
		and reloaded.save_data.building_records.size() == 1
		and reloaded.get_hand_upgrade_level(HandRulesScript.UPGRADE_DEXTERITY) == 1
		and reloaded.get_hand_upgrade_level(HandRulesScript.UPGRADE_GRAB_COUNT) == 1,
		"進んだ後の保存を読み戻すと、同じ建物・残りの毛・成績・手の強化で続きから遊べる",
	)
	_check_room_cleanliness(state, "進んだ直後")
	_check_room_cleanliness(reloaded, "読み戻した後")
	reloaded.free()
	state.free()
	SaveStorageScript.delete_save_file(TEST_SAVE_PATH)


## 次の建物で増えた部屋 (最後の部屋) の毛を半分にすると、きれいさがその建物に入った時の本数を分母にした値 (0.5 前後) になる。
## 分母を最初の屋敷の作りから取ると、最初の屋敷に無い部屋の分母が 0 になり、毛が残る間はきれいさが 0 になる
func _check_room_cleanliness(state: Node, timing_label: String) -> void:
	var room_id: StringName = state.current_layout.rooms.back().room_id
	var initial_room_hair_count: int = int(state.get_room_status(room_id)["hair_count"])
	for surface_def: MansionLayout.SurfaceDef in state.current_layout.surfaces:
		if surface_def.room_id != room_id:
			continue
		var surface: SurfaceHair = state.save_data.building_progress.find_surface_hair(
			surface_def.surface_id
		)
		for color_key: Variant in surface.hair_counts.keys():
			surface.hair_counts[color_key] = int(surface.hair_counts[color_key]) / 2
	var remaining: int = int(state.get_room_status(room_id)["hair_count"])
	var cleanliness: float = float(state.get_room_status(room_id)["cleanliness"])
	_check(
		remaining < initial_room_hair_count
		and cleanliness > 0.0
		and is_equal_approx(
			cleanliness, EconomyRulesScript.cleanliness(remaining, initial_room_hair_count)
		),
		"%s、次の建物のきれいさはその建物に入った時の部屋の毛 (%d 本) を分母にする (残り %d 本できれいさ %.2f)"
		% [timing_label, initial_room_hair_count, remaining, cleanliness],
	)


## 保存データはあるが今いる建物の進行が無い時は、進めず何も変えない
func _check_advance_without_progress() -> void:
	var state: Node = _new_state()
	make_everyone_happy(state)
	state.save_data.building_progress = null
	_check(
		not state.next_building.can_advance()
		and state.next_building.advance() == null
		and state.save_data.building_records.is_empty(),
		"今いる建物の進行が無い時は進めない",
	)
	state.free()
	var uninitialized: Node = GameStateScript.new()
	_check(
		uninitialized.next_building.building_index() == 0
		and uninitialized.next_building.resident_moods().is_empty()
		and not uninitialized.next_building.can_advance()
		and uninitialized.next_building.advance() == null,
		"保存データを読む前の GameState では、今いる建物は屋敷で、住人がいないため進めない",
	)
	uninitialized.free()
	SaveStorageScript.delete_save_file(TEST_SAVE_PATH)


## 最後の建物 (街全体) では進めず、「はじめから」は屋敷・手の強化なし・成績なしに戻す
func _check_last_building_and_new_game() -> void:
	var state: Node = _new_state()
	for _index: int in range(BuildingRulesScript.BUILDING_ORDER.size() - 1):
		make_everyone_happy(state)
		if state.next_building.advance() == null:
			break
	_check(
		state.save_data.building_progress.building_id == BuildingRulesScript.BUILDING_CITY
		and state.save_data.building_records.size() == 3,
		"屋敷からホテル・猫島を経て街全体まで進める",
	)
	make_everyone_happy(state)
	_check(
		not state.next_building.can_advance() and state.next_building.advance() == null,
		"最後の建物 (街全体) では全員がご機嫌でも次へは進まない",
	)
	state.set_hand_upgrade_level(HandRulesScript.UPGRADE_DEXTERITY, 4)
	state.start_new_game()
	_check(
		state.save_data.building_progress.building_id == BuildingProgressScript.BUILDING_MANSION
		and state.save_data.building_records.is_empty()
		and state.get_hand_upgrade_level(HandRulesScript.UPGRADE_DEXTERITY) == 0
		and state.current_layout.rooms.size() == TEST_ROOM_COUNT,
		"「はじめから」は最初の屋敷の作りに戻し、手の強化と成績も消す",
	)
	state.free()
	SaveStorageScript.delete_save_file(TEST_SAVE_PATH)


## 検証の屋敷 (毛 TEST_HAIR_COUNT 本・TEST_ROOM_COUNT 部屋) で始めた GameState を作る (呼び出し側が free する)
func _new_state() -> Node:
	SaveStorageScript.delete_save_file(TEST_SAVE_PATH)
	var state: Node = GameStateScript.new()
	state.initialize_from_storage(
		TEST_SAVE_PATH,
		PackedStringArray([
			"%s%d" % [MansionTuningScript.ARG_HAIR_COUNT, TEST_HAIR_COUNT],
			"%s%d" % [MansionTuningScript.ARG_ROOM_COUNT, TEST_ROOM_COUNT],
		]),
	)
	return state


## state の今いる建物の住人全員の機嫌を 1.0 (ご機嫌) にする (integration・screenshot からも使う)
static func make_everyone_happy(state: Node) -> void:
	var moods: Dictionary = state.save_data.building_progress.resident_moods
	for resident_key: Variant in moods.keys():
		moods[resident_key] = 1.0

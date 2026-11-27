extends RefCounted
## 住人の依頼 (探し物・黒いスーツの服の毛・逃げた猫) の検証スイート (scripts/dev/selfcheck.gd から呼ぶ)。
## 道具ごとに探し物がきれい・傷むのどちらになるか、お礼の額、服の毛を取り切った時の上乗せ、探し物の数が調整値と
## 一致すること、保存と読み込み、逃げた猫を抱えて届けると住人がご機嫌になることを確かめる。

## 依頼の計算
const RequestRulesScript := preload("res://scripts/requests/request_rules.gd")
## 依頼の状態 (出来事の種類)
const RequestStateScript := preload("res://scripts/state/request_state.gd")
## 依頼の見た目のノード (知らせの文言)
const RequestControllerScript := preload("res://scripts/requests/request_controller.gd")
## 依頼の一覧の画面
const RequestListPanelScript := preload("res://scripts/ui/request_list_panel.gd")
## 探し物の状態の型
const FoundItemProgressScript := preload("res://scripts/data/found_item_progress.gd")
## 建物 1 つの進行データ型 (保存と読み込み)
const BuildingProgressScript := preload("res://scripts/data/building_progress.gd")
## 道具の定義
const ToolCatalogScript := preload("res://scripts/tools/tool_catalog.gd")
## 屋敷レイアウト型スクリプト
const MansionLayoutScript := preload("res://scripts/mansion/mansion_layout.gd")
## 猫の通り道の計算 (猫の表)
const CatRulesScript := preload("res://scripts/automation/cat_rules.gd")
## 掃除ロボットの決まり (回る面の種類)
const RobotRulesScript := preload("res://scripts/automation/robot_rules.gd")
## 屋敷ビルダー (住人の id)
const MansionBuilderScript := preload("res://scripts/mansion/mansion_builder.gd")
## 面ごとの毛データ型スクリプト
const SurfaceHairScript := preload("res://scripts/data/surface_hair.gd")
## お金の計算 (掃除代を払う間隔)
const EconomyRulesScript := preload("res://scripts/economy/economy_rules.gd")
## 状態管理 autoload スクリプト
const GameStateScript := preload("res://scripts/state/game_state.gd")
## JSON 保存ストレージスクリプト (一時セーブファイルの後片付けに使う)
const SaveStorageScript := preload("res://scripts/state/save_storage.gd")
## selfcheck が使う一時セーブファイルパス (GameState の初期化だけに使い、保存はしない)
const TEST_SAVE_PATH: String = "user://selfcheck_requests_save_data.json"

## 検証結果を記録する selfcheck の SceneTree 参照
var _checker: SceneTree = null


## 住人の依頼の検証をすべて実行する
static func run_all(checker: SceneTree) -> void:
	var suite: RefCounted = load("res://scripts/dev/selfcheck_requests.gd").new()
	suite._checker = checker
	suite._check_item_kinds()
	suite._check_condition_after_tool()
	suite._check_rewards()
	suite._check_reveal_and_suit_rules()
	suite._check_item_count_matches_tuning()
	suite._check_found_item_flow_in_game_state()
	suite._check_suit_bonus_in_game_state()
	suite._check_save_round_trip()
	suite._check_runaway_cat()
	suite._check_reveal_by_tool_and_robot()
	suite._check_reach_boundaries()
	suite._check_runaway_path_on_fixed_layout()
	suite._check_runaway_timing_and_reset()
	suite._check_texts()


## 検証結果を selfcheck 本体へ記録する
func _check(cond: bool, label: String) -> void:
	_checker._check(cond, label)


## 探し物の種類に、衣類 (毛が付きやすい物) と機械 (毛が入ると壊れやすい物) の両方があり、合う道具が探し物を傷めない道具か
func _check_item_kinds() -> void:
	var categories: Dictionary = {}
	var match_tools_gentle: bool = true
	for kind: Dictionary in RequestRulesScript.ITEM_KINDS:
		categories[kind["category"]] = true
		if bool(ToolCatalogScript.find_tool(kind["match_tool"]).get("damages_found_items", true)):
			match_tools_gentle = false
	_check(
		categories.has(RequestRulesScript.CATEGORY_CLOTH)
		and categories.has(RequestRulesScript.CATEGORY_MACHINE) and match_tools_gentle,
		"探し物に衣類と機械の両方があり、合う道具はどれも探し物を傷めない道具",
	)
	_check(
		RequestRulesScript.kind_for_item_id(&"found_item_0")["id"] == &"pocket_watch"
		and RequestRulesScript.kind_for_item_id(&"found_item_1")["id"] == &"silk_scarf"
		and RequestRulesScript.kind_for_item_id(&"found_item_4")["id"] == &"pocket_watch",
		"探し物の id の番号の順に種類を繰り返して割り当てる (0 = 懐中時計、1 = 絹のスカーフ、4 = 懐中時計)",
	)


## 道具ごとに、探し物がきれい・傷む・変わらないのどれになるか (PROJECT.md「住人・依頼・探し物」と「道具」の文から書いた期待値)
func _check_condition_after_tool() -> void:
	var watch: Dictionary = RequestRulesScript.kind_for_item_id(&"found_item_0")
	var scarf: Dictionary = RequestRulesScript.kind_for_item_id(&"found_item_1")
	# [種類, 道具, 前の状態, 期待する後の状態, 文言]
	var cases: Array[Array] = [
		[
			watch, ToolCatalogScript.TOOL_TWEEZERS,
			FoundItemProgress.Condition.FOUND, FoundItemProgress.Condition.CLEAN,
			"懐中時計をピンセットで取るときれい",
		],
		[
			scarf, ToolCatalogScript.TOOL_LINT_ROLLER,
			FoundItemProgress.Condition.FOUND, FoundItemProgress.Condition.CLEAN,
			"スカーフを粘着ローラーで取るときれい",
		],
		[
			watch, ToolCatalogScript.TOOL_LINT_ROLLER,
			FoundItemProgress.Condition.FOUND, FoundItemProgress.Condition.FOUND,
			"懐中時計に粘着ローラーでは取れない",
		],
		[
			scarf, ToolCatalogScript.TOOL_TWEEZERS,
			FoundItemProgress.Condition.FOUND, FoundItemProgress.Condition.FOUND,
			"スカーフにピンセットでは取れない",
		],
		[
			watch, ToolCatalogScript.TOOL_VACUUM,
			FoundItemProgress.Condition.FOUND, FoundItemProgress.Condition.DAMAGED,
			"掃除機で吸うと懐中時計が傷む",
		],
		[
			scarf, ToolCatalogScript.TOOL_SUCTION_TRUCK,
			FoundItemProgress.Condition.FOUND, FoundItemProgress.Condition.DAMAGED,
			"吸引車で吸うとスカーフが傷む",
		],
		[
			scarf, ToolCatalogScript.TOOL_PACKING_TAPE,
			FoundItemProgress.Condition.FOUND, FoundItemProgress.Condition.DAMAGED,
			"ガムテープで剥がすとスカーフが傷む",
		],
		[
			watch, ToolCatalogScript.TOOL_VACUUM,
			FoundItemProgress.Condition.HIDDEN, FoundItemProgress.Condition.DAMAGED,
			"埋もれた探し物も掃除機で吸うと傷む",
		],
		[
			watch, ToolCatalogScript.TOOL_TWEEZERS,
			FoundItemProgress.Condition.HIDDEN, FoundItemProgress.Condition.HIDDEN,
			"埋もれた探し物には合う道具が届かない",
		],
		[
			scarf, ToolCatalogScript.TOOL_ANDROID,
			FoundItemProgress.Condition.HIDDEN, FoundItemProgress.Condition.CLEAN,
			"アンドロイドは埋もれた探し物も見分けてきれいに取る",
		],
		[
			watch, ToolCatalogScript.TOOL_HAND,
			FoundItemProgress.Condition.FOUND, FoundItemProgress.Condition.FOUND,
			"手では探し物を取らない",
		],
		[
			watch, ToolCatalogScript.TOOL_ADHESIVE_SHEET,
			FoundItemProgress.Condition.FOUND, FoundItemProgress.Condition.FOUND,
			"粘着シートは探し物を取らない",
		],
		[
			watch, ToolCatalogScript.TOOL_VACUUM,
			FoundItemProgress.Condition.CLEAN, FoundItemProgress.Condition.CLEAN,
			"きれいに取った後に掃除機をかけても変わらない",
		],
		[
			watch, ToolCatalogScript.TOOL_TWEEZERS,
			FoundItemProgress.Condition.DAMAGED, FoundItemProgress.Condition.DAMAGED,
			"傷めた後に合う道具をかけても戻らない",
		],
	]
	for case: Array in cases:
		var actual: FoundItemProgress.Condition = RequestRulesScript.condition_after_tool(
			case[0], case[1], case[2]
		)
		_check(actual == case[3], "%s (実際: %d)" % [case[4], actual])
	var damaging: Array[StringName] = []
	for tool_def: Dictionary in ToolCatalogScript.TOOLS:
		if bool(tool_def["damages_found_items"]):
			damaging.append(tool_def["id"])
	damaging.sort()
	var expected: Array[StringName] = [
		ToolCatalogScript.TOOL_PACKING_TAPE,
		ToolCatalogScript.TOOL_SUCTION_TRUCK,
		ToolCatalogScript.TOOL_VACUUM,
	]
	expected.sort()
	_check(
		damaging == expected,
		"探し物を傷める道具はガムテープ・掃除機・吸引車の 3 つ (実際: %s)" % str(damaging),
	)


## きれいに返した時のお礼が傷めて返した時より大きく、取っていない探し物にはお礼が無いか
func _check_rewards() -> void:
	var clean: int = RequestRulesScript.reward(FoundItemProgress.Condition.CLEAN)
	var damaged: int = RequestRulesScript.reward(FoundItemProgress.Condition.DAMAGED)
	_check(
		clean > damaged and damaged > 0
		and RequestRulesScript.reward(FoundItemProgress.Condition.HIDDEN) == 0
		and RequestRulesScript.reward(FoundItemProgress.Condition.FOUND) == 0,
		"お礼はきれい (%d 円) > 傷んだ (%d 円) > 0 で、見つけただけ・埋もれた物は 0" % [clean, damaged],
	)


## 探し物が出てくる毛の残りの境目と、黒いスーツの服の毛の上乗せを受け取れる条件の境目
func _check_reveal_and_suit_rules() -> void:
	_check(
		RequestRulesScript.is_revealed(50, 100) and not RequestRulesScript.is_revealed(51, 100)
		and RequestRulesScript.is_revealed(0, 0) and RequestRulesScript.is_revealed(0, 1),
		"面の毛が最初の半分 (50 / 100 本) 以下で探し物が出て、51 本では出ない",
	)
	var deadline: float = RequestRulesScript.SUIT_DEADLINE_SECONDS
	_check(
		RequestRulesScript.suit_cleared_now(0, deadline - 0.1)
		and not RequestRulesScript.suit_cleared_now(1, deadline - 0.1)
		and not RequestRulesScript.suit_cleared_now(0, deadline),
		"スーツの毛は出かける前 (%.0f 秒より前) に 0 本にした時だけ上乗せがある" % deadline,
	)
	_check(
		RequestRulesScript.suit_status(false, deadline - 0.1) == &"open"
		and RequestRulesScript.suit_status(false, deadline) == &"missed"
		and RequestRulesScript.suit_status(true, deadline + 100.0) == &"done",
		"スーツの依頼は出かけるまで受付中、出かけたら逃した、取り切ったら済み",
	)


## 依頼の一覧の探し物の数が調整値の「埋める探し物の数」と一致するか
func _check_item_count_matches_tuning() -> void:
	for count: int in [0, 7]:
		var state: Node = GameStateScript.new()
		state.initialize_from_storage(
			TEST_SAVE_PATH, PackedStringArray(["--hair-count=600", "--found-item-count=%d" % count])
		)
		var panel: RequestListPanel = RequestListPanelScript.new()
		panel.refresh(state)
		var item_rows: int = 0
		for row: String in panel.get_row_texts():
			if not row.begins_with("・黒いスーツ") and not row.begins_with("・逃げた猫"):
				item_rows += 1
		_check(
			state.requests.remaining_item_count() == count and item_rows == count
			and panel.get_summary_text() == "探し物: 残り %d / %d 件" % [count, count],
			"調整値の探し物の数 %d と、依頼の一覧の残りの数・行の数が一致する (実際: %s / %d 行)"
			% [count, panel.get_summary_text(), item_rows],
		)
		panel.free()
		state.free()
	SaveStorageScript.delete_save_file(TEST_SAVE_PATH)


## GameState で、面の毛を減らすと探し物が出てきて (一度出たら戻らない)、合う道具で取って持ち主の部屋で返すとお礼が入るか
func _check_found_item_flow_in_game_state() -> void:
	var state: Node = GameStateScript.new()
	state.initialize_from_storage(TEST_SAVE_PATH, PackedStringArray(["--hair-count=6000"]))
	var events: Array[Dictionary] = []
	state.request_event.connect(func(event: Dictionary) -> void: events.append(event))
	var spot: MansionLayout.FoundItemSpotDef = state.current_layout.found_item_spots[0]
	var item: FoundItemProgress = state.requests.find_item(spot.found_item_id)
	var surface: SurfaceHair = state.save_data.building_progress.find_surface_hair(spot.surface_id)
	var initial: int = state.automation.get_initial_surface_hairs(spot.surface_id)
	_check(
		initial > 0 and item.condition == FoundItemProgress.Condition.HIDDEN,
		"毛のある面に埋めた探し物は最初は埋もれている",
	)
	var half: int = floori(initial * RequestRulesScript.REVEAL_REMAINING_RATIO)
	_set_surface_count(surface, half + 1)
	state.requests.after_hairs_removed()
	_check(item.condition == FoundItemProgress.Condition.HIDDEN, "面の毛が半分より多く残っている間は出てこない")
	_set_surface_count(surface, half)
	state.requests.after_hairs_removed()
	_check(
		item.condition == FoundItemProgress.Condition.FOUND and not events.is_empty()
		and events[-1]["kind"] == RequestStateScript.EVENT_REVEALED,
		"面の毛が半分になると探し物が出てきて、出来事を知らせる",
	)
	_set_surface_count(surface, initial)
	state.requests.after_hairs_removed()
	_check(item.condition == FoundItemProgress.Condition.FOUND, "猫がまた毛を落として面の毛が増えても、出てきた探し物は埋もれ直さない")
	var other_room: StringName = &""
	for room: MansionLayout.RoomDef in state.current_layout.rooms:
		if room.room_id != spot.room_id:
			other_room = room.room_id
	_check(
		state.requests.return_item(spot.found_item_id, spot.room_id) == 0,
		"見つけただけで取っていない探し物は返せない",
	)
	var reach: Array[StringName] = state.requests.items_in_reach(spot.surface_id, spot.position, 0.05)
	_check(
		reach.has(spot.found_item_id)
		and not state.requests.items_in_reach(
			spot.surface_id, spot.position + Vector3(1.0, 0.0, 0.0), 0.05
		).has(spot.found_item_id),
		"道具の範囲 (半径 + %.2f m) に入った探し物だけが道具に当たる" % RequestRulesScript.ITEM_REACH_MARGIN_M,
	)
	state.requests.apply_tool(
		RequestRulesScript.kind_for_item_id(spot.found_item_id)["match_tool"], reach
	)
	var money_before: int = state.get_money()
	_check(
		item.condition == FoundItemProgress.Condition.CLEAN
		and state.requests.return_item(spot.found_item_id, other_room) == 0
		and state.get_money() == money_before,
		"合う道具で取るときれいになり、持ち主でない部屋では返せない",
	)
	var paid: int = state.requests.return_item(spot.found_item_id, spot.room_id)
	_check(
		paid == RequestRulesScript.REWARD_CLEAN and state.get_money() == money_before
		and state.requests.pending_reward(spot.room_id) == paid
		and item.is_returned and state.requests.return_item(spot.found_item_id, spot.room_id) == 0
		and state.requests.remaining_item_count() == state.current_layout.found_item_spots.size() - 1,
		"きれいな探し物を持ち主の部屋で返すと、お礼 %d 円が次の掃除代に上乗せされ、残りが 1 件減り、2 度は返せない"
		% paid,
	)
	var added: int = reward_in_next_payment(state)
	_check(
		added == paid and state.requests.pending_reward(spot.room_id) == 0,
		"次の掃除代でお礼 %d 円が所持金に入り、上乗せが消える (実際: %d 円)" % [paid, added],
	)
	var second: MansionLayout.FoundItemSpotDef = state.current_layout.found_item_spots[1]
	var second_ids: Array[StringName] = [second.found_item_id]
	state.requests.apply_tool(ToolCatalogScript.TOOL_VACUUM, second_ids)
	var damaged_paid: int = state.requests.return_item(second.found_item_id, second.room_id)
	_check(
		state.requests.find_item(second.found_item_id).condition == FoundItemProgress.Condition.DAMAGED
		and damaged_paid == RequestRulesScript.REWARD_DAMAGED and damaged_paid < paid,
		"掃除機で吸った探し物は傷み、返した時のお礼が %d 円と少ない" % damaged_paid,
	)
	state.free()
	SaveStorageScript.delete_save_file(TEST_SAVE_PATH)


## GameState で、住人が出かけた後にスーツの毛を取り切っても上乗せが無く、出かける前に 0 本にすると 1 回だけ入るか
func _check_suit_bonus_in_game_state() -> void:
	var state: Node = GameStateScript.new()
	state.initialize_from_storage(TEST_SAVE_PATH, PackedStringArray(["--hair-count=6000"]))
	var suits: Array[Dictionary] = state.requests.suit_requests()
	_check(not suits.is_empty(), "既定の屋敷に黒いスーツの依頼がある (実際: %d 件)" % suits.size())
	if suits.is_empty():
		state.free()
		SaveStorageScript.delete_save_file(TEST_SAVE_PATH)
		return
	var progress: BuildingProgress = state.save_data.building_progress
	var suit: SurfaceHair = progress.find_surface_hair(suits[0]["surface_id"])
	var suit_room: StringName = suits[0]["room_id"]
	_set_surface_count(suit, 1)
	state.requests.after_hairs_removed()
	_check(state.requests.pending_reward(suit_room) == 0, "スーツに毛が 1 本残っている間は上乗せが無い")
	progress.elapsed_seconds = RequestRulesScript.SUIT_DEADLINE_SECONDS
	_set_surface_count(suit, 0)
	state.requests.after_hairs_removed()
	_check(
		state.requests.pending_reward(suit_room) == 0
		and state.requests.suit_requests()[0]["status"] == &"missed",
		"住人が出かけた後 (%.0f 秒) にスーツの毛を取り切っても上乗せは入らない"
		% RequestRulesScript.SUIT_DEADLINE_SECONDS,
	)
	progress.elapsed_seconds = RequestRulesScript.SUIT_DEADLINE_SECONDS - 1.0
	state.requests.after_hairs_removed()
	state.requests.after_hairs_removed()
	_check(
		state.requests.pending_reward(suit_room) == RequestRulesScript.SUIT_BONUS
		and reward_in_next_payment(state) == RequestRulesScript.SUIT_BONUS
		and progress.cleared_suit_surface_ids.size() == 1
		and progress.cleared_suit_surface_ids[0] == suits[0]["surface_id"]
		and state.requests.suit_requests()[0]["status"] == &"done",
		"出かける前にスーツの毛が 0 本なら、次の掃除代に +%d 円が 1 回だけ上乗せされる"
		% RequestRulesScript.SUIT_BONUS,
	)
	state.free()
	SaveStorageScript.delete_save_file(TEST_SAVE_PATH)


## 探し物の状態・取り切ったスーツ・猫を届けたかが保存と読み込みで戻り、依頼を足す前の保存データ (キーが無い) も読めるか
func _check_save_round_trip() -> void:
	var progress: BuildingProgress = BuildingProgressScript.new()
	var item: FoundItemProgress = FoundItemProgressScript.new()
	item.found_item_id = &"found_item_3"
	item.condition = FoundItemProgress.Condition.DAMAGED
	item.is_returned = true
	progress.found_items.append(item)
	progress.cleared_suit_surface_ids.append(&"surface_9")
	progress.runaway_cat_returned = true
	progress.pending_rewards[&"resident_room_1"] = 250
	var data: Dictionary = JSON.parse_string(JSON.stringify(progress.to_dict()))
	var loaded: BuildingProgress = BuildingProgressScript.from_dict(data)
	_check(
		loaded != null and loaded.found_items.size() == 1
		and loaded.found_items[0].condition == FoundItemProgress.Condition.DAMAGED
		and loaded.found_items[0].is_returned
		and loaded.cleared_suit_surface_ids.size() == 1
		and loaded.cleared_suit_surface_ids[0] == &"surface_9" and loaded.runaway_cat_returned
		and int(loaded.pending_rewards.get(&"resident_room_1", 0)) == 250,
		"探し物の状態 (傷んだ・返した)・取り切ったスーツ・猫を届けたか・次の掃除代の上乗せが保存と読み込みで戻る",
	)
	var old_save: Dictionary = data.duplicate(true)
	old_save.erase("cleared_suit_surface_ids")
	old_save.erase("runaway_cat_returned")
	old_save.erase("pending_rewards")
	var old_loaded: BuildingProgress = BuildingProgressScript.from_dict(old_save)
	_check(
		old_loaded != null and old_loaded.cleared_suit_surface_ids.is_empty()
		and not old_loaded.runaway_cat_returned and old_loaded.pending_rewards.is_empty(),
		"依頼を足す前の保存データ (キーが無い) は、依頼を始める前の値で読める",
	)
	var bad: Dictionary = data.duplicate(true)
	bad["runaway_cat_returned"] = "yes"
	var bad_suits: Dictionary = data.duplicate(true)
	bad_suits["cleared_suit_surface_ids"] = [3]
	var bad_rewards: Dictionary = data.duplicate(true)
	bad_rewards["pending_rewards"] = {"resident_room_1": "many"}
	var suits_not_array: Dictionary = data.duplicate(true)
	suits_not_array["cleared_suit_surface_ids"] = "surface_9"
	var rewards_not_dict: Dictionary = data.duplicate(true)
	rewards_not_dict["pending_rewards"] = [250]
	_check(
		BuildingProgressScript.from_dict(bad) == null
		and BuildingProgressScript.from_dict(bad_suits) == null
		and BuildingProgressScript.from_dict(bad_rewards) == null
		and BuildingProgressScript.from_dict(suits_not_array) == null
		and BuildingProgressScript.from_dict(rewards_not_dict) == null,
		"依頼の進みの型が違う保存データは読まない",
	)


## 逃げた猫: 時間で逃げ出し、毛を落とさず、毛の跡が隠れる所へ続き、抱えて持ち主の部屋に届けると住人がご機嫌になるか
func _check_runaway_cat() -> void:
	var state: Node = GameStateScript.new()
	state.initialize_from_storage(TEST_SAVE_PATH, PackedStringArray(["--hair-count=6000"]))
	var layout: MansionLayout = state.current_layout
	var events: Array[Dictionary] = []
	state.request_event.connect(func(event: Dictionary) -> void: events.append(event))
	var cat_id: StringName = RequestRulesScript.runaway_cat_id()
	var owner_room: MansionLayout.RoomDef = RequestRulesScript.runaway_owner_room(layout)
	var path: Array[MansionLayout.RoomDef] = RequestRulesScript.runaway_path(layout)
	var trail: Array[Vector3] = RequestRulesScript.trail_points(layout)
	_check(
		path.size() >= 2 and path[0] == owner_room and not trail.is_empty()
		and trail[0].is_equal_approx(owner_room.center),
		"逃げた猫は持ち主の部屋から別の部屋へ隠れ、毛の跡は持ち主の部屋から続く (%d 部屋・%d か所)"
		% [path.size(), trail.size()],
	)
	_check(
		state.requests.runaway_status() == &"home" and not state.requests.carry_runaway_cat(),
		"逃げ出す前の猫は抱えられない",
	)
	state.advance_time(RequestRulesScript.RUNAWAY_START_SECONDS)
	var escaped_events: Array = events.filter(
		func(event: Dictionary) -> bool: return event["kind"] == RequestStateScript.EVENT_CAT_ESCAPED
	)
	_check(
		state.requests.runaway_status() == &"escaped" and state.requests.is_cat_away(cat_id)
		and escaped_events.size() == 1,
		"遊んだ時間が %.0f 秒になると猫が逃げ、知らせる" % RequestRulesScript.RUNAWAY_START_SECONDS,
	)
	# 面の毛の上限で落とせない状態を除くため、全部の面を空にしてから時計を進める
	for surface: SurfaceHair in state.save_data.building_progress.surface_hairs:
		_set_surface_count(surface, 0)
	# 猫の通り道を 1 周以上回り、どの猫も毛を落とす時刻を通る長さ
	var changes: Dictionary = state.automation.advance(120.0)
	var dropped_by_runaway: int = 0
	var dropped_by_others: int = 0
	for drop: Dictionary in changes["drops"]:
		if drop["cat_id"] == cat_id:
			dropped_by_runaway += int(drop["count"])
		else:
			dropped_by_others += int(drop["count"])
	_check(
		dropped_by_runaway == 0 and dropped_by_others > 0
		and not state.requests.is_cat_away(CatRulesScript.CATS[1]["id"]),
		"隠れている猫は毛を落とさず、ほかの猫は落とし続ける (実際: 逃げた猫 %d 本・ほかの猫 %d 本)"
		% [dropped_by_runaway, dropped_by_others],
	)
	var resident: StringName = MansionBuilderScript.resident_id_for_room(owner_room.room_id)
	# 届けた時に最大 (1.0) へ上がったと分かるよう、ご機嫌の線 (0.8) より下にしておく
	state.save_data.building_progress.resident_moods[resident] = 0.2
	_check(
		state.requests.carry_runaway_cat() and state.requests.runaway_status() == &"carried"
		and not state.requests.deliver_runaway_cat(path[path.size() - 1].room_id),
		"逃げた猫を抱えられ、持ち主でない部屋では届けられない",
	)
	_check(
		state.requests.deliver_runaway_cat(owner_room.room_id)
		and state.requests.runaway_status() == &"returned"
		and is_equal_approx(
			float(state.save_data.building_progress.resident_moods[resident]),
			RequestRulesScript.RUNAWAY_RETURN_MOOD
		)
		and not state.requests.is_cat_away(cat_id)
		and state.save_data.building_progress.runaway_cat_returned,
		"抱えた猫を持ち主の部屋に届けると住人がご機嫌 (%.1f) になり、猫は通り道に戻る"
		% RequestRulesScript.RUNAWAY_RETURN_MOOD,
	)
	_check(
		RequestControllerScript.notice_text(
			{"kind": RequestStateScript.EVENT_CAT_RETURNED, "cat_id": cat_id}
		).ends_with("住人がご機嫌になった"),
		"猫を届けた知らせの文言",
	)
	state.free()
	SaveStorageScript.delete_save_file(TEST_SAVE_PATH)


## 遊んだ時間を次に掃除代を払う時まで進め、入ったお金のうち掃除代 (住人の機嫌で決まる額) を除いた分 (上乗せのお礼) を返す。
## 掃除代は機嫌を動かした後の値で払うため、進めた後の部屋の状態の掃除代の合計が払った掃除代になる
static func reward_in_next_payment(state: Node) -> int:
	var interval: float = EconomyRulesScript.PAYMENT_INTERVAL_SECONDS
	var elapsed: float = state.save_data.building_progress.elapsed_seconds
	var earned: int = state.advance_time(interval - fmod(elapsed, interval))
	var fees: int = 0
	for room: MansionLayout.RoomDef in state.current_layout.rooms:
		fees += int(state.get_room_status(room.room_id)["cleaning_fee"])
	return earned - fees


## 手で取る以外の経路 (毛を減らす道具の GameState の入口・掃除ロボット) で面の毛が半分になっても探し物が出てくるか
func _check_reveal_by_tool_and_robot() -> void:
	var state: Node = GameStateScript.new()
	state.initialize_from_storage(TEST_SAVE_PATH, PackedStringArray(["--hair-count=6000"]))
	var progress: BuildingProgress = state.save_data.building_progress
	var spot: MansionLayout.FoundItemSpotDef = state.current_layout.found_item_spots[0]
	var item: FoundItemProgress = state.requests.find_item(spot.found_item_id)
	var initial: int = state.automation.get_initial_surface_hairs(spot.surface_id)
	_set_surface_count(progress.find_surface_hair(spot.surface_id), initial)
	var half: int = floori(initial * RequestRulesScript.REVEAL_REMAINING_RATIO)
	# 掃除機 (6,000 円) を買える額
	progress.money = 1000000
	state.purchase(GameStateScript.PURCHASE_TOOL, ToolCatalogScript.TOOL_VACUUM)
	state.apply_tool_sweep(
		ToolCatalogScript.TOOL_VACUUM,
		{spot.surface_id: {SurfaceHairScript.COLOR_WHITE: initial - half}},
	)
	_check(
		item.condition == FoundItemProgress.Condition.FOUND,
		"道具で面の毛を半分にすると探し物が出てくる (実際: 状態 %d・残り %d / %d 本)"
		% [item.condition, state.get_surface_hair_count(spot.surface_id), initial],
	)
	state.free()
	SaveStorageScript.delete_save_file(TEST_SAVE_PATH)
	var robot_state: Node = GameStateScript.new()
	robot_state.initialize_from_storage(TEST_SAVE_PATH, PackedStringArray(["--hair-count=6000"]))
	var robot_progress: BuildingProgress = robot_state.save_data.building_progress
	var floor_spot: MansionLayout.FoundItemSpotDef = null
	for candidate: MansionLayout.FoundItemSpotDef in robot_state.current_layout.found_item_spots:
		for surface_def: MansionLayout.SurfaceDef in robot_state.current_layout.surfaces:
			if (
				floor_spot == null and surface_def.surface_id == candidate.surface_id
				and RobotRulesScript.CLEAN_SURFACE_TYPES.has(surface_def.surface_type)
			):
				floor_spot = candidate
	_check(floor_spot != null, "既定の屋敷に、掃除ロボットが回る面 (床・カーペット) に埋めた探し物がある")
	if floor_spot == null:
		robot_state.free()
		SaveStorageScript.delete_save_file(TEST_SAVE_PATH)
		return
	var robot_item: FoundItemProgress = robot_state.requests.find_item(floor_spot.found_item_id)
	var robot_initial: int = robot_state.automation.get_initial_surface_hairs(floor_spot.surface_id)
	# 半分の境目のすぐ上に置き、ロボットが数本取れば境目を越えるようにする
	_set_surface_count(
		robot_progress.find_surface_hair(floor_spot.surface_id),
		floori(robot_initial * RequestRulesScript.REVEAL_REMAINING_RATIO) + 1,
	)
	# 掃除ロボット (値段は RobotRules.ROBOT_PRICE) を買える額
	robot_progress.money = 1000000
	robot_state.automation.buy_robot(floor_spot.room_id)
	# ロボットが部屋を何周もして、境目の上の 1 本以上を取る長さ
	robot_state.automation.advance(600.0)
	_check(
		robot_item.condition == FoundItemProgress.Condition.FOUND,
		"掃除ロボットが取った毛で面の毛が半分になると探し物が出てくる (実際: 状態 %d・残り %d / %d 本)"
		% [
			robot_item.condition, robot_state.get_surface_hair_count(floor_spot.surface_id),
			robot_initial,
		],
	)
	robot_state.free()
	SaveStorageScript.delete_save_file(TEST_SAVE_PATH)


## 道具の範囲の境目: 半径 + 余白の 1 mm 内は当たり、1 mm 外と別の面は当たらない
func _check_reach_boundaries() -> void:
	var spot: MansionLayout.FoundItemSpotDef = MansionLayout.FoundItemSpotDef.new()
	spot.surface_id = &"surface_a"
	spot.position = Vector3.ZERO
	var radius: float = 0.05
	var edge: float = radius + RequestRulesScript.ITEM_REACH_MARGIN_M
	# Vector3 は単精度のため、境目ちょうどの値は丸めで外に出ることがある。境目の 1 mm 内と 1 mm 外で確かめる
	_check(
		RequestRulesScript.is_in_reach(spot, &"surface_a", Vector3(edge - 0.001, 0.0, 0.0), radius)
		and not RequestRulesScript.is_in_reach(
			spot, &"surface_a", Vector3(edge + 0.001, 0.0, 0.0), radius
		)
		and not RequestRulesScript.is_in_reach(spot, &"surface_b", Vector3.ZERO, radius),
		"道具の範囲は半径 + %.2f m の 1 mm 内まで当たり、1 mm 外と別の面には当たらない"
		% RequestRulesScript.ITEM_REACH_MARGIN_M,
	)


## 間取りを固定した屋敷で、逃げた猫がドアをたどって最も遠い部屋に隠れ、毛の跡が 0.8 m おきに続くか。
## 間取り: 持ち主の部屋 A (0,0) - ドア - B (1,0) - ドア - C (2,0)。A の南の D (0,1) は隣り合うがドアが無い
func _check_runaway_path_on_fixed_layout() -> void:
	var layout: MansionLayout = _fixed_layout([
		[&"room_a", 0, 0, false, true, false, false], [&"room_b", 1, 0, true, true, false, false],
		[&"room_c", 2, 0, true, false, false, false], [&"room_d", 0, 1, false, false, false, false],
	])
	var path: Array[MansionLayout.RoomDef] = RequestRulesScript.runaway_path(layout)
	var ids: Array[StringName] = []
	for room: MansionLayout.RoomDef in path:
		ids.append(room.room_id)
	_check(
		ids == [&"room_a", &"room_b", &"room_c"],
		"逃げた猫はドアのある部屋だけをたどって最も遠い部屋 C に隠れ、ドアの無い D には入らない (実際: %s)"
		% str(ids),
	)
	var vertical: MansionLayout = _fixed_layout([
		[&"room_n", 0, 0, false, false, false, true], [&"room_s", 0, 1, false, false, true, false],
		[&"room_far", 0, 2, false, false, false, false],
	])
	var vertical_ids: Array[StringName] = []
	for room: MansionLayout.RoomDef in RequestRulesScript.runaway_path(vertical):
		vertical_ids.append(room.room_id)
	var single: MansionLayout = _fixed_layout([[&"room_only", 0, 0, false, false, false, false]])
	var empty: MansionLayout = MansionLayout.new()
	_check(
		vertical_ids == [&"room_n", &"room_s"]
		and RequestRulesScript.runaway_path(single).size() == 1
		and RequestRulesScript.runaway_path(empty).is_empty()
		and RequestRulesScript.runaway_hiding_point(empty) == Vector3.ZERO
		and RequestRulesScript.trail_points(empty).is_empty(),
		"南北のドアもたどってドアの無い部屋で止まり、部屋が 1 つなら持ち主の部屋に隠れ、部屋が無ければ経路も跡も無い (実際: %s)"
		% str(vertical_ids),
	)
	var trail: Array[Vector3] = RequestRulesScript.trail_points(layout)
	var spaced: bool = trail.size() >= 9
	for index: int in range(1, mini(trail.size(), 5)):
		if not is_equal_approx(
			trail[index].distance_to(trail[index - 1]), RequestRulesScript.TRAIL_SPACING_M
		):
			spaced = false
	_check(
		spaced and trail[0].is_equal_approx(Vector3.ZERO),
		"毛の跡は持ち主の部屋の中心から %.1f m おきに隣の部屋へ続く (実際: %d か所)"
		% [RequestRulesScript.TRAIL_SPACING_M, trail.size()],
	)


## 猫が逃げ出す時刻の境目と、知らせが 1 回だけなこと、抱えたまま屋敷を作り直すと隠れている所に戻ること
func _check_runaway_timing_and_reset() -> void:
	var state: Node = GameStateScript.new()
	state.initialize_from_storage(TEST_SAVE_PATH, PackedStringArray(["--hair-count=6000"]))
	var escaped: Array[int] = [0]
	state.request_event.connect(
		func(event: Dictionary) -> void:
			if event["kind"] == RequestStateScript.EVENT_CAT_ESCAPED:
				escaped[0] += 1
	)
	state.advance_time(RequestRulesScript.RUNAWAY_START_SECONDS - 1.0)
	_check(
		escaped[0] == 0 and state.requests.runaway_status() == &"home",
		"逃げ出す時刻の 1 秒前には猫は逃げていない",
	)
	state.advance_time(1.0)
	state.advance_time(100.0)
	_check(
		escaped[0] == 1 and state.requests.runaway_status() == &"escaped",
		"逃げ出す時刻をまたいだ時だけ 1 回知らせ、その後に時間が進んでも知らせない (実際: %d 回)" % escaped[0],
	)
	state.requests.carry_runaway_cat()
	state.apply_tuning_and_rebuild(state.get_tuning(), false)
	_check(
		state.requests.runaway_status() == &"escaped",
		"猫を抱えたまま屋敷を作り直す・読み込むと、猫は隠れている所に戻る",
	)
	state.free()
	SaveStorageScript.delete_save_file(TEST_SAVE_PATH)


## 一覧の行と知らせの文言が、探し物・スーツ・猫の状態ごとに分かれるか。抱えられる距離の境目
func _check_texts() -> void:
	var layout: MansionLayout = _fixed_layout([[&"room_a", 0, 0, false, false, false, false]])
	layout.rooms[0].display_name = "玄関"
	var spot: MansionLayout.FoundItemSpotDef = MansionLayout.FoundItemSpotDef.new()
	spot.found_item_id = &"found_item_0"
	spot.room_id = &"room_a"
	var item: FoundItemProgress = FoundItemProgressScript.new()
	var item_texts: Array[String] = []
	for condition: FoundItemProgress.Condition in [
		FoundItemProgress.Condition.HIDDEN, FoundItemProgress.Condition.FOUND,
		FoundItemProgress.Condition.CLEAN, FoundItemProgress.Condition.DAMAGED,
	]:
		item.condition = condition
		item_texts.append(RequestListPanelScript._item_text(spot, item, layout))
	item.is_returned = true
	item_texts.append(RequestListPanelScript._item_text(spot, item, layout))
	_check(
		item_texts[0].contains("埋もれている") and item_texts[1].contains("ピンセットで丁寧に取る")
		and item_texts[2].contains("きれいに取った") and item_texts[3].contains("傷めて取った")
		and item_texts[4].contains("返した (お礼 %d 円)" % RequestRulesScript.REWARD_DAMAGED)
		and item_texts[0].begins_with("・懐中時計 (玄関の住人)"),
		"一覧の探し物の行は、埋もれた・見つけた・きれい・傷んだ・返したで文言が分かれる (実際: %s)"
		% str(item_texts),
	)
	var suit: Dictionary = {"room_id": &"room_a", "remaining": 12, "seconds_left": 125.0}
	var suit_texts: Array[String] = []
	for status: StringName in [&"open", &"done", &"missed"]:
		suit_texts.append(RequestListPanelScript._suit_text(suit.merged({"status": status}), layout))
	_check(
		suit_texts[0].contains("残り 12 本 / 出かけるまで 2:05")
		and suit_texts[1].contains("取り切った") and suit_texts[2].contains("出かけた"),
		"一覧のスーツの行は、受付中 (残りの本数と分:秒)・取り切った・出かけたで文言が分かれる (実際: %s)"
		% str(suit_texts),
	)
	var cat_texts: Array[String] = []
	for status: StringName in [&"home", &"escaped", &"carried", &"returned"]:
		cat_texts.append(RequestListPanelScript._cat_text(status, layout.rooms[0]))
	_check(
		cat_texts[0].contains("まだ逃げていない") and cat_texts[1].contains("毛の跡をたどって")
		and cat_texts[2].contains("玄関に届ける") and cat_texts[3].ends_with("届けた"),
		"一覧の猫の行は、逃げる前・隠れている・抱えている・届けたで文言が分かれる (実際: %s)"
		% str(cat_texts),
	)
	var notices: Array[String] = [
		RequestControllerScript.notice_text({
			"kind": RequestStateScript.EVENT_TAKEN, "found_item_id": &"found_item_0",
			"condition": FoundItemProgress.Condition.DAMAGED,
		}),
		RequestControllerScript.notice_text(
			{"kind": RequestStateScript.EVENT_SUIT_CLEARED, "reward": 150}
		),
		RequestControllerScript.notice_text({"kind": RequestStateScript.EVENT_CAT_ESCAPED}),
		RequestControllerScript.notice_text({"kind": RequestStateScript.EVENT_CAT_CARRIED}),
		RequestControllerScript.notice_text({"kind": &"unknown"}),
	]
	_check(
		notices[0] == "懐中時計を傷めて取った"
		and notices[1] == "黒いスーツの毛を取り切った: 次の掃除代に +150 円"
		and notices[2].ends_with("毛の跡をたどって探す") and notices[3].ends_with("持ち主の部屋に届ける")
		and notices[4].is_empty(),
		"知らせの文言は、傷めて取った・スーツ・猫が逃げた・抱えたで分かれ、知らない出来事は出さない (実際: %s)"
		% str(notices),
	)
	var carry_range: float = RequestControllerScript.CARRY_RANGE_M
	_check(
		RequestControllerScript.can_carry(Vector3(carry_range - 0.01, 5.0, 0.0), Vector3.ZERO)
		and not RequestControllerScript.can_carry(
			Vector3(carry_range + 0.01, 0.0, 0.0), Vector3.ZERO
		),
		"隠れている猫は水平に %.1f m の 1 cm 内なら抱えられ (高さは見ない)、1 cm 外では抱えない"
		% carry_range,
	)


## rows の [id, grid_x, grid_z, 西のドア, 東のドア, 北のドア, 南のドア] で、4 m 四方の部屋を並べた屋敷を作る
static func _fixed_layout(rows: Array) -> MansionLayout:
	var layout: MansionLayout = MansionLayout.new()
	for spec: Array in rows:
		var room: MansionLayout.RoomDef = MansionLayout.RoomDef.new()
		room.room_id = spec[0]
		room.grid_x = spec[1]
		room.grid_z = spec[2]
		room.open_west = spec[3]
		room.open_east = spec[4]
		room.open_north = spec[5]
		room.open_south = spec[6]
		room.center = Vector3(float(spec[1]) * 4.0, 0.0, float(spec[2]) * 4.0)
		room.size = Vector3(4.0, 3.0, 4.0)
		layout.rooms.append(room)
	return layout


## 面 surface の毛を白い毛 count 本だけにする
static func _set_surface_count(surface: SurfaceHair, count: int) -> void:
	surface.hair_counts = {SurfaceHairScript.COLOR_WHITE: count}

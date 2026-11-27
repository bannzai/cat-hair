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
## 探し物の状態の短い名前 (検証の文言用)
const HIDDEN := FoundItemProgressScript.Condition.HIDDEN
## 探し物の状態: 見つけた
const FOUND := FoundItemProgressScript.Condition.FOUND
## 探し物の状態: きれいに取った
const CLEAN := FoundItemProgressScript.Condition.CLEAN
## 探し物の状態: 傷めて取った
const DAMAGED := FoundItemProgressScript.Condition.DAMAGED

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
		[watch, ToolCatalogScript.TOOL_TWEEZERS, FOUND, CLEAN, "懐中時計をピンセットで取るときれい"],
		[scarf, ToolCatalogScript.TOOL_LINT_ROLLER, FOUND, CLEAN, "スカーフを粘着ローラーで取るときれい"],
		[watch, ToolCatalogScript.TOOL_LINT_ROLLER, FOUND, FOUND, "懐中時計に粘着ローラーでは取れない"],
		[scarf, ToolCatalogScript.TOOL_TWEEZERS, FOUND, FOUND, "スカーフにピンセットでは取れない"],
		[watch, ToolCatalogScript.TOOL_VACUUM, FOUND, DAMAGED, "掃除機で吸うと懐中時計が傷む"],
		[scarf, ToolCatalogScript.TOOL_SUCTION_TRUCK, FOUND, DAMAGED, "吸引車で吸うとスカーフが傷む"],
		[scarf, ToolCatalogScript.TOOL_PACKING_TAPE, FOUND, DAMAGED, "ガムテープで剥がすとスカーフが傷む"],
		[watch, ToolCatalogScript.TOOL_VACUUM, HIDDEN, DAMAGED, "埋もれた探し物も掃除機で吸うと傷む"],
		[watch, ToolCatalogScript.TOOL_TWEEZERS, HIDDEN, HIDDEN, "埋もれた探し物には合う道具が届かない"],
		[scarf, ToolCatalogScript.TOOL_ANDROID, HIDDEN, CLEAN, "アンドロイドは埋もれた探し物も見分けてきれいに取る"],
		[watch, ToolCatalogScript.TOOL_HAND, FOUND, FOUND, "手では探し物を取らない"],
		[watch, ToolCatalogScript.TOOL_ADHESIVE_SHEET, FOUND, FOUND, "粘着シートは探し物を取らない"],
		[watch, ToolCatalogScript.TOOL_VACUUM, CLEAN, CLEAN, "きれいに取った後に掃除機をかけても変わらない"],
		[watch, ToolCatalogScript.TOOL_TWEEZERS, DAMAGED, DAMAGED, "傷めた後に合う道具をかけても戻らない"],
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
	var clean: int = RequestRulesScript.reward(CLEAN)
	var damaged: int = RequestRulesScript.reward(DAMAGED)
	_check(
		clean > damaged and damaged > 0
		and RequestRulesScript.reward(HIDDEN) == 0 and RequestRulesScript.reward(FOUND) == 0,
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
	_check(initial > 0 and item.condition == HIDDEN, "毛のある面に埋めた探し物は最初は埋もれている")
	var half: int = floori(initial * RequestRulesScript.REVEAL_REMAINING_RATIO)
	_set_surface_count(surface, half + 1)
	state.requests.after_hairs_removed()
	_check(item.condition == HIDDEN, "面の毛が半分より多く残っている間は出てこない")
	_set_surface_count(surface, half)
	state.requests.after_hairs_removed()
	_check(
		item.condition == FOUND and not events.is_empty()
		and events[-1]["kind"] == RequestStateScript.EVENT_REVEALED,
		"面の毛が半分になると探し物が出てきて、出来事を知らせる",
	)
	_set_surface_count(surface, initial)
	state.requests.after_hairs_removed()
	_check(item.condition == FOUND, "猫がまた毛を落として面の毛が増えても、出てきた探し物は埋もれ直さない")
	var other_room: StringName = &""
	for room: MansionLayout.RoomDef in state.current_layout.rooms:
		if room.room_id != spot.room_id:
			other_room = room.room_id
	_check(
		state.requests.return_item(spot.found_item_id, spot.room_id) == 0,
		"見つけただけで取っていない探し物は返せない",
	)
	var match_tool: StringName = RequestRulesScript.kind_for_item_id(spot.found_item_id)["match_tool"]
	var reach: Array[StringName] = state.requests.items_in_reach(spot.surface_id, spot.position, 0.05)
	var far: Array[StringName] = state.requests.items_in_reach(
		spot.surface_id, spot.position + Vector3(1.0, 0.0, 0.0), 0.05
	)
	_check(
		reach.has(spot.found_item_id) and not far.has(spot.found_item_id),
		"道具の範囲 (半径 + %.2f m) に入った探し物だけが道具に当たる" % RequestRulesScript.ITEM_REACH_MARGIN_M,
	)
	state.requests.apply_tool(match_tool, reach)
	var money_before: int = state.get_money()
	_check(
		item.condition == CLEAN
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
		state.requests.find_item(second.found_item_id).condition == DAMAGED
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
	item.condition = DAMAGED
	item.is_returned = true
	progress.found_items.append(item)
	progress.cleared_suit_surface_ids.append(&"surface_9")
	progress.runaway_cat_returned = true
	progress.pending_rewards[&"resident_room_1"] = 250
	var data: Dictionary = JSON.parse_string(JSON.stringify(progress.to_dict()))
	var loaded: BuildingProgress = BuildingProgressScript.from_dict(data)
	_check(
		loaded != null and loaded.found_items.size() == 1
		and loaded.found_items[0].condition == DAMAGED and loaded.found_items[0].is_returned
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
	_check(
		BuildingProgressScript.from_dict(bad) == null
		and BuildingProgressScript.from_dict(bad_suits) == null
		and BuildingProgressScript.from_dict(bad_rewards) == null,
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
	var changes: Dictionary = state.automation.advance(120.0)
	var dropped_by_runaway: int = 0
	for drop: Dictionary in changes["drops"]:
		if drop["cat_id"] == cat_id:
			dropped_by_runaway += int(drop["count"])
	_check(dropped_by_runaway == 0, "隠れている猫は毛を落とさない (実際: %d 本)" % dropped_by_runaway)
	var resident: StringName = MansionBuilderScript.resident_id_for_room(owner_room.room_id)
	state.save_data.building_progress.resident_moods[resident] = 0.2
	var wrong_room: StringName = path[path.size() - 1].room_id
	_check(
		state.requests.carry_runaway_cat() and state.requests.runaway_status() == &"carried"
		and not state.requests.deliver_runaway_cat(wrong_room),
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


## 面 surface の毛を白い毛 count 本だけにする
static func _set_surface_count(surface: SurfaceHair, count: int) -> void:
	surface.hair_counts = {SurfaceHairScript.COLOR_WHITE: count}

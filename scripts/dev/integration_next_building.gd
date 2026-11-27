extends RefCounted
## 次の建物へ進む入力統合テスト (scripts/dev/integration.gd から呼ぶ)。道具を買う画面の「次の建物へ進む」ボタンが、
## 住人全員がご機嫌の時だけ押せ、押すと次の建物 (部屋が増えた屋敷) に組み直されて手の強化を持ち越すことと、
## 自動テストプレイの bot が次の建物へ進んで節目を付けることを確かめる。

## 次の建物へ進む決まりの計算
const BuildingRulesScript := preload("res://scripts/building/building_rules.gd")
## 自動テストプレイの bot (次の建物へ進む 1 手と節目)
const PlaytestBotScript := preload("res://scripts/dev/playtest_bot.gd")
## 状態管理 autoload スクリプト (買う物の種類の定数を使う)
const GameStateScript := preload("res://scripts/state/game_state.gd")
## 手の強化の id
const HandRulesScript := preload("res://scripts/hand/hand_rules.gd")
## 道具の定義 (置いていく道具の id)
const ToolCatalogScript := preload("res://scripts/tools/tool_catalog.gd")
## 道具と手の強化を買えるよう持たせる所持金
const PLENTY_OF_MONEY: int = 1000000
## bot の取りこぼしと珍しい毛の抽選のシード (結果を毎回同じにする)
const BOT_SEED: int = 16
## 進む前に屋敷で遊んだことにする秒 (成績の知らせで 60 分と出る)
const PLAYED_SECONDS: float = 3600.0

## 検証結果を記録する integration の SceneTree 参照
var _checker: SceneTree = null


## 次の建物へ進む検証をすべて実行する (main はプレイ中のメインシーン)。終わったら成績と手の強化を消し、
## 元の調整値で最初の屋敷を組み直す
static func run_all(checker: SceneTree, main: Node3D, game_state: Node) -> void:
	var suite: RefCounted = load("res://scripts/dev/integration_next_building.gd").new()
	suite._checker = checker
	var original_tuning: MansionTuning = game_state.get_tuning()
	var original_levels: Dictionary = game_state.save_data.hand_upgrade_levels.duplicate()
	var original_auto_advance: bool = main.auto_advance_time
	main.auto_advance_time = false
	await suite._verify_bot_advances(main, game_state)
	await suite._reset(game_state, original_tuning, original_levels)
	await suite._verify_advance_from_shop(main, game_state, original_tuning)
	await suite._verify_last_building_button(main, game_state)
	await suite._reset(game_state, original_tuning, original_levels)
	main.auto_advance_time = original_auto_advance


## 成績と手の強化を元に戻し、元の調整値 original_tuning で最初の屋敷を組み直す (保存はしない)
func _reset(game_state: Node, original_tuning: MansionTuning, original_levels: Dictionary) -> void:
	game_state.save_data.building_records.clear()
	game_state.save_data.hand_upgrade_levels = original_levels.duplicate()
	game_state.apply_tuning_and_rebuild(original_tuning, false)
	await _checker.process_frame


## 自動テストプレイの bot は、住人全員がご機嫌なら方針を使わずに次の建物へ進み、進む直前の秒で節目を付けて成績を集計に入れる
func _verify_bot_advances(main: Node3D, game_state: Node) -> void:
	var bot: RefCounted = PlaytestBotScript.new()
	bot.setup(main, BOT_SEED)
	var progress: BuildingProgress = game_state.save_data.building_progress
	progress.elapsed_seconds = PLAYED_SECONDS
	for resident_key: Variant in progress.resident_moods.keys():
		progress.resident_moods[resident_key] = 1.0
	var action: Dictionary = bot.step()
	var report: Dictionary = bot.report()
	_check(
		action["kind"] == PlaytestBotScript.ACTION_ADVANCE
		and game_state.save_data.building_progress.building_id == BuildingRulesScript.BUILDING_HOTEL
		and is_equal_approx(
			float(report["milestone_seconds"].get(PlaytestBotScript.MILESTONE_NEXT_BUILDING, -1.0)),
			PLAYED_SECONDS
		)
		and (report["building_records"] as Array).size() == 1
		and is_equal_approx(bot.elapsed_seconds(), PLAYED_SECONDS)
		and game_state.save_data.building_progress.elapsed_seconds == 0.0,
		"bot は住人全員がご機嫌なら次の建物へ進み、進む直前の秒 (%d 秒) で節目を付け、成績を集計に入れ、通しの秒は続ける (実際: %s)"
		% [int(PLAYED_SECONDS), str(report["milestone_seconds"])],
	)
	await _checker.process_frame


## 最後の建物 (街全体) では、道具を買う画面の「次の建物へ進む」は押せず、最後の建物にいると出す
func _verify_last_building_button(main: Node3D, game_state: Node) -> void:
	while game_state.save_data.building_records.size() < BuildingRulesScript.BUILDING_ORDER.size() - 1:
		game_state.save_data.building_records.append(BuildingRecord.new())
	main.open_tool_shop()
	await _checker.process_frame
	var button: Button = main.tool_shop_panel.get_advance_button()
	_check(
		button.disabled and button.text.contains("最後の建物 (街全体) にいる"),
		"最後の建物 (街全体) では次の建物へ進むボタンを押せず、最後の建物にいると出す (実際: %s)" % button.text,
	)
	main.close_tool_shop()


## 検証結果を integration 本体へ記録する
func _check(cond: bool, label: String) -> void:
	_checker._check(cond, label)


## 道具を買う画面のボタンで進む: ご機嫌でない時は押せず、全員がご機嫌なら押せて、押すと次の建物で始まる
func _verify_advance_from_shop(
	main: Node3D, game_state: Node, base_tuning: MansionTuning
) -> void:
	var progress: BuildingProgress = game_state.save_data.building_progress
	progress.money = PLENTY_OF_MONEY
	_check(
		game_state.purchase(GameStateScript.PURCHASE_TOOL, ToolCatalogScript.TOOL_PACKING_TAPE)
		and game_state.purchase(GameStateScript.PURCHASE_HAND_UPGRADE, HandRulesScript.UPGRADE_DEXTERITY),
		"検証の前提: 道具と手の強化を買える",
	)
	var levels_before: Dictionary = game_state.save_data.hand_upgrade_levels.duplicate()
	for resident_key: Variant in progress.resident_moods.keys():
		progress.resident_moods[resident_key] = 0.0
	main.open_tool_shop()
	await _checker.process_frame
	var button: Button = main.tool_shop_panel.get_advance_button()
	_check(
		button != null and button.visible and button.disabled,
		"住人がご機嫌でない時は、道具を買う画面の「次の建物へ進む」を押せない",
	)
	_check(
		button != null and button.text.contains("ホテル") and button.text.contains("0 / "),
		"押せない時は、次の建物の名前とご機嫌の住人の数を出す (実際: %s)" % (button.text if button else ""),
	)
	button.pressed.emit()
	await _checker.process_frame
	_check(
		game_state.save_data.building_progress == progress
		and game_state.save_data.building_records.is_empty(),
		"ご機嫌でない時に押しても進まない",
	)
	var resident_keys: Array = progress.resident_moods.keys()
	progress.resident_moods[resident_keys[0]] = 1.0
	main.close_tool_shop()
	main.open_tool_shop()
	await _checker.process_frame
	var expected_count: String = "今 1 / %d 人" % resident_keys.size()
	_check(
		button.disabled and button.text.contains(expected_count),
		"1 人だけご機嫌の時は押せず、「%s」と出す (実際: %s)" % [expected_count, button.text],
	)
	progress.elapsed_seconds = PLAYED_SECONDS
	progress.found_items[0].is_returned = true

	for resident_key: Variant in progress.resident_moods.keys():
		progress.resident_moods[resident_key] = 1.0
	main.close_tool_shop()
	main.open_tool_shop()
	await _checker.process_frame
	_check(not button.disabled, "住人全員がご機嫌なら「次の建物へ進む」を押せる")
	button.pressed.emit()
	await _checker.process_frame
	await _checker.process_frame

	var next_tuning: MansionTuning = BuildingRulesScript.building_tuning(base_tuning, 1)
	_check(
		game_state.save_data.building_progress.building_id == BuildingRulesScript.BUILDING_HOTEL
		and game_state.save_data.building_records.size() == 1,
		"押すとホテルへ進み、屋敷の成績を記録する",
	)
	var expected_popup: String = (
		"ホテルへ進んだ\n屋敷の成績: かかった時間 %d 分 / 返した探し物 1 個" % int(PLAYED_SECONDS / 60.0)
	)
	_check(
		not main.tool_shop_panel.visible and main.get_pluck_popup_text() == expected_popup,
		"進むと道具を買う画面を閉じ、進んだことと成績を知らせる (実際: %s)" % main.get_pluck_popup_text(),
	)
	_check(
		main.mansion_world.get_room_node_count() == next_tuning.room_count
		and game_state.current_layout.rooms.size() == next_tuning.room_count
		and game_state.get_total_remaining_hairs() == next_tuning.hair_count,
		"次の建物は部屋が %d に増えた屋敷を組み直し、毛は最初の本数 (%d 本) から" % [
			next_tuning.room_count, next_tuning.hair_count
		],
	)
	_check(
		game_state.get_money() == 0
		and game_state.find_owned_tool(ToolCatalogScript.TOOL_PACKING_TAPE) == null
		and _total_levels(game_state.save_data.hand_upgrade_levels) == _total_levels(levels_before) + 1
		and _levels_kept(game_state.save_data.hand_upgrade_levels, levels_before),
		"お金と道具は置いていき、買った手の強化に返した探し物 1 つ分の 1 段を足して持ち越す",
	)
	main.close_tool_shop()
	_verify_reload(game_state, next_tuning)


## 進んだ時に保存したセーブを別の GameState で読み戻し、同じ建物・残りの毛・お金と道具なし・手の強化で続きから遊べる
func _verify_reload(game_state: Node, next_tuning: MansionTuning) -> void:
	var reloaded: Node = GameStateScript.new()
	reloaded.initialize_from_storage(game_state.save_path)
	_check(
		reloaded.loaded_from_save
		and reloaded.save_data.building_progress.building_id == BuildingRulesScript.BUILDING_HOTEL
		and reloaded.current_layout.rooms.size() == next_tuning.room_count
		and reloaded.get_total_remaining_hairs() == next_tuning.hair_count
		and reloaded.get_money() == 0
		and reloaded.find_owned_tool(ToolCatalogScript.TOOL_PACKING_TAPE) == null
		and reloaded.save_data.hand_upgrade_levels == game_state.save_data.hand_upgrade_levels
		and reloaded.save_data.building_records.size() == 1,
		"進んだ後のセーブを読み戻しても、同じ建物で毛が戻り、お金と道具が無く、手の強化が残っている",
	)
	reloaded.free()


## 手の強化の段 levels の合計
func _total_levels(levels: Dictionary) -> int:
	var total: int = 0
	for upgrade_id: StringName in HandRulesScript.UPGRADE_IDS:
		total += HandRulesScript.upgrade_level(levels, upgrade_id)
	return total


## 手の強化の段 levels が、どの強化も before の段を下回っていないか
func _levels_kept(levels: Dictionary, before: Dictionary) -> bool:
	for upgrade_id: StringName in HandRulesScript.UPGRADE_IDS:
		var level: int = HandRulesScript.upgrade_level(levels, upgrade_id)
		if level < HandRulesScript.upgrade_level(before, upgrade_id):
			return false
	return true

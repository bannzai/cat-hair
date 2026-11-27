extends RefCounted
## 次の建物へ進む入力統合テスト (scripts/dev/integration.gd から呼ぶ)。道具を買う画面の「次の建物へ進む」ボタンが、
## 住人全員がご機嫌の時だけ押せ、押すと次の建物 (部屋が増えた屋敷) に組み直されて手の強化を持ち越すことを確かめる。

## 次の建物へ進む決まりの計算
const BuildingRulesScript := preload("res://scripts/building/building_rules.gd")
## 状態管理 autoload スクリプト (買う物の種類の定数を使う)
const GameStateScript := preload("res://scripts/state/game_state.gd")
## 手の強化の id
const HandRulesScript := preload("res://scripts/hand/hand_rules.gd")
## 道具の定義 (置いていく道具の id)
const ToolCatalogScript := preload("res://scripts/tools/tool_catalog.gd")
## 道具と手の強化を買えるよう持たせる所持金
const PLENTY_OF_MONEY: int = 1000000

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
	await suite._verify_advance_from_shop(main, game_state, original_tuning)
	game_state.save_data.building_records.clear()
	game_state.save_data.hand_upgrade_levels = original_levels
	game_state.apply_tuning_and_rebuild(original_tuning, false)
	main.auto_advance_time = original_auto_advance
	await checker.process_frame


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
	var dexterity_before: int = game_state.get_hand_upgrade_level(HandRulesScript.UPGRADE_DEXTERITY)
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
	_check(
		not main.tool_shop_panel.visible and main.get_pluck_popup_text().contains("ホテルへ進んだ"),
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
		and game_state.get_hand_upgrade_level(HandRulesScript.UPGRADE_DEXTERITY) == dexterity_before,
		"お金と道具は置いていき、買った手の強化は持ち越す",
	)
	main.close_tool_shop()

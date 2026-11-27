extends RefCounted
## 既定の毛の本数 (9,999,999 本) で新しく始めた屋敷の入力統合テスト (scripts/dev/integration.gd から呼ぶ)。
## 1 本ずつ描く毛は描く本数の上限 (HairField.DEFAULT_DRAW_BUDGET) までで、残りは埋もれた毛として数だけ持つ。
## その屋敷で手で 1 本抜くと残り本数が 9,999,998 本になり、描いている毛の本数は埋もれた毛から描き足されて変わらないこと、
## 粘着ローラーを床にかけると取れた本数だけ残り本数が減ることを確かめる (issue #65)。

## 目線を床の毛へ向ける手順
const HandAim := preload("res://scripts/dev/hand_aim.gd")
## 手に持って使う道具の定義
const ToolCatalogScript := preload("res://scripts/tools/tool_catalog.gd")
## 毛の描画・管理 (描く本数の上限の既定値)
const HairFieldScript := preload("res://scripts/hair_field.gd")
## 開発者向け調整値データ型スクリプト (既定の毛の本数)
const MansionTuningScript := preload("res://scripts/data/mansion_tuning.gd")
## 道具を床にかける時の、粘着ローラーの半径の中に要る毛の本数 (取れる毛が出るだけの本数)
const MIN_HAIRS_IN_RANGE: int = 2
## 取りこぼしの抽選の乱数のシード (結果を固定する)
const TOOL_RNG_SEED: int = 20261127
## 道具を買う時に持たせるお金 (粘着ローラーの値段より多い額)
const TEST_MONEY: int = 1000

## 検証結果を記録する integration の SceneTree 参照
var _checker: SceneTree = null


## 既定の毛の本数の屋敷の検証をすべて実行する (main は既定の調整値で新しく始めたメインシーン)。
## 終わったら手に持ち替え、持たせたお金を 0 に戻す
static func run_all(checker: SceneTree, main: Node3D, game_state: Node) -> void:
	var suite: RefCounted = load("res://scripts/dev/integration_default_count.gd").new()
	suite._checker = checker
	main.hand.allow_uncaptured_pluck = true
	main.tools.allow_uncaptured_use = true
	main.tools.set_rng_seed(TOOL_RNG_SEED)
	await checker.process_frame
	suite._verify_fresh_counts(main, game_state)
	await suite._verify_hand_pluck(main, game_state)
	await suite._verify_roller_sweep(main, game_state)
	main.hand.allow_uncaptured_pluck = false
	main.tools.allow_uncaptured_use = false
	Input.action_release(HandController.ACTION_PLUCK)
	await checker._press_physical_key(ToolController.SELECT_KEYS[0])
	game_state.save_data.building_progress.money = 0
	await checker.process_frame


## 描いている毛の本数の合計
static func _drawn_count(hair_field: Node3D) -> int:
	var drawn: int = 0
	for surface_index: int in range(hair_field.get_surface_count()):
		drawn += hair_field.get_surface_visible_instance_count(surface_index)
	return drawn


## 検証結果を integration 本体へ記録する
func _check(cond: bool, label: String) -> void:
	_checker._check(cond, label)


## 新しく始めた屋敷の残り本数が 9,999,999 本で、描いている毛は描く本数の上限までか
func _verify_fresh_counts(main: Node3D, game_state: Node) -> void:
	var hair_field: Node3D = main.mansion_world.get_hair_field()
	var drawn: int = _drawn_count(hair_field)
	_check(
		game_state.get_total_remaining_hairs() == 9999999
		and hair_field.get_remaining_count() == 9999999
		and drawn > 0 and drawn <= HairFieldScript.DEFAULT_DRAW_BUDGET,
		"既定の調整値で始めた屋敷は残り 9,999,999 本で、描いている毛は上限 %d 本まで (残り %d 本・描いている %d 本)"
		% [HairFieldScript.DEFAULT_DRAW_BUDGET, game_state.get_total_remaining_hairs(), drawn],
	)


## 手で 1 本抜くと残り本数が 9,999,998 本になり、描いている毛の本数は変わらないか
func _verify_hand_pluck(main: Node3D, game_state: Node) -> void:
	var hand: HandController = main.hand
	var hair_field: Node3D = main.mansion_world.get_hair_field()
	var aimed: int = await HandAim.aim_at_floor_hair(_checker, main)
	if aimed < 0:
		_check(false, "既定の本数の屋敷で床の毛を狙える")
		return
	var drawn_before: int = _drawn_count(hair_field)
	await _checker.process_frame
	Input.action_press(HandController.ACTION_PLUCK)
	await _checker.process_frame
	var plucked: int = hand.advance_pull(hand.get_pull_duration())
	Input.action_release(HandController.ACTION_PLUCK)
	await _checker.process_frame
	_check(
		plucked == 1
		and game_state.get_total_remaining_hairs() == 9999998
		and hair_field.get_remaining_count() == 9999998
		and not hair_field.has_hair(aimed)
		and _drawn_count(hair_field) == drawn_before,
		"既定の本数の屋敷で手で 1 本抜くと残り 9,999,998 本になり、描いている毛は埋もれた毛から描き足されて %d 本のまま (実際: 残り %d 本・描いている %d 本)"
		% [drawn_before, game_state.get_total_remaining_hairs(), _drawn_count(hair_field)],
	)


## 粘着ローラーを買って床にかけると、取れた本数だけ残り本数が減るか
func _verify_roller_sweep(main: Node3D, game_state: Node) -> void:
	var roller: StringName = ToolCatalogScript.TOOL_LINT_ROLLER
	game_state.save_data.building_progress.money = TEST_MONEY
	main.open_tool_shop()
	await _checker.process_frame
	main.tool_shop_panel.get_tool_button(roller).pressed.emit()
	await _checker.process_frame
	main.close_tool_shop()
	var key_index: int = ToolCatalogScript.selectable_tool_ids().find(roller)
	await _checker._press_physical_key(ToolController.SELECT_KEYS[key_index])
	var radius: float = float(ToolCatalogScript.find_tool(roller)["radius_m"])
	if await HandAim.aim_at_floor_hairs(_checker, main, radius, MIN_HAIRS_IN_RANGE) < 0:
		_check(false, "既定の本数の屋敷で粘着ローラーをかける床の毛を狙える")
		return
	var hair_field: Node3D = main.mansion_world.get_hair_field()
	var total_before: int = game_state.get_total_remaining_hairs()
	var field_before: int = hair_field.get_remaining_count()
	var drawn_before: int = _drawn_count(hair_field)
	var captured: Array[Dictionary] = []
	var on_used: Callable = func(result: Dictionary) -> void: captured.append(result)
	main.tools.tool_used.connect(on_used)
	await _checker.press_and_release_use()
	main.tools.tool_used.disconnect(on_used)
	var removed: int = int(captured[0]["removed"]) if not captured.is_empty() else 0
	_check(
		removed > 0
		and total_before - game_state.get_total_remaining_hairs() == removed
		and field_before - hair_field.get_remaining_count() == removed
		and _drawn_count(hair_field) == drawn_before,
		"既定の本数の屋敷で粘着ローラーを床にかけると、取れた %d 本だけ残り本数が減り、描いている毛は %d 本のまま (実際: 残り %d → %d 本)"
		% [removed, drawn_before, total_before, game_state.get_total_remaining_hairs()],
	)

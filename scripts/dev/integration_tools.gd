extends RefCounted
## 手に持って使う道具とお金の入力統合テスト (scripts/dev/integration.gd から呼ぶ)。
## メインシーンを動かし、道具を買う → 1〜8 キーで選ぶ → つまむ入力で使うと毛が減り取りこぼしが残る → 買取業者に売るとお金が増える
## 流れと、8 つの道具を 1 回ずつ使った時の振る舞い、紙が 0 枚の粘着ローラー、掃除代が入ること、道具を買う画面の開閉を確かめる。

## 目線を床の毛へ向ける手順
const HandAim := preload("res://scripts/dev/hand_aim.gd")
## 手に持って使う道具の定義
const ToolCatalogScript := preload("res://scripts/tools/tool_catalog.gd")
## 毛を売る・掃除代の計算
const EconomyRulesScript := preload("res://scripts/economy/economy_rules.gd")
## 状態管理 autoload スクリプト (買う物の種類の定数を使う)
const GameStateScript := preload("res://scripts/state/game_state.gd")
## メインシーンのスクリプト (本数の表示の書式を使う)
const MainScript := preload("res://scripts/main.gd")
## 道具が 1 回で触れる範囲に何本も毛があるよう、検証の間だけ屋敷を組み直す毛の本数
const DENSE_HAIR_COUNT: int = 60000
## 取りこぼしの抽選の乱数のシード (結果を固定する)
const TOOL_RNG_SEED: int = 20261126
## 道具をかける所に要る、粘着ローラーの半径の中の毛の本数 (取れた毛と取りこぼした毛の両方が出るだけの本数)
const MIN_HAIRS_IN_RANGE: int = 8
## 道具を選ぶキー (ToolController.SELECT_KEYS と同じ並び。1 = 手)
const KEY_FOR_TOOL: Dictionary = {
	ToolCatalogScript.TOOL_HAND: KEY_1,
	ToolCatalogScript.TOOL_TWEEZERS: KEY_2,
	ToolCatalogScript.TOOL_PACKING_TAPE: KEY_3,
	ToolCatalogScript.TOOL_RUBBER_GLOVE: KEY_4,
	ToolCatalogScript.TOOL_LINT_ROLLER: KEY_5,
	ToolCatalogScript.TOOL_VACUUM: KEY_6,
	ToolCatalogScript.TOOL_GLOW_LIGHT: KEY_7,
	ToolCatalogScript.TOOL_BRUSH: KEY_8,
}

## 検証結果を記録する integration の SceneTree 参照
var _checker: SceneTree = null


## 道具とお金の検証をすべて実行する (main はプレイ中のメインシーン)。終わったら元の調整値で屋敷を組み直す
static func run_all(checker: SceneTree, main: Node3D, game_state: Node) -> void:
	var suite: RefCounted = load("res://scripts/dev/integration_tools.gd").new()
	suite._checker = checker
	var original_tuning: MansionTuning = game_state.get_tuning()
	var dense_tuning: MansionTuning = original_tuning.clamped()
	dense_tuning.hair_count = DENSE_HAIR_COUNT
	game_state.apply_tuning_and_rebuild(dense_tuning, false)
	await checker.process_frame
	main.auto_advance_time = false
	main.tools.allow_uncaptured_use = true
	main.hand.allow_uncaptured_pluck = true
	main.tools.set_rng_seed(TOOL_RNG_SEED)
	await suite._verify_unowned_tool_and_shop_screen(main, game_state)
	await suite._verify_buy_use_and_sell(main, game_state)
	await suite._verify_empty_consumable(main, game_state)
	await suite._verify_every_tool_once(main, game_state)
	await suite._verify_cleaning_fee(main, game_state)
	main.tools.select_tool(ToolCatalogScript.TOOL_HAND)
	main.tools.allow_uncaptured_use = false
	main.hand.allow_uncaptured_pluck = false
	Input.action_release(HandController.ACTION_PLUCK)
	game_state.apply_tuning_and_rebuild(original_tuning, false)
	await checker.process_frame


## 検証結果を integration 本体へ記録する
func _check(cond: bool, label: String) -> void:
	_checker._check(cond, label)


## 持っていない道具のキーでは選べず、T キーで道具を買う画面が開閉し、開いている間は操作が止まり他の画面が開かないか
func _verify_unowned_tool_and_shop_screen(main: Node3D, game_state: Node) -> void:
	var tools: ToolController = main.tools
	await _checker._press_physical_key(KEY_FOR_TOOL[ToolCatalogScript.TOOL_TWEEZERS])
	_check(
		tools.get_selected_tool_id() == ToolCatalogScript.TOOL_HAND
		and tools.get_last_message().contains("持っていない")
		and main.tool_message_label.text.contains("持っていない")
		and main.hand.enabled,
		"持っていないピンセットのキー (2) では選べず、手のまま「持っていない」と出る",
	)
	var slot_texts: Array[String] = main.look_hud.get_tool_slot_texts()
	_check(
		slot_texts.size() == 8 and slot_texts[0] == "1 手" and slot_texts[1] == "2 —"
		and main.look_hud.get_selected_tool_slot_index() == 0,
		"右下の道具の枠は 8 つで、手の枠が選ばれ、持っていない道具は「—」で出る (実際: %s)" % str(slot_texts),
	)
	await _checker._press_physical_key(KEY_T)
	_check(
		main.tool_shop_panel.visible and not main.player.controls_enabled
		and not main.hand.enabled and not tools.enabled,
		"T キーで道具を買う画面が開き、歩く・つまむ・道具を使う操作が止まる",
	)
	await _checker._press_physical_key(KEY_B)
	await _checker._press_physical_key(KEY_F1)
	_check(
		not main.hair_book_panel.visible and not main.dev_tuning_panel.visible,
		"道具を買う画面が開いている間は B・F1 で他の画面が開かない",
	)
	var roller_button: Button = main.tool_shop_panel.get_tool_button(
		ToolCatalogScript.TOOL_LINT_ROLLER
	)
	_check(
		game_state.get_money() == 0 and roller_button.disabled,
		"0 円では粘着ローラーの買うボタンが押せない",
	)
	await _checker._press_physical_key(KEY_T)
	_check(
		not main.tool_shop_panel.visible and main.player.controls_enabled and tools.enabled,
		"T キーをもう一度押すと道具を買う画面が閉じ、操作が戻る",
	)


## 道具を買い、選んで床の毛にかけると範囲の毛が減って取りこぼしが残り、跡と割合が出て、買取業者に売るとお金が増えるか
func _verify_buy_use_and_sell(main: Node3D, game_state: Node) -> void:
	var tools: ToolController = main.tools
	var roller: StringName = ToolCatalogScript.TOOL_LINT_ROLLER
	game_state.save_data.building_progress.money = 1000
	main.open_tool_shop()
	await _checker.process_frame
	var roller_button: Button = main.tool_shop_panel.get_tool_button(roller)
	_check(not roller_button.disabled, "1000 円あれば粘着ローラーの買うボタンが押せる")
	roller_button.pressed.emit()
	await _checker.process_frame
	var owned: OwnedTool = game_state.find_owned_tool(roller)
	_check(
		owned != null and owned.consumable_count == 20 and game_state.get_money() == 850
		and roller_button.text.begins_with("レベルを上げる"),
		"買うボタンで粘着ローラー (150 円・紙 20 枚) が持ち物に入り、ボタンがレベルを上げるに変わる",
	)
	main.close_tool_shop()
	await _checker._press_physical_key(KEY_FOR_TOOL[roller])
	_check(
		tools.get_selected_tool_id() == roller and not main.hand.enabled
		and main.look_hud.get_tool_slot_texts()[4] == "5 粘着ローラー"
		and main.look_hud.get_selected_tool_slot_index() == 4
		and main.tool_detail_label.text.contains("紙: 20 枚"),
		"5 キーで粘着ローラーを選ぶと手の操作が止まり、5 番目の枠が選ばれ、紙の残りが出る",
	)

	var result: Dictionary = await _use_on_floor(main, game_state)
	var hair_field: Node3D = main.mansion_world.get_hair_field()
	_check(
		bool(result["used"]) and int(result["in_range"]) >= 2
		and int(result["removed"]) > 0 and int(result["missed"]) > 0
		and int(result["removed"]) + int(result["missed"]) == int(result["in_range"]),
		"粘着ローラーを床の毛にかけると範囲の毛が減り、取りこぼしが残る (範囲 %d 本・取れた %d 本・残った %d 本)"
		% [result["in_range"], result["removed"], result["missed"]],
	)
	_check(
		int(result["total_before"]) - game_state.get_total_remaining_hairs() == int(result["removed"])
		and int(result["field_before"]) - hair_field.get_remaining_count() == int(result["removed"])
		and game_state.get_raw_hair_stock_count() - int(result["stock_before"]) == int(result["removed"])
		and owned.consumable_count == 19,
		"取れた本数だけ残り本数・描いている毛が減って在庫が増え、紙を 1 枚使う",
	)
	var near_after: PackedInt32Array = hair_field.find_hairs_near(
		result["surface_index"],
		result["point"],
		float(ToolCatalogScript.find_tool(roller)["radius_m"]),
		int(ToolCatalogScript.find_tool(roller)["max_hairs"])
	)
	_check(
		near_after.size() >= int(result["missed"]),
		"取りこぼした毛はかけた範囲に残っている (範囲に %d 本)" % near_after.size(),
	)
	var trace: MeshInstance3D = tools.get_trace()
	_check(
		trace != null and trace.global_position.distance_to(result["point"]) < 0.05
		and main.tool_message_label.text.contains("取りこぼし")
		and main.tool_message_label.text.contains("%d / %d 本" % [result["missed"], result["in_range"]]),
		"かけた所に跡の円盤が出て、取りこぼしの割合と残った本数が出る (実際: %s)"
		% main.tool_message_label.text,
	)

	main.open_tool_shop()
	await _checker.process_frame
	_check(
		not main.is_near_trader() and main.tool_shop_panel.get_sell_button().disabled,
		"買取業者から離れている時は毛を売るボタンが押せない",
	)
	var money_far: int = game_state.get_money()
	main.tool_shop_panel.sell_requested.emit()
	await _checker.process_frame
	_check(game_state.get_money() == money_far, "買取業者から離れている時は売る操作でお金が変わらない")
	main.close_tool_shop()
	var trader: Vector3 = main.mansion_world.get_trader_position()
	main.player.set_spawn(trader + Vector3(1.0, 0.0, -1.0), 0.0)
	await _checker.physics_frame
	await _checker.physics_frame
	main.open_tool_shop()
	await _checker.process_frame
	var stock_value: int = EconomyRulesScript.raw_stock_value(
		game_state.save_data.building_progress.hair_stocks
	)
	var sell_button: Button = main.tool_shop_panel.get_sell_button()
	_check(
		main.is_near_trader() and not sell_button.disabled and stock_value > 0,
		"裏口の買取業者の近くでは毛を売るボタンが押せる",
	)
	var money_before: int = game_state.get_money()
	sell_button.pressed.emit()
	await _checker.process_frame
	_check(
		game_state.get_money() == money_before + stock_value
		and game_state.get_raw_hair_stock_count() == 0
		and main.look_hud.get_money_text()
		== "所持金 %s 円" % MainScript.format_hair_count(game_state.get_money()),
		"毛を売ると在庫の売値 %d 円だけお金が増え、在庫が 0 本になり、所持金の表示も変わる" % stock_value,
	)
	main.close_tool_shop()


## 紙が 0 枚の粘着ローラーは使えず毛が変わらず、紙を買い足すとまた使えるか
func _verify_empty_consumable(main: Node3D, game_state: Node) -> void:
	var roller: StringName = ToolCatalogScript.TOOL_LINT_ROLLER
	var owned: OwnedTool = game_state.find_owned_tool(roller)
	owned.consumable_count = 0
	var aimed: bool = await _aim_at_floor_hairs(main)
	var before_total: int = game_state.get_total_remaining_hairs()
	await _press_and_release_use()
	_check(
		aimed and game_state.get_total_remaining_hairs() == before_total
		and owned.consumable_count == 0
		and main.tool_message_label.text.contains("紙が無い"),
		"紙が 0 枚の粘着ローラーを使っても毛が減らず、「紙が無い」と出る",
	)
	main.open_tool_shop()
	await _checker.process_frame
	var refill: Button = main.tool_shop_panel.get_refill_button(roller)
	var money_before: int = game_state.get_money()
	refill.pressed.emit()
	await _checker.process_frame
	_check(
		owned.consumable_count == 20 and game_state.get_money() == money_before - 10,
		"紙の買い足しボタンで紙が 20 枚になり 10 円減る",
	)
	main.close_tool_shop()
	await _verify_capture_click(main, game_state, owned)


## マウスを捕捉していない時のクリックと、捕捉する最初のクリックでは道具を使わず、捕捉した後のクリックで使うか
func _verify_capture_click(main: Node3D, game_state: Node, owned: OwnedTool) -> void:
	var tools: ToolController = main.tools
	await _aim_at_floor_hairs(main)
	var before_total: int = game_state.get_total_remaining_hairs()
	tools.allow_uncaptured_use = false
	Input.action_press(HandController.ACTION_PLUCK)
	await _checker.process_frame
	await _checker.process_frame
	_check(
		owned.consumable_count == 20 and game_state.get_total_remaining_hairs() == before_total,
		"マウスを捕捉していない時のクリックでは道具を使わない",
	)
	# 押したまま捕捉した扱いに切り替える (捕捉する最初のクリックと同じく、前のフレームは捕捉していない)
	tools.allow_uncaptured_use = true
	await _checker.process_frame
	await _checker.process_frame
	Input.action_release(HandController.ACTION_PLUCK)
	await _checker.process_frame
	_check(
		owned.consumable_count == 20 and game_state.get_total_remaining_hairs() == before_total,
		"マウスを捕捉する最初のクリックでは道具を使わず、紙も減らない",
	)
	await _press_and_release_use()
	_check(owned.consumable_count == 19, "捕捉した後のクリックでは道具を使い、紙が 1 枚減る")


## 8 つの道具を 1 回ずつ使う: 手はつまんで 1 本抜け、毛を取る 5 つは範囲の毛が減り、ライトは点いて消え、
## ブラシは猫がいないので何も変わらない
func _verify_every_tool_once(main: Node3D, game_state: Node) -> void:
	var tools: ToolController = main.tools
	game_state.save_data.building_progress.money = 100000
	for tool_def: Dictionary in ToolCatalogScript.TOOLS:
		if tool_def["id"] != ToolCatalogScript.TOOL_HAND:
			game_state.purchase(GameStateScript.PURCHASE_TOOL, tool_def["id"])
	_check(
		game_state.save_data.building_progress.owned_tools.size() == 7,
		"手以外の 7 つの道具を買える",
	)
	var used_ids: Array[StringName] = []
	for tool_def: Dictionary in ToolCatalogScript.TOOLS:
		var tool_id: StringName = tool_def["id"]
		await _checker._press_physical_key(KEY_FOR_TOOL[tool_id])
		if tools.get_selected_tool_id() != tool_id:
			_check(false, "%s をキーで選べる" % tool_def["name"])
			continue
		match tool_def["kind"]:
			ToolCatalogScript.KIND_HAND:
				if await _pluck_with_hand(main, game_state):
					used_ids.append(tool_id)
			ToolCatalogScript.KIND_SWEEP:
				var result: Dictionary = await _use_on_floor(main, game_state)
				var removed: int = int(result.get("removed", 0))
				_check(
					bool(result.get("used", false)) and removed > 0
					and int(result["total_before"]) - game_state.get_total_remaining_hairs() == removed,
					"%s を床の毛にかけると %d 本取れて残り本数が同じだけ減る (範囲 %d 本)"
					% [tool_def["name"], removed, int(result.get("in_range", 0))],
				)
				if removed > 0:
					used_ids.append(tool_id)
			ToolCatalogScript.KIND_LIGHT:
				var before_light: int = game_state.get_total_remaining_hairs()
				await _press_and_release_use()
				var on: bool = tools.is_glow_light_on()
				await _press_and_release_use()
				_check(
					on and not tools.is_glow_light_on()
					and game_state.get_total_remaining_hairs() == before_light,
					"毛を光らせるライトは 1 回目で点き、2 回目で消え、毛の本数は変わらない",
				)
				if on:
					used_ids.append(tool_id)
			ToolCatalogScript.KIND_CAT:
				var before_brush: int = game_state.get_total_remaining_hairs()
				var money_brush: int = game_state.get_money()
				await _press_and_release_use()
				_check(
					main.tool_message_label.text.contains("猫がいない")
					and game_state.get_total_remaining_hairs() == before_brush
					and game_state.get_money() == money_brush
					and not bool(tools.brush_cat(null)["used"]),
					"ブラシは猫がいない屋敷では「猫がいない」と出て、毛の本数とお金が変わらない",
				)
				used_ids.append(tool_id)
	_check(
		used_ids.size() == 8,
		"8 つの道具を 1 回ずつ使えた (実際: %s)" % str(used_ids),
	)


## 時間が 60 秒の区切りをまたぐと、機嫌に比例した掃除代が所持金に入り、今いる部屋のゲージが部屋の様子と一致するか
func _verify_cleaning_fee(main: Node3D, game_state: Node) -> void:
	await _checker.process_frame
	var room: MansionLayout.RoomDef = main.get_current_room()
	_check(room != null and main.room_gauge_panel.visible, "部屋の中では部屋のゲージが出る")
	if room == null:
		return
	var status: Dictionary = game_state.get_room_status(room.room_id)
	_check(
		is_equal_approx(main.cleanliness_bar.value, 100.0 * float(status["cleanliness"]))
		and is_equal_approx(main.mood_bar.value, 100.0 * float(status["mood"]))
		and main.cleaning_fee_label.text.contains("%d 円" % int(status["cleaning_fee"]))
		and main.room_name_label.text.contains(room.display_name),
		"部屋のゲージのきれいさ・機嫌・掃除代が今いる部屋の様子と一致する",
	)
	var progress: BuildingProgress = game_state.save_data.building_progress
	progress.elapsed_seconds = EconomyRulesScript.PAYMENT_INTERVAL_SECONDS - 0.001
	var money_before: int = game_state.get_money()
	main.auto_advance_time = true
	await _checker.create_timer(0.2).timeout
	main.auto_advance_time = false
	_check(
		game_state.get_money() > money_before
		and progress.elapsed_seconds > EconomyRulesScript.PAYMENT_INTERVAL_SECONDS
		and main.get_pluck_popup_text().contains("掃除代"),
		"プレイ中に 60 秒の区切りをまたぐと掃除代が所持金に入り、「掃除代 +N 円」と出る (%d → %d 円)"
		% [money_before, game_state.get_money()],
	)


## 道具の届く範囲 (粘着ローラーの半径) に毛が MIN_HAIRS_IN_RANGE 本以上ある床の点を、画面中央で狙う。狙えたら true
func _aim_at_floor_hairs(main: Node3D) -> bool:
	var radius: float = float(
		ToolCatalogScript.find_tool(ToolCatalogScript.TOOL_LINT_ROLLER)["radius_m"]
	)
	return await HandAim.aim_at_floor_hairs(_checker, main, radius, MIN_HAIRS_IN_RANGE) >= 0


## 床の毛を狙い、選んでいる道具を 1 回使い、結果と使う前の本数を返す (狙えなければ "used" が false)
func _use_on_floor(main: Node3D, game_state: Node) -> Dictionary:
	if not await _aim_at_floor_hairs(main):
		return {"used": false, "total_before": game_state.get_total_remaining_hairs()}
	var target: Dictionary = main.hand.aim_target()
	var before: Dictionary = {
		"total_before": game_state.get_total_remaining_hairs(),
		"field_before": main.mansion_world.get_hair_field().get_remaining_count(),
		"stock_before": game_state.get_raw_hair_stock_count(),
		"surface_index": int(target["surface_index"]),
		"point": target["point"],
	}
	var captured: Array[Dictionary] = []
	var on_used: Callable = func(result: Dictionary) -> void: captured.append(result)
	main.tools.tool_used.connect(on_used)
	await _press_and_release_use()
	main.tools.tool_used.disconnect(on_used)
	var result: Dictionary = captured[0] if not captured.is_empty() else {"used": false}
	result.merge(before, true)
	return result


## 手で床の毛を 1 本つまんで抜く (引き終わるまで押し続ける)。抜けたら true
func _pluck_with_hand(main: Node3D, game_state: Node) -> bool:
	var aimed: int = await HandAim.aim_at_floor_hair(_checker, main)
	var before_total: int = game_state.get_total_remaining_hairs()
	Input.action_press(HandController.ACTION_PLUCK)
	await _checker.create_timer(main.hand.get_pull_duration() + 1.0).timeout
	Input.action_release(HandController.ACTION_PLUCK)
	await _checker.process_frame
	var plucked: bool = aimed >= 0 and game_state.get_total_remaining_hairs() < before_total
	_check(plucked, "手を選んでつまむ入力を押し続けると床の毛が抜ける")
	return plucked


## つまむ入力を 1 フレーム押して離す (手以外の道具を選んでいる時は道具を 1 回使う)
func _press_and_release_use() -> void:
	Input.action_press(HandController.ACTION_PLUCK)
	await _checker.process_frame
	Input.action_release(HandController.ACTION_PLUCK)
	await _checker.process_frame

extends RefCounted
## 住人の依頼の入力統合テスト (scripts/dev/integration.gd から呼ぶ)。メインシーンを動かし、J キーで依頼を聞く →
## 毛を取って探し物を見つける → 合う道具で取る → 持ち主の部屋に入って返す → お金が増える、の一連と、合わない道具 (掃除機) で
## 取ると傷んでお礼が減ること、逃げた猫を毛の跡の先で抱えて持ち主の部屋に届けると住人がご機嫌になることを確かめる。

## 依頼の計算
const RequestRulesScript := preload("res://scripts/requests/request_rules.gd")
## 探し物の状態の型
const FoundItemProgressScript := preload("res://scripts/data/found_item_progress.gd")
## 道具の定義
const ToolCatalogScript := preload("res://scripts/tools/tool_catalog.gd")
## 状態管理 autoload スクリプト (買う物の種類の定数を使う)
const GameStateScript := preload("res://scripts/state/game_state.gd")
## 住人の依頼の検証スイート (次の掃除代で入るお礼の計算)
const SelfcheckRequestsScript := preload("res://scripts/dev/selfcheck_requests.gd")
## 屋敷ビルダー (住人の id)
const MansionBuilderScript := preload("res://scripts/mansion/mansion_builder.gd")
## 検証の間だけ屋敷を組み直す毛の本数。手でつまむ回数を少なくし、探し物の面の毛を短い時間で半分にできる本数
const FEW_HAIR_COUNT: int = 600
## 部屋の中心へ立たせた後に、歩いて起きる操作 (返す・届ける) を待つフレーム数
const SETTLE_FRAMES: int = 3

## 検証結果を記録する integration の SceneTree 参照
var _checker: SceneTree = null


## 住人の依頼の検証をすべて実行する (main はプレイ中のメインシーン)。終わったら元の調整値で屋敷を組み直す
static func run_all(checker: SceneTree, main: Node3D, game_state: Node) -> void:
	var suite: RefCounted = load("res://scripts/dev/integration_requests.gd").new()
	suite._checker = checker
	var original_tuning: MansionTuning = game_state.get_tuning()
	var few_tuning: MansionTuning = original_tuning.clamped()
	few_tuning.hair_count = FEW_HAIR_COUNT
	game_state.apply_tuning_and_rebuild(few_tuning, false)
	await checker.process_frame
	main.auto_advance_time = false
	main.tools.allow_uncaptured_use = true
	await suite._verify_request_list_screen(main, game_state)
	await suite._verify_find_take_and_return(main, game_state)
	await suite._verify_rough_tool_damages(main, game_state)
	await suite._verify_room_tool_damages(main, game_state)
	await suite._verify_runaway_cat(main, game_state)
	main.tools.allow_uncaptured_use = false
	main.tools.select_tool(ToolCatalogScript.TOOL_HAND)
	main.auto_advance_time = true
	game_state.apply_tuning_and_rebuild(original_tuning, false)
	await checker.process_frame


## 検証結果を integration 本体へ記録する
func _check(cond: bool, label: String) -> void:
	_checker._check(cond, label)


## J キーで依頼の一覧が開閉し、開いている間は操作が止まって他の画面が開かず、探し物の残りの数が出るか (依頼を聞く)
func _verify_request_list_screen(main: Node3D, game_state: Node) -> void:
	var count: int = game_state.current_layout.found_item_spots.size()
	await _checker._press_physical_key(KEY_J)
	var panel: RequestListPanel = main.requests.panel
	var rows: PackedStringArray = panel.get_row_texts()
	_check(
		panel.visible and not main.player.controls_enabled and not main.tools.enabled
		and panel.get_summary_text() == "探し物: 残り %d / %d 件" % [count, count]
		and count > 0 and rows[0].contains("埋もれている")
		and Array(rows).any(func(row: String) -> bool: return row.begins_with("・黒いスーツ"))
		and Array(rows).any(func(row: String) -> bool: return row.begins_with("・逃げた猫")),
		"J キーで住人の依頼の一覧が開き、操作が止まり、探し物の残り %d 件・スーツ・逃げた猫の依頼が出る (実際: %s)"
		% [count, panel.get_summary_text()],
	)
	await _checker._press_physical_key(KEY_T)
	await _checker._press_physical_key(KEY_B)
	_check(
		not main.tool_shop_panel.visible and not main.hair_book_panel.visible,
		"依頼の一覧が開いている間は T・B で他の画面が開かない",
	)
	await _checker._press_physical_key(KEY_J)
	_check(
		not panel.visible and main.player.controls_enabled and main.tools.enabled,
		"J キーをもう一度押すと依頼の一覧が閉じ、操作が戻る",
	)


## 探し物の面の毛を手でつまんで半分にすると探し物が出てきて、合う道具で取り、持ち主の部屋に入ると返してお礼が入るか
func _verify_find_take_and_return(main: Node3D, game_state: Node) -> void:
	var spot: MansionLayout.FoundItemSpotDef = game_state.current_layout.found_item_spots[0]
	var item: FoundItemProgress = game_state.requests.find_item(spot.found_item_id)
	var kind: Dictionary = RequestRulesScript.kind_for_item_id(spot.found_item_id)
	var popups: Array[String] = []
	var on_notice: Callable = func(text: String) -> void: popups.append(text)
	main.requests.notice_posted.connect(on_notice)
	_pluck_until_revealed(game_state, spot)
	await _checker.process_frame
	var item_node: Node3D = main.requests.get_item_node(spot.found_item_id)
	_check(
		item.condition == FoundItemProgressScript.Condition.FOUND
		and item_node != null and item_node.visible
		and main.get_pluck_popup_text().begins_with("探し物が出てきた: %s" % kind["name"]),
		"面の毛を手でつまんで半分にすると、%s が毛の上に出てきて知らせが出る (実際: %s)"
		% [kind["name"], main.get_pluck_popup_text()],
	)
	# 持ち主の部屋に立ったまま取ると、取った直後に返してしまうため、別の部屋に立ってから道具をかける
	await _stand_in_room(main, _other_room_id(game_state, spot.room_id))
	var match_tool: StringName = kind["match_tool"]
	game_state.save_data.building_progress.money = 100000
	game_state.purchase(GameStateScript.PURCHASE_TOOL, match_tool)
	main.tools.select_tool(match_tool)
	var result: Dictionary = main.tools.use_selected_tool_at(_target_at(main, spot))
	await _checker.process_frame
	_check(
		bool(result["used"]) and item.condition == FoundItemProgressScript.Condition.CLEAN
		and not item_node.visible and popups.has("%sをきれいに取った" % kind["name"]),
		"合う道具 (%s) で探し物をかけるときれいに取れ、屋敷から消える"
		% ToolCatalogScript.find_tool(match_tool)["name"],
	)
	await _stand_in_room(main, _other_room_id(game_state, spot.room_id))
	_check(not item.is_returned, "持ち主でない部屋に入っても探し物は返さない")
	await _stand_in_room(main, spot.room_id)
	main.toggle_requests()
	var rows: PackedStringArray = main.requests.panel.get_row_texts()
	await _checker.process_frame
	var gauge_with_reward: String = main.cleaning_fee_label.text
	var money_before: int = game_state.get_money()
	var added: int = SelfcheckRequestsScript.reward_in_next_payment(game_state)
	await _checker.process_frame
	_check(
		gauge_with_reward.ends_with("(次はお礼 +%d 円)" % RequestRulesScript.REWARD_CLEAN)
		and not main.cleaning_fee_label.text.contains("次はお礼"),
		"返した後は部屋のゲージの掃除代の横に次のお礼が出て、払った後は消える (実際: %s → %s)"
		% [gauge_with_reward, main.cleaning_fee_label.text],
	)
	_check(
		item.is_returned and added == RequestRulesScript.REWARD_CLEAN
		and game_state.get_money() > money_before
		and popups.has(
			"%sを返した: 次の掃除代にお礼 +%d 円" % [kind["name"], RequestRulesScript.REWARD_CLEAN]
		)
		and rows[0].contains("返した")
		and main.requests.panel.get_summary_text().begins_with(
			"探し物: 残り %d " % (game_state.current_layout.found_item_spots.size() - 1)
		),
		"持ち主の部屋に入ると探し物を返し、次の掃除代でお礼 %d 円が入ってお金が増え、一覧の残りが 1 件減る (実際: %d 円・%s)"
		% [RequestRulesScript.REWARD_CLEAN, added, rows[0]],
	)
	main.toggle_requests()
	main.requests.notice_posted.disconnect(on_notice)


## 合わない道具 (探し物を傷める掃除機) で取ると探し物が傷み、返した時のお礼がきれいな時より少ないか
func _verify_rough_tool_damages(main: Node3D, game_state: Node) -> void:
	var spot: MansionLayout.FoundItemSpotDef = game_state.current_layout.found_item_spots[1]
	var item: FoundItemProgress = game_state.requests.find_item(spot.found_item_id)
	_pluck_until_revealed(game_state, spot)
	await _stand_in_room(main, _other_room_id(game_state, spot.room_id))
	var vacuum: StringName = ToolCatalogScript.TOOL_VACUUM
	game_state.purchase(GameStateScript.PURCHASE_TOOL, vacuum)
	main.tools.select_tool(vacuum)
	main.tools.use_selected_tool_at(_target_at(main, spot))
	await _checker.process_frame
	_check(
		item.condition == FoundItemProgressScript.Condition.DAMAGED,
		"掃除機で探し物を吸うと傷む",
	)
	await _stand_in_room(main, spot.room_id)
	var paid: int = SelfcheckRequestsScript.reward_in_next_payment(game_state)
	_check(
		item.is_returned and paid == RequestRulesScript.REWARD_DAMAGED
		and paid < RequestRulesScript.REWARD_CLEAN,
		"傷めた探し物を返すと次の掃除代のお礼は %d 円で、きれいな時 (%d 円) より少ない (実際: %d 円)"
		% [RequestRulesScript.REWARD_DAMAGED, RequestRulesScript.REWARD_CLEAN, paid],
	)


## 部屋ごとにかける道具 (吸引車) を部屋で使うと、その部屋のまだ取っていない探し物は傷み、別の部屋の探し物は変わらないか
func _verify_room_tool_damages(main: Node3D, game_state: Node) -> void:
	var layout: MansionLayout = game_state.current_layout
	var target: MansionLayout.FoundItemSpotDef = null
	var other: MansionLayout.FoundItemSpotDef = null
	# 毛の少ない検証用の屋敷は探し物が 2 つで、前の検証で両方取って返しているため、埋もれた状態に戻してから使う
	for item: FoundItemProgress in game_state.save_data.building_progress.found_items:
		item.condition = FoundItemProgressScript.Condition.HIDDEN
		item.is_returned = false
	for spot: MansionLayout.FoundItemSpotDef in layout.found_item_spots:
		var condition: FoundItemProgress.Condition = (
			game_state.requests.find_item(spot.found_item_id).condition
		)
		# 前の検証で毛を減らした面の探し物は出てきている (FOUND) ことがあるため、まだ取っていない物を対象にする
		if condition not in [
			FoundItemProgressScript.Condition.HIDDEN, FoundItemProgressScript.Condition.FOUND
		]:
			continue
		if target == null:
			target = spot
		elif other == null and spot.room_id != target.room_id:
			other = spot
	var summary: PackedStringArray = PackedStringArray()
	for spot: MansionLayout.FoundItemSpotDef in layout.found_item_spots:
		summary.append("%s@%s=%d" % [
			spot.found_item_id, spot.room_id,
			game_state.requests.find_item(spot.found_item_id).condition,
		])
	_check(
		target != null and other != null,
		"まだ取っていない探し物が 2 つの部屋に残っている (実際: %s)" % ", ".join(summary),
	)
	if target == null or other == null:
		return
	var other_before: FoundItemProgress.Condition = (
		game_state.requests.find_item(other.found_item_id).condition
	)
	var truck: StringName = ToolCatalogScript.TOOL_SUCTION_TRUCK
	game_state.save_data.building_progress.money = 1000000
	game_state.purchase(GameStateScript.PURCHASE_TOOL, truck)
	await _stand_in_room(main, target.room_id)
	main.tools.select_tool(truck)
	var result: Dictionary = main.tools.use_selected_tool_at(_target_at(main, target))
	await _checker.process_frame
	_check(
		game_state.requests.find_item(target.found_item_id).condition
		== FoundItemProgressScript.Condition.DAMAGED
		and game_state.requests.find_item(other.found_item_id).condition == other_before,
		"吸引車を部屋で使うと、その部屋のまだ取っていない探し物は傷み、別の部屋の探し物は変わらない (実際: %s・%s・%s)"
		% [
			str(result), str(target.found_item_id),
			game_state.requests.find_item(target.found_item_id).condition,
		],
	)
	main.tools.select_tool(ToolCatalogScript.TOOL_HAND)


## 猫が逃げると毛の跡が出て、隠れている所へ歩くと抱え、持ち主の部屋に入ると届けて住人がご機嫌になるか
func _verify_runaway_cat(main: Node3D, game_state: Node) -> void:
	var layout: MansionLayout = game_state.current_layout
	var owner_room: MansionLayout.RoomDef = RequestRulesScript.runaway_owner_room(layout)
	# 隠れる部屋に立っていると逃げた直後に抱えてしまうため、毛の跡の始まる持ち主の部屋に立つ
	await _stand_in_room(main, owner_room.room_id)
	game_state.advance_time(RequestRulesScript.RUNAWAY_START_SECONDS)
	# SceneTree の process_frame はノードの _process より前に出るため、猫の位置を動かす _process を 1 回通すには 2 フレーム待つ
	await _checker.process_frame
	await _checker.process_frame
	var cat_node: Node3D = main.automation.get_cat_node(RequestRulesScript.runaway_cat_id())
	var hiding: Vector3 = RequestRulesScript.runaway_hiding_point(layout)
	_check(
		game_state.requests.runaway_status() == &"escaped"
		and main.requests.get_trail_state()["visible"]
		and int(main.requests.get_trail_state()["count"]) > 0
		and Vector2(cat_node.position.x - hiding.x, cat_node.position.z - hiding.z).length() < 0.01,
		"猫が逃げると、持ち主の部屋から毛の跡が出て、猫は隠れている所にいる (実際: %s・跡 %s・猫 %s / 隠れる所 %s)"
		% [
			game_state.requests.runaway_status(), str(main.requests.get_trail_state()),
			str(cat_node.position), str(hiding),
		],
	)
	var resident: StringName = MansionBuilderScript.resident_id_for_room(owner_room.room_id)
	game_state.save_data.building_progress.resident_moods[resident] = 0.2
	main.player.set_spawn(hiding + Vector3(0.5, 0.0, 0.0), 0.0)
	for _frame: int in range(SETTLE_FRAMES):
		await _checker.physics_frame
	await _checker.process_frame
	var centers: Dictionary = main.automation.cat_centers()
	_check(
		game_state.requests.runaway_status() == &"carried" and not cat_node.visible
		and not main.requests.get_trail_state()["visible"]
		and not centers.has(RequestRulesScript.runaway_cat_id()) and not centers.is_empty(),
		"隠れている猫に近づくと抱え、猫と毛の跡が消え、抱えた猫はブラシで狙う猫から外れる",
	)
	await _stand_in_room(main, owner_room.room_id)
	_check(
		game_state.requests.runaway_status() == &"returned" and cat_node.visible
		and is_equal_approx(
			float(game_state.save_data.building_progress.resident_moods[resident]),
			RequestRulesScript.RUNAWAY_RETURN_MOOD
		),
		"抱えた猫を持ち主の部屋に届けると、住人がご機嫌になり、猫が通り道に戻る",
	)


## 探し物 spot の面の毛を、手でつまむ GameState の入口 (pluck_hair) で 1 本ずつ取り、探し物が出てくるまで続ける
static func _pluck_until_revealed(game_state: Node, spot: MansionLayout.FoundItemSpotDef) -> void:
	var item: FoundItemProgress = game_state.requests.find_item(spot.found_item_id)
	var surface: SurfaceHair = game_state.save_data.building_progress.find_surface_hair(
		spot.surface_id
	)
	while item.condition == FoundItemProgressScript.Condition.HIDDEN and surface.total_count() > 0:
		for color_key: Variant in surface.hair_counts.keys():
			if surface.count_for_color(color_key) > 0:
				game_state.pluck_hair(spot.surface_id, color_key)
				break


## 探し物 spot の上を狙った時の狙いの点 (HandController.aim_target の戻り値と同じ形)
static func _target_at(main: Node3D, spot: MansionLayout.FoundItemSpotDef) -> Dictionary:
	var layout: MansionLayout = main.get_game_state().current_layout
	for surface_index: int in range(layout.surfaces.size()):
		if layout.surfaces[surface_index].surface_id == spot.surface_id:
			return {"surface_index": surface_index, "point": spot.position}
	return {}


## プレイヤーを部屋 room_id の中心に立たせ、歩いて起きる操作を待つ
func _stand_in_room(main: Node3D, room_id: StringName) -> void:
	for room: MansionLayout.RoomDef in main.get_game_state().current_layout.rooms:
		if room.room_id == room_id:
			main.player.set_spawn(room.center, 0.0)
	for _frame: int in range(SETTLE_FRAMES):
		await _checker.physics_frame


## room_id と違う部屋の id
static func _other_room_id(game_state: Node, room_id: StringName) -> StringName:
	for room: MansionLayout.RoomDef in game_state.current_layout.rooms:
		if room.room_id != room_id:
			return room.room_id
	return &""


extends RefCounted
## 大型の道具の入力統合テスト (scripts/dev/integration.gd から呼ぶ)。業務用の吸引車・建物を覆う粘着シート・アンドロイド・
## 毛の加工機・毛を運ぶダンプカーを道具を買う画面で買って使い、加工してから売ると毛のまま売るより多く入るかを確かめる。

## 道具とお金の入力統合テスト (つまむ入力を押して離す手順を使う)
const IntegrationToolsScript := preload("res://scripts/dev/integration_tools.gd")
## 道具の定義
const ToolCatalogScript := preload("res://scripts/tools/tool_catalog.gd")
## 道具のルールの計算
const ToolRulesScript := preload("res://scripts/tools/tool_rules.gd")
## 毛の加工機とダンプカーの計算
const ProcessingRulesScript := preload("res://scripts/economy/processing_rules.gd")
## 面ごとの毛データ型スクリプト (色の定数を使う)
const SurfaceHairScript := preload("res://scripts/data/surface_hair.gd")
## 毛・加工品在庫データ型スクリプト
const HairStockScript := preload("res://scripts/data/hair_stock.gd")
## 部屋ごとにかける道具で、部屋の毛が 1 回で取り切れないことを確かめられる屋敷全体の毛の本数
const DENSE_HAIR_COUNT: int = 60000
## 道具の取りこぼしの抽選の乱数のシード (結果を毎回同じにする)
const RNG_SEED: int = 20261127
## 引いている毛に見せる伸ばした見た目の倍率 (手で引く時の見た目と同じく、毛の向きに長く伸ばして元と見分けられる値)
const STRETCHED_SCALE: Vector3 = Vector3(1.0, 2.0, 1.0)
## 加工を確かめる在庫の、色ごとの毛のままの本数
const STOCK_HAIRS_PER_COLOR: int = 500

## 検証結果を記録する integration の SceneTree 参照
var _checker: SceneTree = null


## 大型の道具の検証をすべて実行する (main はプレイ中のメインシーン)。終わったら元の調整値で屋敷を組み直す
static func run_all(checker: SceneTree, main: Node3D, game_state: Node) -> void:
	var suite: RefCounted = load("res://scripts/dev/integration_big_tools.gd").new()
	suite._checker = checker
	var original_tuning: MansionTuning = game_state.get_tuning()
	var dense_tuning: MansionTuning = original_tuning.clamped()
	dense_tuning.hair_count = DENSE_HAIR_COUNT
	game_state.apply_tuning_and_rebuild(dense_tuning, false)
	await checker.process_frame
	main.auto_advance_time = false
	main.tools.allow_uncaptured_use = true
	main.tools.set_rng_seed(RNG_SEED)
	main.big_tools.set_rng_seed(RNG_SEED)
	game_state.save_data.building_progress.money = 100000
	await suite._verify_suction_truck(main, game_state)
	await suite._verify_adhesive_sheet(main, game_state)
	await suite._verify_android(main, game_state)
	await suite._verify_processing_and_selling(main, game_state)
	await suite._verify_dump_truck(main, game_state)
	await suite._verify_rebuild_clears_big_tools(main, game_state, dense_tuning)
	main.tools.allow_uncaptured_use = false
	Input.action_release(HandController.ACTION_PLUCK)
	game_state.apply_tuning_and_rebuild(original_tuning, false)
	await checker.process_frame


## 検証結果を integration 本体へ記録する
func _check(cond: bool, label: String) -> void:
	_checker._check(cond, label)


## 道具を買う画面で tool_id の買うボタンを押す。買えたら true
func _buy_in_shop(main: Node3D, game_state: Node, tool_id: StringName) -> bool:
	var owned_before: int = ToolRulesScript.count_owned(
		game_state.save_data.building_progress.owned_tools, tool_id
	)
	main.open_tool_shop()
	await _checker.process_frame
	main.tool_shop_panel.get_tool_button(tool_id).pressed.emit()
	await _checker.process_frame
	main.close_tool_shop()
	await _checker.process_frame
	return (
		ToolRulesScript.count_owned(game_state.save_data.building_progress.owned_tools, tool_id)
		== owned_before + 1
	)


## 部屋 room の中に立つ (部屋の南寄りから中央を向く)
func _stand_in_room(main: Node3D, room: MansionLayout.RoomDef) -> void:
	main.player.set_spawn(room.center + Vector3(0.0, 0.0, room.size.z * 0.3), 0.0)
	await _checker.physics_frame
	await _checker.physics_frame
	main.player.look_at_point(room.center)


## 吸引車を買い、9 キーで選ぶと運転席からの眺めになり、使うと今いる部屋の毛が取り切らずに減り、描く毛も同じだけ減るか。
## 部屋の外では使えず、道具を買う画面を開くと運転席が隠れ、手に持ち替えると運転席から降りるか
func _verify_suction_truck(main: Node3D, game_state: Node) -> void:
	var truck: StringName = ToolCatalogScript.TOOL_SUCTION_TRUCK
	_check(await _buy_in_shop(main, game_state, truck), "道具を買う画面で業務用の吸引車を買える")
	var room: MansionLayout.RoomDef = game_state.current_layout.rooms[0]
	await _stand_in_room(main, room)
	await _checker._press_physical_key(KEY_9)
	_check(
		main.tools.get_selected_tool_id() == truck and main.tools.is_in_driver_seat()
		and not main.hand.get_hand_view().visible
		and main.look_hud.get_tool_slot_texts()[8] == "9 業務用の吸引車",
		"9 キーで吸引車を選ぶと運転席からの眺めになって画面の手が隠れ、9 番目の枠に吸引車が出る",
	)
	var room_before: int = int(game_state.get_room_status(room.room_id)["hair_count"])
	var field_before: int = main.mansion_world.get_hair_field().get_remaining_count()
	await _press_and_release_use()
	var room_after: int = int(game_state.get_room_status(room.room_id)["hair_count"])
	var removed: int = room_before - room_after
	_check(
		removed > 0 and room_after > 0
		and field_before - main.mansion_world.get_hair_field().get_remaining_count() == removed
		and main.tool_message_label.text.contains(room.display_name)
		and main.tool_message_label.text.contains("取りこぼし"),
		"吸引車を使うと今いる部屋の毛が %d 本減って取り切らず (残り %d 本)、描く毛も同じだけ減り、部屋の名前と取りこぼしが出る (%s)"
		% [removed, room_after, main.tool_message_label.text],
	)
	main.open_tool_shop()
	await _checker.process_frame
	var hidden_in_shop: bool = not main.tools.is_in_driver_seat()
	main.close_tool_shop()
	await _checker.process_frame
	_check(
		hidden_in_shop and main.tools.is_in_driver_seat(),
		"道具を買う画面を開いている間は運転席が隠れ、閉じると運転席に戻る",
	)
	main.player.set_spawn(Vector3(500.0, 0.0, 500.0), 0.0)
	await _checker.physics_frame
	await _checker.physics_frame
	var total_outside: int = game_state.get_total_remaining_hairs()
	await _press_and_release_use()
	_check(
		game_state.get_total_remaining_hairs() == total_outside
		and main.tool_message_label.text.contains("部屋の中で使う"),
		"部屋の外では吸引車を使っても毛が変わらず「部屋の中で使う」と出る",
	)
	await _checker._press_physical_key(KEY_1)
	_check(
		main.tools.get_selected_tool_id() == ToolCatalogScript.TOOL_HAND
		and not main.tools.is_in_driver_seat()
		and main.hand.get_hand_view().visible,
		"手に持ち替えると運転席から降りて、画面の手がまた見える",
	)


## 粘着シートを買い、0 キーで選んで部屋で使うと、床一面にシートが敷かれ、シートを 1 枚使い、床とカーペットの毛だけが減るか
func _verify_adhesive_sheet(main: Node3D, game_state: Node) -> void:
	var sheet: StringName = ToolCatalogScript.TOOL_ADHESIVE_SHEET
	_check(await _buy_in_shop(main, game_state, sheet), "道具を買う画面で建物を覆う粘着シートを買える")
	var room: MansionLayout.RoomDef = game_state.current_layout.rooms[1]
	await _stand_in_room(main, room)
	await _checker._press_physical_key(KEY_0)
	var owned: OwnedTool = game_state.find_owned_tool(sheet)
	var non_floor_before: int = _room_hairs_not_on(
		game_state, room.room_id, ToolRulesScript.SHEET_SURFACE_TYPES
	)
	var room_before: int = int(game_state.get_room_status(room.room_id)["hair_count"])
	await _press_and_release_use()
	var trace: Node3D = main.tools.get_trace()
	_check(
		main.tools.get_selected_tool_id() == sheet
		and owned.consumable_count == 2
		and trace != null and trace.name == "AdhesiveSheet"
		and absf(trace.global_position.x - room.center.x) < 0.01
		and int(game_state.get_room_status(room.room_id)["hair_count"]) < room_before
		and _room_hairs_not_on(game_state, room.room_id, ToolRulesScript.SHEET_SURFACE_TYPES)
		== non_floor_before,
		"0 キーで粘着シートを選んで使うと、部屋の床一面にシートが敷かれ、シートが 3 → %d 枚になり、床とカーペットの毛だけが減る"
		% owned.consumable_count,
	)
	owned.consumable_count = 0
	var total_empty: int = game_state.get_total_remaining_hairs()
	await _press_and_release_use()
	_check(
		game_state.get_total_remaining_hairs() == total_empty
		and main.tool_message_label.text.contains("シートが無い"),
		"シートが 0 枚では敷けず、「シートが無い」と出る",
	)
	await _checker._press_physical_key(KEY_1)


## アンドロイドを買うとキーで選ばずに働き、時間が進むと毛のいちばん多い部屋を掃除し、描く毛も同じだけ減り、姿が出るか
func _verify_android(main: Node3D, game_state: Node) -> void:
	_check(
		await _buy_in_shop(main, game_state, ToolCatalogScript.TOOL_ANDROID),
		"道具を買う画面でアンドロイドを買える",
	)
	var dirtiest: StringName = main.big_tools.dirtiest_room_id()
	var room_before: int = int(game_state.get_room_status(dirtiest)["hair_count"])
	var total_before: int = game_state.get_total_remaining_hairs()
	main.auto_advance_time = true
	await _checker.create_timer(BigToolSite.ANDROID_INTERVAL_SECONDS + 0.5).timeout
	main.auto_advance_time = false
	var removed: int = total_before - game_state.get_total_remaining_hairs()
	var root: Node3D = main.big_tools.get_models_root()
	_check(
		removed > 0
		and int(game_state.get_room_status(dirtiest)["hair_count"]) < room_before
		and main.mansion_world.get_hair_field().get_remaining_count()
		== game_state.get_total_remaining_hairs()
		and root != null and root.get_node_or_null("Android") != null,
		"アンドロイドは %.0f 秒たつと毛のいちばん多い部屋を掃除し (%d 本)、描く毛も同じ本数になり、屋敷に姿が出る"
		% [BigToolSite.ANDROID_INTERVAL_SECONDS, removed],
	)
	await _verify_android_releases_pull(main)


## 手で引いている毛の一部をアンドロイドが取ると、手は引くのをやめ、取られずに残った毛の見た目が元に戻るか。
## どの毛が取られるかは抽選のため、掃除する部屋の毛をすべて引いている (伸ばした見た目にした) 状態にして確かめる
func _verify_android_releases_pull(main: Node3D) -> void:
	var hair_field: Node3D = main.mansion_world.get_hair_field()
	var room_id: StringName = main.big_tools.dirtiest_room_id()
	var pulling: PackedInt32Array = PackedInt32Array()
	for surface_index: int in range(hair_field.get_surface_count()):
		if main.mansion_world.get_surface_def(surface_index).room_id != room_id:
			continue
		for slot: int in range(hair_field.get_surface_remaining_count(surface_index)):
			var hair_id: int = hair_field.get_hair_id_at_slot(surface_index, slot)
			pulling.append(hair_id)
			hair_field.set_hair_display_transform(
				hair_id, hair_field.get_hair_transform(hair_id).scaled_local(STRETCHED_SCALE)
			)
	main.hand._pulling_ids = pulling
	var cleaned: Dictionary = main.big_tools.step_android()
	var restored: bool = true
	var kept: int = 0
	for hair_id: int in pulling:
		if not hair_field.has_hair(hair_id):
			continue
		kept += 1
		if not hair_field._get_hair_display_transform(hair_id).is_equal_approx(
			hair_field.get_hair_transform(hair_id)
		):
			restored = false
	_check(
		int(cleaned.get("removed", 0)) > 0 and kept > 0 and restored
		and not main.hand.is_pulling(),
		"引いている毛の一部 (%d 本) をアンドロイドが取ると、手は引くのをやめ、残った %d 本の見た目が元に戻る"
		% [int(cleaned.get("removed", 0)), kept],
	)


## 加工機を道具を買う画面で並べて買い、時間が進むと在庫が加工され、買取業者に売ると毛のまま売るより多く入るか
func _verify_processing_and_selling(main: Node3D, game_state: Node) -> void:
	var progress: BuildingProgress = game_state.save_data.building_progress
	progress.hair_stocks = standard_stocks(STOCK_HAIRS_PER_COLOR)
	var raw_value: int = ProcessingRulesScript.stock_value(progress.hair_stocks)
	var bought: int = 0
	for _index: int in range(3):
		if await _buy_in_shop(main, game_state, ToolCatalogScript.TOOL_HAIR_PROCESSOR):
			bought += 1
	var root: Node3D = main.big_tools.get_models_root()
	_check(
		bought == 3 and root != null and root.get_node_or_null("HairProcessor2") != null,
		"道具を買う画面で毛の加工機を 3 台並べて買え、買取業者の横に 3 台並ぶ",
	)
	progress.elapsed_seconds = ProcessingRulesScript.PROCESS_INTERVAL_SECONDS - 0.01
	main.auto_advance_time = true
	await _checker.create_timer(0.3).timeout
	main.auto_advance_time = false
	_check(
		ProcessingRulesScript.stock_value(progress.hair_stocks) > raw_value,
		"プレイ中の時間が加工の区切り (10 秒) をまたぐと、手で時間を進めなくても加工機が加工する",
	)
	game_state.advance_time(ProcessingRulesScript.PROCESS_INTERVAL_SECONDS * 3.0)
	var processed_value: int = ProcessingRulesScript.stock_value(progress.hair_stocks)
	var has_doll: bool = false
	for stock: HairStock in progress.hair_stocks:
		if stock.form == HairStockScript.FORM_DOLL and stock.hair_color == SurfaceHairScript.COLOR_WHITE:
			has_doll = true
	_check(
		has_doll and processed_value > raw_value,
		"プレイ中に時間が進むと加工機 3 台が色ごとに加工し、白の人形ができて在庫の売値が上がる (%d → %d 円)"
		% [raw_value, processed_value],
	)
	main.player.set_spawn(main.mansion_world.get_trader_position() + Vector3(1.0, 0.0, -1.0), 0.0)
	await _checker.physics_frame
	await _checker.physics_frame
	main.open_tool_shop()
	await _checker.process_frame
	var label_has_products: bool = main.tool_shop_panel.get_money_label_text().contains("人形")
	var money_before: int = game_state.get_money()
	main.tool_shop_panel.get_sell_button().pressed.emit()
	await _checker.process_frame
	main.close_tool_shop()
	var earned: int = game_state.get_money() - money_before
	_check(
		label_has_products and earned == processed_value and earned > raw_value
		and progress.hair_stocks.is_empty(),
		"加工してから買取業者に売ると %d 円入り、同じ毛を毛のまま売る %d 円より多い (道具を買う画面に人形の個数が出る)"
		% [earned, raw_value],
	)


## ダンプカーを買うと、買取業者から離れていても道具を買う画面から呼んで在庫を運び出して売れるか
func _verify_dump_truck(main: Node3D, game_state: Node) -> void:
	_check(
		await _buy_in_shop(main, game_state, ToolCatalogScript.TOOL_DUMP_TRUCK),
		"道具を買う画面で毛を運ぶダンプカーを買える",
	)
	var progress: BuildingProgress = game_state.save_data.building_progress
	progress.hair_stocks = []
	main.open_tool_shop()
	await _checker.process_frame
	_check(
		main.tool_shop_panel.get_haul_button().visible
		and main.tool_shop_panel.get_haul_button().disabled,
		"在庫が空の時は、ダンプカーのボタンは出るが押せない",
	)
	main.close_tool_shop()
	await _checker.process_frame
	progress.hair_stocks = standard_stocks(STOCK_HAIRS_PER_COLOR)
	var stock_value: int = ProcessingRulesScript.stock_value(progress.hair_stocks)
	var rooms: Array = game_state.current_layout.rooms
	await _stand_in_room(main, rooms[rooms.size() - 1])
	main.open_tool_shop()
	await _checker.process_frame
	var haul_button: Button = main.tool_shop_panel.get_haul_button()
	var can_haul: bool = (
		not main.is_near_trader() and main.tool_shop_panel.get_sell_button().disabled
		and haul_button.visible and not haul_button.disabled
	)
	var money_before: int = game_state.get_money()
	haul_button.pressed.emit()
	await _checker.process_frame
	main.close_tool_shop()
	var root: Node3D = main.big_tools.get_models_root()
	_check(
		can_haul and game_state.get_money() == money_before + stock_value
		and progress.hair_stocks.is_empty()
		and main.get_pluck_popup_text().contains("ダンプカー")
		and root != null and root.get_node_or_null("DumpTruck") != null,
		"買取業者から離れていてもダンプカーのボタンで在庫 (%d 円分) を運び出して売れ、「ダンプカーで…運んだ」と出て、裏口の外に停まる"
		% stock_value,
	)


## 屋敷を組み直すと、大型の道具の姿 (加工機・ダンプカー・アンドロイド) が消え、運転席から降りるか
func _verify_rebuild_clears_big_tools(
	main: Node3D, game_state: Node, tuning: MansionTuning
) -> void:
	await _stand_in_room(main, game_state.current_layout.rooms[0])
	await _checker._press_physical_key(KEY_9)
	var seated: bool = main.tools.is_in_driver_seat()
	game_state.apply_tuning_and_rebuild(tuning, false)
	await _checker.process_frame
	var root: Node3D = main.big_tools.get_models_root()
	_check(
		seated and not main.tools.is_in_driver_seat()
		and root != null and root.get_child_count() == 0,
		"運転席に座ったまま屋敷を組み直すと運転席から降り、大型の道具の姿が消える",
	)


## 部屋 room_id の毛のうち、表面の種類が surface_types に入らない面の本数を返す
func _room_hairs_not_on(
	game_state: Node, room_id: StringName, surface_types: Array[StringName]
) -> int:
	var total: int = 0
	for surface_def: MansionLayout.SurfaceDef in game_state.current_layout.surfaces:
		if surface_def.room_id != room_id or surface_types.has(surface_def.surface_type):
			continue
		var surface: SurfaceHair = game_state.save_data.building_progress.find_surface_hair(
			surface_def.surface_id
		)
		if surface != null:
			total += surface.total_count()
	return total


## 白・黒・三毛の毛のままを hairs_per_color 本ずつ持つ在庫を作る (大型の道具の撮影も使う)
static func standard_stocks(hairs_per_color: int) -> Array[HairStock]:
	var stocks: Array[HairStock] = []
	for color_id: StringName in SurfaceHairScript.STANDARD_COLORS:
		var stock: HairStock = HairStockScript.new()
		stock.hair_color = color_id
		stock.count = hairs_per_color
		stocks.append(stock)
	return stocks


## つまむ入力を押して離す (選んでいる道具を 1 回使う)
func _press_and_release_use() -> void:
	await IntegrationToolsScript.press_and_release_use(_checker)

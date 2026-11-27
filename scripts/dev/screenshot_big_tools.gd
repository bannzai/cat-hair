extends RefCounted
## 大型の道具の撮影 (scripts/dev/screenshot.gd から呼ぶ)。業務用の吸引車の運転席からの眺め、建物を覆う粘着シートを敷いた部屋、
## アンドロイドが掃除した部屋、買取業者の横に並べた毛の加工機、裏口の外に停めた毛を運ぶダンプカー、
## 加工品とダンプカーのボタンが出た道具を買う画面を撮る。

## 状態管理 autoload スクリプト (買う物の種類の定数を使う)
const GameStateScript := preload("res://scripts/state/game_state.gd")
## 大型の道具の入力統合テスト (色ごとの在庫の作り方を使う)
const IntegrationBigToolsScript := preload("res://scripts/dev/integration_big_tools.gd")
## 見た目の試作の部屋 (位置からいる部屋を求める)
const LookPrototypeRoomScript := preload("res://scripts/look/look_prototype_room.gd")
## 道具の定義
const ToolCatalogScript := preload("res://scripts/tools/tool_catalog.gd")
## 加工機が 1 回加工する間隔を使う
const ProcessingRulesScript := preload("res://scripts/economy/processing_rules.gd")
## 撮る絵を毎回同じにする、取りこぼしの抽選の乱数のシード
const RNG_SEED: int = 20261127
## 撮る前に持たせる在庫 (色ごとの毛のままの本数)。加工機 3 台で色ごとの人形・フェルト・毛玉ができる本数
const STOCK_HAIRS_PER_COLOR: int = 1240
## アンドロイドを撮る時の、アンドロイドからカメラまでの距離 (m)。背の高さ 1.6 m の全身が縦の画角に収まる距離
const ANDROID_VIEW_DISTANCE_M: float = 2.6
## アンドロイドから離れる距離の上限を、部屋の短い辺に対する割合で表した値。アンドロイドは中央か中央から 4 分の 1 寄った所に
## 立つため、短い辺の 0.45 倍までなら部屋の中に収まる
const ANDROID_VIEW_ROOM_RATIO: float = 0.45
## 引いている毛に見せる伸ばした見た目の倍率。毛の向き (y) を 2 倍にして、元の見た目と transform で見分けられる値
const STRETCHED_SCALE: Vector3 = Vector3(1.0, 2.0, 1.0)
## 部屋の中で見下ろす角度 (rad。床に敷いたシートと残った毛が画面の下半分に入る角度)
const ROOM_PITCH: float = -0.5


## 大型の道具の場面を順に撮る。shooter は screenshot.gd の SceneTree (_capture と _capture_frozen を使う)。
## 撮れたら空文字、失敗したら理由を返す
static func capture_all(shooter: SceneTree, main: Node3D) -> String:
	var game_state: Node = main.get_game_state()
	game_state.save_data.building_progress.money = 1000000
	for tool_id: StringName in [
		ToolCatalogScript.TOOL_SUCTION_TRUCK,
		ToolCatalogScript.TOOL_ADHESIVE_SHEET,
		ToolCatalogScript.TOOL_ANDROID,
		ToolCatalogScript.TOOL_DUMP_TRUCK,
	]:
		if not game_state.purchase(GameStateScript.PURCHASE_TOOL, tool_id):
			return "%s を買えない" % ToolCatalogScript.find_tool(tool_id)["name"]
	main.tools.set_rng_seed(RNG_SEED)
	main.big_tools.set_rng_seed(RNG_SEED)
	var rooms: Array = game_state.current_layout.rooms
	var room: MansionLayout.RoomDef = rooms[rooms.size() - 1]
	main.player.set_spawn(room.center + Vector3(0.0, 0.0, room.size.z * 0.35), 0.0)
	await shooter.physics_frame
	main.player.look_at_point(room.center + Vector3(0.0, 0.3, 0.0))
	if (
		not main.tools.select_tool(ToolCatalogScript.TOOL_SUCTION_TRUCK)
		or not main.tools.is_in_driver_seat()
	):
		return "吸引車を選んでも運転席にならない"
	var truck_result: Dictionary = main.tools.use_selected_tool()
	if not bool(truck_result["used"]) or int(truck_result["removed"]) <= 0:
		return "吸引車で部屋の毛が取れない (%s)" % str(truck_result)
	if not await shooter._capture_frozen(main, "tmp/screenshot-suction-truck.png"):
		return "吸引車の運転席を保存できない"
	if not main.tools.select_tool(ToolCatalogScript.TOOL_ADHESIVE_SHEET):
		return "粘着シートを選べない"
	shooter._set_pitch(main.player, ROOM_PITCH)
	var sheet_result: Dictionary = main.tools.use_selected_tool()
	if not bool(sheet_result["used"]) or main.tools.get_trace() == null:
		return "粘着シートを敷けない (%s)" % str(sheet_result)
	if not await shooter._capture_frozen(main, "tmp/screenshot-adhesive-sheet.png"):
		return "粘着シートを敷いた部屋を保存できない"
	main.tools.select_tool(ToolCatalogScript.TOOL_HAND)
	var pulling: PackedInt32Array = _stretch_room_hairs_as_pulled(main)
	var android_result: Dictionary = main.big_tools.step_android()
	if int(android_result.get("removed", 0)) <= 0:
		return "アンドロイドが掃除しない (%s)" % str(android_result)
	var not_restored: int = _count_stretched_left(main, pulling)
	if main.hand.is_pulling() or not_restored > 0:
		return (
			"アンドロイドが引いている毛を取った後、手が引いたまま (%s) か、伸びた見た目のまま残った毛がある (%d 本)"
			% [main.hand.is_pulling(), not_restored]
		)
	var android: Node3D = main.big_tools.get_models_root().get_node_or_null("Android")
	if android == null:
		return "アンドロイドの姿が無い"
	# 全身が入るように、アンドロイドから部屋の中央の向きへ離れた所 (中央に立つ時は南へ) から腰の高さを見る。
	# 部屋の外へ出ないよう、離れる距離は部屋の幅と奥行きの短い方の ANDROID_VIEW_ROOM_RATIO 倍までにする
	var android_room: MansionLayout.RoomDef = LookPrototypeRoomScript.room_at(
		game_state.current_layout, android.global_position
	)
	var away: Vector3 = Vector3(
		android_room.center.x - android.global_position.x,
		0.0,
		android_room.center.z - android.global_position.z,
	)
	main.player.set_spawn(
		android.global_position
		+ (away.normalized() if away.length() > 0.1 else Vector3.BACK)
		* minf(
			ANDROID_VIEW_DISTANCE_M,
			minf(android_room.size.x, android_room.size.z) * ANDROID_VIEW_ROOM_RATIO
		),
		0.0,
	)
	await shooter.physics_frame
	main.player.look_at_point(android.global_position + Vector3(0.0, 0.8, 0.0))
	if not await shooter._capture_frozen(main, "tmp/screenshot-android.png"):
		return "アンドロイドを保存できない"
	return await _capture_processing(shooter, main, game_state)


## アンドロイドが次に掃除する部屋の毛をすべて、手で引いている状態にして伸ばした見た目にし、引いている毛の ID を返す。
## 見た目の transform は描画付きの実行でしか読めないため、headless の integration ではなく撮影でこの確認をする
## (CI の run 45871183473 で、headless では読めず落ちた)。どの毛が取られるかは抽選のため部屋の毛をすべて引く
static func _stretch_room_hairs_as_pulled(main: Node3D) -> PackedInt32Array:
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
	return pulling


## pulling の毛のうち、残っているのに見た目が元の transform に戻っていない毛の本数を返す
static func _count_stretched_left(main: Node3D, pulling: PackedInt32Array) -> int:
	var hair_field: Node3D = main.mansion_world.get_hair_field()
	var count: int = 0
	for hair_id: int in pulling:
		if not hair_field.has_hair(hair_id):
			continue
		var multimesh: MultiMesh = hair_field._buckets[hair_field._id_to_surface[hair_id]]["multimesh"]
		if not multimesh.get_instance_transform(hair_field._id_to_slot[hair_id]).is_equal_approx(
			hair_field.get_hair_transform(hair_id)
		):
			count += 1
	return count


## 加工機 3 台を買取業者の横に並べて在庫を加工した所と、裏口の外のダンプカーと、加工品が出た道具を買う画面を撮る
static func _capture_processing(shooter: SceneTree, main: Node3D, game_state: Node) -> String:
	for _index: int in range(3):
		if not game_state.purchase(GameStateScript.PURCHASE_TOOL, ToolCatalogScript.TOOL_HAIR_PROCESSOR):
			return "毛の加工機を買えない"
	game_state.save_data.building_progress.hair_stocks = (
		IntegrationBigToolsScript.standard_stocks(STOCK_HAIRS_PER_COLOR)
	)
	game_state.advance_time(ProcessingRulesScript.PROCESS_INTERVAL_SECONDS * 6.0)
	var trader: Vector3 = main.mansion_world.get_trader_position()
	main.player.set_spawn(trader + Vector3(1.6, 0.0, -2.2), 0.0)
	await shooter.physics_frame
	main.player.look_at_point(trader + Vector3(1.6, 0.4, -0.2))
	if not await shooter._capture_frozen(main, "tmp/screenshot-hair-processor.png"):
		return "毛の加工機を保存できない"
	main.player.set_spawn(trader + Vector3(2.0, 0.0, 8.5), 0.0)
	await shooter.physics_frame
	main.player.look_at_point(trader + Vector3(2.0, 1.0, 3.2))
	if not await shooter._capture_frozen(main, "tmp/screenshot-dump-truck.png"):
		return "ダンプカーを保存できない"
	main.open_tool_shop()
	# 道具の行の並びが決まってから、加工機とダンプカーの行が見える所まで送る
	await shooter.process_frame
	await shooter.process_frame
	main.tool_shop_panel.scroll_to_tool(ToolCatalogScript.TOOL_DUMP_TRUCK)
	var shop_ok: bool = await shooter._capture("tmp/screenshot-tool-shop-big-tools.png")
	main.close_tool_shop()
	return "" if shop_ok else "加工品とダンプカーのボタンが出た道具を買う画面を保存できない"


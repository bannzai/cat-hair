extends SceneTree
## 実際の描画で代表画面を撮影する (headless では描画されないため、Makefile の screenshot target が
## --headless なしで起動する)。撮影した PNG は tmp/screenshot-<名前>.png に保存し、失敗したら quit(1) で終わる。
## 全部の撮影を終えたら「screenshot OK」の行を出して quit(0) する (Makefile はこの行と PNG の存在で判定する)。
## 画面や状態を増やす時は _capture_scenes() に撮影を足す。

## AudioManager / GameState 準備・後始末を借りる検証の土台
const HeadlessCheck := preload("res://scripts/dev/headless_check.gd")
## 撮影するメインシーン
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
## メインシーンのノードパス定数参照用
const MainScript := preload("res://scripts/main.gd")
## 音声管理ノード (AUDIO_RELEASE_TIME_SEC の単一の正と型解決用)
const AudioManagerScript := preload("res://scripts/audio/audio_manager.gd")
## JSON 保存ストレージスクリプト
const SaveStorageScript := preload("res://scripts/state/save_storage.gd")
## 目線を床の毛へ向ける手順
const HandAim := preload("res://scripts/dev/hand_aim.gd")
## 状態管理 autoload スクリプト (買う物の種類の定数を使う)
const GameStateScript := preload("res://scripts/state/game_state.gd")
## 手に持って使う道具の定義
const ToolCatalogScript := preload("res://scripts/tools/tool_catalog.gd")
## 大型の道具の撮影
const ScreenshotBigTools := preload("res://scripts/dev/screenshot_big_tools.gd")
## 撮影で、見たい所との間に家具を挟まずに立つ所を選ぶ手順
const ViewPointScript := preload("res://scripts/dev/view_point.gd")
## 掃除ロボットの部屋の探し方 (猫がいる部屋を引く)
const RobotRulesScript := preload("res://scripts/automation/robot_rules.gd")
## 猫が今立ち止まっている所の添字
const RouteClockScript := preload("res://scripts/automation/route_clock.gd")
## 道具をかけた跡を撮る時の取りこぼしの抽選の乱数のシード (撮る絵を毎回同じにする)
const TOOL_TRACE_RNG_SEED: int = 20261126
## 道具をかけた跡を撮る所に要る、粘着ローラーの半径の中の毛の本数 (取りこぼした毛が跡の中に見える本数)
const TOOL_TRACE_MIN_HAIRS: int = 6
## 引いている途中を撮る時の進み具合 (毛が伸びて手が閉じかけた所)
const PULL_SNAPSHOT_PROGRESS: float = 0.7
## 掃除ロボットが毛を取った跡を撮る前に時計を進める刻みの秒数 (掃除ロボットの位置に合わせて毛が消えるよう、
## 部屋の中の輪を 1 周する 9 秒より十分細かくする)
const ROBOT_TRACE_STEP_SECONDS: float = 0.25
## 掃除ロボットが毛を取った跡を撮る前に時計を進める回数 (0.25 秒 × 60 = 15 秒。部屋に留まる 20 秒の内に収まり、
## 輪を 1 周以上走った跡が残る長さ)
const ROBOT_TRACE_STEPS: int = 60
## 掃除ロボットを撮る時に、掃除ロボットから立つ位置までの水平距離 (m。掃除ロボットと周りの床の毛が画面に収まる距離)
const ROBOT_VIEW_DISTANCE_M: float = 1.3
## 猫を撮る時に、猫から立つ位置までの水平距離 (m。猫の体と名札が画面に収まる距離)
const CAT_VIEW_DISTANCE_M: float = 1.4

## fps と 1 フレームの時間の表示を出してから撮るまで待つ実時間 (ms)。fps は 1 秒ごとにしか更新されない
## (Godot の Performance.TIME_FPS の説明) ため、1 回目の更新と、その後の表示の描き直し
## (PerfOverlay.REFRESH_INTERVAL_SECONDS ごと) が済む長さ
const PERF_OVERLAY_WAIT_MSEC: int = 1500
## 開発者向け調整値データ型スクリプト (見た目の試作の撮影で毛の本数を変える)
const MansionTuningScript := preload("res://scripts/data/mansion_tuning.gd")

## screenshot 専用のセーブパス
const TEST_SAVE_PATH: String = "user://screenshot_save_data.json"
## 見た目の試作を撮る時の屋敷全体の毛の本数。既定の 4 部屋で 1 部屋 3 万本前後になり、量の多さが一目で分かる。
## 屋敷は全部の毛を 1 本ずつ描くため (#9)、CI の lavapipe で 10 万本が 187 ms/frame (ADR 0002 の実測) を大きく
## 超えない本数にした
const LOOK_HAIR_COUNT: int = 120000
## 部屋に入った直後と自動化の絵で見下ろす角度 (rad)。床と家具の上の毛が画面の下半分を占める角度
const LOOK_OVERVIEW_PITCH: float = -0.45


## tree の準備が終わってから _run() を始める (シーンの追加は _initialize() の後でないとできない)
func _initialize() -> void:
	_run.call_deferred()


## フレームを進めながら撮影するため、同じ実行中に重ねて呼び出さない
func _run() -> void:
	var settings_path: String = ProjectSettings.globalize_path(
		"res://tmp/screenshot-audio-settings.cfg"
	)
	var audio_handle: Dictionary = HeadlessCheck.prepare_audio_manager(self, settings_path)

	var ok: bool = await _capture_scenes()
	(audio_handle["manager"] as AudioManagerScript).stop_all()
	await HeadlessCheck.wait_audio_release(self)
	HeadlessCheck.cleanup_audio_manager(self, audio_handle, settings_path)
	if ok:
		print("screenshot OK")
		quit(0)
	else:
		quit(1)


## 撮影する画面の並び。失敗した撮影は false を返し呼び出し側で後始末して quit(1) する
func _capture_scenes() -> bool:
	SaveStorageScript.delete_save_file(TEST_SAVE_PATH)
	var state_handle: Dictionary = HeadlessCheck.acquire_game_state(root, TEST_SAVE_PATH)
	var game_state: Node = state_handle["node"]
	var created_state: bool = state_handle["created"]

	var main: Node3D = MAIN_SCENE.instantiate()
	main.auto_advance_automation = false
	root.add_child(main)
	current_scene = main

	# 最初の撮影だけ、フォントの読み込みと最初の描画を時間で待つ。0.3 秒は bannzai/goki-hunter の撮影から引き継いだ値で、
	# CI の llvmpipe でこの画面が描画し終わることを PR #1 の artifact で確かめた (下限は測っていない)
	await create_timer(0.3).timeout
	if not await _capture("tmp/screenshot-title.png"):
		_cleanup(main, game_state, created_state)
		return false

	# 音声設定画面を開いた状態
	var settings_button: Button = main.get_node_or_null(MainScript.SETTINGS_BUTTON_PATH)
	if settings_button != null:
		settings_button.pressed.emit()
	if not await _capture("tmp/screenshot-settings.png"):
		_cleanup(main, game_state, created_state)
		return false

	# 屋敷の中の一人称プレイ画面・床の毛を引いている途中・抜いた直後・図鑑・開発者向け調整画面
	var mansion_error: String = await _capture_mansion_scenes(main)
	if not mansion_error.is_empty():
		push_error("screenshot FAIL: " + mansion_error)
		_cleanup(main, game_state, created_state)
		return false

	# 描画付き環境 (非 headless) でのマウス捕捉・捕捉中視点移動・Esc 解放・F1 解放を検証し、
	# 見た目の試作 (issue #19) の 3 つの状態を撮る (マウスの検証は既定の毛の本数で行うため、本数を増やす撮影を後にする)
	var ok: bool = await _verify_windowed_mouse_capture(main)
	if ok:
		ok = await _capture_look_prototype(main, game_state)
	_cleanup(main, game_state, created_state)
	return ok


## 見た目の試作の部屋を、部屋に入った直後・毛をつまんで引いている途中・自動化が進んだ後の 3 つの状態で撮る。
## 毛の本数を LOOK_HAIR_COUNT にして屋敷を作り直す (保存はしない)。撮れたら true
func _capture_look_prototype(main: Node3D, game_state: Node) -> bool:
	# マウスの検証が開いた開発者画面を閉じ、屋敷を歩いている時の画面にする
	main.close_dev_panel()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	var tuning: MansionTuning = MansionTuningScript.new()
	tuning.hair_count = LOOK_HAIR_COUNT
	game_state.apply_tuning_and_rebuild(tuning, false)
	var layout: MansionLayout = game_state.current_layout
	var player: FirstPersonPlayer = main.get_node("Player")
	var look_room: LookPrototypeRoom = main.look_room

	player.set_spawn(layout.spawn_position, layout.spawn_yaw)
	await physics_frame
	set_pitch(player, LOOK_OVERVIEW_PITCH)
	if not await _capture("tmp/screenshot-look-enter.png"):
		return false

	# 手で毛を取る操作 (#9) の本物の引きで、試作の部屋の床の毛を引いている途中を撮る
	var hand: HandController = main.hand
	if await HandAim.aim_at_floor_hair(self, main) < 0 or not hand.begin_pull():
		push_error("look prototype FAIL: 試作の部屋の床の毛をつまめない")
		return false
	hand.advance_pull(hand.get_pull_duration() * PULL_SNAPSHOT_PROGRESS)
	await process_frame
	if not look_room.is_prototype_active():
		push_error("look prototype FAIL: つまんだ毛が試作の部屋の外にある")
		hand.cancel_pull()
		return false
	var pinch_ok: bool = await _capture_frozen(main, "tmp/screenshot-look-pinch.png")
	hand.cancel_pull()
	if not pinch_ok:
		return false

	player.set_spawn(layout.spawn_position, layout.spawn_yaw)
	await physics_frame
	set_pitch(player, LOOK_OVERVIEW_PITCH)
	if look_room.show_automation_props(main.mansion_world.get_hair_field()) <= 0:
		push_error("look prototype FAIL: 掃除ロボットの帯で毛が 1 本も消えていない")
		return false
	return await _capture("tmp/screenshot-look-automation.png")


## プレイヤーの見下ろす角度を pitch (rad) にする
static func set_pitch(player: FirstPersonPlayer, pitch: float) -> void:
	player.apply_look_delta(Vector2(0.0, (player.get_pitch() - pitch) / player.mouse_sensitivity))


## 非 headless 描画環境で左クリック捕捉 → 捕捉中マウス移動 → Esc 解放 → 開発者画面解放を検証する
func _verify_windowed_mouse_capture(main: Node3D) -> bool:
	main.close_dev_panel()
	await process_frame

	var player: FirstPersonPlayer = main.get_node("Player")
	player.allow_uncaptured_look = false
	var click_event: InputEventMouseButton = InputEventMouseButton.new()
	click_event.button_index = MOUSE_BUTTON_LEFT
	click_event.pressed = true
	Input.parse_input_event(click_event)
	await process_frame

	if not await _verify_captured_and_capture_hint(main):
		return false

	var yaw_before: float = player.rotation.y
	var motion_event: InputEventMouseMotion = InputEventMouseMotion.new()
	motion_event.relative = Vector2(36.0, -18.0)
	Input.parse_input_event(motion_event)
	await process_frame

	if is_equal_approx(player.rotation.y, yaw_before):
		push_error("windowed mouse check FAIL: マウス捕捉中の視点移動でヨー角が変わらない")
		return false

	var esc_event: InputEventKey = InputEventKey.new()
	esc_event.physical_keycode = KEY_ESCAPE
	esc_event.pressed = true
	Input.parse_input_event(esc_event)
	await process_frame

	if Input.get_mouse_mode() != Input.MOUSE_MODE_VISIBLE:
		push_error("windowed mouse check FAIL: Esc キーで MOUSE_MODE_VISIBLE に戻らない")
		return false

	# 再度捕捉した状態から開発者調整画面を開くと MOUSE_MODE_VISIBLE に解放されることも検証
	Input.parse_input_event(click_event)
	await process_frame
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		push_error("windowed mouse check FAIL: 再クリックで MOUSE_MODE_CAPTURED にならない")
		return false
	main.open_dev_panel()
	await process_frame
	if Input.get_mouse_mode() != Input.MOUSE_MODE_VISIBLE:
		push_error("windowed mouse check FAIL: 開発者画面を開いても MOUSE_MODE_VISIBLE に戻らない")
		return false
	return true


## 左クリックでマウスが取られたことを確かめ、取られている間の左下のマウスを放すキーの案内を撮る
## (PlayGuideHud が毎フレームマウスの状態に合わせるため、メインシーンの処理を止めずに撮る)。どれもできたら true
func _verify_captured_and_capture_hint(main: Node3D) -> bool:
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		push_error("windowed mouse check FAIL: 左クリックで MOUSE_MODE_CAPTURED にならない")
		return false
	if not await _capture("tmp/screenshot-mouse-captured.png"):
		return false
	if main.play_guide.get_mouse_hint_text() != PlayGuideHud.mouse_hint_text(true):
		push_error("windowed mouse check FAIL: マウスを取られている間に Esc で放す案内が出ない")
		return false
	return true


## 操作の案内の一覧を H キーと同じ切り替えで閉じた画面と、もう一度開いた (後から見直す) 画面を撮る。
## 撮れたら空文字、失敗したら理由を返す
func _capture_guide_toggle(main: Node3D) -> String:
	main.play_guide.toggle_controls_guide()
	if not await _capture("tmp/screenshot-guide-closed.png"):
		return "操作の案内を閉じた画面を保存できない"
	main.play_guide.toggle_controls_guide()
	if not await _capture("tmp/screenshot-guide-reopened.png"):
		return "操作の案内を開き直した画面を保存できない"
	return ""


## 屋敷に入った一人称プレイ画面 (部屋・家具・布・毛・画面の手・照準・残り本数と在庫・遊び始めの操作の案内の HUD)、
## 操作の案内の開閉、毛を引く場面、図鑑、開発者向け調整画面を順に撮る。撮れたら空文字、失敗したら理由を返す
func _capture_mansion_scenes(main: Node3D) -> String:
	main.enter_mansion()
	if not await _capture("tmp/screenshot-mansion.png"):
		return "屋敷の画面を保存できない"
	var capture_error: String = await _capture_perf_overlay(main)
	if capture_error.is_empty():
		capture_error = await _capture_guide_toggle(main)
	if capture_error.is_empty():
		capture_error = await _capture_pluck(main)
	if not capture_error.is_empty():
		return capture_error
	main.open_hair_book()
	var book_ok: bool = await _capture("tmp/screenshot-hair-book.png")
	main.close_hair_book()
	if not book_ok:
		return "図鑑を保存できない"
	var tool_error: String = await _capture_tool_scenes(main)
	if not tool_error.is_empty():
		return tool_error
	main.open_dev_panel()
	return "" if await _capture("tmp/screenshot-dev-panel.png") else "開発者向け調整画面を保存できない"


## F3 で fps と 1 フレームの時間の表示を出した屋敷の画面を撮り、表示を隠して戻す。撮れたら空文字、失敗したら理由を返す
func _capture_perf_overlay(main: Node3D) -> String:
	var key_event: InputEventKey = InputEventKey.new()
	key_event.physical_keycode = MainScript.TOGGLE_PERF_KEY
	key_event.pressed = true
	Input.parse_input_event(key_event)
	await process_frame
	var release_event: InputEventKey = key_event.duplicate()
	release_event.pressed = false
	Input.parse_input_event(release_event)
	if not main.perf_overlay.visible:
		return "F3 で fps と 1 フレームの時間の表示が出ない"
	var deadline_msec: int = Time.get_ticks_msec() + PERF_OVERLAY_WAIT_MSEC
	while Time.get_ticks_msec() < deadline_msec:
		await process_frame
	var ok: bool = await _capture("tmp/screenshot-perf-overlay.png")
	print("screenshot perf overlay: %s" % main.perf_overlay.text)
	main.perf_overlay.set_overlay_visible(false)
	return "" if ok else "fps と 1 フレームの時間の表示を保存できない"


## 道具 (手に持つ道具)・猫と掃除ロボット・大型の道具の場面を順に撮る。撮れたら空文字、失敗したら最初の失敗の理由を返す
func _capture_tool_scenes(main: Node3D) -> String:
	var tool_error: String = await _capture_tools(main)
	if not tool_error.is_empty():
		return tool_error
	var automation_error: String = await _capture_automation(main)
	if not automation_error.is_empty():
		return automation_error
	return await ScreenshotBigTools.capture_all(self, main)


## 床の毛を狙って引いている途中 (伸びた毛と閉じかけた手) と、抜いた直後 (「+1 本」) を撮る。
## 引いている途中と「+1 本」が撮る間に進んだり消えたりしないよう、撮る間はメインシーンの処理を止める。
## 撮れたら空文字、失敗したら理由を返す
func _capture_pluck(main: Node3D) -> String:
	var hand: HandController = main.hand
	if await HandAim.aim_at_floor_hair(self, main) < 0:
		return "床の毛を狙える位置が見つからない"
	if not hand.begin_pull():
		return "狙った床の毛をつまめない"
	hand.advance_pull(hand.get_pull_duration() * PULL_SNAPSHOT_PROGRESS)
	if not await _capture_frozen(main, "tmp/screenshot-pluck.png"):
		return "引いている途中を保存できない"
	if hand.advance_pull(hand.get_pull_duration()) < 1:
		return "引き終えても毛が抜けない"
	if not await _capture_frozen(main, "tmp/screenshot-plucked.png"):
		return "抜いた直後を保存できない"
	# 途中で離して抜けなかった時の理由の表示 (照準の下)。押す入力の代わりに、離した時と同じ知らせを出す
	hand.pull_failed.emit(HandController.REASON_RELEASED)
	var failed_ok: bool = await _capture_frozen(main, "tmp/screenshot-pluck-failed.png")
	main.tool_message_label.text = ""
	return "" if failed_ok else "抜けなかった理由の表示を保存できない"


## 粘着ローラーを床の毛にかけた直後 (跡の円盤・取りこぼした毛・取りこぼしの割合・道具の並び・部屋のゲージ) と、
## 道具を買う画面を撮る。撮れたら空文字、失敗したら理由を返す
func _capture_tools(main: Node3D) -> String:
	var game_state: Node = main.get_game_state()
	var roller: StringName = ToolCatalogScript.TOOL_LINT_ROLLER
	# 手に持つ 8 つの道具を全部持った時の右下の道具の枠の並びも同じ 1 枚で確かめる (大型の道具は後で撮る)。
	# 所持金は 7 つの道具の値段の合計に足りる額で、HUD に 5 桁の所持金が出る見え方も撮れる額にする
	game_state.save_data.building_progress.money = 100000
	for tool_def: Dictionary in ToolCatalogScript.hand_held_tools():
		if tool_def["id"] != ToolCatalogScript.TOOL_HAND:
			game_state.purchase(GameStateScript.PURCHASE_TOOL, tool_def["id"])
	if game_state.find_owned_tool(roller) == null:
		return "粘着ローラーを買えない"
	if not main.tools.select_tool(roller):
		return "粘着ローラーを選べない"
	main.tools.set_rng_seed(TOOL_TRACE_RNG_SEED)
	if (
		await HandAim.aim_at_floor_hairs(
			self, main, float(ToolCatalogScript.find_tool(roller)["radius_m"]), TOOL_TRACE_MIN_HAIRS
		)
		< 0
	):
		return "粘着ローラーをかける床の毛を狙える位置が見つからない"
	var result: Dictionary = main.tools.use_selected_tool()
	if not bool(result["used"]) or int(result["removed"]) <= 0 or int(result["missed"]) <= 0:
		return (
			"粘着ローラーで取れた毛と取りこぼした毛の両方が出ない (%s)" % str(result)
		)
	if not await _capture_frozen(main, "tmp/screenshot-tool-trace.png"):
		return "道具をかけた跡を保存できない"
	return await _capture_trader_and_shop(main)


## 裏口の買取業者 (人型と札の字) と、その近くで開いた道具を買う画面 (毛を売るボタンが押せる) を撮る。
## 撮れたら空文字、失敗したら理由を返す
func _capture_trader_and_shop(main: Node3D) -> String:
	var trader: Vector3 = main.mansion_world.get_trader_position()
	# 買取業者に毛を売れる距離 (main.TRADER_RANGE_M) の内側に立ち、続けて撮る道具を買う画面で売るボタンが押せるようにする
	main.player.set_spawn(trader + Vector3(1.2, 0.0, -1.3), 0.0)
	await physics_frame
	main.player.look_at_point(trader + Vector3(0.0, 1.2, 0.0))
	if not main.is_near_trader():
		return "撮る位置が買取業者に毛を売れる距離の外にある"
	if not await _capture_frozen(main, "tmp/screenshot-trader.png"):
		return "買取業者を保存できない"
	main.open_tool_shop()
	var shop_ok: bool = await _capture("tmp/screenshot-tool-shop.png")
	main.close_tool_shop()
	return "" if shop_ok else "道具を買う画面を保存できない"


## 掃除ロボットの回る順を決める画面 (2 台を買い、1 台目に部屋を 2 つ並べた所)、掃除ロボットが部屋を走って毛を取った跡、
## 猫が部屋に立ち止まっている所を撮る。猫と掃除ロボットの時計は撮る前に進める。撮れたら空文字、失敗したら理由を返す
func _capture_automation(main: Node3D) -> String:
	var game_state: Node = main.get_game_state()
	var automation: RefCounted = game_state.automation
	var layout: MansionLayout = game_state.current_layout
	var room: MansionLayout.RoomDef = layout.rooms[0]
	for _robot: int in range(2):
		if not automation.buy_robot(room.room_id):
			return "掃除ロボットを買えない"
	var route_ids: Array[StringName] = [room.room_id, layout.rooms[1].room_id]
	if not automation.set_robot_route(0, route_ids):
		return "掃除ロボットの回る順を決められない"
	main.open_robot_route()
	var panel_ok: bool = await _capture("tmp/screenshot-robot-route.png")
	main.close_robot_route()
	if not panel_ok:
		return "掃除ロボットの回る順の画面を保存できない"

	# 2 台目 (最初の部屋だけを回る) が部屋を走りながら毛を取る跡が残るよう、時計を細かく刻んで進める
	for _step: int in range(ROBOT_TRACE_STEPS):
		automation.advance(ROBOT_TRACE_STEP_SECONDS)
	await process_frame
	# 前の撮影の道具の結果の文字を消し、掃除ロボットを部屋の中心の側から見下ろす (家具を間に挟まない)
	main.tool_message_label.text = ""
	var robot_node: Node3D = main.automation.get_robot_node(1)
	main.player.set_spawn(
		ViewPointScript.clear_spot(
			layout, room, robot_node.position, ROBOT_VIEW_DISTANCE_M,
			room.center - robot_node.position
		),
		0.0,
	)
	await physics_frame
	main.player.look_at_point(robot_node.position)
	if not await _capture_frozen(main, "tmp/screenshot-robot-room.png"):
		return "掃除ロボットが動いている部屋を保存できない"

	var cat_route: Dictionary = automation.get_cat_routes()[0]
	var cat: Node3D = main.automation.get_cat_node(cat_route["cat_id"])
	var cat_room: MansionLayout.RoomDef = RobotRulesScript.find_room(
		layout,
		cat_route["stops"][RouteClockScript.stop_index_at(cat_route, automation.get_seconds())][
			"room_id"
		],
	)
	main.player.set_spawn(
		ViewPointScript.clear_spot(
			layout, cat_room, cat.global_position, CAT_VIEW_DISTANCE_M,
			cat_room.center - cat.global_position
		),
		0.0,
	)
	await physics_frame
	main.player.look_at_point(cat.global_position)
	return (
		"" if await _capture_frozen(main, "tmp/screenshot-cat-room.png")
		else "猫がいる部屋を保存できない"
	)


## メインシーンの処理を止めたまま現在の画面を path に保存する。保存できたら true
func _capture_frozen(main: Node3D, path: String) -> bool:
	main.process_mode = Node.PROCESS_MODE_DISABLED
	var ok: bool = await _capture(path)
	main.process_mode = Node.PROCESS_MODE_INHERIT
	return ok


## 撮影に使ったメインシーン・自前生成 GameState・一時セーブファイルを片付ける
func _cleanup(main: Node3D, game_state: Node, created_state: bool) -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if current_scene == main:
		current_scene = null
	if is_instance_valid(main) and main.get_parent() != null:
		main.get_parent().remove_child(main)
		main.free()
	if created_state and is_instance_valid(game_state) and game_state.get_parent() != null:
		game_state.get_parent().remove_child(game_state)
		game_state.free()
	SaveStorageScript.delete_save_file(TEST_SAVE_PATH)


## フレームを数フレーム進めて描画を安定させてから、現在の画面を path に保存する。保存できたら true
func _capture(path: String) -> bool:
	# 4 フレームは bannzai/goki-hunter の撮影から引き継いだ値 (レイアウトの確定と描画の反映に数フレームかかるため、
	# 1 フレームでは足りない。下限は測っていない)。Makefile の SCRIPT_FRAME_LIMIT の見積もりはこの値を前提にしている
	for _i: int in range(4):
		await process_frame
	var status: Error = root.get_viewport().get_texture().get_image().save_png(path)
	if status != OK:
		push_error("スクリーンショット保存失敗: %s (%s)" % [path, error_string(status)])
		return false
	print("screenshot: " + path)
	return true

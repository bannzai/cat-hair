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
## 道具をかけた跡を撮る時の取りこぼしの抽選の乱数のシード (撮る絵を毎回同じにする)
const TOOL_TRACE_RNG_SEED: int = 20261126
## 道具をかけた跡を撮る所に要る、粘着ローラーの半径の中の毛の本数 (取りこぼした毛が跡の中に見える本数)
const TOOL_TRACE_MIN_HAIRS: int = 6
## 引いている途中を撮る時の進み具合 (毛が伸びて手が閉じかけた所)
const PULL_SNAPSHOT_PROGRESS: float = 0.7

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
	# 音の解放を実時間で待つ。timer はフレームの経過時間で減るため、撮影の最後の重いフレーム (見た目の試作の多い毛)
	# の直後では実時間より早く終わり、解放が間に合わずリーク警告が出た (PR #30 の CI。1 フレーム進めてから timer で
	# 待っても実時間は 115 ms で、AUDIO_RELEASE_TIME_SEC に届かなかった)
	var release_deadline_msec: int = (
		Time.get_ticks_msec() + int(AudioManagerScript.AUDIO_RELEASE_TIME_SEC * 1000.0)
	)
	while Time.get_ticks_msec() < release_deadline_msec:
		await process_frame
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
	_set_pitch(player, LOOK_OVERVIEW_PITCH)
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
	_set_pitch(player, LOOK_OVERVIEW_PITCH)
	if look_room.show_automation_props(main.mansion_world.get_hair_field()) <= 0:
		push_error("look prototype FAIL: 掃除ロボットの帯で毛が 1 本も消えていない")
		return false
	return await _capture("tmp/screenshot-look-automation.png")


## プレイヤーの見下ろす角度を pitch (rad) にする
func _set_pitch(player: FirstPersonPlayer, pitch: float) -> void:
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

	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		push_error("windowed mouse check FAIL: 左クリックで MOUSE_MODE_CAPTURED にならない")
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


## 屋敷に入った一人称プレイ画面 (部屋・家具・布・毛・画面の手・照準・残り本数と在庫の HUD)、毛を引く場面、
## 図鑑、開発者向け調整画面を順に撮る。撮れたら空文字、失敗したら理由を返す
func _capture_mansion_scenes(main: Node3D) -> String:
	main.enter_mansion()
	if not await _capture("tmp/screenshot-mansion.png"):
		return "屋敷の画面を保存できない"
	var pluck_error: String = await _capture_pluck(main)
	if not pluck_error.is_empty():
		return pluck_error
	main.open_hair_book()
	var book_ok: bool = await _capture("tmp/screenshot-hair-book.png")
	main.close_hair_book()
	if not book_ok:
		return "図鑑を保存できない"
	var tool_error: String = await _capture_tools(main)
	if not tool_error.is_empty():
		return tool_error
	var big_tool_error: String = await ScreenshotBigTools.capture_all(self, main)
	if not big_tool_error.is_empty():
		return big_tool_error
	main.open_dev_panel()
	return "" if await _capture("tmp/screenshot-dev-panel.png") else "開発者向け調整画面を保存できない"


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
	return ""


## 粘着ローラーを床の毛にかけた直後 (跡の円盤・取りこぼした毛・取りこぼしの割合・道具の並び・部屋のゲージ) と、
## 道具を買う画面を撮る。撮れたら空文字、失敗したら理由を返す
func _capture_tools(main: Node3D) -> String:
	var game_state: Node = main.get_game_state()
	var roller: StringName = ToolCatalogScript.TOOL_LINT_ROLLER
	# 手に持つ 8 つの道具を全部持った時の右下の道具の枠の並びも同じ 1 枚で確かめる (大型の道具は後で撮る)。
	# 所持金は 7 つの道具の値段の合計 (940 円) を足りる額で、HUD に 5 桁の所持金が出る見え方も撮れる額にする
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

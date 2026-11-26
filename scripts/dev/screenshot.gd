extends SceneTree
## 実際の描画で代表画面を撮影する (headless では描画されないため、Makefile の screenshot target が
## --headless なしで起動する)。撮影した PNG は tmp/screenshot-<名前>.png に保存し、失敗したら quit(1) で終わる。
## 全部の撮影を終えたら「screenshot OK」の行を出して quit(0) する (Makefile はこの行と PNG の存在で判定する)。
## 画面や状態を増やす時は _capture_scenes() に撮影を足す。

## 音の解放を待つ時間 (AUDIO_RELEASE_TIME) を借りる、headless の検証の土台
const HeadlessCheck := preload("res://scripts/dev/headless_check.gd")
## 撮影するメインシーン
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
## 状態管理 autoload スクリプト
const GameStateScript := preload("res://scripts/state/game_state.gd")
## JSON 保存ストレージスクリプト
const SaveStorageScript := preload("res://scripts/state/save_storage.gd")

## screenshot 専用のセーブパス
const TEST_SAVE_PATH: String = "user://screenshot_save_data.json"


## tree の準備が終わってから _run() を始める (シーンの追加は _initialize() の後でないとできない)
func _initialize() -> void:
	_run.call_deferred()


## フレームを進めながら撮影するため、同じ実行中に重ねて呼び出さない
func _run() -> void:
	if await _capture_scenes():
		await create_timer(HeadlessCheck.AUDIO_RELEASE_TIME).timeout
		print("screenshot OK")
		quit(0)


## 撮影する画面の並び。失敗した撮影は _capture() が quit(1) 済みなので、false を受けたらそのまま抜ける
func _capture_scenes() -> bool:
	SaveStorageScript.delete_save_file(TEST_SAVE_PATH)
	var created_state: bool = false
	var game_state: Node = root.get_node_or_null("GameState")
	if game_state == null:
		game_state = GameStateScript.new()
		game_state.name = "GameState"
		root.add_child(game_state)
		created_state = true
	game_state.initialize_from_storage(TEST_SAVE_PATH)

	var main: Node3D = MAIN_SCENE.instantiate()
	root.add_child(main)
	current_scene = main

	# 最初の撮影だけ、フォントの読み込みと最初の描画を時間で待つ。0.3 秒は bannzai/goki-hunter の撮影から引き継いだ値で、
	# CI の llvmpipe でこの画面が描画し終わることを PR #1 の artifact で確かめた (下限は測っていない)
	await create_timer(0.3).timeout
	if not await _capture("tmp/screenshot-title.png"):
		_cleanup(main, game_state, created_state)
		return false

	# 屋敷の中の一人称プレイ画面 (部屋・家具・布・仮の毛・残り本数の HUD)
	main.enter_mansion()
	if not await _capture("tmp/screenshot-mansion.png"):
		_cleanup(main, game_state, created_state)
		return false

	# 開発者向け調整画面を開いた状態
	main.open_dev_panel()
	if not await _capture("tmp/screenshot-dev-panel.png"):
		_cleanup(main, game_state, created_state)
		return false

	# 描画付き環境 (非 headless) でのマウス捕捉・捕捉中視点移動・Esc 解放・F1 解放を検証する
	if not await _verify_windowed_mouse_capture(main):
		_cleanup(main, game_state, created_state)
		quit(1)
		return false

	_cleanup(main, game_state, created_state)
	return true


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
	main.open_dev_panel()
	await process_frame
	if Input.get_mouse_mode() != Input.MOUSE_MODE_VISIBLE:
		push_error("windowed mouse check FAIL: 開発者画面を開いても MOUSE_MODE_VISIBLE に戻らない")
		return false
	return true


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
		quit(1)
		return false
	print("screenshot: " + path)
	return true

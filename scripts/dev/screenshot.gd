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

## 開発者向け調整値データ型スクリプト (見た目の試作の撮影で毛の本数を変える)
const MansionTuningScript := preload("res://scripts/data/mansion_tuning.gd")
## 見た目の試作の部屋のスクリプト (1 本ずつ描く毛の上限の単一の正)
const LookPrototypeRoomScript := preload("res://scripts/look/look_prototype_room.gd")

## screenshot 専用のセーブパス
const TEST_SAVE_PATH: String = "user://screenshot_save_data.json"
## 見た目の試作を撮る時の屋敷全体の毛の本数。既定の 4 部屋に分けた時に最初の部屋の毛が
## 1 本ずつ描く上限 (LookPrototypeRoom.VISUAL_HAIR_CAP) に届き、量の多さが一目で分かる本数
const LOOK_HAIR_COUNT: int = LookPrototypeRoomScript.VISUAL_HAIR_CAP * 4
## 部屋に入った直後と自動化の絵で見下ろす角度 (rad)。床と家具の上の毛が画面の下半分を占める角度
const LOOK_OVERVIEW_PITCH: float = -0.45
## 毛をつまむ構図で見下ろす角度 (rad)。足元の床の毛と手が画面の中央に入る角度
const LOOK_PINCH_PITCH: float = -0.85
## 毛をつまむ構図の目の高さ (m)。床にしゃがんで顔を寄せた高さで、指先が床から 10 cm 前後になり、
## 引っ張られて伸びた毛が手の長さほどに見える
const LOOK_PINCH_EYE_HEIGHT_M: float = 0.6


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
	# 撮影の最後のフレーム (見た目の試作の 24 万本の毛) は重く、その直後に作った timer は同じフレームの経過時間で
	# 減って待たずに終わり、音の解放が間に合わずリーク警告が出る (PR #30 の CI で観測)。1 フレーム進めてから待つ
	await process_frame
	(audio_handle["manager"] as AudioManagerScript).stop_all()
	var release_wait_start_msec: int = Time.get_ticks_msec()
	await create_timer(AudioManagerScript.AUDIO_RELEASE_TIME_SEC).timeout
	print("DIAG audio release wait: %d ms" % (Time.get_ticks_msec() - release_wait_start_msec))
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
	var player: FirstPersonPlayer = main.get_node("Player")
	var look_room: LookPrototypeRoom = main.look_room
	if look_room.get_visual_hair_count() <= 0:
		push_error("look prototype FAIL: 試作の部屋に毛が描かれていない")
		return false

	_set_pitch(player, LOOK_OVERVIEW_PITCH)
	if not await _capture("tmp/screenshot-look-enter.png"):
		return false

	# 一人称の頭のノード (カメラの親) を下げてしゃがんだ構図にし、撮った後に元の高さへ戻す
	var head: Node3D = player.get_camera().get_parent() as Node3D
	var standing_eye_height: float = head.position.y
	head.position.y = LOOK_PINCH_EYE_HEIGHT_M
	_set_pitch(player, LOOK_PINCH_PITCH)
	look_room.set_pinch_pose(true)
	var pinch_ok: bool = await _capture("tmp/screenshot-look-pinch.png")
	look_room.set_pinch_pose(false)
	head.position.y = standing_eye_height
	if not pinch_ok:
		return false

	_set_pitch(player, LOOK_OVERVIEW_PITCH)
	if look_room.show_automation_props() <= 0:
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

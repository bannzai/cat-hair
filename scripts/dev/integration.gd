extends "res://scripts/dev/headless_check.gd"
## メインシーンを tree に置いて動かす入力統合テスト (headless)。
## 実行方法は AGENTS.md「検証方法」を参照 (各検証の詳細は下の _verify_* 関数を参照)。

## 動かして確かめるメインシーン
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
## 状態管理 autoload スクリプト
const GameStateScript := preload("res://scripts/state/game_state.gd")
## JSON 保存ストレージスクリプト
const SaveStorageScript := preload("res://scripts/state/save_storage.gd")
## 開発者向け調整値データ型スクリプト
const MansionTuningScript := preload("res://scripts/data/mansion_tuning.gd")
## 一人称プレイヤーノードスクリプト (ピッチ上限の単一情報源参照に使用)
const FirstPersonPlayerScript := preload("res://scripts/player/first_person_player.gd")

## integration テスト専用のセーブパス
const TEST_SAVE_PATH: String = "user://integration_save_data.json"
## 実プロセス OS 引数検証モードを指定するフラグ引数
const CMDLINE_VERIFY_FLAG: String = "--verify-cmdline"


## tree の準備が終わってから _run() を始める (シーンの追加は _initialize() の後でないとできない)
func _initialize() -> void:
	_run.call_deferred()


## フレームを進めながら検証するため、同じ実行中に重ねて呼び出さない
func _run() -> void:
	if OS.get_cmdline_user_args().has(CMDLINE_VERIFY_FLAG):
		await _run_cmdline_process_verification()
		_finish()
		return

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
	await process_frame

	await _verify_title_and_blocked_inputs(main)
	await _verify_enter_movement_and_look(main)
	await _verify_dev_panel_keys_and_rebuild(main, game_state)
	await _verify_manual_save_and_close_request(game_state)

	root.remove_child(main)
	main.free()

	await _verify_resume_and_new_game_from_saved_state(game_state)

	if created_state:
		root.remove_child(game_state)
		game_state.free()
	SaveStorageScript.delete_save_file(TEST_SAVE_PATH)
	_finish()


## 実 Godot プロセスへ渡された OS コマンドライン引数を GameState._ready() が適用することを検証する
func _run_cmdline_process_verification() -> void:
	var game_state: Node = root.get_node_or_null("GameState")
	_check(game_state != null, "OS 引数検証で autoload GameState が起動している")
	if game_state == null:
		return
	var main: Node3D = MAIN_SCENE.instantiate()
	root.add_child(main)
	await process_frame

	var world: MansionWorld = main.get_node("MansionWorld")
	var tuning: MansionTuning = game_state.get_tuning()
	_check(game_state.launched_with_cmdline_override, "OS 引数起動で上書きフラグが立っている")
	_check(tuning.room_count == 2, "OS 引数 --room-count=2 が GameState に反映される")
	_check(tuning.hair_count == 321, "OS 引数 --hair-count=321 が GameState に反映される")
	_check(tuning.object_count == 4, "OS 引数 --object-count=4 が GameState に反映される")
	_check(tuning.found_item_count == 1, "OS 引数 --found-item-count=1 が GameState に反映される")
	_check(is_equal_approx(tuning.room_size_m, 5.0), "OS 引数 --room-size=5.0 が反映される")
	_check(world.get_room_node_count() == 2, "OS 引数で屋敷の部屋ノード数が 2 になる")
	_check(world.get_object_node_count() == 4, "OS 引数で屋敷の物ノード数が 4 になる")

	main.enter_mansion()
	await process_frame
	var hair_label: Label = main.get_node("UILayer/UI/HUD/RemainingHairPanel/RemainingHairLabel")
	_check(
		hair_label.text.contains("321"),
		"OS 引数起動の HUD に 321 本が表示される (実際: %s)" % hair_label.text,
	)

	root.remove_child(main)
	main.free()


## タイトル表示・既定フォント設定と、タイトル中は移動・視点・F1・F5 が無効であることを検証する
func _verify_title_and_blocked_inputs(main: Node3D) -> void:
	var title_label: Label = main.get_node_or_null("UILayer/UI/TitleOverlay/Layout/TitleLabel")
	_check(title_label != null, "題名の Label がある")
	if title_label != null:
		_check(not title_label.text.is_empty(), "題名の Label に文字が入っている")
	var ui_theme: Theme = main.get_ui_theme()
	_check(ui_theme != null and ui_theme.default_font != null, "UI の theme に既定フォントが入っている")
	var start_button: Button = main.get_node("UILayer/UI/TitleOverlay/Layout/StartButton")
	var new_game_button: Button = main.get_node("UILayer/UI/TitleOverlay/Layout/NewGameButton")
	_check(
		main.get_node("UILayer/UI/TitleOverlay").visible and not main.get_node("UILayer/UI/HUD").visible,
		"起動時はタイトル表示で HUD は非表示",
	)
	_check(
		start_button.text == "はじめる" and not new_game_button.visible,
		"セーブ未作成時は『はじめる』のみ表示される",
	)

	var player: FirstPersonPlayer = main.get_node("Player")
	var before_pos: Vector3 = player.global_position
	Input.action_press("move_forward")
	for _step: int in range(6):
		await physics_frame
	Input.action_release("move_forward")
	_check(
		Vector2(player.global_position.x - before_pos.x, player.global_position.z - before_pos.z)
		.length()
		< 0.01,
		"タイトル表示中は前進入力しても水平移動しない",
	)

	# タイトル表示中 (controls_enabled = false) はマウス移動イベントでも視点が変わらない
	player.allow_uncaptured_look = true
	var yaw_before_title_look: float = player.rotation.y
	await _send_mouse_motion(Vector2(60.0, -30.0))
	player.allow_uncaptured_look = false
	_check(
		is_equal_approx(player.rotation.y, yaw_before_title_look),
		"controls_enabled=false の時はマウス移動イベントでも視点が変わらない",
	)

	await _press_physical_key(KEY_F1)
	var panel: DevTuningPanel = main.get_node("UILayer/UI/DevTuningPanel")
	_check(not panel.visible, "タイトル表示中は F1 を押しても開発者向け画面が開かない")

	await _press_physical_key(KEY_F5)
	_check(
		not SaveStorageScript.has_save_file(TEST_SAVE_PATH),
		"タイトル表示中は F5 を押してもセーブされない",
	)


## 屋敷へ入った後の HUD 表示・床接地・壁衝突・ドア通過・4 方向移動・視点入力とクランプを検証する
func _verify_enter_movement_and_look(main: Node3D) -> void:
	main.get_node("UILayer/UI/TitleOverlay/Layout/StartButton").pressed.emit()
	await process_frame

	var hair_label: Label = main.get_node("UILayer/UI/HUD/RemainingHairPanel/RemainingHairLabel")
	_check(main.get_node("UILayer/UI/HUD").visible, "はじめる押下で HUD が表示される")
	_check(
		hair_label.text.contains("12,000"),
		"残り毛本数の表示に既定値 12,000 が出ている (実際: %s)" % hair_label.text,
	)

	var player: FirstPersonPlayer = main.get_node("Player")
	# 数物理フレーム進めて床の上に接地していることを確認 (床衝突が無いと落下し続ける)
	for _step: int in range(6):
		await physics_frame
	_check(
		player.is_on_floor() and player.global_position.y >= -0.05,
		"プレイヤーが床の衝突体の上に接地している (y=%.3f)" % player.global_position.y,
	)

	# 南の閉じた壁へ向かって十分後退しても壁衝突で部屋の外 (z > 3.0) へ抜けないことを確認
	await _hold_move_action("move_back", 45)
	_check(
		player.global_position.z < MansionTuningScript.DEFAULT_ROOM_SIZE_M * 0.5,
		"南側の閉じた壁の衝突体で止まり外へ抜けない (z=%.3f)" % player.global_position.z,
	)

	# 前進 (-Z)・後退 (+Z)・左 (-X)・右 (+X) の 4 方向すべての向きを検証
	var pos_before_fwd: Vector3 = player.global_position
	await _hold_move_action("move_forward", 8)
	_check(player.global_position.z < pos_before_fwd.z - 0.1, "前進入力で -Z 方向へ移動する")

	var pos_before_back: Vector3 = player.global_position
	await _hold_move_action("move_back", 6)
	_check(player.global_position.z > pos_before_back.z + 0.1, "後退入力で +Z 方向へ移動する")

	var pos_before_left: Vector3 = player.global_position
	await _hold_move_action("move_left", 6)
	_check(player.global_position.x < pos_before_left.x - 0.1, "左移動入力で -X 方向へ移動する")

	var pos_before_right: Vector3 = player.global_position
	await _hold_move_action("move_right", 6)
	_check(player.global_position.x > pos_before_right.x + 0.1, "右移動入力で +X 方向へ移動する")

	# 中央 (x=0) へ戻って北側ドア開口を通過し隣室 (z < -room_size/2) へ入れることを確認
	player.global_position = Vector3(0.0, 0.05, 0.0)
	await _hold_move_action("move_forward", 60)
	_check(
		player.global_position.z < -MansionTuningScript.DEFAULT_ROOM_SIZE_M * 0.5,
		"北側ドア開口を通って隣室へ移動できる (z=%.3f)" % player.global_position.z,
	)

	# Esc キー入力 (release_mouse) がエラーなく処理されることを確認
	await _press_physical_key(KEY_ESCAPE)

	# マウス未捕捉 + allow_uncaptured_look=false では視点が変わらない
	player.allow_uncaptured_look = false
	var yaw_uncaptured: float = player.rotation.y
	var pitch_uncaptured: float = player.get_pitch()
	await _send_mouse_motion(Vector2(50.0, -25.0))
	_check(
		is_equal_approx(player.rotation.y, yaw_uncaptured)
		and is_equal_approx(player.get_pitch(), pitch_uncaptured),
		"マウス未捕捉かつ allow_uncaptured_look=false では視点が変わらない",
	)

	# allow_uncaptured_look=true で InputEventMouseMotion が _unhandled_input を通って視点を動かす
	player.allow_uncaptured_look = true
	await _send_mouse_motion(Vector2(40.0, -30.0))
	_check(
		not is_equal_approx(player.rotation.y, yaw_uncaptured)
		and not is_equal_approx(player.get_pitch(), pitch_uncaptured),
		"InputEventMouseMotion が _unhandled_input を通ってヨー角とピッチ角を動かす",
	)
	player.allow_uncaptured_look = false

	# 上下限のピッチクランプを FirstPersonPlayer.MAX_PITCH_RADIANS で両側検証
	player.apply_look_delta(Vector2(0.0, -99999.0))
	_check(
		is_equal_approx(player.get_pitch(), FirstPersonPlayerScript.MAX_PITCH_RADIANS),
		"極端な上向き入力でピッチ角が +MAX_PITCH_RADIANS にクランプされる",
	)
	player.apply_look_delta(Vector2(0.0, 99999.0))
	_check(
		is_equal_approx(player.get_pitch(), -FirstPersonPlayerScript.MAX_PITCH_RADIANS),
		"極端な下向き入力でピッチ角が -MAX_PITCH_RADIANS にクランプされる",
	)


## F1 トグル開閉・閉じるボタン・調整値変更での屋敷作り直しと load_from_tuning 反映を検証する
func _verify_dev_panel_keys_and_rebuild(main: Node3D, game_state: Node) -> void:
	var world: MansionWorld = main.get_node("MansionWorld")
	var panel: DevTuningPanel = main.get_node("UILayer/UI/DevTuningPanel")
	var player: FirstPersonPlayer = main.get_node("Player")
	var hair_label: Label = main.get_node("UILayer/UI/HUD/RemainingHairPanel/RemainingHairLabel")

	_check(
		world.get_room_node_count() == MansionTuningScript.DEFAULT_ROOM_COUNT,
		"作り直し前の部屋ノード数が既定値と一致する",
	)
	_check(
		world.get_object_node_count() == MansionTuningScript.DEFAULT_OBJECT_COUNT,
		"作り直し前の物ノード数が既定値と一致する",
	)

	# F1 キーで開く → F1 キーで閉じるトグル分岐を検証
	await _press_physical_key(KEY_F1)
	_check(panel.visible and not player.controls_enabled, "F1 キー入力で開発者向け画面が開く")

	var pos_while_open: Vector3 = player.global_position
	await _hold_move_action("move_forward", 6)
	_check(
		Vector2(
			player.global_position.x - pos_while_open.x,
			player.global_position.z - pos_while_open.z,
		).length()
		< 0.01,
		"開発者向け画面が開いている間は前進入力しても移動しない",
	)

	await _press_physical_key(KEY_F1)
	_check(not panel.visible and player.controls_enabled, "開いた状態で F1 再押下すると閉じる")

	# 閉じるボタン分岐も検証
	await _press_physical_key(KEY_F1)
	panel.close_button.pressed.emit()
	await process_frame
	_check(not panel.visible and player.controls_enabled, "閉じるボタンでパネルが閉じて操作再開する")

	# F1 で再度開き、調整値を変更して屋敷を作り直す
	await _press_physical_key(KEY_F1)
	panel.hair_count_spin.value = 500.0
	panel.found_item_count_spin.value = 2.0
	panel.room_size_spin.value = 8.0
	panel.object_count_spin.value = 6.0
	panel.room_count_spin.value = 2.0
	panel.apply_button.pressed.emit()
	await process_frame

	_check(not panel.visible and player.controls_enabled, "適用後に開発者向け画面が閉じて操作再開する")
	_check(world.get_room_node_count() == 2, "屋敷を作り直すと部屋ノード数が 2 に変わる")
	_check(world.get_object_node_count() == 6, "屋敷を作り直すと物ノード数が 6 に変わる")
	_check(game_state.get_total_remaining_hairs() == 500, "屋敷を作り直すと総毛本数が 500 に変わる")
	_check(
		game_state.current_layout.found_item_spots.size() == 2,
		"屋敷を作り直すと探し物置き場所が 2 に変わる",
	)
	_check(hair_label.text.contains("500"), "HUD の残り毛本数が 500 に更新される")

	# 一度入力欄を別値に変えてから F1 で再度開き、load_from_tuning が現在値 5 項目を復元することを検証
	panel.hair_count_spin.value = 1.0
	panel.room_count_spin.value = 1.0
	await _press_physical_key(KEY_F1)
	_check(
		int(round(panel.hair_count_spin.value)) == 500
		and int(round(panel.found_item_count_spin.value)) == 2
		and is_equal_approx(panel.room_size_spin.value, 8.0)
		and int(round(panel.object_count_spin.value)) == 6
		and int(round(panel.room_count_spin.value)) == 2,
		"開発者向け画面を再度開くと現在の 5 調整値が入力欄へ反映される",
	)
	await _press_physical_key(KEY_F1)

	var reloaded_state: Node = GameStateScript.new()
	reloaded_state.initialize_from_storage(TEST_SAVE_PATH)
	_check(
		reloaded_state.loaded_from_save
		and reloaded_state.get_tuning().room_count == 2
		and reloaded_state.get_tuning().object_count == 6
		and reloaded_state.get_tuning().hair_count == 500
		and reloaded_state.get_tuning().found_item_count == 2
		and is_equal_approx(reloaded_state.get_tuning().room_size_m, 8.0),
		"再起動後に保存した 5 つの調整値がそのまま復元される",
	)
	reloaded_state.free()


## F5 手動セーブキーと NOTIFICATION_WM_CLOSE_REQUEST 終了時保存を検証する
func _verify_manual_save_and_close_request(game_state: Node) -> void:
	game_state.save_data.building_progress.money = 999
	await _press_physical_key(KEY_F5)
	var after_f5: SaveData = SaveStorageScript.load_from_path(TEST_SAVE_PATH)
	_check(
		after_f5 != null and after_f5.building_progress.money == 999,
		"プレイ中の F5 キー入力で所持金 999 が手動保存される",
	)

	game_state.save_data.building_progress.money = 1234
	game_state.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	var after_close: SaveData = SaveStorageScript.load_from_path(TEST_SAVE_PATH)
	_check(
		after_close != null and after_close.building_progress.money == 1234,
		"NOTIFICATION_WM_CLOSE_REQUEST で所持金 1234 が保存される",
	)


## 保存データがある状態での起動表示 (「続きから」「はじめから」) と「はじめから」動作を検証する
func _verify_resume_and_new_game_from_saved_state(game_state: Node) -> void:
	game_state.initialize_from_storage(TEST_SAVE_PATH)
	var resumed_main: Node3D = MAIN_SCENE.instantiate()
	root.add_child(resumed_main)
	await process_frame

	var start_button: Button = resumed_main.get_node("UILayer/UI/TitleOverlay/Layout/StartButton")
	var new_game_button: Button = resumed_main.get_node(
		"UILayer/UI/TitleOverlay/Layout/NewGameButton"
	)
	_check(
		start_button.text == "続きから" and new_game_button.visible,
		"保存データあり起動時は『続きから』と『はじめから』が表示される",
	)

	new_game_button.pressed.emit()
	await process_frame
	var hud: Control = resumed_main.get_node("UILayer/UI/HUD")
	_check(hud.visible and game_state.get_money() == 0, "『はじめから』押下で初期化して屋敷へ入る")
	var saved_after_reset: SaveData = SaveStorageScript.load_from_path(TEST_SAVE_PATH)
	_check(
		saved_after_reset != null and saved_after_reset.building_progress.money == 0,
		"『はじめから』で初期化した進行が保存ファイルへ書き出される",
	)

	root.remove_child(resumed_main)
	resumed_main.free()


## 指定した移動アクションを指定フレーム数だけ押し続けてから離す
func _hold_move_action(action_name: String, frame_count: int) -> void:
	Input.action_press(action_name)
	for _step: int in range(frame_count):
		await physics_frame
	Input.action_release(action_name)
	await physics_frame


## 指定した物理キーの押下・解放イベントを Input に流して 1 フレーム進める
func _press_physical_key(physical_key: Key) -> void:
	var press_event: InputEventKey = InputEventKey.new()
	press_event.physical_keycode = physical_key
	press_event.pressed = true
	Input.parse_input_event(press_event)
	await process_frame

	var release_event: InputEventKey = InputEventKey.new()
	release_event.physical_keycode = physical_key
	release_event.pressed = false
	Input.parse_input_event(release_event)
	await process_frame


## マウス移動イベントを Input に流して 1 フレーム進める
func _send_mouse_motion(relative_delta: Vector2) -> void:
	var motion_event: InputEventMouseMotion = InputEventMouseMotion.new()
	motion_event.relative = relative_delta
	Input.parse_input_event(motion_event)
	await process_frame

extends "res://scripts/dev/headless_check.gd"
## メインシーンを tree に置いて動かす入力統合テスト (headless)。
## タイトルからの遷移・一人称の移動と視点入力・F1/F5 キー入力・開発者調整画面での屋敷作り直し・
## 終了時保存・セーブあり起動時の「続きから」「はじめから」を検証する。
## 実行方法は AGENTS.md「検証方法」を参照。

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveStorageScript := preload("res://scripts/state/save_storage.gd")
const MansionTuningScript := preload("res://scripts/data/mansion_tuning.gd")

## integration テスト専用のセーブパス
const TEST_SAVE_PATH: String = "user://integration_save_data.json"


## tree の準備が終わってから _run() を始める (シーンの追加は _initialize() の後でないとできない)
func _initialize() -> void:
	_run.call_deferred()


## フレームを進めながら検証するため、同じ実行中に重ねて呼び出さない
func _run() -> void:
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
	await _verify_enter_and_movement(main)
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


## タイトル表示・既定フォント設定と、タイトル中は移動・F1・F5 が無効であることを検証する
func _verify_title_and_blocked_inputs(main: Node3D) -> void:
	var title_label: Label = main.get_node_or_null("UILayer/UI/TitleOverlay/Layout/TitleLabel")
	_check(title_label != null, "題名の Label がある")
	if title_label != null:
		_check(not title_label.text.is_empty(), "題名の Label に文字が入っている")
	var ui_theme: Theme = main.get_ui_theme()
	_check(ui_theme != null and ui_theme.default_font != null, "UI の theme に既定フォントが入っている")
	var title_overlay: Control = main.get_node("UILayer/UI/TitleOverlay")
	var hud: Control = main.get_node("UILayer/UI/HUD")
	var start_button: Button = main.get_node("UILayer/UI/TitleOverlay/Layout/StartButton")
	var new_game_button: Button = main.get_node("UILayer/UI/TitleOverlay/Layout/NewGameButton")
	_check(title_overlay.visible and not hud.visible, "起動時はタイトル表示で HUD は非表示")
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

	await _press_physical_key(KEY_F1)
	var panel: DevTuningPanel = main.get_node("UILayer/UI/DevTuningPanel")
	_check(not panel.visible, "タイトル表示中は F1 を押しても開発者向け画面が開かない")

	await _press_physical_key(KEY_F5)
	_check(
		not SaveStorageScript.has_save_file(TEST_SAVE_PATH),
		"タイトル表示中は F5 を押してもセーブされない",
	)


## 屋敷へ入った後の HUD 表示・一人称移動・視点操作とクランプを検証する
func _verify_enter_and_movement(main: Node3D) -> void:
	var start_button: Button = main.get_node("UILayer/UI/TitleOverlay/Layout/StartButton")
	start_button.pressed.emit()
	await process_frame

	var hud: Control = main.get_node("UILayer/UI/HUD")
	var hair_label: Label = main.get_node("UILayer/UI/HUD/RemainingHairPanel/RemainingHairLabel")
	_check(hud.visible, "はじめる押下で HUD が表示される")
	_check(
		hair_label.text.contains("12,000"),
		"残り毛本数の表示に既定値 12,000 が出ている (実際: %s)" % hair_label.text,
	)

	var player: FirstPersonPlayer = main.get_node("Player")
	var before_pos: Vector3 = player.global_position
	Input.action_press("move_forward")
	for _step: int in range(10):
		await physics_frame
	Input.action_release("move_forward")
	await physics_frame
	var moved_dist: float = before_pos.distance_to(player.global_position)
	_check(
		moved_dist > 0.1,
		"前進入力でプレイヤー位置が変わる (移動距離: %.3f m)" % moved_dist,
	)

	var before_yaw: float = player.rotation.y
	var before_pitch: float = player.get_pitch()
	player.apply_look_delta(Vector2(40.0, -30.0))
	_check(
		not is_equal_approx(player.rotation.y, before_yaw),
		"視点の水平入力でヨー角が変わる",
	)
	_check(
		not is_equal_approx(player.get_pitch(), before_pitch),
		"視点の垂直入力でピッチ角が変わる",
	)
	player.apply_look_delta(Vector2(0.0, -99999.0))
	_check(player.get_pitch() <= 1.351, "極端な上向き入力でもピッチ角が上限内に収まる")


## F1 キー開閉・閉じるボタン・調整値変更での屋敷作り直しと永続化を検証する
func _verify_dev_panel_keys_and_rebuild(main: Node3D, game_state: Node) -> void:
	var world: MansionWorld = main.get_node("MansionWorld")
	var panel: DevTuningPanel = main.get_node("UILayer/UI/DevTuningPanel")
	var player: FirstPersonPlayer = main.get_node("Player")
	var hair_label: Label = main.get_node("UILayer/UI/HUD/RemainingHairPanel/RemainingHairLabel")

	_check(
		world.get_room_node_count() == MansionTuningScript.DEFAULT_ROOM_COUNT,
		"作り直し前の部屋ノード数が既定値と一致する (%d)" % world.get_room_node_count(),
	)
	_check(
		world.get_object_node_count() == MansionTuningScript.DEFAULT_OBJECT_COUNT,
		"作り直し前の物ノード数が既定値と一致する (%d)" % world.get_object_node_count(),
	)

	# 実際の F1 キー入力イベントで開発者向け画面を開く
	await _press_physical_key(KEY_F1)
	_check(panel.visible, "プレイ中に F1 キー入力で開発者向け画面が開く")
	_check(not player.controls_enabled, "開発者向け画面を開いている間はプレイヤー移動が無効")

	# パネル表示中は移動入力しても動かない
	var pos_while_open: Vector3 = player.global_position
	Input.action_press("move_forward")
	for _step: int in range(6):
		await physics_frame
	Input.action_release("move_forward")
	_check(
		Vector2(
			player.global_position.x - pos_while_open.x,
			player.global_position.z - pos_while_open.z,
		).length()
		< 0.01,
		"開発者向け画面が開いている間は前進入力しても移動しない",
	)

	# 閉じるボタンで閉じて操作再開
	panel.close_button.pressed.emit()
	await process_frame
	_check(not panel.visible and player.controls_enabled, "閉じるボタンでパネルが閉じて操作再開する")

	# 再度 F1 キーで開き、調整値を変更して屋敷を作り直す
	await _press_physical_key(KEY_F1)
	_check(panel.visible, "F1 キー再押下で開発者向け画面が再度開く")

	panel.hair_count_spin.value = 500.0
	panel.found_item_count_spin.value = 2.0
	panel.room_size_spin.value = 8.0
	panel.object_count_spin.value = 6.0
	panel.room_count_spin.value = 2.0
	panel.apply_button.pressed.emit()
	await process_frame

	_check(not panel.visible, "適用後に開発者向け画面が閉じる")
	_check(player.controls_enabled, "適用後にプレイヤー移動が再開する")
	_check(
		world.get_room_node_count() == 2,
		"屋敷を作り直すと部屋ノード数が 2 に変わる (実際: %d)" % world.get_room_node_count(),
	)
	_check(
		world.get_object_node_count() == 6,
		"屋敷を作り直すと物ノード数が 6 に変わる (実際: %d)" % world.get_object_node_count(),
	)
	_check(
		game_state.get_total_remaining_hairs() == 500,
		"屋敷を作り直すと総毛本数が 500 に変わる (実際: %d)" % game_state.get_total_remaining_hairs(),
	)
	_check(
		game_state.current_layout.found_item_spots.size() == 2,
		"屋敷を作り直すと探し物置き場所が 2 に変わる",
	)
	_check(
		hair_label.text.contains("500"),
		"HUD の残り毛本数が 500 に更新される (実際: %s)" % hair_label.text,
	)

	var reloaded_state: Node = GameStateScript.new()
	reloaded_state.initialize_from_storage(TEST_SAVE_PATH)
	_check(reloaded_state.loaded_from_save, "変更した調整値が保存され次回起動で読み込まれる")
	_check(
		reloaded_state.get_tuning().room_count == 2
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
	_check(hud.visible, "『はじめから』押下で屋敷プレイ画面へ入る")
	_check(game_state.get_money() == 0, "『はじめから』で所持金が 0 に初期化される")
	var saved_after_reset: SaveData = SaveStorageScript.load_from_path(TEST_SAVE_PATH)
	_check(
		saved_after_reset != null and saved_after_reset.building_progress.money == 0,
		"『はじめから』で初期化した進行が保存ファイルへ書き出される",
	)

	root.remove_child(resumed_main)
	resumed_main.free()


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

extends "res://scripts/dev/headless_check.gd"
## メインシーンを tree に置いて動かす入力統合テスト (headless)。
## タイトルからの遷移・一人称の移動と視点入力・開発者向けの調整画面での屋敷作り直しと
## 永続化を検証する。実行方法は AGENTS.md「検証方法」を参照。

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

	var game_state: Node = GameStateScript.new()
	game_state.name = "GameState"
	game_state.save_path = TEST_SAVE_PATH
	root.add_child(game_state)
	game_state.initialize_from_storage(TEST_SAVE_PATH)

	var main: Node3D = MAIN_SCENE.instantiate()
	root.add_child(main)
	await process_frame

	_verify_title_and_theme(main)
	await _verify_enter_and_movement(main)
	await _verify_dev_panel_rebuild_and_persistence(main, game_state)

	root.remove_child(main)
	main.free()
	root.remove_child(game_state)
	game_state.free()
	SaveStorageScript.delete_save_file(TEST_SAVE_PATH)
	_finish()


func _verify_title_and_theme(main: Node3D) -> void:
	var title_label: Label = main.get_node_or_null("UILayer/UI/TitleOverlay/Layout/TitleLabel")
	_check(title_label != null, "題名の Label がある")
	if title_label != null:
		_check(not title_label.text.is_empty(), "題名の Label に文字が入っている")
	var ui_theme: Theme = main.get_ui_theme()
	_check(ui_theme != null and ui_theme.default_font != null, "UI の theme に既定フォントが入っている")
	var title_overlay: Control = main.get_node("UILayer/UI/TitleOverlay")
	var hud: Control = main.get_node("UILayer/UI/HUD")
	_check(title_overlay.visible and not hud.visible, "起動時はタイトル表示で HUD は非表示")


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
	for _i: int in range(10):
		await physics_frame
	Input.action_release("move_forward")
	await physics_frame
	var after_pos: Vector3 = player.global_position
	var moved_dist: float = before_pos.distance_to(after_pos)
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


func _verify_dev_panel_rebuild_and_persistence(main: Node3D, game_state: Node) -> void:
	var world: MansionWorld = main.get_node("MansionWorld")
	var panel: DevTuningPanel = main.get_node("UILayer/UI/DevTuningPanel")
	var player: FirstPersonPlayer = main.get_node("Player")
	var hair_label: Label = main.get_node("UILayer/UI/HUD/RemainingHairPanel/RemainingHairLabel")

	var before_rooms: int = world.get_room_node_count()
	var before_objects: int = world.get_object_node_count()
	_check(
		before_rooms == MansionTuningScript.DEFAULT_ROOM_COUNT,
		"作り直し前の部屋ノード数が既定値と一致する (%d)" % before_rooms,
	)
	_check(
		before_objects == MansionTuningScript.DEFAULT_OBJECT_COUNT,
		"作り直し前の物ノード数が既定値と一致する (%d)" % before_objects,
	)

	# 開発者向け画面を開く
	main.open_dev_panel()
	await process_frame
	_check(panel.visible, "開発者向け画面が開く")
	_check(not player.controls_enabled, "開発者向け画面を開いている間はプレイヤー移動が無効")

	# 調整値を変更して屋敷を作り直す
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

	# 再起動相当で別インスタンスから読み込み、同じ調整値と屋敷で始まることを確かめる
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

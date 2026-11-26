extends RefCounted
## 手で毛を取る操作の入力統合テスト (scripts/dev/integration.gd から呼ぶ)。
## メインシーンを動かし、画面中央で狙った毛をつまむ入力で、伸びて抜け・効果音・「+1 本」・残り本数 -1・在庫 +1 になること、
## 途中で離すと何も変わらないこと、図鑑の開閉と、何も変わらない場面 (図鑑中・狙いの先に毛が無い) を確かめる。

## 手で毛を取る時のルールの計算
const HandRulesScript := preload("res://scripts/hand/hand_rules.gd")
## 目線を床の毛へ向ける手順
const HandAim := preload("res://scripts/dev/hand_aim.gd")
## 屋敷レイアウト型スクリプト (表面の種類の定数を使う)
const MansionLayoutScript := preload("res://scripts/mansion/mansion_layout.gd")
## 音声カタログ (効果音の出来事名)
const AudioCatalog := preload("res://scripts/audio/audio_catalog.gd")
## AudioManager の型解決と実行時取得用スクリプト参照
const AudioManagerScript := preload("res://scripts/audio/audio_manager.gd")
## 面ごとの毛データ型スクリプト (色の定数を使う)
const SurfaceHairScript := preload("res://scripts/data/surface_hair.gd")
## メインシーンのスクリプト (本数の表示の書式を使う)
const MainScript := preload("res://scripts/main.gd")
## JSON 保存ストレージスクリプト (保存した内容の読み戻しに使う)
const SaveStorageScript := preload("res://scripts/state/save_storage.gd")
## 毛・加工品在庫データ型スクリプト (毛のままの形の定数を使う)
const HairStockScript := preload("res://scripts/data/hair_stock.gd")
## 毛をつまむ入力アクション
const ACTION_PLUCK: StringName = &"pluck_hair"

## 検証結果を記録する integration の SceneTree 参照
var _checker: SceneTree = null


## 手で毛を取る操作の検証をすべて実行する (main はプレイ中のメインシーン)
static func run_all(checker: SceneTree, main: Node3D, game_state: Node) -> void:
	var suite: RefCounted = load("res://scripts/dev/integration_hand.gd").new()
	suite._checker = checker
	main.hand.allow_uncaptured_pluck = true
	await checker.process_frame
	await suite._verify_hair_book_blocks_and_shows(main, game_state)
	await suite._verify_aim_at_nothing(main, game_state)
	await suite._verify_release_midway_and_pluck(main, game_state)
	await suite._verify_upgrades_change_pull(main, game_state)
	main.hand.allow_uncaptured_pluck = false
	Input.action_release(ACTION_PLUCK)
	await checker.process_frame


## 検証結果を integration 本体へ記録する
func _check(cond: bool, label: String) -> void:
	_checker._check(cond, label)


## B キーで図鑑が開閉し、開いている間はつまむ入力で何も変わらず、見つけた珍しい毛の名前が出るか
func _verify_hair_book_blocks_and_shows(main: Node3D, game_state: Node) -> void:
	var hand: HandController = main.hand
	var aimed_id: int = await HandAim.aim_at_floor_hair(_checker, main)
	_check(aimed_id >= 0, "床の毛を画面中央に狙える位置と向きが見つかる")
	await _press_physical_key(KEY_B)
	_check(
		main.hair_book_panel.visible and not hand.enabled and not main.player.controls_enabled,
		"B キーで図鑑が開き、歩く操作とつまむ操作が止まる",
	)
	var before_total: int = game_state.get_total_remaining_hairs()
	await _hold_pluck(3)
	_check(
		not hand.is_pulling() and game_state.get_total_remaining_hairs() == before_total,
		"図鑑が開いている間はつまむ入力で毛をつままず、残り本数も変わらない",
	)
	await _press_physical_key(KEY_B)
	_check(
		not main.hair_book_panel.visible and hand.enabled,
		"B キーをもう一度押すと図鑑が閉じ、操作が戻る",
	)

	# 図鑑に載った珍しい毛が、次に開いた図鑑に名前で出る
	var first_surface: SurfaceHair = game_state.save_data.building_progress.surface_hairs[0]
	var color_id: StringName = SurfaceHairScript.COLOR_WHITE
	for candidate: StringName in SurfaceHairScript.STANDARD_COLORS:
		if first_surface.count_for_color(candidate) > 0:
			color_id = candidate
			break
	game_state.pluck_hair(first_surface.surface_id, color_id, HandRulesScript.RARE_WHISKER)
	main.open_hair_book()
	await _checker.process_frame
	_check(
		main.hair_book_panel.get_entry_texts()[0] == "・猫のヒゲ"
		and main.hair_book_panel.get_summary_text().contains("1 / 3"),
		"珍しい毛 (猫のヒゲ) を見つけた後に開いた図鑑に、その名前と 1 / 3 種類が出る",
	)
	main.hair_book_panel.close_requested.emit()
	await _checker.process_frame
	_check(not main.hair_book_panel.visible, "図鑑の閉じるボタンで図鑑が閉じる")
	# 図鑑の検証で GameState だけ 1 本減らしたので、毛の見た目をそろえるため作り直す
	game_state.mansion_rebuilt.emit(game_state.current_layout)
	await _checker.process_frame


## 狙いの先に毛の表面が無い (真上を見る) 時は、つまむ入力で何も変わらないか
func _verify_aim_at_nothing(main: Node3D, game_state: Node) -> void:
	var player: FirstPersonPlayer = main.player
	player.look_at_point(player.get_camera().global_position + Vector3(0.0, 10.0, 0.01))
	await _checker.physics_frame
	var before_total: int = game_state.get_total_remaining_hairs()
	var before_stock: int = game_state.get_raw_hair_stock_count()
	await _hold_pluck(3)
	_check(
		not main.hand.is_pulling()
		and game_state.get_total_remaining_hairs() == before_total
		and game_state.get_raw_hair_stock_count() == before_stock,
		"天井を狙ってつまむ入力をしても毛をつままず、残り本数と在庫が変わらない",
	)


## 狙った毛をつまむ入力で引き始め、途中で離すと元に戻り、引き終えると 1 本抜けて本数・在庫・効果音・表示が変わるか
func _verify_release_midway_and_pluck(main: Node3D, game_state: Node) -> void:
	var hand: HandController = main.hand
	var world: MansionWorld = main.mansion_world
	var hair_field: Node3D = world.get_hair_field()
	var aimed_id: int = await HandAim.aim_at_floor_hair(_checker, main)
	_check(aimed_id >= 0, "作り直した屋敷でも床の毛を狙える")
	if aimed_id < 0:
		return
	var surface_index: int = int(hand.aim_target()["surface_index"])
	var surface_def: MansionLayout.SurfaceDef = world.get_surface_def(surface_index)
	var before_total: int = game_state.get_total_remaining_hairs()
	var before_surface: int = game_state.get_surface_hair_count(surface_def.surface_id)
	var before_stock: int = game_state.get_raw_hair_stock_count()
	var before_field: int = hair_field.get_remaining_count()

	# 押した瞬間につまみ、離すと元に戻る
	Input.action_press(ACTION_PLUCK)
	await _checker.process_frame
	var pulled_ids: PackedInt32Array = hand.get_pulling_ids()
	_check(
		hand.is_pulling() and pulled_ids.size() == 1
		and hair_field.find_hairs_near(
			surface_index, hair_field.get_hair_transform(pulled_ids[0]).origin, 0.001, 1
		) == pulled_ids,
		"狙った床の毛をつまむ入力で、その表面の毛を 1 本つまむ",
	)
	_check(
		is_equal_approx(
			hand.get_pull_duration(),
			HandRulesScript.pull_seconds(MansionLayoutScript.SURFACE_FLOOR, 0),
		),
		"強化していない手で床の毛を引き抜く時間が 0.45 秒",
	)
	hand.advance_pull(hand.get_pull_duration() * 0.5)
	_check(
		hand.get_pull_progress() >= 0.5 and hand.get_pull_progress() < 1.0
		and hand.get_hand_view().get_pull_progress() >= 0.5,
		"引いている途中は進み具合が 0.5 以上 1 未満で、画面の手も同じだけ引いている",
	)
	Input.action_release(ACTION_PLUCK)
	await _checker.process_frame
	_check(
		not hand.is_pulling()
		and hair_field.has_hair(pulled_ids[0])
		and hand.get_hand_view().get_pull_progress() == 0.0
		and game_state.get_total_remaining_hairs() == before_total
		and game_state.get_raw_hair_stock_count() == before_stock,
		"途中で離すと毛は抜けずに残り、手が開き、残り本数と在庫が変わらない",
	)

	# もう一度つまんで引き終えると 1 本抜ける
	var audio_manager: AudioManagerScript = (
		AudioManagerScript.resolve(_checker) as AudioManagerScript
	)
	Input.action_press(ACTION_PLUCK)
	await _checker.process_frame
	var plucked_id: int = hand.get_pulling_ids()[0] if hand.is_pulling() else -1
	var plucked_color: StringName = world.get_hair_color_id(plucked_id)
	var surface_hair: SurfaceHair = game_state.save_data.building_progress.find_surface_hair(
		surface_def.surface_id
	)
	var before_color: int = surface_hair.count_for_color(plucked_color)
	var plucked: int = hand.advance_pull(hand.get_pull_duration())
	await _checker.process_frame
	Input.action_release(ACTION_PLUCK)
	await _checker.process_frame
	_check(
		plucked == 1 and not hair_field.has_hair(plucked_id),
		"引き終えるとつまんだ 1 本が抜けて HairField から消える",
	)
	_check(
		game_state.get_total_remaining_hairs() == before_total - 1
		and game_state.get_surface_hair_count(surface_def.surface_id) == before_surface - 1
		and surface_hair.count_for_color(plucked_color) == before_color - 1
		and hair_field.get_remaining_count() == before_field - 1,
		"抜くと残り本数・その面の本数・その面のその色の本数・HairField の本数がそろって 1 減る",
	)
	_check(game_state.get_raw_hair_stock_count() == before_stock + 1, "抜くと毛のままの在庫が 1 増える")
	_check(
		audio_manager == null
		or audio_manager.get_last_sfx_event_name() == AudioCatalog.SFX_PLUCK_HAIR,
		"抜くと効果音 pluck_hair が鳴る",
	)
	_check(main.get_pluck_popup_text().begins_with("+1 本"), "抜くと画面中央に「+1 本」が出る")
	_check(
		main.remaining_hair_label.text.contains(MainScript.format_hair_count(before_total - 1))
		and main.stock_label.text.contains(MainScript.format_hair_count(before_stock + 1)),
		"HUD の残り本数が 1 減り、在庫の表示が 1 増える",
	)
	game_state.save_current_state()
	var saved: SaveData = SaveStorageScript.load_from_path(game_state.save_path)
	var saved_stock: int = 0
	if saved != null:
		for stock: HairStock in saved.building_progress.hair_stocks:
			saved_stock += stock.count if stock.form == HairStockScript.FORM_RAW else 0
	_check(
		saved != null
		and saved.building_progress.total_remaining_hairs() == before_total - 1
		and saved_stock == before_stock + 1
		and saved.found_rare_hair_ids.has(HandRulesScript.RARE_WHISKER),
		"抜いた後に保存すると、減った残り本数・増えた在庫・図鑑に載った珍しい毛が保存データに残る",
	)


## 器用さの強化で引く時間が短くなり、一度につまめる本数の強化でつまむ本数の上限が増えるか
func _verify_upgrades_change_pull(main: Node3D, game_state: Node) -> void:
	var hand: HandController = main.hand
	game_state.set_hand_upgrade_level(HandRulesScript.UPGRADE_DEXTERITY, 2)
	game_state.set_hand_upgrade_level(HandRulesScript.UPGRADE_GRAB_COUNT, 2)
	var aimed_id: int = await HandAim.aim_at_floor_hair(_checker, main)
	if aimed_id < 0:
		_check(false, "強化の検証で床の毛を狙える")
		return
	var target: Dictionary = hand.aim_target()
	var reachable: PackedInt32Array = main.mansion_world.get_hair_field().find_hairs_near(
		int(target["surface_index"]), target["point"], HandController.GRAB_RADIUS_M, 3
	)
	Input.action_press(ACTION_PLUCK)
	await _checker.process_frame
	_check(
		is_equal_approx(
			hand.get_pull_duration(),
			HandRulesScript.pull_seconds(MansionLayoutScript.SURFACE_FLOOR, 2),
		)
		and hand.get_pull_duration()
		< HandRulesScript.pull_seconds(MansionLayoutScript.SURFACE_FLOOR, 0),
		"器用さ 2 段で床の毛を引き抜く時間が強化なしより短くなる",
	)
	_check(
		hand.get_pulling_ids().size() == reachable.size() and reachable.size() >= 1,
		"一度につまめる本数 2 段 (3 本) で、狙った点の近くの毛を最大 3 本まとめてつまむ",
	)
	Input.action_release(ACTION_PLUCK)
	await _checker.process_frame
	game_state.set_hand_upgrade_level(HandRulesScript.UPGRADE_DEXTERITY, 0)
	game_state.set_hand_upgrade_level(HandRulesScript.UPGRADE_GRAB_COUNT, 0)


## つまむ入力を指定フレーム数だけ押し続けてから離す
func _hold_pluck(frame_count: int) -> void:
	Input.action_press(ACTION_PLUCK)
	for _step: int in range(frame_count):
		await _checker.process_frame
	Input.action_release(ACTION_PLUCK)
	await _checker.process_frame


## 指定した物理キーの押下・解放イベントを Input に流して 1 フレームずつ進める
func _press_physical_key(physical_key: Key) -> void:
	var press_event: InputEventKey = InputEventKey.new()
	press_event.physical_keycode = physical_key
	press_event.pressed = true
	Input.parse_input_event(press_event)
	await _checker.process_frame
	var release_event: InputEventKey = InputEventKey.new()
	release_event.physical_keycode = physical_key
	release_event.pressed = false
	Input.parse_input_event(release_event)
	await _checker.process_frame

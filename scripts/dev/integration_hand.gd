extends RefCounted
## 手で毛を取る操作の入力統合テスト (scripts/dev/integration.gd から呼ぶ)。
## 手で毛を取る時のルールの計算
const HandRulesScript := preload("res://scripts/hand/hand_rules.gd")
## 目線を床の毛へ向ける手順
const HandAim := preload("res://scripts/dev/hand_aim.gd")
## 音声カタログ (効果音の出来事名)
const AudioCatalog := preload("res://scripts/audio/audio_catalog.gd")
## AudioManager の型解決と実行時取得用スクリプト参照
const AudioManagerScript := preload("res://scripts/audio/audio_manager.gd")
## 面ごとの毛データ型スクリプト (色の定数を使う)
const SurfaceHairScript := preload("res://scripts/data/surface_hair.gd")
## メインシーンのスクリプト (本数の表示の書式を使う)
const MainScript := preload("res://scripts/main.gd")

## 検証結果を記録する integration の SceneTree 参照
var _checker: SceneTree = null


## 手で毛を取る操作の検証をすべて実行する (main はプレイ中のメインシーン)
static func run_all(checker: SceneTree, main: Node3D, game_state: Node) -> void:
	var suite: RefCounted = load("res://scripts/dev/integration_hand.gd").new()
	suite._checker = checker
	main.hand.allow_uncaptured_pluck = true
	await checker.process_frame
	suite._verify_crosshair_centered(main)
	await suite._verify_tap(main, game_state)
	await suite._verify_bare_floor(main, game_state)
	await suite._verify_play_guide(main)
	await suite._verify_hair_book_blocks_and_shows(main, game_state)
	await suite._verify_occluded_aim(main, game_state)
	await suite._verify_capture_gate(main, game_state)
	await suite._verify_rare_hair_from_pluck(main, game_state)
	await suite._verify_hand_upgrade_twice(main, game_state)
	main.hand.allow_uncaptured_pluck = false
	Input.action_release(HandController.ACTION_PLUCK)
	await checker.process_frame


## 検証結果を integration 本体へ記録する
func _check(cond: bool, label: String) -> void:
	_checker._check(cond, label)


## 照準の線の交点が画面のちょうど中央 (狙いの光線の向き) にあるか
func _verify_crosshair_centered(main: Node3D) -> void:
	var screen_center: Vector2 = main.get_viewport().get_visible_rect().get_center()
	var centered: bool = main.crosshair.get_child_count() == 2
	for line: Control in main.crosshair.get_children():
		if line.get_global_rect().get_center().distance_to(screen_center) > 0.5:
			centered = false
	_check(centered, "照準の横と縦の線の中心が画面の中央にある (狙いの光線と同じ位置)")


## B キーで図鑑が開閉し、開いている間はつまむ入力で何も変わらず、見つけた珍しい毛の名前が出るか
func _verify_hair_book_blocks_and_shows(main: Node3D, game_state: Node) -> void:
	var hand: HandController = main.hand
	var aimed_id: int = await HandAim.aim_at_floor_hair(_checker, main)
	_check(aimed_id >= 0, "床の毛を画面中央に狙える位置と向きが見つかる")
	await _checker._press_physical_key(KEY_B)
	_check(
		main.hair_book_panel.visible and not hand.enabled and not main.player.controls_enabled,
		"B キーで図鑑が開き、歩く操作とつまむ操作が止まる",
	)
	# 入力の処理の後、HUD が通常の _process で表示を更新したフレームを確認する。
	await _checker.process_frame
	_check(
		not hand.can_pluck() and not main.crosshair.is_visible_in_tree()
		and not main.look_hud.get_node("GuideLabel").is_visible_in_tree(),
		"届く毛を狙っていても、図鑑を開くと手の案内と照準が消える (つまめる=%s 案内=%s 照準=%s)"
		% [hand.can_pluck(), main.look_hud.get_node("GuideLabel").is_visible_in_tree(),
			main.crosshair.is_visible_in_tree()],
	)
	var before_total: int = game_state.get_total_remaining_hairs()
	await _checker._press_physical_key(KEY_E)
	_check(
		game_state.get_total_remaining_hairs() == before_total,
		"図鑑が開いている間はつまむ入力で毛をつままず、残り本数も変わらない",
	)
	await _checker._press_physical_key(KEY_F1)
	_check(
		main.hair_book_panel.visible and not main.dev_tuning_panel.visible,
		"図鑑が開いている間は F1 で開発者向け画面が開かない (2 つの画面が重ならない)",
	)
	await _checker._press_physical_key(KEY_B)
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


## 同じフレーム内に押して離す E と、押し続けてキーリピートが届く E を実際の入力経路に通す。
func _verify_tap(main: Node3D, game_state: Node) -> void:
	var audio: AudioManagerScript = AudioManagerScript.resolve(_checker) as AudioManagerScript
	_check(main.player.find_child("Body", true, false) == null
		and main.player.find_child("HandView", true, false) == null, "自分の体と手を描くノードがない")
	for hold: bool in [false, true]:
		var hair: int = await HandAim.aim_at_floor_hair(_checker, main)
		if hair < 0:
			_check(false, "押す前に床の毛に照準が合う")
			return
		var total: int = game_state.get_total_remaining_hairs()
		var sounds: int = audio.get_sfx_play_count()
		var stock: int = game_state.get_raw_hair_stock_count()
		await _checker.process_frame
		await _checker.process_frame
		_check(main.crosshair.is_visible_in_tree() and main.look_hud.get_node("GuideLabel").visible,
			"届く毛を狙うと照準と操作の案内が現れる")
		_send_key(main, true)
		var lifted: MeshInstance3D = main.player.get_camera().get_node_or_null("PluckedHair")
		_check(lifted != null and lifted.is_visible_in_tree(), "押した直後に手前に 1 本の毛が見える")
		if hold:
			await _checker.process_frame
			await HandAim.aim_at_floor_hair(_checker, main)
			_send_key(main, true, true)
		_send_key(main, false)
		await _checker.process_frame
		_check(not main.mansion_world.get_hair_field().has_hair(hair)
			and game_state.get_total_remaining_hairs() == total - 1
			and game_state.get_raw_hair_stock_count() == stock + 1
			and audio.get_sfx_play_count() == sounds + 1
			and audio.get_last_sfx_event_name() == AudioCatalog.SFX_PLUCK_HAIR,
			"E の短押し・長押しのどちらも狙った 1 本だけが取れて成功音が 1 回鳴る (長押し=%s)" % hold)
	main.player.look_at_point(main.player.get_camera().global_position + Vector3.UP * 4.0)
	await _checker.physics_frame
	var before: int = game_state.get_total_remaining_hairs()
	var sounds_before: int = audio.get_sfx_play_count()
	_send_key(main, true)
	_send_key(main, false)
	await _checker.process_frame
	_check(game_state.get_total_remaining_hairs() == before and main.tool_message_label.text.is_empty()
		and audio.get_sfx_play_count() == sounds_before + 1
		and audio.get_last_sfx_event_name() == AudioCatalog.SFX_BUTTON,
		"空振りでは本数と照準の文字が変わらず、成功音と異なる音が 1 回鳴る")


## 毛が付く床面まで照準が届いても、根元が近くにないときは短い音で空振りを伝える。
func _verify_bare_floor(main: Node3D, game_state: Node) -> void:
	if not await _aim_at_bare_floor(main):
		_check(false, "毛の付く床のうち、照準の近くに毛がない部分を狙える")
		return
	var audio: AudioManagerScript = AudioManagerScript.resolve(_checker) as AudioManagerScript
	var total: int = game_state.get_total_remaining_hairs()
	var sounds: int = audio.get_sfx_play_count()
	await _checker._press_physical_key(KEY_E)
	_check(not main.hand.can_pluck() and game_state.get_total_remaining_hairs() == total
		and audio.get_sfx_play_count() == sounds + 1
		and audio.get_last_sfx_event_name() == AudioCatalog.SFX_BUTTON
		and main.tool_message_label.text.is_empty(),
		"届く床面の毛がない所で押すと本数が変わらず、理由の文字が出ず、空振り音が 1 回鳴る")


## 狙いを床の毛に向けた後、その周りの床を順に狙い、狙った所の つまめる範囲内に毛が無い所で止める。止めたら true
func _aim_at_bare_floor(main: Node3D) -> bool:
	if await HandAim.aim_at_floor_hair(_checker, main) < 0:
		return false
	var hand: HandController = main.hand
	var hair_field: Node3D = main.mansion_world.get_hair_field()
	var floor_hair_target: Dictionary = hand.aim_target()
	var surface_index: int = int(floor_hair_target["surface_index"])
	var center: Vector3 = floor_hair_target["point"]
	# 狙った毛の周りを、0.12 m (つかむ半径 0.08 m より広い) ずつ 7 輪、1 輪を 8 方向で探す (最大 0.84 m 先まで)
	for ring: int in range(1, 8):
		for step: int in range(8):
			var angle: float = TAU * float(step) / 8.0
			main.player.look_at_point(center + Vector3(cos(angle), 0.0, sin(angle)) * 0.12 * ring)
			await _checker.physics_frame
			var target: Dictionary = hand.aim_target()
			if target.is_empty() or int(target["surface_index"]) != surface_index:
				continue
			if hair_field.find_hairs_near(
				surface_index, target["point"],
				HandRulesScript.grab_radius(MansionLayout.SURFACE_FLOOR, 0), 1
			).is_empty():
				return true
	return false


## 実際の操作と同じ E キーのイベントをビューポートに渡す。
func _send_key(main: Node3D, pressed: bool, repeat: bool = false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_E
	event.pressed = pressed
	event.echo = repeat
	main.get_viewport().push_input(event)


## 道具を買う画面の「手の強化」のボタンを続けて 2 回押すと、2 回とも段が上がるか
func _verify_hand_upgrade_twice(main: Node3D, game_state: Node) -> void:
	var dexterity: StringName = HandRulesScript.UPGRADE_DEXTERITY
	var level_before: int = game_state.get_hand_upgrade_level(dexterity)
	var money_before: int = game_state.save_data.building_progress.money
	# 2 段分の値段 (ToolRules.hand_upgrade_price) より十分に多い所持金。値段の調整で 2 回目が買えずに落ちないようにする
	game_state.save_data.building_progress.money = 100000
	main.toggle_tool_shop()
	await _checker.process_frame
	var button: Button = main.tool_shop_panel.get_hand_upgrade_button(dexterity)
	for press: int in [1, 2]:
		var enabled_before: bool = button != null and not button.disabled
		if button != null:
			button.pressed.emit()
		await _checker.process_frame
		_check(
			enabled_before and game_state.get_hand_upgrade_level(dexterity) == level_before + press,
			"道具を買う画面の「手の強化」(器用さ) のボタンが押せる状態で、%d 回目に押すと段が %d に上がる"
			% [press, level_before + press],
		)
	main.toggle_tool_shop()
	await _checker.process_frame
	game_state.set_hand_upgrade_level(dexterity, level_before)
	game_state.save_data.building_progress.money = money_before


## 遊び始めに操作の一覧が出ていて、H キーで閉じる・開く。画面を開いている間は隠れて H が効かず、
## マウスを放す案内がマウスの状態に合った文言で出ているか
func _verify_play_guide(main: Node3D) -> void:
	var guide: PlayGuideHud = main.play_guide
	var text: String = guide.get_controls_guide_text()
	var listed: bool = true
	for needle: String in ["歩く", "視点", "毛を取る", "持ち替える", "T: 道具を買う", "R: 掃除ロボット", "Esc: マウスを放す"]:
		listed = listed and text.contains(needle)
	_check(
		guide.is_controls_guide_visible() and listed,
		"屋敷に入った時に操作の一覧が出ていて、歩く・視点・1 回押して取る・持ち替え・道具を買う・掃除ロボット・マウスを放すが書いてある",
	)
	await _checker._press_physical_key(MainScript.TOGGLE_GUIDE_KEY)
	_check(not guide.is_controls_guide_visible(), "H キーで操作の一覧が閉じる")
	await _checker._press_physical_key(MainScript.TOGGLE_GUIDE_KEY)
	_check(guide.is_controls_guide_visible(), "H キーをもう一度押すと操作の一覧が開く (後から見直せる)")
	main.toggle_tool_shop()
	await _checker.process_frame
	_check(not guide.is_controls_guide_visible(), "道具を買う画面を開いている間は操作の一覧が隠れる")
	await _checker._press_physical_key(MainScript.TOGGLE_GUIDE_KEY)
	main.toggle_tool_shop()
	await _checker.process_frame
	_check(
		guide.is_controls_guide_visible(),
		"道具を買う画面を開いている間の H キーは効かず、画面を閉じると操作の一覧がまた出る",
	)
	# タイトル画面 (遊んでいない間) の H キーは効かない。タイトルへ戻る操作が無いため、遊んでいるかの値だけを戻して確かめる
	main._is_playing = false
	await _checker._press_physical_key(MainScript.TOGGLE_GUIDE_KEY)
	main._is_playing = true
	_check(guide.is_controls_guide_visible(), "遊んでいない間 (タイトル画面) の H キーでは操作の一覧が閉じない")
	_check(
		guide.get_mouse_hint_text() == PlayGuideHud.mouse_hint_text(false)
		and PlayGuideHud.mouse_hint_text(true).contains("Esc: マウスを放す"),
		"マウスを取っていない時はマウスを取る案内が出ていて、取っている時の案内には Esc で放すことが書いてある",
	)


## 毛の面より手前に衝突体がある時はつまめず、取り除くとまたつまめるか
func _verify_occluded_aim(main: Node3D, game_state: Node) -> void:
	var hand: HandController = main.hand
	if await HandAim.aim_at_floor_hair(_checker, main) < 0:
		_check(false, "遮りの検証で床の毛を狙える")
		return
	var camera: Camera3D = main.player.get_camera()
	var target_point: Vector3 = hand.aim_target()["point"]
	var blocker: StaticBody3D = StaticBody3D.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(0.3, 0.3, 0.05)
	shape.shape = box
	blocker.add_child(shape)
	main.add_child(blocker)
	blocker.global_position = camera.global_position.lerp(target_point, 0.5)
	await _checker.physics_frame
	await _checker.physics_frame
	var before_total: int = game_state.get_total_remaining_hairs()
	await _checker._press_physical_key(KEY_E)
	_check(
		hand.aim_target().is_empty()
		and not main.crosshair.is_visible_in_tree()
		and not main.look_hud.get_node("GuideLabel").is_visible_in_tree()
		and game_state.get_total_remaining_hairs() == before_total,
		"毛の面より手前に衝突体があると、狙いが空になりつまむ入力で何も変わらない",
	)
	_check(
		main.tool_message_label.text.is_empty(),
		"毛の面より手前に衝突体がある時につまむ入力をすると、照準の下に理由の文字が出ない",
	)
	Input.action_release(HandController.ACTION_PLUCK)
	blocker.queue_free()
	await _checker.physics_frame
	await _checker.physics_frame
	_check(not hand.aim_target().is_empty(), "手前の衝突体を取り除くと、同じ毛をまた狙える")
	await _checker.process_frame


## マウスが捕捉されていないときは、毛が照準の先にあっても操作を受け付けない。
func _verify_capture_gate(main: Node3D, game_state: Node) -> void:
	var hair: int = await HandAim.aim_at_floor_hair(_checker, main)
	main.hand.allow_uncaptured_pluck = false
	var before: int = game_state.get_total_remaining_hairs()
	await _checker._press_physical_key(KEY_E)
	_check(hair >= 0 and not main.hand.can_pluck()
		and game_state.get_total_remaining_hairs() == before,
		"マウスを放している間は毛を取る案内が消え、E を押しても本数が変わらない")
	main.hand.allow_uncaptured_pluck = true


## 抜いた毛が珍しい毛 (猫のヒゲ) になる乱数で抜くと、珍しい毛の在庫に入り、「珍しい毛: 猫のヒゲ」が出るか。
## 猫のヒゲは図鑑の検証で既に図鑑に載っているので「(図鑑に載った)」は出ない
func _verify_rare_hair_from_pluck(main: Node3D, game_state: Node) -> void:
	var hand: HandController = main.hand
	# 最初の乱数が猫のヒゲの区間 [0, 1/400) に入るシードを探す (どの色の毛でも猫のヒゲになる)
	var whisker_seed: int = -1
	var probe: RandomNumberGenerator = RandomNumberGenerator.new()
	for candidate: int in range(1, 200000):
		probe.seed = candidate
		if probe.randf() < 1.0 / 400.0:
			whisker_seed = candidate
			break
	if whisker_seed < 0 or await HandAim.aim_at_floor_hair(_checker, main) < 0:
		_check(false, "珍しい毛の検証でシードと床の毛が見つかる")
		return
	hand.set_rng_seed(whisker_seed)
	var before_whisker: int = _rare_stock_count(game_state, HandRulesScript.RARE_WHISKER)
	await _checker._press_physical_key(KEY_E)
	Input.action_release(HandController.ACTION_PLUCK)
	await _checker.process_frame
	_check(
		_rare_stock_count(game_state, HandRulesScript.RARE_WHISKER) == before_whisker + 1
		and main.get_pluck_popup_text().contains("珍しい毛: 猫のヒゲ")
		and not main.get_pluck_popup_text().contains("(図鑑に載った)"),
		"珍しい毛を引き当てて抜くと猫のヒゲの在庫が 1 増え、「珍しい毛: 猫のヒゲ」が出る (図鑑に載り済みなので新しくは載らない)",
	)
	hand.set_rng_seed(Time.get_ticks_usec())


## 毛のままの在庫のうち、指定した珍しい毛の本数を返す
static func _rare_stock_count(game_state: Node, rare_hair_id: StringName) -> int:
	var total: int = 0
	for stock: HairStock in game_state.save_data.building_progress.hair_stocks:
		if stock.rare_hair_id == rare_hair_id:
			total += stock.count
	return total

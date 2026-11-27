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

## 検証結果を記録する integration の SceneTree 参照
var _checker: SceneTree = null


## 手で毛を取る操作の検証をすべて実行する (main はプレイ中のメインシーン)
static func run_all(checker: SceneTree, main: Node3D, game_state: Node) -> void:
	var suite: RefCounted = load("res://scripts/dev/integration_hand.gd").new()
	suite._checker = checker
	main.hand.allow_uncaptured_pluck = true
	await checker.process_frame
	suite._verify_crosshair_centered(main)
	await suite._verify_play_guide(main)
	await suite._verify_hair_book_blocks_and_shows(main, game_state)
	await suite._verify_aim_at_nothing(main, game_state)
	await suite._verify_short_press_twice(main, game_state)
	await suite._verify_bare_floor_reason(main, game_state)
	await suite._verify_out_of_reach_reason(main, game_state)
	await suite._verify_obstacle_only_reason(main, game_state)
	await suite._verify_no_reason_when_interrupted(main, game_state)
	await suite._verify_release_midway_and_pluck(main, game_state)
	await suite._verify_upgrades_change_pull(main, game_state)
	await suite._verify_hold_plucks_and_capture_gate(main, game_state)
	await suite._verify_occluded_aim(main, game_state)
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
	var before_total: int = game_state.get_total_remaining_hairs()
	await _hold_pluck(3)
	_check(
		not hand.is_pulling() and game_state.get_total_remaining_hairs() == before_total,
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
	_check(
		main.tool_message_label.text == HandController.failure_message(HandController.REASON_NO_HAIR),
		"天井を狙ってつまむ入力をすると、照準の下に「狙った所に毛が無い」理由が出る",
	)


## 6 番の発言の読み (a): 毛を狙って短く押して離すのを 2 回続けると、2 回とも毛が戻り、2 回とも理由が出るか
func _verify_short_press_twice(main: Node3D, game_state: Node) -> void:
	var hand: HandController = main.hand
	var aimed_id: int = await HandAim.aim_at_floor_hair(_checker, main)
	if aimed_id < 0:
		_check(false, "短く押す検証で床の毛を狙える")
		return
	var before_total: int = game_state.get_total_remaining_hairs()
	var released_message: String = HandController.failure_message(HandController.REASON_RELEASED)
	for attempt: int in [1, 2]:
		main.tool_message_label.text = ""
		# 2 フレームは、HandController の _process が押した 1 フレーム (引き始め) と離した 1 フレームを見る最短の長さ
		await _hold_pluck(2)
		_check(
			not hand.is_pulling()
			and main.mansion_world.get_hair_field().has_hair(aimed_id)
			and game_state.get_total_remaining_hairs() == before_total
			and main.tool_message_label.text == released_message,
			"毛を狙って短く押して離す %d 回目も、毛が戻って残り本数が変わらず、照準の下に「途中で離した」理由が出る"
			% attempt,
		)


## 6 番の発言の読み (b): 毛の付く床を狙っていても、狙った所の 0.08 m 以内に毛が無い時は、つまめずに理由が出るか
func _verify_bare_floor_reason(main: Node3D, game_state: Node) -> void:
	if not await _aim_at_bare_floor(main):
		_check(false, "床の毛の表面のうち、狙った所の近くに毛が無い所を狙える")
		return
	var before_total: int = game_state.get_total_remaining_hairs()
	main.tool_message_label.text = ""
	await _hold_pluck(3)
	_check(
		not main.hand.is_pulling()
		and game_state.get_total_remaining_hairs() == before_total
		and main.tool_message_label.text
		== HandController.failure_message(HandController.REASON_NO_HAIR),
		"毛の付く床の、近くに毛が無い所を狙ってつまむと、毛をつまめず照準の下に「狙った所に毛が無い」理由が出る",
	)


## 届かない所: 床の毛から手の届く距離より遠く離れて、その毛を狙ってつまむと、理由が出るか。
## 遊び始めの立ち位置と目線 (水平に近く、照準が手の届く距離より遠い隣の部屋の奥を指す) でつまむと、
## 「届かない」が出るかも確かめ、理由をログに残す
func _verify_out_of_reach_reason(main: Node3D, game_state: Node) -> void:
	var hand: HandController = main.hand
	var player: FirstPersonPlayer = main.player
	var aimed_id: int = await HandAim.aim_at_floor_hair(_checker, main)
	if aimed_id < 0:
		_check(false, "届かない所の検証で床の毛を狙える")
		return
	# 手の届く距離の 2 倍 (5.2 m) は、届く距離を少し超えた所での判定の揺れ (根元と狙いの点の差) に左右されない遠さ
	await _move_to_root_distance(
		player,
		main.mansion_world.get_hair_field().get_hair_transform(aimed_id).origin,
		HandController.REACH_M * 2.0,
	)
	await _checker.physics_frame
	var before_total: int = game_state.get_total_remaining_hairs()
	main.tool_message_label.text = ""
	await _hold_pluck(3)
	_check(
		not hand.is_pulling()
		and game_state.get_total_remaining_hairs() == before_total
		and main.tool_message_label.text
		== HandController.failure_message(HandController.REASON_OUT_OF_REACH),
		"床の毛から 5.2 m 離れてその毛を狙ってつまむと、毛をつまめず照準の下に「毛まで手が届かない」理由が出る",
	)

	var layout: MansionLayout = game_state.current_layout
	player.set_spawn(layout.spawn_position, layout.spawn_yaw)
	await _checker.physics_frame
	await _checker.physics_frame
	main.tool_message_label.text = ""
	await _hold_pluck(3)
	print(
		"integration: 遊び始めの立ち位置と目線でつまむと: pulling=%s reason=%s message=%s"
		% [hand.is_pulling(), hand.pull_failure_reason(), main.tool_message_label.text]
	)
	_check(
		main.tool_message_label.text
		== HandController.failure_message(HandController.REASON_OUT_OF_REACH),
		"遊び始めの立ち位置と目線のままつまむと、毛に手が届かず、照準の下に「毛まで手が届かない」理由が出る",
	)


## 届かない・毛が無いの見分けのうち、光線が毛の付く表面に当たらず壁・家具の衝突体だけに当たる時:
## 衝突体が手の届く距離より遠ければ「届かない」、届く距離にあれば「狙った所に毛が無い」になるか。
## 屋敷の上空 (屋根より 60 m 上。毛の付く表面も衝突体も無い) へ立ち位置を移して真上を狙い、光線の上に衝突体を置いて
## 確かめる。終わったら遊び始めの立ち位置へ戻す
func _verify_obstacle_only_reason(main: Node3D, game_state: Node) -> void:
	var hand: HandController = main.hand
	var camera: Camera3D = main.player.get_camera()
	var layout: MansionLayout = game_state.current_layout
	main.player.set_spawn(layout.spawn_position + Vector3(0.0, 60.0, 0.0), layout.spawn_yaw)
	await _checker.physics_frame
	main.player.look_at_point(camera.global_position + Vector3(0.0, 10.0, 0.1))
	await _checker.physics_frame
	if not main.mansion_world.get_hair_field().intersect_surfaces(
		camera.global_position, -camera.global_basis.z, HandController.AIM_PROBE_M
	).is_empty():
		_check(false, "屋敷の上空で真上を狙うと、光線の先に毛の付く表面が無い")
		main.player.set_spawn(layout.spawn_position, layout.spawn_yaw)
		return
	var blocker: StaticBody3D = StaticBody3D.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(1.0, 0.05, 1.0)
	shape.shape = box
	blocker.add_child(shape)
	main.add_child(blocker)
	# 届く距離の 2 倍 (遠い) と半分 (届く) の 2 か所に置く
	for case: Array in [
		[HandController.REACH_M * 2.0, HandController.REASON_OUT_OF_REACH, "遠い"],
		[HandController.REACH_M * 0.5, HandController.REASON_NO_HAIR, "手の届く"],
	]:
		# 上空で落ち続ける分を合わせるため、毎回その時の目線の光線の上に置く
		blocker.global_position = camera.global_position - camera.global_basis.z * float(case[0])
		await _checker.physics_frame
		_check(
			hand.pull_failure_reason() == case[1],
			"毛の付く表面の無い向きで、%s所の壁・家具にだけ光線が当たる時の理由が %s になる" % [case[2], case[1]],
		)
	blocker.queue_free()
	main.player.set_spawn(layout.spawn_position, layout.spawn_yaw)
	await _checker.physics_frame
	await _checker.physics_frame


## 引いている途中に道具を買う画面を開いた時と、マウスの捕捉が外れた時は、遊ぶ人が離したのではないので、
## 引くのをやめても照準の下に理由を出さないか。つまんでいる毛を手以外が取った時も、届かないのではないので出さないか
func _verify_no_reason_when_interrupted(main: Node3D, game_state: Node) -> void:
	var hand: HandController = main.hand
	for interruption: String in ["shop", "capture", "taken", "taken_and_released"]:
		if await HandAim.aim_at_floor_hair(_checker, main) < 0:
			_check(false, "中断の検証で床の毛を狙える")
			return
		main.tool_message_label.text = ""
		await _press_pluck()
		if not hand.is_pulling():
			_check(false, "中断の検証で毛をつまめる")
			Input.action_release(HandController.ACTION_PLUCK)
			return
		match interruption:
			"shop":
				main.toggle_tool_shop()
			"capture":
				hand.allow_uncaptured_pluck = false
			"taken", "taken_and_released":
				# 掃除ロボットなど、手以外が引いている途中の毛を取った時と同じく、つまんでいる毛を屋敷から消す
				for hair_id: int in hand.get_pulling_ids():
					main.mansion_world.get_hair_field().remove_hair(hair_id)
				if interruption == "taken_and_released":
					Input.action_release(HandController.ACTION_PLUCK)
		await _checker.process_frame
		await _checker.process_frame
		_check(
			not hand.is_pulling() and main.tool_message_label.text.is_empty(),
			{
				"shop": "引いている途中に道具を買う画面を開くと、引くのをやめ、照準の下に理由を出さない",
				"capture": "引いている途中にマウスの捕捉が外れると、引くのをやめ、照準の下に理由を出さない",
				"taken": "押したまま引いている途中に、つまんでいる毛が手以外に取られると、引くのをやめ、「届かない」を出さない",
				"taken_and_released":
				"つまんでいる毛が手以外に取られたのと同じ時に離しても、「途中で離した」を出さない",
			}[interruption],
		)
		Input.action_release(HandController.ACTION_PLUCK)
		match interruption:
			"shop":
				main.toggle_tool_shop()
			"capture":
				hand.allow_uncaptured_pluck = true
			"taken", "taken_and_released":
				# 毛の表示だけから消した毛を残り本数 (GameState) と合わせるため、屋敷を組み直す (図鑑の検証と同じ後始末)
				game_state.mansion_rebuilt.emit(game_state.current_layout)
		await _checker.process_frame


## 6 番の発言の別の読み: 道具を買う画面の「手の強化」のボタンを続けて 2 回押すと、2 回とも段が上がるか
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
	for needle: String in ["歩く", "視点", "押したまま", "持ち替える", "T: 道具を買う", "R: 掃除ロボット", "Esc: マウスを放す"]:
		listed = listed and text.contains(needle)
	_check(
		guide.is_controls_guide_visible() and listed,
		"屋敷に入った時に操作の一覧が出ていて、歩く・視点・押したまま抜く・持ち替え・道具を買う・掃除ロボット・マウスを放すが書いてある",
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


## 狙いを床の毛に向けた後、その周りの床を順に狙い、狙った所の GRAB_RADIUS_M 以内に毛が無い所で止める。止めたら true
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
				surface_index, target["point"], HandController.GRAB_RADIUS_M, 1
			).is_empty():
				return true
	return false


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
	await _press_pluck()
	var pulled_ids: PackedInt32Array = hand.get_pulling_ids()
	_check(
		hand.is_pulling() and pulled_ids.size() == 1
		and hair_field.find_hairs_near(
			surface_index, hair_field.get_hair_transform(pulled_ids[0]).origin, 0.001, 1
		) == pulled_ids,
		"狙った床の毛をつまむ入力で、その表面の毛を 1 本つまむ",
	)
	if pulled_ids.is_empty():
		Input.action_release(HandController.ACTION_PLUCK)
		return
	_check(
		is_equal_approx(
			hand.get_pull_duration(),
			HandRulesScript.pull_seconds(MansionLayoutScript.SURFACE_FLOOR, 0),
		),
		"強化していない手で床の毛を引き抜く時間が 0.45 秒",
	)
	_check(
		main.play_guide.is_pull_progress_visible() and main.play_guide.get_pull_progress_value() == 0.0,
		"つまんだ瞬間に、照準の下に引いている進み具合のゲージが 0 で出る",
	)
	hand.advance_pull(hand.get_pull_duration() * 0.5)
	_check(
		hand.get_pull_progress() >= 0.5 and hand.get_pull_progress() < 1.0
		and hand.get_hand_view().get_pull_progress() >= 0.5,
		"引いている途中は進み具合が 0.5 以上 1 未満で、画面の手も同じだけ引いている",
	)
	_check(
		main.play_guide.is_pull_progress_visible()
		and is_equal_approx(main.play_guide.get_pull_progress_value(), hand.get_pull_progress()),
		"引いている途中は、照準の下のゲージが手の進み具合と同じ値を出す",
	)
	Input.action_release(HandController.ACTION_PLUCK)
	await _checker.process_frame
	_check(
		not hand.is_pulling()
		and hair_field.has_hair(pulled_ids[0])
		and hand.get_hand_view().get_pull_progress() == 0.0
		and game_state.get_total_remaining_hairs() == before_total
		and game_state.get_raw_hair_stock_count() == before_stock,
		"途中で離すと毛は抜けずに残り、手が開き、残り本数と在庫が変わらない",
	)
	_check(
		not main.play_guide.is_pull_progress_visible()
		and main.tool_message_label.text
		== HandController.failure_message(HandController.REASON_RELEASED),
		"途中で離すと、進み具合のゲージが消え、照準の下に「途中で離したので毛が戻った」理由が出る",
	)

	# 押したまま、毛の根元までの距離が REACH_M より遠く REACH_M + GRAB_RADIUS_M 以内の所へ下がっても引き続け、
	# それより遠くへ離れると引くのをやめる
	await _press_pluck()
	var reach_ids: PackedInt32Array = hand.get_pulling_ids()
	var player: FirstPersonPlayer = main.player
	if reach_ids.is_empty():
		_check(false, "届く距離の境目の検証で毛をつまめる")
		Input.action_release(HandController.ACTION_PLUCK)
		return
	var reach_root: Vector3 = hair_field.get_hair_transform(reach_ids[0]).origin
	await _move_to_root_distance(
		player, reach_root, HandController.REACH_M + HandController.GRAB_RADIUS_M * 0.5
	)
	_check(
		hand.is_pulling(),
		"毛の根元まで 2.6m より遠く 2.68m 以内の所へ下がっても、つまんだ毛を引き続ける (届く距離の境目ですぐ離さない)",
	)
	await _move_to_root_distance(
		player, reach_root, HandController.REACH_M + HandController.GRAB_RADIUS_M * 1.5
	)
	_check(
		not hand.is_pulling()
		and hair_field.has_hair(reach_ids[0])
		and game_state.get_total_remaining_hairs() == before_total,
		"毛の根元まで 2.68m より遠くへ下がると、毛は抜けずに引くのをやめ、残り本数も変わらない",
	)
	_check(
		main.tool_message_label.text
		== HandController.failure_message(HandController.REASON_OUT_OF_REACH),
		"押したまま離れすぎて引くのをやめた時は、照準の下に「毛まで手が届かない」理由が出る",
	)
	Input.action_release(HandController.ACTION_PLUCK)
	if await HandAim.aim_at_floor_hair(_checker, main) != aimed_id:
		_check(false, "離れた後に同じ床の毛を狙い直せる")
		return

	# もう一度つまんで引き終えると 1 本抜ける
	var audio_manager: AudioManagerScript = (
		AudioManagerScript.resolve(_checker) as AudioManagerScript
	)
	await _press_pluck()
	var plucked_id: int = hand.get_pulling_ids()[0] if hand.is_pulling() else -1
	var plucked_color: StringName = world.get_hair_color_id(plucked_id)
	var surface_hair: SurfaceHair = game_state.save_data.building_progress.find_surface_hair(
		surface_def.surface_id
	)
	var before_color: int = surface_hair.count_for_color(plucked_color)
	var plucked: int = hand.advance_pull(hand.get_pull_duration())
	await _checker.process_frame
	Input.action_release(HandController.ACTION_PLUCK)
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
		not main.play_guide.is_pull_progress_visible() and main.tool_message_label.text.is_empty(),
		"抜くと進み具合のゲージが消え、照準の下に抜けなかった理由が残っていない",
	)
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
	await _press_pluck()
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
	Input.action_release(HandController.ACTION_PLUCK)
	await _checker.process_frame
	game_state.set_hand_upgrade_level(HandRulesScript.UPGRADE_DEXTERITY, 0)
	game_state.set_hand_upgrade_level(HandRulesScript.UPGRADE_GRAB_COUNT, 0)


## 押し続けるだけで (引く時間を直接進めずに) 毛が抜け、押したままでは次の毛を引き始めないか。
## マウスを捕捉していない時 (headless の検証の許可も無い時) はつままないか
func _verify_hold_plucks_and_capture_gate(main: Node3D, game_state: Node) -> void:
	var hand: HandController = main.hand
	if await HandAim.aim_at_floor_hair(_checker, main) < 0:
		_check(false, "押し続ける検証で床の毛を狙える")
		return
	var before_total: int = game_state.get_total_remaining_hairs()
	await _hold_until_plucked(hand)
	_check(
		game_state.get_total_remaining_hairs() == before_total - 1 and not hand.is_pulling(),
		"押し続けると引く時間の後に 1 本抜け、押したままでは次の毛を引き始めない",
	)
	Input.action_release(HandController.ACTION_PLUCK)
	await _checker.process_frame

	# 同じ起動の中で、離して狙い直し、もう一度押し続けると 2 本目も抜ける (1 本目の後に止まらない)
	if await HandAim.aim_at_floor_hair(_checker, main) < 0:
		_check(false, "1 本抜いた後に、次の床の毛を狙い直せる")
		return
	await _hold_until_plucked(hand)
	_check(
		game_state.get_total_remaining_hairs() == before_total - 2 and not hand.is_pulling(),
		"1 本抜いた後に離して狙い直し、もう一度押し続けると 2 本目も抜ける",
	)
	Input.action_release(HandController.ACTION_PLUCK)
	await _checker.process_frame

	hand.allow_uncaptured_pluck = false
	await _press_pluck()
	_check(
		not hand.is_pulling() and game_state.get_total_remaining_hairs() == before_total - 2,
		"マウスを捕捉していない時はつまむ入力で毛をつままない",
	)
	Input.action_release(HandController.ACTION_PLUCK)
	hand.allow_uncaptured_pluck = true
	await _checker.process_frame


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
	await _press_pluck()
	_check(
		hand.aim_target().is_empty() and not hand.is_pulling()
		and game_state.get_total_remaining_hairs() == before_total,
		"毛の面より手前に衝突体があると、狙いが空になりつまむ入力で何も変わらない",
	)
	_check(
		main.tool_message_label.text == HandController.failure_message(HandController.REASON_BLOCKED),
		"毛の面より手前に衝突体がある時につまむ入力をすると、照準の下に「手前に物があって」理由が出る",
	)
	Input.action_release(HandController.ACTION_PLUCK)
	blocker.queue_free()
	await _checker.physics_frame
	await _checker.physics_frame
	_check(not hand.aim_target().is_empty(), "手前の衝突体を取り除くと、同じ毛をまた狙える")
	await _checker.process_frame


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
	await _press_pluck()
	var plucked: int = hand.advance_pull(hand.get_pull_duration())
	Input.action_release(HandController.ACTION_PLUCK)
	await _checker.process_frame
	_check(
		plucked == 1
		and _rare_stock_count(game_state, HandRulesScript.RARE_WHISKER) == before_whisker + 1
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


## カメラから毛の根元 root までの距離が distance になる所へ、水平に root から離れる向きでプレイヤーを動かし、
## 目線を root へ向けて 2 フレーム進める (HandController の _process が新しい位置で距離を見る)
func _move_to_root_distance(player: FirstPersonPlayer, root: Vector3, distance: float) -> void:
	var camera_position: Vector3 = player.get_camera().global_position
	var height: float = camera_position.y - root.y
	var away: Vector3 = (
		Vector3(camera_position.x - root.x, 0.0, camera_position.z - root.z).normalized()
	)
	var camera_target: Vector3 = (
		Vector3(root.x, camera_position.y, root.z)
		+ away * sqrt(maxf(0.0, distance * distance - height * height))
	)
	player.set_spawn(player.global_position + camera_target - camera_position, 0.0)
	player.look_at_point(root)
	await _checker.process_frame
	await _checker.process_frame


## つまむ入力を押し、HandController の _process がその押下を処理した直後まで進める。
## process_frame は各ノードの _process より前に出るため、まず process_frame に合わせてから押し、
## もう 1 回 process_frame を待つと、その間の _process が押下を見る
func _press_pluck() -> void:
	await _checker.process_frame
	Input.action_press(HandController.ACTION_PLUCK)
	await _checker.process_frame


## つまむ入力を押し、引く時間を直接進めずに、抜けるまで (上限 600 フレーム) 押し続ける (離さずに返る)。
## 実時間で 0.45 秒待つとフレーム数の上限 (Makefile の SCRIPT_FRAME_LIMIT) を使うため、時間の進みを 20 倍にする
func _hold_until_plucked(hand: HandController) -> void:
	Engine.time_scale = 20.0
	await _press_pluck()
	var held_frames: int = 0
	while hand.is_pulling() and held_frames < 600:
		await _checker.process_frame
		held_frames += 1
	for _step: int in range(5):
		await _checker.process_frame
	Engine.time_scale = 1.0


## つまむ入力を指定フレーム数だけ押し続けてから離す
func _hold_pluck(frame_count: int) -> void:
	Input.action_press(HandController.ACTION_PLUCK)
	for _step: int in range(frame_count):
		await _checker.process_frame
	Input.action_release(HandController.ACTION_PLUCK)
	await _checker.process_frame

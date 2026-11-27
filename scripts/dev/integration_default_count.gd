extends RefCounted
## 既定の毛の本数 (9,999,999 本) で新しく始めた屋敷の入力統合テスト (scripts/dev/integration.gd から呼ぶ)。
## 1 本ずつ描く毛は描く本数の上限 (HairField.DEFAULT_DRAW_BUDGET) までで、残りは埋もれた毛として数だけ持つ。
## その屋敷で手で 1 本抜くと残り本数が 9,999,998 本になり、描いている毛の本数は埋もれた毛から描き足されて変わらないこと、
## 粘着ローラーを床にかけると取れた本数だけ残り本数が減ることを確かめる (issue #65)。

## 手の強化と、引く時間の下限。
const HandRulesScript := preload("res://scripts/hand/hand_rules.gd")
## 目線を床の毛へ向ける手順
const HandAim := preload("res://scripts/dev/hand_aim.gd")
## 手に持って使う道具の定義
const ToolCatalogScript := preload("res://scripts/tools/tool_catalog.gd")
## 毛の描画・管理 (描く本数の上限の既定値)
const HairFieldScript := preload("res://scripts/hair_field.gd")
## 道具を床にかける時の、粘着ローラーの半径の中に要る毛の本数 (取れる毛が出るだけの本数)
const MIN_HAIRS_IN_RANGE: int = 2
## 取りこぼしの抽選の乱数のシード (結果を固定する)
const TOOL_RNG_SEED: int = 20261127
## 道具を買う時に持たせるお金 (粘着ローラーの値段より多い額)
const TEST_MONEY: int = 1000

## 検証結果を記録する integration の SceneTree 参照
var _checker: SceneTree = null


## 既定の毛の本数の屋敷の検証をすべて実行する (main は既定の調整値で新しく始めたメインシーン)。
## 終わったら手に持ち替え、持たせたお金を 0 に戻す
static func run_all(checker: SceneTree, main: Node3D, game_state: Node) -> void:
	var suite: RefCounted = load("res://scripts/dev/integration_default_count.gd").new()
	suite._checker = checker
	main.hand.allow_uncaptured_pluck = true
	main.tools.allow_uncaptured_use = true
	main.tools.set_rng_seed(TOOL_RNG_SEED)
	await checker.process_frame
	suite._verify_fresh_counts(main, game_state)
	await suite._verify_hand_pluck(main, game_state)
	await suite._verify_sofa_resistance(main)
	await suite._verify_roller_sweep(main, game_state)
	await suite._verify_simultaneous_removal(main, game_state)
	main.hand.allow_uncaptured_pluck = false
	main.tools.allow_uncaptured_use = false
	Input.action_release(HandController.ACTION_PLUCK)
	await checker._press_physical_key(ToolController.SELECT_KEYS[0])
	game_state.save_data.building_progress.money = 0
	await checker.process_frame


## 検証結果を integration 本体へ記録する
func _check(cond: bool, label: String) -> void:
	_checker._check(cond, label)


## 新しく始めた屋敷の残り本数が 9,999,999 本で、描いている毛は描く本数の上限までか。
## 期待値は issue #65 の完了条件の本数 (9,999,999 と 9,999,998) を、実装の定数から取らずに書く
func _verify_fresh_counts(main: Node3D, game_state: Node) -> void:
	var hair_field: Node3D = main.mansion_world.get_hair_field()
	var drawn: int = HairFieldScript.count_drawn_hairs(hair_field)
	_check(
		game_state.get_total_remaining_hairs() == 9999999
		and hair_field.get_remaining_count() == 9999999
		and drawn > 0 and drawn <= HairFieldScript.DEFAULT_DRAW_BUDGET,
		"既定の調整値で始めた屋敷は残り 9,999,999 本で、描いている毛は上限 %d 本まで (残り %d 本・描いている %d 本)"
		% [HairFieldScript.DEFAULT_DRAW_BUDGET, game_state.get_total_remaining_hairs(), drawn],
	)

	var floor_surface: MansionLayout.SurfaceDef = game_state.current_layout.surfaces[0]
	var footprints: Array[Dictionary] = MansionWorld._object_footprints_in_room(
		game_state.current_layout, floor_surface)
	for obj: MansionLayout.ObjectDef in game_state.current_layout.objects:
		if obj.object_kind != MansionLayout.OBJECT_SUIT_RACK:
			continue
		var model: Node3D = main.mansion_world.get_node("ObjectsRoot/" + String(obj.object_id))
		_check(model.has_node("WallHook") == obj.wall_mounted
			and model.has_node("Base") != obj.wall_mounted and model.has_node("Pole") != obj.wall_mounted,
			"壁掛けの上着にはフック、床置きの上着には台と支柱がある")
		if obj.wall_mounted:
			var covers_floor: bool = false
			for footprint: Dictionary in footprints:
				var inverse: Transform3D = footprint["inverse"]
				if inverse.affine_inverse().origin.is_equal_approx(obj.position):
					covers_floor = true
			_check(not covers_floor, "壁掛けのスーツの真下には床の毛を置ける")


## 手で 1 本抜くと残り本数が 9,999,998 本になり、描いている毛の本数は変わらないか
func _verify_hand_pluck(main: Node3D, game_state: Node) -> void:
	var hand: HandController = main.hand
	var hair_field: Node3D = main.mansion_world.get_hair_field()
	var aimed: int = await HandAim.aim_at_floor_hair(_checker, main)
	if aimed < 0:
		_check(false, "既定の本数の屋敷で床の毛を狙える")
		return
	var drawn_before: int = HairFieldScript.count_drawn_hairs(hair_field)
	await _checker.process_frame
	Input.action_press(HandController.ACTION_PLUCK)
	await _checker.process_frame
	var plucked: int = hand.advance_pull(hand.get_pull_duration())
	Input.action_release(HandController.ACTION_PLUCK)
	await _checker.process_frame
	_check(
		plucked == 1
		and game_state.get_total_remaining_hairs() == 9999998
		and hair_field.get_remaining_count() == 9999998
		and not hair_field.has_hair(aimed)
		and HairFieldScript.count_drawn_hairs(hair_field) == drawn_before,
		"既定の本数の屋敷で手で 1 本抜くと残り 9,999,998 本になり、描いている毛は埋もれた毛から描き足されて %d 本のまま (実際: 残り %d 本・描いている %d 本)"
		% [
			drawn_before,
			game_state.get_total_remaining_hairs(),
			HairFieldScript.count_drawn_hairs(hair_field),
		],
	)


## 同じ手で床とソファの毛を照準からつまみ、抜けるまでの時間を同じ刻みで比べる。
func _verify_sofa_resistance(main: Node3D) -> void:
	var hand: HandController = main.hand
	var floor_steps: int = 0
	for kind: StringName in [MansionLayout.SURFACE_FLOOR, MansionLayout.SURFACE_SOFA]:
		var aimed: int = await HandAim.aim_at_first_room_hair(_checker, main, kind)
		await _checker.process_frame
		Input.action_press(HandController.ACTION_PLUCK)
		await _checker.process_frame
		var ids: PackedInt32Array = hand.get_pulling_ids()
		var steps: int = 0
		var plucked: int = 0
		# 1/120 秒刻みで 2 秒まで。描画フレームの所要時間に依存せず、実際に 1 本減るまでを測る。
		while hand.is_pulling() and steps < 240:
			plucked = hand.advance_pull(1.0 / 120.0)
			steps += 1
		Input.action_release(HandController.ACTION_PLUCK)
		await _checker.process_frame
		_check(
			aimed >= 0 and ids == PackedInt32Array([aimed]) and plucked == 1,
			"%s の照準で選んだ毛が 1 本抜ける" % kind,
		)
		if kind == MansionLayout.SURFACE_FLOOR:
			floor_steps = steps
		else:
			_check(
				floor_steps > 0 and steps > floor_steps,
				"同じ手でソファの毛を抜き終えるまでが床より長い (床 %d 刻み・ソファ %d 刻み)" % [floor_steps, steps],
			)


## 粘着ローラーを買って床にかけると、取れた本数だけ残り本数が減るか
func _verify_roller_sweep(main: Node3D, game_state: Node) -> void:
	var roller: StringName = ToolCatalogScript.TOOL_LINT_ROLLER
	game_state.save_data.building_progress.money = TEST_MONEY
	main.open_tool_shop()
	await _checker.process_frame
	main.tool_shop_panel.get_tool_button(roller).pressed.emit()
	await _checker.process_frame
	main.close_tool_shop()
	await _checker._press_physical_key(
		ToolController.SELECT_KEYS[ToolCatalogScript.selectable_tool_ids().find(roller)]
	)
	if (
		await HandAim.aim_at_floor_hairs(
			_checker, main, float(ToolCatalogScript.find_tool(roller)["radius_m"]), MIN_HAIRS_IN_RANGE
		)
		< 0
	):
		_check(false, "既定の本数の屋敷で粘着ローラーをかける床の毛を狙える")
		return
	var hair_field: Node3D = main.mansion_world.get_hair_field()
	var total_before: int = game_state.get_total_remaining_hairs()
	var field_before: int = hair_field.get_remaining_count()
	var drawn_before: int = HairFieldScript.count_drawn_hairs(hair_field)
	var captured: Array[Dictionary] = []
	var on_used: Callable = func(result: Dictionary) -> void: captured.append(result)
	main.tools.tool_used.connect(on_used)
	await _checker.press_and_release_use()
	main.tools.tool_used.disconnect(on_used)
	var removed: int = int(captured[0]["removed"]) if not captured.is_empty() else 0
	_check(
		removed > 0
		and total_before - game_state.get_total_remaining_hairs() == removed
		and field_before - hair_field.get_remaining_count() == removed
		and HairFieldScript.count_drawn_hairs(hair_field) == drawn_before,
		"既定の本数の屋敷で粘着ローラーを床にかけると、取れた %d 本だけ残り本数が減り、描いている毛は %d 本のまま (実際: 残り %d → %d 本)"
		% [removed, drawn_before, total_before, game_state.get_total_remaining_hairs()],
	)


## 複数本をつまんでから他の掃除が先に取った時は、手元に残った本数だけを抜く。
func _verify_simultaneous_removal(main: Node3D, game_state: Node) -> void:
	var hand: HandController = main.hand
	var field: Node3D = main.mansion_world.get_hair_field()
	game_state.set_hand_upgrade_level(HandRulesScript.UPGRADE_GRAB_COUNT, 1)
	# 引く時間が下限に達するまで器用さを上げ、速い手でも前半で毛先を挟むことを確かめる。
	game_state.set_hand_upgrade_level(HandRulesScript.UPGRADE_DEXTERITY, 20)
	for remaining: int in [1, 0]:
		if await HandAim.aim_at_floor_hairs(_checker, main, HandController.GRAB_RADIUS_M, 2) < 0:
			_check(false, "同時につまめる床の毛が 2 本ある")
			break
		var target: Dictionary = hand.aim_target()
		hand.begin_pull_at(target)
		var ids: PackedInt32Array = hand.get_pulling_ids()
		if ids.size() != 2:
			_check(false, "同時に 2 本をつまみ、そのうち何本が残るかを試せる")
			break
		var surface: MansionLayout.SurfaceDef = main.mansion_world.get_surface_def(target.surface_index)
		for i: int in range(ids.size() - remaining):
			game_state.pluck_hair(surface.surface_id, main.mansion_world.get_hair_color_id(ids[i]), &"")
			field.remove_hair(ids[i])
		hand.advance_pull(hand.get_pull_duration() * 0.5)
		if remaining == 1:
			var tip: Vector3 = field.get_hair_transform(ids[1]) * HairFieldScript.HAIR_TIP
			_check(is_equal_approx(hand.get_pull_duration(), HandRulesScript.MIN_PULL_SECONDS)
				and hand.get_hand_view().get_pinch_position().is_equal_approx(tip),
				"最短の引く時間の半分で、残った毛の先に両指がそろう")
		var before: int = game_state.get_total_remaining_hairs()
		_check(hand.advance_pull(hand.get_pull_duration()) == remaining
			and game_state.get_total_remaining_hairs() == before - remaining,
			"他の掃除の後、手は残った %d 本だけを取る" % remaining)
		_check(hand.get_hand_view().get_node("PluckedHair").visible == (remaining > 0),
			"手が空の時には抜いた毛のメッシュを表示しない")
	game_state.set_hand_upgrade_level(HandRulesScript.UPGRADE_DEXTERITY, 0)
	game_state.set_hand_upgrade_level(HandRulesScript.UPGRADE_GRAB_COUNT, 0)

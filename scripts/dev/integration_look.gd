extends RefCounted
## 見た目の試作 (issue #19) の入力統合テスト (scripts/dev/integration.gd から呼ぶ)。

## 開発者向け調整値データ型スクリプト (部屋の幅の既定値の単一の正)
const MansionTuningScript := preload("res://scripts/data/mansion_tuning.gd")


## 見た目の試作が、歩いている間に最初の部屋の中にいる時だけ環境を切り替えることを検証する。
## 終わる時はプレイヤーを最初の位置へ戻し、試作を重ね直す (後に続く手で毛を取る操作の検証の前提をそろえるため)。
## checker は結果を記録してフレームを進める integration の SceneTree
static func verify_look_prototype_room(checker: SceneTree, main: Node3D, game_state: Node) -> void:
	var player: FirstPersonPlayer = main.get_node("Player")
	var environment_node: WorldEnvironment = main.get_node("WorldEnvironment")
	var look_room: LookPrototypeRoom = main.look_room
	var layout: MansionLayout = game_state.current_layout
	player.set_spawn(layout.spawn_position, layout.spawn_yaw)
	await checker.process_frame
	var inside_environment: Environment = environment_node.environment
	checker._check(
		look_room.is_prototype_active() and environment_node.environment.ssao_enabled,
		"最初の部屋に立つと試作の環境 (家具の陰あり) が出る",
	)
	checker._check(
		main.look_hud.get_money_text()
		== "所持金 %s 円" % main.format_hair_count(game_state.get_money())
		and main.look_hud.get_parent() == main.get_node("UILayer/UI/HUD"),
		"HUD に GameState の所持金が 3 桁区切りで出る (%s)" % main.look_hud.get_money_text(),
	)
	# 試作の見た目を出している間に setup をもう一度呼んでも、試作の環境を部屋の外の環境として取り込まない
	look_room.setup(player, environment_node)
	await checker.process_frame

	player.global_position = Vector3(0.0, 0.05, -MansionTuningScript.DEFAULT_ROOM_SIZE_M)
	await checker.process_frame
	checker._check(
		not look_room.is_prototype_active()
		and environment_node.environment != inside_environment
		and not environment_node.environment.ssao_enabled,
		"隣の部屋に移ると試作の環境が消え、環境が既定 (家具の陰なし) に戻る",
	)

	# 試作の見た目を出していない時に setup を呼ぶと、その時の環境を既定の環境として取り込み直す
	var original_environment: Environment = environment_node.environment
	var replaced_environment: Environment = Environment.new()
	environment_node.environment = replaced_environment
	look_room.setup(player, environment_node)
	player.set_spawn(layout.spawn_position, layout.spawn_yaw)
	await checker.process_frame
	player.global_position = Vector3(0.0, 0.05, -MansionTuningScript.DEFAULT_ROOM_SIZE_M)
	await checker.process_frame
	checker._check(
		environment_node.environment == replaced_environment,
		"試作の見た目を出していない時の setup は、その時の環境を部屋の外の環境として取り込む",
	)
	environment_node.environment = original_environment
	look_room.setup(player, environment_node)

	# 最初の部屋の中にいても、タイトルの画面 (歩いていない間) では試作の環境を出さない。main.gd の画面の切り替えを通す
	player.set_spawn(layout.spawn_position, layout.spawn_yaw)
	main._set_title_mode()
	await checker.process_frame
	checker._check(
		not look_room.is_prototype_active() and not environment_node.environment.ssao_enabled,
		"最初の部屋の中でも、タイトルの画面では試作の環境を出さない",
	)
	main.enter_mansion()
	await checker.process_frame
	checker._check(
		look_room.is_prototype_active(),
		"タイトルから屋敷へ戻ると、最初の部屋で試作の環境がまた出る",
	)

	# 歩いていて最初の部屋の位置にいても、重ねる部屋が無いレイアウトの後は試作の環境を出さない
	look_room.apply(null, null)
	await checker.process_frame
	checker._check(
		not look_room.is_prototype_active() and not environment_node.environment.ssao_enabled,
		"重ねる部屋が無い時は、歩いていても試作の環境を出さない",
	)
	look_room.apply(layout, main.mansion_world)
	player.set_spawn(layout.spawn_position, layout.spawn_yaw)
	await checker.process_frame

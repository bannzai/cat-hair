extends RefCounted
## 見た目の試作 (issue #19) の入力統合テスト (scripts/dev/integration.gd から呼ぶ)。

## 開発者向け調整値データ型スクリプト (部屋の幅の既定値の単一の正)
const MansionTuningScript := preload("res://scripts/data/mansion_tuning.gd")


## 見た目の試作が最初の部屋の中にいる間だけ環境・手を切り替え、つまむ構図で伸びた毛が指先から床へ張られることを検証する
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
		look_room.is_prototype_active() and look_room.get_hand().visible,
		"最初の部屋に立つと試作の見た目 (環境と手) が出る",
	)
	checker._check(
		main.look_hud.get_money_text() == "所持金 1,280 円"
		and main.look_hud.get_parent() == main.get_node("UILayer/UI/HUD"),
		"HUD に見本の所持金が 3 桁区切りで出る (%s)" % main.look_hud.get_money_text(),
	)
	# 同じプレイヤーで setup をもう一度呼んでも、カメラに付く手は 1 つのまま
	look_room.setup(player, environment_node)
	var hand_count: int = 0
	for child: Node in player.get_camera().get_children():
		if child is FirstPersonHand:
			hand_count += 1
	checker._check(hand_count == 1, "setup を 2 回呼んでもカメラの手は 1 つ (%d)" % hand_count)
	await checker.process_frame

	player.global_position = Vector3(0.0, 0.05, -MansionTuningScript.DEFAULT_ROOM_SIZE_M)
	await checker.process_frame
	checker._check(
		not look_room.is_prototype_active()
		and not look_room.get_hand().visible
		and environment_node.environment != inside_environment
		and not environment_node.environment.ssao_enabled,
		"隣の部屋に移ると試作の見た目が消え、環境が既定 (家具の陰なし) に戻る",
	)

	player.set_spawn(layout.spawn_position, layout.spawn_yaw)
	look_room.set_pinch_pose(true)
	await checker.process_frame
	var ends: PackedVector3Array = look_room.get_hand().get_stretched_hair_endpoints()
	var hair_mesh_transform: Transform3D = look_room.get_hand().get_stretched_hair_transform()
	# 毛のメッシュは高さ 1 の円柱なので、メッシュの中心が両端の中点に、Y 軸の長さが両端の距離になっていれば張られている
	checker._check(
		ends.size() == 2
		and ends[0].y > ends[1].y
		and ends[1].y < 0.01
		and hair_mesh_transform.origin.is_equal_approx((ends[0] + ends[1]) * 0.5)
		and is_equal_approx(hair_mesh_transform.basis.y.length(), ends[0].distance_to(ends[1])),
		"つまむ構図の伸びた毛のメッシュは指先から床へ張られる (%s)" % [ends],
	)
	look_room.set_pinch_pose(false)

	# 最初の部屋の中にいても、タイトルの画面 (歩いていない間) では試作の見た目を出さない
	look_room.set_playing(false)
	await checker.process_frame
	checker._check(
		not look_room.is_prototype_active()
		and not look_room.get_hand().visible
		and not environment_node.environment.ssao_enabled,
		"最初の部屋の中でも、歩いていない間は試作の見た目を出さない",
	)
	look_room.set_playing(true)
	await checker.process_frame

	# 歩いていて最初の部屋の位置にいても、重ねる部屋が無いレイアウトの後は試作の見た目を出さない
	look_room.apply(null, null, null)
	await checker.process_frame
	checker._check(
		not look_room.is_prototype_active()
		and not look_room.get_hand().visible
		and not environment_node.environment.ssao_enabled,
		"重ねる部屋が無い時は、歩いていても試作の見た目を出さない",
	)
	look_room.apply(
		layout, game_state.save_data.building_progress, main.mansion_world
	)
	await checker.process_frame

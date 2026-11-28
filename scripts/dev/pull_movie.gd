extends SceneTree
## 最初の部屋で床・壁の上着・ソファへ歩き、各面で 1 本をクリックして取る操作を録画する。

## 撮影対象を、実際に届く距離から狙う。
const HandAim := preload("res://scripts/dev/hand_aim.gd")
## 録画と入力テストの音・状態の初期化を共通にする。
const HeadlessCheck := preload("res://scripts/dev/headless_check.gd")
## 録画専用データの作成前と終了後に使う。
const SaveStorageScript := preload("res://scripts/state/save_storage.gd")
## 通常起動と同じ屋敷を操作する。
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
## 普段のプレイと独立した録画用のセーブ先。
const SAVE_PATH: String = "user://pull_movie_save_data.json"
## 普段の音量設定を使わずに撮るための設定先。
const AUDIO_SETTINGS: String = "res://tmp/pull-movie-audio.cfg"
## つまめる位置の少し後ろから、数歩を撮って停止する距離 (m)
const APPROACH_DISTANCE: float = 0.65


## シーンツリーの初期化後に録画を開始する。
func _initialize() -> void:
	_run.call_deferred()


## 録画専用のセーブから毎回始め、音とセーブを片付けてから結果を返す
func _run() -> void:
	var settings_path: String = ProjectSettings.globalize_path(AUDIO_SETTINGS)
	var audio: Dictionary = HeadlessCheck.prepare_audio_manager(self, settings_path)
	SaveStorageScript.delete_save_file(SAVE_PATH)
	HeadlessCheck.acquire_game_state(root, SAVE_PATH)
	var main: Node3D = MAIN_SCENE.instantiate()
	main.auto_advance_automation = false
	root.add_child(main)
	current_scene = main
	await process_frame
	main.enter_mansion()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	await process_frame
	await process_frame
	var ok: bool = true
	for surface: StringName in [MansionLayout.SURFACE_FLOOR, MansionLayout.SURFACE_SUIT,
			MansionLayout.SURFACE_SOFA]:
		if not await _record_surface(main, surface):
			push_error("最初の部屋の %s の操作を録画できない" % surface)
			ok = false
			break
	_mouse_button(false)
	Input.action_release("move_forward")
	audio.manager.stop_all()
	await HeadlessCheck.wait_audio_release(self)
	HeadlessCheck.cleanup_audio_manager(self, audio, settings_path)
	main.free()
	SaveStorageScript.delete_save_file(SAVE_PATH)
	if ok:
		print("pull movie OK")
	quit(0 if ok else 1)


## 本物の照準とクリックで毛が取れた前後を撮り、対応するコマの番号を残す
func _record_surface(main: Node3D, surface: StringName) -> bool:
	var hair: int = await HandAim.aim_at_first_room_hair(self, main, surface)
	if hair < 0:
		push_error("撮影対象の毛を照準に合わせられない")
		return false
	var field: Node3D = main.mansion_world.get_hair_field()
	var target: Vector3 = field.get_hair_transform(hair).origin
	var player: FirstPersonPlayer = main.player
	if not await _walk_and_aim(player, target):
		return false
	var before: int = main.get_game_state().get_total_remaining_hairs()
	await process_frame
	_mark(surface, "before")
	_mouse_button(true)
	_mouse_button(false)
	await process_frame
	await process_frame
	_mark(surface, "detached")
	if field.has_hair(hair) or main.get_game_state().get_total_remaining_hairs() != before - 1:
		push_error("クリック 1 回で狙った毛が 1 本取れない")
		return false
	await create_timer(0.7).timeout
	return true


## 照準を合わせた位置まで前進し、マウス移動で目線を下げる。途中の壁や家具で進めない時は失敗とする
func _walk_and_aim(player: FirstPersonPlayer, target: Vector3) -> bool:
	var destination: Vector3 = player.global_position
	var back: Vector3 = player.global_basis.z
	player.set_spawn(destination + back * APPROACH_DISTANCE, player.rotation.y)
	Input.action_press("move_forward")
	var reached: bool = false
	for _step: int in range(Engine.physics_ticks_per_second):
		await physics_frame
		var remaining: float = (player.global_position - destination).dot(back)
		if remaining <= player.move_speed / Engine.physics_ticks_per_second:
			reached = true
			break
	Input.action_release("move_forward")
	if not reached:
		push_error("撮影位置まで歩けない")
		return false
	await process_frame
	for step: int in range(8, 0, -1):
		var direction: Vector3 = target - player.get_camera().global_position
		var yaw: float = atan2(-direction.x, -direction.z)
		var pitch: float = atan2(direction.y, Vector2(direction.x, direction.z).length())
		var motion: InputEventMouseMotion = InputEventMouseMotion.new()
		motion.relative = Vector2(
			-angle_difference(player.rotation.y, yaw), player.get_pitch() - pitch
		) / (player.mouse_sensitivity * step)
		Input.parse_input_event(motion)
		Input.flush_buffered_events()
		await process_frame
	await create_timer(0.25).timeout
	await process_frame
	return true


## 左ボタンを実際の入力経路に送り、このフレームの手の処理が読める状態にする
func _mouse_button(pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


## process_frame では直前に描いた画面が録画済みなので、その 0 起点の番号を記す
func _mark(surface: StringName, stage: String) -> void:
	print("PULL_FRAME %s-%s %d" % [surface, stage, Engine.get_frames_drawn() - 1])

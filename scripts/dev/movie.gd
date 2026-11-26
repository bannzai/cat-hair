extends SceneTree
## 操作なしの起動〜メインシーン表示を Movie Maker モードで録画する (Makefile の movie target)。
## 引数に --automation を付けると、屋敷に入って掃除ロボットを 2 台置き、猫と掃除ロボットの時計を速めて
## 掃除ロボットが毛を取り残り本数が減る様子を録画する (Makefile の movie-automation target)。
## Godot 4.7.2-stable (ubuntu-24.04 / --audio-driver Dummy / --write-movie) の CI 実測
## (run 45767272708) で、再生中 BGM のまま --quit-after で終了すると ObjectDB 4 件・Resource 2 件の
## リーク警告が出たため、終了直前に stop_all() してフレームを進めて解放する (run 45767858306 で解消)。

## AudioManager の準備・後始末を借りる検証の土台
const HeadlessCheck := preload("res://scripts/dev/headless_check.gd")
## 録画するメインシーン
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
## 音声管理ノード (AUDIO_RELEASE_TIME_SEC の単一の正と型解決用)
const AudioManagerScript := preload("res://scripts/audio/audio_manager.gd")
## 音声解放待ちの切り上げフレーム数へ足す余裕 (AUDIO_RELEASE_TIME_SEC ちょうどの端数ズレ吸収用)
const RELEASE_MARGIN_FRAMES: int = 2
## Makefile の --quit-after と本スクリプトの quit(0) が同一フレームで競合しないための余裕フレーム数
const END_MARGIN_FRAMES: int = 2
## 掃除ロボットの録画で、猫と掃除ロボットの時計を実時間の何倍で進めるか。10 秒の録画で掃除ロボットが
## 1 部屋に留まる 20 秒を超え、毛を取る様子と残り本数の減り方が見える倍率
const AUTOMATION_SPEED: float = 4.0
## 掃除ロボットの録画で置く台数 (同じ部屋を回らせ、取る量を目で追える数にする)
const AUTOMATION_ROBOTS: int = 2
## 掃除ロボットの録画で、部屋の中心から離れて立つ距離の割合 (部屋の短い辺の半分に対する比率)
const AUTOMATION_VIEW_RATIO: float = 0.7
## JSON 保存ストレージスクリプト (掃除ロボットの録画の一時セーブを消す)
const SaveStorageScript := preload("res://scripts/state/save_storage.gd")
## 掃除ロボットの録画だけが使う一時セーブのパス (遊んでいる人のセーブと分ける)
const AUTOMATION_SAVE_PATH: String = "user://movie_automation_save_data.json"
## 掃除ロボットの値段の定数
const RobotRulesScript := preload("res://scripts/automation/robot_rules.gd")
## 部屋の中心との間に家具を挟まずに立つ所を選ぶ手順
const ViewPointScript := preload("res://scripts/dev/view_point.gd")


## コマンドライン引数から prefix=<正の整数> を取り出す。未指定・空・非数値・0 以下は -1 を返す
static func parse_positive_int_arg(args: PackedStringArray, prefix: String) -> int:
	for arg: String in args:
		if not arg.begins_with(prefix):
			continue
		var raw: String = arg.substr(prefix.length())
		if not raw.is_valid_int():
			return -1
		var parsed: int = raw.to_int()
		return parsed if parsed > 0 else -1
	return -1


## コマンドライン引数から --frames と --fps の両方が正の整数で揃う時だけ辞書で返し、欠落・不正時は空辞書を返す
static func parse_movie_options(args: PackedStringArray) -> Dictionary:
	var total_frames: int = parse_positive_int_arg(args, "--frames=")
	var fps: int = parse_positive_int_arg(args, "--fps=")
	if total_frames <= 0 or fps <= 0:
		return {}
	return {"total_frames": total_frames, "fps": fps}


## 固定 FPS から AudioServer 解放待ちに必要なフレーム数を算出する (AUDIO_RELEASE_TIME_SEC が単一の正)
static func calc_release_frames(fps: int) -> int:
	return (
		int(ceil(AudioManagerScript.AUDIO_RELEASE_TIME_SEC * float(maxi(1, fps))))
		+ RELEASE_MARGIN_FRAMES
	)


## 録画 1 フレーム + 音声解放待ち + 終了余裕を含めた最小の総フレーム数を返す
static func calc_min_total_frames(release_frames: int) -> int:
	return release_frames + END_MARGIN_FRAMES + 1


## 総フレーム数から解放待ちと終了余裕を引いた通常録画のフレーム数を返す (予算不足時は 0)
static func calc_record_frames(total_frames: int, release_frames: int) -> int:
	return maxi(0, total_frames - release_frames - END_MARGIN_FRAMES)


## tree の準備が終わってから _run() を始める
func _initialize() -> void:
	_run.call_deferred()


## メインシーンを配置して録画し、終了前に音を止めて解放を待ってから終える
func _run() -> void:
	var user_args: PackedStringArray = OS.get_cmdline_user_args()
	var options: Dictionary = parse_movie_options(user_args)
	if options.is_empty():
		push_error("movie.gd には正の --frames=<N> と --fps=<N> が必要 (引数: %s)" % str(user_args))
		quit(1)
		return

	var total_frames: int = int(options["total_frames"])
	var release_frames: int = calc_release_frames(int(options["fps"]))
	var record_frames: int = calc_record_frames(total_frames, release_frames)
	if record_frames <= 0:
		var min_frames: int = calc_min_total_frames(release_frames)
		push_error(
			"movie.gd の --frames=%d が不足しています (最小 %d フレーム必要)"
			% [total_frames, min_frames]
		)
		quit(1)
		return

	var settings_path: String = ProjectSettings.globalize_path(
		"res://tmp/movie-audio-settings.cfg"
	)
	var audio_handle: Dictionary = HeadlessCheck.prepare_audio_manager(self, settings_path)

	var automation_mode: bool = user_args.has("--automation")
	if automation_mode:
		# 遊んでいる人のセーブ (買った掃除ロボットの台数など) に左右されず、毎回はじめからの屋敷で録る
		SaveStorageScript.delete_save_file(AUTOMATION_SAVE_PATH)
		HeadlessCheck.acquire_game_state(root, AUTOMATION_SAVE_PATH)
	var main: Node3D = MAIN_SCENE.instantiate()
	if automation_mode:
		main.auto_advance_automation = false
	root.add_child(main)
	current_scene = main
	if automation_mode and not await _stage_automation(main):
		SaveStorageScript.delete_save_file(AUTOMATION_SAVE_PATH)
		quit(1)
		return

	for _i: int in range(record_frames):
		if automation_mode:
			main.get_game_state().automation.advance(
				AUTOMATION_SPEED / float(int(options["fps"]))
			)
		await process_frame
	(audio_handle["manager"] as AudioManagerScript).stop_all()
	for _i: int in range(release_frames):
		await process_frame
	HeadlessCheck.cleanup_audio_manager(self, audio_handle, settings_path)
	if automation_mode:
		SaveStorageScript.delete_save_file(AUTOMATION_SAVE_PATH)
	print("movie OK")
	quit(0)


## 屋敷に入り、最初の部屋を回る掃除ロボットを AUTOMATION_ROBOTS 台置いて、家具を挟まない所から部屋の中心を見下ろす。置けたら true
func _stage_automation(main: Node3D) -> bool:
	await process_frame
	main.enter_mansion()
	var game_state: Node = main.get_game_state()
	var room: MansionLayout.RoomDef = game_state.current_layout.rooms[0]
	game_state.save_data.building_progress.money = RobotRulesScript.ROBOT_PRICE * AUTOMATION_ROBOTS
	for _robot: int in range(AUTOMATION_ROBOTS):
		if not game_state.automation.buy_robot(room.room_id):
			push_error("movie.gd: 掃除ロボットを置けない")
			return false
	var corner: Vector3 = ViewPointScript.clear_spot(
		game_state.current_layout, room, room.center,
		minf(room.size.x, room.size.z) * 0.5 * AUTOMATION_VIEW_RATIO, Vector3(1.0, 0.0, 1.0)
	)
	main.player.set_spawn(corner, 0.0)
	await physics_frame
	main.player.look_at_point(room.center)
	return true

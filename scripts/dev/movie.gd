extends SceneTree
## 操作なしの起動〜メインシーン表示を Movie Maker モードで録画する (Makefile の movie target)。
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


## 総フレーム数から解放待ちと終了余裕を引いた通常録画のフレーム数を返す (最小 1)
static func calc_record_frames(total_frames: int, release_frames: int) -> int:
	return maxi(1, total_frames - release_frames - END_MARGIN_FRAMES)


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

	var settings_path: String = ProjectSettings.globalize_path(
		"res://tmp/movie-audio-settings.cfg"
	)
	var audio_handle: Dictionary = HeadlessCheck.prepare_audio_manager(self, settings_path)

	var main: Control = MAIN_SCENE.instantiate()
	root.add_child(main)
	current_scene = main

	var release_frames: int = calc_release_frames(int(options["fps"]))
	for _i: int in range(calc_record_frames(int(options["total_frames"]), release_frames)):
		await process_frame
	(audio_handle["manager"] as AudioManagerScript).stop_all()
	for _i: int in range(release_frames):
		await process_frame
	HeadlessCheck.cleanup_audio_manager(self, audio_handle, settings_path)
	print("movie OK")
	quit(0)

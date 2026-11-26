extends SceneTree
## 操作なしの起動〜メインシーン表示を Movie Maker モードで録画する (Makefile の movie target)。
## Godot 4.7.2-stable (ubuntu-24.04 / --audio-driver Dummy / --write-movie) の CI 実測
## (run 45767272708) で、再生中 BGM のまま --quit-after で終了すると ObjectDB 4 件・Resource 2 件の
## リーク警告が出たため、終了直前に stop_all() してフレームを進めて解放する (run 45767858306 で解消)。

## 共通の一時ファイル削除・AUDIO_RELEASE_TIME を借りる検証の土台
const HeadlessCheck := preload("res://scripts/dev/headless_check.gd")
## 録画するメインシーン
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
## 音声管理ノード (autoload の実行時取得用)
const AudioManagerScript := preload("res://scripts/audio/audio_manager.gd")
## --frames=<N> 未指定時の総フレーム数の既定値 (Makefile の MOVIE_FRAMES = 150 = 30 fps × 5 秒に合わせる)
const DEFAULT_TOTAL_FRAMES: int = 150
## 音を止めてから解放を待つフレーム数。AUDIO_RELEASE_TIME (0.25 秒) × 30 fps = 7.5 → 切り上げ 8 に
## 2 フレームの余裕を足した 10 フレーム (約 0.33 秒)
const AUDIO_RELEASE_FRAMES: int = 10
## Makefile の --quit-after と本スクリプトの quit(0) が同一フレームで競合しないための余裕フレーム数
const END_MARGIN_FRAMES: int = 2


## tree の準備が終わってから _run() を始める
func _initialize() -> void:
	_run.call_deferred()


## メインシーンを配置して録画し、終了前に音を止めて解放を待ってから終える
func _run() -> void:
	var settings_path: String = ProjectSettings.globalize_path(
		"res://tmp/movie-audio-settings.cfg"
	)
	HeadlessCheck.remove_file_if_exists(settings_path)
	var audio_manager: AudioManagerScript = AudioManagerScript.resolve(self) as AudioManagerScript
	if audio_manager != null:
		audio_manager.reload_settings(settings_path)

	var main: Control = MAIN_SCENE.instantiate()
	root.add_child(main)
	current_scene = main

	for _i: int in range(_record_frames(_resolve_total_frames())):
		await process_frame
	if audio_manager != null:
		audio_manager.stop_all()
	for _i: int in range(AUDIO_RELEASE_FRAMES):
		await process_frame
	HeadlessCheck.remove_file_if_exists(settings_path)
	print("movie OK")
	quit(0)


## コマンドラインの --frames=<N> 引数から総フレーム数を読み取る (Makefile の MOVIE_FRAMES が単一の正)
func _resolve_total_frames() -> int:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--frames="):
			var parsed: int = int(arg.substr("--frames=".length()))
			if parsed > 0:
				return parsed
	return DEFAULT_TOTAL_FRAMES


## 総フレーム数から解放待ちと終了余裕を引いた、通常録画のフレーム数を返す
static func _record_frames(total_frames: int) -> int:
	return maxi(1, total_frames - AUDIO_RELEASE_FRAMES - END_MARGIN_FRAMES)

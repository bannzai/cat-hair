extends SceneTree
## 操作なしの起動〜メインシーン表示を Movie Maker モードで録画する (Makefile の movie target)。
## Movie Maker モードでは --quit-after で直接終了すると再生中 BGM の AudioStreamPlayback が
## 解放されずリーク警告が出るため、終了直前に AudioManager.stop_all() して数フレーム進めてから終わる。

## 録画するメインシーン
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
## 音声管理ノード (autoload の実行時取得用)
const AudioManagerScript := preload("res://scripts/audio/audio_manager.gd")
## メインシーンを録画するフレーム数 (30 fps 固定で約 4.6 秒)
const RECORD_FRAMES: int = 138
## 音を止めてから解放を待つフレーム数 (30 fps 固定で 10 フレーム ≒ 0.33 秒 > AUDIO_RELEASE_TIME)
const AUDIO_RELEASE_FRAMES: int = 10


## tree の準備が終わってから _run() を始める
func _initialize() -> void:
	_run.call_deferred()


## メインシーンを配置して録画し、終了前に音を止めて解放を待ってから終える
func _run() -> void:
	var settings_path: String = ProjectSettings.globalize_path(
		"res://tmp/movie-audio-settings.cfg"
	)
	if FileAccess.file_exists(settings_path):
		DirAccess.remove_absolute(settings_path)
	var audio_manager: AudioManagerScript = (
		root.get_node_or_null("AudioManager") as AudioManagerScript
	)
	if audio_manager != null:
		audio_manager.reload_settings(settings_path)

	var main: Control = MAIN_SCENE.instantiate()
	root.add_child(main)
	current_scene = main

	for _i: int in range(RECORD_FRAMES):
		await process_frame
	if audio_manager != null:
		audio_manager.stop_all()
	for _i: int in range(AUDIO_RELEASE_FRAMES):
		await process_frame
	if FileAccess.file_exists(settings_path):
		DirAccess.remove_absolute(settings_path)
	print("movie OK")
	quit(0)

extends SceneTree
## 実際の描画で代表画面を撮影する (headless では描画されないため、Makefile の screenshot target が
## --headless なしで起動する)。撮影した PNG は tmp/screenshot-<名前>.png に保存し、失敗したら quit(1) で終わる。
## 全部の撮影を終えたら「screenshot OK」の行を出して quit(0) する (Makefile はこの行と PNG の存在で判定する)。
## 画面や状態を増やす時は _capture_scenes() に撮影を足す。

## 音の解放を待つ時間 (AUDIO_RELEASE_TIME) と一時ファイル削除を借りる、headless の検証の土台
const HeadlessCheck := preload("res://scripts/dev/headless_check.gd")
## 撮影するメインシーン
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
## 音声管理ノード (screenshot の --script 実行でも本番と同じ経路で動かす)
const AudioManagerScript := preload("res://scripts/audio/audio_manager.gd")


## tree の準備が終わってから _run() を始める (シーンの追加は _initialize() の後でないとできない)
func _initialize() -> void:
	_run.call_deferred()


## フレームを進めながら撮影するため、同じ実行中に重ねて呼び出さない
func _run() -> void:
	var settings_path: String = ProjectSettings.globalize_path(
		"res://tmp/screenshot-audio-settings.cfg"
	)
	HeadlessCheck.remove_file_if_exists(settings_path)
	var audio_manager: AudioManagerScript = AudioManagerScript.resolve(self) as AudioManagerScript
	var created_audio_manager: bool = false
	if audio_manager == null:
		audio_manager = AudioManagerScript.new()
		audio_manager.name = AudioManagerScript.NODE_NAME
		root.add_child(audio_manager)
		created_audio_manager = true
	audio_manager.reload_settings(settings_path)

	var ok: bool = await _capture_scenes()
	audio_manager.stop_all()
	await create_timer(HeadlessCheck.AUDIO_RELEASE_TIME).timeout
	if created_audio_manager:
		root.remove_child(audio_manager)
		audio_manager.free()
	HeadlessCheck.remove_file_if_exists(settings_path)
	if ok:
		print("screenshot OK")
		quit(0)


## 撮影する画面の並び。失敗した撮影は _capture() が quit(1) 済みなので、false を受けたらそのまま抜ける
func _capture_scenes() -> bool:
	var main: Control = MAIN_SCENE.instantiate()
	root.add_child(main)
	current_scene = main
	# 最初の撮影だけ、フォントの読み込みと最初の描画を時間で待つ。0.3 秒は bannzai/goki-hunter の撮影から引き継いだ値で、
	# CI の llvmpipe でこの画面が描画し終わることを PR #1 の artifact で確かめた (下限は測っていない)
	await create_timer(0.3).timeout
	if not await _capture("tmp/screenshot-title.png"):
		return false
	var settings_button: Button = main.get_node_or_null("Layout/SettingsButton")
	if settings_button != null:
		settings_button.pressed.emit()
	return await _capture("tmp/screenshot-settings.png")


## フレームを数フレーム進めて描画を安定させてから、現在の画面を path に保存する。保存できたら true
func _capture(path: String) -> bool:
	# 4 フレームは bannzai/goki-hunter の撮影から引き継いだ値 (レイアウトの確定と描画の反映に数フレームかかるため、
	# 1 フレームでは足りない。下限は測っていない)。Makefile の SCRIPT_FRAME_LIMIT の見積もりはこの値を前提にしている
	for _i: int in range(4):
		await process_frame
	var status: Error = root.get_viewport().get_texture().get_image().save_png(path)
	if status != OK:
		push_error("スクリーンショット保存失敗: %s (%s)" % [path, error_string(status)])
		quit(1)
		return false
	print("screenshot: " + path)
	return true

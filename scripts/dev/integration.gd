extends "res://scripts/dev/headless_check.gd"
## メインシーンを tree に置いて動かす入力統合テスト (headless)。画面の遷移や入力で変わる振る舞いを足したら、
## ここに検証を足す。実行方法は AGENTS.md「検証方法」を参照。

## 動かして確かめるメインシーン
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
## 音声カタログ
const AudioCatalog := preload("res://scripts/audio/audio_catalog.gd")
## 音声設定の永続化検証用
const AudioSettings := preload("res://scripts/audio/audio_settings.gd")
## 音声管理ノード (headless --script では autoload が自動配置されないため自分で tree に置く)
const AudioManagerScript := preload("res://scripts/audio/audio_manager.gd")


## tree の準備が終わってから _run() を始める (シーンの追加は _initialize() の後でないとできない)
func _initialize() -> void:
	_run.call_deferred()


## フレームを進めながら検証するため、同じ実行中に重ねて呼び出さない
func _run() -> void:
	var settings_path: String = ProjectSettings.globalize_path(
		"res://tmp/integration-audio-settings.cfg"
	)
	_remove_file_if_exists(settings_path)

	var audio_manager: AudioManagerScript = AudioManagerScript.new()
	audio_manager.name = "AudioManager"
	root.add_child(audio_manager)
	audio_manager.reload_settings(settings_path)

	var main: Control = MAIN_SCENE.instantiate()
	root.add_child(main)
	# _ready が走り、子のノードが tree に入るのを 1 フレーム待つ
	await process_frame

	_check_title_screen_basics(main)
	_check_audio_playback_entry(audio_manager, main)
	_check_settings_screen_toggles(audio_manager, main, settings_path)
	_check_focus_pause_resume(audio_manager)

	audio_manager.stop_all()
	AudioSettings.apply_to_audio_server(true, true)
	await create_timer(AUDIO_RELEASE_TIME).timeout
	root.remove_child(main)
	main.free()
	root.remove_child(audio_manager)
	audio_manager.free()
	_remove_file_if_exists(settings_path)
	_finish()


## 題名画面の基本表示 (Label と既定フォント) を確認する
func _check_title_screen_basics(main: Control) -> void:
	var title_label: Label = main.get_node_or_null("Layout/TitleLabel")
	_check(title_label != null, "題名の Label (Layout/TitleLabel) がある")
	if title_label != null:
		_check(not title_label.text.is_empty(), "題名の Label に文字が入っている")
	_check(main.theme != null and main.theme.default_font != null, "メインシーンの theme に既定フォントが入っている")


## 題名画面起動時の BGM 再生、曲切替、効果音の出来事別入口を確認する
func _check_audio_playback_entry(audio_manager: AudioManagerScript, main: Control) -> void:
	_check(
		audio_manager.get_current_bgm_name() == AudioCatalog.BGM_TITLE,
		"題名の画面を開くと題名 BGM が再生される (実際: %s)" % audio_manager.get_current_bgm_name()
	)
	_check(
		audio_manager.play_bgm(AudioCatalog.BGM_TITLE),
		"同じ BGM を重ねて指定しても成功し継続する"
	)
	_check(
		audio_manager.play_bgm(AudioCatalog.BGM_MANSION),
		"屋敷 BGM へ切り替えられる"
	)
	_check(
		audio_manager.get_current_bgm_name() == AudioCatalog.BGM_MANSION,
		"切替後の現在 BGM が mansion である"
	)
	_check(
		not audio_manager.play_bgm("unknown_bgm"),
		"未登録の BGM 名では false を返しゲームを止めない"
	)
	_check(
		audio_manager.get_current_bgm_name() == AudioCatalog.BGM_MANSION,
		"未登録 BGM の指定後も再生中の BGM が維持される"
	)
	var start_button: Button = main.get_node_or_null("Layout/StartButton")
	_check(start_button != null, "はじめるボタン (Layout/StartButton) がある")
	if start_button != null:
		start_button.pressed.emit()
	for event_name: String in AudioCatalog.all_sfx_names():
		_check(
			audio_manager.play_sfx(event_name),
			"効果音 '%s' を出来事名で鳴らせる" % event_name
		)
	_check(
		not audio_manager.play_sfx(""),
		"空文字の効果音名は false を返しゲームを止めない"
	)
	_check(
		not audio_manager.play_sfx("unknown_sfx"),
		"未登録の効果音名は false を返しゲームを止めない"
	)


## 設定画面で BGM・効果音のオン・オフを切り替え、バス消音と保存へ反映されることを確認する
func _check_settings_screen_toggles(
	audio_manager: AudioManagerScript, main: Control, settings_path: String
) -> void:
	var bgm_idx: int = AudioServer.get_bus_index(AudioCatalog.BUS_BGM)
	var sfx_idx: int = AudioServer.get_bus_index(AudioCatalog.BUS_SFX)
	var settings_button: Button = main.get_node_or_null("Layout/SettingsButton")
	var panel: Control = main.get_node_or_null("AudioSettingsPanel")
	_check(settings_button != null, "設定ボタン (Layout/SettingsButton) がある")
	_check(panel != null, "設定画面パネル (AudioSettingsPanel) がある")
	if settings_button == null or panel == null:
		return

	_check(not panel.visible, "起動直後は設定画面が閉じている")
	_check(not AudioServer.is_bus_mute(bgm_idx), "初期状態で BGM バスは消音ではない")
	_check(not AudioServer.is_bus_mute(sfx_idx), "初期状態で SFX バスは消音ではない")

	settings_button.pressed.emit()
	_check(panel.visible, "設定ボタンを押すと設定画面が開く")

	var bgm_toggle: CheckButton = panel.get_node_or_null(
		"CenterContainer/Panel/MarginContainer/VBoxContainer/BgmToggle"
	)
	var sfx_toggle: CheckButton = panel.get_node_or_null(
		"CenterContainer/Panel/MarginContainer/VBoxContainer/SfxToggle"
	)
	var close_button: Button = panel.get_node_or_null(
		"CenterContainer/Panel/MarginContainer/VBoxContainer/CloseButton"
	)
	_check(
		bgm_toggle != null and sfx_toggle != null and close_button != null,
		"設定画面に BGM・効果音トグルと閉じるボタンがある"
	)
	if bgm_toggle == null or sfx_toggle == null or close_button == null:
		return

	# BGM をオフにする -> BGM バスだけ消音になり、保存される
	bgm_toggle.button_pressed = false
	_check(AudioServer.is_bus_mute(bgm_idx), "設定画面で BGM を切ると BGM バスが消音になる")
	_check(not AudioServer.is_bus_mute(sfx_idx), "BGM を切っても SFX バスは消音にならない")
	_check(not audio_manager.is_bgm_enabled(), "AudioManager の BGM 設定がオフになる")
	var saved_after_bgm: RefCounted = AudioSettings.new()
	_check(
		saved_after_bgm.load_from_path(settings_path) == OK
		and not saved_after_bgm.bgm_enabled
		and saved_after_bgm.sfx_enabled,
		"BGM オフ・効果音オンの状態が設定ファイルに保存されている"
	)

	# 効果音もオフにする -> 両方消音になり、保存される
	sfx_toggle.button_pressed = false
	_check(AudioServer.is_bus_mute(sfx_idx), "設定画面で効果音を切ると SFX バスが消音になる")
	_check(AudioServer.is_bus_mute(bgm_idx), "効果音を切っても BGM バスの消音は維持される")

	# BGM だけオンに戻す -> BGM バスだけ消音解除、SFX バスは消音のまま
	bgm_toggle.button_pressed = true
	_check(not AudioServer.is_bus_mute(bgm_idx), "設定画面で BGM をオンに戻すと BGM バスの消音が解除される")
	_check(AudioServer.is_bus_mute(sfx_idx), "BGM をオンに戻しても SFX バスは消音のまま")

	# 閉じて再度開いた時に表示が設定値と同期していること
	close_button.pressed.emit()
	_check(not panel.visible, "閉じるボタンで設定画面が閉じる")
	settings_button.pressed.emit()
	_check(
		bgm_toggle.button_pressed and not sfx_toggle.button_pressed,
		"設定画面を開き直した時に BGM オン・効果音オフの表示が保たれる"
	)
	close_button.pressed.emit()


## ウィンドウが裏に回った時・戻った時の BGM 一時停止と再開 (明示停止時は再開しない)
func _check_focus_pause_resume(audio_manager: AudioManagerScript) -> void:
	audio_manager.play_bgm(AudioCatalog.BGM_TITLE)
	audio_manager.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(audio_manager.is_bgm_paused_by_focus(), "FOCUS_OUT で再生中 BGM が一時停止になる")
	# 重ねて FOCUS_OUT が来ても状態を壊さない
	audio_manager.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(audio_manager.is_bgm_paused_by_focus(), "一時停止中の重ね FOCUS_OUT でも一時停止が維持される")
	audio_manager.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	_check(not audio_manager.is_bgm_paused_by_focus(), "FOCUS_IN で一時停止が解除される")

	audio_manager.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	_check(audio_manager.is_bgm_paused_by_focus(), "PAUSED で再生中 BGM が一時停止になる")
	audio_manager.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	_check(not audio_manager.is_bgm_paused_by_focus(), "RESUMED で一時停止が解除される")

	# 明示停止中は裏に回っても一時停止扱いにならず、戻っても再開しない
	audio_manager.stop_bgm()
	audio_manager.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(not audio_manager.is_bgm_paused_by_focus(), "明示停止中の FOCUS_OUT では一時停止フラグが立たない")
	audio_manager.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	_check(audio_manager.get_current_bgm_name().is_empty(), "明示停止中の FOCUS_IN で勝手に BGM が再開しない")


## テスト用の一時ファイルを削除する
func _remove_file_if_exists(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

extends "res://scripts/dev/headless_check.gd"
## メインシーンを tree に置いて動かす入力統合テスト (headless)。画面の遷移や入力で変わる振る舞いを足したら、
## ここに検証を足す。実行方法は AGENTS.md「検証方法」を参照。

## 動かして確かめるメインシーン
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
## 音声カタログ
const AudioCatalog := preload("res://scripts/audio/audio_catalog.gd")
## 音声設定の永続化検証用
const AudioSettings := preload("res://scripts/audio/audio_settings.gd")
## 音声管理ノード (autoload の実行時取得用)
const AudioManagerScript := preload("res://scripts/audio/audio_manager.gd")


## tree の準備が終わってから _run() を始める (シーンの追加は _initialize() の後でないとできない)
func _initialize() -> void:
	_run.call_deferred()


## フレームを進めながら検証するため、同じ実行中に重ねて呼び出さない
func _run() -> void:
	var settings_path: String = ProjectSettings.globalize_path(
		"res://tmp/integration-audio-settings.cfg"
	)
	remove_file_if_exists(settings_path)

	var audio_manager: AudioManagerScript = AudioManagerScript.resolve(self) as AudioManagerScript
	var created_audio_manager: bool = false
	if audio_manager == null:
		audio_manager = AudioManagerScript.new()
		audio_manager.name = AudioManagerScript.NODE_NAME
		root.add_child(audio_manager)
		created_audio_manager = true
	audio_manager.reload_settings(settings_path)

	var main: Control = MAIN_SCENE.instantiate()
	root.add_child(main)
	# _ready が走り、子のノードが tree に入るのを 1 フレーム待つ
	await process_frame

	_check_title_screen_basics(main)
	_check_audio_playback_entry(audio_manager, main)
	_check_stream_load_errors(audio_manager)
	_check_sfx_pool_round_robin(audio_manager)
	_check_settings_screen_toggles(audio_manager, main, settings_path)
	await _check_reload_persisted_settings(audio_manager, settings_path)
	_check_focus_pause_resume(audio_manager)

	audio_manager.stop_all()
	AudioSettings.apply_to_audio_server(true, true)
	await create_timer(AUDIO_RELEASE_TIME).timeout
	root.remove_child(main)
	main.free()
	if created_audio_manager:
		root.remove_child(audio_manager)
		audio_manager.free()
	remove_file_if_exists(settings_path)
	_finish()


## 題名画面の基本表示 (Label と既定フォント) を確認する
func _check_title_screen_basics(main: Control) -> void:
	var title_label: Label = main.get_node_or_null("Layout/TitleLabel")
	_check(title_label != null, "題名の Label (Layout/TitleLabel) がある")
	if title_label != null:
		_check(not title_label.text.is_empty(), "題名の Label に文字が入っている")
	_check(main.theme != null and main.theme.default_font != null, "メインシーンの theme に既定フォントが入っている")


## 題名画面起動時の BGM 再生、同一曲の継続、ループ有効化、効果音の出来事別入口を確認する
func _check_audio_playback_entry(audio_manager: AudioManagerScript, main: Control) -> void:
	var bgm_player: AudioStreamPlayer = audio_manager.get_node_or_null("BGMPlayer")
	_check(bgm_player != null, "AudioManager 配下に BGMPlayer がある")
	_check(
		audio_manager.get_current_bgm_name() == AudioCatalog.BGM_TITLE,
		"題名の画面を開くと題名 BGM が再生される (実際: %s)" % audio_manager.get_current_bgm_name()
	)
	if bgm_player != null:
		_check(
			bgm_player.stream is AudioStreamOggVorbis
			and (bgm_player.stream as AudioStreamOggVorbis).loop,
			"題名 BGM の AudioStreamOggVorbis で loop が有効になっている"
		)

	# 同じ曲を重ねて指定した時は play() を呼び直さず継続する
	var play_count_before_same: int = audio_manager.get_bgm_play_count()
	_check(audio_manager.play_bgm(AudioCatalog.BGM_TITLE), "同じ BGM の再指定が true を返す")
	_check(
		audio_manager.get_bgm_play_count() == play_count_before_same,
		"同じ BGM を重ねて指定しても頭から再生し直さない (count: %d)" % audio_manager.get_bgm_play_count()
	)

	# 別の曲へ切り替えると play() が増え、屋敷 BGM もループ有効になる
	_check(audio_manager.play_bgm(AudioCatalog.BGM_MANSION), "屋敷 BGM へ切り替えられる")
	_check(
		audio_manager.get_bgm_play_count() == play_count_before_same + 1,
		"別 BGM への切替時は再生回数が増える"
	)
	_check(
		audio_manager.get_current_bgm_name() == AudioCatalog.BGM_MANSION,
		"切替後の現在 BGM が mansion である"
	)
	if bgm_player != null:
		_check(
			bgm_player.stream is AudioStreamOggVorbis
			and (bgm_player.stream as AudioStreamOggVorbis).loop,
			"屋敷 BGM の AudioStreamOggVorbis で loop が有効になっている"
		)

	_check(
		not audio_manager.play_bgm("unknown_bgm"),
		"未登録の BGM 名では false を返しゲームを止めない"
	)
	_check(
		audio_manager.get_current_bgm_name() == AudioCatalog.BGM_MANSION,
		"未登録 BGM の指定後も再生中の BGM が維持される"
	)

	# はじめるボタンで効果音 button が実際に鳴ることを確認する
	var start_button: Button = main.get_node_or_null("Layout/StartButton")
	_check(start_button != null, "はじめるボタン (Layout/StartButton) がある")
	if start_button != null:
		var count_before_start: int = audio_manager.get_sfx_play_count()
		start_button.pressed.emit()
		_check_button_sfx_played(audio_manager, count_before_start, "はじめるボタン押下")

	for event_name: String in AudioCatalog.all_sfx_names():
		_check(audio_manager.play_sfx(event_name), "効果音 '%s' を出来事名で鳴らせる" % event_name)
	_check(not audio_manager.play_sfx(""), "空文字の効果音名は false を返しゲームを止めない")
	_check(not audio_manager.play_sfx("unknown_sfx"), "未登録の効果音名は false を返しゲームを止めない")


## 存在しないパスと AudioStream でないリソースの読み込み失敗時に null を返すか確認する
func _check_stream_load_errors(audio_manager: AudioManagerScript) -> void:
	_check(
		audio_manager.load_stream("res://assets/audio/does_not_exist.ogg") == null,
		"存在しない音声パスの読み込みは null を返す"
	)
	_check(
		audio_manager.load_stream("res://scenes/main.tscn") == null,
		"AudioStream でないリソースの読み込みは null を返す"
	)


## 効果音プール (SFX_POOL_SIZE = 4) が全て再生中の時にラウンドロビンで再利用されることを確認する
func _check_sfx_pool_round_robin(audio_manager: AudioManagerScript) -> void:
	audio_manager.stop_all()
	for index: int in range(AudioManagerScript.SFX_POOL_SIZE):
		var player: AudioStreamPlayer = audio_manager.get_node_or_null("SFXPlayer%d" % index)
		_check(
			player != null and player.bus == AudioCatalog.BUS_SFX,
			"SFXPlayer%d が SFX バスに接続されている" % index
		)
	var chosen_indices: Array[int] = []
	for _i: int in range(AudioManagerScript.SFX_POOL_SIZE + 2):
		audio_manager.play_sfx(AudioCatalog.SFX_PLUCK_HAIR)
		chosen_indices.append(audio_manager.get_last_sfx_player_index())
	_check(
		chosen_indices == [0, 1, 2, 3, 0, 1],
		"効果音プール満杯時に 0→1→2→3→0→1 のラウンドロビンで再利用される (実際: %s)" % str(chosen_indices)
	)
	audio_manager.stop_all()
	audio_manager.play_bgm(AudioCatalog.BGM_TITLE)


## 設定画面で BGM・効果音のオン・オフを切り替え、バス消音・保存・同期・ボタン効果音を確認する
func _check_settings_screen_toggles(
	audio_manager: AudioManagerScript, main: Control, settings_path: String
) -> void:
	var bgm_bus_index: int = AudioServer.get_bus_index(AudioCatalog.BUS_BGM)
	var sfx_bus_index: int = AudioServer.get_bus_index(AudioCatalog.BUS_SFX)
	var settings_button: Button = main.get_node_or_null("Layout/SettingsButton")
	var panel: Control = main.get_node_or_null("AudioSettingsPanel")
	_check(settings_button != null, "設定ボタン (Layout/SettingsButton) がある")
	_check(panel != null, "設定画面パネル (AudioSettingsPanel) がある")
	if settings_button == null or panel == null:
		return

	_check(not panel.visible, "起動直後は設定画面が閉じている")
	_check(not AudioServer.is_bus_mute(bgm_bus_index), "初期状態で BGM バスは消音ではない")
	_check(not AudioServer.is_bus_mute(sfx_bus_index), "初期状態で SFX バスは消音ではない")

	var count_before_open: int = audio_manager.get_sfx_play_count()
	settings_button.pressed.emit()
	_check(panel.visible, "設定ボタンを押すと設定画面が開く")
	_check_button_sfx_played(audio_manager, count_before_open, "設定ボタン押下")

	var bgm_toggle: CheckButton = panel.get_node_or_null(
		"CenterContainer/Panel/MarginContainer/VBoxContainer/BGMToggle"
	)
	var sfx_toggle: CheckButton = panel.get_node_or_null(
		"CenterContainer/Panel/MarginContainer/VBoxContainer/SFXToggle"
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

	# BGM をオフにする -> BGM バスだけ消音になり、保存され、ボタン効果音が鳴る
	var count_before_bgm: int = audio_manager.get_sfx_play_count()
	bgm_toggle.button_pressed = false
	_check_button_sfx_played(audio_manager, count_before_bgm, "BGM トグル切替")
	_check(AudioServer.is_bus_mute(bgm_bus_index), "設定画面で BGM を切ると BGM バスが消音になる")
	_check(not AudioServer.is_bus_mute(sfx_bus_index), "BGM を切っても SFX バスは消音にならない")
	_check(not audio_manager.is_bgm_enabled(), "AudioManager の BGM 設定がオフになる")
	var saved_after_bgm: RefCounted = AudioSettings.new()
	_check(
		saved_after_bgm.load_from_path(settings_path) == OK
		and not saved_after_bgm.bgm_enabled
		and saved_after_bgm.sfx_enabled,
		"BGM オフ・効果音オンの状態が設定ファイルに保存されている"
	)

	# 効果音もオフにする -> 両方消音になり、効果音設定もファイルへ保存される
	var count_before_sfx: int = audio_manager.get_sfx_play_count()
	sfx_toggle.button_pressed = false
	_check_button_sfx_played(audio_manager, count_before_sfx, "効果音トグル切替")
	_check(AudioServer.is_bus_mute(sfx_bus_index), "設定画面で効果音を切ると SFX バスが消音になる")
	_check(AudioServer.is_bus_mute(bgm_bus_index), "効果音を切っても BGM バスの消音は維持される")
	var saved_after_sfx: RefCounted = AudioSettings.new()
	_check(
		saved_after_sfx.load_from_path(settings_path) == OK
		and not saved_after_sfx.bgm_enabled
		and not saved_after_sfx.sfx_enabled,
		"BGM オフ・効果音オフの状態が設定ファイルに保存されている"
	)

	# BGM だけオンに戻す -> BGM バスだけ消音解除、SFX バスは消音のまま
	bgm_toggle.button_pressed = true
	_check(not AudioServer.is_bus_mute(bgm_bus_index), "設定画面で BGM をオンに戻すと BGM バスの消音が解除される")
	_check(AudioServer.is_bus_mute(sfx_bus_index), "BGM をオンに戻しても SFX バスは消音のまま")

	# 閉じている間に AudioManager 側の設定を変更し、開き直した時にトグル表示が同期されることを確認
	var count_before_close: int = audio_manager.get_sfx_play_count()
	close_button.pressed.emit()
	_check(not panel.visible, "閉じるボタンで設定画面が閉じる")
	_check_button_sfx_played(audio_manager, count_before_close, "閉じるボタン押下")
	audio_manager.set_bgm_enabled(false)
	audio_manager.set_sfx_enabled(true)
	settings_button.pressed.emit()
	_check(
		(not bgm_toggle.button_pressed) and sfx_toggle.button_pressed,
		"閉じた間に変わった AudioManager の値 (false, true) が設定画面を開き直した時に同期される"
	)
	close_button.pressed.emit()


## 保存済みの非既定値ファイルから reload_settings し、バス消音と新規 UI 初期表示へ反映されるか確認する
func _check_reload_persisted_settings(
	audio_manager: AudioManagerScript, settings_path: String
) -> void:
	var bgm_bus_index: int = AudioServer.get_bus_index(AudioCatalog.BUS_BGM)
	var sfx_bus_index: int = AudioServer.get_bus_index(AudioCatalog.BUS_SFX)
	_check(
		AudioSettings.new(false, false).save_to_path(settings_path) == OK,
		"再起動テスト用の非既定値 (false, false) を保存できる"
	)
	AudioSettings.apply_to_audio_server(true, true)
	_check(
		audio_manager.reload_settings(settings_path) == OK,
		"保存済み設定ファイルを reload_settings で読み込める"
	)
	_check(
		AudioServer.is_bus_mute(bgm_bus_index) and AudioServer.is_bus_mute(sfx_bus_index),
		"reload_settings により保存済みの (false, false) が BGM・SFX バスの消音へ反映される"
	)
	var reopened_main: Control = MAIN_SCENE.instantiate()
	root.add_child(reopened_main)
	await process_frame
	var bgm_toggle: CheckButton = reopened_main.get_node_or_null(
		"AudioSettingsPanel/CenterContainer/Panel/MarginContainer/VBoxContainer/BGMToggle"
	)
	var sfx_toggle: CheckButton = reopened_main.get_node_or_null(
		"AudioSettingsPanel/CenterContainer/Panel/MarginContainer/VBoxContainer/SFXToggle"
	)
	_check(
		bgm_toggle != null and sfx_toggle != null
		and not bgm_toggle.button_pressed and not sfx_toggle.button_pressed,
		"非既定値の保存済み設定で新規生成した設定画面のトグルが (false, false) で初期化される"
	)
	root.remove_child(reopened_main)
	reopened_main.free()


## ウィンドウが裏に回った時・戻った時の BGM 一時停止と再開 (実際の BGMPlayer 状態を確認)
func _check_focus_pause_resume(audio_manager: AudioManagerScript) -> void:
	var bgm_player: AudioStreamPlayer = audio_manager.get_node_or_null("BGMPlayer")
	_check(bgm_player != null, "フォーカス検証用に BGMPlayer を取得できる")
	if bgm_player == null:
		return

	audio_manager.play_bgm(AudioCatalog.BGM_TITLE)
	audio_manager.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(
		audio_manager.is_bgm_paused_by_focus() and bgm_player.stream_paused,
		"FOCUS_OUT で BGMPlayer.stream_paused が true になる"
	)
	# 重ねて FOCUS_OUT が来ても状態を壊さない
	audio_manager.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(
		audio_manager.is_bgm_paused_by_focus() and bgm_player.stream_paused,
		"一時停止中の重ね FOCUS_OUT でも一時停止が維持される"
	)
	audio_manager.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	_check(
		not audio_manager.is_bgm_paused_by_focus() and not bgm_player.stream_paused,
		"FOCUS_IN で BGMPlayer.stream_paused が false に戻る"
	)

	audio_manager.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	_check(
		audio_manager.is_bgm_paused_by_focus() and bgm_player.stream_paused,
		"PAUSED で BGMPlayer.stream_paused が true になる"
	)
	audio_manager.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	_check(
		not audio_manager.is_bgm_paused_by_focus() and not bgm_player.stream_paused,
		"RESUMED で BGMPlayer.stream_paused が false に戻る"
	)

	# 明示停止中は裏に回っても一時停止扱いにならず、戻っても playing が false のまま
	audio_manager.stop_bgm()
	audio_manager.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(
		not audio_manager.is_bgm_paused_by_focus() and not bgm_player.playing,
		"明示停止中の FOCUS_OUT では一時停止フラグが立たず停止のまま"
	)
	audio_manager.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	_check(
		audio_manager.get_current_bgm_name().is_empty() and not bgm_player.playing,
		"明示停止中の FOCUS_IN で BGMPlayer.playing が true に戻らない"
	)


## 直前の操作で効果音 button が 1 回鳴ったことを再生回数・出来事名・ストリームパスで確認する
func _check_button_sfx_played(
	audio_manager: AudioManagerScript, count_before: int, action_label: String
) -> void:
	var player_index: int = audio_manager.get_last_sfx_player_index()
	var player: AudioStreamPlayer = audio_manager.get_node_or_null("SFXPlayer%d" % player_index)
	_check(
		audio_manager.get_sfx_play_count() == count_before + 1
		and audio_manager.get_last_sfx_event_name() == AudioCatalog.SFX_BUTTON
		and player != null
		and player.stream != null
		and player.stream.resource_path == AudioCatalog.resolve_sfx_path(AudioCatalog.SFX_BUTTON),
		"%s で効果音 button (sfx_button.ogg) が再生される" % action_label
	)

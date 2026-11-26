extends "res://scripts/dev/headless_check.gd"
## メインシーンを tree に置いて動かす入力統合テスト (headless)。
## 音声系 (BGM・効果音・設定画面・フォーカス) と屋敷系 (移動・視点・開発者画面・保存・OS 引数) を検証する。
## 実行方法は AGENTS.md「検証方法」を参照。

## 動かして確かめるメインシーン
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
## メインシーンのノードパス定数参照用
const MainScript := preload("res://scripts/main.gd")
## 音声カタログ
const AudioCatalog := preload("res://scripts/audio/audio_catalog.gd")
## 音声設定の永続化検証用
const AudioSettings := preload("res://scripts/audio/audio_settings.gd")
## 設定画面パネルのノードパス定数参照用
const AudioSettingsPanelScript := preload("res://scripts/ui/audio_settings_panel.gd")
## JSON 保存ストレージスクリプト
const SaveStorageScript := preload("res://scripts/state/save_storage.gd")
## 開発者向け調整値データ型スクリプト
const MansionTuningScript := preload("res://scripts/data/mansion_tuning.gd")
## 一人称プレイヤーノードスクリプト (ピッチ上限の単一情報源参照に使用)
const FirstPersonPlayerScript := preload("res://scripts/player/first_person_player.gd")

## integration テスト専用のセーブパス
const TEST_SAVE_PATH: String = "user://integration_save_data.json"
## 実プロセス OS 引数検証モードを指定するフラグ引数
const CMDLINE_VERIFY_FLAG: String = "--verify-cmdline"


## tree の準備が終わってから _run() を始める (シーンの追加は _initialize() の後でないとできない)
func _initialize() -> void:
	_run.call_deferred()


## フレームを進めながら検証するため、同じ実行中に重ねて呼び出さない
func _run() -> void:
	if OS.get_cmdline_user_args().has(CMDLINE_VERIFY_FLAG):
		await _run_cmdline_process_verification()
		_finish()
		return

	var settings_path: String = ProjectSettings.globalize_path(
		"res://tmp/integration-audio-settings.cfg"
	)
	var audio_handle: Dictionary = prepare_audio_manager(self, settings_path)
	var audio_manager: AudioManagerScript = audio_handle["manager"] as AudioManagerScript

	SaveStorageScript.delete_save_file(TEST_SAVE_PATH)
	var state_handle: Dictionary = acquire_game_state(root, TEST_SAVE_PATH)
	var game_state: Node = state_handle["node"]
	var created_state: bool = state_handle["created"]

	# 1. 音声・設定画面の統合検証
	var audio_main: Node3D = MAIN_SCENE.instantiate()
	root.add_child(audio_main)
	await process_frame

	_check_title_screen_basics(audio_main)
	_check_audio_playback_entry(audio_manager, audio_main)
	_check_stream_load_errors(audio_manager)
	_check_sfx_pool_round_robin(audio_manager)
	_check_settings_screen_toggles(audio_manager, audio_main, settings_path)
	await _check_reload_persisted_settings(audio_manager, settings_path)
	_check_focus_pause_resume(audio_manager)

	audio_manager.stop_all()
	AudioSettings.apply_to_audio_server(true, true)
	root.remove_child(audio_main)
	audio_main.free()

	# 2. 屋敷・一人称操作・開発者画面・セーブの統合検証
	SaveStorageScript.delete_save_file(TEST_SAVE_PATH)
	game_state.initialize_from_storage(TEST_SAVE_PATH)
	var main: Node3D = MAIN_SCENE.instantiate()
	root.add_child(main)
	await process_frame

	await _verify_title_and_blocked_inputs(main)
	await _verify_enter_movement_and_look(main)
	await _verify_dev_panel_keys_and_rebuild(main, game_state)
	await _verify_manual_save_and_close_request(game_state)

	root.remove_child(main)
	main.free()

	await _verify_resume_and_new_game_from_saved_state(game_state)

	audio_manager.stop_all()
	AudioSettings.apply_to_audio_server(true, true)
	await create_timer(AudioManagerScript.AUDIO_RELEASE_TIME_SEC).timeout
	if created_state:
		root.remove_child(game_state)
		game_state.free()
	cleanup_audio_manager(self, audio_handle, settings_path)
	SaveStorageScript.delete_save_file(TEST_SAVE_PATH)
	_finish()


## 題名画面の基本表示 (Label と既定フォント) を確認する
func _check_title_screen_basics(main: Node3D) -> void:
	var title_label: Label = main.get_node_or_null(MainScript.TITLE_LABEL_PATH)
	_check(title_label != null, "題名の Label (%s) がある" % MainScript.TITLE_LABEL_PATH)
	if title_label != null:
		_check(not title_label.text.is_empty(), "題名の Label に文字が入っている")
	_check(
		main.get_ui_theme() != null and main.get_ui_theme().default_font != null,
		"メインシーンの theme に既定フォントが入っている",
	)


## 題名画面起動時の BGM 再生、同一曲の継続、停止後の再再生、ループ有効化、効果音の出来事別入口を確認する
func _check_audio_playback_entry(audio_manager: AudioManagerScript, main: Node3D) -> void:
	var bgm_player: AudioStreamPlayer = audio_manager.get_node_or_null(
		AudioManagerScript.BGM_PLAYER_NAME
	)
	_check(bgm_player != null, "AudioManager 配下に BGMPlayer がある")
	if bgm_player != null:
		_check(
			bgm_player.bus == AudioCatalog.BUS_BGM,
			"BGMPlayer が BGM バスに接続されている (実際: %s)" % bgm_player.bus
		)
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

	# 曲名は同じだがプレイヤー側だけ止まっている時 (playing=false) は再生し直す
	if bgm_player != null:
		bgm_player.stop()
		_check(
			audio_manager.play_bgm(AudioCatalog.BGM_TITLE)
			and bgm_player.playing
			and audio_manager.get_bgm_play_count() == play_count_before_same + 1,
			"同じ曲名でもプレイヤーが停止中なら頭から再生し直す"
		)

	# 別の曲へ切り替えると play() が増え、屋敷 BGM もループ有効になる
	var play_count_before_mansion: int = audio_manager.get_bgm_play_count()
	_check(audio_manager.play_bgm(AudioCatalog.BGM_MANSION), "屋敷 BGM へ切り替えられる")
	_check(
		audio_manager.get_bgm_play_count() == play_count_before_mansion + 1,
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
	var start_button: Button = main.get_node_or_null(MainScript.START_BUTTON_PATH)
	_check(start_button != null, "はじめるボタン (%s) がある" % MainScript.START_BUTTON_PATH)
	if start_button != null:
		var count_before_start: int = audio_manager.get_sfx_play_count()
		start_button.pressed.emit()
		_check_button_sfx_played(audio_manager, count_before_start, "はじめるボタン押下")

	for event_name: String in AudioCatalog.all_sfx_names():
		_check(audio_manager.play_sfx(event_name), "効果音 '%s' を出来事名で鳴らせる" % event_name)
	_check(not audio_manager.play_sfx(""), "空文字の効果音名は false を返しゲームを止めない")
	_check(not audio_manager.play_sfx("unknown_sfx"), "未登録の効果音名は false を返しゲームを止めない")


## 存在しないパスと AudioStream でないリソースの読み込み失敗時に再生の入口がスキップするか確認する
func _check_stream_load_errors(audio_manager: AudioManagerScript) -> void:
	var bgm_name_before: String = audio_manager.get_current_bgm_name()
	var bgm_count_before: int = audio_manager.get_bgm_play_count()
	var sfx_count_before: int = audio_manager.get_sfx_play_count()
	for bad_path: String in ["res://assets/audio/does_not_exist.ogg", "res://scenes/main.tscn"]:
		_check(
			audio_manager.load_stream(bad_path) == null,
			"不正な音声リソース %s の読み込みは null を返す" % bad_path
		)
		_check(
			not audio_manager.play_bgm_path("broken_bgm", bad_path),
			"素材読み込み失敗 (%s) の play_bgm_path は false を返す" % bad_path
		)
		_check(
			not audio_manager.play_sfx_path("broken_sfx", bad_path),
			"素材読み込み失敗 (%s) の play_sfx_path は false を返す" % bad_path
		)
	_check(
		audio_manager.get_current_bgm_name() == bgm_name_before
		and audio_manager.get_bgm_play_count() == bgm_count_before
		and audio_manager.get_sfx_play_count() == sfx_count_before,
		"素材読み込み失敗時に再生中の BGM 名・BGM/SFX 再生回数が変わらない"
	)


## 効果音プール (SFX_POOL_SIZE) が全て再生中の時にラウンドロビンで再利用されることを確認する
func _check_sfx_pool_round_robin(audio_manager: AudioManagerScript) -> void:
	audio_manager.stop_all()
	var pool_size: int = AudioManagerScript.SFX_POOL_SIZE
	for index: int in range(pool_size):
		var player: AudioStreamPlayer = audio_manager.get_node_or_null(
			AudioManagerScript.SFX_PLAYER_NAME_FORMAT % index
		)
		_check(
			player != null and player.bus == AudioCatalog.BUS_SFX,
			"SFXPlayer%d が SFX バスに接続されている" % index
		)
	var expected_indices: Array[int] = []
	var chosen_indices: Array[int] = []
	for step: int in range(pool_size + 2):
		expected_indices.append(step % pool_size)
		audio_manager.play_sfx(AudioCatalog.SFX_PLUCK_HAIR)
		chosen_indices.append(audio_manager.get_last_sfx_player_index())
	_check(
		chosen_indices == expected_indices,
		"効果音プール満杯時にラウンドロビン %s で再利用される (実際: %s)" % [
			str(expected_indices), str(chosen_indices)
		]
	)
	audio_manager.stop_all()
	audio_manager.play_bgm(AudioCatalog.BGM_TITLE)


## 設定画面で BGM・効果音のオン・オフを切り替え、バス消音・保存・同期・ボタン効果音を確認する
func _check_settings_screen_toggles(
	audio_manager: AudioManagerScript, main: Node3D, settings_path: String
) -> void:
	var bgm_bus_index: int = AudioServer.get_bus_index(AudioCatalog.BUS_BGM)
	var sfx_bus_index: int = AudioServer.get_bus_index(AudioCatalog.BUS_SFX)
	var settings_button: Button = main.get_node_or_null(MainScript.SETTINGS_BUTTON_PATH)
	var panel: Control = main.get_node_or_null(MainScript.SETTINGS_PANEL_PATH)
	_check(settings_button != null, "設定ボタン (%s) がある" % MainScript.SETTINGS_BUTTON_PATH)
	_check(panel != null, "設定画面パネル (%s) がある" % MainScript.SETTINGS_PANEL_PATH)
	if settings_button == null or panel == null:
		return

	_check(not panel.visible, "起動直後は設定画面が閉じている")
	_check(not AudioServer.is_bus_mute(bgm_bus_index), "初期状態で BGM バスは消音ではない")
	_check(not AudioServer.is_bus_mute(sfx_bus_index), "初期状態で SFX バスは消音ではない")

	var count_before_open: int = audio_manager.get_sfx_play_count()
	settings_button.pressed.emit()
	_check(panel.visible, "設定ボタンを押すと設定画面が開く")
	_check_button_sfx_played(audio_manager, count_before_open, "設定ボタン押下")

	var bgm_toggle: CheckButton = panel.get_node_or_null(AudioSettingsPanelScript.BGM_TOGGLE_PATH)
	var sfx_toggle: CheckButton = panel.get_node_or_null(AudioSettingsPanelScript.SFX_TOGGLE_PATH)
	var save_error_label: Label = panel.get_node_or_null(
		AudioSettingsPanelScript.SAVE_ERROR_LABEL_PATH
	)
	var close_button: Button = panel.get_node_or_null(AudioSettingsPanelScript.CLOSE_BUTTON_PATH)
	_check(
		bgm_toggle != null and sfx_toggle != null
		and save_error_label != null and close_button != null,
		"設定画面に BGM・効果音トグル、保存エラー表示、閉じるボタンがある"
	)
	if (
		bgm_toggle == null or sfx_toggle == null
		or save_error_label == null or close_button == null
	):
		return
	_check(not save_error_label.visible, "初期表示時は設定保存エラーが表示されない")

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
	_check(not save_error_label.visible, "正常保存時は設定保存エラーが表示されない")

	# 保存先が不正で保存に失敗した時はエラー表示しつつ今セッションの音声変更は即時反映する
	var original_path: String = audio_manager.settings_path
	audio_manager.settings_path = ""
	bgm_toggle.button_pressed = false
	_check(
		save_error_label.visible
		and save_error_label.text == AudioSettingsPanelScript.SAVE_ERROR_MESSAGE
		and AudioServer.is_bus_mute(bgm_bus_index),
		"BGM トグルの保存失敗時にエラーメッセージを表示しつつ BGM バス消音は即時反映される"
	)
	sfx_toggle.button_pressed = true
	_check(
		save_error_label.visible
		and save_error_label.text == AudioSettingsPanelScript.SAVE_ERROR_MESSAGE
		and not AudioServer.is_bus_mute(sfx_bus_index),
		"効果音トグルの保存失敗時にエラーメッセージを表示しつつ SFX バス解除は即時反映される"
	)
	audio_manager.settings_path = original_path
	bgm_toggle.button_pressed = true
	_check(
		not save_error_label.visible and save_error_label.text.is_empty(),
		"保存成功時に設定保存エラー表示が消える"
	)

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


## 保存済みの非既定値ファイルが _ready() の起動経路および reload_settings で反映されるか確認する
func _check_reload_persisted_settings(
	audio_manager: AudioManagerScript, settings_path: String
) -> void:
	var bgm_bus_index: int = AudioServer.get_bus_index(AudioCatalog.BUS_BGM)
	var sfx_bus_index: int = AudioServer.get_bus_index(AudioCatalog.BUS_SFX)
	_check(
		AudioSettings.new(false, false).save_to_path(settings_path) == OK,
		"再起動テスト用の非既定値 (false, false) を保存できる"
	)

	# _ready() だけで (reload_settings を外から呼ばずに) 保存済み設定とバス消音が反映されること
	AudioSettings.apply_to_audio_server(true, true)
	var boot_manager: AudioManagerScript = AudioManagerScript.new()
	boot_manager.settings_path = settings_path
	root.add_child(boot_manager)
	_check(
		not boot_manager.is_bgm_enabled()
		and not boot_manager.is_sfx_enabled()
		and AudioServer.is_bus_mute(bgm_bus_index)
		and AudioServer.is_bus_mute(sfx_bus_index),
		"起動時 (_ready) のみで保存済み設定 (false, false) と BGM・SFX バス消音が復元される"
	)
	root.remove_child(boot_manager)
	boot_manager.free()

	AudioSettings.apply_to_audio_server(true, true)
	_check(
		audio_manager.reload_settings(settings_path) == OK,
		"保存済み設定ファイルを reload_settings で読み込める"
	)
	_check(
		AudioServer.is_bus_mute(bgm_bus_index) and AudioServer.is_bus_mute(sfx_bus_index),
		"reload_settings により保存済みの (false, false) が BGM・SFX バスの消音へ反映される"
	)
	var reopened_main: Node3D = MAIN_SCENE.instantiate()
	root.add_child(reopened_main)
	await process_frame
	var panel: Control = reopened_main.get_node_or_null(MainScript.SETTINGS_PANEL_PATH)
	var bgm_toggle: CheckButton = (
		panel.get_node_or_null(AudioSettingsPanelScript.BGM_TOGGLE_PATH) if panel != null else null
	)
	var sfx_toggle: CheckButton = (
		panel.get_node_or_null(AudioSettingsPanelScript.SFX_TOGGLE_PATH) if panel != null else null
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
	var bgm_player: AudioStreamPlayer = audio_manager.get_node_or_null(
		AudioManagerScript.BGM_PLAYER_NAME
	)
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
	# フォーカス一時停止中に同じ BGM を再指定しても頭から再生し直さず一時停止を維持する
	var play_count_while_paused: int = audio_manager.get_bgm_play_count()
	_check(
		audio_manager.play_bgm(AudioCatalog.BGM_TITLE)
		and audio_manager.get_bgm_play_count() == play_count_while_paused
		and audio_manager.is_bgm_paused_by_focus()
		and bgm_player.stream_paused,
		"一時停止中の同じ BGM 再指定では頭から再生し直さず一時停止を維持する"
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

	# 一時停止中に別曲へ切り替えても裏のまま鳴り出さず、曲だけ差し替えて復帰時に再開する
	audio_manager.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	audio_manager.play_bgm(AudioCatalog.BGM_MANSION)
	_check(
		audio_manager.get_current_bgm_name() == AudioCatalog.BGM_MANSION
		and audio_manager.is_bgm_paused_by_focus()
		and bgm_player.stream_paused
		and not bgm_player.playing,
		"一時停止中の別曲 play_bgm では裏のまま鳴り出さず一時停止を維持して曲を差し替える"
	)
	audio_manager.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	_check(
		audio_manager.get_current_bgm_name() == AudioCatalog.BGM_MANSION
		and not audio_manager.is_bgm_paused_by_focus()
		and not bgm_player.stream_paused
		and bgm_player.playing,
		"一時停止中に別曲へ切り替えた後の FOCUS_IN で新曲が再開される"
	)

	# 一時停止中に stop_bgm() すると一時停止状態とフラグが解除され、直後の FOCUS_IN でも再開しない
	audio_manager.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	audio_manager.stop_bgm()
	_check(
		not audio_manager.is_bgm_paused_by_focus()
		and not bgm_player.stream_paused
		and not bgm_player.playing,
		"一時停止中の stop_bgm() で一時停止状態とフラグが解除される"
	)
	audio_manager.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	_check(
		audio_manager.get_current_bgm_name().is_empty() and not bgm_player.playing,
		"一時停止中に stop_bgm() した後の FOCUS_IN で勝手に再開しない"
	)

	# 明示停止中は裏に回っても一時停止扱いにならず、戻っても playing が false のまま
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
	var player: AudioStreamPlayer = audio_manager.get_node_or_null(
		AudioManagerScript.SFX_PLAYER_NAME_FORMAT % audio_manager.get_last_sfx_player_index()
	)
	_check(
		audio_manager.get_sfx_play_count() == count_before + 1
		and audio_manager.get_last_sfx_event_name() == AudioCatalog.SFX_BUTTON
		and player != null
		and player.stream != null
		and player.stream.resource_path == AudioCatalog.resolve_sfx_path(AudioCatalog.SFX_BUTTON),
		"%s で効果音 button (sfx_button.ogg) が再生される" % action_label
	)


## 実 Godot プロセスへ渡された OS コマンドライン引数を GameState._ready() が適用することを検証する
func _run_cmdline_process_verification() -> void:
	var game_state: Node = root.get_node_or_null("GameState")
	_check(game_state != null, "OS 引数検証で autoload GameState が起動している")
	if game_state == null:
		return
	var main: Node3D = MAIN_SCENE.instantiate()
	root.add_child(main)
	await process_frame

	var world: MansionWorld = main.get_node("MansionWorld")
	var tuning: MansionTuning = game_state.get_tuning()
	_check(game_state.launched_with_cmdline_override, "OS 引数起動で上書きフラグが立っている")
	_check(tuning.room_count == 2, "OS 引数 --room-count=2 が GameState に反映される")
	_check(tuning.hair_count == 321, "OS 引数 --hair-count=321 が GameState に反映される")
	_check(tuning.object_count == 4, "OS 引数 --object-count=4 が GameState に反映される")
	_check(tuning.found_item_count == 1, "OS 引数 --found-item-count=1 が GameState に反映される")
	_check(is_equal_approx(tuning.room_size_m, 5.0), "OS 引数 --room-size=5.0 が反映される")
	_check(world.get_room_node_count() == 2, "OS 引数で屋敷の部屋ノード数が 2 になる")
	_check(world.get_object_node_count() == 4, "OS 引数で屋敷の物ノード数が 4 になる")

	main.enter_mansion()
	await process_frame
	var hair_label: Label = main.get_node("UILayer/UI/HUD/RemainingHairPanel/RemainingHairLabel")
	_check(
		hair_label.text.contains("321"),
		"OS 引数起動の HUD に 321 本が表示される (実際: %s)" % hair_label.text,
	)

	var audio_manager: AudioManagerScript = (
		AudioManagerScript.resolve(self) as AudioManagerScript
	)
	if audio_manager != null:
		audio_manager.stop_all()
		await create_timer(AudioManagerScript.AUDIO_RELEASE_TIME_SEC).timeout
	root.remove_child(main)
	main.free()


## タイトル表示・既定フォント設定と、タイトル中は移動・視点・F1・F5 が無効であることを検証する
func _verify_title_and_blocked_inputs(main: Node3D) -> void:
	var title_label: Label = main.get_node_or_null("UILayer/UI/TitleOverlay/Layout/TitleLabel")
	_check(title_label != null, "題名の Label がある")
	if title_label != null:
		_check(not title_label.text.is_empty(), "題名の Label に文字が入っている")
	var ui_theme: Theme = main.get_ui_theme()
	_check(ui_theme != null and ui_theme.default_font != null, "UI の theme に既定フォントが入っている")
	var start_button: Button = main.get_node("UILayer/UI/TitleOverlay/Layout/StartButton")
	var new_game_button: Button = main.get_node("UILayer/UI/TitleOverlay/Layout/NewGameButton")
	_check(
		main.get_node("UILayer/UI/TitleOverlay").visible and not main.get_node("UILayer/UI/HUD").visible,
		"起動時はタイトル表示で HUD は非表示",
	)
	_check(
		start_button.text == "はじめる" and not new_game_button.visible,
		"セーブ未作成時は『はじめる』のみ表示される",
	)

	var player: FirstPersonPlayer = main.get_node("Player")
	var before_pos: Vector3 = player.global_position
	Input.action_press("move_forward")
	for _step: int in range(6):
		await physics_frame
	Input.action_release("move_forward")
	_check(
		Vector2(player.global_position.x - before_pos.x, player.global_position.z - before_pos.z)
		.length()
		< 0.01,
		"タイトル表示中は前進入力しても水平移動しない",
	)

	# タイトル表示中 (controls_enabled = false) はマウス移動イベントでも視点が変わらない
	player.allow_uncaptured_look = true
	var yaw_before_title_look: float = player.rotation.y
	await _send_mouse_motion(Vector2(60.0, -30.0))
	player.allow_uncaptured_look = false
	_check(
		is_equal_approx(player.rotation.y, yaw_before_title_look),
		"controls_enabled=false の時はマウス移動イベントでも視点が変わらない",
	)

	await _press_physical_key(KEY_F1)
	var panel: DevTuningPanel = main.get_node("UILayer/UI/DevTuningPanel")
	_check(not panel.visible, "タイトル表示中は F1 を押しても開発者向け画面が開かない")

	await _press_physical_key(KEY_F5)
	_check(
		not SaveStorageScript.has_save_file(TEST_SAVE_PATH),
		"タイトル表示中は F5 を押してもセーブされない",
	)


## 屋敷へ入った後の HUD 表示・床接地・壁衝突・ドア通過・4 方向移動・視点入力とクランプを検証する
func _verify_enter_movement_and_look(main: Node3D) -> void:
	main.get_node("UILayer/UI/TitleOverlay/Layout/StartButton").pressed.emit()
	await process_frame

	var hair_label: Label = main.get_node("UILayer/UI/HUD/RemainingHairPanel/RemainingHairLabel")
	_check(main.get_node("UILayer/UI/HUD").visible, "はじめる押下で HUD が表示される")
	_check(
		hair_label.text.contains("12,000"),
		"残り毛本数の表示に既定値 12,000 が出ている (実際: %s)" % hair_label.text,
	)

	var player: FirstPersonPlayer = main.get_node("Player")
	# 数物理フレーム進めて床の上に接地していることを確認 (床衝突が無いと落下し続ける)
	for _step: int in range(6):
		await physics_frame
	_check(
		player.is_on_floor() and player.global_position.y >= -0.05,
		"プレイヤーが床の衝突体の上に接地している (y=%.3f)" % player.global_position.y,
	)

	# 南の閉じた壁へ向かって十分後退しても壁衝突で部屋の外 (z > 3.0) へ抜けないことを確認
	await _hold_move_action("move_back", 45)
	_check(
		player.global_position.z < MansionTuningScript.DEFAULT_ROOM_SIZE_M * 0.5,
		"南側の閉じた壁の衝突体で止まり外へ抜けない (z=%.3f)" % player.global_position.z,
	)

	# 前進 (-Z)・後退 (+Z)・左 (-X)・右 (+X) の 4 方向すべての向きを検証
	var pos_before_fwd: Vector3 = player.global_position
	await _hold_move_action("move_forward", 8)
	_check(player.global_position.z < pos_before_fwd.z - 0.1, "前進入力で -Z 方向へ移動する")

	var pos_before_back: Vector3 = player.global_position
	await _hold_move_action("move_back", 6)
	_check(player.global_position.z > pos_before_back.z + 0.1, "後退入力で +Z 方向へ移動する")

	var pos_before_left: Vector3 = player.global_position
	await _hold_move_action("move_left", 6)
	_check(player.global_position.x < pos_before_left.x - 0.1, "左移動入力で -X 方向へ移動する")

	var pos_before_right: Vector3 = player.global_position
	await _hold_move_action("move_right", 6)
	_check(player.global_position.x > pos_before_right.x + 0.1, "右移動入力で +X 方向へ移動する")

	# 中央 (x=0) へ戻って北側ドア開口を通過し隣室 (z < -room_size/2) へ入れることを確認
	player.global_position = Vector3(0.0, 0.05, 0.0)
	await _hold_move_action("move_forward", 60)
	_check(
		player.global_position.z < -MansionTuningScript.DEFAULT_ROOM_SIZE_M * 0.5,
		"北側ドア開口を通って隣室へ移動できる (z=%.3f)" % player.global_position.z,
	)

	# Esc キー入力 (release_mouse) がエラーなく処理されることを確認
	await _press_physical_key(KEY_ESCAPE)

	# マウス未捕捉 + allow_uncaptured_look=false では視点が変わらない
	player.allow_uncaptured_look = false
	var yaw_uncaptured: float = player.rotation.y
	var pitch_uncaptured: float = player.get_pitch()
	await _send_mouse_motion(Vector2(50.0, -25.0))
	_check(
		is_equal_approx(player.rotation.y, yaw_uncaptured)
		and is_equal_approx(player.get_pitch(), pitch_uncaptured),
		"マウス未捕捉かつ allow_uncaptured_look=false では視点が変わらない",
	)

	# allow_uncaptured_look=true で InputEventMouseMotion が _unhandled_input を通って視点を動かす
	player.allow_uncaptured_look = true
	await _send_mouse_motion(Vector2(40.0, -30.0))
	_check(
		not is_equal_approx(player.rotation.y, yaw_uncaptured)
		and not is_equal_approx(player.get_pitch(), pitch_uncaptured),
		"InputEventMouseMotion が _unhandled_input を通ってヨー角とピッチ角を動かす",
	)
	player.allow_uncaptured_look = false

	# 上下限のピッチクランプを FirstPersonPlayer.MAX_PITCH_RADIANS で両側検証
	player.apply_look_delta(Vector2(0.0, -99999.0))
	_check(
		is_equal_approx(player.get_pitch(), FirstPersonPlayerScript.MAX_PITCH_RADIANS),
		"極端な上向き入力でピッチ角が +MAX_PITCH_RADIANS にクランプされる",
	)
	player.apply_look_delta(Vector2(0.0, 99999.0))
	_check(
		is_equal_approx(player.get_pitch(), -FirstPersonPlayerScript.MAX_PITCH_RADIANS),
		"極端な下向き入力でピッチ角が -MAX_PITCH_RADIANS にクランプされる",
	)


## F1 トグル開閉・閉じるボタン・調整値変更での屋敷作り直しと load_from_tuning 反映を検証する
func _verify_dev_panel_keys_and_rebuild(main: Node3D, game_state: Node) -> void:
	var world: MansionWorld = main.get_node("MansionWorld")
	var panel: DevTuningPanel = main.get_node("UILayer/UI/DevTuningPanel")
	var player: FirstPersonPlayer = main.get_node("Player")
	var hair_label: Label = main.get_node("UILayer/UI/HUD/RemainingHairPanel/RemainingHairLabel")

	_check(
		world.get_room_node_count() == MansionTuningScript.DEFAULT_ROOM_COUNT,
		"作り直し前の部屋ノード数が既定値と一致する",
	)
	_check(
		world.get_object_node_count() == MansionTuningScript.DEFAULT_OBJECT_COUNT,
		"作り直し前の物ノード数が既定値と一致する",
	)

	# F1 キーで開く → F1 キーで閉じるトグル分岐を検証
	await _press_physical_key(KEY_F1)
	_check(panel.visible and not player.controls_enabled, "F1 キー入力で開発者向け画面が開く")

	var pos_while_open: Vector3 = player.global_position
	await _hold_move_action("move_forward", 6)
	_check(
		Vector2(
			player.global_position.x - pos_while_open.x,
			player.global_position.z - pos_while_open.z,
		).length()
		< 0.01,
		"開発者向け画面が開いている間は前進入力しても移動しない",
	)

	await _press_physical_key(KEY_F1)
	_check(not panel.visible and player.controls_enabled, "開いた状態で F1 再押下すると閉じる")

	# 閉じるボタン分岐も検証
	await _press_physical_key(KEY_F1)
	panel.close_button.pressed.emit()
	await process_frame
	_check(not panel.visible and player.controls_enabled, "閉じるボタンでパネルが閉じて操作再開する")

	# F1 で再度開き、調整値を変更して屋敷を作り直す
	await _press_physical_key(KEY_F1)
	panel.hair_count_spin.value = 500.0
	panel.found_item_count_spin.value = 2.0
	panel.room_size_spin.value = 8.0
	panel.object_count_spin.value = 6.0
	panel.room_count_spin.value = 2.0
	panel.apply_button.pressed.emit()
	await process_frame

	_check(not panel.visible and player.controls_enabled, "適用後に開発者向け画面が閉じて操作再開する")
	_check(world.get_room_node_count() == 2, "屋敷を作り直すと部屋ノード数が 2 に変わる")
	_check(world.get_object_node_count() == 6, "屋敷を作り直すと物ノード数が 6 に変わる")
	_check(game_state.get_total_remaining_hairs() == 500, "屋敷を作り直すと総毛本数が 500 に変わる")
	_check(
		game_state.current_layout.found_item_spots.size() == 2,
		"屋敷を作り直すと探し物置き場所が 2 に変わる",
	)
	_check(hair_label.text.contains("500"), "HUD の残り毛本数が 500 に更新される")

	# 一度入力欄を別値に変えてから F1 で再度開き、load_from_tuning が現在値 5 項目を復元することを検証
	panel.hair_count_spin.value = 1.0
	panel.room_count_spin.value = 1.0
	await _press_physical_key(KEY_F1)
	_check(
		int(round(panel.hair_count_spin.value)) == 500
		and int(round(panel.found_item_count_spin.value)) == 2
		and is_equal_approx(panel.room_size_spin.value, 8.0)
		and int(round(panel.object_count_spin.value)) == 6
		and int(round(panel.room_count_spin.value)) == 2,
		"開発者向け画面を再度開くと現在の 5 調整値が入力欄へ反映される",
	)
	await _press_physical_key(KEY_F1)

	var reloaded_state: Node = GameStateScript.new()
	reloaded_state.initialize_from_storage(TEST_SAVE_PATH)
	_check(
		reloaded_state.loaded_from_save
		and reloaded_state.get_tuning().room_count == 2
		and reloaded_state.get_tuning().object_count == 6
		and reloaded_state.get_tuning().hair_count == 500
		and reloaded_state.get_tuning().found_item_count == 2
		and is_equal_approx(reloaded_state.get_tuning().room_size_m, 8.0),
		"再起動後に保存した 5 つの調整値がそのまま復元される",
	)
	reloaded_state.free()


## F5 手動セーブキーと NOTIFICATION_WM_CLOSE_REQUEST 終了時保存を検証する
func _verify_manual_save_and_close_request(game_state: Node) -> void:
	game_state.save_data.building_progress.money = 999
	await _press_physical_key(KEY_F5)
	var after_f5: SaveData = SaveStorageScript.load_from_path(TEST_SAVE_PATH)
	_check(
		after_f5 != null and after_f5.building_progress.money == 999,
		"プレイ中の F5 キー入力で所持金 999 が手動保存される",
	)

	game_state.save_data.building_progress.money = 1234
	game_state.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	var after_close: SaveData = SaveStorageScript.load_from_path(TEST_SAVE_PATH)
	_check(
		after_close != null and after_close.building_progress.money == 1234,
		"NOTIFICATION_WM_CLOSE_REQUEST で所持金 1234 が保存される",
	)


## 保存データがある状態での起動表示 (「続きから」「はじめから」) と「はじめから」動作を検証する
func _verify_resume_and_new_game_from_saved_state(game_state: Node) -> void:
	game_state.initialize_from_storage(TEST_SAVE_PATH)
	var resumed_main: Node3D = MAIN_SCENE.instantiate()
	root.add_child(resumed_main)
	await process_frame

	var start_button: Button = resumed_main.get_node("UILayer/UI/TitleOverlay/Layout/StartButton")
	var new_game_button: Button = resumed_main.get_node(
		"UILayer/UI/TitleOverlay/Layout/NewGameButton"
	)
	_check(
		start_button.text == "続きから" and new_game_button.visible,
		"保存データあり起動時は『続きから』と『はじめから』が表示される",
	)

	new_game_button.pressed.emit()
	await process_frame
	_check(
		resumed_main.get_node("UILayer/UI/HUD").visible and game_state.get_money() == 0,
		"『はじめから』押下で初期化して屋敷へ入る",
	)
	var saved_after_reset: SaveData = SaveStorageScript.load_from_path(TEST_SAVE_PATH)
	_check(
		saved_after_reset != null
		and saved_after_reset.building_progress.money == 0
		and saved_after_reset.tuning.room_count == 2
		and saved_after_reset.tuning.hair_count == 500
		and saved_after_reset.tuning.object_count == 6
		and saved_after_reset.tuning.found_item_count == 2
		and is_equal_approx(saved_after_reset.tuning.room_size_m, 8.0),
		"『はじめから』で現在の調整値を引き継ぎ初期化した進行を保存ファイルへ書き出す",
	)

	root.remove_child(resumed_main)
	resumed_main.free()


## 指定した移動アクションを指定フレーム数だけ押し続けてから離す
func _hold_move_action(action_name: String, frame_count: int) -> void:
	Input.action_press(action_name)
	for _step: int in range(frame_count):
		await physics_frame
	Input.action_release(action_name)
	await physics_frame


## 指定した物理キーの押下・解放イベントを Input に流して 1 フレーム進める
func _press_physical_key(physical_key: Key) -> void:
	var press_event: InputEventKey = InputEventKey.new()
	press_event.physical_keycode = physical_key
	press_event.pressed = true
	Input.parse_input_event(press_event)
	await process_frame

	var release_event: InputEventKey = InputEventKey.new()
	release_event.physical_keycode = physical_key
	release_event.pressed = false
	Input.parse_input_event(release_event)
	await process_frame


## マウス移動イベントを Input に流して 1 フレーム進める
func _send_mouse_motion(relative_delta: Vector2) -> void:
	var motion_event: InputEventMouseMotion = InputEventMouseMotion.new()
	motion_event.relative = relative_delta
	Input.parse_input_event(motion_event)
	await process_frame

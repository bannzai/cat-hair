extends "res://scripts/dev/headless_check.gd"
## メインシーンを tree に置いて動かす入力統合テスト (headless)。画面の遷移や入力で変わる振る舞いを足したら、
## ここに検証を足す。実行方法は AGENTS.md「検証方法」を参照。

## 動かして確かめるメインシーン
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
## 毛の描画の試作シーン
const HAIR_PROTOTYPE_SCENE: PackedScene = preload("res://scenes/hair_prototype.tscn")
## メインシーンのノードパス定数参照用
const MainScript := preload("res://scripts/main.gd")
## 音声カタログ
const AudioCatalog := preload("res://scripts/audio/audio_catalog.gd")
## 音声設定の永続化検証用
const AudioSettings := preload("res://scripts/audio/audio_settings.gd")
## 設定画面パネルのノードパス定数参照用
const AudioSettingsPanelScript := preload("res://scripts/ui/audio_settings_panel.gd")


## tree の準備が終わってから _run() を始める (シーンの追加は _initialize() の後でないとできない)
func _initialize() -> void:
	_run.call_deferred()


## フレームを進めながら検証するため、同じ実行中に重ねて呼び出さない
func _run() -> void:
	var settings_path: String = ProjectSettings.globalize_path(
		"res://tmp/integration-audio-settings.cfg"
	)
	var audio_handle: Dictionary = prepare_audio_manager(self, settings_path)
	var audio_manager: AudioManagerScript = audio_handle["manager"] as AudioManagerScript

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
	await create_timer(AudioManagerScript.AUDIO_RELEASE_TIME_SEC).timeout
	root.remove_child(main)
	main.free()
	cleanup_audio_manager(self, audio_handle, settings_path)

	await _verify_hair_prototype_scene()
	_finish()


## 題名画面の基本表示 (Label と既定フォント) を確認する
func _check_title_screen_basics(main: Control) -> void:
	var title_label: Label = main.get_node_or_null("Layout/TitleLabel")
	_check(title_label != null, "題名の Label (Layout/TitleLabel) がある")
	if title_label != null:
		_check(not title_label.text.is_empty(), "題名の Label に文字が入っている")
	_check(main.theme != null and main.theme.default_font != null, "メインシーンの theme に既定フォントが入っている")


## 毛の描画試作シーンで 2 表面への配置と 1 本削除が連動するか検証する
func _verify_hair_prototype_scene() -> void:
	var hair_prototype: Node3D = HAIR_PROTOTYPE_SCENE.instantiate()
	root.add_child(hair_prototype)
	await process_frame

	var field: Node3D = hair_prototype.get_hair_field()
	_check(field != null, "HairPrototype に HairField ノードがある")
	_check(field.get_surface_count() == 2, "床とソファの 2 表面が登録されている")

	_check(
		hair_prototype.populate_hairs(100) == 100 and hair_prototype.get_remaining_count() == 100,
		"試作シーンに 100 本の毛を配置できる"
	)
	_check(
		field.get_surface_visible_instance_count(0)
		+ field.get_surface_visible_instance_count(1)
		== 100,
		"2 表面の visible_instance_count 合計が 100"
	)

	var removed: bool = hair_prototype.remove_hair(0)
	await process_frame
	_check(
		removed
		and hair_prototype.get_remaining_count() == 99
		and field.get_surface_visible_instance_count(0)
		+ field.get_surface_visible_instance_count(1)
		== 99,
		"試作シーンで 1 本だけ抜いて残り本数・visible_instance_count が 99 になる"
	)

	root.remove_child(hair_prototype)
	hair_prototype.free()


## 題名画面起動時の BGM 再生、同一曲の継続、停止後の再再生、ループ有効化、効果音の出来事別入口を確認する
func _check_audio_playback_entry(audio_manager: AudioManagerScript, main: Control) -> void:
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
	audio_manager: AudioManagerScript, main: Control, settings_path: String
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
	var reopened_main: Control = MAIN_SCENE.instantiate()
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

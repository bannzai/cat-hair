extends "res://scripts/dev/headless_check.gd"
## 純粋なロジックとプロジェクト設定の検証 (headless)。ゲームのルールの計算を足したら、ここに検証を足す。
## 実行方法は AGENTS.md「検証方法」を参照。

## プロジェクト設定のメインシーンに入っているべきパス
const MAIN_SCENE_PATH: String = "res://scenes/main.tscn"
## プロジェクト設定の名前に入っているべき値 (ゲームの題名)
const PROJECT_NAME: String = "Oh My Fur!"
## プロジェクト設定の音声バスレイアウトのパス
const BUS_LAYOUT_PATH: String = "res://default_bus_layout.tres"
## プロジェクト設定の AudioManager autoload の値
const AUDIO_MANAGER_AUTOLOAD: String = "*res://scripts/audio/audio_manager.gd"
## 音声カタログ (純粋関数)
const AudioCatalog := preload("res://scripts/audio/audio_catalog.gd")
## 音声設定の保存・読み込み・バス適用
const AudioSettings := preload("res://scripts/audio/audio_settings.gd")


## 検証をすべて実行して終える
func _initialize() -> void:
	_check_project_settings()
	_check_main_scene_loads()
	_check_audio_bus_layout()
	_check_audio_catalog()
	_check_audio_settings_persistence()
	_check_audio_settings_bus_mute()
	_finish()


## プロジェクト設定の名前・メインシーン・音声設定が想定どおりか
func _check_project_settings() -> void:
	var main_scene: String = ProjectSettings.get_setting("application/run/main_scene", "")
	_check(
		main_scene == MAIN_SCENE_PATH,
		"application/run/main_scene が %s (実際: %s)" % [MAIN_SCENE_PATH, main_scene]
	)
	var project_name: String = ProjectSettings.get_setting("application/config/name", "")
	_check(
		project_name == PROJECT_NAME,
		"application/config/name が %s (実際: %s)" % [PROJECT_NAME, project_name]
	)
	var bus_layout: String = ProjectSettings.get_setting("audio/buses/default_bus_layout", "")
	_check(
		bus_layout == BUS_LAYOUT_PATH,
		"audio/buses/default_bus_layout が %s (実際: %s)" % [BUS_LAYOUT_PATH, bus_layout]
	)
	var autoload_entry: String = ProjectSettings.get_setting("autoload/AudioManager", "")
	_check(
		autoload_entry == AUDIO_MANAGER_AUTOLOAD,
		"autoload/AudioManager が %s (実際: %s)" % [AUDIO_MANAGER_AUTOLOAD, autoload_entry]
	)


## メインシーンがロードでき、PackedScene が返るか
func _check_main_scene_loads() -> void:
	_check(
		load(MAIN_SCENE_PATH) is PackedScene,
		"%s が PackedScene としてロードできる" % MAIN_SCENE_PATH
	)


## BGM と効果音のバスが別々に定義され、効果音が BGM より大きい音量設定になっているか
func _check_audio_bus_layout() -> void:
	var bgm_idx: int = AudioServer.get_bus_index(AudioCatalog.BUS_BGM)
	var sfx_idx: int = AudioServer.get_bus_index(AudioCatalog.BUS_SFX)
	_check(bgm_idx >= 0, "AudioServer に BGM バスがある (index: %d)" % bgm_idx)
	_check(sfx_idx >= 0, "AudioServer に SFX バスがある (index: %d)" % sfx_idx)
	_check(bgm_idx != sfx_idx, "BGM バスと SFX バスが別々である")
	if bgm_idx >= 0 and sfx_idx >= 0:
		var bgm_db: float = AudioServer.get_bus_volume_db(bgm_idx)
		var sfx_db: float = AudioServer.get_bus_volume_db(sfx_idx)
		_check(
			bgm_db < sfx_db,
			"効果音を目立たせるため BGM 音量 (%s dB) < SFX 音量 (%s dB)" % [bgm_db, sfx_db]
		)


## 場面名・出来事名から音声パスを選ぶ純粋関数の正常系・異常系・境界値・実ファイル存在確認
func _check_audio_catalog() -> void:
	var expected_bgm: Dictionary = {
		"title": "res://assets/audio/bgm_title.ogg",
		"mansion": "res://assets/audio/bgm_mansion.ogg",
	}
	var expected_sfx: Dictionary = {
		"pluck_hair": "res://assets/audio/sfx_pluck_hair.ogg",
		"earn_money": "res://assets/audio/sfx_earn_money.ogg",
		"buy_tool": "res://assets/audio/sfx_buy_tool.ogg",
		"button": "res://assets/audio/sfx_button.ogg",
	}
	_check(
		AudioCatalog.all_bgm_names().size() == expected_bgm.size(),
		"BGM 登録数が %d 件 (実際: %d)" % [expected_bgm.size(), AudioCatalog.all_bgm_names().size()]
	)
	_check(
		AudioCatalog.all_sfx_names().size() == expected_sfx.size(),
		"効果音登録数が %d 件 (実際: %d)" % [expected_sfx.size(), AudioCatalog.all_sfx_names().size()]
	)
	for scene_name: String in expected_bgm.keys():
		var expected_path: String = String(expected_bgm[scene_name])
		var actual_path: String = AudioCatalog.resolve_bgm_path(scene_name)
		_check(
			actual_path == expected_path,
			"BGM '%s' のパスが %s (実際: %s)" % [scene_name, expected_path, actual_path]
		)
		_check(
			ResourceLoader.exists(actual_path) and load(actual_path) is AudioStream,
			"BGM '%s' の素材 %s が AudioStream として読み込める" % [scene_name, actual_path]
		)
	for event_name: String in expected_sfx.keys():
		var expected_path: String = String(expected_sfx[event_name])
		var actual_path: String = AudioCatalog.resolve_sfx_path(event_name)
		_check(
			actual_path == expected_path,
			"効果音 '%s' のパスが %s (実際: %s)" % [event_name, expected_path, actual_path]
		)
		_check(
			ResourceLoader.exists(actual_path) and load(actual_path) is AudioStream,
			"効果音 '%s' の素材 %s が AudioStream として読み込める" % [event_name, actual_path]
		)
	# 異常系・境界値: 空文字・未登録名・大文字小文字違い・末尾空白・BGM/SFX の取り違え
	var invalid_bgm_inputs: PackedStringArray = PackedStringArray([
		"", "unknown", "TITLE", "title ", "button", "pluck_hair"
	])
	for bad_bgm: String in invalid_bgm_inputs:
		_check(
			AudioCatalog.resolve_bgm_path(bad_bgm).is_empty(),
			"未登録の BGM 名 '%s' は空文字を返す" % bad_bgm
		)
	var invalid_sfx_inputs: PackedStringArray = PackedStringArray([
		"", "unknown", "BUTTON", "pluck_hair ", "title", "mansion"
	])
	for bad_sfx: String in invalid_sfx_inputs:
		_check(
			AudioCatalog.resolve_sfx_path(bad_sfx).is_empty(),
			"未登録の効果音名 '%s' は空文字を返す" % bad_sfx
		)


## ConfigFile による設定の保存・読み戻し (正常系 4 パターン + 異常系・境界値)
func _check_audio_settings_persistence() -> void:
	var test_path: String = ProjectSettings.globalize_path("res://tmp/selfcheck-audio-settings.cfg")
	_remove_file_if_exists(test_path)

	# 初期値
	var defaults: RefCounted = AudioSettings.new()
	_check(defaults.bgm_enabled and defaults.sfx_enabled, "音声設定の初期値は BGM・効果音ともオン")

	# 正常系: 4 通りの組み合わせを保存して別インスタンスで読み戻す
	var combinations: Array = [
		[false, true],
		[true, false],
		[false, false],
		[true, true],
	]
	for pair: Array in combinations:
		var expected_bgm: bool = bool(pair[0])
		var expected_sfx: bool = bool(pair[1])
		var writer: RefCounted = AudioSettings.new(expected_bgm, expected_sfx)
		var save_err: Error = writer.save_to_path(test_path)
		_check(save_err == OK, "設定 (%s, %s) の保存が OK" % [expected_bgm, expected_sfx])
		var reader: RefCounted = AudioSettings.new(not expected_bgm, not expected_sfx)
		var load_err: Error = reader.load_from_path(test_path)
		_check(load_err == OK, "設定 (%s, %s) の読み込みが OK" % [expected_bgm, expected_sfx])
		_check(
			reader.bgm_enabled == expected_bgm and reader.sfx_enabled == expected_sfx,
			"保存した (%s, %s) を読み戻せる (実際: %s, %s)" % [
				expected_bgm, expected_sfx, reader.bgm_enabled, reader.sfx_enabled
			]
		)

	# 異常系: 空パス
	var empty_writer: RefCounted = AudioSettings.new(false, false)
	_check(
		empty_writer.save_to_path("") == ERR_INVALID_PARAMETER,
		"空パスへの保存は ERR_INVALID_PARAMETER を返す"
	)
	_check(
		empty_writer.load_from_path("") == ERR_INVALID_PARAMETER,
		"空パスからの読み込みは ERR_INVALID_PARAMETER を返す"
	)
	_check(
		empty_writer.bgm_enabled and empty_writer.sfx_enabled,
		"空パス読み込み失敗時は既定値 (オン, オン) に戻る"
	)

	# 異常系: 存在しないファイル
	_remove_file_if_exists(test_path)
	var missing_reader: RefCounted = AudioSettings.new(false, false)
	var missing_err: Error = missing_reader.load_from_path(test_path)
	_check(missing_err != OK, "存在しない設定ファイルの読み込みはエラーを返す")
	_check(
		missing_reader.bgm_enabled and missing_reader.sfx_enabled,
		"存在しない設定ファイルの読み込み時は既定値 (オン, オン) に戻る"
	)

	# 異常系: 対象セクションが無いファイル (エンジン ERROR を出さない有効な INI 構文)
	_write_raw_text(test_path, "[other]\nvalue=1\n")
	var other_section_reader: RefCounted = AudioSettings.new(false, false)
	_check(
		other_section_reader.load_from_path(test_path) == OK,
		"audio セクションが無い設定ファイルはエラーなく読み込める"
	)
	_check(
		other_section_reader.bgm_enabled and other_section_reader.sfx_enabled,
		"audio セクションが無い設定ファイルは既定値 (オン, オン) になる"
	)

	# 異常系: 不正型 (片方だけ正常・片方だけ不正型) とキー欠落
	_write_raw_text(test_path, "[audio]\nbgm_enabled=false\nsfx_enabled=\"bad\"\n")
	var partial_type_reader: RefCounted = AudioSettings.new(true, false)
	_check(partial_type_reader.load_from_path(test_path) == OK, "不正型混在ファイルは安全に読める")
	_check(
		(not partial_type_reader.bgm_enabled) and partial_type_reader.sfx_enabled,
		"正常な bgm_enabled=false は保持し、不正型の sfx_enabled は既定値 true になる"
	)

	_write_raw_text(test_path, "[audio]\nsfx_enabled=false\n")
	var missing_key_reader: RefCounted = AudioSettings.new(false, true)
	_check(missing_key_reader.load_from_path(test_path) == OK, "片方欠落ファイルは安全に読める")
	_check(
		missing_key_reader.bgm_enabled and (not missing_key_reader.sfx_enabled),
		"欠落した bgm_enabled は既定値 true、存在する sfx_enabled=false は保持する"
	)

	_remove_file_if_exists(test_path)


## AudioSettings.apply_to_audio_server が BGM・SFX バスを個別に消音できるか
func _check_audio_settings_bus_mute() -> void:
	var bgm_idx: int = AudioServer.get_bus_index(AudioCatalog.BUS_BGM)
	var sfx_idx: int = AudioServer.get_bus_index(AudioCatalog.BUS_SFX)
	if bgm_idx < 0 or sfx_idx < 0:
		return
	AudioSettings.apply_to_audio_server(false, true)
	_check(
		AudioServer.is_bus_mute(bgm_idx) and not AudioServer.is_bus_mute(sfx_idx),
		"BGM オフ・効果音オンで BGM バスだけ消音になる"
	)
	AudioSettings.apply_to_audio_server(true, false)
	_check(
		(not AudioServer.is_bus_mute(bgm_idx)) and AudioServer.is_bus_mute(sfx_idx),
		"BGM オン・効果音オフで SFX バスだけ消音になる"
	)
	AudioSettings.apply_to_audio_server(false, false)
	_check(
		AudioServer.is_bus_mute(bgm_idx) and AudioServer.is_bus_mute(sfx_idx),
		"両方オフで BGM・SFX バスとも消音になる"
	)
	AudioSettings.apply_to_audio_server(true, true)
	_check(
		(not AudioServer.is_bus_mute(bgm_idx)) and (not AudioServer.is_bus_mute(sfx_idx)),
		"両方オンで BGM・SFX バスとも消音解除になる"
	)


## テスト用の一時ファイルを削除する
func _remove_file_if_exists(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


## 異常系テスト用に任意の文字列をファイルへ書き出す
func _write_raw_text(path: String, content: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(content)
		file.close()

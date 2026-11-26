extends RefCounted
## BGM と効果音のオン・オフ設定の保持、ConfigFile での永続化、AudioServer バスへの適用を担う。

## バス名の定数を持つ音声カタログ
const AudioCatalog := preload("res://scripts/audio/audio_catalog.gd")

## 端末ローカルの既定の保存先
const DEFAULT_PATH: String = "user://audio_settings.cfg"
## ConfigFile のセクション名
const SECTION: String = "audio"
## ConfigFile の BGM オン・オフのキー
const KEY_BGM_ENABLED: String = "bgm_enabled"
## ConfigFile の効果音オン・オフのキー
const KEY_SFX_ENABLED: String = "sfx_enabled"

## BGM がオンか (初回既定値はオン)
var bgm_enabled: bool = true
## 効果音がオンか (初回既定値はオン)
var sfx_enabled: bool = true


## 初期値を指定して設定を作る
func _init(initial_bgm_enabled: bool = true, initial_sfx_enabled: bool = true) -> void:
	bgm_enabled = initial_bgm_enabled
	sfx_enabled = initial_sfx_enabled


## 現在の設定を path に ConfigFile 形式で保存する
func save_to_path(path: String = DEFAULT_PATH) -> Error:
	if path.is_empty():
		return ERR_INVALID_PARAMETER
	var config: ConfigFile = ConfigFile.new()
	config.set_value(SECTION, KEY_BGM_ENABLED, true)
	config.set_value(SECTION, KEY_SFX_ENABLED, sfx_enabled)
	return config.save(path)


## path から ConfigFile を読み込み、設定を更新する。失敗時は既定値 (どちらもオン) に戻す
func load_from_path(path: String = DEFAULT_PATH) -> Error:
	bgm_enabled = true
	sfx_enabled = true
	if path.is_empty():
		return ERR_INVALID_PARAMETER
	var config: ConfigFile = ConfigFile.new()
	var err: Error = config.load(path)
	if err != OK:
		return err
	var raw_bgm: Variant = config.get_value(SECTION, KEY_BGM_ENABLED, true)
	var raw_sfx: Variant = config.get_value(SECTION, KEY_SFX_ENABLED, true)
	bgm_enabled = raw_bgm if raw_bgm is bool else true
	sfx_enabled = raw_sfx if raw_sfx is bool else true
	return OK


## AudioServer の BGM・SFX バスの消音状態を設定に合わせる
static func apply_to_audio_server(is_bgm_on: bool, is_sfx_on: bool) -> void:
	var bgm_bus_index: int = AudioServer.get_bus_index(AudioCatalog.BUS_BGM)
	if bgm_bus_index >= 0:
		AudioServer.set_bus_mute(bgm_bus_index, not is_bgm_on)
	var sfx_bus_index: int = AudioServer.get_bus_index(AudioCatalog.BUS_SFX)
	if sfx_bus_index >= 0:
		AudioServer.set_bus_mute(sfx_bus_index, not is_sfx_on)

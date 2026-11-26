extends Control
## BGM と効果音のオン・オフを個別に切り替える設定画面。
## 切替と同時に AudioManager を通じてバス消音へ反映し、ConfigFile へ保存する。

## 出来事名の定数を持つ音声カタログ
const AudioCatalog := preload("res://scripts/audio/audio_catalog.gd")
## AudioManager の型解決と実行時取得用スクリプト参照 (headless --script で autoload 名を静的参照しない)
const AudioManagerScript := preload("res://scripts/audio/audio_manager.gd")
## BGM トグルのパネル内ノードパス (UI とテストで共有する単一の正)
const BGM_TOGGLE_PATH: String = "CenterContainer/Panel/MarginContainer/VBoxContainer/BGMToggle"
## 効果音トグルのパネル内ノードパス (UI とテストで共有する単一の正)
const SFX_TOGGLE_PATH: String = "CenterContainer/Panel/MarginContainer/VBoxContainer/SFXToggle"
## 閉じるボタンのパネル内ノードパス (UI とテストで共有する単一の正)
const CLOSE_BUTTON_PATH: String = "CenterContainer/Panel/MarginContainer/VBoxContainer/CloseButton"

## BGM のオン・オフを切り替えるチェックボタン
var _bgm_toggle: CheckButton = null
## 効果音のオン・オフを切り替えるチェックボタン
var _sfx_toggle: CheckButton = null
## 設定画面を閉じるボタン
var _close_button: Button = null


## UI のシグナルを接続し、現在の音声設定を表示へ反映する
func _ready() -> void:
	_bgm_toggle = get_node(BGM_TOGGLE_PATH) as CheckButton
	_sfx_toggle = get_node(SFX_TOGGLE_PATH) as CheckButton
	_close_button = get_node(CLOSE_BUTTON_PATH) as Button
	_bgm_toggle.toggled.connect(_on_bgm_toggled)
	_sfx_toggle.toggled.connect(_on_sfx_toggled)
	_close_button.pressed.connect(_on_close_pressed)
	_sync_from_audio_manager()


## 現在の設定値を読み直してから設定画面を表示する
func open() -> void:
	_sync_from_audio_manager()
	visible = true


## 設定画面を閉じる
func close() -> void:
	visible = false


## AudioManager の現在値をチェックボタンへ反映する (シグナルを発火させない)
func _sync_from_audio_manager() -> void:
	var audio_manager: AudioManagerScript = (
		AudioManagerScript.resolve(get_tree()) as AudioManagerScript
	)
	if audio_manager == null:
		return
	_bgm_toggle.set_pressed_no_signal(audio_manager.is_bgm_enabled())
	_sfx_toggle.set_pressed_no_signal(audio_manager.is_sfx_enabled())


## BGM トグル切替時の処理
func _on_bgm_toggled(toggled_on: bool) -> void:
	var audio_manager: AudioManagerScript = (
		AudioManagerScript.resolve(get_tree()) as AudioManagerScript
	)
	if audio_manager == null:
		return
	audio_manager.set_bgm_enabled(toggled_on)
	audio_manager.play_sfx(AudioCatalog.SFX_BUTTON)


## 効果音トグル切替時の処理
func _on_sfx_toggled(toggled_on: bool) -> void:
	var audio_manager: AudioManagerScript = (
		AudioManagerScript.resolve(get_tree()) as AudioManagerScript
	)
	if audio_manager == null:
		return
	audio_manager.set_sfx_enabled(toggled_on)
	audio_manager.play_sfx(AudioCatalog.SFX_BUTTON)


## 閉じるボタン押下時の処理
func _on_close_pressed() -> void:
	AudioManagerScript.play_button_sfx(get_tree())
	close()

extends Control
## ゲームのメインシーン。題名の画面の表示、題名 BGM の再生、ボタンの効果音と設定画面の開閉を担う。

## make check がメインシーンのロードと _ready の実行を確かめる印
const BOOT_MESSAGE: String = "cat-hair boot"
## プロジェクト全体の既定フォント (日本語の字形を持つ。出典は assets/CREDITS.md)
const FONT: Font = preload("res://assets/fonts/NotoSansJP[wght].ttf")
## 場面名・出来事名のカタログ
const AudioCatalog := preload("res://scripts/audio/audio_catalog.gd")
## AudioManager の型解決と実行時取得用スクリプト参照 (headless --script で autoload 名を静的参照しない)
const AudioManagerScript := preload("res://scripts/audio/audio_manager.gd")
## 設定画面パネルの型解決用スクリプト参照
const AudioSettingsPanelScript := preload("res://scripts/ui/audio_settings_panel.gd")

## はじめるボタン
@onready var _start_button: Button = $Layout/StartButton
## 設定ボタン
@onready var _settings_button: Button = $Layout/SettingsButton
## 設定画面パネル
@onready var _settings_panel: AudioSettingsPanelScript = (
	$AudioSettingsPanel as AudioSettingsPanelScript
)


## 起動の入口
func _ready() -> void:
	# フォントは project.godot の gui/theme/custom_font ではなく、このノードの theme として設定する (子にも効く)。
	# custom_font で指定すると、初回の import でフォントの import より先に読もうとして ERROR になる
	var main_theme: Theme = Theme.new()
	main_theme.default_font = FONT
	theme = main_theme
	_start_button.pressed.connect(_on_start_button_pressed)
	_settings_button.pressed.connect(_on_settings_button_pressed)
	var audio_manager: AudioManagerScript = (
		AudioManagerScript.resolve(get_tree()) as AudioManagerScript
	)
	if audio_manager != null:
		audio_manager.play_bgm(AudioCatalog.BGM_TITLE)
	print(BOOT_MESSAGE)


## はじめるボタン押下時の処理 (現時点ではボタン効果音の再生まで)
func _on_start_button_pressed() -> void:
	var audio_manager: AudioManagerScript = (
		AudioManagerScript.resolve(get_tree()) as AudioManagerScript
	)
	if audio_manager != null:
		audio_manager.play_sfx(AudioCatalog.SFX_BUTTON)


## 設定ボタン押下時の処理
func _on_settings_button_pressed() -> void:
	var audio_manager: AudioManagerScript = (
		AudioManagerScript.resolve(get_tree()) as AudioManagerScript
	)
	if audio_manager != null:
		audio_manager.play_sfx(AudioCatalog.SFX_BUTTON)
	if _settings_panel != null:
		_settings_panel.open()

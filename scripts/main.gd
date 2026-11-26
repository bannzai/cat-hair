extends Node3D
## ゲームのメインシーン。屋敷の 3D 空間・一人称プレイヤー・タイトル・HUD・音声設定・開発者調整画面を繋ぐ。
## 進行状態は autoload (GameState)、音声は autoload (AudioManager) に集約し、このノードは表示と入力の橋渡しを行う。

## make check がメインシーンのロードと _ready の実行を確かめる印
const BOOT_MESSAGE: String = "cat-hair boot"
## プロジェクト全体の既定フォント (日本語の字形を持つ。出典は assets/CREDITS.md)
const FONT: Font = preload("res://assets/fonts/NotoSansJP[wght].ttf")
## 状態管理 autoload スクリプト (headless 検証時のフォールバック生成に使用)
const GameStateScript := preload("res://scripts/state/game_state.gd")
## 場面名・出来事名のカタログ
const AudioCatalog := preload("res://scripts/audio/audio_catalog.gd")
## AudioManager の型解決と実行時取得用スクリプト参照 (headless --script で autoload 名を静的参照しない)
const AudioManagerScript := preload("res://scripts/audio/audio_manager.gd")
## 設定画面パネルの型解決用スクリプト参照
const AudioSettingsPanelScript := preload("res://scripts/ui/audio_settings_panel.gd")
## 題名ラベルのノードパス (本体・テストで共有する単一の正)
const TITLE_LABEL_PATH: String = "UILayer/UI/TitleOverlay/Layout/TitleLabel"
## はじめるボタンのノードパス (本体・テスト・撮影で共有する単一の正)
const START_BUTTON_PATH: String = "UILayer/UI/TitleOverlay/Layout/StartButton"
## はじめからボタンのノードパス (本体・テストで共有する単一の正)
const NEW_GAME_BUTTON_PATH: String = "UILayer/UI/TitleOverlay/Layout/NewGameButton"
## 設定ボタンのノードパス (本体・テスト・撮影で共有する単一の正)
const SETTINGS_BUTTON_PATH: String = "UILayer/UI/TitleOverlay/Layout/SettingsButton"
## 設定画面パネルのノードパス (本体・テストで共有する単一の正)
const SETTINGS_PANEL_PATH: String = "UILayer/UI/AudioSettingsPanel"

## 参照中の GameState ノード (autoload または検証時のフォールバック)
var _game_state: Node = null
## autoload 未起動時にこのシーンが自前生成した GameState (終了時に解放する)
var _owned_game_state: Node = null
## タイトルを抜けて屋敷を歩いているプレイ状態か
var _is_playing: bool = false

## 屋敷 1 階の 3D 構築ノード
@onready var mansion_world: MansionWorld = $MansionWorld
## 一人称プレイヤーノード
@onready var player: FirstPersonPlayer = $Player
## UI 全体のルート (既定フォントのテーマを適用する先)
@onready var ui_root: Control = $UILayer/UI
## 起動時に重ねるタイトル画面オーバーレイ
@onready var title_overlay: Control = $UILayer/UI/TitleOverlay
## タイトル画面の題名ラベル
@onready var title_label: Label = get_node(TITLE_LABEL_PATH) as Label
## タイトル画面の開始 / 続きからボタン
@onready var start_button: Button = get_node(START_BUTTON_PATH) as Button
## セーブデータがある時に表示するはじめからボタン
@onready var new_game_button: Button = get_node(NEW_GAME_BUTTON_PATH) as Button
## タイトル画面の音声設定ボタン
@onready var settings_button: Button = get_node(SETTINGS_BUTTON_PATH) as Button
## 音声設定パネル
@onready var settings_panel: AudioSettingsPanelScript = (
	get_node(SETTINGS_PANEL_PATH) as AudioSettingsPanelScript
)
## プレイ中に表示する HUD コンテナ
@onready var hud: Control = $UILayer/UI/HUD
## 屋敷全体の残り毛本数ラベル
@onready var remaining_hair_label: Label = $UILayer/UI/HUD/RemainingHairPanel/RemainingHairLabel
## 開発者向け調整パネル
@onready var dev_tuning_panel: DevTuningPanel = $UILayer/UI/DevTuningPanel


## 起動の入口
func _ready() -> void:
	# フォントは project.godot の gui/theme/custom_font ではなく、UI ルートの theme に設定する (子にも効く)。
	# custom_font で指定すると、初回の import でフォントの import より先に読もうとして ERROR になる
	var main_theme: Theme = Theme.new()
	main_theme.default_font = FONT
	ui_root.theme = main_theme

	start_button.pressed.connect(_on_start_pressed)
	new_game_button.pressed.connect(_on_new_game_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	dev_tuning_panel.apply_requested.connect(_on_dev_tuning_applied)
	dev_tuning_panel.close_requested.connect(close_dev_panel)

	_game_state = _resolve_game_state()
	if not _game_state.state_changed.is_connected(_refresh_hud):
		_game_state.state_changed.connect(_refresh_hud)
	if not _game_state.mansion_rebuilt.is_connected(_on_mansion_rebuilt):
		_game_state.mansion_rebuilt.connect(_on_mansion_rebuilt)

	_rebuild_world_from_state()
	_refresh_title_buttons()
	_set_title_mode()

	var audio_manager: AudioManagerScript = (
		AudioManagerScript.resolve(get_tree()) as AudioManagerScript
	)
	if audio_manager != null:
		audio_manager.play_bgm(AudioCatalog.BGM_TITLE)
	print(BOOT_MESSAGE)


## ツリー離脱時にシグナル接続と自前生成 GameState を片付ける
func _exit_tree() -> void:
	if _game_state != null and is_instance_valid(_game_state):
		if _game_state.state_changed.is_connected(_refresh_hud):
			_game_state.state_changed.disconnect(_refresh_hud)
		if _game_state.mansion_rebuilt.is_connected(_on_mansion_rebuilt):
			_game_state.mansion_rebuilt.disconnect(_on_mansion_rebuilt)
	if _owned_game_state != null and is_instance_valid(_owned_game_state):
		_owned_game_state.free()
		_owned_game_state = null


## プレイ中の F1 (開発者調整画面開閉) と F5 (手動セーブ) を処理する
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_dev_panel"):
		if _is_playing:
			toggle_dev_panel()
	elif event.is_action_pressed("save_game"):
		if _is_playing and _game_state != null:
			_game_state.save_current_state()


## タイトルを閉じて一人称プレイを開始し、屋敷 BGM へ切り替える
func enter_mansion() -> void:
	_is_playing = true
	title_overlay.visible = false
	if settings_panel != null:
		settings_panel.visible = false
	hud.visible = true
	dev_tuning_panel.visible = false
	player.controls_enabled = true
	_refresh_hud()
	var audio_manager: AudioManagerScript = (
		AudioManagerScript.resolve(get_tree()) as AudioManagerScript
	)
	if audio_manager != null:
		audio_manager.play_bgm(AudioCatalog.BGM_MANSION)


## 開発者向け調整画面の開閉を切り替える
func toggle_dev_panel() -> void:
	if dev_tuning_panel.visible:
		close_dev_panel()
	else:
		open_dev_panel()


## 開発者向け調整画面を開く
func open_dev_panel() -> void:
	if _game_state != null:
		dev_tuning_panel.load_from_tuning(_game_state.get_tuning())
	dev_tuning_panel.visible = true
	player.controls_enabled = false
	if DisplayServer.get_name() != "headless":
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


## 開発者向け調整画面を閉じる
func close_dev_panel() -> void:
	dev_tuning_panel.visible = false
	player.controls_enabled = _is_playing


## UI ルートに設定した既定テーマを返す (検証スクリプト用)
func get_ui_theme() -> Theme:
	return ui_root.theme


## 現在の GameState ノードを返す (検証スクリプト用)
func get_game_state() -> Node:
	return _game_state


## 数値を 3 桁区切りで整形する
static func format_hair_count(count: int) -> String:
	var raw_digits: String = str(maxi(0, count))
	var digit_groups: PackedStringArray = PackedStringArray()
	var cursor: int = raw_digits.length()
	while cursor > 0:
		var group_start: int = maxi(0, cursor - 3)
		digit_groups.append(raw_digits.substr(group_start, cursor - group_start))
		cursor = group_start
	digit_groups.reverse()
	return ",".join(digit_groups)


## autoload の GameState を取得し、未起動環境では自前インスタンスで補う
func _resolve_game_state() -> Node:
	var root_node: Window = get_tree().root if get_tree() != null else null
	if root_node != null:
		var autoload: Node = root_node.get_node_or_null("GameState")
		if autoload != null:
			return autoload
	_owned_game_state = GameStateScript.new()
	_owned_game_state.name = "LocalGameState"
	_owned_game_state.initialize_from_storage()
	return _owned_game_state


## 起動直後のタイトル表示状態へ切り替える
func _set_title_mode() -> void:
	_is_playing = false
	title_overlay.visible = true
	hud.visible = false
	dev_tuning_panel.visible = false
	player.controls_enabled = false


## 保存データの有無に応じてタイトルのボタン文言と「はじめから」表示を更新する
func _refresh_title_buttons() -> void:
	if _game_state != null and _game_state.loaded_from_save:
		start_button.text = "続きから"
		new_game_button.visible = true
	else:
		start_button.text = "はじめる"
		new_game_button.visible = false


## GameState の現在レイアウトと進行から 3D 屋敷とスポーン位置を再構築する
func _rebuild_world_from_state() -> void:
	if _game_state == null or _game_state.current_layout == null:
		return
	var layout: MansionLayout = _game_state.current_layout
	mansion_world.rebuild(layout, _game_state.save_data.building_progress)
	player.set_spawn(layout.spawn_position, layout.spawn_yaw)
	_refresh_hud()


## HUD の残り毛本数表示を GameState の最新値へ同期する
func _refresh_hud() -> void:
	if _game_state == null or remaining_hair_label == null:
		return
	remaining_hair_label.text = (
		"残り毛本数: %s 本" % format_hair_count(_game_state.get_total_remaining_hairs())
	)


## GameState.mansion_rebuilt シグナル受信ハンドラ
func _on_mansion_rebuilt(_layout: MansionLayout) -> void:
	_rebuild_world_from_state()


## 「はじめる」/「続きから」ボタン押下ハンドラ
func _on_start_pressed() -> void:
	AudioManagerScript.play_button_sfx(get_tree())
	enter_mansion()


## 「はじめから」ボタン押下ハンドラ
func _on_new_game_pressed() -> void:
	AudioManagerScript.play_button_sfx(get_tree())
	if _game_state != null:
		_game_state.start_new_game()
	enter_mansion()


## 「設定」ボタン押下ハンドラ
func _on_settings_pressed() -> void:
	AudioManagerScript.play_button_sfx(get_tree())
	if settings_panel != null:
		settings_panel.open()


## 開発者調整画面で「屋敷を作り直す」を押した時のハンドラ
func _on_dev_tuning_applied(new_tuning: MansionTuning) -> void:
	if _game_state != null:
		_game_state.apply_tuning_and_rebuild(new_tuning, true)
	close_dev_panel()

extends Node3D
## ゲームのメインシーン。屋敷の 3D 空間・一人称プレイヤー・タイトル・HUD・開発者調整画面を繋ぐ。
## ゲーム進行の状態自体は autoload (GameState) に集約し、このノードは表示と入力の橋渡しだけを行う。

## make check がメインシーンのロードと _ready の実行を確かめる印
const BOOT_MESSAGE: String = "cat-hair boot"
## プロジェクト全体の既定フォント (日本語の字形を持つ。出典は assets/CREDITS.md)
const FONT: Font = preload("res://assets/fonts/NotoSansJP[wght].ttf")
const GameStateScript := preload("res://scripts/state/game_state.gd")

var _game_state: Node = null
var _owned_game_state: Node = null
var _is_playing: bool = false

@onready var mansion_world: MansionWorld = $MansionWorld
@onready var player: FirstPersonPlayer = $Player
@onready var ui_root: Control = $UILayer/UI
@onready var title_overlay: Control = $UILayer/UI/TitleOverlay
@onready var title_label: Label = $UILayer/UI/TitleOverlay/Layout/TitleLabel
@onready var start_button: Button = $UILayer/UI/TitleOverlay/Layout/StartButton
@onready var new_game_button: Button = $UILayer/UI/TitleOverlay/Layout/NewGameButton
@onready var hud: Control = $UILayer/UI/HUD
@onready var remaining_hair_label: Label = $UILayer/UI/HUD/RemainingHairPanel/RemainingHairLabel
@onready var dev_tuning_panel: DevTuningPanel = $UILayer/UI/DevTuningPanel


func _ready() -> void:
	# フォントは project.godot の gui/theme/custom_font ではなく、UI ルートの theme に設定する (子にも効く)。
	# custom_font で指定すると、初回の import でフォントの import より先に読もうとして ERROR になる
	var main_theme: Theme = Theme.new()
	main_theme.default_font = FONT
	ui_root.theme = main_theme

	start_button.pressed.connect(_on_start_pressed)
	new_game_button.pressed.connect(_on_new_game_pressed)
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
	print(BOOT_MESSAGE)


func _exit_tree() -> void:
	if _game_state != null and is_instance_valid(_game_state):
		if _game_state.state_changed.is_connected(_refresh_hud):
			_game_state.state_changed.disconnect(_refresh_hud)
		if _game_state.mansion_rebuilt.is_connected(_on_mansion_rebuilt):
			_game_state.mansion_rebuilt.disconnect(_on_mansion_rebuilt)
	if _owned_game_state != null and is_instance_valid(_owned_game_state):
		_owned_game_state.free()
		_owned_game_state = null


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_dev_panel"):
		if _is_playing:
			toggle_dev_panel()
	elif event.is_action_pressed("save_game"):
		if _is_playing and _game_state != null:
			_game_state.save_current_state()


## タイトルを閉じて一人称プレイを開始する
func enter_mansion() -> void:
	_is_playing = true
	title_overlay.visible = false
	hud.visible = true
	dev_tuning_panel.visible = false
	player.controls_enabled = true
	_refresh_hud()


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
	var safe: int = maxi(0, count)
	var raw: String = str(safe)
	var parts: PackedStringArray = PackedStringArray()
	var idx: int = raw.length()
	while idx > 0:
		var start: int = maxi(0, idx - 3)
		parts.append(raw.substr(start, idx - start))
		idx = start
	parts.reverse()
	return ",".join(parts)


func _resolve_game_state() -> Node:
	var root_node: Window = get_tree().root if get_tree() != null else null
	if root_node != null:
		var autoload: Node = root_node.get_node_or_null("GameState")
		if autoload != null:
			return autoload
	# --script 検証では project.godot の autoload が自動起動しないため、内部インスタンスで補う
	_owned_game_state = GameStateScript.new()
	_owned_game_state.name = "LocalGameState"
	_owned_game_state.initialize_from_storage()
	return _owned_game_state


func _set_title_mode() -> void:
	_is_playing = false
	title_overlay.visible = true
	hud.visible = false
	dev_tuning_panel.visible = false
	player.controls_enabled = false


func _refresh_title_buttons() -> void:
	if _game_state != null and _game_state.loaded_from_save:
		start_button.text = "続きから"
		new_game_button.visible = true
	else:
		start_button.text = "はじめる"
		new_game_button.visible = false


func _rebuild_world_from_state() -> void:
	if _game_state == null or _game_state.current_layout == null:
		return
	var layout: MansionLayout = _game_state.current_layout
	mansion_world.rebuild(layout, _game_state.save_data.building_progress)
	player.set_spawn(layout.spawn_position, layout.spawn_yaw)
	_refresh_hud()


func _refresh_hud() -> void:
	if _game_state == null or remaining_hair_label == null:
		return
	var total: int = _game_state.get_total_remaining_hairs()
	remaining_hair_label.text = "残り毛本数: %s 本" % format_hair_count(total)


func _on_mansion_rebuilt(_layout: MansionLayout) -> void:
	_rebuild_world_from_state()


func _on_start_pressed() -> void:
	enter_mansion()


func _on_new_game_pressed() -> void:
	if _game_state != null:
		_game_state.start_new_game()
	enter_mansion()


func _on_dev_tuning_applied(_new_tuning: MansionTuning) -> void:
	close_dev_panel()

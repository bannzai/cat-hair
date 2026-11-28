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
## 手で毛を取る時のルールの計算 (珍しい毛の名前)
const HandRulesScript := preload("res://scripts/hand/hand_rules.gd")
## 毛を抜いた時に画面中央に出す「+N 本」の表示を残す秒数。床の毛を 1 本抜く時間 (0.45 秒) より長く、
## 続けて抜いた時に次の表示で上書きされるまで読める長さにした仮の値
const PLUCK_POPUP_SECONDS: float = 1.5
## 画面中央の照準の線の長さと太さ (px)。線の交点が画面のちょうど中央 (狙いの光線の向き) に来る
const CROSSHAIR_LINE_SIZE: Vector2 = Vector2(16.0, 2.0)
## 照準の線の色
const CROSSHAIR_COLOR: Color = Color(1.0, 1.0, 1.0, 0.85)
## 手に持って使う道具の定義
const ToolCatalogScript := preload("res://scripts/tools/tool_catalog.gd")
## 道具を買う画面を開閉するキー
const TOGGLE_SHOP_KEY: Key = KEY_T
## 掃除ロボットの回る順の画面を開閉するキー (Robot の R)
const TOGGLE_ROBOT_KEY: Key = KEY_R
## 操作の案内の一覧を閉じる・開くキー (Help の H)
const TOGGLE_GUIDE_KEY: Key = KEY_H
## 操作の案内・マウスの捕捉の案内・手で引いている進み具合の表示のスクリプト
const PlayGuideHudScript := preload("res://scripts/ui/play_guide_hud.gd")
## 猫と掃除ロボットを描いて時計を進めるノードのスクリプト
const AutomationControllerScript := preload("res://scripts/automation/automation_controller.gd")
## 買取業者に毛を売れる距離 (m。買取業者の足元からの水平距離)。手の届く距離 (HandController.REACH_M の 2.6 m) より
## 少し短くし、手を伸ばせば品物を渡せる、向かい合って話している距離に見える範囲にする
const TRADER_RANGE_M: float = 2.0
## 道具を買う画面のスクリプト (道具の説明の文言を使う)
const ToolShopPanelScript := preload("res://scripts/ui/tool_shop_panel.gd")
## 毛を売る・掃除代の計算 (払う間隔の表示に使う)
const EconomyRulesScript := preload("res://scripts/economy/economy_rules.gd")
## 見た目の方向 (写実の材質・窓の光・影) を屋敷の全部の部屋に重ねるノードのスクリプト
const LookPrototypeRoomScript := preload("res://scripts/look/look_prototype_room.gd")
## 見た目の試作の画面の表示 (所持金・道具の枠・案内) のスクリプト
const LookPrototypeHudScript := preload("res://scripts/look/look_prototype_hud.gd")
## fps と 1 フレームの時間の表示を出し入れするキー (開発者調整画面の F1・手動セーブの F5 と同じ F キーの列で、
## 押し間違えても遊ぶ操作に触れないキー)
const TOGGLE_PERF_KEY: Key = KEY_F3
## fps と 1 フレームの時間の表示のスクリプト
const PerfOverlayScript := preload("res://scripts/ui/perf_overlay.gd")

## fps と 1 フレームの時間の表示 (_ready で HUD の子に作る)
var perf_overlay: PerfOverlay = null
## 見た目の方向を屋敷の全部の部屋に重ねるノード (_ready で作る)
var look_room: LookPrototypeRoom = null
## 見た目の試作の画面の表示 (_ready で HUD の子に作る)
var look_hud: LookPrototypeHud = null
## 操作の案内・マウスの捕捉の案内・手で引いている進み具合の表示 (_ready で HUD の子に作る)
var play_guide: PlayGuideHud = null

## 狙った毛を手でつまんで抜く操作
var hand: HandController = null
## 珍しい毛の図鑑の画面
var hair_book_panel: HairBookPanel = null
## 在庫にある毛のままの本数の表示
var stock_label: Label = null
## 画面中央の照準 (横と縦の線の親。画面全体に広げ、線を中央に置く)
var crosshair: Control = null
## 毛を抜いた時に出す「+N 本」の表示
var pluck_popup_label: Label = null
## 手以外の道具を選んで使う操作
var tools: ToolController = null
## 道具を買う画面
var tool_shop_panel: ToolShopPanel = null
## 選ばずに働く大型の道具 (アンドロイド・加工機・ダンプカー) の働きと見た目
var big_tools: BigToolSite = null
## 掃除ロボットの回る順の画面
var robot_route_panel: RobotRoutePanel = null
## 猫と掃除ロボットを描き、屋敷で遊んでいる間に時計を進めるノード
var automation: AutomationController = null
## 選んでいる道具の様子 (レベル・得意な表面・消耗品の残り) の表示 (画面右下の道具の枠と所持金の上)
var tool_detail_label: Label = null
## 最後に道具を使った結果 (取りこぼしの割合) の表示
var tool_message_label: Label = null
## 今いる部屋のきれいさ・機嫌・掃除代の表示の親
var room_gauge_panel: PanelContainer = null
## 今いる部屋の名前の表示
var room_name_label: Label = null
## 今いる部屋のきれいさのゲージ (0〜100)
var cleanliness_bar: ProgressBar = null
## 今いる部屋の住人の機嫌のゲージ (0〜100)
var mood_bar: ProgressBar = null
## 今いる部屋の住人が次に払う掃除代の表示
var cleaning_fee_label: Label = null
## プレイ中に遊んだ時間を進めて機嫌と掃除代を動かすか (入力統合テストはお金を検証で決めた値に保つため false にする)
var auto_advance_time: bool = true
## プレイ中に猫と掃除ロボットの時計を進めるか (入力統合テストと撮影は毛の本数を検証で決めた値に保つため false にする)。
## シーンをツリーに入れる前に設定してもよい (猫と掃除ロボットを描くノードを作る時に渡す)
var auto_advance_automation: bool = true:
	set(value):
		auto_advance_automation = value
		if automation != null:
			automation.auto_advance = value
## 参照中の GameState ノード (autoload または検証時のフォールバック)
var _game_state: Node = null
## autoload 未起動時にこのシーンが自前生成した GameState (終了時に解放する)
var _owned_game_state: Node = null
## タイトルを抜けて屋敷を歩いているプレイ状態か
var _is_playing: bool = false
## 「+N 本」の表示を消すまでの残り秒数
var _pluck_popup_remaining: float = 0.0

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
## 光・影・色の環境
@onready var world_environment: WorldEnvironment = $WorldEnvironment


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

	look_room = LookPrototypeRoomScript.new()
	look_room.name = "LookPrototypeRoom"
	add_child(look_room)
	look_room.setup(player, world_environment)
	look_hud = LookPrototypeHudScript.new()
	hud.add_child(look_hud)
	play_guide = PlayGuideHudScript.new()
	hud.add_child(play_guide)
	perf_overlay = PerfOverlayScript.new()
	hud.add_child(perf_overlay)

	_game_state = _resolve_game_state()
	_build_hand_ui()
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


## プレイ中の F1 (開発者調整画面開閉)・B (図鑑開閉)・T (道具を買う画面の開閉)・R (掃除ロボットの回る順の画面の開閉)・
## F5 (手動セーブ)・F3 (fps と 1 フレームの時間の表示の出し入れ)・H (操作の案内の開閉。画面を開いていない時だけ) を処理する。
## 画面は 1 つずつしか開かない (開いている画面と別の画面のキーは何もしない)。F3 は画面を開いていても効く (画面を開いた時の重さも読めるように)
func _unhandled_input(event: InputEvent) -> void:
	if _is_key_press(event, TOGGLE_PERF_KEY):
		if _is_playing:
			perf_overlay.toggle()
	elif event.is_action_pressed("toggle_dev_panel"):
		if _is_playing and _no_panel_open_except(dev_tuning_panel):
			toggle_dev_panel()
	elif event.is_action_pressed("toggle_hair_book"):
		if _is_playing and _no_panel_open_except(hair_book_panel):
			toggle_hair_book()
	elif _is_key_press(event, TOGGLE_SHOP_KEY):
		if _is_playing and _no_panel_open_except(tool_shop_panel):
			toggle_tool_shop()
	elif _is_key_press(event, TOGGLE_ROBOT_KEY):
		if _is_playing and _no_panel_open_except(robot_route_panel):
			toggle_robot_route()
	elif _is_key_press(event, TOGGLE_GUIDE_KEY):
		if _is_playing and _no_panel_open_except(null):
			play_guide.toggle_controls_guide()
	elif event.is_action_pressed("save_game"):
		if _is_playing and _game_state != null:
			_game_state.save_current_state()


## event が key を押した瞬間 (押しっぱなしの繰り返しを除く) か
static func _is_key_press(event: InputEvent, key: Key) -> bool:
	var key_event: InputEventKey = event as InputEventKey
	return (
		key_event != null and key_event.pressed and not key_event.echo
		and key_event.physical_keycode == key
	)


## panel 以外の画面 (開発者調整・図鑑・道具を買う・掃除ロボットの回る順) がどれも開いていないか
func _no_panel_open_except(panel: Control) -> bool:
	for other: Control in [dev_tuning_panel, hair_book_panel, tool_shop_panel, robot_route_panel]:
		if other != panel and other.visible:
			return false
	return true


## タイトルを閉じて一人称プレイを開始し、操作の案内の一覧を開いて、屋敷 BGM へ切り替える
func enter_mansion() -> void:
	_is_playing = true
	play_guide.set_controls_guide_open(true)
	title_overlay.visible = false
	if settings_panel != null:
		settings_panel.visible = false
	hud.visible = true
	dev_tuning_panel.visible = false
	hair_book_panel.visible = false
	tool_shop_panel.visible = false
	robot_route_panel.visible = false
	_sync_controls()
	look_room.set_playing(true)
	automation.playing = true
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
	_sync_controls()
	_release_mouse()


## 開発者向け調整画面を閉じる
func close_dev_panel() -> void:
	dev_tuning_panel.visible = false
	_sync_controls()


## 図鑑の開閉を切り替える
func toggle_hair_book() -> void:
	if hair_book_panel.visible:
		close_hair_book()
	else:
		open_hair_book()


## 図鑑を開く (開いている間は歩く・つまむ操作を止める)
func open_hair_book() -> void:
	if _game_state != null:
		hair_book_panel.refresh(_game_state.get_found_rare_hair_ids())
	pluck_popup_label.visible = false
	_pluck_popup_remaining = 0.0
	hair_book_panel.visible = true
	_sync_controls()
	_release_mouse()


## 図鑑を閉じる
func close_hair_book() -> void:
	hair_book_panel.visible = false
	_sync_controls()


## 道具を買う画面の開閉を切り替える
func toggle_tool_shop() -> void:
	if tool_shop_panel.visible:
		close_tool_shop()
	else:
		open_tool_shop()


## 道具を買う画面を開く (開いている間は歩く・つまむ・道具を使う操作を止める)
func open_tool_shop() -> void:
	tool_shop_panel.refresh(_game_state, is_near_trader())
	tool_shop_panel.visible = true
	_sync_controls()
	_release_mouse()


## 道具を買う画面を閉じる
func close_tool_shop() -> void:
	tool_shop_panel.visible = false
	_sync_controls()


## 掃除ロボットの回る順の画面の開閉を切り替える
func toggle_robot_route() -> void:
	if robot_route_panel.visible:
		close_robot_route()
	else:
		open_robot_route()


## 掃除ロボットの回る順の画面を開く (開いている間は歩く・つまむ・道具を使う操作を止める。猫と掃除ロボットは動き続ける)
func open_robot_route() -> void:
	robot_route_panel.refresh(_game_state)
	robot_route_panel.visible = true
	_sync_controls()
	_release_mouse()


## 掃除ロボットの回る順の画面を閉じる
func close_robot_route() -> void:
	robot_route_panel.visible = false
	_sync_controls()


## プレイヤーが買取業者に毛を売れる距離にいるか
func is_near_trader() -> bool:
	var trader: Vector3 = mansion_world.get_trader_position()
	return (
		Vector2(player.global_position.x - trader.x, player.global_position.z - trader.z).length()
		<= TRADER_RANGE_M
	)


## プレイヤーが今いる部屋を返す (どの部屋の床の上にもいなければ null)
func get_current_room() -> MansionLayout.RoomDef:
	if _game_state == null:
		return null
	return LookPrototypeRoomScript.room_at(_game_state.current_layout, player.global_position)


## 「+N 本」の表示の文言を返す (表示していない時は空。検証用)
func get_pluck_popup_text() -> String:
	return pluck_popup_label.text if pluck_popup_label.visible else ""


## プレイ中は遊んだ時間を進め (機嫌と掃除代)、今いる部屋のゲージを描き直し、「+N 本」の表示を残り時間に合わせて消す
func _process(delta: float) -> void:
	if _is_playing and _game_state != null:
		if auto_advance_time:
			_advance_play_time(delta)
		_refresh_room_gauge()
		var can_pluck: bool = hand.can_begin_pull()
		look_hud.set_pluck_guide_visible(can_pluck)
		crosshair.visible = can_pluck or (tools.enabled and not hand.enabled)
	if _pluck_popup_remaining <= 0.0:
		return
	_pluck_popup_remaining -= delta
	if _pluck_popup_remaining <= 0.0:
		pluck_popup_label.visible = false


## 自動テストプレイの bot が、遊んだ時間・アンドロイド・猫と掃除ロボットの時計を delta_seconds 秒まとめて進める
## (auto_advance_time と auto_advance_automation を false にして、毎フレームの時計の代わりに使う)
func advance_play_clock(delta_seconds: float) -> void:
	if _game_state == null:
		return
	_advance_play_time(delta_seconds)
	_game_state.automation.advance(delta_seconds)


## 遊んだ時間 (機嫌・掃除代・加工機) とアンドロイドを delta 秒進め、掃除代が入った時は知らせる
func _advance_play_time(delta: float) -> void:
	var earned: int = _game_state.advance_time(delta)
	if earned > 0:
		_show_popup("掃除代 +%d 円" % earned)
		_play_sfx(AudioCatalog.SFX_EARN_MONEY)
	big_tools.advance(delta)


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
	hair_book_panel.visible = false
	tool_shop_panel.visible = false
	robot_route_panel.visible = false
	_sync_controls()
	look_room.set_playing(false)
	automation.playing = false


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
	hand.cancel_pull()
	tools.reset_for_new_progress()
	mansion_world.rebuild(layout, _game_state.save_data.building_progress)
	big_tools.reset_for_new_progress()
	automation.rebuild()
	look_room.apply(layout, mansion_world)
	player.set_spawn(layout.spawn_position, layout.spawn_yaw)
	_refresh_hud()


## HUD の残り毛本数と在庫の表示を GameState の最新値へ同期する
func _refresh_hud() -> void:
	if _game_state == null or remaining_hair_label == null:
		return
	remaining_hair_label.text = (
		"残り毛本数: %s 本" % format_hair_count(_game_state.get_total_remaining_hairs())
	)
	if stock_label != null:
		stock_label.text = "在庫: %s 本" % format_hair_count(_game_state.get_raw_hair_stock_count())
	if look_hud != null:
		look_hud.set_money_digits(format_hair_count(_game_state.get_money()))
	if look_hud != null and tools != null:
		_refresh_tool_slots()
	if big_tools != null:
		big_tools.refresh_models()
	if tool_shop_panel != null and tool_shop_panel.visible:
		tool_shop_panel.refresh(_game_state, is_near_trader())
	if robot_route_panel != null and robot_route_panel.visible:
		robot_route_panel.refresh(_game_state)


## 画面右下の道具の枠を、キーの番号 (1〜9・0) と名前 (持っていない道具は「—」) のキーで選ぶ道具の数だけ描き直し、
## 選んでいる道具の様子を枠の上に出す
func _refresh_tool_slots() -> void:
	var slot_texts: Array[String] = []
	var selected_index: int = -1
	var selectable: Array[StringName] = ToolCatalogScript.selectable_tool_ids()
	for index: int in range(selectable.size()):
		var tool_id: StringName = selectable[index]
		var key_number: int = (index + 1) % 10
		slot_texts.append(
			"%d %s" % [key_number, ToolCatalogScript.find_tool(tool_id)["name"]]
			if tools.owns_tool(tool_id)
			else "%d —" % key_number
		)
		if tool_id == tools.get_selected_tool_id():
			selected_index = index
	look_hud.set_tools(slot_texts, selected_index)
	tool_detail_label.text = (
		ToolShopPanelScript.describe_tool(
			tools.get_selected_tool_id(), _game_state.find_owned_tool(tools.get_selected_tool_id())
		)
		+ "   (%s / %s)" % [PlayGuideHudScript.SHOP_KEY_TEXT, PlayGuideHudScript.ROBOT_KEY_TEXT]
	)


## 今いる部屋の名前・きれいさ・機嫌のゲージと次の掃除代を描き直す (部屋の外では隠す)
func _refresh_room_gauge() -> void:
	if room_gauge_panel == null:
		return
	var room: MansionLayout.RoomDef = get_current_room()
	room_gauge_panel.visible = room != null
	if room == null:
		return
	var status: Dictionary = _game_state.get_room_status(room.room_id)
	room_name_label.text = "%s の住人" % room.display_name
	cleanliness_bar.value = 100.0 * float(status["cleanliness"])
	mood_bar.value = 100.0 * float(status["mood"])
	cleaning_fee_label.text = "掃除代: %d 円 / %d 秒ごと" % [
		int(status["cleaning_fee"]),
		int(EconomyRulesScript.PAYMENT_INTERVAL_SECONDS),
	]


## プレイ中で、開発者画面・図鑑・道具を買う画面・掃除ロボットの回る順の画面のどれも開いていない時だけ、歩く操作・つまむ操作・道具を使う操作を受け付ける。
## つまむ操作は手を選んでいる時だけ、道具を使う操作は手以外を選んでいる時だけ受け付ける。
## 画面を開いている間は操作の案内の一覧を隠す
func _sync_controls() -> void:
	var active: bool = _is_playing and _no_panel_open_except(null)
	play_guide.set_suppressed(not _no_panel_open_except(null))
	player.controls_enabled = active
	hand.enabled = active and tools.get_selected_tool_id() == ToolCatalogScript.TOOL_HAND
	tools.enabled = active


## 画面の操作のためにマウスの捕捉を解く (headless ではマウスモードを変えない)
func _release_mouse() -> void:
	if DisplayServer.get_name() != "headless":
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


## 手・照準・在庫・「+N 本」・図鑑の部品を作り、手を一人称カメラに付ける
func _build_hand_ui() -> void:
	hand = HandController.new()
	hand.name = "Hand"
	add_child(hand)
	hand.setup(player.get_camera(), mansion_world, _game_state, player)
	hand.hairs_plucked.connect(_on_hairs_plucked)
	hand.pull_progress_changed.connect(_on_pull_progress_changed)
	hand.pull_failed.connect(_on_pull_failed)

	crosshair = Control.new()
	crosshair.name = "Crosshair"
	crosshair.visible = false
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(crosshair)
	var vertical_size: Vector2 = Vector2(CROSSHAIR_LINE_SIZE.y, CROSSHAIR_LINE_SIZE.x)
	for line_size: Vector2 in [CROSSHAIR_LINE_SIZE, vertical_size]:
		var line: ColorRect = ColorRect.new()
		line.color = CROSSHAIR_COLOR
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.anchor_left = 0.5
		line.anchor_right = 0.5
		line.anchor_top = 0.5
		line.anchor_bottom = 0.5
		line.offset_left = -line_size.x * 0.5
		line.offset_right = line_size.x * 0.5
		line.offset_top = -line_size.y * 0.5
		line.offset_bottom = line_size.y * 0.5
		crosshair.add_child(line)

	pluck_popup_label = Label.new()
	pluck_popup_label.name = "PluckPopup"
	pluck_popup_label.visible = false
	pluck_popup_label.add_theme_font_size_override("font_size", 40)
	pluck_popup_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55))
	pluck_popup_label.add_theme_color_override("font_outline_color", Color(0.1, 0.08, 0.05))
	pluck_popup_label.add_theme_constant_override("outline_size", 8)
	pluck_popup_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pluck_popup_label.anchor_left = 0.5
	pluck_popup_label.anchor_right = 0.5
	pluck_popup_label.anchor_top = 0.5
	pluck_popup_label.anchor_bottom = 0.5
	pluck_popup_label.offset_left = -300.0
	pluck_popup_label.offset_right = 300.0
	pluck_popup_label.offset_top = -130.0
	pluck_popup_label.offset_bottom = -30.0
	pluck_popup_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(pluck_popup_label)

	var stock_panel: PanelContainer = remaining_hair_label.get_parent().duplicate() as PanelContainer
	stock_panel.name = "StockPanel"
	stock_panel.offset_top += 58.0
	stock_panel.offset_bottom += 58.0
	hud.add_child(stock_panel)
	stock_label = stock_panel.get_child(0) as Label
	stock_label.name = "StockLabel"

	hair_book_panel = HairBookPanel.new()
	hair_book_panel.name = "HairBookPanel"
	hair_book_panel.visible = false
	hair_book_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	hair_book_panel.offset_left = -240.0
	hair_book_panel.offset_right = 240.0
	hair_book_panel.offset_top = -170.0
	hair_book_panel.offset_bottom = 170.0
	ui_root.add_child(hair_book_panel)
	hair_book_panel.close_requested.connect(close_hair_book)
	_build_tool_ui()


## 道具の操作・選んでいる道具の様子・道具の結果・部屋のゲージ・道具を買う画面を作る
## (所持金と道具の枠は LookPrototypeHud が出す)
func _build_tool_ui() -> void:
	tools = ToolController.new()
	tools.name = "Tools"
	add_child(tools)
	tools.setup(_game_state, mansion_world, hand, player.get_camera())
	tools.tool_used.connect(_on_tool_used)
	tools.tool_selected.connect(_on_tool_selected)
	big_tools = BigToolSite.new()
	big_tools.name = "BigTools"
	add_child(big_tools)
	big_tools.setup(_game_state, mansion_world, hand)

	tool_message_label = Label.new()
	tool_message_label.name = "ToolMessage"
	tool_message_label.add_theme_font_size_override("font_size", 20)
	tool_message_label.add_theme_color_override("font_outline_color", Color(0.1, 0.08, 0.05))
	tool_message_label.add_theme_constant_override("outline_size", 6)
	tool_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tool_message_label.anchor_left = 0.5
	tool_message_label.anchor_right = 0.5
	tool_message_label.anchor_top = 0.5
	tool_message_label.anchor_bottom = 0.5
	tool_message_label.offset_left = -400.0
	tool_message_label.offset_right = 400.0
	tool_message_label.offset_top = 30.0
	tool_message_label.offset_bottom = 70.0
	tool_message_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(tool_message_label)

	# 選んでいる道具の様子は、画面右下の道具の枠と所持金 (LookPrototypeHud) のさらに上に 1 行で出す
	tool_detail_label = Label.new()
	tool_detail_label.name = "ToolDetail"
	tool_detail_label.add_theme_font_size_override("font_size", 15)
	tool_detail_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.75))
	tool_detail_label.add_theme_constant_override("shadow_offset_x", 1)
	tool_detail_label.add_theme_constant_override("shadow_offset_y", 2)
	tool_detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tool_detail_label.anchor_left = 1.0
	tool_detail_label.anchor_right = 1.0
	tool_detail_label.anchor_top = 1.0
	tool_detail_label.anchor_bottom = 1.0
	tool_detail_label.offset_left = -918.0
	tool_detail_label.offset_right = -18.0
	tool_detail_label.offset_top = -130.0
	tool_detail_label.offset_bottom = -104.0
	tool_detail_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(tool_detail_label)

	room_gauge_panel = PanelContainer.new()
	room_gauge_panel.name = "RoomGauge"
	room_gauge_panel.offset_left = 18.0
	room_gauge_panel.offset_right = 290.0
	room_gauge_panel.offset_top = 18.0
	room_gauge_panel.offset_bottom = 170.0
	room_gauge_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(room_gauge_panel)
	var gauge_layout: VBoxContainer = VBoxContainer.new()
	room_gauge_panel.add_child(gauge_layout)
	room_name_label = Label.new()
	room_name_label.name = "RoomName"
	gauge_layout.add_child(room_name_label)
	cleanliness_bar = _add_gauge(gauge_layout, "きれいさ", "CleanlinessBar")
	mood_bar = _add_gauge(gauge_layout, "機嫌", "MoodBar")
	cleaning_fee_label = Label.new()
	cleaning_fee_label.name = "CleaningFee"
	cleaning_fee_label.add_theme_font_size_override("font_size", 14)
	gauge_layout.add_child(cleaning_fee_label)

	tool_shop_panel = ToolShopPanel.new()
	tool_shop_panel.name = "ToolShopPanel"
	tool_shop_panel.visible = false
	tool_shop_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	tool_shop_panel.offset_left = -470.0
	tool_shop_panel.offset_right = 470.0
	tool_shop_panel.offset_top = -330.0
	tool_shop_panel.offset_bottom = 330.0
	ui_root.add_child(tool_shop_panel)
	tool_shop_panel.purchase_requested.connect(_on_purchase_requested)
	tool_shop_panel.sell_requested.connect(_on_sell_requested)
	tool_shop_panel.haul_requested.connect(_on_haul_requested)
	tool_shop_panel.close_requested.connect(close_tool_shop)

	automation = AutomationControllerScript.new()
	automation.name = "Automation"
	automation.auto_advance = auto_advance_automation
	add_child(automation)
	automation.setup(_game_state, mansion_world)
	tools.set_automation(automation)

	robot_route_panel = RobotRoutePanel.new()
	robot_route_panel.name = "RobotRoutePanel"
	robot_route_panel.visible = false
	robot_route_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	# 幅は道具を買う画面と同じ 940 px (台の行の回る順の表示を 1 行に収める)。高さは台 4 台と部屋のボタン 1 段が収まる 560 px
	robot_route_panel.offset_left = -470.0
	robot_route_panel.offset_right = 470.0
	robot_route_panel.offset_top = -280.0
	robot_route_panel.offset_bottom = 280.0
	ui_root.add_child(robot_route_panel)
	robot_route_panel.buy_requested.connect(_on_robot_buy_requested)
	robot_route_panel.route_change_requested.connect(_on_robot_route_change_requested)
	robot_route_panel.close_requested.connect(close_robot_route)


## 見出しと 0〜100 のゲージの行を足し、ゲージを返す
func _add_gauge(parent: VBoxContainer, caption: String, bar_name: String) -> ProgressBar:
	var caption_label: Label = Label.new()
	caption_label.text = caption
	caption_label.add_theme_font_size_override("font_size", 14)
	parent.add_child(caption_label)
	var bar: ProgressBar = ProgressBar.new()
	bar.name = bar_name
	bar.min_value = 0.0
	bar.max_value = 100.0
	# 既定の刻み 1 だと 1% 未満の変化が丸められ、きれいさ・機嫌の値とゲージがずれるため刻みを無くす
	bar.step = 0.0
	bar.custom_minimum_size = Vector2(240.0, 16.0)
	parent.add_child(bar)
	return bar


## 毛が抜けた時に「+N 本」と、珍しい毛ならその名前を画面中央に出す
func _on_hairs_plucked(
	count: int, rare_ids: Array[StringName], new_rare_ids: Array[StringName]
) -> void:
	var lines: PackedStringArray = PackedStringArray(["+%d 本" % count])
	for rare_id: StringName in rare_ids:
		var rare_line: String = "珍しい毛: %s" % HandRulesScript.rare_hair_name(rare_id)
		if new_rare_ids.has(rare_id):
			rare_line += " (図鑑に載った)"
		lines.append(rare_line)
	_show_popup("\n".join(lines))


## 手で引いている進み具合が変わった時に、照準の下のゲージを合わせる。引き始めたら前の抜けなかった理由を消す
func _on_pull_progress_changed(progress: float, pulling: bool) -> void:
	play_guide.show_pull_progress(progress, pulling)
	if pulling:
		tool_message_label.text = ""


## 手で毛を抜けなかった時に、理由を照準の下 (道具の結果と同じ所) に出す
func _on_pull_failed(reason: StringName) -> void:
	tool_message_label.text = HandController.failure_message(reason)


## 画面中央に短い知らせ (「+N 本」・入ったお金) を PLUCK_POPUP_SECONDS 秒出す
func _show_popup(text: String) -> void:
	pluck_popup_label.text = text
	pluck_popup_label.visible = true
	_pluck_popup_remaining = PLUCK_POPUP_SECONDS


## 効果音を出来事名で鳴らす (AudioManager が無い検証では何もしない)
func _play_sfx(event_name: String) -> void:
	var audio_manager: AudioManagerScript = (
		AudioManagerScript.resolve(get_tree()) as AudioManagerScript
	)
	if audio_manager != null:
		audio_manager.play_sfx(event_name)


## 道具を使った時に、結果 (取りこぼしの割合) を照準の下に出す
func _on_tool_used(result: Dictionary) -> void:
	tool_message_label.text = str(result["message"])


## 選んでいる道具が変わった時に、手と道具の操作の切り替えと道具の並びの表示を更新する
func _on_tool_selected(_tool_id: StringName) -> void:
	tool_message_label.text = tools.get_last_message()
	_sync_controls()
	_refresh_hud()


## 道具を買う画面で買う操作をした時 (kind は GameState.PURCHASE_*)。買えた時は効果音 buy_tool を鳴らす
func _on_purchase_requested(kind: StringName, item_id: StringName) -> void:
	if _game_state.purchase(kind, item_id):
		_play_sfx(AudioCatalog.SFX_BUY_TOOL)
	tool_shop_panel.refresh(_game_state, is_near_trader())
	_refresh_hud()


## 掃除ロボットの回る順の画面で買う操作をした時。今いる部屋 (部屋の外なら屋敷の最初の部屋) を最初に回る部屋にして置く
func _on_robot_buy_requested() -> void:
	var room: MansionLayout.RoomDef = get_current_room()
	if room == null and not _game_state.current_layout.rooms.is_empty():
		room = _game_state.current_layout.rooms[0]
	if room != null and _game_state.automation.buy_robot(room.room_id):
		_play_sfx(AudioCatalog.SFX_BUY_TOOL)
	robot_route_panel.refresh(_game_state)


## 掃除ロボットの回る順の画面で回る順を変えた時
func _on_robot_route_change_requested(robot_index: int, room_ids: Array[StringName]) -> void:
	_game_state.automation.set_robot_route(robot_index, room_ids)
	robot_route_panel.refresh(_game_state)


## 道具を買う画面で毛を売った時 (買取業者の近くにいる時だけ売る)
func _on_sell_requested() -> void:
	if not is_near_trader():
		return
	var earned: int = _game_state.sell_hair_stocks()
	if earned > 0:
		_play_sfx(AudioCatalog.SFX_EARN_MONEY)
		_show_popup("+%d 円" % earned)
	tool_shop_panel.refresh(_game_state, is_near_trader())


## 道具を買う画面でダンプカーを呼んだ時 (どこからでも、積める量まで運び出して売る)
func _on_haul_requested() -> void:
	var hauled: Dictionary = _game_state.haul_with_dump_truck()
	if int(hauled["earned"]) > 0:
		_play_sfx(AudioCatalog.SFX_EARN_MONEY)
		_show_popup(
			"ダンプカーで %d 本分を運んだ +%d 円" % [int(hauled["hauled_hairs"]), int(hauled["earned"])]
		)
	tool_shop_panel.refresh(_game_state, is_near_trader())


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

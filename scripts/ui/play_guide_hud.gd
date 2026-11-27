class_name PlayGuideHud
extends Control
## プレイ中の画面に重ねる操作の案内。画面の左下 (今やることの案内の上) に、操作の一覧の枠と、マウスの捕捉の
## 案内 (取られている間は放すキー) の 1 行を出し、画面中央の照準の下に、手で引いている進み具合のゲージを出す。
## 操作の一覧は main が遊び始めに開き、H キーで閉じる・開く。画面 (道具を買う画面など) を開いている間は隠す。

## 道具を買う画面を開くキーの案内 (main.gd の TOGGLE_SHOP_KEY のキー。右下の道具の様子の行と操作の一覧で使う)
const SHOP_KEY_TEXT: String = "T: 道具を買う"
## 掃除ロボットの画面を開くキーの案内 (main.gd の TOGGLE_ROBOT_KEY のキー。右下の道具の様子の行と操作の一覧で使う)
const ROBOT_KEY_TEXT: String = "R: 掃除ロボット"
## 操作の一覧を閉じる・開くキーの案内 (main.gd の TOGGLE_GUIDE_KEY のキー)
const GUIDE_KEY_TEXT: String = "H: 操作の案内"
## マウスを放すキーの案内 (project.godot の入力アクション release_mouse のキー)
const RELEASE_MOUSE_TEXT: String = "Esc: マウスを放す"
## 操作の一覧の行 (キーは project.godot の入力アクションと main.gd・ToolController のキーの定数のとおり)
const CONTROLS_LINES: Array[String] = [
	"操作の案内 (H で閉じる・開く)",
	"W A S D / 矢印キー: 歩く",
	"マウス: 視点を動かす",
	"左クリック / E を押したまま: 手で毛を抜く",
	"  (抜けるまで押したまま。途中で離すと戻る)",
	"1〜9・0: 道具を持ち替える",
	"左クリック / E: 手以外の道具を使う",
	SHOP_KEY_TEXT,
	ROBOT_KEY_TEXT,
	"B: 図鑑 / F5: セーブ",
	RELEASE_MOUSE_TEXT + " (クリックで戻す)",
]
## マウスの案内の行の下端の、画面の下端からの高さ (px)。今やることの案内 (LookPrototypeHud の GuideLabel) の上端
## (余白・道具の枠・間隔・1 行の高さの和) に合わせ、その上に置く
const MOUSE_HINT_BOTTOM_PX: float = (
	LookPrototypeHud.SCREEN_MARGIN_PX + LookPrototypeHud.TOOL_SLOT_SIZE_PX.y
	+ LookPrototypeHud.ROW_GAP_PX + LookPrototypeHud.LABEL_LINE_HEIGHT_PX
)
## マウスの案内の行の高さ (px)。16 px の文字 1 行に上下の余白を足した高さ
const MOUSE_HINT_HEIGHT_PX: float = 26.0
## マウスの案内の行と操作の一覧の枠の幅 (px)。1280 px の幅で、右下の道具の様子の行 (main.gd の ToolDetail。
## 右端から 918 px までの右寄せ) の箱の左端 (画面の左から 362 px) に届かない幅
const LEFT_COLUMN_WIDTH_PX: float = 340.0
## 操作の一覧の枠の高さ (px)。15 px の文字 11 行と上下の余白が収まる高さ (収まらない時は上へ伸びる)
const CONTROLS_PANEL_HEIGHT_PX: float = 270.0
## 操作の一覧の枠の内側の余白 (px)
const PANEL_PADDING_PX: float = 8.0
## 引いている進み具合のゲージの大きさ (px)。照準 (16 px) より広く、照準の下の道具の結果の文字 (中央から 30 px 下) に
## 重ならない高さ
const PULL_BAR_SIZE_PX: Vector2 = Vector2(120.0, 8.0)
## 引いている進み具合のゲージの上端の、画面中央からの距離 (px)。照準の線 (中央から 8 px) の下に離して置く
const PULL_BAR_OFFSET_Y_PX: float = 16.0
## 操作の一覧の枠の背景の色。LookPrototypeHud の道具の枠と同じく、3D の絵を透かして文字を読める濃さ
const PANEL_BACKGROUND_COLOR: Color = Color(0.0, 0.0, 0.0, 0.45)

## 操作の一覧の枠
var _controls_panel: PanelContainer = null
## 操作の一覧の文字
var _controls_label: Label = null
## マウスの捕捉の案内の行
var _mouse_hint_label: Label = null
## 手で引いている進み具合のゲージ
var _pull_bar: ProgressBar = null
## 操作の一覧を開いているか (画面を開いている間は開いたまま隠す)
var _controls_open: bool = false
## 画面 (道具を買う画面など) を開いていて操作の一覧を隠すか
var _suppressed: bool = false


## インスタンス生成時に操作の一覧・マウスの案内・進み具合のゲージを組み立てる (親の大きさいっぱいに広がる)
func _init() -> void:
	name = "PlayGuideHud"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_mouse_hint_label = LookPrototypeHud.make_label("MouseHint", 16, HORIZONTAL_ALIGNMENT_LEFT)
	_anchor_bottom_left(_mouse_hint_label, MOUSE_HINT_BOTTOM_PX, MOUSE_HINT_HEIGHT_PX)
	add_child(_mouse_hint_label)
	refresh_mouse_hint(false)

	_controls_panel = PanelContainer.new()
	_controls_panel.name = "ControlsGuide"
	_controls_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = PANEL_BACKGROUND_COLOR
	style.set_content_margin_all(PANEL_PADDING_PX)
	_controls_panel.add_theme_stylebox_override("panel", style)
	# 文字が枠に収まらない時に、下の今やることの案内に重ならないよう上へ伸ばす
	_controls_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_anchor_bottom_left(
		_controls_panel,
		MOUSE_HINT_BOTTOM_PX + MOUSE_HINT_HEIGHT_PX + LookPrototypeHud.ROW_GAP_PX,
		CONTROLS_PANEL_HEIGHT_PX,
	)
	add_child(_controls_panel)
	_controls_label = LookPrototypeHud.make_label("ControlsText", 15, HORIZONTAL_ALIGNMENT_LEFT)
	_controls_label.text = "\n".join(CONTROLS_LINES)
	_controls_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_controls_panel.add_child(_controls_label)
	_controls_panel.visible = false

	_pull_bar = ProgressBar.new()
	_pull_bar.name = "PullProgress"
	_pull_bar.min_value = 0.0
	_pull_bar.max_value = 1.0
	_pull_bar.step = 0.0
	_pull_bar.show_percentage = false
	_pull_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pull_bar.anchor_left = 0.5
	_pull_bar.anchor_right = 0.5
	_pull_bar.anchor_top = 0.5
	_pull_bar.anchor_bottom = 0.5
	_pull_bar.offset_left = -PULL_BAR_SIZE_PX.x * 0.5
	_pull_bar.offset_right = PULL_BAR_SIZE_PX.x * 0.5
	_pull_bar.offset_top = PULL_BAR_OFFSET_Y_PX
	_pull_bar.offset_bottom = PULL_BAR_OFFSET_Y_PX + PULL_BAR_SIZE_PX.y
	_pull_bar.visible = false
	add_child(_pull_bar)


## 毎フレーム、マウスの捕捉の案内を今のマウスの状態に合わせる (捕捉は FirstPersonPlayer と main が切り替える)
func _process(_delta: float) -> void:
	refresh_mouse_hint(Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED)


## マウスの捕捉の案内の文言を返す。取られている間は放すキー、取られていない間は取り方
static func mouse_hint_text(captured: bool) -> String:
	if captured:
		return "%s / %s" % [RELEASE_MOUSE_TEXT, GUIDE_KEY_TEXT]
	return "クリック: マウスを取る / %s" % GUIDE_KEY_TEXT


## マウスの捕捉の案内を captured (マウスがゲームに取られているか) に合わせる
func refresh_mouse_hint(captured: bool) -> void:
	_mouse_hint_label.text = mouse_hint_text(captured)


## マウスの捕捉の案内の文字列
func get_mouse_hint_text() -> String:
	return _mouse_hint_label.text


## 操作の一覧を開く・閉じる
func set_controls_guide_open(open: bool) -> void:
	_controls_open = open
	_controls_panel.visible = _controls_open and not _suppressed


## 操作の一覧の開閉を切り替える
func toggle_controls_guide() -> void:
	set_controls_guide_open(not _controls_open)


## 操作の一覧を開いているか (画面を開いていて隠している間も開いている扱い)
func is_controls_guide_open() -> bool:
	return _controls_open


## 画面 (道具を買う画面など) を開いている間は suppressed を true にして操作の一覧を隠す
func set_suppressed(suppressed: bool) -> void:
	_suppressed = suppressed
	set_controls_guide_open(_controls_open)


## 操作の一覧が画面に出ているか
func is_controls_guide_visible() -> bool:
	return _controls_panel.visible


## 操作の一覧の文字列
func get_controls_guide_text() -> String:
	return _controls_label.text


## 手で引いている進み具合のゲージを progress (0〜1) にする。pulling が false の時は隠す
func show_pull_progress(progress: float, pulling: bool) -> void:
	_pull_bar.value = clampf(progress, 0.0, 1.0)
	_pull_bar.visible = pulling


## 進み具合のゲージが画面に出ているか
func is_pull_progress_visible() -> bool:
	return _pull_bar.visible


## 進み具合のゲージの値 (0〜1)
func get_pull_progress_value() -> float:
	return _pull_bar.value


## control を画面の左下に、幅 LEFT_COLUMN_WIDTH_PX・高さ height_px で、下端を画面の下端から bottom_px 上げて置く
static func _anchor_bottom_left(control: Control, bottom_px: float, height_px: float) -> void:
	control.anchor_left = 0.0
	control.anchor_right = 0.0
	control.anchor_top = 1.0
	control.anchor_bottom = 1.0
	control.offset_left = LookPrototypeHud.SCREEN_MARGIN_PX
	control.offset_right = LookPrototypeHud.SCREEN_MARGIN_PX + LEFT_COLUMN_WIDTH_PX
	control.offset_bottom = -bottom_px
	control.offset_top = -bottom_px - height_px

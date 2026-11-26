class_name LookPrototypeHud
extends Control
## 見た目の試作 (issue #19) の画面の表示のうち、所持金・手持ちの道具の枠・今やることの短い案内。
## 屋敷全体の毛の残り本数は main.tscn の RemainingHairPanel (右上) がそのまま出す。
## 3D の絵を隠さないよう、文字は影付きの文字だけで出し、枠は細い線の四角にして画面の下の端に寄せる。
## 所持金と道具はまだ実装されていない (必要な機能「お金と手持ちの道具」) ため、見本の値を出す。

## 見本の所持金 (円)。手で取る段階の序盤に、毛を数百本売った後の額の見当
const SAMPLE_MONEY_YEN: int = 1280
## 見本の手持ちの道具の名前 (documents/DIRECTION.md「用語」と PROJECT.md「道具」の名前。安い順)
const SAMPLE_TOOL_NAMES: Array[String] = ["手", "ピンセット", "ガムテープ", "粘着ローラー"]
## 見本で手に持っている道具の位置 (SAMPLE_TOOL_NAMES の番号)。手で取る段階の始まりは手だけを使うため 0
const SAMPLE_SELECTED_TOOL_INDEX: int = 0
## 見本の今やることの短い案内
const SAMPLE_GUIDE_TEXT: String = "玄関ホールの床の毛を、手で 1 本ずつ抜く"
## 画面の端からの余白 (px)。1280x720 で既存の残り本数の枠 (右上 18 px) と揃える値
const SCREEN_MARGIN_PX: float = 18.0
## 道具の枠 1 つの大きさ (px)。最も長い道具の名前 (粘着ローラー、16 px で 6 文字) が 1 行で収まる大きさ
const TOOL_SLOT_SIZE_PX: Vector2 = Vector2(112.0, 44.0)
## 道具の枠どうしの間隔 (px)
const TOOL_SLOT_GAP_PX: int = 6
## 文字の色。写実寄りの部屋の上で白く浮きすぎない、わずかに暖かい白
const TEXT_COLOR: Color = Color(0.94, 0.92, 0.88)
## 文字の影の色。明るい床の上でも文字が読める濃さ
const TEXT_SHADOW_COLOR: Color = Color(0.0, 0.0, 0.0, 0.75)
## 道具の枠の線の色 (手に持っていない道具)。3D の絵を透かして見せる淡い白
const SLOT_BORDER_COLOR: Color = Color(1.0, 1.0, 1.0, 0.35)
## 手に持っている道具の枠の線の色。持っていない枠と明るさの差で見分ける白
const SELECTED_SLOT_BORDER_COLOR: Color = Color(1.0, 1.0, 1.0, 0.9)
## 道具の枠の中の背景の色。枠の中の文字を読めるよう、床を薄く暗くする濃さ
const SLOT_BACKGROUND_COLOR: Color = Color(0.0, 0.0, 0.0, 0.28)

## 所持金のラベル
var _money_label: Label = null
## 今やることの案内のラベル
var _guide_label: Label = null
## 道具の枠の並び
var _tool_row: HBoxContainer = null


## インスタンス生成時に所持金・道具の枠・案内のノードを組み立てる (親の大きさいっぱいに広がる)
func _init() -> void:
	name = "LookPrototypeHud"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_tool_row = HBoxContainer.new()
	_tool_row.name = "ToolSlots"
	_tool_row.add_theme_constant_override("separation", TOOL_SLOT_GAP_PX)
	_tool_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for tool_index: int in range(SAMPLE_TOOL_NAMES.size()):
		_tool_row.add_child(_make_tool_slot(tool_index))
	_anchor_bottom_right(
		_tool_row,
		Vector2(
			TOOL_SLOT_SIZE_PX.x * SAMPLE_TOOL_NAMES.size()
			+ TOOL_SLOT_GAP_PX * (SAMPLE_TOOL_NAMES.size() - 1),
			TOOL_SLOT_SIZE_PX.y,
		),
		0.0,
	)
	add_child(_tool_row)

	# 文字の大きさ: 所持金 20 px・案内 18 px・道具の名前 16 px。既存の残り本数の文字より小さくし、
	# 1280x720 で読める下限の 16 px から、目に入る順 (所持金 > 案内 > 道具) に 2 px ずつ大きくした
	_money_label = _make_label("MoneyLabel", 20, HORIZONTAL_ALIGNMENT_RIGHT)
	# 道具の枠の上に 8 px 空けて置く (所持金は道具を買うためのお金なので道具の並びの上に添える)。
	# 大きさは 20 px の文字で「所持金 999,999,999 円」が 1 行に収まる幅と、1 行の高さ
	_anchor_bottom_right(_money_label, Vector2(320.0, 30.0), TOOL_SLOT_SIZE_PX.y + 8.0)
	add_child(_money_label)

	_guide_label = _make_label("GuideLabel", 18, HORIZONTAL_ALIGNMENT_LEFT)
	_guide_label.text = SAMPLE_GUIDE_TEXT
	# 大きさは 18 px の文字で 30 文字の案内が 1 行に収まる幅 (道具の枠の左端に届かない幅) と、1 行の高さ
	_guide_label.anchor_top = 1.0
	_guide_label.anchor_bottom = 1.0
	_guide_label.offset_left = SCREEN_MARGIN_PX
	_guide_label.offset_right = SCREEN_MARGIN_PX + 560.0
	_guide_label.offset_top = -SCREEN_MARGIN_PX - 30.0
	_guide_label.offset_bottom = -SCREEN_MARGIN_PX
	add_child(_guide_label)


## 所持金の表示を 3 桁区切りの数字の文字列 (main.gd の format_hair_count で整形した物) で更新する
func set_money_digits(digits: String) -> void:
	_money_label.text = "所持金 %s 円" % digits


## 所持金のラベルの文字列
func get_money_text() -> String:
	return _money_label.text


## 今やることの案内の文字列
func get_guide_text() -> String:
	return _guide_label.text


## 道具の枠の数
func get_tool_slot_count() -> int:
	return _tool_row.get_child_count()


## 道具の枠 1 つ (細い線の四角と、中央の道具の名前) を作る
func _make_tool_slot(tool_index: int) -> PanelContainer:
	var selected: bool = tool_index == SAMPLE_SELECTED_TOOL_INDEX
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = SLOT_BACKGROUND_COLOR
	style.border_color = SELECTED_SLOT_BORDER_COLOR if selected else SLOT_BORDER_COLOR
	# 手に持っている枠だけ線を 2 px にして、色の差だけに頼らず見分けられるようにする
	style.set_border_width_all(2 if selected else 1)
	var slot: PanelContainer = PanelContainer.new()
	slot.name = "ToolSlot%d" % tool_index
	slot.custom_minimum_size = TOOL_SLOT_SIZE_PX
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_theme_stylebox_override("panel", style)
	var label: Label = _make_label("ToolName", 16, HORIZONTAL_ALIGNMENT_CENTER)
	label.text = SAMPLE_TOOL_NAMES[tool_index]
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	slot.add_child(label)
	return slot


## 影付きの文字のラベルを作る
static func _make_label(
	node_name: String, font_size: int, alignment: HorizontalAlignment
) -> Label:
	var label: Label = Label.new()
	label.name = node_name
	label.horizontal_alignment = alignment
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	label.add_theme_color_override("font_shadow_color", TEXT_SHADOW_COLOR)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 2)
	return label


## control を画面の右下の角に、size の大きさで、下の余白から lift_px 上げて置く
static func _anchor_bottom_right(control: Control, size_px: Vector2, lift_px: float) -> void:
	control.anchor_left = 1.0
	control.anchor_right = 1.0
	control.anchor_top = 1.0
	control.anchor_bottom = 1.0
	control.offset_right = -SCREEN_MARGIN_PX
	control.offset_left = -SCREEN_MARGIN_PX - size_px.x
	control.offset_bottom = -SCREEN_MARGIN_PX - lift_px
	control.offset_top = -SCREEN_MARGIN_PX - lift_px - size_px.y

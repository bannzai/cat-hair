class_name LookPrototypeHud
extends Control
## 見た目の試作 (issue #19) の画面の表示のうち、所持金・手持ちの道具の枠・今やることの短い案内。
## 屋敷全体の毛の残り本数は main.tscn の RemainingHairPanel (右上) がそのまま出す。
## 3D の絵を隠さないよう、文字は影付きの文字だけで出し、枠は細い線の四角にして画面の下の端に寄せる。
## 所持金と道具の枠は、main が GameState の本物の値 (set_money_digits・set_tools) を渡す。
## 渡すまでの道具の枠と、今やることの案内 (まだ実装していない) は見本の値を出す。

## 見本の手持ちの道具の名前 (documents/DIRECTION.md「用語」と PROJECT.md「道具」の名前。安い順)
const SAMPLE_TOOL_NAMES: Array[String] = ["手", "ピンセット", "ガムテープ", "粘着ローラー"]
## 見本で手に持っている道具の位置 (SAMPLE_TOOL_NAMES の番号)。手で取る段階の始まりは手だけを使うため 0
const SAMPLE_SELECTED_TOOL_INDEX: int = 0
## 見本の今やることの短い案内
const SAMPLE_GUIDE_TEXT: String = "玄関ホールの床の毛を、手で 1 本ずつ抜く"
## 画面の端からの余白 (px)。1280x720 で既存の残り本数の枠 (右上 18 px) と揃える値
const SCREEN_MARGIN_PX: float = 18.0
## 道具の枠 1 つの大きさ (px)。幅は 16 px の字で 7 文字が 1 行に収まり、8 つの枠と間隔 (938 px) が 1280 px の画面に
## 収まる幅。高さは 13 px の字で 2 行 (TOOL_SLOT_ONE_LINE_CHARS を超える名前の折り返し) が収まる高さ
const TOOL_SLOT_SIZE_PX: Vector2 = Vector2(112.0, 44.0)
## 道具の枠の行と、その上の所持金・案内の行との間隔 (px)。枠の線と文字の影が重ならない最小の間隔
const ROW_GAP_PX: float = 8.0
## ラベル 1 行の高さ (px)。20 px の文字の行の高さに上下の余白を足し、所持金と案内の両方で使う
const LABEL_LINE_HEIGHT_PX: float = 30.0
## 道具の枠に 16 px の字で 1 行に収まる文字数 (枠の幅 112 px から左右の余白を引いた幅)
const TOOL_SLOT_ONE_LINE_CHARS: int = 7
## 道具の枠どうしの間隔 (px)。枠の線 (1〜2 px) が隣の枠の線と重ならず、8 つの枠が 1 つの並びに見える狭さ
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
	# 道具の枠の並びは右下の角を起点に左へ伸ばす (道具の名前と枠の数で幅が変わるため)
	_tool_row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_anchor_bottom_right(_tool_row, TOOL_SLOT_SIZE_PX, 0.0)
	add_child(_tool_row)
	set_tools(SAMPLE_TOOL_NAMES, SAMPLE_SELECTED_TOOL_INDEX)

	# 文字の大きさ: 所持金 20 px・案内 18 px・道具の名前 16 px。既存の残り本数の文字より小さくし、
	# 1280x720 で読める下限の 16 px から、目に入る順 (所持金 > 案内 > 道具) に 2 px ずつ大きくした
	_money_label = make_label("MoneyLabel", 20, HORIZONTAL_ALIGNMENT_RIGHT)
	# 道具の枠の上に 8 px 空けて置く (所持金は道具を買うためのお金なので道具の並びの上に添える)。
	# 大きさは 20 px の文字で「所持金 999,999,999 円」が 1 行に収まる幅と、1 行の高さ
	_anchor_bottom_right(
		_money_label, Vector2(320.0, LABEL_LINE_HEIGHT_PX), TOOL_SLOT_SIZE_PX.y + ROW_GAP_PX
	)
	add_child(_money_label)

	_guide_label = make_label("GuideLabel", 18, HORIZONTAL_ALIGNMENT_LEFT)
	_guide_label.text = SAMPLE_GUIDE_TEXT
	# 大きさは 18 px の文字で 30 文字の案内が 1 行に収まる幅 (所持金の左端に届かない幅) と、1 行の高さ。
	# 道具 8 つの枠は画面の幅の大半を使うため、案内は枠の行ではなく所持金と同じ高さの左に置く
	_guide_label.anchor_top = 1.0
	_guide_label.anchor_bottom = 1.0
	_guide_label.offset_left = SCREEN_MARGIN_PX
	_guide_label.offset_right = SCREEN_MARGIN_PX + 560.0
	_guide_label.offset_top = (
		-SCREEN_MARGIN_PX - TOOL_SLOT_SIZE_PX.y - ROW_GAP_PX - LABEL_LINE_HEIGHT_PX
	)
	_guide_label.offset_bottom = -SCREEN_MARGIN_PX - TOOL_SLOT_SIZE_PX.y - ROW_GAP_PX
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


## 道具の枠の並びを、左から slot_texts の文字の枠で作り直し、selected_index の枠を手に持っている枠にする
func set_tools(slot_texts: Array[String], selected_index: int) -> void:
	for old_slot: Node in _tool_row.get_children():
		_tool_row.remove_child(old_slot)
		old_slot.free()
	for tool_index: int in range(slot_texts.size()):
		_tool_row.add_child(
			_make_tool_slot(tool_index, slot_texts[tool_index], tool_index == selected_index)
		)


## 道具の枠の文字を左から順に返す
func get_tool_slot_texts() -> Array[String]:
	var texts: Array[String] = []
	for slot: Node in _tool_row.get_children():
		texts.append((slot.get_node("ToolName") as Label).text)
	return texts


## 手に持っている道具の枠の位置を返す (無ければ -1)
func get_selected_tool_slot_index() -> int:
	for slot: Node in _tool_row.get_children():
		if bool(slot.get_meta("selected", false)):
			return slot.get_index()
	return -1


## 道具の枠 1 つ (細い線の四角と、中央の道具の名前) を作る
func _make_tool_slot(tool_index: int, slot_text: String, selected: bool) -> PanelContainer:
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
	slot.set_meta("selected", selected)
	var label: Label = make_label("ToolName", 16, HORIZONTAL_ALIGNMENT_CENTER)
	label.text = slot_text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# 枠の幅に 1 行で収まらない名前 (「4 ゴム手袋とスポンジ」など) は、字を小さくして枠の中で 2 行に折り返す
	if slot_text.length() > TOOL_SLOT_ONE_LINE_CHARS:
		label.add_theme_font_size_override("font_size", 13)
		label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		label.add_theme_constant_override("line_spacing", -3)
	slot.add_child(label)
	return slot


## 影付きの文字のラベルを作る
static func make_label(
	node_name: String, font_size: int, alignment: HorizontalAlignment
) -> Label:
	var label: Label = Label.new()
	label.name = node_name
	label.horizontal_alignment = alignment
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	label.add_theme_color_override("font_shadow_color", TEXT_SHADOW_COLOR)
	# 影を右下へ 1・2 px ずらす。上から照らした時の影の向きで、16 px の文字でも影と文字が重なって潰れない最小のずれ
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

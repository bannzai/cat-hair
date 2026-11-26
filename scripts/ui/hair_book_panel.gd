class_name HairBookPanel
extends PanelContainer
## 珍しい毛の図鑑の画面。HandRules の珍しい毛の表の順に並べ、見つけた毛は名前を、まだの毛は「？？？」を出す。
## 状態は持たず、開くたびに見つけた毛の一覧 (GameState) を受け取って描き直す。

## 図鑑を閉じる操作をした時
signal close_requested

## 手で毛を取る時のルールの計算 (珍しい毛の表)
const HandRulesScript := preload("res://scripts/hand/hand_rules.gd")
## まだ見つけていない毛の表示
const UNKNOWN_TEXT: String = "？？？"

## 見つけた数の見出し
var _summary_label: Label = null
## 珍しい毛 1 種類ごとの行 (表の順)
var _entry_labels: Array[Label] = []


## ツリーに入った時に画面の部品を組み立てる
func _ready() -> void:
	if _summary_label == null:
		_build()


## 見つけた珍しい毛の一覧で表示を描き直す
func refresh(found_rare_hair_ids: Array[StringName]) -> void:
	if _summary_label == null:
		_build()
	var found_count: int = 0
	for entry_idx: int in range(HandRulesScript.RARE_HAIRS.size()):
		var rare: Dictionary = HandRulesScript.RARE_HAIRS[entry_idx]
		var found: bool = found_rare_hair_ids.has(rare["id"])
		if found:
			found_count += 1
		_entry_labels[entry_idx].text = "・%s" % (str(rare["name"]) if found else UNKNOWN_TEXT)
	_summary_label.text = "見つけた珍しい毛: %d / %d 種類" % [
		found_count, HandRulesScript.RARE_HAIRS.size()
	]


## 見つけた数の見出しの文言を返す (検証用)
func get_summary_text() -> String:
	return _summary_label.text if _summary_label != null else ""


## 珍しい毛の行の文言を表の順に返す (検証用)
func get_entry_texts() -> PackedStringArray:
	var texts: PackedStringArray = PackedStringArray()
	for label: Label in _entry_labels:
		texts.append(label.text)
	return texts


## 見出し・行・閉じるボタンを組み立てる
func _build() -> void:
	var background: StyleBoxFlat = StyleBoxFlat.new()
	background.bg_color = Color(0.16, 0.12, 0.09, 0.96)
	background.set_corner_radius_all(8)
	background.set_content_margin_all(24.0)
	add_theme_stylebox_override("panel", background)
	var layout: VBoxContainer = VBoxContainer.new()
	layout.name = "Layout"
	layout.add_theme_constant_override("separation", 10)
	add_child(layout)

	var title: Label = Label.new()
	title.name = "Title"
	title.text = "珍しい毛の図鑑"
	title.add_theme_font_size_override("font_size", 28)
	layout.add_child(title)

	_summary_label = Label.new()
	_summary_label.name = "Summary"
	_summary_label.add_theme_font_size_override("font_size", 18)
	layout.add_child(_summary_label)

	for rare: Dictionary in HandRulesScript.RARE_HAIRS:
		var entry: Label = Label.new()
		entry.name = "Entry_%s" % String(rare["id"])
		entry.add_theme_font_size_override("font_size", 22)
		layout.add_child(entry)
		_entry_labels.append(entry)

	var hint: Label = Label.new()
	hint.name = "Hint"
	hint.text = "珍しい毛は手でつまんだ時にだけ見分けられる"
	hint.add_theme_font_size_override("font_size", 14)
	layout.add_child(hint)

	var close_button: Button = Button.new()
	close_button.name = "CloseButton"
	close_button.text = "閉じる (B)"
	close_button.pressed.connect(func() -> void: close_requested.emit())
	layout.add_child(close_button)
	var none_found: Array[StringName] = []
	refresh(none_found)

class_name RequestListPanel
extends PanelContainer
## 住人の依頼の一覧の画面 (J で開閉)。探し物の残りの数と 1 件ごとの様子、黒いスーツの服の毛の依頼、逃げた猫の依頼を出す。
## 状態は持たず、開くたびに GameState の依頼の状態を受け取って描き直す。

## 一覧を閉じる操作をした時
signal close_requested

## 依頼の計算 (探し物の種類・お礼・締め切り)
const RequestRulesScript := preload("res://scripts/requests/request_rules.gd")
## 探し物の状態の型 (Condition の定数)
const FoundItemProgressScript := preload("res://scripts/data/found_item_progress.gd")
## 道具の定義 (合う道具の名前)
const ToolCatalogScript := preload("res://scripts/tools/tool_catalog.gd")
## 猫の通り道の計算 (猫の名前)
const CatRulesScript := preload("res://scripts/automation/cat_rules.gd")

## 探し物の残りの数の見出し
var _summary_label: Label = null
## 探し物・スーツ・逃げた猫の行を並べる親 (開くたびに作り直す)
var _rows: VBoxContainer = null


## ツリーに入った時に画面の部品を組み立てる
func _ready() -> void:
	if _summary_label == null:
		_build()


## GameState (game_state) の依頼の状態で表示を描き直す
func refresh(game_state: Node) -> void:
	if _summary_label == null:
		_build()
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.free()
	var layout: MansionLayout = game_state.current_layout
	var requests: RefCounted = game_state.requests
	_summary_label.text = "探し物: 残り %d / %d 件" % [
		requests.remaining_item_count(), layout.found_item_spots.size() if layout != null else 0
	]
	if layout == null:
		return
	for spot: MansionLayout.FoundItemSpotDef in layout.found_item_spots:
		_add_row(_item_text(spot, requests.find_item(spot.found_item_id), layout))
	for suit: Dictionary in requests.suit_requests():
		_add_row(_suit_text(suit, layout))
	var owner_room: MansionLayout.RoomDef = RequestRulesScript.runaway_owner_room(layout)
	if owner_room != null:
		_add_row(_cat_text(requests.runaway_status(), owner_room))


## 見出しの文言を返す (検証用)
func get_summary_text() -> String:
	return _summary_label.text if _summary_label != null else ""


## 行の文言を表示の順に返す (検証用)
func get_row_texts() -> PackedStringArray:
	var texts: PackedStringArray = PackedStringArray()
	if _rows != null:
		for row: Node in _rows.get_children():
			texts.append((row as Label).text)
	return texts


## 探し物 1 件の行の文言
static func _item_text(
	spot: MansionLayout.FoundItemSpotDef, item: FoundItemProgress, layout: MansionLayout
) -> String:
	var kind: Dictionary = RequestRulesScript.kind_for_item_id(spot.found_item_id)
	var state_text: String = "毛の山に埋もれている (面の毛が半分になると出てくる)"
	if item != null and item.is_returned:
		state_text = "返した (お礼 %d 円)" % RequestRulesScript.reward(item.condition)
	elif item != null:
		match item.condition:
			FoundItemProgressScript.Condition.FOUND:
				state_text = "見つけた: %sで丁寧に取る" % (
					ToolCatalogScript.find_tool(kind["match_tool"]).get("name", "")
				)
			FoundItemProgressScript.Condition.CLEAN:
				state_text = "きれいに取った: 持ち主の部屋で返す (お礼 %d 円)" % (
					RequestRulesScript.REWARD_CLEAN
				)
			FoundItemProgressScript.Condition.DAMAGED:
				state_text = "傷めて取った: 持ち主の部屋で返す (お礼 %d 円)" % (
					RequestRulesScript.REWARD_DAMAGED
				)
	return "・%s (%sの住人): %s" % [kind["name"], _room_name(layout, spot.room_id), state_text]


## 黒いスーツの服の毛の依頼 1 件の行の文言 (suit は RequestState.suit_requests の要素)
static func _suit_text(suit: Dictionary, layout: MansionLayout) -> String:
	var state_text: String = ""
	match suit["status"]:
		&"done":
			state_text = "取り切った (上乗せ %d 円)" % RequestRulesScript.SUIT_BONUS
		&"missed":
			state_text = "取り切る前に出かけた"
		_:
			var seconds_left: int = ceili(float(suit["seconds_left"]))
			state_text = "残り %d 本 / 出かけるまで %d:%02d (取り切ると +%d 円)" % [
				int(suit["remaining"]), floori(seconds_left / 60.0), seconds_left % 60,
				RequestRulesScript.SUIT_BONUS,
			]
	return "・黒いスーツの服の毛 (%sの住人): %s" % [_room_name(layout, suit["room_id"]), state_text]


## 逃げた猫の依頼の行の文言 (status は RequestRules.runaway_status)
static func _cat_text(status: StringName, owner_room: MansionLayout.RoomDef) -> String:
	var state_text: String = "まだ逃げていない"
	match status:
		&"escaped":
			state_text = "逃げた: 毛の跡をたどって探し、近づいて抱える"
		&"carried":
			state_text = "抱えている: %sに届ける" % owner_room.display_name
		&"returned":
			state_text = "届けた"
	return "・逃げた猫 %s (%sの住人): %s" % [
		CatRulesScript.CATS[RequestRulesScript.RUNAWAY_CAT_INDEX]["name"],
		owner_room.display_name,
		state_text,
	]


## 部屋 room_id の表示名 (無ければ id)
static func _room_name(layout: MansionLayout, room_id: StringName) -> String:
	for room: MansionLayout.RoomDef in layout.rooms:
		if room.room_id == room_id:
			return room.display_name
	return String(room_id)


## 行を 1 つ足す
func _add_row(text: String) -> void:
	var row: Label = Label.new()
	row.text = text
	row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# 図鑑の画面の見出しの下の行 (18) と同じ大きさ。10 行が一覧の高さに収まる
	row.add_theme_font_size_override("font_size", 18)
	_rows.add_child(row)


## 見出し・行の親・案内・閉じるボタンを組み立てる
func _build() -> void:
	# 背景・角丸・余白・見出しの大きさは、図鑑の画面 (HairBookPanel) とそろえる
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
	title.text = "住人の依頼"
	title.add_theme_font_size_override("font_size", 28)
	layout.add_child(title)

	_summary_label = Label.new()
	_summary_label.name = "Summary"
	# 行 (18) より一段大きくして、残りの数を先に読めるようにする
	_summary_label.add_theme_font_size_override("font_size", 20)
	layout.add_child(_summary_label)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.name = "Rows"
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 行どうしは見出しの間 (10) より詰め、一覧として 1 かたまりに見せる
	_rows.add_theme_constant_override("separation", 6)
	scroll.add_child(_rows)

	var hint: Label = Label.new()
	hint.name = "Hint"
	var damaging: PackedStringArray = PackedStringArray()
	for tool_def: Dictionary in ToolCatalogScript.TOOLS:
		if bool(tool_def["damages_found_items"]):
			damaging.append(str(tool_def["name"]))
	hint.text = "%sで取ると傷む。取った探し物は持ち主の部屋に入ると返し、お礼は次の掃除代に上乗せされる" % (
		"・".join(damaging)
	)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 14)
	layout.add_child(hint)

	var close_button: Button = Button.new()
	close_button.name = "CloseButton"
	close_button.text = "閉じる (J)"
	close_button.pressed.connect(func() -> void: close_requested.emit())
	layout.add_child(close_button)

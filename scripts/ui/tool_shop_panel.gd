class_name ToolShopPanel
extends PanelContainer
## 道具を買う画面。道具ごとに値段・得意な表面・消耗品・探し物を傷めるかを出し、買う・レベルを上げる・消耗品を買い足す。
## 手の強化もここで買う。毛を売るのは、裏口の買取業者の近くにいる時だけ押せる。
## 状態は持たず、開くたびと買った後に GameState を受け取って描き直す。押した操作はシグナルで main へ渡す。

## 買う操作をした時 (kind は GameState.PURCHASE_*、item_id は道具の id か手の強化の id)
signal purchase_requested(kind: StringName, item_id: StringName)
## 毛を売る操作をした時
signal sell_requested
## 画面を閉じる操作をした時
signal close_requested

## ゲーム状態のスクリプト (買う物の種類の定数を使う)
const GameStateScript := preload("res://scripts/state/game_state.gd")
## 手に持って使う道具の定義
const ToolCatalogScript := preload("res://scripts/tools/tool_catalog.gd")
## 手に持って使う道具のルールの計算
const ToolRulesScript := preload("res://scripts/tools/tool_rules.gd")
## 手で毛を取る時のルールの計算 (手の強化の種類)
const HandRulesScript := preload("res://scripts/hand/hand_rules.gd")
## 毛を売る・掃除代の計算
const EconomyRulesScript := preload("res://scripts/economy/economy_rules.gd")
## 屋敷レイアウト型スクリプト (表面の種類の定数を使う)
const MansionLayoutScript := preload("res://scripts/mansion/mansion_layout.gd")
## 表面の種類の表示名
const SURFACE_NAMES: Dictionary = {
	MansionLayoutScript.SURFACE_FLOOR: "床",
	MansionLayoutScript.SURFACE_CARPET: "カーペット",
	MansionLayoutScript.SURFACE_SOFA: "ソファ",
	MansionLayoutScript.SURFACE_KNIT: "ニット",
	MansionLayoutScript.SURFACE_SUIT: "スーツ",
	MansionLayoutScript.SURFACE_FURNITURE: "家具",
}
## 手の強化の表示名 (並び順が画面の並び)
const HAND_UPGRADE_NAMES: Dictionary = {
	HandRulesScript.UPGRADE_DEXTERITY: "手の強化: 指先の器用さ (引く時間が短くなる)",
	HandRulesScript.UPGRADE_GRAB_COUNT: "手の強化: 一度につまめる本数",
}

## 所持金と在庫の見出し
var _money_label: Label = null
## 毛を売るボタン
var _sell_button: Button = null
## 道具ごとの説明の行 (tool_id -> Label)
var _tool_labels: Dictionary = {}
## 道具ごとの買う / レベルを上げるボタン (tool_id -> Button)
var _tool_buttons: Dictionary = {}
## 消耗品を使う道具の買い足すボタン (tool_id -> Button)
var _refill_buttons: Dictionary = {}
## 手の強化ごとのボタン (upgrade_id -> Button)
var _hand_upgrade_buttons: Dictionary = {}
## 最後に描き直した時点で道具を持っていたか (tool_id -> bool。ボタンが買うかレベルを上げるかを決める)
var _owned_on_refresh: Dictionary = {}


## ツリーに入った時に画面の部品を組み立てる
func _ready() -> void:
	if _money_label == null:
		_build()


## GameState の所持金・在庫・持っている道具で表示を描き直す。near_trader は買取業者の近くにいるか
func refresh(game_state: Node, near_trader: bool) -> void:
	if _money_label == null:
		_build()
	var money: int = game_state.get_money()
	var stock_value: int = EconomyRulesScript.raw_stock_value(
		game_state.save_data.building_progress.hair_stocks
	)
	_money_label.text = "所持金: %d 円 / 在庫の毛: %d 本 (売ると %d 円)" % [
		money, game_state.get_raw_hair_stock_count(), stock_value
	]
	_sell_button.disabled = not near_trader or stock_value <= 0
	_sell_button.text = (
		"毛を売る (+%d 円)" % stock_value if near_trader else "毛を売る (裏口の買取業者の近くで売れる)"
	)
	for tool_def: Dictionary in ToolCatalogScript.TOOLS:
		var tool_id: StringName = tool_def["id"]
		if tool_id == ToolCatalogScript.TOOL_HAND:
			continue
		var owned: OwnedTool = game_state.find_owned_tool(tool_id)
		_owned_on_refresh[tool_id] = owned != null
		var button: Button = _tool_buttons[tool_id]
		(_tool_labels[tool_id] as Label).text = describe_tool(tool_id, owned)
		if owned == null:
			button.text = "買う (%d 円)" % int(tool_def["price"])
			button.disabled = not ToolRulesScript.can_afford(money, int(tool_def["price"]))
		else:
			var price: int = ToolRulesScript.level_up_price(tool_id, owned.level)
			if price >= 0:
				button.text = "レベルを上げる (%d 円)" % price
			elif tool_def["kind"] == ToolCatalogScript.KIND_SWEEP:
				button.text = "レベル上限"
			else:
				button.text = "持っている"
			button.disabled = not ToolRulesScript.can_afford(money, price)
		if _refill_buttons.has(tool_id):
			var refill: Button = _refill_buttons[tool_id]
			refill.visible = owned != null
			refill.text = "%sを %d 枚買い足す (%d 円)" % [
				tool_def["consumable_name"], int(tool_def["refill_count"]), int(tool_def["refill_price"])
			]
			refill.disabled = not ToolRulesScript.can_afford(money, int(tool_def["refill_price"]))
	for upgrade_id: StringName in _hand_upgrade_buttons.keys():
		var level: int = game_state.get_hand_upgrade_level(upgrade_id)
		var upgrade_price: int = ToolRulesScript.hand_upgrade_price(level)
		var upgrade_button: Button = _hand_upgrade_buttons[upgrade_id]
		upgrade_button.text = (
			"%s 段 %d → %d (%d 円)" % [HAND_UPGRADE_NAMES[upgrade_id], level, level + 1, upgrade_price]
			if upgrade_price >= 0
			else "%s 段 %d (上限)" % [HAND_UPGRADE_NAMES[upgrade_id], level]
		)
		upgrade_button.disabled = not ToolRulesScript.can_afford(money, upgrade_price)


## 道具 1 つの説明 (名前・レベル・得意・不得意な表面・消耗品の残り・探し物を傷めるか) を返す
static func describe_tool(tool_id: StringName, owned: OwnedTool) -> String:
	var tool_def: Dictionary = ToolCatalogScript.find_tool(tool_id)
	var parts: PackedStringArray = PackedStringArray([str(tool_def["name"])])
	parts.append("Lv %d" % owned.level if owned != null else "未購入")
	if tool_def["kind"] == ToolCatalogScript.KIND_SWEEP:
		parts.append(
			"取りこぼし %d%%" % roundi(
				100.0 * ToolRulesScript.miss_ratio(tool_id, owned.level if owned != null else 1, &"")
			)
		)
		if not (tool_def["good"] as Array).is_empty():
			parts.append("得意: %s" % _surface_list(tool_def["good"]))
		if not (tool_def["bad"] as Array).is_empty():
			parts.append("不得意: %s" % _surface_list(tool_def["bad"]))
	elif tool_def["kind"] == ToolCatalogScript.KIND_LIGHT:
		parts.append("点けると毛が見つけやすくなる")
	elif tool_def["kind"] == ToolCatalogScript.KIND_CAT:
		parts.append("猫をブラッシングして落ちる前の毛を取る")
	if ToolRulesScript.uses_consumable(tool_id):
		parts.append(
			"%s: %s" % [
				tool_def["consumable_name"],
				"%d 枚" % owned.consumable_count if owned != null else "買うと %d 枚" % int(
					tool_def["initial_consumables"]
				),
			]
		)
	if bool(tool_def["damages_found_items"]):
		parts.append("探し物を傷める")
	return " / ".join(parts)


## 道具の買う / レベルを上げるボタンを返す (検証用)
func get_tool_button(tool_id: StringName) -> Button:
	return _tool_buttons.get(tool_id) as Button


## 消耗品を買い足すボタンを返す (検証用。消耗品を使わない道具は null)
func get_refill_button(tool_id: StringName) -> Button:
	return _refill_buttons.get(tool_id) as Button


## 手の強化のボタンを返す (検証用)
func get_hand_upgrade_button(upgrade_id: StringName) -> Button:
	return _hand_upgrade_buttons.get(upgrade_id) as Button


## 毛を売るボタンを返す (検証用)
func get_sell_button() -> Button:
	return _sell_button


## 見出し・道具の行・手の強化・売る・閉じるボタンを組み立てる
func _build() -> void:
	var background: StyleBoxFlat = StyleBoxFlat.new()
	background.bg_color = Color(0.16, 0.12, 0.09, 0.96)
	background.set_corner_radius_all(8)
	background.set_content_margin_all(20.0)
	add_theme_stylebox_override("panel", background)
	var layout: VBoxContainer = VBoxContainer.new()
	layout.name = "Layout"
	layout.add_theme_constant_override("separation", 6)
	add_child(layout)

	var title: Label = Label.new()
	title.name = "Title"
	title.text = "道具を買う"
	title.add_theme_font_size_override("font_size", 26)
	layout.add_child(title)

	_money_label = Label.new()
	_money_label.name = "Money"
	_money_label.add_theme_font_size_override("font_size", 17)
	layout.add_child(_money_label)

	_sell_button = Button.new()
	_sell_button.name = "SellButton"
	_sell_button.pressed.connect(func() -> void: sell_requested.emit())
	layout.add_child(_sell_button)

	for tool_def: Dictionary in ToolCatalogScript.TOOLS:
		var tool_id: StringName = tool_def["id"]
		if tool_id == ToolCatalogScript.TOOL_HAND:
			continue
		var row: HBoxContainer = HBoxContainer.new()
		row.name = "Row_%s" % String(tool_id)
		layout.add_child(row)
		var label: Label = Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 14)
		row.add_child(label)
		_tool_labels[tool_id] = label
		var button: Button = Button.new()
		button.name = "ToolButton"
		button.custom_minimum_size = Vector2(190.0, 0.0)
		button.pressed.connect(_on_tool_button_pressed.bind(tool_id))
		row.add_child(button)
		_tool_buttons[tool_id] = button
		if ToolRulesScript.uses_consumable(tool_id):
			var refill: Button = Button.new()
			refill.name = "RefillButton"
			refill.pressed.connect(
				func() -> void: purchase_requested.emit(GameStateScript.PURCHASE_CONSUMABLE, tool_id)
			)
			row.add_child(refill)
			_refill_buttons[tool_id] = refill

	for upgrade_id: StringName in HAND_UPGRADE_NAMES.keys():
		var upgrade_button: Button = Button.new()
		upgrade_button.name = "HandUpgrade_%s" % String(upgrade_id)
		upgrade_button.pressed.connect(
			func() -> void: purchase_requested.emit(GameStateScript.PURCHASE_HAND_UPGRADE, upgrade_id)
		)
		layout.add_child(upgrade_button)
		_hand_upgrade_buttons[upgrade_id] = upgrade_button

	var close_button: Button = Button.new()
	close_button.name = "CloseButton"
	close_button.text = "閉じる (T)"
	close_button.pressed.connect(func() -> void: close_requested.emit())
	layout.add_child(close_button)


## 道具の行のボタンを押した時、最後に描き直した時点で持っていなければ買う、持っていればレベルを上げる操作を出す
func _on_tool_button_pressed(tool_id: StringName) -> void:
	purchase_requested.emit(
		(
			GameStateScript.PURCHASE_LEVEL_UP
			if bool(_owned_on_refresh.get(tool_id, false))
			else GameStateScript.PURCHASE_TOOL
		),
		tool_id
	)


## 表面の種類の一覧を表示名の並びにする
static func _surface_list(surface_types: Array) -> String:
	var names: PackedStringArray = PackedStringArray()
	for surface_type: Variant in surface_types:
		names.append(str(SURFACE_NAMES.get(surface_type, String(surface_type))))
	return "・".join(names)

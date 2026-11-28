class_name ToolShopPanel
extends PanelContainer
## 道具を買う画面。道具ごとに値段・得意な表面・消耗品・探し物を傷めるかを出し、買う・レベルを上げる・消耗品を買い足す。
## 手の強化もここで買う。毛を売るのは、裏口の買取業者の近くにいる時だけ押せる。
## 状態は持たず、開くたびと買った後に GameState を受け取って描き直す。押した操作はシグナルで main へ渡す。

## 買う操作をした時 (kind は GameState.PURCHASE_*、item_id は道具の id か手の強化の id)
signal purchase_requested(kind: StringName, item_id: StringName)
## 毛を売る操作をした時
signal sell_requested
## 毛を運ぶダンプカーを呼ぶ操作をした時
signal haul_requested
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
## 選ばずに働く大型の道具 (アンドロイドの掃除の間隔を使う)
const BigToolSiteScript := preload("res://scripts/tools/big_tool_site.gd")
## 毛の加工機とダンプカーの計算 (在庫の売値)
const ProcessingRulesScript := preload("res://scripts/economy/processing_rules.gd")
## 毛・加工品在庫データ型スクリプト (形の定数を使う)
const HairStockScript := preload("res://scripts/data/hair_stock.gd")
## 加工した物の形の表示名 (毛のままは含めない)
const PRODUCT_NAMES: Dictionary = {
	HairStockScript.FORM_BALL: "毛玉",
	HairStockScript.FORM_FELT: "フェルト",
	HairStockScript.FORM_DOLL: "人形",
}
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
	HandRulesScript.UPGRADE_DEXTERITY: "手の強化: 指先の器用さ (狙える範囲が広がる)",
	HandRulesScript.UPGRADE_GRAB_COUNT: "手の強化: 一度につまめる本数",
}

## 所持金と在庫の見出し
var _money_label: Label = null
## 毛を売るボタン
var _sell_button: Button = null
## 毛を運ぶダンプカーを呼ぶボタン (ダンプカーを持っている時だけ見せる)
var _haul_button: Button = null
## 道具の行と手の強化を縦に送って見る枠 (道具の行が画面の高さに収まらないため)
var _scroll: ScrollContainer = null
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
	var stocks: Array[HairStock] = game_state.save_data.building_progress.hair_stocks
	var owned_tools: Array[OwnedTool] = game_state.save_data.building_progress.owned_tools
	var stock_value: int = ProcessingRulesScript.stock_value(stocks)
	_money_label.text = "所持金: %d 円 / 在庫の毛: %d 本%s (売ると %d 円)" % [
		money, game_state.get_raw_hair_stock_count(), describe_products(stocks), stock_value
	]
	_sell_button.disabled = not near_trader or stock_value <= 0
	_sell_button.text = (
		"毛と加工品を売る (+%d 円)" % stock_value
		if near_trader
		else "毛と加工品を売る (裏口の買取業者の近くで売れる)"
	)
	_haul_button.visible = (
		ToolRulesScript.count_owned(owned_tools, ToolCatalogScript.TOOL_DUMP_TRUCK) > 0
	)
	_haul_button.disabled = stock_value <= 0
	_haul_button.text = "毛を運ぶダンプカーで運び出して売る (1 回 %d 本分まで。どこからでも)" % (
		ProcessingRulesScript.DUMP_TRUCK_CAPACITY_HAIRS
	)
	for tool_def: Dictionary in ToolCatalogScript.TOOLS:
		var tool_id: StringName = tool_def["id"]
		if tool_id == ToolCatalogScript.TOOL_HAND:
			continue
		var owned: OwnedTool = game_state.find_owned_tool(tool_id)
		var owned_count: int = ToolRulesScript.count_owned(owned_tools, tool_id)
		var can_add: bool = owned_count < ToolCatalogScript.max_owned(tool_id)
		# 並べて持てる道具 (加工機) は、上限まではもう 1 台買う操作にする
		_owned_on_refresh[tool_id] = owned != null and not can_add
		var button: Button = _tool_buttons[tool_id]
		(_tool_labels[tool_id] as Label).text = describe_tool(tool_id, owned, owned_count)
		if owned == null or can_add:
			button.text = (
				"買う (%d 円)" % int(tool_def["price"])
				if owned == null
				else "もう 1 台並べる (%d 円)" % int(tool_def["price"])
			)
			button.disabled = not ToolRulesScript.can_afford(money, int(tool_def["price"]))
		else:
			var price: int = ToolRulesScript.level_up_price(tool_id, owned.level)
			if price >= 0:
				button.text = "レベルを上げる (%d 円)" % price
			elif ToolRulesScript.removes_hair(tool_id):
				button.text = "レベル上限"
			elif ToolCatalogScript.max_owned(tool_id) > 1:
				button.text = "%d 台並べた (上限)" % owned_count
			else:
				button.text = "持っている"
			button.disabled = not ToolRulesScript.can_afford(money, price)
		if _refill_buttons.has(tool_id):
			var refill: Button = _refill_buttons[tool_id]
			refill.visible = owned != null
			refill.text = (
				"%sを交換する (%d 円)" % [tool_def["consumable_name"], int(tool_def["refill_price"])]
				if ToolRulesScript.refill_replaces(tool_id)
				else "%sを %d %s買い足す (%d 円)" % [
					tool_def["consumable_name"],
					int(tool_def["refill_count"]),
					ToolRulesScript.consumable_unit(tool_id),
					int(tool_def["refill_price"]),
				]
			)
			# パックの空きが満タンの時は、交換しても変わらないので押せなくする
			refill.disabled = (
				not ToolRulesScript.can_afford(money, int(tool_def["refill_price"]))
				or owned == null
				or not ToolRulesScript.refill_changes_count(tool_id, owned.consumable_count)
			)
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


## 道具 1 つの説明 (名前・レベル・得意・不得意な表面・消耗品の残り・探し物を傷めるか) を返す。
## owned_count は並べて持てる道具 (加工機) の持っている台数
static func describe_tool(tool_id: StringName, owned: OwnedTool, owned_count: int = 1) -> String:
	var tool_def: Dictionary = ToolCatalogScript.find_tool(tool_id)
	var parts: PackedStringArray = PackedStringArray([str(tool_def["name"])])
	if owned != null and ToolCatalogScript.max_owned(tool_id) > 1:
		parts.append("%d 台 (%d 台まで)" % [owned_count, ToolCatalogScript.max_owned(tool_id)])
	elif owned != null:
		parts.append("Lv %d" % owned.level)
	elif tool_id != ToolCatalogScript.TOOL_HAND:
		# 手は最初から持っていて owned_tools に入れないため、買っていない印を出さない
		parts.append("未購入")
	match tool_def["kind"]:
		ToolCatalogScript.KIND_ROOM:
			parts.append("運転席から今いる部屋をまるごと吸う")
		ToolCatalogScript.KIND_SHEET:
			parts.append("今いる部屋の床一面に敷き、床とカーペットの毛を捕まえる")
		ToolCatalogScript.KIND_AUTO:
			parts.append(
				"毛のいちばん多い部屋を %d 秒ごとに自動で掃除する" % int(
					BigToolSiteScript.ANDROID_INTERVAL_SECONDS
				)
			)
		ToolCatalogScript.KIND_PROCESS:
			parts.append(
				"%d 秒ごとに毛を毛玉・フェルト・人形にする。1 台は白と黒を混ぜ、3 台で色を分ける"
				% int(ProcessingRulesScript.PROCESS_INTERVAL_SECONDS)
			)
		ToolCatalogScript.KIND_TRANSPORT:
			parts.append("在庫を売り先へ運び出す")
	if ToolRulesScript.removes_hair(tool_id):
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
		var unit: String = ToolRulesScript.consumable_unit(tool_id)
		parts.append(
			"%s%s: %s" % [
				tool_def["consumable_name"],
				"の空き" if ToolRulesScript.refill_replaces(tool_id) else "",
				"%d %s" % [owned.consumable_count, unit]
				if owned != null
				else "買うと %d %s" % [int(tool_def["initial_consumables"]), unit],
			]
		)
	if bool(tool_def["damages_found_items"]):
		parts.append("探し物を傷める")
	return " / ".join(parts)


## 在庫の加工した物の個数を「 / 毛玉 N 個・フェルト N 枚…」の形で返す (加工した物が無ければ空)
static func describe_products(stocks: Array[HairStock]) -> String:
	var counts: Dictionary = {}
	for stock: HairStock in stocks:
		if stock != null and PRODUCT_NAMES.has(stock.form):
			counts[stock.form] = int(counts.get(stock.form, 0)) + stock.count
	var parts: PackedStringArray = PackedStringArray()
	for form: Variant in PRODUCT_NAMES.keys():
		if int(counts.get(form, 0)) > 0:
			parts.append("%s %d 個" % [PRODUCT_NAMES[form], int(counts[form])])
	return " / " + "・".join(parts) if not parts.is_empty() else ""


## 毛を運ぶダンプカーを呼ぶボタンを返す (検証用)
func get_haul_button() -> Button:
	return _haul_button


## 道具 tool_id の行が見える所まで、道具の行の枠を送る (画面を開いて並びが決まった後に呼ぶ)
func scroll_to_tool(tool_id: StringName) -> void:
	if _tool_buttons.has(tool_id):
		_scroll.ensure_control_visible(_tool_buttons[tool_id])


## 所持金と在庫の見出しの文言を返す (検証用)
func get_money_label_text() -> String:
	return _money_label.text


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

	_haul_button = Button.new()
	_haul_button.name = "HaulButton"
	_haul_button.visible = false
	_haul_button.pressed.connect(func() -> void: haul_requested.emit())
	layout.add_child(_haul_button)

	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(_scroll)
	var rows: VBoxContainer = VBoxContainer.new()
	rows.name = "Rows"
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 6)
	_scroll.add_child(rows)

	for tool_def: Dictionary in ToolCatalogScript.TOOLS:
		var tool_id: StringName = tool_def["id"]
		if tool_id == ToolCatalogScript.TOOL_HAND:
			continue
		var row: HBoxContainer = HBoxContainer.new()
		row.name = "Row_%s" % String(tool_id)
		rows.add_child(row)
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
		rows.add_child(upgrade_button)
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

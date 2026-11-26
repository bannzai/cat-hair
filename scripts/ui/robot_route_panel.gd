class_name RobotRoutePanel
extends PanelContainer
## 掃除ロボットを買い、1 台ずつ回る部屋の順を決める画面。台を選び、部屋のボタンを押した順に回る順へ足す。
## 回る順の正は GameState (OwnedTool.robot_room_ids) で、この画面は開くたびと操作の後に GameState を受け取って描き直す。
## 押した操作はシグナルで main へ渡す。画面が持つのは、どの台の順を組んでいるか (選んでいる台) だけ。

## 掃除ロボットを買う操作をした時 (最初に回る部屋は main が今いる部屋から決める)
signal buy_requested
## 回る順を変える操作をした時 (robot_index は GameState.get_robots の並び)
signal route_change_requested(robot_index: int, room_ids: Array[StringName])
## 画面を閉じる操作をした時
signal close_requested

## 掃除ロボットの値段・回る順・毛を取る量の計算
const RobotRulesScript := preload("res://scripts/automation/robot_rules.gd")

## 所持金と台数の見出し
var _money_label: Label = null
## 掃除ロボットを買うボタン
var _buy_button: Button = null
## 台ごとの行の親
var _robot_rows: VBoxContainer = null
## 部屋のボタンの親 (選んでいる台の回る順に足す)
var _room_buttons: HFlowContainer = null
## 選んでいる台の回る順の最後の部屋を外すボタン
var _remove_last_button: Button = null
## 選んでいる台の回る順を空にする (止める) ボタン
var _clear_button: Button = null
## 組んでいる台 (GameState.get_robots の添字。台が無ければ -1)
var _selected_index: int = -1
## 部屋のボタンを作った時の屋敷の部屋の id の並び (屋敷を組み直して部屋が変わった時だけボタンを作り直す)
var _room_button_ids: Array[StringName] = []
## 最後に描き直した時の、台ごとの回る順 (ボタンを押した時に、その順に部屋を足した順を出すため)
var _routes_on_refresh: Array[Array] = []


## ツリーに入った時に画面の部品を組み立てる
func _ready() -> void:
	if _money_label == null:
		_build()


## GameState の所持金・掃除ロボット・屋敷の部屋で表示を描き直す
func refresh(game_state: Node) -> void:
	if _money_label == null:
		_build()
	var robots: Array[OwnedTool] = game_state.automation.get_robots()
	var money: int = game_state.get_money()
	_money_label.text = "所持金: %d 円 / %s: %d 台 (上限 %d 台)" % [
		money, RobotRulesScript.ROBOT_NAME, robots.size(), RobotRulesScript.MAX_ROBOTS
	]
	_buy_button.text = "%sを買う (%d 円。今いる部屋から回る)" % [
		RobotRulesScript.ROBOT_NAME, RobotRulesScript.ROBOT_PRICE
	]
	_buy_button.disabled = (
		robots.size() >= RobotRulesScript.MAX_ROBOTS or money < RobotRulesScript.ROBOT_PRICE
	)
	if robots.is_empty():
		_selected_index = -1
	else:
		_selected_index = clampi(_selected_index if _selected_index >= 0 else 0, 0, robots.size() - 1)
	var room_names: Dictionary = {}
	var layout: MansionLayout = game_state.current_layout
	if layout != null:
		for room: MansionLayout.RoomDef in layout.rooms:
			room_names[room.room_id] = room.display_name
	_routes_on_refresh.clear()
	for robot: OwnedTool in robots:
		_routes_on_refresh.append(robot.robot_room_ids.duplicate())
	# 台の数か屋敷の部屋が変わった時だけボタンを作り直す。毛の本数やお金が変わるたび (掃除ロボットが 1 秒に 1 本取る
	# たび) に作り直すと、押している途中のボタンが消えて押した操作が失われるため、それ以外は文字と押せるかだけ変える
	if _robot_rows.get_child_count() != robots.size():
		_clear_children(_robot_rows)
		for robot_index: int in range(robots.size()):
			var select: Button = Button.new()
			select.name = "Robot%d" % robot_index
			select.toggle_mode = true
			select.alignment = HORIZONTAL_ALIGNMENT_LEFT
			select.pressed.connect(_on_robot_selected.bind(robot_index, game_state))
			_robot_rows.add_child(select)
	for robot_index: int in range(robots.size()):
		var select: Button = _robot_rows.get_child(robot_index)
		select.set_pressed_no_signal(robot_index == _selected_index)
		select.text = "%d 台目: %s" % [
			robot_index + 1, describe_route(robots[robot_index].robot_room_ids, room_names)
		]
	var rooms: Array[MansionLayout.RoomDef] = layout.rooms if layout != null else []
	var room_ids_now: Array[StringName] = []
	for room: MansionLayout.RoomDef in rooms:
		room_ids_now.append(room.room_id)
	if room_ids_now != _room_button_ids:
		_clear_children(_room_buttons)
		_room_button_ids = room_ids_now
		for room: MansionLayout.RoomDef in rooms:
			var add: Button = Button.new()
			add.name = "AddRoom_%s" % String(room.room_id)
			add.text = "+ %s" % room.display_name
			add.pressed.connect(_on_add_room.bind(room.room_id))
			_room_buttons.add_child(add)
	var selected_route: Array = (
		_routes_on_refresh[_selected_index] if _selected_index >= 0 else []
	)
	for room_id: StringName in _room_button_ids:
		get_add_room_button(room_id).disabled = (
			_selected_index < 0 or selected_route.has(room_id)
		)
	_remove_last_button.disabled = selected_route.is_empty()
	_clear_button.disabled = selected_route.is_empty()


## parent の子のノードをすべて外して解放する
static func _clear_children(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


## 回る順の表示 (部屋の名前を「→」でつないだもの。空なら止まっている)
static func describe_route(room_ids: Array[StringName], room_names: Dictionary) -> String:
	if room_ids.is_empty():
		return "止まっている (部屋を足すと回り出す)"
	var names: PackedStringArray = PackedStringArray()
	for room_id: StringName in room_ids:
		names.append(str(room_names.get(room_id, String(room_id))))
	return " → ".join(names) + " → (最初に戻る)"


## 組んでいる台の添字を返す (台が無ければ -1。検証用)
func get_selected_index() -> int:
	return _selected_index


## 掃除ロボットを買うボタンを返す (検証用)
func get_buy_button() -> Button:
	return _buy_button


## 部屋を回る順に足すボタンを返す (検証用。無い部屋は null)
func get_add_room_button(room_id: StringName) -> Button:
	return _room_buttons.get_node_or_null("AddRoom_%s" % String(room_id)) as Button


## 台を選ぶボタンを返す (検証用。無い台は null)
func get_robot_button(robot_index: int) -> Button:
	return _robot_rows.get_node_or_null("Robot%d" % robot_index) as Button


## 最後の部屋を外すボタンを返す (検証用)
func get_remove_last_button() -> Button:
	return _remove_last_button


## 回る順を空にするボタンを返す (検証用)
func get_clear_button() -> Button:
	return _clear_button


## 見出し・買うボタン・台の行・部屋のボタン・閉じるボタンを組み立てる
func _build() -> void:
	var background: StyleBoxFlat = StyleBoxFlat.new()
	# 角の丸み・余白・行間・字の大きさは道具を買う画面 (ToolShopPanel) と同じ値にそろえる。背景色だけ、道具を買う画面
	# (茶) と区別できる青みの濃い色にし、不透明度は同じ 0.96 にする
	background.bg_color = Color(0.1, 0.13, 0.16, 0.96)
	background.set_corner_radius_all(8)
	background.set_content_margin_all(20.0)
	add_theme_stylebox_override("panel", background)
	var layout: VBoxContainer = VBoxContainer.new()
	layout.name = "Layout"
	layout.add_theme_constant_override("separation", 6)
	add_child(layout)

	var title: Label = Label.new()
	title.name = "Title"
	title.text = "%sの回る順" % RobotRulesScript.ROBOT_NAME
	title.add_theme_font_size_override("font_size", 26)
	layout.add_child(title)

	_money_label = Label.new()
	_money_label.name = "Money"
	_money_label.add_theme_font_size_override("font_size", 17)
	layout.add_child(_money_label)

	var hint: Label = Label.new()
	hint.name = "Hint"
	hint.text = (
		"%sは回る順の部屋に %d 秒ずつ留まり、床とカーペットの毛を %d 秒に 1 本取って在庫に入れる"
		% [
			RobotRulesScript.ROBOT_NAME, roundi(RobotRulesScript.ROOM_SECONDS),
			roundi(RobotRulesScript.PICK_INTERVAL_SECONDS)
		]
	)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 14)
	layout.add_child(hint)

	_buy_button = Button.new()
	_buy_button.name = "BuyButton"
	_buy_button.pressed.connect(func() -> void: buy_requested.emit())
	layout.add_child(_buy_button)

	_robot_rows = VBoxContainer.new()
	_robot_rows.name = "Robots"
	layout.add_child(_robot_rows)

	var rooms_caption: Label = Label.new()
	rooms_caption.text = "選んだ台の回る順に部屋を足す (押した順に回る)"
	rooms_caption.add_theme_font_size_override("font_size", 14)
	layout.add_child(rooms_caption)

	_room_buttons = HFlowContainer.new()
	_room_buttons.name = "Rooms"
	layout.add_child(_room_buttons)

	var edit_row: HBoxContainer = HBoxContainer.new()
	layout.add_child(edit_row)
	_remove_last_button = Button.new()
	_remove_last_button.name = "RemoveLastButton"
	_remove_last_button.text = "最後の部屋を外す"
	_remove_last_button.pressed.connect(_on_remove_last)
	edit_row.add_child(_remove_last_button)
	_clear_button = Button.new()
	_clear_button.name = "ClearButton"
	_clear_button.text = "順を空にして止める"
	_clear_button.pressed.connect(_on_clear)
	edit_row.add_child(_clear_button)

	var close_button: Button = Button.new()
	close_button.name = "CloseButton"
	close_button.text = "閉じる (R)"
	close_button.pressed.connect(func() -> void: close_requested.emit())
	layout.add_child(close_button)


## 台を選んだ時に、その台の回る順を組めるように描き直す
func _on_robot_selected(robot_index: int, game_state: Node) -> void:
	_selected_index = robot_index
	refresh(game_state)


## 部屋のボタンを押した時に、選んでいる台の回る順の最後にその部屋を足す操作を出す
func _on_add_room(room_id: StringName) -> void:
	if _selected_index < 0:
		return
	var room_ids: Array[StringName] = []
	room_ids.assign(_routes_on_refresh[_selected_index])
	room_ids.append(room_id)
	route_change_requested.emit(_selected_index, room_ids)


## 選んでいる台の回る順の最後の部屋を外す操作を出す
func _on_remove_last() -> void:
	if _selected_index < 0:
		return
	var room_ids: Array[StringName] = []
	room_ids.assign(_routes_on_refresh[_selected_index])
	if room_ids.is_empty():
		return
	room_ids.pop_back()
	route_change_requested.emit(_selected_index, room_ids)


## 選んでいる台の回る順を空にする操作を出す
func _on_clear() -> void:
	if _selected_index < 0:
		return
	var room_ids: Array[StringName] = []
	route_change_requested.emit(_selected_index, room_ids)

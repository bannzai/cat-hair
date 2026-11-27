class_name RequestController
extends Node3D
## 住人の依頼の見た目と、歩いて起きる操作。毛の上に出てきた探し物を屋敷に置き、逃げた猫の毛の跡を床に並べる。
## プレイヤーが隠れている逃げた猫に近づくと抱え、持ち主の部屋に入ると取った探し物を返し、抱えた猫を届ける。
## 状態は GameState の依頼の状態 (RequestState) が持ち、このノードは描くだけにする。

## 知らせ (探し物が出てきた・返した等) を画面に出した時 (text は出した文言)
signal notice_posted(text: String)

## 依頼の計算 (探し物の種類・猫の隠れる所・毛の跡)
const RequestRulesScript := preload("res://scripts/requests/request_rules.gd")
## 依頼の状態の出来事の種類
const RequestStateScript := preload("res://scripts/state/request_state.gd")
## 探し物の状態の型 (Condition の定数)
const FoundItemProgressScript := preload("res://scripts/data/found_item_progress.gd")
## 道具の定義 (合う道具の名前)
const ToolCatalogScript := preload("res://scripts/tools/tool_catalog.gd")
## 猫の通り道の計算 (猫の名前と毛の色)
const CatRulesScript := preload("res://scripts/automation/cat_rules.gd")
## 部屋の判定 (今いる部屋)
const LookPrototypeRoomScript := preload("res://scripts/look/look_prototype_room.gd")
## 屋敷の文字のフォント
const FONT: Font = preload("res://assets/fonts/NotoSansJP[wght].ttf")
## 探し物の箱の大きさ (m)。毛の山の上で一目で分かり、家具の天面からはみ出さない大きさ
const ITEM_SIZE: Vector3 = Vector3(0.16, 0.08, 0.12)
## 探し物の名前の札の、物の上の高さ (m)。札が物に重ならず、物と一緒に視界に入る高さ
const ITEM_LABEL_LIFT_M: float = 0.22
## 毛の跡の毛の塊の半径 (m)。立った目線から床の毛と見分けられ、廊下の幅に 1 つ収まる大きさ
const TRAIL_CLUMP_RADIUS_M: float = 0.09
## 毛の跡の毛の塊の高さ (m)。床に平たく積もって見える高さ
const TRAIL_CLUMP_HEIGHT_M: float = 0.02
## 毛の跡を床から浮かせる高さ (m)。床の毛と重なってちらつかない高さ
const TRAIL_LIFT_M: float = 0.012
## 毛の跡の毛の色 (逃げる猫の毛の色。白い猫は床で見えるよう少し灰色にする)
const TRAIL_COLOR: Color = Color(0.9, 0.9, 0.88)
## 隠れている逃げた猫を抱えられる、プレイヤーの足元からの水平距離 (m)。手の届く距離 (HandController.REACH_M) より短い、
## しゃがんで手を伸ばす距離
const CARRY_RANGE_M: float = 1.5
## 知らせを出しておく秒数。毛を抜いた「+N 本」の知らせ (Main.PLUCK_POPUP_SECONDS) より長い文なので、読み切れる長さにする
const NOTICE_SECONDS: float = 4.0

## 住人の依頼の一覧の画面 (setup で作り、ui_root に足す)
var panel: RequestListPanel = null
## 参照中の GameState
var _game_state: Node = null
## 探し物 id -> 屋敷に置いた探し物のノード
var _item_nodes: Dictionary = {}
## 毛の跡の毛の塊の親
var _trail_root: Node3D = null
## 依頼の知らせを出す Label。毛を抜いた「+N 本」の知らせと別の所に出し、同じフレームの知らせで上書きされないようにする
var _notice_label: Label = null
## 知らせを消すまでの残りの秒
var _notice_remaining: float = 0.0


## GameState・画面のルート (一覧の画面の親) を受け取る
func setup(game_state: Node, ui_root: Control) -> void:
	_game_state = game_state
	panel = RequestListPanel.new()
	panel.name = "RequestListPanel"
	panel.visible = false
	# 1280x720 の画面で、探し物 5 行・スーツ 4 行・猫 1 行が折り返さずに収まる大きさ (CI の撮影で確かめた)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -440.0
	panel.offset_right = 440.0
	panel.offset_top = -300.0
	panel.offset_bottom = 300.0
	ui_root.add_child(panel)
	_notice_label = Label.new()
	_notice_label.name = "RequestNotice"
	_notice_label.visible = false
	# 文字の色・縁取りは毛を抜いた知らせ (Main の PluckPopup) とそろえ、文が長いので一段小さくする
	_notice_label.add_theme_font_size_override("font_size", 30)
	_notice_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55))
	_notice_label.add_theme_color_override("font_outline_color", Color(0.1, 0.08, 0.05))
	_notice_label.add_theme_constant_override("outline_size", 8)
	_notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# 画面の上の残り本数の段より下、照準と「+N 本」の知らせより上の帯に出す
	_notice_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_notice_label.offset_left = -560.0
	_notice_label.offset_right = 560.0
	_notice_label.offset_top = 150.0
	_notice_label.offset_bottom = 200.0
	_notice_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(_notice_label)
	if not _game_state.request_event.is_connected(_on_request_event):
		_game_state.request_event.connect(_on_request_event)


## ツリー離脱時にシグナル接続を外す
func _exit_tree() -> void:
	if _game_state != null and is_instance_valid(_game_state):
		if _game_state.request_event.is_connected(_on_request_event):
			_game_state.request_event.disconnect(_on_request_event)


## 屋敷を組み直した時に、探し物と毛の跡のノードを作り直す
func rebuild() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.free()
	_item_nodes.clear()
	_trail_root = Node3D.new()
	_trail_root.name = "RunawayTrail"
	add_child(_trail_root)
	var layout: MansionLayout = _game_state.current_layout if _game_state != null else null
	if layout == null:
		return
	for spot: MansionLayout.FoundItemSpotDef in layout.found_item_spots:
		var item: Node3D = _build_item(spot)
		add_child(item)
		_item_nodes[spot.found_item_id] = item
	var clump_mesh: SphereMesh = SphereMesh.new()
	clump_mesh.radius = TRAIL_CLUMP_RADIUS_M
	clump_mesh.height = TRAIL_CLUMP_HEIGHT_M
	var clump_material: StandardMaterial3D = StandardMaterial3D.new()
	clump_material.albedo_color = TRAIL_COLOR
	# 毛の塊は光を返さないので、つやを出さない
	clump_material.roughness = 1.0
	clump_mesh.material = clump_material
	for point: Vector3 in RequestRulesScript.trail_points(layout):
		var clump: MeshInstance3D = MeshInstance3D.new()
		clump.mesh = clump_mesh
		clump.position = point + Vector3.UP * TRAIL_LIFT_M
		_trail_root.add_child(clump)
	refresh()


## 探し物の見え方 (毛の上に出てきた物だけを置く) と毛の跡 (猫が隠れている間だけ) を状態に合わせ、開いている一覧を描き直す
func refresh() -> void:
	if _game_state == null:
		return
	for found_item_id: Variant in _item_nodes.keys():
		var item: FoundItemProgress = _game_state.requests.find_item(found_item_id)
		(_item_nodes[found_item_id] as Node3D).visible = (
			item != null and item.condition == FoundItemProgressScript.Condition.FOUND
		)
	if _trail_root != null:
		_trail_root.visible = _game_state.requests.runaway_status() == &"escaped"
	if panel != null and panel.visible:
		panel.refresh(_game_state)


## 出している知らせを、出してから NOTICE_SECONDS 秒たったら消す
func _process(delta: float) -> void:
	if _notice_remaining <= 0.0:
		return
	_notice_remaining -= delta
	if _notice_remaining <= 0.0 and _notice_label != null:
		_notice_label.visible = false


## 出している知らせの文言 (出していなければ空。検証用)
func get_notice_text() -> String:
	return _notice_label.text if _notice_label != null and _notice_label.visible else ""


## 依頼の一覧を開く
func open_panel() -> void:
	panel.refresh(_game_state)
	panel.visible = true


## 探し物のノードを返す (無い探し物は null。検証用)
func get_item_node(found_item_id: StringName) -> Node3D:
	return _item_nodes.get(found_item_id)


## 毛の跡の毛の塊の数と、見えているかを返す ({"count", "visible"}。検証用)
func get_trail_state() -> Dictionary:
	if _trail_root == null:
		return {"count": 0, "visible": false}
	return {"count": _trail_root.get_child_count(), "visible": _trail_root.visible}


## プレイヤーが足元 player_position にいる時の操作を行う: 隠れている逃げた猫に近ければ抱え、持ち主の部屋にいれば
## 抱えた猫を届け、その部屋の住人の取った探し物を返す。プレイ中に毎フレーム呼ぶ
func interact_at(player_position: Vector3) -> void:
	if _game_state == null or _game_state.current_layout == null:
		return
	var layout: MansionLayout = _game_state.current_layout
	var requests: RefCounted = _game_state.requests
	if requests.runaway_status() == &"escaped":
		if can_carry(player_position, RequestRulesScript.runaway_hiding_point(layout)):
			requests.carry_runaway_cat()
	var room: MansionLayout.RoomDef = LookPrototypeRoomScript.room_at(layout, player_position)
	if room == null:
		return
	requests.deliver_runaway_cat(room.room_id)
	for spot: MansionLayout.FoundItemSpotDef in layout.found_item_spots:
		if spot.room_id == room.room_id:
			requests.return_item(spot.found_item_id, room.room_id)


## 足元 player_position から、隠れている所 hiding まで抱えられる距離か (水平の距離が CARRY_RANGE_M 以内)
static func can_carry(player_position: Vector3, hiding: Vector3) -> bool:
	return (
		Vector2(player_position.x - hiding.x, player_position.z - hiding.z).length()
		<= CARRY_RANGE_M
	)


## 探し物 1 つの見た目 (種類の色の箱と名前の札) を作る
func _build_item(spot: MansionLayout.FoundItemSpotDef) -> Node3D:
	var kind: Dictionary = RequestRulesScript.kind_for_item_id(spot.found_item_id)
	var root: Node3D = Node3D.new()
	root.name = "FoundItem_%s" % String(spot.found_item_id)
	root.position = spot.position
	var box: BoxMesh = BoxMesh.new()
	box.size = ITEM_SIZE
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = kind["color"]
	# 機械は金属のつや、衣類は布のつやの無い見た目にして、毛の山の上で種類を見分けられるようにする
	material.metallic = 0.6 if kind["category"] == RequestRulesScript.CATEGORY_MACHINE else 0.0
	material.roughness = 0.35 if kind["category"] == RequestRulesScript.CATEGORY_MACHINE else 0.9
	box.material = material
	var body: MeshInstance3D = MeshInstance3D.new()
	body.name = "Body"
	body.mesh = box
	body.position = Vector3.UP * ITEM_SIZE.y * 0.5
	root.add_child(body)
	var label: Label3D = Label3D.new()
	label.name = "NameLabel"
	label.text = str(kind["name"])
	label.font = FONT
	# 文字の大きさ・縁取りは猫の名前の札 (AutomationController) とそろえ、表示の大きさ (pixel_size) は、
	# 毛に埋もれた小さな物を部屋の入口から見つけられるよう、猫の札 (0.0022) の倍ほどにする
	label.font_size = 40
	label.pixel_size = 0.004
	label.outline_size = 10
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = Vector3.UP * ITEM_LABEL_LIFT_M
	root.add_child(label)
	return root


## 依頼の出来事を受け取り、見え方を描き直して知らせの文言を出す
func _on_request_event(event: Dictionary) -> void:
	refresh()
	var text: String = notice_text(event)
	if text.is_empty():
		return
	if _notice_label != null:
		_notice_label.text = text
		_notice_label.visible = true
		_notice_remaining = NOTICE_SECONDS
	notice_posted.emit(text)


## 依頼の出来事 event (RequestState の request_event の辞書) の知らせの文言。出さない出来事は空
static func notice_text(event: Dictionary) -> String:
	match event.get("kind"):
		RequestStateScript.EVENT_REVEALED:
			var kind: Dictionary = RequestRulesScript.kind_for_item_id(event["found_item_id"])
			return "探し物が出てきた: %s (%sで丁寧に取る)" % [
				kind["name"], ToolCatalogScript.find_tool(kind["match_tool"]).get("name", "")
			]
		RequestStateScript.EVENT_TAKEN:
			return "%sを%s取った" % [
				RequestRulesScript.kind_for_item_id(event["found_item_id"])["name"],
				"きれいに" if event["condition"] == FoundItemProgressScript.Condition.CLEAN else "傷めて",
			]
		RequestStateScript.EVENT_RETURNED:
			return "%sを返した: 次の掃除代にお礼 +%d 円" % [
				RequestRulesScript.kind_for_item_id(event["found_item_id"])["name"], int(event["reward"])
			]
		RequestStateScript.EVENT_SUIT_CLEARED:
			return "黒いスーツの毛を取り切った: 次の掃除代に +%d 円" % int(event["reward"])
		RequestStateScript.EVENT_CAT_ESCAPED:
			return "%sが逃げた: 毛の跡をたどって探す" % _runaway_cat_name()
		RequestStateScript.EVENT_CAT_CARRIED:
			return "%sを抱えた: 持ち主の部屋に届ける" % _runaway_cat_name()
		RequestStateScript.EVENT_CAT_RETURNED:
			return "%sを届けた: 住人がご機嫌になった" % _runaway_cat_name()
	return ""


## 逃げる猫の名前
static func _runaway_cat_name() -> String:
	return str(CatRulesScript.CATS[RequestRulesScript.RUNAWAY_CAT_INDEX]["name"])

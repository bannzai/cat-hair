class_name AutomationController
extends Node3D
## 猫と掃除ロボットを屋敷に描き、屋敷で遊んでいる間に GameState の猫と掃除ロボットの時計を進める。
## 本数の正は GameState で、猫が落とした毛と掃除ロボットが取った毛は、その変化 (automation_advanced) と同じ本数だけ
## HairField の毛を足し引きする。猫と掃除ロボットの位置は GameState の時計から毎フレーム求める (このノードは状態を持たない)。

## 猫の通り道・毛を落とす量の計算
const CatRulesScript := preload("res://scripts/automation/cat_rules.gd")
## 掃除ロボットの回る順・毛を取る量の計算
const RobotRulesScript := preload("res://scripts/automation/robot_rules.gd")
## 決まった所を順に回る動きの時刻の計算
const RouteClockScript := preload("res://scripts/automation/route_clock.gd")
## 屋敷の毛の描画 (猫が落とした毛を足す)
const HairFieldScript := preload("res://scripts/hair_field.gd")
## 面ごとの毛の型 (毛の色の id)
const SurfaceHairScript := preload("res://scripts/data/surface_hair.gd")
## 猫の名札の字 (日本語の字形を持つ。出典は assets/CREDITS.md)
const FONT: Font = preload("res://assets/fonts/NotoSansJP[wght].ttf")
## 猫の毛の色ごとの体の色。白・黒は毛の色そのもの、三毛は白地 (茶と黒のぶちは別に付ける)
const CAT_BODY_COLORS: Dictionary = {
	SurfaceHairScript.COLOR_WHITE: Color(0.93, 0.92, 0.88),
	SurfaceHairScript.COLOR_BLACK: Color(0.09, 0.08, 0.08),
	SurfaceHairScript.COLOR_CALICO: Color(0.95, 0.93, 0.88),
}
## 三毛猫のぶちの色 (茶・黒)
const CALICO_PATCH_COLORS: Array[Color] = [Color(0.82, 0.47, 0.18), Color(0.12, 0.1, 0.09)]
## 猫が落とした毛を、立ち止まった所から面に沿って散らす半径 (m)。猫の体の大きさほどの範囲
const DROP_SPREAD_M: float = 0.35
## 猫の体の長さ (m。家猫の頭を除いた胴の標準 45 cm 前後)
const CAT_BODY_LENGTH_M: float = 0.42
## 猫の胴の半径 (m。家猫の胴回りの標準 60 cm 前後を円にした半径より少し細い、遠目で猫の形に見える太さ)
const CAT_BODY_RADIUS_M: float = 0.1
## 猫の脚の長さ (m。家猫の肩までの高さの標準 25 cm 前後から胴の太さを引いた長さ)
const CAT_LEG_LENGTH_M: float = 0.12
## 昼寝している猫の胴を下げる高さ (m。脚をたたんで伏せた形)
const NAP_LOWER_M: float = CAT_LEG_LENGTH_M * 0.85
## 掃除ロボットの半径 (m。見た目の試作の置き物と同じ大きさ)
const ROBOT_RADIUS_M: float = LookPrototypeRoom.ROBOT_RADIUS_M
## 掃除ロボットの高さ (m。見た目の試作の置き物と同じ大きさ)
const ROBOT_HEIGHT_M: float = LookPrototypeRoom.ROBOT_HEIGHT_M
## 猫の向きを変える最小の移動 (m)。立ち止まっている間に向きがちらつかないため
const TURN_MIN_MOVE_M: float = 0.002

## 屋敷で遊んでいる間に猫と掃除ロボットの時計を進めるか (入力統合テストと撮影は本数を検証で決めた値に保つため false にする)
var auto_advance: bool = true
## タイトルを抜けて屋敷を歩いている間だけ時計を進める (main が設定する)
var playing: bool = false

## 本数と時計の正を持つ GameState
var _game_state: Node = null
## 毛を持つ屋敷
var _world: MansionWorld = null
## 猫のノードの親
var _cats_root: Node3D = null
## 掃除ロボットのノードの親 (買った順に Robot0, Robot1, …)
var _robots_root: Node3D = null
## cat_id -> 猫のノード
var _cat_nodes: Dictionary = {}
## 面の id -> HairField の表面の添字 (layout.surfaces の並び)
var _surface_index_by_id: Dictionary = {}
## 猫が落とした毛の置き方の乱数
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


## GameState と屋敷を受け取り、猫と掃除ロボットの時計の変化を受け取る
func setup(game_state: Node, world: MansionWorld) -> void:
	_game_state = game_state
	_world = world
	if not _game_state.automation_advanced.is_connected(_on_automation_advanced):
		_game_state.automation_advanced.connect(_on_automation_advanced)


## ツリー離脱時にシグナル接続を外す
func _exit_tree() -> void:
	if (
		_game_state != null
		and is_instance_valid(_game_state)
		and _game_state.automation_advanced.is_connected(_on_automation_advanced)
	):
		_game_state.automation_advanced.disconnect(_on_automation_advanced)


## 屋敷を作り直した後に、今の屋敷の猫と掃除ロボットを置き直す
func rebuild() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.free()
	_cat_nodes.clear()
	_surface_index_by_id.clear()
	# 猫が落とした毛の置き方を、撮影と録画で毎回同じにする固定の種 (値に意味は無く、作った日付)
	_rng.seed = 20261127
	_cats_root = Node3D.new()
	_cats_root.name = "Cats"
	add_child(_cats_root)
	_robots_root = Node3D.new()
	_robots_root.name = "Robots"
	add_child(_robots_root)
	if _game_state == null or _game_state.current_layout == null:
		return
	var layout: MansionLayout = _game_state.current_layout
	for surface_index: int in range(layout.surfaces.size()):
		_surface_index_by_id[layout.surfaces[surface_index].surface_id] = surface_index
	for route: Dictionary in _game_state.automation.get_cat_routes():
		var cat: Node3D = _build_cat(route)
		_cats_root.add_child(cat)
		_cat_nodes[route["cat_id"]] = cat
	update_positions()


## 屋敷で遊んでいる間は時計を進め、猫と掃除ロボットを今の位置へ動かす
func _process(delta: float) -> void:
	if playing and auto_advance and _game_state != null:
		_game_state.automation.advance(delta)
	update_positions()


## 猫と掃除ロボットを GameState の時計の位置へ動かす (買った掃除ロボットの台数に合わせてノードも足す)
func update_positions() -> void:
	if _game_state == null or _game_state.current_layout == null or _cats_root == null:
		return
	var now: float = _game_state.automation.get_seconds()
	for route: Dictionary in _game_state.automation.get_cat_routes():
		var cat: Node3D = _cat_nodes.get(route["cat_id"])
		if cat == null:
			continue
		var position_now: Vector3 = RouteClockScript.position_at(route, now)
		var moved: Vector3 = position_now - cat.position
		moved.y = 0.0
		cat.position = position_now
		if moved.length() > TURN_MIN_MOVE_M:
			cat.rotation.y = atan2(-moved.x, -moved.z)
		var stop_index: int = RouteClockScript.stop_index_at(route, now)
		var napping: bool = (
			stop_index >= 0
			and bool(route["stops"][stop_index]["nap"])
			and RouteClockScript.seconds_in_stop(route, now) >= RouteClockScript.MOVE_SECONDS
		)
		(cat.get_node("Body") as Node3D).position.y = -NAP_LOWER_M if napping else 0.0
		(cat.get_node("Legs") as Node3D).visible = not napping
	var robots: Array[OwnedTool] = _game_state.automation.get_robots()
	while _robots_root.get_child_count() < robots.size():
		_robots_root.add_child(_build_robot(_robots_root.get_child_count()))
	var room_sizes: Dictionary = {}
	for room: MansionLayout.RoomDef in _game_state.current_layout.rooms:
		room_sizes[room.room_id] = room.size
	for robot_index: int in range(robots.size()):
		var route: Dictionary = RobotRulesScript.build_route(
			_game_state.current_layout, robots[robot_index].robot_room_ids
		)
		var robot_node: Node3D = _robots_root.get_child(robot_index)
		robot_node.visible = not route["stops"].is_empty()
		robot_node.position = RobotRulesScript.position_at(
			route, RobotRulesScript.robot_time(robot_index, now), room_sizes
		)


## cat_id -> 猫の体の中心のワールド座標 (ブラシで狙う猫を決める)
func cat_centers() -> Dictionary:
	var centers: Dictionary = {}
	for cat_id: Variant in _cat_nodes.keys():
		var cat: Node3D = _cat_nodes[cat_id]
		centers[cat_id] = cat.global_position + Vector3.UP * CatRulesScript.BODY_CENTER_HEIGHT_M
	return centers


## 猫のノードを返す (いない猫は null)
func get_cat_node(cat_id: StringName) -> Node3D:
	return _cat_nodes.get(cat_id)


## 置いた掃除ロボットのノードの数
func get_robot_node_count() -> int:
	return _robots_root.get_child_count() if _robots_root != null else 0


## robot_index 台目の掃除ロボットのノード (無ければ null)
func get_robot_node(robot_index: int) -> Node3D:
	if _robots_root == null or robot_index < 0 or robot_index >= _robots_root.get_child_count():
		return null
	return _robots_root.get_child(robot_index)


## GameState の本数の変化と同じ本数だけ、猫が落とした毛を立ち止まった所の周りに足し、
## 掃除ロボットが取った毛をロボットに近い順に消す
func _on_automation_advanced(changes: Dictionary) -> void:
	if _world == null or _world.get_hair_field() == null:
		return
	var hair_field: Node3D = _world.get_hair_field()
	# 時計を進めた後の位置で、掃除ロボットに近い毛を消す
	update_positions()
	var routes_by_cat: Dictionary = {}
	for route: Dictionary in _game_state.automation.get_cat_routes():
		routes_by_cat[route["cat_id"]] = route
	for drop: Dictionary in changes["drops"]:
		var surface_index: int = int(_surface_index_by_id.get(drop["surface_id"], -1))
		var stop: Dictionary = CatRulesScript.stop_on_surface(
			routes_by_cat.get(drop["cat_id"], {"stops": []}), drop["surface_id"]
		)
		if surface_index < 0 or stop.is_empty():
			continue
		var group: int = SurfaceHairScript.STANDARD_COLORS.find(drop["color"])
		for _i: int in range(int(drop["count"])):
			HairFieldScript.add_hair(
				hair_field, surface_index, stop["point"], DROP_SPREAD_M, group, _rng
			)
	for pick: Dictionary in changes["picks"]:
		var surface_index: int = int(_surface_index_by_id.get(pick["surface_id"], -1))
		var robot_node: Node3D = get_robot_node(int(pick["robot_index"]))
		if surface_index < 0:
			continue
		var left: int = int(pick["count"])
		for hair_id: int in hair_field.find_hairs_near(
			surface_index,
			robot_node.position if robot_node != null else Vector3.ZERO,
			INF,
			hair_field.get_surface_remaining_count(surface_index),
		):
			if left <= 0:
				break
			if _world.get_hair_color_id(hair_id) == pick["color"]:
				hair_field.remove_hair(hair_id)
				left -= 1


## 猫 1 匹の形 (胴・頭・耳・尾・脚と、三毛猫のぶち、頭の上の名札) を作る。足元が原点で、-Z が顔の向き
func _build_cat(route: Dictionary) -> Node3D:
	var cat: Node3D = Node3D.new()
	cat.name = "Cat_%s" % String(route["cat_id"])
	var body_color: Color = CAT_BODY_COLORS.get(route["color"], Color.WHITE)
	var body: Node3D = Node3D.new()
	body.name = "Body"
	cat.add_child(body)
	var torso_height: float = CAT_LEG_LENGTH_M + CAT_BODY_RADIUS_M
	var torso: CapsuleMesh = CapsuleMesh.new()
	torso.radius = CAT_BODY_RADIUS_M
	torso.height = CAT_BODY_LENGTH_M
	_add_part(body, torso, Vector3(0.0, torso_height, 0.0), Vector3(-90.0, 0.0, 0.0), body_color)
	# 頭・耳・尾・ぶち・脚の寸法は、胴 (CAT_BODY_*) に対する家猫の見た目の比率で決め、撮影の目視で猫に見えることを確かめた
	var head: SphereMesh = SphereMesh.new()
	head.radius = 0.085
	head.height = 0.16
	var head_center: Vector3 = Vector3(0.0, torso_height + 0.08, -CAT_BODY_LENGTH_M * 0.5)
	_add_part(body, head, head_center, Vector3.ZERO, body_color)
	for side: float in [-1.0, 1.0]:
		var ear: CylinderMesh = CylinderMesh.new()
		ear.top_radius = 0.0
		ear.bottom_radius = 0.032
		ear.height = 0.06
		_add_part(
			body, ear, head_center + Vector3(side * 0.045, 0.075, 0.0), Vector3(0.0, 0.0, -side * 15.0),
			body_color
		)
	var tail: CapsuleMesh = CapsuleMesh.new()
	tail.radius = 0.022
	tail.height = 0.3
	_add_part(
		body, tail, Vector3(0.0, torso_height + 0.1, CAT_BODY_LENGTH_M * 0.5 + 0.05),
		Vector3(-35.0, 0.0, 0.0), body_color
	)
	if route["color"] == SurfaceHairScript.COLOR_CALICO:
		var patch_spots: Array[Vector3] = [
			Vector3(0.05, torso_height + 0.06, 0.05), Vector3(-0.05, torso_height + 0.05, -0.08)
		]
		for patch_index: int in range(patch_spots.size()):
			var patch: SphereMesh = SphereMesh.new()
			patch.radius = 0.07
			patch.height = 0.1
			_add_part(body, patch, patch_spots[patch_index], Vector3.ZERO, CALICO_PATCH_COLORS[patch_index])
	var legs: Node3D = Node3D.new()
	legs.name = "Legs"
	cat.add_child(legs)
	for leg_spot: Vector2 in [
		Vector2(-0.05, -0.13), Vector2(0.05, -0.13), Vector2(-0.05, 0.13), Vector2(0.05, 0.13)
	]:
		var leg: CylinderMesh = CylinderMesh.new()
		leg.top_radius = 0.02
		leg.bottom_radius = 0.018
		leg.height = CAT_LEG_LENGTH_M
		_add_part(
			legs, leg, Vector3(leg_spot.x, CAT_LEG_LENGTH_M * 0.5, leg_spot.y), Vector3.ZERO, body_color
		)
	var name_label: Label3D = Label3D.new()
	name_label.name = "NameTag"
	name_label.text = str(route["name"])
	name_label.font = FONT
	# 名札の字の大きさと縁取りは、撮影 (1280x720) で 1.5 m ほど離れて読め、猫の体より大きく見えない値
	name_label.font_size = 40
	name_label.outline_size = 10
	name_label.pixel_size = 0.0022
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.position = Vector3(0.0, torso_height + 0.32, 0.0)
	body.add_child(name_label)
	return cat


## robot_index 台目の掃除ロボットの形 (円盤の本体・上蓋・前の緑の灯・番号の札) を作る。床に置く底が原点
func _build_robot(robot_index: int) -> Node3D:
	var robot: Node3D = Node3D.new()
	robot.name = "Robot%d" % robot_index
	var shell: CylinderMesh = CylinderMesh.new()
	shell.top_radius = ROBOT_RADIUS_M
	shell.bottom_radius = ROBOT_RADIUS_M
	shell.height = ROBOT_HEIGHT_M * 0.8
	# 配色は見た目の試作の置き物と同じ (本体は艶を抑えた濃い灰色、上蓋は明るい灰色)。前の小さな緑の灯で動いていると分かるようにする
	_add_part(
		robot, shell, Vector3(0.0, ROBOT_HEIGHT_M * 0.4, 0.0), Vector3.ZERO, Color(0.15, 0.15, 0.16)
	)
	var lid: CylinderMesh = CylinderMesh.new()
	lid.top_radius = ROBOT_RADIUS_M * 0.88
	lid.bottom_radius = ROBOT_RADIUS_M * 0.88
	lid.height = ROBOT_HEIGHT_M * 0.2
	_add_part(
		robot, lid, Vector3(0.0, ROBOT_HEIGHT_M * 0.9, 0.0), Vector3.ZERO, Color(0.36, 0.37, 0.38)
	)
	# 灯は本体の 1 割ほどの大きさで、上から見て前の向きが分かる位置に置く
	var lamp: SphereMesh = SphereMesh.new()
	lamp.radius = 0.02
	lamp.height = 0.03
	_add_part(
		robot, lamp, Vector3(0.0, ROBOT_HEIGHT_M * 1.05, -ROBOT_RADIUS_M * 0.5), Vector3.ZERO,
		Color(0.3, 0.9, 0.5)
	)
	var tag: Label3D = Label3D.new()
	tag.name = "NumberTag"
	tag.text = "%d" % (robot_index + 1)
	tag.font = FONT
	# 番号の札は猫の名札と同じ大きさの字で、掃除ロボットの小ささに合わせて少し小さく描く
	tag.font_size = 40
	tag.outline_size = 10
	tag.pixel_size = 0.002
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.position = Vector3(0.0, ROBOT_HEIGHT_M + 0.12, 0.0)
	robot.add_child(tag)
	return robot


## 形を 1 つ足す (衝突体は付けない。歩く邪魔をしないため)。rotation_deg は度
func _add_part(
	parent_node: Node3D, mesh: Mesh, part_position: Vector3, rotation_deg: Vector3, color: Color
) -> void:
	var part: MeshInstance3D = MeshInstance3D.new()
	part.mesh = mesh
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	# 毛並みと樹脂の艶の無さに合わせた粗さ
	material.roughness = 0.85
	part.material_override = material
	part.position = part_position
	part.rotation_degrees = rotation_deg
	parent_node.add_child(part)

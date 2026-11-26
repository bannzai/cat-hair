class_name LookPrototypeRoom
extends Node3D
## 見た目の試作 (issue #19) を、屋敷の最初の部屋 (プレイヤーが入る部屋) にだけ重ねるノード。
## 写実寄りの材質・窓から差す光と影を最初の部屋に付け、光・影・色の環境はその部屋の中にいる間だけ切り替える。
## 毛と画面の手は MansionWorld と手で毛を取る操作 (#9) が描く物をそのまま使い、ここでは描かない。
## ほかの部屋の見た目は変えない。MansionWorld の子は作り直しのたびに解放されるため、自分の物は自分の子に置き、
## MansionWorld のノードには材質と影の設定だけを上書きする。

## 屋敷の 3D ノード (壁の厚みの単一の正)
const MansionWorldScript := preload("res://scripts/mansion/mansion_world.gd")

## 見た目を切り替える部屋の番号。0 はプレイヤーが最初に立つ部屋 (MansionBuilder の初期位置) で、
## 起動してすぐ試作の見た目を見られるため
const TARGET_ROOM_INDEX: int = 0
## 自動化の構図で掃除ロボットが毛を取った帯の毛を消す高さの上限 (m)。床 (0.01) とカーペット (0.04) の毛だけを消し、
## 家具の上の毛を残す高さ
const ROBOT_CLEAR_MAX_Y_M: float = 0.1
## 掃除ロボットの半径 (m)。家庭用の円盤型の掃除ロボットの標準 (直径 34 cm)
const ROBOT_RADIUS_M: float = 0.17
## 掃除ロボットの高さ (m)。家具の下に入れる家庭用の標準 (9 cm 前後)
const ROBOT_HEIGHT_M: float = 0.085
## 掃除ロボットが毛を取りながら走った帯 (部屋の幅に対する比率)。z_ratio は帯の Z 位置、end_x_ratio はロボットが今いる X 位置。
## 一人称の初期位置 (部屋の中心から +Z へ 0.36 の比率。MansionBuilder.SPAWN_BACK_OFFSET_RATIO) から少し見下ろした時に、
## 3 台が手前から奥へ重ならずに画面に入る Z と、台ごとに違う進み具合に見える X を選んだ
const ROBOT_LANES: Array[Dictionary] = [
	{"z_ratio": -0.20, "end_x_ratio": -0.05},
	{"z_ratio": 0.0, "end_x_ratio": 0.17},
	{"z_ratio": 0.10, "end_x_ratio": -0.12},
]
## 掃除ロボットが走り始めた壁からの距離 (m)。充電台の前から走り出した見た目にする
const ROBOT_LANE_START_MARGIN_M: float = 0.45
## 窓の幅と高さ (m)。洋館の縦長の窓の標準寸法
const WINDOW_SIZE_M: Vector2 = Vector2(1.5, 1.6)
## 窓の中心の床からの高さ (m)。窓の下端が床から 0.8 m になる高さ
const WINDOW_CENTER_HEIGHT_M: float = 1.6
## 窓の外の昼の光の色。曇りの日の昼の空のやや青い白
const DAYLIGHT_COLOR: Color = Color(0.86, 0.92, 1.0)
## 窓から差す光の強さ。部屋の天井の灯り (MansionWorld.ROOM_LIGHT_ENERGY) より強くし、
## 窓の側から影が落ちる向きを主にする値
const DAYLIGHT_ENERGY: float = 7.0
## 窓から差す光の到達距離 (部屋の幅に対する倍率)。反対の壁まで届く倍率
const DAYLIGHT_RANGE_RATIO: float = 1.6
## 窓から差す光の広がり (度)。窓 1 枚から床の半分を照らす角度
const DAYLIGHT_SPOT_ANGLE_DEG: float = 55.0
## 窓から差す光を下へ傾ける角度 (rad)。昼過ぎの日差しが床に斜めに落ちる角度 (約 35 度)
const DAYLIGHT_TILT_RAD: float = 0.6
## 試作の部屋の環境光の強さ。既定 (main.tscn の WorldEnvironment) より下げ、窓と灯りの影が見える値 (CI の撮影で影が見えることを目視した)
const PROTOTYPE_AMBIENT_ENERGY: float = 0.45
## 試作の部屋の露出。環境光を下げた分を戻し、暗くなりすぎないための値
const PROTOTYPE_EXPOSURE: float = 1.25
## 試作の部屋の家具の陰の濃さ (SSAO の強さ)。家具の足元と壁の隅に陰が付く値
const PROTOTYPE_SSAO_INTENSITY: float = 1.6
## 生成するテクスチャ (木目・壁紙・ノイズ) の 1 辺の画素数。木目と壁紙はノイズの画像を同じ画素の位置で読むため
## 全部同じ大きさにする。128 は床の 1 枚の板 (32 画素) が 1280x720 で潰れない最小の解像度
const GENERATED_TEXTURE_SIZE: int = 128
## 1 枚の板の幅 (画素)。テクスチャ 1 枚に 4 枚の板を並べる
const WOOD_PLANK_PX: int = 32
## 床のテクスチャが 1 回繰り返す長さ (m)。1 枚の板の幅を 15 cm (洋館の床板の標準) にする長さ
const FLOOR_TEXTURE_REPEAT_M: float = 0.6
## 布・ニット・カーペットのテクスチャが 1 回繰り返す長さ (m)。毛足の凹凸が 1 cm 前後に見える長さ
const FABRIC_TEXTURE_REPEAT_M: float = 0.25
## 壁紙のテクスチャが 1 回繰り返す長さ (m)。縦の縞が 8 cm 間隔に見える長さ
const WALLPAPER_TEXTURE_REPEAT_M: float = 0.5
## 生成するテクスチャの画素の形式。RGB8 は Vulkan (CI の lavapipe) が受け付けず、読み込みのたびに RGBA8 へ変換して
## WARNING を出す (PR #30 の CI の --verbose の実行で観測) ため、最初から RGBA8 で作る
const TEXTURE_IMAGE_FORMAT: Image.Format = Image.FORMAT_RGBA8

## MansionWorld が付けるノード名 (衝突体付きは StaticBody3D の名前) から、試作の材質の種類への対応
const NODE_MATERIAL_KINDS: Dictionary = {
	"Floor": &"floor",
	"Ceiling": &"ceiling",
	"Panel": &"wall",
	"LeftPanel": &"wall",
	"RightPanel": &"wall",
	"HeaderPanel": &"wall",
	"Baseboard": &"dark_wood",
	"FrameLeft": &"dark_wood",
	"FrameRight": &"dark_wood",
	"FrameTop": &"dark_wood",
	"CarpetBody": &"carpet",
	"CarpetTrim": &"carpet_trim",
	"Seat": &"sofa",
	"Backrest": &"sofa",
	"ArmLeft": &"sofa",
	"ArmRight": &"sofa",
	"TableTop": &"furniture",
	"Leg": &"furniture",
	"Cabinet": &"furniture",
	"TopTrim": &"dark_wood",
	"ChairSeat": &"furniture",
	"ChairBack": &"furniture",
	"KnitThrow": &"knit",
	"SuitJacket": &"suit",
	"SuitShoulders": &"suit",
	"Base": &"metal",
	"Pole": &"metal",
}

## 見た目を切り替えている部屋 (無い時は null)
var _room: MansionLayout.RoomDef = null
## 部屋の中にいるかを見るプレイヤー
var _player: Node3D = null
## 環境 (光・影・色) を差し替える WorldEnvironment
var _world_environment: WorldEnvironment = null
## main.tscn が持つ既定の環境 (試作の部屋の外で使う)
var _base_environment: Environment = null
## 試作の部屋の中で使う環境
var _prototype_environment: Environment = null
## 試作の部屋の中で試作の見た目を出しているか
var _prototype_active: bool = false
## タイトルを抜けて屋敷を歩いているか (タイトルの画面と起動の録画の明るさを変えないため、歩いている間だけ試作を出す)
var _playing: bool = false
## 窓・光・掃除ロボットの親 (作り直しのたびに入れ替える)
var _content_root: Node3D = null
## 掃除ロボットと充電台の親
var _robots_root: Node3D = null
## 材質の種類 (NODE_MATERIAL_KINDS の値) から試作の材質への対応 (テクスチャの生成は 1 回だけにする)
var _materials: Dictionary = {}


## 部屋の中にいるかに合わせて、環境を切り替える
func _process(_delta: float) -> void:
	_refresh_active()


## 部屋の中にいるかを見るプレイヤーと、差し替える環境を受け取る。2 回呼んでも試作の環境は作り直さない
func setup(player: FirstPersonPlayer, world_environment: WorldEnvironment) -> void:
	_player = player
	_world_environment = world_environment
	# 試作の見た目を出している間に呼ばれると、今の環境は試作の環境のため、既定の環境として取り込まない
	if _prototype_environment == null or world_environment.environment != _prototype_environment:
		_base_environment = world_environment.environment
		_prototype_environment = build_prototype_environment(_base_environment)
	_refresh_active()


## タイトルを抜けて屋敷を歩いているか (main.gd が画面の切り替えで呼ぶ) を受け取り、試作の見た目の表示を合わせる
func set_playing(playing: bool) -> void:
	_playing = playing
	_refresh_active()


## レイアウトの最初の部屋に試作の見た目を重ねる。MansionWorld.rebuild の後に毎回呼ぶ (前回の物は消してから作る)。
## layout が null か部屋が無い時は何も重ねない
func apply(layout: MansionLayout, world: MansionWorld) -> void:
	_clear_content()
	_room = null
	if layout == null or layout.rooms.size() <= TARGET_ROOM_INDEX:
		_refresh_active()
		return
	_room = layout.rooms[TARGET_ROOM_INDEX]
	_content_root = Node3D.new()
	_content_root.name = "PrototypeContent"
	add_child(_content_root)

	_ensure_materials()
	_override_room_materials(layout, world)
	_add_window_and_daylight()
	_enable_room_light_shadow(world)
	_refresh_active()


## 掃除ロボットが部屋を回っている構図にする (掃除ロボットはまだ無いため、形だけの置き物と、走った帯の毛を消した絵)。
## hair_field (MansionWorld の毛) から帯の床とカーペットの毛を消し、消した本数を返す。消した毛は保存データの本数に
## 数えないため、撮影 (scripts/dev/screenshot.gd) の最後の絵にだけ使う。apply の前に呼んだ時は 0
func show_automation_props(hair_field: Node3D) -> int:
	if _room == null or _content_root == null:
		return 0
	if _robots_root != null:
		_content_root.remove_child(_robots_root)
		_robots_root.free()
	_robots_root = Node3D.new()
	_robots_root.name = "Robots"
	_content_root.add_child(_robots_root)

	var lane_start_x: float = _room.center.x - _room.size.x * 0.5 + ROBOT_LANE_START_MARGIN_M
	var removed: int = 0
	for lane_index: int in range(ROBOT_LANES.size()):
		var lane: Dictionary = ROBOT_LANES[lane_index]
		var lane_z: float = _room.center.z + float(lane["z_ratio"]) * _room.size.z
		var robot_x: float = _room.center.x + float(lane["end_x_ratio"]) * _room.size.x
		_add_robot(_robots_root, "Robot%d" % lane_index, Vector3(robot_x, 0.0, lane_z))
		removed += _remove_hairs_in_lane(hair_field, lane_start_x, robot_x, lane_z)
	_add_dock(_robots_root)
	return removed


## 見た目を切り替えている部屋の id (無い時は空)
func get_target_room_id() -> StringName:
	return _room.room_id if _room != null else &""


## 窓のノード (窓を付けなかった時は null)
func get_window_node() -> Node3D:
	return _content_root.get_node_or_null("Window") as Node3D if _content_root != null else null


## 窓から差す光 (窓を付けなかった時は null)
func get_daylight() -> SpotLight3D:
	return _content_root.get_node_or_null("Daylight") as SpotLight3D if _content_root != null else null


## 置いた掃除ロボットの台数
func get_robot_count() -> int:
	if _robots_root == null:
		return 0
	var count: int = 0
	for child: Node in _robots_root.get_children():
		if String(child.name).begins_with("Robot"):
			count += 1
	return count


## 試作の部屋の中で試作の見た目を出しているか
func is_prototype_active() -> bool:
	return _prototype_active


## 試作の材質の種類 (NODE_MATERIAL_KINDS の値) に対応する材質を返す。知らない種類は null
func get_material_for_kind(kind: StringName) -> StandardMaterial3D:
	_ensure_materials()
	return _materials.get(kind, null)


## 位置が部屋の床の範囲 (壁の内側。高さは問わない) の中か
static func is_inside_room(room: MansionLayout.RoomDef, world_position: Vector3) -> bool:
	return (
		absf(world_position.x - room.center.x) <= room.size.x * 0.5
		and absf(world_position.z - room.center.z) <= room.size.z * 0.5
	)


## 窓を付ける壁 (ドアの無い壁を西・南・東・北の順に探す)。全部の壁にドアがある時は空
static func window_wall_side(room: MansionLayout.RoomDef) -> StringName:
	if not room.open_west:
		return &"west"
	if not room.open_south:
		return &"south"
	if not room.open_east:
		return &"east"
	if not room.open_north:
		return &"north"
	return &""


## 既定の環境を写して、試作の部屋の環境 (ACES の色調・家具の陰・抑えた環境光) を作る。base が null の時は新しく作る
static func build_prototype_environment(base: Environment) -> Environment:
	var environment: Environment = (
		base.duplicate() as Environment if base != null else Environment.new()
	)
	environment.ambient_light_energy = PROTOTYPE_AMBIENT_ENERGY
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = PROTOTYPE_EXPOSURE
	environment.ssao_enabled = true
	environment.ssao_intensity = PROTOTYPE_SSAO_INTENSITY
	return environment


## 歩いている間にプレイヤーが試作の部屋の中にいる時だけ、試作の環境を出す
func _refresh_active() -> void:
	var active: bool = (
		_playing
		and _room != null
		and _player != null
		and is_instance_valid(_player)
		and _player.is_inside_tree()
		and is_inside_room(_room, _player.global_position)
	)
	_prototype_active = active
	var wanted_environment: Environment = _prototype_environment if active else _base_environment
	# 毎フレーム呼ばれるため、変わった時だけ差し替える
	if _world_environment != null and _world_environment.environment != wanted_environment:
		_world_environment.environment = wanted_environment


## 前回作った窓・光・掃除ロボットを解放する
func _clear_content() -> void:
	if _content_root != null:
		remove_child(_content_root)
		_content_root.free()
	_content_root = null
	_robots_root = null


## 試作の部屋の床・壁・天井と、部屋に置いた物のメッシュに試作の材質を上書きする
func _override_room_materials(layout: MansionLayout, world: MansionWorld) -> void:
	if world == null:
		return
	var room_node: Node = world.get_node_or_null("RoomsRoot/%s" % String(_room.room_id))
	if room_node != null:
		_override_meshes_under(room_node)
	var objects_root: Node = world.get_node_or_null("ObjectsRoot")
	if objects_root == null:
		return
	for obj: MansionLayout.ObjectDef in layout.objects:
		if obj.room_id != _room.room_id:
			continue
		var object_node: Node = objects_root.get_node_or_null(String(obj.object_id))
		if object_node != null:
			_override_meshes_under(object_node)


## node の下の MeshInstance3D のうち、NODE_MATERIAL_KINDS にある名前のものに試作の材質を付ける
func _override_meshes_under(node: Node) -> void:
	for child: Node in node.get_children():
		if child is MeshInstance3D:
			var mesh_node_name: String = String(
				child.get_parent().name if child.get_parent() is StaticBody3D else child.name
			)
			if NODE_MATERIAL_KINDS.has(mesh_node_name):
				(child as MeshInstance3D).material_override = _materials[
					NODE_MATERIAL_KINDS[mesh_node_name]
				]
		_override_meshes_under(child)


## ドアの無い壁に、外の光で明るい窓と、窓から部屋へ差す影付きの光を置く
func _add_window_and_daylight() -> void:
	var side: StringName = window_wall_side(_room)
	if side.is_empty():
		return
	# 窓から部屋の内側へ向かう向きと、壁の内側の面の位置
	var inward: Vector3 = {
		&"west": Vector3.RIGHT,
		&"east": Vector3.LEFT,
		&"south": Vector3.FORWARD,
		&"north": Vector3.BACK,
	}[side]
	var wall_face: Vector3 = (
		_room.center
		- inward * (
			(_room.size.x if side == &"west" or side == &"east" else _room.size.z) * 0.5
			- MansionWorldScript.WALL_THICKNESS_M
		)
		+ Vector3(0.0, WINDOW_CENTER_HEIGHT_M, 0.0)
	)
	var window_root: Node3D = Node3D.new()
	window_root.name = "Window"
	_place_on_wall(window_root, wall_face, inward)
	_build_window(window_root)

	var daylight: SpotLight3D = SpotLight3D.new()
	daylight.name = "Daylight"
	daylight.light_color = DAYLIGHT_COLOR
	daylight.light_energy = DAYLIGHT_ENERGY
	daylight.spot_range = maxf(_room.size.x, _room.size.z) * DAYLIGHT_RANGE_RATIO
	daylight.spot_angle = DAYLIGHT_SPOT_ANGLE_DEG
	daylight.shadow_enabled = true
	# 窓の面より 5 cm 内側から、部屋の内側へ向けて下へ傾ける (SpotLight3D は -Z を照らす)
	daylight.transform = Transform3D(
		Basis.looking_at(inward * cos(DAYLIGHT_TILT_RAD) + Vector3.DOWN * sin(DAYLIGHT_TILT_RAD)),
		wall_face + inward * 0.05,
	)
	_content_root.add_child(daylight)


## node を壁の内側の面の位置に置き、ローカルの -Z が部屋の内側を向くよう回す
func _place_on_wall(node: Node3D, wall_face: Vector3, inward: Vector3) -> void:
	node.transform = Transform3D(Basis.looking_at(inward), wall_face)
	_content_root.add_child(node)


## 窓ガラス (外の光で光る面) と木の窓枠・桟をローカルの XY 面に組み立てる
func _build_window(window_root: Node3D) -> void:
	var glass: StandardMaterial3D = StandardMaterial3D.new()
	glass.albedo_color = DAYLIGHT_COLOR
	glass.emission_enabled = true
	glass.emission = DAYLIGHT_COLOR
	# 外の昼の明るさが室内より明るく見え、ACES の色調で白く飛びすぎない強さ
	glass.emission_energy_multiplier = 2.2
	# 窓の部品は壁の内側の面 (z = 0) から部屋の内側 (-z) へ少し出して置く。ガラスを 5 mm、枠と桟を 1.5〜3 cm 出し、
	# 壁の面と重なってちらつかない最小の差にする。窓の下の枠は窓台として幅を 20 cm 広く・奥行を 9 cm にした
	_add_box(
		window_root,
		"Glass",
		Vector3(0.0, 0.0, -0.005),
		Vector3(WINDOW_SIZE_M.x, WINDOW_SIZE_M.y, 0.01),
		glass,
	)
	var frame_material: StandardMaterial3D = _materials[&"dark_wood"]
	# 窓枠の太さ 7 cm・桟の太さ 4 cm (洋館の木製の窓の標準)
	var frame_width: float = 0.07
	var bar_width: float = 0.04
	var half: Vector2 = WINDOW_SIZE_M * 0.5
	for frame_def: Array in [
		[
			"FrameTop",
			Vector3(0.0, half.y, -0.02),
			Vector3(WINDOW_SIZE_M.x + frame_width, frame_width, 0.05),
		],
		["FrameBottom", Vector3(0.0, -half.y, -0.03), Vector3(WINDOW_SIZE_M.x + 0.2, frame_width, 0.09)],
		["FrameLeft", Vector3(-half.x, 0.0, -0.02), Vector3(frame_width, WINDOW_SIZE_M.y, 0.05)],
		["FrameRight", Vector3(half.x, 0.0, -0.02), Vector3(frame_width, WINDOW_SIZE_M.y, 0.05)],
		["BarVertical", Vector3(0.0, 0.0, -0.015), Vector3(bar_width, WINDOW_SIZE_M.y, 0.03)],
		# 横の桟は窓の中心より 1 割上 (上下の窓の高さが 4:6 の、洋館の上げ下げ窓の比率)
		["BarHorizontal", Vector3(0.0, half.y * 0.2, -0.015), Vector3(WINDOW_SIZE_M.x, bar_width, 0.03)],
	]:
		_add_box(window_root, frame_def[0], frame_def[1], frame_def[2], frame_material)


## MansionWorld が置いた部屋の天井の灯りに影を付ける (光の当たり方だけを変え、灯りの数と位置は変えない)
func _enable_room_light_shadow(world: MansionWorld) -> void:
	if world == null:
		return
	var room_light: OmniLight3D = world.get_node_or_null(
		"LightsRoot/RoomLight_%d" % TARGET_ROOM_INDEX
	) as OmniLight3D
	if room_light != null:
		room_light.shadow_enabled = true


## 掃除ロボットが走った帯 (X は lane_start_x〜robot_x、Z は lane_z ± ロボットの半径) にある床とカーペットの毛を
## hair_field から消し、消した本数を返す
static func _remove_hairs_in_lane(
	hair_field: Node3D, lane_start_x: float, robot_x: float, lane_z: float
) -> int:
	if hair_field == null:
		return 0
	# 消すと同じ表面の最後の毛が空いた位置へ移るため、消す毛を先に集めてから消す
	var lane_hair_ids: PackedInt32Array = PackedInt32Array()
	for surface_index: int in range(hair_field.get_surface_count()):
		for slot: int in range(hair_field.get_surface_visible_instance_count(surface_index)):
			var hair_id: int = hair_field.get_hair_id_at_slot(surface_index, slot)
			var origin: Vector3 = hair_field.get_hair_transform(hair_id).origin
			if (
				origin.y <= ROBOT_CLEAR_MAX_Y_M
				and origin.x >= minf(lane_start_x, robot_x)
				and origin.x <= maxf(lane_start_x, robot_x)
				and absf(origin.z - lane_z) <= ROBOT_RADIUS_M
			):
				lane_hair_ids.append(hair_id)
	var removed: int = 0
	for hair_id: int in lane_hair_ids:
		if hair_field.remove_hair(hair_id):
			removed += 1
	return removed


## 円盤型の掃除ロボット 1 台 (本体・上蓋・前の緩衝材・後ろのセンサー) を形だけ置く。衝突体は付けない (歩く邪魔をしないため)
func _add_robot(parent_node: Node3D, robot_name: String, floor_position: Vector3) -> void:
	var robot: Node3D = Node3D.new()
	robot.name = robot_name
	robot.position = floor_position
	parent_node.add_child(robot)
	# 本体は艶を抑えた濃い灰色、上蓋は明るい灰色 (実在の製品の配色と意匠を避けた無地)。
	# 各部の比率は、家庭用の円盤型の掃除ロボットの一般的な形 (本体の上に一回り小さい蓋、後ろ寄りの小さなセンサーの突起、
	# 前の縁の緩衝材) を、本体の半径と高さに対する割合で置いたもの
	var body_material: StandardMaterial3D = make_material(
		Color(0.15, 0.15, 0.16), 0.55
	)
	_add_cylinder(
		robot,
		"Body",
		ROBOT_RADIUS_M,
		ROBOT_HEIGHT_M * 0.8,
		Vector3(0.0, ROBOT_HEIGHT_M * 0.4, 0.0),
		body_material,
	)
	_add_cylinder(
		robot,
		"Lid",
		ROBOT_RADIUS_M * 0.88,
		ROBOT_HEIGHT_M * 0.2,
		Vector3(0.0, ROBOT_HEIGHT_M * 0.9, 0.0),
		make_material(Color(0.36, 0.37, 0.38), 0.45),
	)
	_add_cylinder(
		robot,
		"Sensor",
		ROBOT_RADIUS_M * 0.22,
		ROBOT_HEIGHT_M * 0.25,
		Vector3(-ROBOT_RADIUS_M * 0.45, ROBOT_HEIGHT_M * 1.1, 0.0),
		body_material,
	)
	_add_box(
		robot,
		"Bumper",
		Vector3(ROBOT_RADIUS_M * 0.82, ROBOT_HEIGHT_M * 0.35, 0.0),
		Vector3(0.06, ROBOT_HEIGHT_M * 0.4, ROBOT_RADIUS_M * 1.3),
		body_material,
	)


## 掃除ロボットが走り始めた壁際に、形だけの充電台を置く
func _add_dock(parent_node: Node3D) -> void:
	# 充電台は幅 32 cm・高さ 12 cm・奥行 14 cm (家庭用の標準)。帯の始まりの壁 (-X) に付ける
	_add_box(
		parent_node,
		"Dock",
		Vector3(
			_room.center.x - _room.size.x * 0.5 + MansionWorldScript.WALL_THICKNESS_M + 0.07,
			0.06,
			_room.center.z + float(ROBOT_LANES[1]["z_ratio"]) * _room.size.z,
		),
		Vector3(0.14, 0.12, 0.32),
		# 色はロボットの本体と同じ系統の濃い灰色で、本体より 1 段明るくして形の境目を見せる。粗さは本体と同じ艶消し
		make_material(Color(0.18, 0.18, 0.19), 0.6),
	)


## 円柱メッシュのノードを parent_node の子に置く
func _add_cylinder(
	parent_node: Node3D,
	node_name: String,
	radius: float,
	height: float,
	mesh_position: Vector3,
	surface_material: Material,
) -> void:
	var cylinder: CylinderMesh = CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = height
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.name = node_name
	mesh_instance.mesh = cylinder
	mesh_instance.material_override = surface_material
	mesh_instance.position = mesh_position
	parent_node.add_child(mesh_instance)


## 直方体メッシュのノードを parent_node の子に置く
func _add_box(
	parent_node: Node3D,
	node_name: String,
	box_position: Vector3,
	box_size: Vector3,
	surface_material: Material,
) -> void:
	var box: BoxMesh = BoxMesh.new()
	box.size = box_size
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.name = node_name
	mesh_instance.mesh = box
	mesh_instance.material_override = surface_material
	mesh_instance.position = box_position
	parent_node.add_child(mesh_instance)


## 試作の材質を 1 回だけ作る (テクスチャの画素を GDScript で埋めるため、作り直しのたびには作らない)
func _ensure_materials() -> void:
	if not _materials.is_empty():
		return
	# ノイズの周波数は、1 画素あたりの変化の速さ。0.32 は毛足の細かい凹凸 (数画素で変わる)、0.12 は編み目や布の
	# 大きなむら (10 画素前後で変わる) に見える値。種はテクスチャごとに違う模様にするための任意の値
	var wood_height: Image = _make_wood_height_image()
	var fine_noise: Image = _make_noise_image(0.32, 7)
	var coarse_noise: Image = _make_noise_image(0.12, 11)

	# 粗さ (roughness) は物の表面の艶で決めた。塗装した木の床 0.62・磨いた家具 0.5・濃い木 0.55 は窓の光を鈍く返す艶、
	# 壁紙 0.9・ソファ 0.9・スーツ 0.9 は光を返さない紙と布、毛足のある物 (カーペット 0.98・縁 0.95・ニット 0.97) は
	# ほぼ光を返さない値
	# 凹凸の強さ (bump_map_to_normal_map の倍率) は、CI の撮影で凹凸が見え、照明で白く飛ばない範囲から材質ごとに選んだ。
	# 平らな物 (家具の木 0.6・スーツ 0.8) は弱く、毛足のある物 (カーペット 2.5・ニット 3.0) は強くする
	# 床: 中くらいの茶の木の床板。板ごとの明るさの差・木目・板の継ぎ目の溝
	_materials[&"floor"] = _make_textured_material(
		Color(0.50, 0.33, 0.20), 0.62, wood_height, wood_height, 1.2, FLOOR_TEXTURE_REPEAT_M
	)
	# 家具: 床より濃いくるみ色の木
	_materials[&"furniture"] = _make_textured_material(
		Color(0.34, 0.21, 0.13), 0.5, wood_height, wood_height, 0.6, FLOOR_TEXTURE_REPEAT_M
	)
	# 濃い木 (巾木・窓枠・ドア枠): 床より暗くして、床と壁の境目と枠の輪郭が見える色
	_materials[&"dark_wood"] = make_material(Color(0.22, 0.14, 0.09), 0.55)
	# 壁: くすんだ緑灰の壁紙 (縦の細い縞)。窓の光の色を受けて写実寄りに見える彩度の低い色
	_materials[&"wall"] = _make_textured_material(
		Color(0.52, 0.56, 0.50), 0.9, _make_wallpaper_image(), null, 0.0, WALLPAPER_TEXTURE_REPEAT_M
	)
	# 天井: 漆喰のわずかに暖かい白。灯りを照り返さないよう粗さを高くする
	_materials[&"ceiling"] = make_material(Color(0.82, 0.81, 0.78), 0.95)
	# カーペット: 深い臙脂の毛足。細かい凹凸と、毛足の明暗のむら
	_materials[&"carpet"] = _make_textured_material(
		Color(0.42, 0.10, 0.11), 0.98, fine_noise, fine_noise, 2.5, FABRIC_TEXTURE_REPEAT_M
	)
	# カーペットの縁: くすんだ金茶の房。臙脂の本体との明暗差でカーペットの輪郭が見える色
	_materials[&"carpet_trim"] = _make_textured_material(
		Color(0.58, 0.46, 0.24), 0.95, fine_noise, fine_noise, 1.5, FABRIC_TEXTURE_REPEAT_M
	)
	# ソファ: 濃い青緑のベルベット。縁の光 (rim) で布の起毛を出す
	var sofa: StandardMaterial3D = _make_textured_material(
		Color(0.10, 0.22, 0.24), 0.9, coarse_noise, fine_noise, 1.0, FABRIC_TEXTURE_REPEAT_M
	)
	sofa.rim_enabled = true
	# 縁の光の強さ 0.45 は起毛が見え、布が光って見えない上限。0.6 は縁の光に布の色を混ぜ、白い縁取りにしない割合
	sofa.rim = 0.45
	sofa.rim_tint = 0.6
	_materials[&"sofa"] = sofa
	# ニット: からし色の毛糸。猫の毛が付くと目立つ明るさで、部屋の暗い色の中で目に入る
	_materials[&"knit"] = _make_textured_material(
		Color(0.66, 0.46, 0.20), 0.97, coarse_noise, coarse_noise, 3.0, FABRIC_TEXTURE_REPEAT_M
	)
	# スーツ: ほぼ黒の紺。白い猫の毛が付くと最も目立つ色
	_materials[&"suit"] = _make_textured_material(
		Color(0.08, 0.085, 0.10), 0.9, fine_noise, fine_noise, 0.8, FABRIC_TEXTURE_REPEAT_M
	)
	# 金属: ハンガーラックの柱。鏡面の艶は避け、つや消しの鉄にする
	var metal: StandardMaterial3D = make_material(Color(0.40, 0.40, 0.42), 0.6)
	# 0.6 は鉄の色が出て、鏡のように部屋を映さない金属らしさ
	metal.metallic = 0.6
	_materials[&"metal"] = metal


## 木の床板の高さの画像 (明るいほど高い)。4 枚の板・板ごとの明るさの差・木目の縞・継ぎ目の溝を描く
static func _make_wood_height_image() -> Image:
	# 木目の縞の揺らぎ。0.06 は板 1 枚 (32 画素) の中でゆっくり曲がる周波数。種は任意
	var grain: Image = _make_noise_image(0.06, 3)
	var image: Image = Image.create(
		GENERATED_TEXTURE_SIZE, GENERATED_TEXTURE_SIZE, false, TEXTURE_IMAGE_FORMAT
	)
	for y: int in range(GENERATED_TEXTURE_SIZE):
		var plank: int = floori(float(y) / float(WOOD_PLANK_PX))
		# 板ごとの明るさの差 (0.82〜1.0)。板の番号から決まる擬似乱数 (12.9898 と 43758.5453 は、シェーダーで広く使われる
		# sin を使った擬似乱数の係数で、隣り合う番号で値が大きく変わる)
		var plank_tint: float = 0.82 + 0.18 * fposmod(sin(float(plank) * 12.9898) * 43758.5453, 1.0)
		# 板の端の継ぎ目の X 位置。隣の板と揃わないよう板ごとにずらす (53 は 128 と互いに素な素数で、4 枚の板の継ぎ目が
		# 重ならない。17 は最初の板の継ぎ目をテクスチャの端から離す任意のずれ)
		var joint_x: int = (plank * 53 + 17) % GENERATED_TEXTURE_SIZE
		for x: int in range(GENERATED_TEXTURE_SIZE):
			# 木目は板の長さの方向 (X) に流れる細い縞。板の幅 (Y) の中で 5 本並べ、ノイズで縞を波打たせる。
			# 揺らぎの 2.5 rad は縞が隣の縞に届かない (半周期 π 未満) 曲がり方。縞の明暗差は板の明るさの 20% で、
			# 18% の板ごとの差と同じくらいにして、どちらかだけが目立たないようにする
			var shade: float = plank_tint * (
				0.80
				+ 0.20 * (
					0.5
					+ 0.5 * sin(
						TAU * float(y % WOOD_PLANK_PX) / float(WOOD_PLANK_PX) * 5.0
						+ grain.get_pixel(x, y).r * 2.5
					)
				)
			)
			# 継ぎ目の溝は板の明るさの 35%。1280x720 で 1 画素の線として見える暗さ
			if y % WOOD_PLANK_PX == 0 or x == joint_x:
				shade *= 0.35
			image.set_pixel(x, y, Color(shade, shade, shade))
	return image


## 縦の細い縞の壁紙の明るさの画像
static func _make_wallpaper_image() -> Image:
	# 壁紙の紙の細かいむら。0.2 は数画素で変わる周波数。種は任意
	var noise: Image = _make_noise_image(0.2, 5)
	var image: Image = Image.create(
		GENERATED_TEXTURE_SIZE, GENERATED_TEXTURE_SIZE, false, TEXTURE_IMAGE_FORMAT
	)
	for y: int in range(GENERATED_TEXTURE_SIZE):
		for x: int in range(GENERATED_TEXTURE_SIZE):
			# 1 枚に 6 本の縞 (0.5 m で繰り返すため 8 cm 間隔)。縞の明暗差は 8% に抑えて目立たせすぎない
			# 紙のむらは明るさの 6% に抑え、縞より目立たせない
			var shade: float = (
				(1.0 if fposmod(float(x) / float(GENERATED_TEXTURE_SIZE) * 6.0, 1.0) >= 0.5 else 0.92)
				* (0.94 + 0.06 * noise.get_pixel(x, y).r)
			)
			image.set_pixel(x, y, Color(shade, shade, shade))
	return image


## 端で繋がる (タイルにしても継ぎ目が出ない) ノイズの明るさの画像 (GENERATED_TEXTURE_SIZE 四方)
static func _make_noise_image(frequency: float, noise_seed: int) -> Image:
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = noise_seed
	noise.frequency = frequency
	var image: Image = noise.get_seamless_image(GENERATED_TEXTURE_SIZE, GENERATED_TEXTURE_SIZE)
	image.convert(TEXTURE_IMAGE_FORMAT)
	return image


## 明るさの画像を色に掛けた albedo と、高さの画像から作った凹凸 (normal map) を持つ材質を作る。
## テクスチャはワールド座標の 3 方向から投影し (triplanar)、repeat_m ごとに繰り返す (箱の大きさに依らず同じ密度にするため)
static func _make_textured_material(
	albedo_color: Color,
	roughness_value: float,
	albedo_image: Image,
	height_image: Image,
	normal_strength: float,
	repeat_m: float,
) -> StandardMaterial3D:
	var surface_material: StandardMaterial3D = make_material(
		albedo_color, roughness_value
	)
	surface_material.uv1_triplanar = true
	surface_material.uv1_world_triplanar = true
	surface_material.uv1_scale = Vector3.ONE / repeat_m
	surface_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if albedo_image != null:
		var albedo: Image = albedo_image.duplicate() as Image
		albedo.generate_mipmaps()
		surface_material.albedo_texture = ImageTexture.create_from_image(albedo)
	if height_image != null and normal_strength > 0.0:
		var normal: Image = height_image.duplicate() as Image
		normal.bump_map_to_normal_map(normal_strength)
		normal.generate_mipmaps()
		surface_material.normal_enabled = true
		surface_material.normal_texture = ImageTexture.create_from_image(normal)
	return surface_material


## 指定色と粗さの StandardMaterial3D を生成する
static func make_material(albedo_color: Color, roughness_value: float) -> StandardMaterial3D:
	var surface_material: StandardMaterial3D = StandardMaterial3D.new()
	surface_material.albedo_color = albedo_color
	surface_material.roughness = roughness_value
	return surface_material

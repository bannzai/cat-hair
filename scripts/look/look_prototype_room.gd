class_name LookPrototypeRoom
extends Node3D
## 見た目の試作 (issue #19) を、屋敷の最初の部屋 (プレイヤーが入る部屋) にだけ重ねるノード。
## 写実寄りの材質・窓から差す光と影・量の多さが一目で分かる毛・一人称の手を、その部屋の中にいる間だけ見せる。
## ほかの部屋の見た目は変えない。MansionWorld の子は作り直しのたびに解放されるため、自分の物は自分の子に置き、
## MansionWorld のノードには材質と影の設定だけを上書きする。

## 1 本ずつ描く毛のノード (#6 の毛の描画の試作。中身は変えずに使う)
const HairFieldScript := preload("res://scripts/hair_field.gd")
## 一人称の手
const FirstPersonHandScript := preload("res://scripts/look/first_person_hand.gd")
## 屋敷の 3D ノード (壁の厚みの単一の正)
const MansionWorldScript := preload("res://scripts/mansion/mansion_world.gd")

## 見た目を切り替える部屋の番号。0 はプレイヤーが最初に立つ部屋 (MansionBuilder の初期位置) で、
## 起動してすぐ試作の見た目を見られるため
const TARGET_ROOM_INDEX: int = 0
## 試作の部屋に 1 本ずつ描く毛の上限本数。CI の lavapipe で 10 万本が 187 ms/frame (ADR 0002 の実測) のため、
## 撮影の 1 フレームを 10 万本の時より軽くする 6 万本で打ち切る
const VISUAL_HAIR_CAP: int = 60000
## 毛の配置の乱数の種 (試作を作った日 2026-11-26。撮るたびに同じ絵にするため)
const VISUAL_HAIR_SEED: int = 20261126
## 自動化の構図で掃除ロボットが毛を取った帯の毛を消す高さの上限 (m)。床 (0.01) とカーペット (0.04) の毛だけを消し、
## 家具の上の毛を残す高さ
const ROBOT_CLEAR_MAX_Y_M: float = 0.1
## 掃除ロボットの半径 (m)。家庭用の円盤型の掃除ロボットの標準 (直径 34 cm)
const ROBOT_RADIUS_M: float = 0.17
## 掃除ロボットの高さ (m)。家具の下に入れる家庭用の標準 (9 cm 前後)
const ROBOT_HEIGHT_M: float = 0.085
## 掃除ロボットが毛を取りながら走った帯 (部屋の幅に対する比率)。rz は帯の Z 位置、rx_end はロボットが今いる X 位置。
## 一人称の初期位置 (部屋の中心から +Z へ 0.36 の比率。MansionBuilder.SPAWN_BACK_OFFSET_RATIO) から少し見下ろした時に、
## 3 台が手前から奥へ重ならずに画面に入る Z と、台ごとに違う進み具合に見える X を選んだ
const ROBOT_LANES: Array[Dictionary] = [
	{"rz": -0.20, "rx_end": -0.05},
	{"rz": 0.0, "rx_end": 0.17},
	{"rz": 0.17, "rx_end": 0.08},
]
## 掃除ロボットが走り始めた壁からの距離 (m)。充電台の前から走り出した見た目にする
const ROBOT_LANE_START_MARGIN_M: float = 0.45
## 窓の幅と高さ (m)。洋館の縦長の窓の標準寸法
const WINDOW_SIZE_M: Vector2 = Vector2(1.5, 1.6)
## 窓の中心の床からの高さ (m)。窓の下端が床から 0.8 m になる高さ
const WINDOW_CENTER_HEIGHT_M: float = 1.6
## 窓の外の昼の光の色。曇りの日の昼の空のやや青い白
const DAYLIGHT_COLOR: Color = Color(0.86, 0.92, 1.0)
## 窓から差す光の強さ。部屋の天井の灯り (MansionWorld.ROOM_LIGHT_ENERGY = 1.6) より強くし、
## 窓の側から影が落ちる向きを主にする値
const DAYLIGHT_ENERGY: float = 7.0
## 窓から差す光の到達距離 (部屋の幅に対する倍率)。反対の壁まで届く倍率
const DAYLIGHT_RANGE_RATIO: float = 1.6
## 窓から差す光の広がり (度)。窓 1 枚から床の半分を照らす角度
const DAYLIGHT_SPOT_ANGLE_DEG: float = 55.0
## 窓から差す光を下へ傾ける角度 (rad)。昼過ぎの日差しが床に斜めに落ちる角度 (約 35 度)
const DAYLIGHT_TILT_RAD: float = 0.6
## 試作の部屋の環境光の強さ。既定 (main.tscn の 0.78) より下げ、窓と灯りの影が見える値
const PROTOTYPE_AMBIENT_ENERGY: float = 0.45
## 試作の部屋の露出。環境光を下げた分を戻し、暗くなりすぎないための値
const PROTOTYPE_EXPOSURE: float = 1.25
## 試作の部屋の家具の陰の濃さ (SSAO の強さ)。家具の足元と壁の隅に陰が付く値
const PROTOTYPE_SSAO_INTENSITY: float = 1.6
## 木目のテクスチャの 1 辺の画素数。床の 1 枚の板が 1280x720 で潰れない最小の解像度
const WOOD_TEXTURE_SIZE: int = 128
## 1 枚の板の幅 (画素)。テクスチャ 1 枚に 4 枚の板を並べる
const WOOD_PLANK_PX: int = 32
## 床のテクスチャが 1 回繰り返す長さ (m)。1 枚の板の幅を 15 cm (洋館の床板の標準) にする長さ
const FLOOR_TEXTURE_REPEAT_M: float = 0.6
## 布・ニット・カーペットのテクスチャが 1 回繰り返す長さ (m)。毛足の凹凸が 1 cm 前後に見える長さ
const FABRIC_TEXTURE_REPEAT_M: float = 0.25
## 壁紙のテクスチャが 1 回繰り返す長さ (m)。縦の縞が 8 cm 間隔に見える長さ
const WALLPAPER_TEXTURE_REPEAT_M: float = 0.5
## 布の凹凸のテクスチャの 1 辺の画素数
const FABRIC_TEXTURE_SIZE: int = 128

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
## カメラに付けた一人称の手
var _hand: FirstPersonHand = null
## 試作の部屋の中で試作の見た目を出しているか
var _prototype_active: bool = false
## タイトルを抜けて屋敷を歩いているか (タイトルの画面と起動の録画の明るさを変えないため、歩いている間だけ試作を出す)
var _playing: bool = false
## 窓・光・毛・掃除ロボットの親 (作り直しのたびに入れ替える)
var _content_root: Node3D = null
## 試作の部屋に 1 本ずつ描く毛
var _hair_field: Node3D = null
## 試作の部屋に描いた毛の本数 (自動化の構図で消した分を含まない、置いた時の本数)
var _placed_hair_count: int = 0
## 掃除ロボットと充電台の親
var _robots_root: Node3D = null
## 材質の種類 (NODE_MATERIAL_KINDS の値) から試作の材質への対応 (テクスチャの生成は 1 回だけにする)
var _materials: Dictionary = {}


## 部屋の中にいるかに合わせて、環境と手の表示を切り替える
func _process(_delta: float) -> void:
	_refresh_active()


## 部屋の中にいるかを見るプレイヤーと、差し替える環境を受け取り、プレイヤーのカメラに手を付ける。
## 同じプレイヤーで 2 回呼んでも手は 1 つ (2 回目は環境の参照だけを更新する)
func setup(player: FirstPersonPlayer, world_environment: WorldEnvironment) -> void:
	_player = player
	_world_environment = world_environment
	_base_environment = world_environment.environment
	_prototype_environment = build_prototype_environment(_base_environment)
	if _hand == null:
		_hand = FirstPersonHandScript.new()
		player.get_camera().add_child(_hand)
	_refresh_active()


## タイトルを抜けて屋敷を歩いているか (main.gd が画面の切り替えで呼ぶ) を受け取り、試作の見た目の表示を合わせる
func set_playing(playing: bool) -> void:
	_playing = playing
	_refresh_active()


## レイアウトの最初の部屋に試作の見た目を重ねる。MansionWorld.rebuild の後に毎回呼ぶ (前回の物は消してから作る)。
## layout が null か部屋が無い時は何も重ねない
func apply(layout: MansionLayout, progress: BuildingProgress, world: MansionWorld) -> void:
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
	_add_hair_field(layout, progress)
	_hide_world_hairs_in_room(world)
	_refresh_active()


## 掃除ロボットが部屋を回っている構図にする (掃除ロボットはまだ無いため、形だけの置き物と、走った帯の毛を消した絵)。
## 消した毛の本数を返す。apply の前に呼んだ時は 0
func show_automation_props() -> int:
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
		var lane_z: float = _room.center.z + float(lane["rz"]) * _room.size.z
		var robot_x: float = _room.center.x + float(lane["rx_end"]) * _room.size.x
		_add_robot(_robots_root, "Robot%d" % lane_index, Vector3(robot_x, 0.0, lane_z))
		removed += _remove_hairs_in_lane(lane_start_x, robot_x, lane_z)
	_add_dock(_robots_root)
	return removed


## 毛をつまんで引いている途中の手の構図を切り替える (手で抜く操作はまだ無いため、手と毛の位置を置いただけの構図)
func set_pinch_pose(enabled: bool) -> void:
	if _hand != null:
		_hand.set_pinch_pose(enabled, 0.0)


## 見た目を切り替えている部屋の id (無い時は空)
func get_target_room_id() -> StringName:
	return _room.room_id if _room != null else &""


## 試作の部屋に今描いている毛の本数
func get_visual_hair_count() -> int:
	return _hair_field.get_remaining_count() if _hair_field != null else 0


## 試作の部屋に置いた時の毛の本数
func get_placed_hair_count() -> int:
	return _placed_hair_count


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


## カメラに付けた一人称の手 (setup の前は null)
func get_hand() -> FirstPersonHand:
	return _hand


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


## 部屋で数えている毛の本数から、1 本ずつ描く本数を返す (上限 VISUAL_HAIR_CAP。0 以下は 0)
static func visual_hair_count(counted_hairs: int) -> int:
	return clampi(counted_hairs, 0, VISUAL_HAIR_CAP)


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


## 歩いている間にプレイヤーが試作の部屋の中にいる時だけ、試作の見た目 (環境と手) を出す
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
	if _hand != null:
		_hand.visible = active


## 前回作った窓・光・毛・掃除ロボットを解放する
func _clear_content() -> void:
	if _content_root != null:
		remove_child(_content_root)
		_content_root.free()
	_content_root = null
	_hair_field = null
	_robots_root = null
	_placed_hair_count = 0


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
	var half_extent: float = (
		_room.size.x * 0.5 if side == &"west" or side == &"east" else _room.size.z * 0.5
	)
	var wall_face: Vector3 = (
		_room.center
		- inward * (half_extent - MansionWorldScript.WALL_THICKNESS_M)
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
	var light_position: Vector3 = wall_face + inward * 0.05
	daylight.transform = Transform3D(
		Basis.looking_at(inward * cos(DAYLIGHT_TILT_RAD) + Vector3.DOWN * sin(DAYLIGHT_TILT_RAD)),
		light_position,
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
	_add_box(
		window_root,
		"Glass",
		Vector3(0.0, 0.0, -0.005),
		Vector3(WINDOW_SIZE_M.x, WINDOW_SIZE_M.y, 0.01),
		glass,
	)
	var frame: StandardMaterial3D = _materials[&"dark_wood"]
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
		["BarHorizontal", Vector3(0.0, half.y * 0.2, -0.015), Vector3(WINDOW_SIZE_M.x, bar_width, 0.03)],
	]:
		_add_box(window_root, frame_def[0], frame_def[1], frame_def[2], frame)


## MansionWorld が置いた部屋の天井の灯りに影を付ける (光の当たり方だけを変え、灯りの数と位置は変えない)
func _enable_room_light_shadow(world: MansionWorld) -> void:
	if world == null:
		return
	var room_light: OmniLight3D = world.get_node_or_null(
		"LightsRoot/RoomLight_%d" % TARGET_ROOM_INDEX
	) as OmniLight3D
	if room_light != null:
		room_light.shadow_enabled = true


## 部屋の表面ごとに数えている毛の本数を重みにして、部屋全体で visual_hair_count 本の毛を 1 本ずつ描く
func _add_hair_field(layout: MansionLayout, progress: BuildingProgress) -> void:
	if progress == null:
		return
	_hair_field = HairFieldScript.new()
	_hair_field.name = "PrototypeHairField"
	_content_root.add_child(_hair_field)
	var counted_total: int = 0
	for surface: MansionLayout.SurfaceDef in layout.surfaces:
		if surface.room_id != _room.room_id:
			continue
		var surface_hair: SurfaceHair = progress.find_surface_hair(surface.surface_id)
		var counted: int = surface_hair.total_count() if surface_hair != null else 0
		if counted <= 0:
			continue
		var half_extent: Vector3 = Vector3(surface.extents.x * 0.5, 0.0, surface.extents.y * 0.5)
		_hair_field.add_surface(
			String(surface.surface_id),
			surface.center - half_extent,
			surface.center + half_extent,
			float(counted),
		)
		counted_total += counted
	_placed_hair_count = _hair_field.populate(visual_hair_count(counted_total), VISUAL_HAIR_SEED)


## MansionWorld が描いた仮の毛 (細長い箱) のうち、試作の部屋の中にあるものを床の下へ移して見えなくする。
## 試作の部屋の毛は _add_hair_field の 1 本ずつの毛で描くため。MansionWorld の毛の描画のコードは #9 が書き換えるため変えず、
## 描画済みの MultiMesh の位置だけを動かす。headless では MultiMesh の位置を読めない (既定値が返る) ため何もしない
func _hide_world_hairs_in_room(world: MansionWorld) -> void:
	if world == null or DisplayServer.get_name() == "headless":
		return
	var hairs_root: Node = world.get_node_or_null("HairsRoot")
	if hairs_root == null:
		return
	for child: Node in hairs_root.get_children():
		if not child is MultiMeshInstance3D or (child as MultiMeshInstance3D).multimesh == null:
			continue
		var multi_mesh: MultiMesh = (child as MultiMeshInstance3D).multimesh
		for instance_index: int in range(multi_mesh.instance_count):
			var hair_transform: Transform3D = multi_mesh.get_instance_transform(instance_index)
			if is_inside_room(_room, hair_transform.origin):
				# 床 (y = 0) の 50 m 下は、どの部屋のカメラにも映らない
				hair_transform.origin.y -= 50.0
				multi_mesh.set_instance_transform(instance_index, hair_transform)


## 掃除ロボットが走った帯 (X は lane_start_x〜robot_x、Z は lane_z ± ロボットの半径) にある床とカーペットの毛を消し、
## 消した本数を返す
func _remove_hairs_in_lane(lane_start_x: float, robot_x: float, lane_z: float) -> int:
	if _hair_field == null:
		return 0
	var removed: int = 0
	for hair_id: int in range(_placed_hair_count):
		if not _hair_field.has_hair(hair_id):
			continue
		var origin: Vector3 = _hair_field.get_hair_transform(hair_id).origin
		if (
			origin.y <= ROBOT_CLEAR_MAX_Y_M
			and origin.x >= minf(lane_start_x, robot_x)
			and origin.x <= maxf(lane_start_x, robot_x)
			and absf(origin.z - lane_z) <= ROBOT_RADIUS_M
		):
			if _hair_field.remove_hair(hair_id):
				removed += 1
	return removed


## 円盤型の掃除ロボット 1 台 (本体・上蓋・前の緩衝材・後ろのセンサー) を形だけ置く。衝突体は付けない (歩く邪魔をしないため)
func _add_robot(parent_node: Node3D, robot_name: String, floor_position: Vector3) -> void:
	var robot: Node3D = Node3D.new()
	robot.name = robot_name
	robot.position = floor_position
	parent_node.add_child(robot)
	# 本体は艶を抑えた濃い灰色、上蓋は明るい灰色 (実在の製品の配色と意匠を避けた無地)
	var body: StandardMaterial3D = _make_material(Color(0.15, 0.15, 0.16), 0.55)
	var lid: StandardMaterial3D = _make_material(Color(0.36, 0.37, 0.38), 0.45)
	_add_cylinder(
		robot,
		"Body",
		ROBOT_RADIUS_M,
		ROBOT_HEIGHT_M * 0.8,
		Vector3(0.0, ROBOT_HEIGHT_M * 0.4, 0.0),
		body,
	)
	_add_cylinder(
		robot,
		"Lid",
		ROBOT_RADIUS_M * 0.88,
		ROBOT_HEIGHT_M * 0.2,
		Vector3(0.0, ROBOT_HEIGHT_M * 0.9, 0.0),
		lid,
	)
	_add_cylinder(
		robot,
		"Sensor",
		ROBOT_RADIUS_M * 0.22,
		ROBOT_HEIGHT_M * 0.25,
		Vector3(-ROBOT_RADIUS_M * 0.45, ROBOT_HEIGHT_M * 1.1, 0.0),
		body,
	)
	_add_box(
		robot,
		"Bumper",
		Vector3(ROBOT_RADIUS_M * 0.82, ROBOT_HEIGHT_M * 0.35, 0.0),
		Vector3(0.06, ROBOT_HEIGHT_M * 0.4, ROBOT_RADIUS_M * 1.3),
		body,
	)


## 掃除ロボットが走り始めた壁際に、形だけの充電台を置く
func _add_dock(parent_node: Node3D) -> void:
	var half_width: float = _room.size.x * 0.5
	# 充電台は幅 32 cm・高さ 12 cm・奥行 14 cm (家庭用の標準)。帯の始まりの壁 (-X) に付ける
	_add_box(
		parent_node,
		"Dock",
		Vector3(
			_room.center.x - half_width + MansionWorldScript.WALL_THICKNESS_M + 0.07,
			0.06,
			_room.center.z + float(ROBOT_LANES[1]["rz"]) * _room.size.z,
		),
		Vector3(0.14, 0.12, 0.32),
		_make_material(Color(0.18, 0.18, 0.19), 0.6),
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
	var wood_height: Image = _make_wood_height_image()
	var fine_noise: Image = _make_noise_image(0.32, 7)
	var coarse_noise: Image = _make_noise_image(0.12, 11)

	# 床: 中くらいの茶の木の床板。板ごとの明るさの差・木目・板の継ぎ目の溝
	_materials[&"floor"] = _make_textured_material(
		Color(0.50, 0.33, 0.20), 0.62, wood_height, wood_height, 1.2, FLOOR_TEXTURE_REPEAT_M
	)
	# 家具: 床より濃いくるみ色の木
	_materials[&"furniture"] = _make_textured_material(
		Color(0.34, 0.21, 0.13), 0.5, wood_height, wood_height, 0.6, FLOOR_TEXTURE_REPEAT_M
	)
	_materials[&"dark_wood"] = _make_material(Color(0.22, 0.14, 0.09), 0.55)
	# 壁: くすんだ緑灰の壁紙 (縦の細い縞)。窓の光の色を受けて写実寄りに見える彩度の低い色
	_materials[&"wall"] = _make_textured_material(
		Color(0.52, 0.56, 0.50), 0.9, _make_wallpaper_image(), null, 0.0, WALLPAPER_TEXTURE_REPEAT_M
	)
	_materials[&"ceiling"] = _make_material(Color(0.82, 0.81, 0.78), 0.95)
	# カーペット: 深い臙脂の毛足。細かい凹凸と、毛足の明暗のむら
	_materials[&"carpet"] = _make_textured_material(
		Color(0.42, 0.10, 0.11), 0.98, fine_noise, fine_noise, 2.5, FABRIC_TEXTURE_REPEAT_M
	)
	_materials[&"carpet_trim"] = _make_textured_material(
		Color(0.58, 0.46, 0.24), 0.95, fine_noise, fine_noise, 1.5, FABRIC_TEXTURE_REPEAT_M
	)
	# ソファ: 濃い青緑のベルベット。縁の光 (rim) で布の起毛を出す
	var sofa: StandardMaterial3D = _make_textured_material(
		Color(0.10, 0.22, 0.24), 0.9, coarse_noise, fine_noise, 1.0, FABRIC_TEXTURE_REPEAT_M
	)
	sofa.rim_enabled = true
	sofa.rim = 0.45
	sofa.rim_tint = 0.6
	_materials[&"sofa"] = sofa
	_materials[&"knit"] = _make_textured_material(
		Color(0.66, 0.46, 0.20), 0.97, coarse_noise, coarse_noise, 3.0, FABRIC_TEXTURE_REPEAT_M
	)
	_materials[&"suit"] = _make_textured_material(
		Color(0.08, 0.085, 0.10), 0.9, fine_noise, fine_noise, 0.8, FABRIC_TEXTURE_REPEAT_M
	)
	# 金属: ハンガーラックの柱。鏡面の艶は避け、つや消しの鉄にする
	var metal: StandardMaterial3D = _make_material(Color(0.40, 0.40, 0.42), 0.6)
	metal.metallic = 0.6
	_materials[&"metal"] = metal


## 木の床板の高さの画像 (明るいほど高い)。4 枚の板・板ごとの明るさの差・木目の縞・継ぎ目の溝を描く
static func _make_wood_height_image() -> Image:
	var grain: Image = _make_noise_image(0.06, 3)
	var image: Image = Image.create(WOOD_TEXTURE_SIZE, WOOD_TEXTURE_SIZE, false, Image.FORMAT_RGB8)
	for y: int in range(WOOD_TEXTURE_SIZE):
		var plank: int = floori(float(y) / float(WOOD_PLANK_PX))
		# 板ごとの明るさの差 (0.82〜1.0)。板の番号から決まる擬似乱数
		var plank_tint: float = 0.82 + 0.18 * fposmod(sin(float(plank) * 12.9898) * 43758.5453, 1.0)
		# 板の端の継ぎ目の X 位置。隣の板と揃わないよう板ごとにずらす
		var joint_x: int = (plank * 53 + 17) % WOOD_TEXTURE_SIZE
		for x: int in range(WOOD_TEXTURE_SIZE):
			# 木目は板の長さの方向 (X) に流れる縞。テクスチャの端で繋がるよう周期を幅の約数にし、ノイズで揺らす
			var stripe: float = 0.5 + 0.5 * sin(
				TAU * float(x) / float(WOOD_TEXTURE_SIZE) * 6.0 + grain.get_pixel(x, y).r * 7.0
			)
			var shade: float = plank_tint * (0.72 + 0.28 * stripe)
			if y % WOOD_PLANK_PX == 0 or x == joint_x:
				shade *= 0.35
			image.set_pixel(x, y, Color(shade, shade, shade))
	return image


## 縦の細い縞の壁紙の明るさの画像
static func _make_wallpaper_image() -> Image:
	var noise: Image = _make_noise_image(0.2, 5)
	var image: Image = Image.create(WOOD_TEXTURE_SIZE, WOOD_TEXTURE_SIZE, false, Image.FORMAT_RGB8)
	for y: int in range(WOOD_TEXTURE_SIZE):
		for x: int in range(WOOD_TEXTURE_SIZE):
			# 1 枚に 6 本の縞 (0.5 m で繰り返すため 8 cm 間隔)。縞の明暗差は 8% に抑えて目立たせすぎない
			var stripe_phase: float = fposmod(float(x) / float(WOOD_TEXTURE_SIZE) * 6.0, 1.0)
			var stripe: float = 1.0 if stripe_phase >= 0.5 else 0.92
			var shade: float = stripe * (0.94 + 0.06 * noise.get_pixel(x, y).r)
			image.set_pixel(x, y, Color(shade, shade, shade))
	return image


## 端で繋がる (タイルにしても継ぎ目が出ない) ノイズの明るさの画像 (FABRIC_TEXTURE_SIZE 四方)
static func _make_noise_image(frequency: float, noise_seed: int) -> Image:
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = noise_seed
	noise.frequency = frequency
	var image: Image = noise.get_seamless_image(FABRIC_TEXTURE_SIZE, FABRIC_TEXTURE_SIZE)
	image.convert(Image.FORMAT_RGB8)
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
	var surface_material: StandardMaterial3D = _make_material(albedo_color, roughness_value)
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
static func _make_material(albedo_color: Color, roughness_value: float) -> StandardMaterial3D:
	var surface_material: StandardMaterial3D = StandardMaterial3D.new()
	surface_material.albedo_color = albedo_color
	surface_material.roughness = roughness_value
	return surface_material

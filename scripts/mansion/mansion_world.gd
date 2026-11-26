class_name MansionWorld
extends Node3D
## MansionLayout と BuildingProgress を受け取り、屋敷 1 階の 3D 空間と仮の毛を構築する。

## 屋敷レイアウト型スクリプト
const MansionLayoutScript := preload("res://scripts/mansion/mansion_layout.gd")
## 屋敷ビルダーロジックスクリプト
const MansionBuilderScript := preload("res://scripts/mansion/mansion_builder.gd")
## 面ごとの毛データ型スクリプト
const SurfaceHairScript := preload("res://scripts/data/surface_hair.gd")

## 1 つの表面に仮描画する毛片の上限本数 (面ごとの分布を視認しつつソフトウェア描画負荷を抑える値)
const MAX_VISUAL_HAIRS_PER_SURFACE: int = 45
## 面数が多い屋敷でも各面に毛の存在が見える仮描画の下限本数
const MIN_VISUAL_HAIRS_PER_SURFACE: int = 4
## 屋敷全体で仮描画する毛片の上限本数 (CI の Mesa llvmpipe で数秒以内に完了させる上限)
const MAX_VISUAL_HAIRS_TOTAL: int = 900
## 室内補助ライト (OmniLight3D) を置く部屋数の上限。
## 出典 (Godot 4 公式ドキュメント「OpenGL 3 / GL Compatibility レンダラーの制限」):
## GL Compatibility では 1 メッシュあたり同時適用できる Omni/Spot ライト数の既定上限が 8
## (rendering/limits/opengl/max_lights_per_object = 8、DirectionalLight3D は別枠)。
## 隣室のライトが境界メッシュへ重なっても上限 8 を超えない安全余裕として 6 灯に制限する。
const MAX_ROOM_LIGHTS: int = 6
## 室内補助ライトの強度 (アンビエント 0.78 + 平行光 0.75 に重ねて床と家具の立体感を出す値)
const ROOM_LIGHT_ENERGY: float = 1.6
## 室内補助ライトの到達距離倍率 (部屋幅の対角距離 sqrt(2) ≈ 1.41 まで届く値)
const ROOM_LIGHT_RANGE_MULTIPLIER: float = 1.4
## 部屋の壁の厚み (m)。隣接部屋との Z-fighting を防ぐ内側オフセットの単一情報源
const WALL_THICKNESS_M: float = 0.14
## 隣接部屋の壁どうしが重ならないよう各部屋の壁を内側へ寄せる距離 (壁厚の半分)
const WALL_HALF_THICKNESS_M: float = WALL_THICKNESS_M * 0.5
## ドア開口の両脇に最低 0.3m ずつの壁柱を残すための最小合計余白 (m)
const DOOR_SIDE_WALL_MIN_TOTAL_M: float = 0.6
## 仮の毛片を表面の端 6% を避けて内側へ散らす半幅比率
const VISUAL_HAIR_EXTENT_HALF_RATIO: float = 0.44
## 一人称視点 2〜4m 先から細い線として視認できる仮毛片の寸法 (m)
const VISUAL_HAIR_MESH_SIZE: Vector3 = Vector3(0.014, 0.006, 0.11)
## 仮の毛片を再現性高く散らすための固定シード
const VISUAL_HAIR_RNG_SEED: int = 20261126

## 部屋ノード群の親コンテナ
var _rooms_root: Node3D = null
## 家具・布ノード群の親コンテナ
var _objects_root: Node3D = null
## 仮描画の毛 (MultiMeshInstance3D) の親コンテナ
var _hairs_root: Node3D = null
## 室内照明ノード群の親コンテナ
var _lights_root: Node3D = null
## 現在描画している仮の毛片インスタンスの総数
var _rendered_hair_count: int = 0

## 床メッシュ用マテリアル (フローリング調)
var _material_floor: StandardMaterial3D = null
## 内壁メッシュ用マテリアル (淡い生成り色)
var _material_wall: StandardMaterial3D = null
## 巾木メッシュ用マテリアル (濃い木色)
var _material_baseboard: StandardMaterial3D = null
## 天井メッシュ用マテリアル (白漆喰調)
var _material_ceiling: StandardMaterial3D = null
## ドア枠メッシュ用マテリアル (濃い木枠)
var _material_door_frame: StandardMaterial3D = null
## 天井照明シェード用マテリアル (温白色発光)
var _material_lamp: StandardMaterial3D = null
## カーペット本体用マテリアル (臙脂色)
var _material_carpet: StandardMaterial3D = null
## カーペット縁取り用マテリアル (金色系)
var _material_carpet_trim: StandardMaterial3D = null
## ソファ布地用マテリアル (深緑系)
var _material_sofa: StandardMaterial3D = null
## 木製家具用マテリアル (テーブル・椅子・キャビネット)
var _material_wood: StandardMaterial3D = null
## 住人のスーツ用マテリアル (黒地で白い毛が見えやすい色)
var _material_suit: StandardMaterial3D = null
## ハンガーラック支柱用マテリアル (金属調)
var _material_metal: StandardMaterial3D = null
## ニット布地用マテリアル (マスタード系)
var _material_knit: StandardMaterial3D = null
## 仮描画の白い毛用マテリアル
var _material_hair_white: StandardMaterial3D = null
## 仮描画の黒い毛用マテリアル
var _material_hair_black: StandardMaterial3D = null
## 仮描画の三毛用マテリアル
var _material_hair_calico: StandardMaterial3D = null


## インスタンス生成時に仮見た目マテリアルを初期化する
func _init() -> void:
	_init_materials()


## 既存の屋敷ノードをすべて破棄し、指定されたレイアウトと進行状態から再構築する
func rebuild(layout: MansionLayout, progress: BuildingProgress) -> void:
	_clear_children()
	if layout == null:
		return
	_rooms_root = Node3D.new()
	_rooms_root.name = "RoomsRoot"
	add_child(_rooms_root)

	_objects_root = Node3D.new()
	_objects_root.name = "ObjectsRoot"
	add_child(_objects_root)

	_hairs_root = Node3D.new()
	_hairs_root.name = "HairsRoot"
	add_child(_hairs_root)

	_lights_root = Node3D.new()
	_lights_root.name = "LightsRoot"
	add_child(_lights_root)

	for room_idx: int in range(layout.rooms.size()):
		_build_room_node(layout.rooms[room_idx], room_idx)

	for obj: MansionLayout.ObjectDef in layout.objects:
		_build_object_node(obj)

	_build_visual_hairs(layout, progress)


## 構築済みの部屋ノード数を返す
func get_room_node_count() -> int:
	return _rooms_root.get_child_count() if _rooms_root != null else 0


## 構築済みの物ノード数を返す
func get_object_node_count() -> int:
	return _objects_root.get_child_count() if _objects_root != null else 0


## 構築済みの室内補助ライト数を返す
func get_room_light_count() -> int:
	return _lights_root.get_child_count() if _lights_root != null else 0


## 仮描画している毛片のインスタンス総数を返す
func get_rendered_hair_instance_count() -> int:
	return _rendered_hair_count


## 既存の子ノードを即時解放し、再構築時に古いノードが残らないようにする
func _clear_children() -> void:
	_rendered_hair_count = 0
	for child: Node in get_children():
		remove_child(child)
		child.free()
	_rooms_root = null
	_objects_root = null
	_hairs_root = null
	_lights_root = null


## 床・壁・家具・布・3 色の毛の共有マテリアルを初期化する
func _init_materials() -> void:
	_material_floor = _make_material(Color(0.54, 0.39, 0.25), 0.72)
	_material_wall = _make_material(Color(0.85, 0.81, 0.74), 0.9)
	_material_baseboard = _make_material(Color(0.32, 0.22, 0.14), 0.65)
	_material_ceiling = _make_material(Color(0.92, 0.90, 0.85), 0.95)
	_material_door_frame = _make_material(Color(0.36, 0.24, 0.15), 0.6)
	_material_lamp = _make_material(Color(1.0, 0.96, 0.84), 0.3)
	_material_lamp.emission_enabled = true
	_material_lamp.emission = Color(1.0, 0.95, 0.80)
	_material_lamp.emission_energy_multiplier = 1.4

	_material_carpet = _make_material(Color(0.56, 0.16, 0.18), 0.95)
	_material_carpet_trim = _make_material(Color(0.76, 0.62, 0.30), 0.85)
	_material_sofa = _make_material(Color(0.20, 0.32, 0.34), 0.92)
	_material_wood = _make_material(Color(0.38, 0.24, 0.14), 0.58)
	_material_suit = _make_material(Color(0.11, 0.12, 0.15), 0.88)
	_material_metal = _make_material(Color(0.62, 0.64, 0.68), 0.35)
	_material_knit = _make_material(Color(0.76, 0.56, 0.28), 0.96)

	_material_hair_white = _make_material(Color(0.97, 0.95, 0.91), 0.6)
	_material_hair_black = _make_material(Color(0.10, 0.09, 0.11), 0.65)
	_material_hair_calico = _make_material(Color(0.84, 0.47, 0.19), 0.65)


## 指定色と粗さの StandardMaterial3D を生成する
static func _make_material(albedo_color: Color, roughness_value: float) -> StandardMaterial3D:
	var surface_material: StandardMaterial3D = StandardMaterial3D.new()
	surface_material.albedo_color = albedo_color
	surface_material.roughness = roughness_value
	return surface_material


## 1 部屋分の床・天井・照明・4 方向の壁ノードを生成する
func _build_room_node(room: MansionLayout.RoomDef, room_idx: int) -> void:
	var room_node: Node3D = Node3D.new()
	room_node.name = String(room.room_id)
	room_node.position = room.center
	_rooms_root.add_child(room_node)

	var room_width: float = room.size.x
	var room_height: float = room.size.y
	var room_depth: float = room.size.z

	_add_static_box(
		room_node,
		"Floor",
		Vector3(0.0, -0.05, 0.0),
		Vector3(room_width, 0.1, room_depth),
		_material_floor,
		true,
	)
	_add_static_box(
		room_node,
		"Ceiling",
		Vector3(0.0, room_height + 0.05, 0.0),
		Vector3(room_width, 0.1, room_depth),
		_material_ceiling,
		false,
	)
	_add_static_box(
		room_node,
		"CeilingLamp",
		Vector3(0.0, room_height - 0.08, 0.0),
		Vector3(0.55, 0.10, 0.55),
		_material_lamp,
		false,
	)

	if room_idx < MAX_ROOM_LIGHTS:
		var room_light: OmniLight3D = OmniLight3D.new()
		room_light.name = "RoomLight_%d" % room_idx
		room_light.position = room.center + Vector3(0.0, room_height - 0.35, 0.0)
		room_light.light_color = Color(1.0, 0.94, 0.84)
		room_light.light_energy = ROOM_LIGHT_ENERGY
		room_light.omni_range = maxf(room_width, room_depth) * ROOM_LIGHT_RANGE_MULTIPLIER
		room_light.shadow_enabled = false
		_lights_root.add_child(room_light)

	_build_wall(
		room_node,
		"WallNorth",
		Vector3(0.0, 0.0, -room_depth * 0.5 + WALL_HALF_THICKNESS_M),
		room_width,
		room_height,
		true,
		room.open_north,
	)
	_build_wall(
		room_node,
		"WallSouth",
		Vector3(0.0, 0.0, room_depth * 0.5 - WALL_HALF_THICKNESS_M),
		room_width,
		room_height,
		true,
		room.open_south,
	)
	_build_wall(
		room_node,
		"WallWest",
		Vector3(-room_width * 0.5 + WALL_HALF_THICKNESS_M, 0.0, 0.0),
		room_depth,
		room_height,
		false,
		room.open_west,
	)
	_build_wall(
		room_node,
		"WallEast",
		Vector3(room_width * 0.5 - WALL_HALF_THICKNESS_M, 0.0, 0.0),
		room_depth,
		room_height,
		false,
		room.open_east,
	)


## 1 面分の壁 (閉壁またはドア開口付きの分割壁) を生成する
func _build_wall(
	parent_node: Node3D,
	wall_name: String,
	wall_position: Vector3,
	wall_span: float,
	wall_height: float,
	along_x_axis: bool,
	has_door: bool,
) -> void:
	var wall_root: Node3D = Node3D.new()
	wall_root.name = wall_name
	wall_root.position = wall_position
	if not along_x_axis:
		wall_root.rotation.y = PI * 0.5
	parent_node.add_child(wall_root)

	if not has_door:
		_add_static_box(
			wall_root,
			"Panel",
			Vector3(0.0, wall_height * 0.5, 0.0),
			Vector3(wall_span, wall_height, WALL_THICKNESS_M),
			_material_wall,
			true,
		)
		_add_static_box(
			wall_root,
			"Baseboard",
			Vector3(0.0, 0.09, 0.0),
			Vector3(wall_span, 0.18, WALL_THICKNESS_M + 0.03),
			_material_baseboard,
			false,
		)
		return

	var door_width: float = minf(
		MansionLayoutScript.DOOR_WIDTH_M,
		wall_span - DOOR_SIDE_WALL_MIN_TOTAL_M,
	)
	var door_height: float = minf(MansionLayoutScript.DOOR_HEIGHT_M, wall_height - 0.3)
	var side_width: float = maxf(0.15, (wall_span - door_width) * 0.5)
	var side_offset: float = (door_width + side_width) * 0.5

	_add_static_box(
		wall_root,
		"LeftPanel",
		Vector3(-side_offset, wall_height * 0.5, 0.0),
		Vector3(side_width, wall_height, WALL_THICKNESS_M),
		_material_wall,
		true,
	)
	_add_static_box(
		wall_root,
		"RightPanel",
		Vector3(side_offset, wall_height * 0.5, 0.0),
		Vector3(side_width, wall_height, WALL_THICKNESS_M),
		_material_wall,
		true,
	)
	var header_height: float = maxf(0.2, wall_height - door_height)
	_add_static_box(
		wall_root,
		"HeaderPanel",
		Vector3(0.0, door_height + header_height * 0.5, 0.0),
		Vector3(door_width, header_height, WALL_THICKNESS_M),
		_material_wall,
		true,
	)
	_add_static_box(
		wall_root,
		"FrameLeft",
		Vector3(-door_width * 0.5, door_height * 0.5, 0.0),
		Vector3(0.08, door_height, WALL_THICKNESS_M + 0.04),
		_material_door_frame,
		false,
	)
	_add_static_box(
		wall_root,
		"FrameRight",
		Vector3(door_width * 0.5, door_height * 0.5, 0.0),
		Vector3(0.08, door_height, WALL_THICKNESS_M + 0.04),
		_material_door_frame,
		false,
	)
	_add_static_box(
		wall_root,
		"FrameTop",
		Vector3(0.0, door_height, 0.0),
		Vector3(door_width + 0.08, 0.08, WALL_THICKNESS_M + 0.04),
		_material_door_frame,
		false,
	)


## 家具・布 1 つ分の 3D ノードを種別に応じた基本形状で生成する
func _build_object_node(obj: MansionLayout.ObjectDef) -> void:
	var object_root: Node3D = Node3D.new()
	object_root.name = String(obj.object_id)
	object_root.position = obj.position
	object_root.rotation.y = obj.rotation_y
	_objects_root.add_child(object_root)

	var object_width: float = obj.size.x
	var object_height: float = obj.size.y
	var object_depth: float = obj.size.z

	if obj.object_kind == &"carpet":
		_add_static_box(
			object_root,
			"CarpetTrim",
			Vector3(0.0, object_height * 0.4, 0.0),
			Vector3(object_width, object_height * 0.8, object_depth),
			_material_carpet_trim,
			false,
		)
		_add_static_box(
			object_root,
			"CarpetBody",
			Vector3(0.0, object_height * 0.65, 0.0),
			Vector3(object_width * 0.92, object_height * 0.7, object_depth * 0.90),
			_material_carpet,
			false,
		)
	elif obj.object_kind == &"sofa":
		var seat_height: float = object_height * MansionBuilderScript.SOFA_SEAT_HEIGHT_RATIO
		_add_static_box(
			object_root,
			"Seat",
			Vector3(0.0, seat_height * 0.5, 0.0),
			Vector3(object_width, seat_height, object_depth),
			_material_sofa,
			true,
		)
		_add_static_box(
			object_root,
			"Backrest",
			Vector3(0.0, object_height * 0.68, -object_depth * 0.36),
			Vector3(object_width, object_height * 0.64, object_depth * 0.26),
			_material_sofa,
			true,
		)
		_add_static_box(
			object_root,
			"ArmLeft",
			Vector3(-object_width * 0.44, object_height * 0.48, 0.0),
			Vector3(object_width * 0.12, object_height * 0.48, object_depth),
			_material_sofa,
			false,
		)
		_add_static_box(
			object_root,
			"ArmRight",
			Vector3(object_width * 0.44, object_height * 0.48, 0.0),
			Vector3(object_width * 0.12, object_height * 0.48, object_depth),
			_material_sofa,
			false,
		)
	elif obj.object_kind == &"suit_rack":
		_add_static_box(
			object_root,
			"Base",
			Vector3(0.0, 0.03, 0.0),
			Vector3(object_width, 0.06, object_depth),
			_material_metal,
			true,
		)
		_add_static_box(
			object_root,
			"Pole",
			Vector3(0.0, object_height * 0.5, 0.0),
			Vector3(0.06, object_height, 0.06),
			_material_metal,
			true,
		)
		_add_static_box(
			object_root,
			"SuitJacket",
			Vector3(0.0, object_height * 0.66, 0.0),
			Vector3(object_width * 0.72, object_height * 0.46, object_depth * 0.55),
			_material_suit,
			true,
		)
		_add_static_box(
			object_root,
			"SuitShoulders",
			Vector3(0.0, object_height * 0.88, 0.0),
			Vector3(object_width * 0.86, 0.12, object_depth * 0.42),
			_material_suit,
			false,
		)
	elif obj.object_kind == &"knit_chair":
		_add_static_box(
			object_root,
			"ChairSeat",
			Vector3(0.0, object_height * 0.30, 0.0),
			Vector3(object_width, object_height * 0.60, object_depth),
			_material_wood,
			true,
		)
		_add_static_box(
			object_root,
			"ChairBack",
			Vector3(0.0, object_height * 0.75, -object_depth * 0.40),
			Vector3(object_width, object_height * 0.50, object_depth * 0.16),
			_material_wood,
			false,
		)
		_add_static_box(
			object_root,
			"KnitThrow",
			Vector3(0.0, object_height * 0.72, -object_depth * 0.15),
			Vector3(object_width * 0.88, object_height * 0.34, object_depth * 0.72),
			_material_knit,
			false,
		)
	elif obj.object_kind == &"sideboard":
		_add_static_box(
			object_root,
			"Cabinet",
			Vector3(0.0, object_height * 0.5, 0.0),
			Vector3(object_width, object_height, object_depth),
			_material_wood,
			true,
		)
		_add_static_box(
			object_root,
			"TopTrim",
			Vector3(0.0, object_height + 0.02, 0.0),
			Vector3(object_width + 0.05, 0.04, object_depth + 0.05),
			_material_door_frame,
			false,
		)
	else:
		_add_static_box(
			object_root,
			"TableTop",
			Vector3(0.0, object_height - 0.04, 0.0),
			Vector3(object_width, 0.08, object_depth),
			_material_wood,
			true,
		)
		var leg_height: float = maxf(0.1, object_height - 0.08)
		var leg_offset_x: float = object_width * 0.42
		var leg_offset_z: float = object_depth * 0.40
		for leg_pos: Vector3 in [
			Vector3(-leg_offset_x, leg_height * 0.5, -leg_offset_z),
			Vector3(leg_offset_x, leg_height * 0.5, -leg_offset_z),
			Vector3(-leg_offset_x, leg_height * 0.5, leg_offset_z),
			Vector3(leg_offset_x, leg_height * 0.5, leg_offset_z),
		]:
			_add_static_box(
				object_root,
				"Leg",
				leg_pos,
				Vector3(0.07, leg_height, 0.07),
				_material_wood,
				false,
			)


## 直方体メッシュ (必要に応じて StaticBody3D 衝突体付き) を親ノードへ追加する
func _add_static_box(
	parent_node: Node3D,
	node_name: String,
	box_position: Vector3,
	box_size: Vector3,
	surface_material: Material,
	with_collision: bool,
) -> void:
	var box_mesh: BoxMesh = BoxMesh.new()
	box_mesh.size = box_size
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.mesh = box_mesh
	mesh_instance.material_override = surface_material

	if with_collision:
		var static_body: StaticBody3D = StaticBody3D.new()
		static_body.name = node_name
		static_body.position = box_position
		var box_shape: BoxShape3D = BoxShape3D.new()
		box_shape.size = box_size
		var collision_shape: CollisionShape3D = CollisionShape3D.new()
		collision_shape.shape = box_shape
		static_body.add_child(collision_shape)
		static_body.add_child(mesh_instance)
		parent_node.add_child(static_body)
	else:
		mesh_instance.name = node_name
		mesh_instance.position = box_position
		parent_node.add_child(mesh_instance)


## 表面ごとの毛の本数をもとに、白・黒・三毛の 3 色分の仮の毛片を MultiMeshInstance3D で描画する
func _build_visual_hairs(layout: MansionLayout, progress: BuildingProgress) -> void:
	if progress == null or layout.surfaces.is_empty():
		return
	var transforms_by_color: Dictionary = {
		SurfaceHairScript.COLOR_WHITE: [],
		SurfaceHairScript.COLOR_BLACK: [],
		SurfaceHairScript.COLOR_CALICO: [],
	}
	var per_surface_cap: int = clampi(
		MAX_VISUAL_HAIRS_TOTAL / maxi(1, layout.surfaces.size()),
		MIN_VISUAL_HAIRS_PER_SURFACE,
		MAX_VISUAL_HAIRS_PER_SURFACE,
	)

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = VISUAL_HAIR_RNG_SEED

	for surface: MansionLayout.SurfaceDef in layout.surfaces:
		var surface_hair: SurfaceHair = progress.find_surface_hair(surface.surface_id)
		if surface_hair == null:
			continue
		var total_on_surface: int = surface_hair.total_count()
		if total_on_surface <= 0:
			continue
		var visual_count: int = mini(total_on_surface, per_surface_cap)
		if _rendered_hair_count + visual_count > MAX_VISUAL_HAIRS_TOTAL:
			visual_count = maxi(0, MAX_VISUAL_HAIRS_TOTAL - _rendered_hair_count)
		if visual_count <= 0:
			break

		var white_count: int = surface_hair.count_for_color(SurfaceHairScript.COLOR_WHITE)
		var black_count: int = surface_hair.count_for_color(SurfaceHairScript.COLOR_BLACK)
		var color_sum: float = maxf(
			1.0,
			float(
				white_count
				+ black_count
				+ surface_hair.count_for_color(SurfaceHairScript.COLOR_CALICO)
			),
		)

		for _hair_idx: int in range(visual_count):
			var pick_ratio: float = rng.randf() * color_sum
			var color_id: StringName = SurfaceHairScript.COLOR_CALICO
			if pick_ratio < float(white_count):
				color_id = SurfaceHairScript.COLOR_WHITE
			elif pick_ratio < float(white_count + black_count):
				color_id = SurfaceHairScript.COLOR_BLACK

			transforms_by_color[color_id].append(
				Transform3D(
					Basis(Vector3.UP, rng.randf_range(0.0, TAU)),
					Vector3(
						surface.center.x
						+ rng.randf_range(
							-surface.extents.x * VISUAL_HAIR_EXTENT_HALF_RATIO,
							surface.extents.x * VISUAL_HAIR_EXTENT_HALF_RATIO,
						),
						surface.center.y + 0.008,
						surface.center.z
						+ rng.randf_range(
							-surface.extents.y * VISUAL_HAIR_EXTENT_HALF_RATIO,
							surface.extents.y * VISUAL_HAIR_EXTENT_HALF_RATIO,
						),
					),
				)
			)
			_rendered_hair_count += 1

	_spawn_hair_multimesh(
		"HairsWhite",
		transforms_by_color[SurfaceHairScript.COLOR_WHITE],
		_material_hair_white,
	)
	_spawn_hair_multimesh(
		"HairsBlack",
		transforms_by_color[SurfaceHairScript.COLOR_BLACK],
		_material_hair_black,
	)
	_spawn_hair_multimesh(
		"HairsCalico",
		transforms_by_color[SurfaceHairScript.COLOR_CALICO],
		_material_hair_calico,
	)


## 1 色分の毛片変換配列から MultiMeshInstance3D を構築して HairsRoot へ追加する
func _spawn_hair_multimesh(
	node_name: String,
	hair_transforms: Array,
	hair_material: StandardMaterial3D,
) -> void:
	if hair_transforms.is_empty():
		return
	var hair_mesh: BoxMesh = BoxMesh.new()
	hair_mesh.size = VISUAL_HAIR_MESH_SIZE
	var multi_mesh: MultiMesh = MultiMesh.new()
	multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
	multi_mesh.mesh = hair_mesh
	multi_mesh.instance_count = hair_transforms.size()
	for instance_idx: int in range(hair_transforms.size()):
		multi_mesh.set_instance_transform(instance_idx, hair_transforms[instance_idx])
	var mesh_instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mesh_instance.name = node_name
	mesh_instance.multimesh = multi_mesh
	mesh_instance.material_override = hair_material
	_hairs_root.add_child(mesh_instance)

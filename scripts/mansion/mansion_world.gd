class_name MansionWorld
extends Node3D
## MansionLayout と BuildingProgress を受け取り、屋敷 1 階の 3D 空間と仮の毛を構築する。

const MansionLayoutScript := preload("res://scripts/mansion/mansion_layout.gd")
const SurfaceHairScript := preload("res://scripts/data/surface_hair.gd")

## 1 つの表面に仮描画する毛片の上限本数 (CI のソフトウェア描画でも軽く保つため)
const MAX_VISUAL_HAIRS_PER_SURFACE: int = 45
## 屋敷全体で仮描画する毛片の上限本数
const MAX_VISUAL_HAIRS_TOTAL: int = 900
## 室内補助ライトを置く部屋数の上限 (GL Compatibility のライト数上限に収めるため)
const MAX_ROOM_LIGHTS: int = 6

var _rooms_root: Node3D = null
var _objects_root: Node3D = null
var _hairs_root: Node3D = null
var _lights_root: Node3D = null
var _rendered_hair_count: int = 0

var _mat_floor: StandardMaterial3D = null
var _mat_wall: StandardMaterial3D = null
var _mat_baseboard: StandardMaterial3D = null
var _mat_ceiling: StandardMaterial3D = null
var _mat_door_frame: StandardMaterial3D = null
var _mat_lamp: StandardMaterial3D = null
var _mat_carpet: StandardMaterial3D = null
var _mat_carpet_trim: StandardMaterial3D = null
var _mat_sofa: StandardMaterial3D = null
var _mat_wood: StandardMaterial3D = null
var _mat_suit: StandardMaterial3D = null
var _mat_metal: StandardMaterial3D = null
var _mat_knit: StandardMaterial3D = null
var _mat_hair_white: StandardMaterial3D = null
var _mat_hair_black: StandardMaterial3D = null
var _mat_hair_calico: StandardMaterial3D = null


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
		var room: MansionLayout.RoomDef = layout.rooms[room_idx]
		_build_room_node(room, room_idx)

	for obj: MansionLayout.ObjectDef in layout.objects:
		_build_object_node(obj)

	_build_visual_hairs(layout, progress)


## 構築済みの部屋ノード数を返す
func get_room_node_count() -> int:
	return _rooms_root.get_child_count() if _rooms_root != null else 0


## 構築済みの物ノード数を返す
func get_object_node_count() -> int:
	return _objects_root.get_child_count() if _objects_root != null else 0


## 仮描画している毛片のインスタンス総数を返す
func get_rendered_hair_instance_count() -> int:
	return _rendered_hair_count


func _clear_children() -> void:
	_rendered_hair_count = 0
	for child: Node in get_children():
		remove_child(child)
		child.free()
	_rooms_root = null
	_objects_root = null
	_hairs_root = null
	_lights_root = null


func _init_materials() -> void:
	_mat_floor = _make_mat(Color(0.54, 0.39, 0.25), 0.72)
	_mat_wall = _make_mat(Color(0.85, 0.81, 0.74), 0.9)
	_mat_baseboard = _make_mat(Color(0.32, 0.22, 0.14), 0.65)
	_mat_ceiling = _make_mat(Color(0.92, 0.90, 0.85), 0.95)
	_mat_door_frame = _make_mat(Color(0.36, 0.24, 0.15), 0.6)
	_mat_lamp = _make_mat(Color(1.0, 0.96, 0.84), 0.3)
	_mat_lamp.emission_enabled = true
	_mat_lamp.emission = Color(1.0, 0.95, 0.80)
	_mat_lamp.emission_energy_multiplier = 1.4

	_mat_carpet = _make_mat(Color(0.56, 0.16, 0.18), 0.95)
	_mat_carpet_trim = _make_mat(Color(0.76, 0.62, 0.30), 0.85)
	_mat_sofa = _make_mat(Color(0.20, 0.32, 0.34), 0.92)
	_mat_wood = _make_mat(Color(0.38, 0.24, 0.14), 0.58)
	_mat_suit = _make_mat(Color(0.11, 0.12, 0.15), 0.88)
	_mat_metal = _make_mat(Color(0.62, 0.64, 0.68), 0.35)
	_mat_knit = _make_mat(Color(0.76, 0.56, 0.28), 0.96)

	_mat_hair_white = _make_mat(Color(0.97, 0.95, 0.91), 0.6)
	_mat_hair_black = _make_mat(Color(0.10, 0.09, 0.11), 0.65)
	_mat_hair_calico = _make_mat(Color(0.84, 0.47, 0.19), 0.65)


static func _make_mat(albedo: Color, roughness: float) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = albedo
	mat.roughness = roughness
	return mat


func _build_room_node(room: MansionLayout.RoomDef, room_idx: int) -> void:
	var room_node: Node3D = Node3D.new()
	room_node.name = String(room.room_id)
	room_node.position = room.center
	_rooms_root.add_child(room_node)

	var w: float = room.size.x
	var h: float = room.size.y
	var d: float = room.size.z

	# 床
	_add_static_box(
		room_node,
		"Floor",
		Vector3(0.0, -0.05, 0.0),
		Vector3(w, 0.1, d),
		_mat_floor,
		true,
	)

	# 天井
	_add_static_box(
		room_node,
		"Ceiling",
		Vector3(0.0, h + 0.05, 0.0),
		Vector3(w, 0.1, d),
		_mat_ceiling,
		false,
	)

	# 天井照明のシェード
	_add_static_box(
		room_node,
		"CeilingLamp",
		Vector3(0.0, h - 0.08, 0.0),
		Vector3(0.55, 0.10, 0.55),
		_mat_lamp,
		false,
	)

	if room_idx < MAX_ROOM_LIGHTS:
		var light: OmniLight3D = OmniLight3D.new()
		light.name = "RoomLight_%d" % room_idx
		light.position = room.center + Vector3(0.0, h - 0.35, 0.0)
		light.light_color = Color(1.0, 0.94, 0.84)
		light.light_energy = 1.6
		light.omni_range = maxf(w, d) * 1.4
		light.shadow_enabled = false
		_lights_root.add_child(light)

	# 4 方向の壁 (隣接部屋と Z-fighting しないよう壁厚の半分だけ内側に寄せる)
	var half_t: float = 0.07
	_build_wall(
		room_node,
		"WallNorth",
		Vector3(0.0, 0.0, -d * 0.5 + half_t),
		w,
		h,
		true,
		room.open_north,
	)
	_build_wall(
		room_node,
		"WallSouth",
		Vector3(0.0, 0.0, d * 0.5 - half_t),
		w,
		h,
		true,
		room.open_south,
	)
	_build_wall(
		room_node,
		"WallWest",
		Vector3(-w * 0.5 + half_t, 0.0, 0.0),
		d,
		h,
		false,
		room.open_west,
	)
	_build_wall(
		room_node,
		"WallEast",
		Vector3(w * 0.5 - half_t, 0.0, 0.0),
		d,
		h,
		false,
		room.open_east,
	)


func _build_wall(
	parent: Node3D,
	wall_name: String,
	wall_pos: Vector3,
	span: float,
	height: float,
	along_x: bool,
	has_door: bool,
) -> void:
	var thickness: float = 0.14
	var wall_root: Node3D = Node3D.new()
	wall_root.name = wall_name
	wall_root.position = wall_pos
	if not along_x:
		wall_root.rotation.y = PI * 0.5
	parent.add_child(wall_root)

	if not has_door:
		_add_static_box(
			wall_root,
			"Panel",
			Vector3(0.0, height * 0.5, 0.0),
			Vector3(span, height, thickness),
			_mat_wall,
			true,
		)
		_add_static_box(
			wall_root,
			"Baseboard",
			Vector3(0.0, 0.09, 0.0),
			Vector3(span, 0.18, thickness + 0.03),
			_mat_baseboard,
			false,
		)
		return

	var door_w: float = minf(MansionLayoutScript.DOOR_WIDTH_M, span - 0.6)
	var door_h: float = minf(MansionLayoutScript.DOOR_HEIGHT_M, height - 0.3)
	var side_w: float = maxf(0.15, (span - door_w) * 0.5)
	var side_offset: float = (door_w + side_w) * 0.5

	# 左右の壁
	_add_static_box(
		wall_root,
		"LeftPanel",
		Vector3(-side_offset, height * 0.5, 0.0),
		Vector3(side_w, height, thickness),
		_mat_wall,
		true,
	)
	_add_static_box(
		wall_root,
		"RightPanel",
		Vector3(side_offset, height * 0.5, 0.0),
		Vector3(side_w, height, thickness),
		_mat_wall,
		true,
	)
	# ドア上のまぐさ
	var top_h: float = maxf(0.2, height - door_h)
	_add_static_box(
		wall_root,
		"HeaderPanel",
		Vector3(0.0, door_h + top_h * 0.5, 0.0),
		Vector3(door_w, top_h, thickness),
		_mat_wall,
		true,
	)
	# ドア枠 (視覚的な区切り)
	_add_static_box(
		wall_root,
		"FrameLeft",
		Vector3(-door_w * 0.5, door_h * 0.5, 0.0),
		Vector3(0.08, door_h, thickness + 0.04),
		_mat_door_frame,
		false,
	)
	_add_static_box(
		wall_root,
		"FrameRight",
		Vector3(door_w * 0.5, door_h * 0.5, 0.0),
		Vector3(0.08, door_h, thickness + 0.04),
		_mat_door_frame,
		false,
	)
	_add_static_box(
		wall_root,
		"FrameTop",
		Vector3(0.0, door_h, 0.0),
		Vector3(door_w + 0.08, 0.08, thickness + 0.04),
		_mat_door_frame,
		false,
	)


func _build_object_node(obj: MansionLayout.ObjectDef) -> void:
	var root_node: Node3D = Node3D.new()
	root_node.name = String(obj.object_id)
	root_node.position = obj.position
	root_node.rotation.y = obj.rotation_y
	_objects_root.add_child(root_node)

	var sx: float = obj.size.x
	var sy: float = obj.size.y
	var sz: float = obj.size.z

	if obj.object_kind == &"carpet":
		_add_static_box(
			root_node,
			"CarpetTrim",
			Vector3(0.0, sy * 0.4, 0.0),
			Vector3(sx, sy * 0.8, sz),
			_mat_carpet_trim,
			false,
		)
		_add_static_box(
			root_node,
			"CarpetBody",
			Vector3(0.0, sy * 0.65, 0.0),
			Vector3(sx * 0.92, sy * 0.7, sz * 0.90),
			_mat_carpet,
			false,
		)
	elif obj.object_kind == &"sofa":
		_add_static_box(
			root_node,
			"Seat",
			Vector3(0.0, sy * 0.28, 0.0),
			Vector3(sx, sy * 0.56, sz),
			_mat_sofa,
			true,
		)
		_add_static_box(
			root_node,
			"Backrest",
			Vector3(0.0, sy * 0.68, -sz * 0.36),
			Vector3(sx, sy * 0.64, sz * 0.26),
			_mat_sofa,
			true,
		)
		_add_static_box(
			root_node,
			"ArmLeft",
			Vector3(-sx * 0.44, sy * 0.48, 0.0),
			Vector3(sx * 0.12, sy * 0.48, sz),
			_mat_sofa,
			false,
		)
		_add_static_box(
			root_node,
			"ArmRight",
			Vector3(sx * 0.44, sy * 0.48, 0.0),
			Vector3(sx * 0.12, sy * 0.48, sz),
			_mat_sofa,
			false,
		)
	elif obj.object_kind == &"suit_rack":
		_add_static_box(
			root_node,
			"Base",
			Vector3(0.0, 0.03, 0.0),
			Vector3(sx, 0.06, sz),
			_mat_metal,
			true,
		)
		_add_static_box(
			root_node,
			"Pole",
			Vector3(0.0, sy * 0.5, 0.0),
			Vector3(0.06, sy, 0.06),
			_mat_metal,
			true,
		)
		_add_static_box(
			root_node,
			"SuitJacket",
			Vector3(0.0, sy * 0.66, 0.0),
			Vector3(sx * 0.72, sy * 0.46, sz * 0.55),
			_mat_suit,
			true,
		)
		_add_static_box(
			root_node,
			"SuitShoulders",
			Vector3(0.0, sy * 0.88, 0.0),
			Vector3(sx * 0.86, 0.12, sz * 0.42),
			_mat_suit,
			false,
		)
	elif obj.object_kind == &"knit_chair":
		_add_static_box(
			root_node,
			"ChairSeat",
			Vector3(0.0, sy * 0.30, 0.0),
			Vector3(sx, sy * 0.60, sz),
			_mat_wood,
			true,
		)
		_add_static_box(
			root_node,
			"ChairBack",
			Vector3(0.0, sy * 0.75, -sz * 0.40),
			Vector3(sx, sy * 0.50, sz * 0.16),
			_mat_wood,
			false,
		)
		_add_static_box(
			root_node,
			"KnitThrow",
			Vector3(0.0, sy * 0.72, -sz * 0.15),
			Vector3(sx * 0.88, sy * 0.34, sz * 0.72),
			_mat_knit,
			false,
		)
	elif obj.object_kind == &"sideboard":
		_add_static_box(
			root_node,
			"Cabinet",
			Vector3(0.0, sy * 0.5, 0.0),
			Vector3(sx, sy, sz),
			_mat_wood,
			true,
		)
		_add_static_box(
			root_node,
			"TopTrim",
			Vector3(0.0, sy + 0.02, 0.0),
			Vector3(sx + 0.05, 0.04, sz + 0.05),
			_mat_door_frame,
			false,
		)
	else:
		# テーブル
		_add_static_box(
			root_node,
			"TableTop",
			Vector3(0.0, sy - 0.04, 0.0),
			Vector3(sx, 0.08, sz),
			_mat_wood,
			true,
		)
		var leg_h: float = maxf(0.1, sy - 0.08)
		var lx: float = sx * 0.42
		var lz: float = sz * 0.40
		for leg_pos: Vector3 in [
			Vector3(-lx, leg_h * 0.5, -lz),
			Vector3(lx, leg_h * 0.5, -lz),
			Vector3(-lx, leg_h * 0.5, lz),
			Vector3(lx, leg_h * 0.5, lz),
		]:
			_add_static_box(
				root_node,
				"Leg",
				leg_pos,
				Vector3(0.07, leg_h, 0.07),
				_mat_wood,
				false,
			)


func _add_static_box(
	parent: Node3D,
	node_name: String,
	pos: Vector3,
	size: Vector3,
	mat: Material,
	with_collision: bool,
) -> void:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.material_override = mat

	if with_collision:
		var body: StaticBody3D = StaticBody3D.new()
		body.name = node_name
		body.position = pos
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = size
		var collider: CollisionShape3D = CollisionShape3D.new()
		collider.shape = shape
		body.add_child(collider)
		body.add_child(mesh_instance)
		parent.add_child(body)
	else:
		mesh_instance.name = node_name
		mesh_instance.position = pos
		parent.add_child(mesh_instance)


## 表面ごとの毛の本数をもとに、白・黒・三毛の 3 色分の仮の毛片を MultiMeshInstance3D で描画する
func _build_visual_hairs(layout: MansionLayout, progress: BuildingProgress) -> void:
	if progress == null or layout.surfaces.is_empty():
		return
	var transforms_by_color: Dictionary = {
		SurfaceHairScript.COLOR_WHITE: [],
		SurfaceHairScript.COLOR_BLACK: [],
		SurfaceHairScript.COLOR_CALICO: [],
	}
	var total_budget: int = MAX_VISUAL_HAIRS_TOTAL
	var surface_count: int = layout.surfaces.size()
	var per_surface_cap: int = clampi(
		total_budget / maxi(1, surface_count),
		4,
		MAX_VISUAL_HAIRS_PER_SURFACE,
	)

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 20261126

	for surface: MansionLayout.SurfaceDef in layout.surfaces:
		var surface_hair: SurfaceHair = progress.find_surface_hair(surface.surface_id)
		if surface_hair == null:
			continue
		var total_on_surface: int = surface_hair.total_count()
		if total_on_surface <= 0:
			continue
		var visual_count: int = mini(total_on_surface, per_surface_cap)
		if _rendered_hair_count + visual_count > total_budget:
			visual_count = maxi(0, total_budget - _rendered_hair_count)
		if visual_count <= 0:
			break

		var w_count: int = surface_hair.count_for_color(SurfaceHairScript.COLOR_WHITE)
		var b_count: int = surface_hair.count_for_color(SurfaceHairScript.COLOR_BLACK)
		var c_count: int = surface_hair.count_for_color(SurfaceHairScript.COLOR_CALICO)
		var color_sum: float = maxf(1.0, float(w_count + b_count + c_count))

		for _i: int in range(visual_count):
			var pick: float = rng.randf() * color_sum
			var color_id: StringName = SurfaceHairScript.COLOR_CALICO
			if pick < float(w_count):
				color_id = SurfaceHairScript.COLOR_WHITE
			elif pick < float(w_count + b_count):
				color_id = SurfaceHairScript.COLOR_BLACK

			var ox: float = rng.randf_range(-surface.extents.x * 0.44, surface.extents.x * 0.44)
			var oz: float = rng.randf_range(-surface.extents.y * 0.44, surface.extents.y * 0.44)
			var yaw: float = rng.randf_range(0.0, TAU)
			var pos: Vector3 = Vector3(
				surface.center.x + ox,
				surface.center.y + 0.008,
				surface.center.z + oz,
			)
			var basis: Basis = Basis(Vector3.UP, yaw)
			var list: Array = transforms_by_color[color_id]
			list.append(Transform3D(basis, pos))
			_rendered_hair_count += 1

	_spawn_hair_multimesh(
		"HairsWhite",
		transforms_by_color[SurfaceHairScript.COLOR_WHITE],
		_mat_hair_white,
	)
	_spawn_hair_multimesh(
		"HairsBlack",
		transforms_by_color[SurfaceHairScript.COLOR_BLACK],
		_mat_hair_black,
	)
	_spawn_hair_multimesh(
		"HairsCalico",
		transforms_by_color[SurfaceHairScript.COLOR_CALICO],
		_mat_hair_calico,
	)


func _spawn_hair_multimesh(
	node_name: String,
	transforms: Array,
	mat: StandardMaterial3D,
) -> void:
	if transforms.is_empty():
		return
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(0.014, 0.006, 0.11)
	var multi_mesh: MultiMesh = MultiMesh.new()
	multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
	multi_mesh.mesh = mesh
	multi_mesh.instance_count = transforms.size()
	for idx: int in range(transforms.size()):
		multi_mesh.set_instance_transform(idx, transforms[idx])
	var instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multi_mesh
	instance.material_override = mat
	_hairs_root.add_child(instance)

extends Node3D
## 毛の描画の試作シーン。床とソファの 2 表面を持つ 1 部屋に毛を配置し、
## 一人称視点から 1 本ずつ見分けられることと、1 本だけ消せることを確かめる。

## 部屋の床の幅・奥行き (m)
const ROOM_SIZE_M: float = 5.0
## 部屋の壁の高さ (m)
const WALL_HEIGHT_M: float = 2.8
## ソファ座面の高さ (m)
const SOFA_SEAT_Y_M: float = 0.44
## 床とソファへの毛の本数配分 (床 82% / ソファ 18%)
const FLOOR_WEIGHT: float = 0.82
const SOFA_WEIGHT: float = 0.18

## 毛の描画ノード (表面ごとに MultiMesh を持つ)
@onready var hair_field: Node3D = $HairField


## 部屋の表面メッシュと HairField の配置領域を初期化する
func _ready() -> void:
	_build_room_geometry()
	_configure_hair_surfaces()


## 部屋全体へ合計 total_count 本の毛を配置し、配置できた本数を返す
func populate_hairs(total_count: int, seed_value: int = 20261126) -> int:
	return hair_field.populate(total_count, seed_value)


## 指定した毛 ID を 1 本だけ消す
func remove_hair(hair_id: int) -> bool:
	return hair_field.remove_hair(hair_id)


## 現在の残り毛本数を返す
func get_remaining_count() -> int:
	return hair_field.get_remaining_count()


## 内部の HairField ノードを返す
func get_hair_field() -> Node3D:
	return hair_field


func _configure_hair_surfaces() -> void:
	# 床: カメラから手前〜奥まで視界に入る領域
	hair_field.add_surface(
		"floor",
		Vector3(-2.3, 0.0, -2.2),
		Vector3(2.3, 0.0, 1.8),
		FLOOR_WEIGHT
	)
	# ソファ座面: 猫が昼寝する想定の表面
	hair_field.add_surface(
		"sofa",
		Vector3(-0.92, SOFA_SEAT_Y_M, -1.46),
		Vector3(0.92, SOFA_SEAT_Y_M, -0.78),
		SOFA_WEIGHT
	)


func _build_room_geometry() -> void:
	var room: Node3D = $Room

	var floor_mat: StandardMaterial3D = _make_material(Color(0.43, 0.31, 0.21), 0.65)
	var wall_mat: StandardMaterial3D = _make_material(Color(0.80, 0.77, 0.70), 0.88)
	var trim_mat: StandardMaterial3D = _make_material(Color(0.24, 0.17, 0.12), 0.60)
	var sofa_mat: StandardMaterial3D = _make_material(Color(0.29, 0.35, 0.42), 0.92)
	var wood_leg_mat: StandardMaterial3D = _make_material(Color(0.20, 0.13, 0.08), 0.55)

	# 床 (上面が Y = 0.0)
	_add_box(
		room, "Floor", Vector3(ROOM_SIZE_M, 0.1, ROOM_SIZE_M),
		Vector3(0.0, -0.05, 0.0), floor_mat
	)

	# 壁 (奥・左・右)
	var half_room: float = ROOM_SIZE_M * 0.5
	var wall_y: float = WALL_HEIGHT_M * 0.5
	_add_box(
		room, "BackWall", Vector3(ROOM_SIZE_M, WALL_HEIGHT_M, 0.12),
		Vector3(0.0, wall_y, -half_room), wall_mat
	)
	_add_box(
		room, "LeftWall", Vector3(0.12, WALL_HEIGHT_M, ROOM_SIZE_M),
		Vector3(-half_room, wall_y, 0.0), wall_mat
	)
	_add_box(
		room, "RightWall", Vector3(0.12, WALL_HEIGHT_M, ROOM_SIZE_M),
		Vector3(half_room, wall_y, 0.0), wall_mat
	)

	# 奥の壁の巾木
	_add_box(
		room, "Baseboard", Vector3(ROOM_SIZE_M, 0.14, 0.04),
		Vector3(0.0, 0.07, -half_room + 0.07), trim_mat
	)

	# ソファ (座面の上面が SOFA_SEAT_Y_M = 0.44)
	_add_box(room, "SofaSeat", Vector3(1.94, 0.24, 0.76), Vector3(0.0, 0.32, -1.12), sofa_mat)
	_add_box(room, "SofaBack", Vector3(1.94, 0.58, 0.20), Vector3(0.0, 0.66, -1.56), sofa_mat)
	_add_box(room, "SofaArmLeft", Vector3(0.20, 0.42, 0.90), Vector3(-1.07, 0.41, -1.18), sofa_mat)
	_add_box(room, "SofaArmRight", Vector3(0.20, 0.42, 0.90), Vector3(1.07, 0.41, -1.18), sofa_mat)

	# ソファの脚 4 本
	var leg_offsets: Array[Vector3] = [
		Vector3(-1.04, 0.10, -0.82),
		Vector3(1.04, 0.10, -0.82),
		Vector3(-1.04, 0.10, -1.54),
		Vector3(1.04, 0.10, -1.54),
	]
	for idx: int in range(leg_offsets.size()):
		_add_box(room, "SofaLeg_%d" % idx, Vector3(0.08, 0.20, 0.08), leg_offsets[idx], wood_leg_mat)


func _make_material(albedo: Color, roughness: float) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = albedo
	mat.roughness = roughness
	return mat


func _add_box(
	parent: Node3D, node_name: String, size: Vector3, pos: Vector3, mat: Material
) -> void:
	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	mesh_inst.name = node_name
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	mesh_inst.mesh = box
	mesh_inst.material_override = mat
	mesh_inst.position = pos
	parent.add_child(mesh_inst)

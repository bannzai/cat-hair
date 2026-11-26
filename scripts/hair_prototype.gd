extends Node3D
## 毛の描画の試作シーン。床とソファの 2 表面を持つ 1 部屋に毛を配置し、
## 一人称視点から 1 本ずつ見分けられることと、1 本だけ消せることを確かめる。

## HairField の既定シードを SSOT として参照する
const HairFieldScript := preload("res://scripts/hair_field.gd")
## 部屋の床の幅・奥行き (m。1 部屋の標準的な 5m 四方)
const ROOM_SIZE_M: float = 5.0
## 部屋の壁の高さ (m。一人称視点で天井付近まで映る高さ)
const WALL_HEIGHT_M: float = 2.8
## 壁の厚み (m。一般的な室内間仕切り壁の厚み 12 cm)
const WALL_THICKNESS_M: float = 0.12
## 巾木の高さ (m。床と壁の境界を視覚的に区切る 14 cm)
const BASEBOARD_HEIGHT_M: float = 0.14
## 巾木の厚み (m。壁面から 4 cm 張り出させて陰影を付ける)
const BASEBOARD_DEPTH_M: float = 0.04
## 床の毛配置の壁際余白 (m。壁・巾木への毛の貫通を避ける 20 cm 余白)
const FLOOR_HAIR_MARGIN_M: float = 0.20
## 床の毛配置の手前側 Z 上限 (m。カメラ z=0.42 の背後まで覆う 1.8 m)
const FLOOR_HAIR_FRONT_Z_M: float = 1.8
## ソファ座面の上面高さ (m。一般的なソファ座面 44 cm)
const SOFA_SEAT_Y_M: float = 0.44
## ソファ座面クッションの厚み (m。座面箱の中心 Y は SOFA_SEAT_Y_M から計算する)
const SOFA_SEAT_HEIGHT_M: float = 0.24
## ソファ座面の幅 (m。3 人掛け相当の 1.94 m)
const SOFA_SEAT_WIDTH_M: float = 1.94
## ソファ座面の奥行 (m。座面として標準的な 76 cm)
const SOFA_SEAT_DEPTH_M: float = 0.76
## ソファ座面の中心 Z 座標 (m。カメラ z=0.42 から 1.5 m 奥に置き床と両方映す)
const SOFA_SEAT_Z_M: float = -1.12
## ソファ座面の毛配置の縁余白 (m。座面端からの毛のはみ出しを抑える 5 cm)
const SOFA_HAIR_MARGIN_M: float = 0.05
## 床とソファへの毛の本数配分 (床面積 18.4 m²・ソファ座面 1.25 m² に対し、
## 猫の昼寝場所であるソファをやや高密度にして両表面の識別性を確かめる配分)
const FLOOR_WEIGHT: float = 0.82
## ソファ座面への毛の本数配分比率 (FLOOR_WEIGHT と合計 1.0)
const SOFA_WEIGHT: float = 0.18

## 毛の描画ノード (表面ごとに MultiMesh を持つ)
@onready var hair_field: Node3D = $HairField


## 部屋の表面メッシュと HairField の配置領域を初期化する
func _ready() -> void:
	_build_room_geometry()
	_configure_hair_surfaces()


## 部屋全体へ合計 total_count 本の毛を配置し、配置できた本数を返す
func populate_hairs(
	total_count: int, seed_value: int = HairFieldScript.DEFAULT_SEED
) -> int:
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


## 床とソファ座面の配置領域を、部屋の寸法定数から算出して HairField に登録する
func _configure_hair_surfaces() -> void:
	var floor_half_x: float = ROOM_SIZE_M * 0.5 - FLOOR_HAIR_MARGIN_M
	var floor_back_z: float = -ROOM_SIZE_M * 0.5 + FLOOR_HAIR_MARGIN_M + WALL_THICKNESS_M
	# 床: カメラから手前〜奥壁の手前まで視界に入る領域
	hair_field.add_surface(
		"floor",
		Vector3(-floor_half_x, 0.0, floor_back_z),
		Vector3(floor_half_x, 0.0, FLOOR_HAIR_FRONT_Z_M),
		FLOOR_WEIGHT
	)
	# ソファ座面: 座面箱 (SOFA_SEAT_*) の内側に SOFA_HAIR_MARGIN_M 余白を取って算出する
	var seat_half_x: float = SOFA_SEAT_WIDTH_M * 0.5 - SOFA_HAIR_MARGIN_M
	var seat_half_z: float = SOFA_SEAT_DEPTH_M * 0.5 - SOFA_HAIR_MARGIN_M
	hair_field.add_surface(
		"sofa",
		Vector3(-seat_half_x, SOFA_SEAT_Y_M, SOFA_SEAT_Z_M - seat_half_z),
		Vector3(seat_half_x, SOFA_SEAT_Y_M, SOFA_SEAT_Z_M + seat_half_z),
		SOFA_WEIGHT
	)


## 1 部屋の床・壁・巾木・ソファの簡易メッシュを構築する
func _build_room_geometry() -> void:
	var room: Node3D = $Room

	# 落ち着いた室内の色と roughness (白・黒・三毛の毛とコントラストを確保する中明度・非鏡面)
	var wall_material: StandardMaterial3D = _make_material(Color(0.64, 0.60, 0.54), 0.90)
	var sofa_material: StandardMaterial3D = _make_material(Color(0.19, 0.24, 0.31), 0.92)
	var wood_leg_material: StandardMaterial3D = _make_material(Color(0.18, 0.11, 0.07), 0.55)

	# 床 (上面が Y = 0.0。厚み 0.1 m のスラブを下に配置。木床の中明度茶色・roughness 0.70)
	_add_box(
		room, "Floor", Vector3(ROOM_SIZE_M, 0.1, ROOM_SIZE_M),
		Vector3(0.0, -0.05, 0.0), _make_material(Color(0.32, 0.22, 0.14), 0.70)
	)

	# 壁 (奥・左・右の 3 面で部屋を囲う)
	var half_room: float = ROOM_SIZE_M * 0.5
	var wall_y: float = WALL_HEIGHT_M * 0.5
	_add_box(
		room, "BackWall", Vector3(ROOM_SIZE_M, WALL_HEIGHT_M, WALL_THICKNESS_M),
		Vector3(0.0, wall_y, -half_room), wall_material
	)
	_add_box(
		room, "LeftWall", Vector3(WALL_THICKNESS_M, WALL_HEIGHT_M, ROOM_SIZE_M),
		Vector3(-half_room, wall_y, 0.0), wall_material
	)
	_add_box(
		room, "RightWall", Vector3(WALL_THICKNESS_M, WALL_HEIGHT_M, ROOM_SIZE_M),
		Vector3(half_room, wall_y, 0.0), wall_material
	)

	# 奥の壁の巾木 (奥壁の内側面に接するよう配置。こげ茶の木部 roughness 0.60)
	_add_box(
		room, "Baseboard", Vector3(ROOM_SIZE_M, BASEBOARD_HEIGHT_M, BASEBOARD_DEPTH_M),
		Vector3(0.0, BASEBOARD_HEIGHT_M * 0.5, -half_room + WALL_THICKNESS_M * 0.5 + 0.01),
		_make_material(Color(0.20, 0.14, 0.10), 0.60)
	)

	# ソファ本体 (座面・背もたれ・両肘掛けを SOFA_SEAT_* 定数基準で配置)
	var seat_center_y: float = SOFA_SEAT_Y_M - SOFA_SEAT_HEIGHT_M * 0.5
	_add_box(
		room, "SofaSeat", Vector3(SOFA_SEAT_WIDTH_M, SOFA_SEAT_HEIGHT_M, SOFA_SEAT_DEPTH_M),
		Vector3(0.0, seat_center_y, SOFA_SEAT_Z_M), sofa_material
	)
	# 背もたれ (高さ 58 cm・厚み 20 cm、座面奥端に接して配置)
	_add_box(
		room, "SofaBack", Vector3(SOFA_SEAT_WIDTH_M, 0.58, 0.20),
		Vector3(0.0, SOFA_SEAT_Y_M + 0.22, SOFA_SEAT_Z_M - SOFA_SEAT_DEPTH_M * 0.5 - 0.06),
		sofa_material
	)
	# 両肘掛け (幅 20 cm・高さ 42 cm・奥行 90 cm、座面の左右外側に配置)
	var arm_x: float = SOFA_SEAT_WIDTH_M * 0.5 + 0.10
	_add_box(
		room, "SofaArmLeft", Vector3(0.20, 0.42, 0.90),
		Vector3(-arm_x, 0.41, SOFA_SEAT_Z_M - 0.06), sofa_material
	)
	_add_box(
		room, "SofaArmRight", Vector3(0.20, 0.42, 0.90),
		Vector3(arm_x, 0.41, SOFA_SEAT_Z_M - 0.06), sofa_material
	)

	# ソファの脚 4 本 (高さ 20 cm で座面底面 y=0.20 を床 y=0.0 で支える)
	var leg_x: float = SOFA_SEAT_WIDTH_M * 0.5 + 0.07
	var leg_front_z: float = SOFA_SEAT_Z_M + SOFA_SEAT_DEPTH_M * 0.5 - 0.08
	var leg_back_z: float = SOFA_SEAT_Z_M - SOFA_SEAT_DEPTH_M * 0.5 - 0.04
	var leg_offsets: Array[Vector3] = [
		Vector3(-leg_x, 0.10, leg_front_z),
		Vector3(leg_x, 0.10, leg_front_z),
		Vector3(-leg_x, 0.10, leg_back_z),
		Vector3(leg_x, 0.10, leg_back_z),
	]
	for idx: int in range(leg_offsets.size()):
		_add_box(
			room, "SofaLeg_%d" % idx, Vector3(0.08, 0.20, 0.08),
			leg_offsets[idx], wood_leg_material
		)


## 単色の PBR StandardMaterial3D を生成する
func _make_material(albedo: Color, roughness: float) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = albedo
	material.roughness = roughness
	return material


## 指定した親ノードに BoxMesh の MeshInstance3D を追加する
func _add_box(
	parent: Node3D, node_name: String, size: Vector3, pos: Vector3, material: Material
) -> void:
	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	mesh_inst.name = node_name
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	mesh_inst.mesh = box
	mesh_inst.material_override = material
	mesh_inst.position = pos
	parent.add_child(mesh_inst)

extends RefCounted
## 大型の道具の見た目 (吸引車の運転席・床一面の粘着シート・アンドロイド・毛の加工機・ダンプカー) を、
## 箱・円柱・輪の組み合わせで組み立てる。実在の車や機械の意匠に似せない、色の付いた単純な形にする
## (DIRECTION.md「決めたこと」: 実在の商品名・メーカー名・意匠を使わない)。状態は持たない。
## 寸法と色は、CI の撮影 (tmp/screenshot-*.png) で、部屋の家具 (1 m 前後) と並べて道具と分かる大きさ・色を目で見て決めた値で、
## ゲームの計算には使わない

## 運転席の内装の色 (濃い灰色。部屋の暖かい色の前で、運転席の枠と分かる色)
const COCKPIT_COLOR: Color = Color(0.18, 0.19, 0.21)
## 吸引車の車体と計器の差し色 (黄色。作業車と分かり、部屋の床と壁の茶色と見分けやすい色)
const WORK_VEHICLE_COLOR: Color = Color(0.92, 0.72, 0.16)
## 粘着シートの色 (薄い黄色の半透明。下の床と、捕まった毛が透けて見える)
const SHEET_COLOR: Color = Color(1.0, 0.95, 0.7, 0.35)
## 粘着シートを床から浮かせる高さ (m)。カーペットの上面より上に置き、カーペットに隠れない高さ
const SHEET_LIFT_M: float = 0.03
## アンドロイドの体の色 (白に近い灰色。住人 (焦げ茶の作業着の買取業者) と見分けられる色)
const ANDROID_COLOR: Color = Color(0.86, 0.88, 0.9)
## アンドロイドの目の色 (水色。人でなく機械と分かる印)
const ANDROID_EYE_COLOR: Color = Color(0.3, 0.85, 1.0)
## アンドロイドの背の高さ (m。住人と同じくらい)
const ANDROID_HEIGHT_M: float = 1.6
## 毛の加工機の箱の大きさ (m。膝の高さほどの箱で、部屋の隅に並べても通り道をふさがない大きさ)
const PROCESSOR_SIZE_M: Vector3 = Vector3(0.5, 0.6, 0.5)
## 毛の加工機の色 (青緑。家具の木の色・壁紙と見分けやすい色)
const PROCESSOR_COLOR: Color = Color(0.2, 0.55, 0.55)
## ダンプカーの荷台の色
const DUMP_BED_COLOR: Color = Color(0.75, 0.35, 0.18)


## 業務用の吸引車の運転席 (計器盤・ハンドル・窓の柱・屋根の縁・ホースの付け根) をカメラの手前に組み立てる。
## カメラの子にすると、前を向いたまま運転席の窓から部屋を眺める見え方になる
static func build_cockpit() -> Node3D:
	var cockpit: Node3D = Node3D.new()
	cockpit.name = "Cockpit"
	var body: StandardMaterial3D = _material(COCKPIT_COLOR, 0.7)
	var accent: StandardMaterial3D = _material(WORK_VEHICLE_COLOR, 0.5)
	# 計器盤は画面の下 3 分の 1 ほどを隠し、上の窓から部屋が見える高さ
	_add_box(cockpit, "Dashboard", Vector3(0.0, -0.42, -0.75), Vector3(1.9, 0.28, 0.5), body)
	_add_box(cockpit, "Gauge", Vector3(0.35, -0.27, -0.62), Vector3(0.36, 0.04, 0.14), accent)
	_add_box(cockpit, "PillarLeft", Vector3(-0.92, 0.1, -0.85), Vector3(0.1, 1.2, 0.1), body)
	_add_box(cockpit, "PillarRight", Vector3(0.92, 0.1, -0.85), Vector3(0.1, 1.2, 0.1), body)
	_add_box(cockpit, "RoofEdge", Vector3(0.0, 0.62, -0.85), Vector3(1.94, 0.12, 0.12), accent)
	var wheel_mesh: TorusMesh = TorusMesh.new()
	wheel_mesh.inner_radius = 0.15
	wheel_mesh.outer_radius = 0.19
	var wheel: MeshInstance3D = _add_mesh(
		cockpit, "SteeringWheel", wheel_mesh, Vector3(-0.32, -0.28, -0.55), body
	)
	wheel.rotation_degrees = Vector3(65.0, 0.0, 0.0)
	var hose_mesh: CylinderMesh = CylinderMesh.new()
	hose_mesh.top_radius = 0.07
	hose_mesh.bottom_radius = 0.07
	hose_mesh.height = 0.9
	var hose: MeshInstance3D = _add_mesh(
		cockpit, "Hose", hose_mesh, Vector3(0.82, -0.35, -0.9), accent
	)
	hose.rotation_degrees = Vector3(80.0, 0.0, 20.0)
	return cockpit


## 部屋 room の床一面を覆う、半透明の粘着シートを組み立てる (置く場所も決めて返す)
static func build_floor_sheet(room: MansionLayout.RoomDef) -> MeshInstance3D:
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(room.size.x, room.size.z)
	var material: StandardMaterial3D = _material(SHEET_COLOR, 0.15)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	plane.material = material
	var sheet: MeshInstance3D = MeshInstance3D.new()
	sheet.name = "AdhesiveSheet"
	sheet.mesh = plane
	sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sheet.position = room.center + Vector3(0.0, SHEET_LIFT_M, 0.0)
	return sheet


## アンドロイド (頭・目・胴・腕・脚) を足元を原点にして組み立てる
static func build_android() -> Node3D:
	var android: Node3D = Node3D.new()
	android.name = "Android"
	var body: StandardMaterial3D = _material(ANDROID_COLOR, 0.3)
	body.metallic = 0.4
	var eye: StandardMaterial3D = _material(ANDROID_EYE_COLOR, 0.2)
	eye.emission_enabled = true
	eye.emission = ANDROID_EYE_COLOR
	var leg_height: float = ANDROID_HEIGHT_M * 0.45
	var torso_height: float = ANDROID_HEIGHT_M * 0.35
	var leg_size: Vector3 = Vector3(0.1, leg_height, 0.12)
	_add_box(android, "LegLeft", Vector3(-0.09, leg_height * 0.5, 0.0), leg_size, body)
	_add_box(android, "LegRight", Vector3(0.09, leg_height * 0.5, 0.0), leg_size, body)
	_add_box(
		android, "Torso", Vector3(0.0, leg_height + torso_height * 0.5, 0.0),
		Vector3(0.36, torso_height, 0.2), body
	)
	_add_box(
		android, "ArmLeft", Vector3(-0.24, leg_height + torso_height * 0.45, 0.06),
		Vector3(0.08, torso_height * 0.9, 0.08), body
	)
	_add_box(
		android, "ArmRight", Vector3(0.24, leg_height + torso_height * 0.45, 0.06),
		Vector3(0.08, torso_height * 0.9, 0.08), body
	)
	var head_mesh: SphereMesh = SphereMesh.new()
	head_mesh.radius = 0.12
	head_mesh.height = 0.24
	var head_y: float = leg_height + torso_height + 0.14
	_add_mesh(android, "Head", head_mesh, Vector3(0.0, head_y, 0.0), body)
	_add_box(android, "Eyes", Vector3(0.0, head_y + 0.02, -0.11), Vector3(0.14, 0.03, 0.02), eye)
	return android


## 毛の加工機 1 台 (箱・毛を入れる口・出てくる口) を足元を原点にして組み立てる
static func build_processor() -> Node3D:
	var processor: Node3D = Node3D.new()
	processor.name = "HairProcessor"
	var dark: StandardMaterial3D = _material(COCKPIT_COLOR, 0.7)
	_add_box(
		processor, "Body", Vector3(0.0, PROCESSOR_SIZE_M.y * 0.5, 0.0), PROCESSOR_SIZE_M,
		_material(PROCESSOR_COLOR, 0.5)
	)
	_add_box(
		processor, "Hopper", Vector3(0.0, PROCESSOR_SIZE_M.y + 0.06, 0.0),
		Vector3(PROCESSOR_SIZE_M.x * 0.6, 0.12, PROCESSOR_SIZE_M.z * 0.6), dark
	)
	_add_box(
		processor, "Outlet", Vector3(0.0, 0.12, -PROCESSOR_SIZE_M.z * 0.5 - 0.04),
		Vector3(PROCESSOR_SIZE_M.x * 0.5, 0.1, 0.08), dark
	)
	return processor


## 毛を運ぶダンプカー (運転台・荷台・車輪) を、前を -Z に向けて足元を原点にして組み立てる
static func build_dump_truck() -> Node3D:
	var truck: Node3D = Node3D.new()
	truck.name = "DumpTruck"
	var tire: StandardMaterial3D = _material(Color(0.08, 0.08, 0.08), 0.9)
	_add_box(
		truck, "Cab", Vector3(0.0, 1.0, -1.3), Vector3(1.6, 1.3, 1.0),
		_material(WORK_VEHICLE_COLOR, 0.5)
	)
	_add_box(
		truck, "Bed", Vector3(0.0, 1.0, 0.6), Vector3(1.8, 0.9, 2.6), _material(DUMP_BED_COLOR, 0.6)
	)
	_add_box(truck, "Chassis", Vector3(0.0, 0.45, -0.2), Vector3(1.6, 0.25, 4.0), tire)
	# 屋敷の外には地面が無いため、停める所の舗装を敷いて宙に浮いて見えないようにする
	_add_box(
		truck, "ParkingPad", Vector3(0.0, -0.025, -0.2), Vector3(3.0, 0.05, 5.4),
		_material(Color(0.4, 0.4, 0.42), 0.9)
	)
	var wheel_mesh: CylinderMesh = CylinderMesh.new()
	wheel_mesh.top_radius = 0.4
	wheel_mesh.bottom_radius = 0.4
	wheel_mesh.height = 0.3
	var wheel_index: int = 0
	for wheel_z: float in [-1.3, 1.2]:
		for wheel_x: float in [-0.85, 0.85]:
			var wheel: MeshInstance3D = _add_mesh(
				truck, "Wheel%d" % wheel_index, wheel_mesh, Vector3(wheel_x, 0.4, wheel_z), tire
			)
			wheel.rotation_degrees = Vector3(0.0, 0.0, 90.0)
			wheel_index += 1
	return truck


## 色と粗さから不透明なマテリアルを作る
static func _material(albedo: Color, roughness_value: float) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = albedo
	material.roughness = roughness_value
	return material


## 親に箱を足す
static func _add_box(
	parent: Node3D, node_name: String, local_position: Vector3, box_size: Vector3, material: Material
) -> MeshInstance3D:
	var box: BoxMesh = BoxMesh.new()
	box.size = box_size
	return _add_mesh(parent, node_name, box, local_position, material)


## 親にメッシュを足す (影は落とさない。大型の道具の影が部屋の毛を隠さないため)
static func _add_mesh(
	parent: Node3D, node_name: String, mesh: Mesh, local_position: Vector3, material: Material
) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.position = local_position
	parent.add_child(instance)
	return instance

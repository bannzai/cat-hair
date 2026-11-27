class_name MansionWorld
extends Node3D
## MansionLayout と BuildingProgress を受け取り、屋敷 1 階の 3D 空間と、表面ごとの毛 (HairField) を構築する。

## 屋敷レイアウト型スクリプト
const MansionLayoutScript := preload("res://scripts/mansion/mansion_layout.gd")
## 屋敷ビルダーロジックスクリプト
const MansionBuilderScript := preload("res://scripts/mansion/mansion_builder.gd")
## 面ごとの毛データ型スクリプト
const SurfaceHairScript := preload("res://scripts/data/surface_hair.gd")
## 毛を 1 本ずつ持って描くノードのスクリプト
const HairFieldScript := preload("res://scripts/hair_field.gd")
## 人の体の部品を作る関数 (買取業者の体)
const HumanParts := preload("res://scripts/human/human_parts.gd")

## 上に物が重なり得る、床の高さの表面の種類 (物の真下に毛を置かない)
const FLOOR_LIKE_SURFACE_TYPES: Array[StringName] = [
	MansionLayoutScript.SURFACE_FLOOR, MansionLayoutScript.SURFACE_CARPET
]
## 室内補助ライト (OmniLight3D) を置く部屋数の上限。
## 出典 (Godot 4 公式ドキュメント「OpenGL 3 / GL Compatibility レンダラーの制限」):
## GL Compatibility では 1 メッシュあたり同時適用できる Omni/Spot ライト数の既定上限が 8
## (rendering/limits/opengl/max_lights_per_object = 8、DirectionalLight3D は別枠)。
## 隣室のライトが境界メッシュへ重なっても上限 8 を超えない安全余裕として 6 灯に制限する。
const MAX_ROOM_LIGHTS: int = 6
## 室内補助ライトの強度 (環境光と平行光に重ねて床と家具の立体感を出す値)
const ROOM_LIGHT_ENERGY: float = 1.6
## 室内補助ライトの到達距離倍率 (部屋幅の対角距離 sqrt(2) ≈ 1.41 まで届く値)
const ROOM_LIGHT_RANGE_MULTIPLIER: float = 1.4
## 室内補助ライトを天井面から下げて照明シェードと重ならない位置に置く距離 (m)
const ROOM_LIGHT_CEILING_OFFSET_M: float = 0.35
## 部屋の壁の厚み (m)。隣接部屋との Z-fighting を防ぐ内側オフセットの単一情報源
const WALL_THICKNESS_M: float = 0.14
## 隣接部屋の壁どうしが重ならないよう各部屋の壁を内側へ寄せる距離 (壁厚の半分)
const WALL_HALF_THICKNESS_M: float = WALL_THICKNESS_M * 0.5
## ドア開口の両脇に最低 0.3m ずつの壁柱を残すための最小合計余白 (m)
const DOOR_SIDE_WALL_MIN_TOTAL_M: float = 0.6
## ドア開口の上側にまぐさ壁を残すための最小天井余白 (m)
const DOOR_HEADER_MIN_CLEARANCE_M: float = 0.3
## ドア両脇の壁柱メッシュが潰れない最小幅 (m)
const DOOR_SIDE_MIN_WIDTH_M: float = 0.15
## ドア上のまぐさ壁メッシュが潰れない最小高さ (m)
const DOOR_HEADER_MIN_HEIGHT_M: float = 0.2
## 室内壁の下端に付ける洋館巾木の高さ (m。床と壁の境目を視認しやすくする標準寸法)
const BASEBOARD_HEIGHT_M: float = 0.18
## 巾木を壁面からわずかに張り出して立体感を出す厚み加算 (m)
const BASEBOARD_DEPTH_EXTRA_M: float = 0.03
## ドア開口を縁取る木枠の太さ (m。隣室への入口を遠目でも視認しやすい幅)
const DOOR_FRAME_WIDTH_M: float = 0.08
## ドア枠を壁面からわずかに張り出して Z-fighting を防ぐ厚み加算 (m)
const DOOR_FRAME_DEPTH_EXTRA_M: float = 0.04
## テーブル天板の厚み (m。木製テーブルとして自然な強度に見える厚み)
const TABLE_TOP_THICKNESS_M: float = 0.08
## テーブル脚が極端に短い高さで潰れないための最小脚高さ (m)
const TABLE_MIN_LEG_HEIGHT_M: float = 0.1
## テーブル四隅の脚を天板端からわずかに内側へ寄せる X 方向配置比率 (幅の半分 0.5 より内側)
const TABLE_LEG_OFFSET_X_RATIO: float = 0.42
## テーブル四隅の脚を天板端からわずかに内側へ寄せる Z 方向配置比率 (奥行の半分 0.5 より内側)
const TABLE_LEG_OFFSET_Z_RATIO: float = 0.40
## テーブル脚の断面一辺の幅 (m。天板を支える見た目として細すぎずかさばらない一般的な木製脚幅)
const TABLE_LEG_WIDTH_M: float = 0.07
## 買取業者の札の字 (Label3D は UI の theme のフォントを引かないため、日本語の字形を持つフォントを渡す)
const SIGN_FONT: Font = preload("res://assets/fonts/NotoSansJP[wght].ttf")
## 買取業者を立たせる所の、最初の部屋の西の壁からの距離 (m)
const TRADER_WEST_OFFSET_M: float = 0.8
## 買取業者を立たせる所の、最初の部屋の南の壁 (屋敷の外に面した裏口の側) からの距離 (m)。
## 床の毛を置かない壁際の帯 (MansionBuilder.FLOOR_HAIR_INSET_M の半分) に収め、真下の毛が取れなくならないようにする
const TRADER_SOUTH_OFFSET_M: float = 0.22
## 買取業者の背の高さ (m。帽子を除く頭の上まで)。人の背の高さの見当で、札がプレイヤーの目線より少し上に来る高さ。
## _build_trader_body の各部の位置と大きさは、この背の高さの大人の体の釣り合いで置いた値
const TRADER_HEIGHT_M: float = 1.6

## 屋敷全体で 1 本ずつ描く毛の本数の上限 (HairField.draw_budget に渡す。rebuild の前に変えると次の作り直しから効く。
## 計測で上限を変えて比べる scenebench が変える)
var hair_draw_budget: int = HairFieldScript.DEFAULT_DRAW_BUDGET
## 部屋ノード群の親コンテナ
var _rooms_root: Node3D = null
## 家具・布ノード群の親コンテナ
var _objects_root: Node3D = null
## 表面ごとの毛を 1 本ずつ持って描くノード (表面の並びは layout.surfaces と同じ)
var _hair_field: Node3D = null
## 室内照明ノード群の親コンテナ
var _lights_root: Node3D = null
## 構築に使ったレイアウト (毛の表面の添字から表面の定義を引く)
var _layout: MansionLayout = null
## 裏口に来る買取業者 (物の数・毛の除外範囲に数えないよう、物とは別の親に置く。衝突体は持たない)
var _trader: Node3D = null

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


## インスタンス生成時に部屋と物のマテリアルを初期化する
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

	_hair_field = HairFieldScript.new()
	_hair_field.name = "HairField"
	_hair_field.draw_budget = hair_draw_budget
	add_child(_hair_field)

	_lights_root = Node3D.new()
	_lights_root.name = "LightsRoot"
	add_child(_lights_root)

	for room_idx: int in range(layout.rooms.size()):
		_build_room_node(layout.rooms[room_idx], room_idx)

	_layout = layout
	for obj: MansionLayout.ObjectDef in layout.objects:
		_build_object_node(obj)

	_build_hairs(layout, progress)
	_build_trader(layout)


## 買取業者が立っている所 (足元) を返す。部屋が無い屋敷では原点
func get_trader_position() -> Vector3:
	return _trader.global_position if _trader != null else Vector3.ZERO


## 最初の部屋の南西の隅 (裏口の側) に買取業者を立たせる
func _build_trader(layout: MansionLayout) -> void:
	if layout.rooms.is_empty():
		return
	var room: MansionLayout.RoomDef = layout.rooms[0]
	_trader = Node3D.new()
	_trader.name = "Trader"
	add_child(_trader)
	_trader.position = room.center + Vector3(
		-room.size.x * 0.5 + TRADER_WEST_OFFSET_M, 0.0, room.size.z * 0.5 - TRADER_SOUTH_OFFSET_M
	)
	_build_trader_body(_trader)
	var sign_label: Label3D = Label3D.new()
	sign_label.name = "Sign"
	sign_label.text = "買取業者 (裏口)"
	sign_label.font = SIGN_FONT
	# 札は南の壁と平行に、部屋の中 (北) へ向けて立てる。カメラへ向ける札は南の壁のすぐ前で斜めになり、
	# 片側が壁にめり込んで字が欠けたため。幅 (約 1.1 m) の半分は西の壁までの距離に収まる
	sign_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	sign_label.rotation_degrees = Vector3(0.0, 180.0, 0.0)
	sign_label.pixel_size = 0.0025
	# 字の大きさは pixel_size と合わせて字の高さ約 12 cm (部屋の反対側からも読める大きさ)。縁取りは字の 4 分の 1 の太さで、
	# 明るい壁紙の前でも白い字が埋もれない。札は頭の上 25 cm に置き、体と重ならない
	sign_label.font_size = 48
	sign_label.outline_size = 12
	sign_label.position = Vector3(0.0, TRADER_HEIGHT_M + 0.25, 0.0)
	_trader.add_child(sign_label)


## 買取業者の体 (靴・脚・腰・胴・腕・手・首・頭・顔・髪・帽子) を、足元を原点に、顔を部屋の中 (北。局所の -Z) へ
## 向けて trader の子に組み立てる。札と同じ向きにし、部屋の中から近づくプレイヤーに正面が見えるようにする
func _build_trader_body(trader: Node3D) -> void:
	var body: Node3D = Node3D.new()
	body.name = "Body"
	trader.add_child(body)
	# 作業着の焦げ茶で、明るい壁紙と床の前で人の形が見分けられ、光沢の無い布に見える粗さ
	var jacket_material: StandardMaterial3D = _make_material(Color(0.32, 0.27, 0.2), 0.8)
	# ズボンは作業着より暗い灰色で、上着との境 (腰) が見分けられる
	var trousers_material: StandardMaterial3D = _make_material(Color(0.18, 0.18, 0.2), 0.85)
	# 靴はほぼ黒の革で、ズボンより暗く足元の形が見分けられ、少し艶のある粗さ
	var shoes_material: StandardMaterial3D = _make_material(Color(0.07, 0.06, 0.06), 0.5)
	# 肌は画面の手 (scripts/player/hand_view.gd の SKIN_COLOR) より少し日焼けした色で、焦げ茶の作業着の上で顔と手が浮いて見える
	var skin_material: StandardMaterial3D = _make_material(Color(0.86, 0.68, 0.55), 0.75)
	# 目は黒に近い色で、肌の上の小さな点として正面から見える。濡れて見えるよう少し艶を残す粗さ
	var eyes_material: StandardMaterial3D = _make_material(Color(0.05, 0.04, 0.04), 0.4)
	# 帽子は作業着と同じ系統の、一段暗い色
	var cap_material: StandardMaterial3D = _make_material(Color(0.22, 0.18, 0.13), 0.85)
	# 肩の高さ (m)。背の高さ 1.6 m の大人の肩の見当で、上腕の付け根と、左右の肩を渡す部品で同じ高さにそろえる
	var shoulder_y: float = 1.3
	for side: float in [-1.0, 1.0]:
		var side_name: String = "Left" if side < 0.0 else "Right"
		# 肘の位置。上腕の終点と前腕の始点を同じ点にして、関節が離れないようにする
		var elbow: Vector3 = Vector3(0.23 * side, 1.02, 0.01)
		HumanParts.add_box(
			body, side_name + "Shoe", Vector3(0.09 * side, 0.035, -0.03), Vector3(0.1, 0.07, 0.25),
			shoes_material, true,
		)
		HumanParts.add_limb(
			body, side_name + "Leg", Vector3(0.09 * side, 0.1, 0.0), Vector3(0.095 * side, 0.84, 0.0), 0.065,
			trousers_material, true,
		)
		# 腕は肩から少し外へ開いて下ろし、肘から先をわずかに前へ出す
		HumanParts.add_limb(
			body, side_name + "UpperArm", Vector3(0.2 * side, shoulder_y, 0.0), elbow, 0.048,
			jacket_material, true,
		)
		HumanParts.add_limb(
			body, side_name + "Forearm", elbow, Vector3(0.22 * side, 0.78, -0.03), 0.042,
			jacket_material, true,
		)
		HumanParts.add_sphere(
			body, side_name + "Hand", Vector3(0.22 * side, 0.72, -0.035), 0.5,
			Vector3(0.05, 0.1, 0.08), skin_material, true,
		)
		HumanParts.add_sphere(
			body, side_name + "Eye", Vector3(0.035 * side, 1.51, -0.086), 0.012, Vector3.ONE,
			eyes_material, false,
		)
		HumanParts.add_sphere(
			body, side_name + "Ear", Vector3(0.086 * side, 1.49, 0.0), 0.5,
			Vector3(0.02, 0.05, 0.035), skin_material, false,
		)
	# 半径 0.5 の球を伸ばす部品は、倍率がそのまま幅・高さ・奥行 (m) になる
	HumanParts.add_sphere(
		body, "Hips", Vector3(0.0, 0.87, 0.0), 0.5, Vector3(0.32, 0.18, 0.2), trousers_material, true
	)
	HumanParts.add_sphere(
		body, "Torso", Vector3(0.0, 1.1, 0.0), 0.5, Vector3(0.38, 0.52, 0.23), jacket_material, true
	)
	HumanParts.add_limb(
		body, "Shoulders", Vector3(-0.17, shoulder_y, 0.0), Vector3(0.17, shoulder_y, 0.0), 0.062,
		jacket_material, true,
	)
	HumanParts.add_limb(
		body, "Neck", Vector3(0.0, 1.32, 0.0), Vector3(0.0, 1.41, 0.0), 0.045, skin_material, true
	)
	HumanParts.add_sphere(
		body, "Head", Vector3(0.0, 1.49, 0.0), 0.5, Vector3(0.17, 0.22, 0.19), skin_material, true
	)
	HumanParts.add_sphere(
		body, "Nose", Vector3(0.0, 1.475, -0.093), 0.5, Vector3(0.028, 0.04, 0.03), skin_material, false
	)
	# 髪は頭の後ろ寄りに重ね、正面からは額の上と耳の後ろだけに見せる
	HumanParts.add_sphere(
		body, "Hair", Vector3(0.0, 1.5, 0.035), 0.5, Vector3(0.17, 0.19, 0.16),
		# 髪は黒に近い焦げ茶で、肌と帽子の間で境が見え、艶の無い粗さ
		_make_material(Color(0.12, 0.09, 0.07), 0.9), true,
	)
	# 作業帽は頭の上半分にかぶせ、つばを顔の側 (-Z) へ出す
	HumanParts.add_sphere(
		body, "Cap", Vector3(0.0, 1.555, 0.005), 0.5, Vector3(0.18, 0.1, 0.2), cap_material, true
	)
	HumanParts.add_box(
		body, "CapBrim", Vector3(0.0, 1.56, -0.115), Vector3(0.15, 0.012, 0.08), cap_material, true
	)


## 構築済みの部屋ノード数を返す
func get_room_node_count() -> int:
	return _rooms_root.get_child_count() if _rooms_root != null else 0


## 構築済みの物ノード数を返す
func get_object_node_count() -> int:
	return _objects_root.get_child_count() if _objects_root != null else 0


## 構築済みの室内補助ライト数を返す
func get_room_light_count() -> int:
	return _lights_root.get_child_count() if _lights_root != null else 0


## 表面ごとの毛を持つ HairField を返す (未構築なら null)
func get_hair_field() -> Node3D:
	return _hair_field


## HairField の表面の添字に対応する表面の定義を返す (範囲外は null)
func get_surface_def(surface_index: int) -> MansionLayout.SurfaceDef:
	if _layout == null or surface_index < 0 or surface_index >= _layout.surfaces.size():
		return null
	return _layout.surfaces[surface_index]


## 指定した毛の色 (SurfaceHair の色) を返す (存在しない毛は空)
func get_hair_color_id(hair_id: int) -> StringName:
	if _hair_field == null or not _hair_field.has_hair(hair_id):
		return &""
	return SurfaceHairScript.STANDARD_COLORS[
		HairFieldScript.classify_hair_color(_hair_field.get_hair_color(hair_id))
	]


## 既存の子ノードを即時解放し、再構築時に古いノードが残らないようにする
func _clear_children() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.free()
	_rooms_root = null
	_objects_root = null
	_hair_field = null
	_lights_root = null
	_trader = null
	_layout = null


## 床・壁・家具・布の共有マテリアルを初期化する
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
		room_light.position = (
			room.center + Vector3(0.0, room_height - ROOM_LIGHT_CEILING_OFFSET_M, 0.0)
		)
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
			Vector3(0.0, BASEBOARD_HEIGHT_M * 0.5, 0.0),
			Vector3(wall_span, BASEBOARD_HEIGHT_M, WALL_THICKNESS_M + BASEBOARD_DEPTH_EXTRA_M),
			_material_baseboard,
			false,
		)
		return

	var door_width: float = minf(
		MansionLayoutScript.DOOR_WIDTH_M,
		wall_span - DOOR_SIDE_WALL_MIN_TOTAL_M,
	)
	var door_height: float = minf(
		MansionLayoutScript.DOOR_HEIGHT_M,
		wall_height - DOOR_HEADER_MIN_CLEARANCE_M,
	)
	var side_width: float = maxf(DOOR_SIDE_MIN_WIDTH_M, (wall_span - door_width) * 0.5)
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
	var header_height: float = maxf(DOOR_HEADER_MIN_HEIGHT_M, wall_height - door_height)
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
		Vector3(DOOR_FRAME_WIDTH_M, door_height, WALL_THICKNESS_M + DOOR_FRAME_DEPTH_EXTRA_M),
		_material_door_frame,
		false,
	)
	_add_static_box(
		wall_root,
		"FrameRight",
		Vector3(door_width * 0.5, door_height * 0.5, 0.0),
		Vector3(DOOR_FRAME_WIDTH_M, door_height, WALL_THICKNESS_M + DOOR_FRAME_DEPTH_EXTRA_M),
		_material_door_frame,
		false,
	)
	_add_static_box(
		wall_root,
		"FrameTop",
		Vector3(0.0, door_height, 0.0),
		Vector3(
			door_width + DOOR_FRAME_WIDTH_M,
			DOOR_FRAME_WIDTH_M,
			WALL_THICKNESS_M + DOOR_FRAME_DEPTH_EXTRA_M,
		),
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

	if obj.object_kind == MansionLayoutScript.OBJECT_CARPET:
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
	elif obj.object_kind == MansionLayoutScript.OBJECT_SOFA:
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
			Vector3(
				0.0,
				object_height * 0.68,
				object_depth * MansionBuilderScript.SOFA_BACKREST_OFFSET_RATIO,
			),
			Vector3(
				object_width,
				object_height * 0.64,
				object_depth * MansionBuilderScript.SOFA_BACKREST_DEPTH_RATIO,
			),
			_material_sofa,
			true,
		)
		_add_static_box(
			object_root,
			"ArmLeft",
			Vector3(
				-object_width * MansionBuilderScript.SOFA_ARM_OFFSET_RATIO,
				object_height * 0.48,
				0.0,
			),
			Vector3(
				object_width * MansionBuilderScript.SOFA_ARM_WIDTH_RATIO,
				object_height * 0.48,
				object_depth,
			),
			_material_sofa,
			false,
		)
		_add_static_box(
			object_root,
			"ArmRight",
			Vector3(
				object_width * MansionBuilderScript.SOFA_ARM_OFFSET_RATIO,
				object_height * 0.48,
				0.0,
			),
			Vector3(
				object_width * MansionBuilderScript.SOFA_ARM_WIDTH_RATIO,
				object_height * 0.48,
				object_depth,
			),
			_material_sofa,
			false,
		)
	elif obj.object_kind == MansionLayoutScript.OBJECT_SUIT_RACK:
		if obj.wall_mounted:
			# 玄関の北壁から上着の中心まで届く長さ。家具の縮尺と壁際の余白の両方を含む。
			var entrance: MansionLayout.RoomDef = _layout.rooms[0]
			var hook_depth: float = obj.position.z - (entrance.center.z - entrance.size.z * 0.5)
			_add_static_box(
				object_root,
				"WallHook",
				Vector3(0.0, object_height * 0.88, -hook_depth * 0.5),
				Vector3(0.045, 0.065, hook_depth),
				_material_metal,
				false,
			)
		else:
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
			MansionBuilderScript.SUIT_JACKET_CENTER_RATIO * obj.size,
			MansionBuilderScript.SUIT_JACKET_SIZE_RATIO * obj.size,
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
	elif obj.object_kind == MansionLayoutScript.OBJECT_KNIT_CHAIR:
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
			MansionBuilderScript.CHAIR_BACK_CENTER_RATIO * obj.size,
			MansionBuilderScript.CHAIR_BACK_SIZE_RATIO * obj.size,
			_material_wood,
			false,
		)
		_add_static_box(
			object_root,
			"KnitThrow",
			MansionBuilderScript.KNIT_THROW_CENTER_RATIO * obj.size,
			MansionBuilderScript.KNIT_THROW_SIZE_RATIO * obj.size,
			_material_knit,
			false,
		)
	elif obj.object_kind == MansionLayoutScript.OBJECT_SIDEBOARD:
		_add_static_box(
			object_root,
			"Cabinet",
			Vector3(0.0, object_height * 0.5, 0.0),
			Vector3(object_width, object_height, object_depth),
			_material_wood,
			true,
		)
		var top_trim_height: float = MansionBuilderScript.SIDEBOARD_TOP_TRIM_HEIGHT_M
		_add_static_box(
			object_root,
			"TopTrim",
			Vector3(0.0, object_height + top_trim_height * 0.5, 0.0),
			Vector3(object_width + 0.05, top_trim_height, object_depth + 0.05),
			_material_door_frame,
			false,
		)
	else:
		_add_static_box(
			object_root,
			"TableTop",
			Vector3(0.0, object_height - TABLE_TOP_THICKNESS_M * 0.5, 0.0),
			Vector3(object_width, TABLE_TOP_THICKNESS_M, object_depth),
			_material_wood,
			true,
		)
		var leg_height: float = maxf(TABLE_MIN_LEG_HEIGHT_M, object_height - TABLE_TOP_THICKNESS_M)
		var leg_offset_x: float = object_width * TABLE_LEG_OFFSET_X_RATIO
		var leg_offset_z: float = object_depth * TABLE_LEG_OFFSET_Z_RATIO
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
				Vector3(TABLE_LEG_WIDTH_M, leg_height, TABLE_LEG_WIDTH_M),
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


## 表面ごと・色ごとの残り本数 (SurfaceHair) と同じ本数の毛を HairField に 1 本ずつ置く。
## 床とカーペットの表面では、同じ部屋のほかの物の真下 (手が届かず見えない所) に毛を置かない
func _build_hairs(layout: MansionLayout, progress: BuildingProgress) -> void:
	var counts_by_surface: Array[PackedInt32Array] = []
	for surface: MansionLayout.SurfaceDef in layout.surfaces:
		var exclusions: Array[Dictionary] = []
		if surface.surface_type in FLOOR_LIKE_SURFACE_TYPES:
			exclusions = _object_footprints_in_room(layout, surface)
		_hair_field.add_oriented_surface(
			String(surface.surface_id),
			surface.frame(),
			surface.extents,
			surface.hair_weight,
			exclusions,
		)
		var group_counts: PackedInt32Array = PackedInt32Array()
		var surface_hair: SurfaceHair = (
			progress.find_surface_hair(surface.surface_id) if progress != null else null
		)
		for color_id: StringName in SurfaceHairScript.STANDARD_COLORS:
			group_counts.append(
				surface_hair.count_for_color(color_id) if surface_hair != null else 0
			)
		counts_by_surface.append(group_counts)
	_hair_field.populate_with_group_counts(counts_by_surface)


## 表面と同じ部屋に置いた物 (その表面自身の物を除く) の床の上の占有範囲を、HairField の除外範囲の形で返す
static func _object_footprints_in_room(
	layout: MansionLayout, surface: MansionLayout.SurfaceDef
) -> Array[Dictionary]:
	var footprints: Array[Dictionary] = []
	for obj: MansionLayout.ObjectDef in layout.objects:
		if (
			obj.room_id != surface.room_id or obj.wall_mounted
			or MansionBuilderScript.object_surface_id(obj.object_id) == surface.surface_id
		):
			continue
		footprints.append({
			"inverse": Transform3D(Basis(Vector3.UP, obj.rotation_y), obj.position).affine_inverse(),
			"half": Vector2(obj.size.x * 0.5, obj.size.z * 0.5),
		})
	return footprints

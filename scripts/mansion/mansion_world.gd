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
## 物の種別ごとの既製の 3D モデルと、物の箱に合わせて置く関数
const FurnitureModels := preload("res://scripts/mansion/furniture_models.gd")
## 買取業者の体の既製の 3D モデル (OpenGameArt の CC0 の人の模型。顔の写真を単色にして書き出したもの。
## 変換は scripts/assets/convert_models.py、出典は assets/CREDITS.md)。glTF の +Z に顔を向けて立つ
const TRADER_SCENE: PackedScene = preload("res://assets/models/buyer.glb")

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
## テーブル天板の衝突体の厚み (m。木製テーブルとして自然な強度に見える厚み。モデルの天板の上面と衝突体の上面をそろえ、
## 天板の下からは毛を遮らない)
const TABLE_TOP_THICKNESS_M: float = 0.08
## 椅子に掛けたニットの、座面の前の縁から下へ垂らす長さ (物の高さに対する比率)。座面の高さ (KNIT_THROW の下端) の
## 半分ほど垂らし、掛け布が座面に乗っているだけの板に見えないようにする
const KNIT_DRAPE_LENGTH_RATIO: float = 0.2
## スーツのラックの柱の太さ (m)。家庭用の金属のハンガーラックの柱 (径 2.5〜3 cm) の見当
const SUIT_RACK_POLE_WIDTH_M: float = 0.03
## スーツのラックの台の高さ (m)。床に置く金属の台の板の厚みの見当
const SUIT_RACK_BASE_HEIGHT_M: float = 0.04
## スーツの上着の袖の太さ (m)。大人の上着の袖口の幅 (13〜15 cm) より少し細い見当で、上着の前身頃の幅に比べて袖と分かる太さ
const SUIT_SLEEVE_WIDTH_M: float = 0.11
## 買取業者の札の字 (Label3D は UI の theme のフォントを引かないため、日本語の字形を持つフォントを渡す)
const SIGN_FONT: Font = preload("res://assets/fonts/NotoSansJP[wght].ttf")
## 買取業者を立たせる所の、最初の部屋の西の壁からの距離 (m)
const TRADER_WEST_OFFSET_M: float = 0.8
## 買取業者を立たせる所の、最初の部屋の南の壁 (屋敷の外に面した裏口の側) からの距離 (m)。
## 床の毛を置かない壁際の帯 (MansionBuilder.FLOOR_HAIR_INSET_M の半分) に収め、真下の毛が取れなくならないようにする
const TRADER_SOUTH_OFFSET_M: float = 0.22
## 買取業者の背の高さ (m。頭の上まで)。人の背の高さの見当で、札がプレイヤーの目線より少し上に来る高さ。
## 買取業者のモデルは、全身の範囲の高さがこの値になるよう縦横の釣り合いを保って縮める
const TRADER_HEIGHT_M: float = 1.6

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
	add_child(_hair_field)

	_lights_root = Node3D.new()
	_lights_root.name = "LightsRoot"
	add_child(_lights_root)

	for room_idx: int in range(layout.rooms.size()):
		_build_room_node(layout.rooms[room_idx], room_idx)

	for obj: MansionLayout.ObjectDef in layout.objects:
		_build_object_node(obj)

	_layout = layout
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


## 買取業者の体 (TRADER_SCENE のモデル) を、足元の中心を原点に、背の高さを TRADER_HEIGHT_M にし、顔を部屋の中
## (北。局所の -Z) へ向けて trader の子に置く。札と同じ向きにし、部屋の中から近づくプレイヤーに正面が見えるようにする
func _build_trader_body(trader: Node3D) -> void:
	var body: Node3D = Node3D.new()
	body.name = "Body"
	trader.add_child(body)
	var model: Node3D = TRADER_SCENE.instantiate() as Node3D
	var bounds: AABB = FurnitureModels.merged_mesh_aabb(model)
	model.position = -FurnitureModels.bottom_center(bounds)
	body.add_child(model)
	# モデルは glTF の +Z に顔を向けるため、Y 軸で半回転して局所の -Z へ向ける
	body.basis = Basis(Vector3.UP, PI).scaled(Vector3.ONE * (TRADER_HEIGHT_M / bounds.size.y))


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


## 家具・布 1 つ分の 3D ノードを生成する。ソファ・テーブル・サイドボード・椅子は既製のモデル (FurnitureModels) を物の箱に
## 合わせて置き、衝突体だけを毛の面の高さにそろえた直方体で足す。モデルの無いカーペット・スーツのラック・椅子に掛けた
## ニットは、基本の形に写実の素材 (LookPrototypeRoom が貼る) で描く
func _build_object_node(obj: MansionLayout.ObjectDef) -> void:
	var object_root: Node3D = Node3D.new()
	object_root.name = String(obj.object_id)
	object_root.position = obj.position
	object_root.rotation.y = obj.rotation_y
	_objects_root.add_child(object_root)

	var object_width: float = obj.size.x
	var object_height: float = obj.size.y
	var object_depth: float = obj.size.z
	if FurnitureModels.has_model(obj.object_kind):
		object_root.add_child(FurnitureModels.instantiate_fitted(obj.object_kind, obj.size))

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
		# 座面より上を手前から見通せるよう、衝突体は座面 (毛の面) の高さまでの台と、背もたれの前端より後ろの板にする
		var seat_height: float = object_height * MansionBuilderScript.SOFA_SEAT_HEIGHT_RATIO
		_add_collision_box(
			object_root,
			"Seat",
			Vector3(0.0, object_height * 0.5, 0.0),
			Vector3(object_width, object_height, object_depth),
		)
		_add_collision_box(
			object_root,
			"Backrest",
			Vector3(
				0.0, object_height * 0.5, object_depth * MansionBuilderScript.SOFA_BACKREST_OFFSET_RATIO
			),
			Vector3(
				object_width, object_height, object_depth * MansionBuilderScript.SOFA_BACKREST_DEPTH_RATIO
			),
		)
	elif obj.object_kind == MansionLayoutScript.OBJECT_SUIT_RACK:
		_add_static_box(
			object_root,
			"Base",
			Vector3(0.0, SUIT_RACK_BASE_HEIGHT_M * 0.5, 0.0),
			Vector3(object_width, SUIT_RACK_BASE_HEIGHT_M, object_depth * 0.6),
			_material_metal,
			true,
		)
		_add_static_box(
			object_root,
			"Pole",
			Vector3(0.0, object_height * 0.5, 0.0),
			Vector3(SUIT_RACK_POLE_WIDTH_M, object_height, SUIT_RACK_POLE_WIDTH_M),
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
		# 上着を掛けるハンガーの横棒と、上着の左右に垂れる袖。袖は前身頃 (毛の面) の左右の外に置き、前の毛を遮らない
		var jacket_center: Vector3 = MansionBuilderScript.SUIT_JACKET_CENTER_RATIO * obj.size
		var jacket_size: Vector3 = MansionBuilderScript.SUIT_JACKET_SIZE_RATIO * obj.size
		_add_static_box(
			object_root,
			"Hanger",
			Vector3(0.0, object_height * 0.95, 0.0),
			Vector3(object_width * 0.95, SUIT_RACK_POLE_WIDTH_M, SUIT_RACK_POLE_WIDTH_M),
			_material_metal,
			false,
		)
		for side: float in [-1.0, 1.0]:
			_add_static_box(
				object_root,
				"SleeveLeft" if side < 0.0 else "SleeveRight",
				Vector3(
					side * (jacket_size.x * 0.5 + SUIT_SLEEVE_WIDTH_M * 0.5),
					jacket_center.y + jacket_size.y * 0.05,
					0.0,
				),
				Vector3(SUIT_SLEEVE_WIDTH_M, jacket_size.y * 1.1, jacket_size.z * 0.7),
				_material_suit,
				false,
			)
	elif obj.object_kind == MansionLayoutScript.OBJECT_KNIT_CHAIR:
		var throw_center: Vector3 = MansionBuilderScript.KNIT_THROW_CENTER_RATIO * obj.size
		var throw_size: Vector3 = MansionBuilderScript.KNIT_THROW_SIZE_RATIO * obj.size
		# 衝突体は掛け布の下面までの台 (座面) と、背もたれの板にする。掛け布の上面の毛を手前から遮らない
		var seat_top: float = throw_center.y - throw_size.y * 0.5
		_add_collision_box(
			object_root,
			"ChairSeat",
			Vector3(0.0, seat_top * 0.5, 0.0),
			Vector3(object_width, seat_top, object_depth),
		)
		_add_collision_box(
			object_root,
			"ChairBack",
			MansionBuilderScript.CHAIR_BACK_CENTER_RATIO * obj.size,
			MansionBuilderScript.CHAIR_BACK_SIZE_RATIO * obj.size,
		)
		_add_static_box(
			object_root, "KnitThrow", throw_center, throw_size, _material_knit, false
		)
		# 座面の前の縁から下へ垂らした掛け布の端
		var drape_length: float = object_height * KNIT_DRAPE_LENGTH_RATIO
		_add_static_box(
			object_root,
			"KnitDrape",
			Vector3(
				0.0,
				throw_center.y + throw_size.y * 0.5 - drape_length * 0.5,
				throw_center.z + throw_size.z * 0.5 + throw_size.y * 0.5,
			),
			Vector3(throw_size.x, drape_length, throw_size.y),
			_material_knit,
			false,
		)
	elif obj.object_kind == MansionLayoutScript.OBJECT_SIDEBOARD:
		_add_collision_box(
			object_root,
			"Cabinet",
			Vector3(0.0, object_height * 0.5, 0.0),
			Vector3(object_width, object_height, object_depth),
		)
	else:
		_add_collision_box(
			object_root,
			"TableTop",
			Vector3(0.0, object_height - TABLE_TOP_THICKNESS_M * 0.5, 0.0),
			Vector3(object_width, TABLE_TOP_THICKNESS_M, object_depth),
		)


## 見えない直方体の衝突体 (StaticBody3D) を親ノードへ追加する (モデルで描く物の、歩く・見通す邪魔をする範囲)
func _add_collision_box(
	parent_node: Node3D, node_name: String, box_position: Vector3, box_size: Vector3
) -> void:
	var static_body: StaticBody3D = StaticBody3D.new()
	static_body.name = node_name
	static_body.position = box_position
	var box_shape: BoxShape3D = BoxShape3D.new()
	box_shape.size = box_size
	var collision_shape: CollisionShape3D = CollisionShape3D.new()
	collision_shape.shape = box_shape
	static_body.add_child(collision_shape)
	parent_node.add_child(static_body)


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
			obj.room_id != surface.room_id
			or MansionBuilderScript.object_surface_id(obj.object_id) == surface.surface_id
		):
			continue
		footprints.append({
			"inverse": Transform3D(Basis(Vector3.UP, obj.rotation_y), obj.position).affine_inverse(),
			"half": Vector2(obj.size.x * 0.5, obj.size.z * 0.5),
		})
	return footprints

extends RefCounted
## 見た目の試作 (issue #19) の部屋・手・画面の表示の検証スイート (scripts/dev/selfcheck.gd から呼ぶ)。

## 見た目の試作の部屋のスクリプト
const LookPrototypeRoomScript := preload("res://scripts/look/look_prototype_room.gd")
## 一人称の手のスクリプト
const FirstPersonHandScript := preload("res://scripts/look/first_person_hand.gd")
## 見た目の試作の画面の表示のスクリプト
const LookPrototypeHudScript := preload("res://scripts/look/look_prototype_hud.gd")
## 開発者向け調整値データ型スクリプト
const MansionTuningScript := preload("res://scripts/data/mansion_tuning.gd")
## 屋敷レイアウト型スクリプト
const MansionLayoutScript := preload("res://scripts/mansion/mansion_layout.gd")
## 屋敷ビルダーロジックスクリプト
const MansionBuilderScript := preload("res://scripts/mansion/mansion_builder.gd")
## 3D 屋敷構築ノードスクリプト
const MansionWorldScript := preload("res://scripts/mansion/mansion_world.gd")

## 検証結果を記録する selfcheck の SceneTree 参照
var _checker: SceneTree = null


## 見た目の試作の検証をすべて実行する
static func run_all(checker: SceneTree) -> void:
	var suite: RefCounted = load("res://scripts/dev/selfcheck_look.gd").new()
	suite._checker = checker
	suite._check_room_predicates()
	suite._check_prototype_environment()
	suite._check_apply_to_first_room_only()
	suite._check_automation_props()
	suite._check_apply_edges()
	suite._check_textured_material()
	suite._check_hand_pose()
	suite._check_hud_samples()


## 部屋の範囲・描く毛の本数・窓を付ける壁の判定の境界を検証する
func _check_room_predicates() -> void:
	var room: MansionLayout.RoomDef = MansionLayoutScript.RoomDef.new()
	room.center = Vector3(10.0, 0.0, -4.0)
	room.size = Vector3(6.0, 3.2, 4.0)
	_check(
		LookPrototypeRoomScript.is_inside_room(room, Vector3(10.0, 1.5, -4.0))
		and LookPrototypeRoomScript.is_inside_room(room, Vector3(13.0, 0.0, -2.0))
		and not LookPrototypeRoomScript.is_inside_room(room, Vector3(13.01, 0.0, -4.0))
		and not LookPrototypeRoomScript.is_inside_room(room, Vector3(10.0, 0.0, -6.01)),
		"部屋の範囲の判定は壁の線上を内、1 cm 外を外とする",
	)
	var cap: int = LookPrototypeRoomScript.VISUAL_HAIR_CAP
	_check(
		LookPrototypeRoomScript.visual_hair_count(-5) == 0
		and LookPrototypeRoomScript.visual_hair_count(0) == 0
		and LookPrototypeRoomScript.visual_hair_count(321) == 321
		and LookPrototypeRoomScript.visual_hair_count(cap) == cap
		and LookPrototypeRoomScript.visual_hair_count(cap + 1) == cap,
		"1 本ずつ描く毛の本数は数えている本数 (0 未満は 0) で、上限で打ち切る",
	)
	# 期待値の配列リテラルと == で比べるため、型付きでない Array にする
	var sides: Array = []
	room.open_west = false
	sides.append(LookPrototypeRoomScript.window_wall_side(room))
	room.open_west = true
	sides.append(LookPrototypeRoomScript.window_wall_side(room))
	room.open_south = true
	sides.append(LookPrototypeRoomScript.window_wall_side(room))
	room.open_east = true
	sides.append(LookPrototypeRoomScript.window_wall_side(room))
	room.open_north = true
	sides.append(LookPrototypeRoomScript.window_wall_side(room))
	_check(
		sides == [&"west", &"south", &"east", &"north", &""],
		"窓はドアの無い壁に西・南・東・北の順で付き、4 面ともドアなら付かない: %s" % [sides],
	)


## 試作の部屋の環境が既定の環境を変えずに、影と陰の出る値を持つことを検証する
func _check_prototype_environment() -> void:
	var base: Environment = Environment.new()
	base.ambient_light_energy = 0.78
	var prototype: Environment = LookPrototypeRoomScript.build_prototype_environment(base)
	_check(
		prototype != base
		and is_equal_approx(base.ambient_light_energy, 0.78)
		and not base.ssao_enabled
		and is_equal_approx(
			prototype.ambient_light_energy, LookPrototypeRoomScript.PROTOTYPE_AMBIENT_ENERGY
		)
		and prototype.ssao_enabled
		and prototype.tonemap_mode == Environment.TONE_MAPPER_ACES,
		"試作の環境は既定の環境の写しで、環境光を下げ、家具の陰と ACES の色調を持つ",
	)
	_check(
		LookPrototypeRoomScript.build_prototype_environment(null) != null,
		"既定の環境が無い時も試作の環境を作れる",
	)


## 最初の部屋だけに材質・影・毛を重ね、作り直しても重ねた物が 1 組のままであることを検証する
func _check_apply_to_first_room_only() -> void:
	var tuning: MansionTuning = MansionTuningScript.new()
	tuning.room_count = 2
	tuning.object_count = 6
	tuning.hair_count = 4000
	var layout: MansionLayout = MansionBuilderScript.build_layout(tuning)
	var progress: BuildingProgress = MansionBuilderScript.build_initial_progress(layout, tuning)
	var world: MansionWorld = MansionWorldScript.new()
	world.rebuild(layout, progress)
	var look_room: LookPrototypeRoom = LookPrototypeRoomScript.new()
	look_room.apply(layout, progress, world)
	look_room.apply(layout, progress, world)

	var first_room_id: StringName = layout.rooms[0].room_id
	_check(
		look_room.get_target_room_id() == first_room_id
		and (
			_floor_mesh(world, first_room_id).material_override
			== look_room.get_material_for_kind(&"floor")
		)
		and (
			_floor_mesh(world, layout.rooms[1].room_id).material_override
			!= look_room.get_material_for_kind(&"floor")
		),
		"試作の床の材質は最初の部屋の床だけに付き、2 部屋目の床は元の材質のまま",
	)
	# 置いた物: 最初の部屋の物のメッシュには試作の材質が付き、2 部屋目の物のメッシュには付かない
	var prototype_materials: Array = []
	for kind: StringName in LookPrototypeRoomScript.NODE_MATERIAL_KINDS.values():
		prototype_materials.append(look_room.get_material_for_kind(kind))
	var first_room_object_overridden: int = 0
	var other_room_object_overridden: int = 0
	for obj: MansionLayout.ObjectDef in layout.objects:
		for mesh: MeshInstance3D in _meshes_under(
			world.get_node("ObjectsRoot/%s" % String(obj.object_id))
		):
			if prototype_materials.has(mesh.material_override):
				if obj.room_id == first_room_id:
					first_room_object_overridden += 1
				else:
					other_room_object_overridden += 1
	_check(
		first_room_object_overridden > 0 and other_room_object_overridden == 0,
		"試作の材質は最初の部屋に置いた物だけに付く (最初の部屋 %d / ほかの部屋 %d)"
		% [first_room_object_overridden, other_room_object_overridden],
	)
	_check(
		(world.get_node("LightsRoot/RoomLight_0") as OmniLight3D).shadow_enabled
		and not (world.get_node("LightsRoot/RoomLight_1") as OmniLight3D).shadow_enabled,
		"影は最初の部屋の灯りだけに付く",
	)

	var counted_in_first_room: int = 0
	for surface: MansionLayout.SurfaceDef in layout.surfaces:
		if surface.room_id == first_room_id:
			counted_in_first_room += progress.find_surface_hair(surface.surface_id).total_count()
	_check(
		counted_in_first_room > 0
		and look_room.get_visual_hair_count() == counted_in_first_room
		and look_room.get_placed_hair_count() == counted_in_first_room,
		"上限より少ない時は、最初の部屋で数えている本数と同じ本数の毛を描く (%d / %d)"
		% [look_room.get_visual_hair_count(), counted_in_first_room],
	)
	_check(
		look_room.get_child_count() == 1,
		"2 回重ねても重ねた物 (窓・光・毛) は 1 組だけ残る (子 %d)" % look_room.get_child_count(),
	)

	look_room.apply(null, null, world)
	_check(
		look_room.get_target_room_id() == &""
		and look_room.get_child_count() == 0
		and look_room.get_visual_hair_count() == 0,
		"レイアウトが無い時は何も重ねない",
	)
	look_room.free()
	world.free()


## 掃除ロボットの置き物が 3 台並び、走った帯の床とカーペットの毛だけが消えることを検証する
func _check_automation_props() -> void:
	var look_room: LookPrototypeRoom = LookPrototypeRoomScript.new()
	_check(look_room.show_automation_props() == 0, "部屋を重ねる前は掃除ロボットを置かない")
	var tuning: MansionTuning = MansionTuningScript.new()
	tuning.room_count = 1
	tuning.object_count = 4
	tuning.hair_count = 20000
	var layout: MansionLayout = MansionBuilderScript.build_layout(tuning)
	var progress: BuildingProgress = MansionBuilderScript.build_initial_progress(layout, tuning)
	look_room.apply(layout, progress, null)
	var hair_field: Node3D = look_room.get_hair_field()
	var origins: Array[Vector3] = []
	for hair_id: int in range(look_room.get_placed_hair_count()):
		origins.append(hair_field.get_hair_transform(hair_id).origin)
	var before: int = look_room.get_visual_hair_count()
	var removed: int = look_room.show_automation_props()
	# 帯の外の毛 (家具の上・どの帯の Z 幅にも入らない・走り始めより壁側) が 1 本も消えていないことを、
	# ROBOT_LANES と部屋の寸法から帯を求め直して確かめる
	var room: MansionLayout.RoomDef = layout.rooms[0]
	var lane_start_x: float = (
		room.center.x - room.size.x * 0.5 + LookPrototypeRoomScript.ROBOT_LANE_START_MARGIN_M
	)
	var kept_outside_lanes: bool = true
	var outside_lane_count: int = 0
	# 帯の Z 幅に入る床の毛のうち、ロボットがまだ走っていない先 (ロボットの位置より +X) にあるもの。X の上限の境界の側
	var ahead_of_robot_count: int = 0
	for hair_id: int in range(origins.size()):
		var origin: Vector3 = origins[hair_id]
		var in_any_lane: bool = false
		for lane: Dictionary in LookPrototypeRoomScript.ROBOT_LANES:
			var in_lane_z: bool = (
				absf(origin.z - (room.center.z + float(lane["rz"]) * room.size.z))
				<= LookPrototypeRoomScript.ROBOT_RADIUS_M
			)
			var robot_x: float = room.center.x + float(lane["rx_end"]) * room.size.x
			if origin.y <= LookPrototypeRoomScript.ROBOT_CLEAR_MAX_Y_M and in_lane_z:
				if origin.x >= lane_start_x and origin.x <= robot_x:
					in_any_lane = true
				elif origin.x > robot_x:
					ahead_of_robot_count += 1
		if not in_any_lane:
			outside_lane_count += 1
			kept_outside_lanes = kept_outside_lanes and hair_field.has_hair(hair_id)
	_check(
		outside_lane_count > 0 and ahead_of_robot_count > 0 and kept_outside_lanes,
		(
			"帯の外の毛 %d 本 (家具の上・帯の Z 幅の外・走り始めより壁側・ロボットより先の %d 本) は 1 本も消えない"
			% [outside_lane_count, ahead_of_robot_count]
		),
	)
	_check(
		removed > 0
		and look_room.get_visual_hair_count() == before - removed
		and look_room.get_robot_count() == LookPrototypeRoomScript.ROBOT_LANES.size(),
		"掃除ロボットが %d 台並び、走った帯の毛 %d 本が描く毛から消える"
		% [look_room.get_robot_count(), removed],
	)
	_check(
		look_room.show_automation_props() == 0
		and look_room.get_robot_count() == LookPrototypeRoomScript.ROBOT_LANES.size(),
		"2 回置いても掃除ロボットは同じ台数で、消えた帯の毛は増えも減りもしない",
	)
	look_room.free()


## 描く毛の上限・部屋の無いレイアウト・進行の無い時・窓を付ける壁が無い時と西の壁に付ける時の重ね方を検証する
func _check_apply_edges() -> void:
	var look_room: LookPrototypeRoom = LookPrototypeRoomScript.new()
	var tuning: MansionTuning = MansionTuningScript.new()
	tuning.room_count = 1
	tuning.object_count = 4
	# 1 部屋の屋敷で、部屋の毛が描く毛の上限を超える本数
	tuning.hair_count = LookPrototypeRoomScript.VISUAL_HAIR_CAP + 5000
	var layout: MansionLayout = MansionBuilderScript.build_layout(tuning)
	var progress: BuildingProgress = MansionBuilderScript.build_initial_progress(layout, tuning)
	look_room.apply(layout, progress, null)
	_check(
		look_room.get_visual_hair_count() == LookPrototypeRoomScript.VISUAL_HAIR_CAP,
		"部屋で数えている毛が上限を超える時は上限の本数だけ描く (%d)" % look_room.get_visual_hair_count(),
	)

	var room: MansionLayout.RoomDef = layout.rooms[0]
	var window: Node3D = look_room.get_window_node()
	_check(
		window != null
		and LookPrototypeRoomScript.window_wall_side(room) == &"west"
		and is_equal_approx(
			window.position.x,
			room.center.x - room.size.x * 0.5 + MansionWorldScript.WALL_THICKNESS_M,
		)
		and window.basis.z.is_equal_approx(Vector3.LEFT),
		"西の壁にドアが無い時は、窓を西の壁の内側の面に部屋の内側へ向けて付ける",
	)

	look_room.apply(layout, null, null)
	_check(
		look_room.get_target_room_id() == room.room_id
		and look_room.get_hair_field() == null
		and look_room.get_visual_hair_count() == 0,
		"進行が無い時は部屋を重ねるが毛は描かない",
	)

	room.open_west = true
	room.open_south = true
	room.open_east = true
	room.open_north = true
	look_room.apply(layout, progress, null)
	_check(look_room.get_window_node() == null, "4 面ともドアの部屋には窓を付けない")

	look_room.apply(MansionLayoutScript.new(), progress, null)
	_check(
		look_room.get_target_room_id() == &"" and look_room.get_child_count() == 0,
		"部屋の無いレイアウトには何も重ねない",
	)
	look_room.free()


## 材質の凹凸は、高さの画像があり強さが正の時だけ付くことを検証する
func _check_textured_material() -> void:
	var height: Image = Image.create(4, 4, false, Image.FORMAT_RGBA8)
	var with_both: StandardMaterial3D = LookPrototypeRoomScript._make_textured_material(
		Color.WHITE, 0.5, null, height, 1.0, 1.0
	)
	_check(
		with_both.normal_enabled
		and with_both.normal_texture != null
		and not LookPrototypeRoomScript._make_textured_material(
			Color.WHITE, 0.5, null, height, 0.0, 1.0
		).normal_enabled
		and not LookPrototypeRoomScript._make_textured_material(
			Color.WHITE, 0.5, null, null, 1.0, 1.0
		).normal_enabled
		and with_both.uv1_triplanar
		and with_both.uv1_scale.is_equal_approx(Vector3.ONE),
		"凹凸は高さの画像があり強さが正の時だけ付き、テクスチャは繰り返しの長さ 1 m で 3 方向から投影する",
	)


## 手の構図の切り替えで、伸びた毛が毛をつまんでいる間だけ見えることを検証する
func _check_hand_pose() -> void:
	var hand: FirstPersonHand = FirstPersonHandScript.new()
	var idle_visible: bool = hand.is_stretched_hair_visible()
	hand.set_pinch_pose(true, 0.0)
	var pinch_state: Array = [hand.is_pinching(), hand.is_stretched_hair_visible()]
	hand.set_pinch_pose(false, 0.0)
	_check(
		not idle_visible
		and pinch_state == [true, true]
		and not hand.is_pinching()
		and not hand.is_stretched_hair_visible()
		and hand.position == FirstPersonHandScript.IDLE_POSITION,
		"伸びた毛は平常時に隠れ、つまんでいる間だけ見え、戻すと平常の位置に戻る",
	)
	_check(
		hand.get_stretched_hair_endpoints().is_empty(),
		"tree に入っていない手は伸びた毛の両端を返さない",
	)
	hand.free()


## 画面の表示の見本の値 (所持金・道具の枠・案内) を検証する
func _check_hud_samples() -> void:
	var look_hud: LookPrototypeHud = LookPrototypeHudScript.new()
	look_hud.set_money_digits("1,280")
	_check(
		look_hud.get_money_text() == "所持金 1,280 円"
		and look_hud.get_tool_slot_count() == LookPrototypeHudScript.SAMPLE_TOOL_NAMES.size()
		and look_hud.get_guide_text() == LookPrototypeHudScript.SAMPLE_GUIDE_TEXT,
		"画面の表示は所持金・道具の枠 %d 個・案内を出す" % look_hud.get_tool_slot_count(),
	)
	look_hud.free()


## MansionWorld が作った部屋の床のメッシュ (衝突体の子) を返す
func _floor_mesh(world: MansionWorld, room_id: StringName) -> MeshInstance3D:
	for child: Node in world.get_node("RoomsRoot/%s/Floor" % String(room_id)).get_children():
		if child is MeshInstance3D:
			return child
	return null


## node の下の MeshInstance3D をすべて返す
func _meshes_under(node: Node) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	for child: Node in node.get_children():
		if child is MeshInstance3D:
			meshes.append(child)
		meshes.append_array(_meshes_under(child))
	return meshes


## selfcheck の判定に結果を渡す
func _check(cond: bool, label: String) -> void:
	_checker._check(cond, label)

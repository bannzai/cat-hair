extends RefCounted
## 見た目の試作 (issue #19) の部屋・画面の表示の検証スイート (scripts/dev/selfcheck.gd から呼ぶ)。

## 見た目の試作の部屋のスクリプト
const LookPrototypeRoomScript := preload("res://scripts/look/look_prototype_room.gd")
## 見た目の試作の画面の表示のスクリプト
const LookPrototypeHudScript := preload("res://scripts/look/look_prototype_hud.gd")
## 開発者向け調整値データ型スクリプト
const MansionTuningScript := preload("res://scripts/data/mansion_tuning.gd")
## 屋敷レイアウト型スクリプト
const MansionLayoutScript := preload("res://scripts/mansion/mansion_layout.gd")
## 屋敷ビルダーロジックスクリプト
const MansionBuilderScript := preload("res://scripts/mansion/mansion_builder.gd")
## 一人称プレイヤーのスクリプト (tree の外のプレイヤーを作る)
const FirstPersonPlayerScript := preload("res://scripts/player/first_person_player.gd")
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
	suite._check_hud_samples()


## 部屋の範囲・窓を付ける壁の判定の境界を検証する
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


## 最初の部屋だけに材質・影を重ね、作り直しても重ねた物が 1 組のままで、屋敷の毛を増やさないことを検証する
func _check_apply_to_first_room_only() -> void:
	var tuning: MansionTuning = MansionTuningScript.new()
	tuning.room_count = 2
	tuning.object_count = 6
	tuning.hair_count = 4000
	var layout: MansionLayout = MansionBuilderScript.build_layout(tuning)
	var world: MansionWorld = MansionWorldScript.new()
	world.rebuild(layout, MansionBuilderScript.build_initial_progress(layout, tuning))
	var look_room: LookPrototypeRoom = LookPrototypeRoomScript.new()
	var world_hairs_before: int = world.get_hair_field().get_remaining_count()
	look_room.apply(layout, world)
	look_room.apply(layout, world)

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
		look_room.get_material_for_kind(&"unknown_kind") == null,
		"NODE_MATERIAL_KINDS に無い種類の材質は null を返す",
	)
	_check(
		(world.get_node("LightsRoot/RoomLight_0") as OmniLight3D).shadow_enabled
		and not (world.get_node("LightsRoot/RoomLight_1") as OmniLight3D).shadow_enabled,
		"影は最初の部屋の灯りだけに付く",
	)

	# 毛は屋敷 (MansionWorld) が描く物だけで、試作は毛を足しも消しもしない (手で毛を取る操作 #9 が数える毛と同じにするため)
	_check(
		world_hairs_before > 0
		and world.get_hair_field().get_remaining_count() == world_hairs_before
		and look_room.find_children("*", "MultiMeshInstance3D", true, false).is_empty(),
		"試作は屋敷の毛の本数を変えず、自分の毛を描かない (%d 本)" % world_hairs_before,
	)
	_check(
		look_room.get_child_count() == 1,
		"2 回重ねても重ねた物 (窓・光) は 1 組だけ残る (子 %d)" % look_room.get_child_count(),
	)

	look_room.apply(null, world)
	_check(
		look_room.get_target_room_id() == &"" and look_room.get_child_count() == 0,
		"レイアウトが無い時は何も重ねない",
	)
	look_room.free()
	world.free()


## 掃除ロボットの置き物が 3 台並び、屋敷の毛のうち走った帯の床とカーペットの毛だけが消えることを検証する
func _check_automation_props() -> void:
	var look_room: LookPrototypeRoom = LookPrototypeRoomScript.new()
	_check(look_room.show_automation_props(null) == 0, "部屋を重ねる前は掃除ロボットを置かない")
	var tuning: MansionTuning = MansionTuningScript.new()
	tuning.room_count = 1
	tuning.object_count = 4
	tuning.hair_count = 20000
	var layout: MansionLayout = MansionBuilderScript.build_layout(tuning)
	var world: MansionWorld = MansionWorldScript.new()
	world.rebuild(layout, MansionBuilderScript.build_initial_progress(layout, tuning))
	look_room.apply(layout, world)
	var hair_field: Node3D = world.get_hair_field()
	# 消す前の全部の毛の ID と根元 (消すと同じ表面の毛の位置が入れ替わるため、ID で控える)
	var origins: Dictionary = {}
	for surface_index: int in range(hair_field.get_surface_count()):
		for slot: int in range(hair_field.get_surface_visible_instance_count(surface_index)):
			var slot_hair_id: int = hair_field.get_hair_id_at_slot(surface_index, slot)
			origins[slot_hair_id] = hair_field.get_hair_transform(slot_hair_id).origin
	var before: int = hair_field.get_remaining_count()
	var removed: int = look_room.show_automation_props(hair_field)
	# 帯の外の毛 (家具の上・どの帯の Z 幅にも入らない・走り始めより壁側) が 1 本も消えていないことを、
	# ROBOT_LANES と部屋の寸法から帯を求め直して確かめる
	var room: MansionLayout.RoomDef = layout.rooms[0]
	var lane_start_x: float = (
		room.center.x - room.size.x * 0.5 + LookPrototypeRoomScript.ROBOT_LANE_START_MARGIN_M
	)
	var kept_outside_lanes: bool = true
	var outside_lane_count: int = 0
	var cleared_inside_lanes: bool = true
	var inside_lane_count: int = 0
	# 帯の Z 幅に入る床の毛のうち、ロボットがまだ走っていない先 (ロボットの位置より +X) にあるもの。X の上限の境界の側
	var ahead_of_robot_count: int = 0
	# 帯の Z 幅に入る床の毛のうち、走り始めより壁側 (-X) にあるもの。X の下限の境界の側
	var behind_start_count: int = 0
	for hair_id: int in origins:
		var origin: Vector3 = origins[hair_id]
		var in_any_lane: bool = false
		for lane: Dictionary in LookPrototypeRoomScript.ROBOT_LANES:
			var robot_x: float = room.center.x + float(lane["end_x_ratio"]) * room.size.x
			if (
				origin.y <= LookPrototypeRoomScript.ROBOT_CLEAR_MAX_Y_M
				and (
					absf(origin.z - (room.center.z + float(lane["z_ratio"]) * room.size.z))
					<= LookPrototypeRoomScript.ROBOT_RADIUS_M
				)
			):
				if origin.x >= lane_start_x and origin.x <= robot_x:
					in_any_lane = true
				elif origin.x > robot_x:
					ahead_of_robot_count += 1
				else:
					behind_start_count += 1
		if not in_any_lane:
			outside_lane_count += 1
			kept_outside_lanes = kept_outside_lanes and hair_field.has_hair(hair_id)
		else:
			inside_lane_count += 1
			cleared_inside_lanes = cleared_inside_lanes and not hair_field.has_hair(hair_id)
	_check(
		inside_lane_count == removed and cleared_inside_lanes,
		"帯の中の床とカーペットの毛 %d 本は 1 本残らず消え、消えた本数 %d と同じ" % [inside_lane_count, removed],
	)
	_check(
		outside_lane_count > 0
		and ahead_of_robot_count > 0
		and behind_start_count > 0
		and kept_outside_lanes,
		(
			"帯の外の毛 %d 本 (家具の上・帯の Z 幅の外・走り始めより壁側の %d 本・ロボットより先の %d 本) は消えない"
			% [outside_lane_count, behind_start_count, ahead_of_robot_count]
		),
	)
	_check(
		removed > 0
		and hair_field.get_remaining_count() == before - removed
		and look_room.get_robot_count() == LookPrototypeRoomScript.ROBOT_LANES.size(),
		"掃除ロボットが %d 台並び、走った帯の毛 %d 本が屋敷の毛から消える"
		% [look_room.get_robot_count(), removed],
	)
	_check(
		look_room.show_automation_props(hair_field) == 0
		and look_room.get_robot_count() == LookPrototypeRoomScript.ROBOT_LANES.size(),
		"2 回置いても掃除ロボットは同じ台数で、消えた帯の毛は増えも減りもしない",
	)
	# 充電台は帯の走り始めの壁 (-X) の内側に、真ん中の帯の Z に置く
	var dock: Node3D = look_room.get_node_or_null("PrototypeContent/Robots/Dock") as Node3D
	_check(
		dock != null
		and dock.position.x < lane_start_x
		and dock.position.x > room.center.x - room.size.x * 0.5
		and is_equal_approx(
			dock.position.z,
			room.center.z + float(LookPrototypeRoomScript.ROBOT_LANES[1]["z_ratio"]) * room.size.z
		),
		"充電台は走り始めの壁際に、真ん中の帯の位置で置く (%s)"
		% [dock.position if dock != null else null],
	)
	look_room.free()
	world.free()


## 部屋の無いレイアウト・屋敷の無い時・プレイヤーの無い時・窓を付ける壁が無い時と 4 面の壁に付ける時の重ね方を検証する
func _check_apply_edges() -> void:
	var look_room: LookPrototypeRoom = LookPrototypeRoomScript.new()
	var tuning: MansionTuning = MansionTuningScript.new()
	tuning.room_count = 1
	tuning.object_count = 4
	var layout: MansionLayout = MansionBuilderScript.build_layout(tuning)

	var room: MansionLayout.RoomDef = layout.rooms[0]
	# 縦横の違う部屋にして、東西の壁は幅 (size.x)・南北の壁は奥行 (size.z) から位置を求めることを見分ける
	# (ビルダーの部屋は正方形のため、そのままでは取り違えても位置が同じになる)
	room.size = Vector3(room.size.x, room.size.y, room.size.x * 0.6)
	# 4 面それぞれで、ドアの無い壁がその面だけの時に、窓がその壁の内側の面 (壁の中心線から壁の厚み分内側)・
	# 床から WINDOW_CENTER_HEIGHT_M の高さに、部屋の内側を向いて (ローカルの +Z が部屋の外) 付くことを確かめる
	var half_x: float = room.size.x * 0.5 - MansionWorldScript.WALL_THICKNESS_M
	var half_z: float = room.size.z * 0.5 - MansionWorldScript.WALL_THICKNESS_M
	var expected_by_side: Dictionary = {
		&"west": [Vector3(-half_x, 0.0, 0.0), Vector3.LEFT],
		&"east": [Vector3(half_x, 0.0, 0.0), Vector3.RIGHT],
		&"south": [Vector3(0.0, 0.0, half_z), Vector3.BACK],
		&"north": [Vector3(0.0, 0.0, -half_z), Vector3.FORWARD],
	}
	for side: StringName in expected_by_side:
		room.open_west = side != &"west"
		room.open_south = side != &"south"
		room.open_east = side != &"east"
		room.open_north = side != &"north"
		look_room.apply(layout, null)
		var window: Node3D = look_room.get_window_node()
		var daylight: SpotLight3D = look_room.get_daylight()
		_check(
			window != null
			and window.position.is_equal_approx(
				room.center
				+ expected_by_side[side][0]
				+ Vector3(0.0, LookPrototypeRoomScript.WINDOW_CENTER_HEIGHT_M, 0.0)
			)
			and window.basis.z.is_equal_approx(expected_by_side[side][1]),
			"%s の壁だけにドアが無い時は、窓をその壁の内側の面に部屋の内側へ向けて付ける (%s)"
			% [side, window.position if window != null else null],
		)
		# 窓の光: 影を付け、部屋の内側 (窓の外向きの逆) かつ下を照らす (SpotLight3D は -Z を照らす)
		var light_direction: Vector3 = (
			-daylight.transform.basis.z if daylight != null else Vector3.ZERO
		)
		_check(
			daylight != null
			and daylight.shadow_enabled
			and light_direction.dot(-expected_by_side[side][1]) > 0.0
			and light_direction.y < 0.0,
			"%s の窓の光は影付きで、部屋の内側の下を照らす (%s)" % [side, light_direction],
		)

	# setup の前 (プレイヤーが無い) は、歩いていて部屋があっても試作の見た目を出さない
	look_room.set_playing(true)
	_check(not look_room.is_prototype_active(), "プレイヤーが無い時は試作の見た目を出さない")
	# プレイヤーが tree の外の時と、プレイヤーを解放した後は、試作の見た目を出さない
	var outside_player: FirstPersonPlayer = FirstPersonPlayerScript.new()
	var environment_node: WorldEnvironment = WorldEnvironment.new()
	look_room.setup(outside_player, environment_node)
	look_room.set_playing(true)
	var active_outside_tree: bool = look_room.is_prototype_active()
	outside_player.free()
	look_room.set_playing(true)
	_check(
		not active_outside_tree and not look_room.is_prototype_active(),
		"プレイヤーが tree の外の時と解放した後は試作の見た目を出さない",
	)
	look_room.set_playing(false)
	environment_node.free()

	look_room.apply(layout, null)
	_check(
		look_room.get_target_room_id() == room.room_id and look_room.get_window_node() != null,
		"屋敷 (MansionWorld) が無い時も、部屋の窓と光は重ねる",
	)
	_check(
		look_room.show_automation_props(null) == 0
		and look_room.get_robot_count() == LookPrototypeRoomScript.ROBOT_LANES.size(),
		"毛の無い時も掃除ロボットは置き、消える毛は 0 本",
	)

	room.open_west = true
	room.open_south = true
	room.open_east = true
	room.open_north = true
	look_room.apply(layout, null)
	_check(look_room.get_window_node() == null, "4 面ともドアの部屋には窓を付けない")

	look_room.apply(MansionLayoutScript.new(), null)
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
	# 道具の枠は「手・ピンセット・ガムテープ・粘着ローラー」の順で、手を持っている印 (2 px の明るい線) は手の枠だけに付く
	var names: Array = []
	var marked: Array = []
	for slot: Node in look_hud.get_node("ToolSlots").get_children():
		names.append((slot.get_node("ToolName") as Label).text)
		var style: StyleBoxFlat = (slot as PanelContainer).get_theme_stylebox("panel") as StyleBoxFlat
		marked.append(
			style.border_width_left == 2
			and style.border_color == LookPrototypeHudScript.SELECTED_SLOT_BORDER_COLOR
		)
	_check(
		names == ["手", "ピンセット", "ガムテープ", "粘着ローラー"]
		and marked == [true, false, false, false],
		"道具の枠の名前 %s と、手を持っている印 %s" % [names, marked],
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

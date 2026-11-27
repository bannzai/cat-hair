class_name BigToolSite
extends Node3D
## 選ばずに働く大型の道具 (アンドロイド・毛の加工機・毛を運ぶダンプカー) の、屋敷の中での働きと見た目。
## アンドロイドは ANDROID_INTERVAL_SECONDS ごとに毛のいちばん多い部屋を選び、部屋のすべての表面を掃除する
## (探し物を見分けて傷めない。ToolCatalog の damages_found_items が false)。
## 加工機は買取業者の横に並べた台数だけ置き、ダンプカーは裏口の外に停める。加工の計算は GameState.advance_time が行う。
## 本数の正は GameState で、アンドロイドが取った毛は HairField からも同じだけ減らす。

## 道具の定義
const ToolCatalogScript := preload("res://scripts/tools/tool_catalog.gd")
## 道具のルールの計算
const ToolRulesScript := preload("res://scripts/tools/tool_rules.gd")
## 大型の道具の見た目
const BigToolModelsScript := preload("res://scripts/tools/big_tool_models.gd")

## アンドロイドが 1 回掃除する間隔 (遊んだ時間の秒)。部屋を歩いて回る間に何回か掃除したと分かる長さ
const ANDROID_INTERVAL_SECONDS: float = 4.0
## アンドロイドを立たせる所の候補 (部屋の中央からの、部屋の幅・奥行に対する割合)。中央と 4 隅寄りの順に見る
const ANDROID_SPOT_RATIOS: Array[Vector2] = [
	Vector2(0.0, 0.0),
	Vector2(0.25, -0.25),
	Vector2(-0.25, -0.25),
	Vector2(0.25, 0.25),
	Vector2(-0.25, 0.25),
]
## アンドロイドを物から離す余白 (m。体の幅の半分ほど)
const ANDROID_CLEARANCE_M: float = 0.25
## 加工機を買取業者から東へ並べる時の、買取業者から 1 台目までの距離 (m。買取業者の体の幅 0.5 m と加工機の幅の半分の和に余白を足した距離)
const PROCESSOR_ROW_START_M: float = 0.8
## 加工機の台の間隔 (m。箱の幅 0.5 m に 0.1 m のすき間)
const PROCESSOR_SPACING_M: float = 0.6
## 加工機を買取業者の立つ位置から北へずらす距離 (m)。買取業者は南の壁際に立つため、加工機の箱の奥行きの半分 (0.25 m)
## ほど北へ寄せて壁にめり込まないようにした
const PROCESSOR_NORTH_OFFSET_M: float = 0.2
## ダンプカーを停める所の、買取業者からの位置 (m)。南の壁の外に車体の幅 (1.8 m) の半分以上離して置き、
## 東へずらして裏口の前をふさがないようにした (CI の撮影で壁と重ならないことを確かめた)
const DUMP_TRUCK_OFFSET_M: Vector3 = Vector3(2.0, 0.0, 3.2)

## 本数とお金の正を持つ GameState
var _game_state: Node = null
## 毛を持つ屋敷
var _world: MansionWorld = null
## アンドロイドが手で引いている毛を取る前に、引くのをやめさせるための手
var _hand: HandController = null
## アンドロイドの取りこぼしの抽選に使う乱数
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
## アンドロイドの次の掃除までにたまった時間 (秒)
var _android_elapsed: float = 0.0
## アンドロイドが最後に掃除した部屋 (掃除する前は最初の部屋)
var _android_room_id: StringName = &""
## 見た目の親 (作り直す時にまとめて消す)
var _models_root: Node3D = null
## 最後に見た目を作った時の、加工機の台数・ダンプカーとアンドロイドを持っていたか・アンドロイドのいる部屋
var _models_key: String = ""


## GameState・屋敷・手を受け取る
func setup(game_state: Node, world: MansionWorld, hand: HandController) -> void:
	_game_state = game_state
	_world = world
	_hand = hand


## 遊んだ時間を delta_seconds 秒進め、アンドロイドの掃除の時期が来た回数だけ掃除する。戻り値は取った本数の合計
func advance(delta_seconds: float) -> int:
	_android_elapsed += maxf(0.0, delta_seconds)
	var removed: int = 0
	while _android_elapsed >= ANDROID_INTERVAL_SECONDS:
		_android_elapsed -= ANDROID_INTERVAL_SECONDS
		removed += int(step_android().get("removed", 0))
	return removed


## アンドロイドに 1 回掃除させる。持っていない時と、どの部屋にも取れる毛が無い時は何も変えずに空の辞書。
## 戻り値は {"room_id": 掃除した部屋, "in_range": 部屋の本数, "removed": 取った本数}
func step_android() -> Dictionary:
	if _game_state == null or _world == null or _game_state.current_layout == null:
		return {}
	var owned: OwnedTool = _game_state.find_owned_tool(ToolCatalogScript.TOOL_ANDROID)
	if owned == null:
		return {}
	var room_id: StringName = dirtiest_room_id()
	if room_id == &"":
		return {}
	var plan: Dictionary = ToolController.plan_room_removal(
		_world, room_id, ToolCatalogScript.TOOL_ANDROID, owned.level, _rng
	)
	var removed_ids: PackedInt32Array = plan["removed_ids"]
	if _hand != null and _hand.is_pulling():
		for hair_id: int in _hand.get_pulling_ids():
			if removed_ids.has(hair_id):
				# 毛はまだ消していないため、見た目を戻して離す (cancel_pull は作り直しの時だけ使う)
				_hand.release_pull()
				break
	var removed: int = _game_state.apply_tool_sweep(
		ToolCatalogScript.TOOL_ANDROID, plan["counts_by_surface"]
	)
	if removed < 0:
		return {}
	var hair_field: Node3D = _world.get_hair_field()
	for hair_id: int in removed_ids:
		hair_field.remove_hair(hair_id)
	_game_state.requests.apply_tool(
		ToolCatalogScript.TOOL_ANDROID,
		_game_state.requests.items_on_surfaces(plan["counts_by_surface"].keys()),
	)
	_android_room_id = room_id
	refresh_models()
	return {"room_id": room_id, "in_range": int(plan["in_range"]), "removed": removed}


## 道具で取れる毛 (各表面の最後の 1 本を除いた本数の合計。ToolRules.touchable_count が最後の 1 本を残すため)
## のいちばん多い部屋を返す (同じ本数なら表の前の部屋)。どの部屋にも取れる毛が無ければ空。
## 部屋の毛の合計で選ぶと、表面ごとに 1 本ずつ残った部屋 (何も取れない) を選び続け、ほかの部屋の掃除が止まるため
func dirtiest_room_id() -> StringName:
	var hair_field: Node3D = _world.get_hair_field()
	if hair_field == null:
		return &""
	var touchable_by_room: Dictionary = {}
	for surface_index: int in range(hair_field.get_surface_count()):
		var surface_def: MansionLayout.SurfaceDef = _world.get_surface_def(surface_index)
		if surface_def == null:
			continue
		touchable_by_room[surface_def.room_id] = (
			int(touchable_by_room.get(surface_def.room_id, 0))
			+ maxi(0, hair_field.get_surface_remaining_count(surface_index) - 1)
		)
	var best_id: StringName = &""
	var best_count: int = 0
	for room: MansionLayout.RoomDef in _game_state.current_layout.rooms:
		var count: int = int(touchable_by_room.get(room.room_id, 0))
		if count > best_count:
			best_id = room.room_id
			best_count = count
	return best_id


## アンドロイドの取りこぼしの抽選の乱数のシードを設定する (検証で結果を固定するため)
func set_rng_seed(seed_value: int) -> void:
	_rng.seed = seed_value


## 進行を作り直した時に、アンドロイドの掃除までの時間と居場所を戻し、見た目を作り直す
func reset_for_new_progress() -> void:
	_android_elapsed = 0.0
	_android_room_id = &""
	_models_key = ""
	refresh_models()


## 持っている大型の道具に合わせて、加工機・ダンプカー・アンドロイドの見た目を置き直す (持ち物が変わった時だけ作り直す)
func refresh_models() -> void:
	# 置く位置を世界座標で決めるため、tree に入っていない時 (selfcheck で単体で動かす時) は置かない
	if not is_inside_tree() or _game_state == null or _world == null or _game_state.save_data == null:
		return
	var owned_tools: Array[OwnedTool] = _game_state.save_data.building_progress.owned_tools
	var processors: int = ToolRulesScript.count_owned(
		owned_tools, ToolCatalogScript.TOOL_HAIR_PROCESSOR
	)
	var has_truck: bool = (
		ToolRulesScript.count_owned(owned_tools, ToolCatalogScript.TOOL_DUMP_TRUCK) > 0
	)
	var has_android: bool = (
		ToolRulesScript.count_owned(owned_tools, ToolCatalogScript.TOOL_ANDROID) > 0
	)
	var key: String = "%d/%s/%s/%s" % [processors, has_truck, has_android, _android_room_id]
	if key == _models_key and _models_root != null:
		return
	_models_key = key
	if _models_root != null:
		remove_child(_models_root)
		_models_root.queue_free()
	_models_root = Node3D.new()
	_models_root.name = "BigToolModels"
	add_child(_models_root)
	var trader: Vector3 = _world.get_trader_position()
	for index: int in range(processors):
		var processor: Node3D = BigToolModelsScript.build_processor()
		processor.name = "HairProcessor%d" % index
		_models_root.add_child(processor)
		processor.global_position = trader + Vector3(
			PROCESSOR_ROW_START_M + PROCESSOR_SPACING_M * float(index), 0.0, -PROCESSOR_NORTH_OFFSET_M
		)
	if has_truck:
		var truck: Node3D = BigToolModelsScript.build_dump_truck()
		_models_root.add_child(truck)
		truck.global_position = trader + DUMP_TRUCK_OFFSET_M
		truck.rotation_degrees = Vector3(0.0, 90.0, 0.0)
	if has_android:
		var android: Node3D = BigToolModelsScript.build_android()
		_models_root.add_child(android)
		android.global_position = _android_position()
		android.rotation_degrees = Vector3(0.0, 180.0, 0.0)


## 見た目の親を返す (検証用。まだ作っていなければ null)
func get_models_root() -> Node3D:
	return _models_root


## アンドロイドを立たせる所を返す。最後に掃除した部屋 (掃除する前は最初の部屋) の中央と、中央から 4 隅へ部屋の 4 分の 1
## 寄った所を順に見て、物 (家具・敷物) の足元の範囲に入らない最初の所にする (家具の上に立って見えないため)。
## どこも物と重なる時は中央
func _android_position() -> Vector3:
	var layout: MansionLayout = _game_state.current_layout
	if layout.rooms.is_empty():
		return Vector3.ZERO
	var target: MansionLayout.RoomDef = layout.rooms[0]
	for room: MansionLayout.RoomDef in layout.rooms:
		if room.room_id == _android_room_id:
			target = room
	for ratio: Vector2 in ANDROID_SPOT_RATIOS:
		var spot: Vector3 = target.center + Vector3(
			target.size.x * ratio.x, 0.0, target.size.z * ratio.y
		)
		if not _is_on_object(layout, target.room_id, spot):
			return spot
	return target.center


## 部屋 room_id の物のどれかの足元の範囲 (アンドロイドの体の幅の余白を足した範囲) に spot が入るか
func _is_on_object(layout: MansionLayout, room_id: StringName, spot: Vector3) -> bool:
	for obj: MansionLayout.ObjectDef in layout.objects:
		if obj.room_id != room_id:
			continue
		var local: Vector3 = (spot - obj.position).rotated(Vector3.UP, -obj.rotation_y)
		if (
			absf(local.x) <= obj.size.x * 0.5 + ANDROID_CLEARANCE_M
			and absf(local.z) <= obj.size.z * 0.5 + ANDROID_CLEARANCE_M
		):
			return true
	return false

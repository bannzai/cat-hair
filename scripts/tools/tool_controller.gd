class_name ToolController
extends Node
## キーで選んで使う道具 (手以外の 7 つと、業務用の吸引車・建物を覆う粘着シート) を選んで使う操作。
## 1〜9・0 キーで道具を選び、つまむ操作 (左クリック / E) で使う。
## 毛を取る道具は、画面中央で狙った点の周りの毛を 1 本ずつ抽選し、取りこぼした毛はそのまま残す。
## 吸引車と粘着シートは狙いではなく今いる部屋の表面 (粘着シートは床とカーペット) にかけ、吸引車を選んでいる間は
## カメラに運転席を重ねて運転席からの眺めにする。
## かけた範囲には跡 (円盤・床一面のシート) を出し、残った割合を数字で出す。本数の正は GameState で、HairField も同じ本数だけ減らす。
## 手が選ばれている間は HandController がつまむ操作を扱い、このノードは何もしない。

## 道具を使った時 (result は use_selected_tool の戻り値)
signal tool_used(result: Dictionary)
## 選んでいる道具が変わった時
signal tool_selected(tool_id: StringName)

## 手に持って使う道具の定義
const ToolCatalogScript := preload("res://scripts/tools/tool_catalog.gd")
## 手に持って使う道具のルールの計算
const ToolRulesScript := preload("res://scripts/tools/tool_rules.gd")
## 場面名・出来事名のカタログ
const AudioCatalog := preload("res://scripts/audio/audio_catalog.gd")
## AudioManager の型解決と実行時取得用スクリプト参照
const AudioManagerScript := preload("res://scripts/audio/audio_manager.gd")
## 猫の通り道・ブラッシングの計算 (狙った猫を決める)
const CatRulesScript := preload("res://scripts/automation/cat_rules.gd")

## 見た目の試作の部屋 (部屋の中にいるかの判定を使う)
const LookPrototypeRoomScript := preload("res://scripts/look/look_prototype_room.gd")
## 状態管理 autoload スクリプト (買う物の種類の定数を使う)
const GameStateScript := preload("res://scripts/state/game_state.gd")
## 大型の道具の見た目 (運転席・床一面のシート)
const BigToolModelsScript := preload("res://scripts/tools/big_tool_models.gd")
## 毛の描画・管理 (埋もれた毛の系統の本数と、その抽選・削除を使う)
const HairFieldScript := preload("res://scripts/hair_field.gd")
## 面ごとの毛データ型スクリプト (HairColorGroup の順の色の名前を使う)
const SurfaceHairScript := preload("res://scripts/data/surface_hair.gd")

## 道具を選ぶキー (ToolCatalog.selectable_tool_ids の順に、キーボードの数字の段の左から割り当てる)
const SELECT_KEYS: Array[Key] = [
	KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0
]
## 跡の円盤の色 (半透明の水色。残った毛の白・黒・三毛と見分けやすい色)
const TRACE_COLOR: Color = Color(0.45, 0.8, 1.0, 0.28)
## 跡の円盤を表面から浮かせる距離 (m。表面と重なってちらつかないように)
const TRACE_LIFT_M: float = 0.004
## 毛を光らせるライトの色。部屋の暖かい明かりの中で照らした所が見分けられ、白・黒・三毛の毛の色を変えすぎない薄い青白
const GLOW_LIGHT_COLOR: Color = Color(0.7, 0.85, 1.0)
## 毛を光らせるライトの強さ。部屋の明かりの下でも照らした所の毛が周りより明るく見える強さ
const GLOW_LIGHT_ENERGY: float = 6.0
## 毛を光らせるライトの届く距離 (m。手の届く距離より少し遠くまで)
const GLOW_LIGHT_RANGE_M: float = 5.0
## 毛を光らせるライトの広がりの角度 (度)。画面の中央の 3 分の 1 ほどを照らし、狙う所だけが光って見える角度
const GLOW_LIGHT_ANGLE_DEG: float = 28.0

## 入力を受け付けるか (プレイ中で、画面が開いていない時だけ main が true にする)。
## 変えると運転席の表示も合わせる (タイトル・画面を開いている間は運転席を隠す)
var enabled: bool = false:
	set(value):
		enabled = value
		_sync_cockpit()
## マウスを捕捉していなくても使えるようにする (headless の検証用。HandController.allow_uncaptured_pluck と同じ扱い)
var allow_uncaptured_use: bool = false

## 本数とお金の正を持つ GameState
var _game_state: Node = null
## 毛を持つ屋敷
var _world: MansionWorld = null
## 狙いの照会に使う手 (画面中央の光線と遮りの判定を共有する)
var _hand: HandController = null
## ブラシで狙う猫の位置を照会する、猫と掃除ロボットを描くノード (set_automation で受け取る)
var _automation: AutomationController = null
## 画面中央の光線を出し、今いる部屋を求めるカメラ
var _camera: Camera3D = null
## 選んでいる道具
var _selected_tool_id: StringName = ToolCatalogScript.TOOL_HAND
## 取りこぼしの抽選に使う乱数
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
## 最後にかけた跡の円盤 (屋敷を作り直すと一緒に消える)
var _trace: MeshInstance3D = null
## 毛を光らせるライト (カメラに付ける)
var _glow_light: SpotLight3D = null
## 業務用の吸引車の運転席 (カメラに付け、吸引車を選んでいる間だけ見せる)
var _cockpit: Node3D = null
## 最後に道具を使った結果の文言
var _last_message: String = ""
## 前のフレームでつまむ操作が押されていたか (押した瞬間だけ使うため)
var _was_pressed: bool = false
## 前のフレームでマウスを捕捉していたか (捕捉する最初のクリックで道具を使わないため)
var _was_captured: bool = false


## GameState・屋敷・手・カメラを受け取り、毛を光らせるライトをカメラに付ける
func setup(game_state: Node, world: MansionWorld, hand: HandController, camera: Camera3D) -> void:
	_game_state = game_state
	_world = world
	_hand = hand
	_camera = camera
	if _cockpit == null:
		_cockpit = BigToolModelsScript.build_cockpit()
		_cockpit.visible = false
		camera.add_child(_cockpit)
	if _glow_light == null:
		_glow_light = SpotLight3D.new()
		_glow_light.name = "GlowLight"
		_glow_light.light_color = GLOW_LIGHT_COLOR
		_glow_light.light_energy = GLOW_LIGHT_ENERGY
		_glow_light.spot_range = GLOW_LIGHT_RANGE_M
		_glow_light.spot_angle = GLOW_LIGHT_ANGLE_DEG
		_glow_light.visible = false
		camera.add_child(_glow_light)


## 毎フレーム、手以外の道具を選んでいる時に、つまむ操作を押した瞬間に道具を使う
func _process(_delta: float) -> void:
	var captured: bool = (
		Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED or allow_uncaptured_use
	)
	var held: bool = Input.is_action_pressed(HandController.ACTION_PLUCK)
	# 押した瞬間は、選んでいる道具や操作できるかに関わらず入力そのものの立ち上がりで見る。
	# 手でつまむ入力を押したまま道具に持ち替えた時に、押し直していないのに道具を使わないため。
	# マウスを捕捉する最初のクリック (前のフレームでは捕捉していない) でも使わない (HandController と同じ)
	if (
		held
		and not _was_pressed
		and _was_captured
		and captured
		and enabled
		and _selected_tool_id != ToolCatalogScript.TOOL_HAND
	):
		use_selected_tool()
	_was_pressed = held
	_was_captured = captured


## 1〜9・0 キーで道具を選ぶ
func _unhandled_input(event: InputEvent) -> void:
	if not enabled or not (event is InputEventKey):
		return
	var key_event: InputEventKey = event
	if not key_event.pressed or key_event.echo:
		return
	var key_index: int = SELECT_KEYS.find(key_event.physical_keycode)
	var selectable: Array[StringName] = ToolCatalogScript.selectable_tool_ids()
	if key_index >= 0 and key_index < selectable.size():
		select_tool(selectable[key_index])


## 道具を選ぶ。キーで選ばない道具 (アンドロイド・加工機・ダンプカー) と持っていない道具は選ばずに false
## (持っていない道具は文言で買う画面を案内する)
func select_tool(tool_id: StringName) -> bool:
	if not ToolCatalogScript.selectable_tool_ids().has(tool_id):
		return false
	if not owns_tool(tool_id):
		_last_message = "%s はまだ持っていない (T で買う画面を開く)" % _tool_name(tool_id)
		tool_selected.emit(_selected_tool_id)
		return false
	_selected_tool_id = tool_id
	_last_message = ""
	if _hand != null and tool_id != ToolCatalogScript.TOOL_HAND:
		_hand.release_pull()
	_sync_cockpit()
	tool_selected.emit(_selected_tool_id)
	return true


## 進行を作り直した時 (はじめから・屋敷の作り直し) に、最初から持っている手に持ち替え、毛を光らせるライトを消す。
## 作り直した進行には前の道具が無く、点けたライトを選び直して消す手段が無くなるため。運転席も手に持ち替えると隠れる
func reset_for_new_progress() -> void:
	select_tool(ToolCatalogScript.TOOL_HAND)
	if _glow_light != null:
		_glow_light.visible = false


## 運転席からの眺めになっているか (吸引車を選んでいて、操作を受け付けている時)
func is_in_driver_seat() -> bool:
	return _cockpit != null and _cockpit.visible


## 運転席を、吸引車を選んでいて操作を受け付けている時だけ見せる。運転席に座っている間は画面の手を隠す
## (手が運転席の計器盤の上に重なって見えるため)
func _sync_cockpit() -> void:
	if _cockpit == null:
		return
	_cockpit.visible = enabled and _selected_tool_id == ToolCatalogScript.TOOL_SUCTION_TRUCK
	if _hand != null and _hand.get_hand_view() != null:
		_hand.get_hand_view().visible = not _cockpit.visible


## 道具を使える状態で持っているか (手は最初から持っている)
func owns_tool(tool_id: StringName) -> bool:
	return (
		tool_id == ToolCatalogScript.TOOL_HAND
		or (_game_state != null and _game_state.find_owned_tool(tool_id) != null)
	)


## 選んでいる道具の id を返す
func get_selected_tool_id() -> StringName:
	return _selected_tool_id


## 最後に道具を使った結果の文言を返す
func get_last_message() -> String:
	return _last_message


## 最後にかけた跡の円盤を返す (まだかけていない・屋敷を作り直した後は null)
func get_trace() -> MeshInstance3D:
	return _trace if _trace != null and is_instance_valid(_trace) else null


## 毛を光らせるライトが点いているか
func is_glow_light_on() -> bool:
	return _glow_light != null and _glow_light.visible


## 取りこぼしの抽選の乱数のシードを設定する (検証で結果を固定するため)
func set_rng_seed(seed_value: int) -> void:
	_rng.seed = seed_value


## 選んでいる道具を 1 回使う。戻り値は {"used": 使えたか, "tool_id", "message": 画面に出す文言,
## "in_range": かけた範囲の本数, "removed": 取れた本数, "missed": 取りこぼした本数}
func use_selected_tool() -> Dictionary:
	var result: Dictionary = {
		"used": false,
		"tool_id": _selected_tool_id,
		"message": "",
		"in_range": 0,
		"removed": 0,
		"missed": 0,
	}
	var tool_def: Dictionary = ToolCatalogScript.find_tool(_selected_tool_id)
	if tool_def.is_empty() or not owns_tool(_selected_tool_id):
		result["message"] = "道具を持っていない"
	else:
		match tool_def["kind"]:
			ToolCatalogScript.KIND_SWEEP:
				_use_sweep_tool(tool_def, result)
			ToolCatalogScript.KIND_ROOM, ToolCatalogScript.KIND_SHEET:
				_use_room_tool(tool_def, result)
			ToolCatalogScript.KIND_LIGHT:
				_glow_light.visible = not _glow_light.visible
				result["used"] = true
				result["message"] = (
					"毛を光らせるライトを点けた" if _glow_light.visible else "毛を光らせるライトを消した"
				)
			ToolCatalogScript.KIND_CAT:
				result.merge(brush_cat(aimed_cat_id()), true)
			_:
				result["message"] = "手はつまむ操作で使う"
	_last_message = str(result["message"])
	tool_used.emit(result)
	return result


## ブラシで猫 cat_id をブラッシングし、落ちる前の毛を在庫に入れる。cat_id が空 (狙いの先に猫がいない) か、
## 猫がブラッシングの後で休んでいる時は何も変えずに使えなかった結果を返す
func brush_cat(cat_id: StringName) -> Dictionary:
	if cat_id == &"":
		return {"used": false, "message": "ブラシをかける猫がいない (猫に近づいて狙う)"}
	var cat_name: String = _cat_name(cat_id)
	var taken: int = _game_state.automation.brush_cat(cat_id)
	if taken <= 0:
		return {"used": false, "message": "%s はブラッシングの後で休んでいる" % cat_name}
	_play_pluck_sfx()
	return {
		"used": true,
		"removed": taken,
		"message": "%s をブラッシングした: 落ちる前の毛 %d 本を在庫に入れた" % [cat_name, taken],
	}


## 猫と掃除ロボットを描くノードを受け取る (ブラシで狙う猫の位置を照会する)
func set_automation(automation: AutomationController) -> void:
	_automation = automation


## 画面中央の光線の先、手の届く距離 (HandController.REACH_M) にいて、壁・家具に遮られない猫の id (いなければ空)
func aimed_cat_id() -> StringName:
	if _automation == null or _camera == null:
		return &""
	var centers: Dictionary = _automation.cat_centers()
	var cat_id: StringName = CatRulesScript.cat_on_ray(
		centers, _camera.global_position, -_camera.global_basis.z, HandController.REACH_M
	)
	# 壁・家具の向こうの猫にはブラシが届かない (手で毛を狙う時と同じ遮りの判定)
	if cat_id != &"" and _hand != null and _hand.is_view_blocked(centers[cat_id]):
		return &""
	return cat_id


## 猫の表示名 (通り道の名前)
func _cat_name(cat_id: StringName) -> String:
	for route: Dictionary in _game_state.automation.get_cat_routes():
		if route["cat_id"] == cat_id:
			return str(route["name"])
	return String(cat_id)


## 手に持つ毛を取る道具を使う。狙いの先に毛の付く表面が無い時は、何もせずに文言だけを入れる。
## パックの道具 (掃除機) のパックが一杯で、アンドロイドを持っている時は先に交換させ、文言の先頭に交換したことを出す。
## ただし範囲に取れる毛 (ToolRules.touchable_count が 1 本以上) が無い時は交換させない (交換の値段だけ減って何も吸えないため)。
## 消耗品が尽きている時は使わずに、尽きた理由 (アンドロイドがいてもお金が足りない時はそのこと) を文言に入れる
func _use_sweep_tool(tool_def: Dictionary, result: Dictionary) -> void:
	var tool_id: StringName = tool_def["id"]
	var owned: OwnedTool = _game_state.find_owned_tool(tool_id)
	var target: Dictionary = _hand.aim_target() if _hand != null else {}
	if target.is_empty():
		result["message"] = "狙いの先に毛の付く表面が無い"
		return
	var hair_field: Node3D = _world.get_hair_field()
	# 範囲の毛を近い順に全部取る (触れる本数は ToolRules.touchable_count で後から絞る)
	var hair_ids: PackedInt32Array = hair_field.find_hairs_near(
		target["surface_index"], target["point"], float(tool_def["radius_m"]),
		hair_field.get_remaining_count()
	)
	var has_touchable: bool = (
		ToolRulesScript.touchable_count(hair_ids.size(), int(tool_def["max_hairs"])) > 0
	)
	var exchanged: bool = (
		has_touchable
		and _game_state.purchase(GameStateScript.PURCHASE_ANDROID_PACK_EXCHANGE, tool_id)
	)
	if not ToolRulesScript.can_use(tool_id, owned.consumable_count):
		result["message"] = _pack_not_exchanged_message(tool_def, has_touchable)
		return
	_use_sweep_tool_on_target(tool_def, owned, target, hair_ids, result)
	if exchanged:
		result["exchanged"] = true
		result["message"] = "アンドロイドが%sを交換した。%s" % [
			tool_def["consumable_name"], result["message"]
		]


## 消耗品が尽きていて道具を使えない時の文言を返す。パックの道具で、アンドロイドを持っている時は交換しなかった理由
## (範囲に取れる毛が無い・交換のお金が足りない) を出し、それ以外は ToolRules.consumable_empty_message の文言。
## has_touchable は狙った範囲に取れる毛があったか (無い時はアンドロイドに交換させていない)
func _pack_not_exchanged_message(tool_def: Dictionary, has_touchable: bool) -> String:
	var tool_id: StringName = tool_def["id"]
	if (
		not ToolRulesScript.refill_replaces(tool_id)
		or _game_state.find_owned_tool(ToolCatalogScript.TOOL_ANDROID) == null
	):
		return ToolRulesScript.consumable_empty_message(tool_id)
	if not has_touchable:
		return "%s の%sが一杯。範囲に取れる毛が無いので、アンドロイドは交換しなかった" % [
			tool_def["name"], tool_def["consumable_name"]
		]
	return "%s の%sが一杯。アンドロイドが交換する %d 円が足りない" % [
		tool_def["name"], tool_def["consumable_name"], int(tool_def["refill_price"])
	]


## 毛を取る道具を狙った点 target (HandController.aim_target の戻り値。空でないこと) の周りの毛 hair_ids
## (近い順) から、ToolRules.touchable_count の本数 (触れる上限まで、最後の 1 本は残す) を 1 本ずつ抽選して
## 取りこぼし以外を取る (狙いと消耗品の確認の後に呼ぶ)。触れなかった毛も範囲に残った毛なので、
## 取りこぼしの表示の分母は範囲の全部の本数にする
func _use_sweep_tool_on_target(
	tool_def: Dictionary,
	owned: OwnedTool,
	target: Dictionary,
	hair_ids: PackedInt32Array,
	result: Dictionary,
) -> void:
	var tool_id: StringName = tool_def["id"]
	var surface_def: MansionLayout.SurfaceDef = _world.get_surface_def(target["surface_index"])
	var hair_field: Node3D = _world.get_hair_field()
	var ratio: float = ToolRulesScript.miss_ratio(tool_id, owned.level, surface_def.surface_type)
	var counts_by_color: Dictionary = {}
	var removed_ids: PackedInt32Array = PackedInt32Array()
	for hair_id: int in hair_ids.slice(
		0, ToolRulesScript.touchable_count(hair_ids.size(), int(tool_def["max_hairs"]))
	):
		if ToolRulesScript.is_missed(_rng.randf(), ratio):
			continue
		var color_id: StringName = _world.get_hair_color_id(hair_id)
		counts_by_color[color_id] = int(counts_by_color.get(color_id, 0)) + 1
		removed_ids.append(hair_id)
	var removed: int = _game_state.apply_tool_sweep(
		tool_id, {surface_def.surface_id: counts_by_color}
	)
	if removed < 0:
		result["message"] = "%s をかけられない" % tool_def["name"]
		return
	for hair_id: int in removed_ids:
		hair_field.remove_hair(hair_id)
	_show_trace(target["point"], surface_def, float(tool_def["radius_m"]))
	_finish_result(tool_def, result, hair_ids.size(), removed, "")


## 部屋ごとにかける道具 (吸引車・粘着シート) を今いる部屋にかける。粘着シートは床一面にシートを敷いた跡を残す
func _use_room_tool(tool_def: Dictionary, result: Dictionary) -> void:
	var tool_id: StringName = tool_def["id"]
	var owned: OwnedTool = _game_state.find_owned_tool(tool_id)
	if not ToolRulesScript.can_use(tool_id, owned.consumable_count):
		result["message"] = ToolRulesScript.consumable_empty_message(tool_id)
		return
	var room: MansionLayout.RoomDef = current_room()
	if room == null:
		result["message"] = "%s は部屋の中で使う" % tool_def["name"]
		return
	var plan: Dictionary = plan_room_removal(_world, room.room_id, tool_id, owned.level, _rng)
	var removed: int = _game_state.apply_tool_sweep(tool_id, plan["counts_by_surface"])
	if removed < 0:
		result["message"] = "%s をかけられない" % tool_def["name"]
		return
	apply_room_removal(_world, plan)
	if tool_def["kind"] == ToolCatalogScript.KIND_SHEET:
		_show_sheet_trace(room)
	_finish_result(tool_def, result, int(plan["in_range"]), removed, room.display_name)


## 道具を使えた結果 (範囲の本数・取れた本数・取りこぼし) と文言を result に入れ、取れた時は効果音を鳴らす
func _finish_result(
	tool_def: Dictionary, result: Dictionary, in_range: int, removed: int, room_name: String
) -> void:
	var missed: int = in_range - removed
	result["used"] = true
	result["in_range"] = in_range
	result["removed"] = removed
	result["missed"] = missed
	result["message"] = (
		"%s%s: +%d 本 / 取りこぼし %d%% (%d / %d 本が残った)"
		% [
			tool_def["name"],
			" (%s)" % room_name if not room_name.is_empty() else "",
			removed,
			roundi(100.0 * float(missed) / float(in_range)) if in_range > 0 else 0,
			missed,
			in_range,
		]
	)
	if removed > 0:
		_play_pluck_sfx()


## 毛が取れた時の効果音を鳴らす
func _play_pluck_sfx() -> void:
	var audio_manager: AudioManagerScript = (
		AudioManagerScript.resolve(get_tree()) as AudioManagerScript
	)
	if audio_manager != null:
		audio_manager.play_sfx(AudioCatalog.SFX_PLUCK_HAIR)


## カメラがいる部屋を返す (どの部屋の中にもいなければ null)
func current_room() -> MansionLayout.RoomDef:
	if _game_state == null or _camera == null:
		return null
	return LookPrototypeRoomScript.room_at(_game_state.current_layout, _camera.global_position)


## 部屋ごとにかける道具 (吸引車・粘着シート・アンドロイド) を部屋 room_id に 1 回かけた時に取る毛を、HairField から抽選する。
## 道具がかかる表面 (ToolRules.covers_surface) ごとに、ToolRules.touchable_count の本数 (表面 1 つあたり max_hairs まで、
## 最後の 1 本は残す) を取りこぼしの割合で抽選する。描いている毛から先に取り、描いている毛より多く触れる時は
## 残りを埋もれた毛 (系統は埋もれた毛の本数に比例した抽選) から取る。HairField と GameState は変えない。
## 戻り値は {"counts_by_surface": surface_id -> {color -> 本数}, "removed_ids": 取る描いている毛 ID,
## "buried_by_surface": 表面の添字 -> 取る埋もれた毛の HairColorGroup ごとの本数, "in_range": かかった表面の本数}。
## HairField へは apply_room_removal で反映する
static func plan_room_removal(
	world: MansionWorld,
	room_id: StringName,
	tool_id: StringName,
	level: int,
	rng: RandomNumberGenerator,
) -> Dictionary:
	var counts_by_surface: Dictionary = {}
	var removed_ids: PackedInt32Array = PackedInt32Array()
	var buried_by_surface: Dictionary = {}
	var in_range: int = 0
	var hair_field: Node3D = world.get_hair_field()
	var tool_def: Dictionary = ToolCatalogScript.find_tool(tool_id)
	if hair_field == null or tool_def.is_empty():
		return {
			"counts_by_surface": counts_by_surface,
			"removed_ids": removed_ids,
			"buried_by_surface": buried_by_surface,
			"in_range": 0,
		}
	for surface_index: int in range(hair_field.get_surface_count()):
		var surface_def: MansionLayout.SurfaceDef = world.get_surface_def(surface_index)
		if (
			surface_def == null
			or surface_def.room_id != room_id
			or not ToolRulesScript.covers_surface(tool_id, surface_def.surface_type)
		):
			continue
		var on_surface: int = hair_field.get_surface_remaining_count(surface_index)
		in_range += on_surface
		var ratio: float = ToolRulesScript.miss_ratio(tool_id, level, surface_def.surface_type)
		var counts_by_color: Dictionary = {}
		var visible: int = hair_field.get_surface_visible_instance_count(surface_index)
		var buried_left: PackedInt32Array = HairFieldScript.buried_group_counts(hair_field, surface_index)
		var buried_taken: PackedInt32Array = PackedInt32Array()
		buried_taken.resize(HairFieldScript.HairColorGroup.size())
		for slot: int in range(ToolRulesScript.touchable_count(on_surface, int(tool_def["max_hairs"]))):
			if ToolRulesScript.is_missed(rng.randf(), ratio):
				continue
			if slot < visible:
				var hair_id: int = hair_field.get_hair_id_at_slot(surface_index, slot)
				var color_id: StringName = world.get_hair_color_id(hair_id)
				counts_by_color[color_id] = int(counts_by_color.get(color_id, 0)) + 1
				removed_ids.append(hair_id)
				continue
			var group: int = HairFieldScript.pick_buried_group(buried_left, rng)
			buried_left[group] -= 1
			buried_taken[group] += 1
			var buried_color: StringName = SurfaceHairScript.STANDARD_COLORS[group]
			counts_by_color[buried_color] = int(counts_by_color.get(buried_color, 0)) + 1
		counts_by_surface[surface_def.surface_id] = counts_by_color
		buried_by_surface[surface_index] = buried_taken
	return {
		"counts_by_surface": counts_by_surface,
		"removed_ids": removed_ids,
		"buried_by_surface": buried_by_surface,
		"in_range": in_range,
	}


## plan_room_removal の結果 plan の毛 (描いている毛と埋もれた毛) を world の HairField から消す
## (GameState に同じ本数を反映した後に呼ぶ)
static func apply_room_removal(world: MansionWorld, plan: Dictionary) -> void:
	var hair_field: Node3D = world.get_hair_field()
	# 埋もれた毛を先に消す (描いている毛を先に消すと、描き足しが計画した埋もれた毛を使ってしまい、消し切れずに残るため)
	var buried_by_surface: Dictionary = plan["buried_by_surface"]
	for surface_index: int in buried_by_surface:
		var taken: PackedInt32Array = buried_by_surface[surface_index]
		for group: int in range(taken.size()):
			HairFieldScript.remove_buried_hairs(hair_field, surface_index, group, taken[group])
	for hair_id: int in plan["removed_ids"]:
		hair_field.remove_hair(hair_id)


## 道具をかけた範囲に、表面に沿った半透明の円盤を出す (前の跡は消す)。取りこぼした毛は円盤の中に残って見える
func _show_trace(point: Vector3, surface_def: MansionLayout.SurfaceDef, radius: float) -> void:
	if get_trace() != null:
		_trace.queue_free()
	var disc: CylinderMesh = CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius
	# 厚みは浮かせる距離 (TRACE_LIFT_M) より薄くし、跡が毛の根元を隠さない。分割数は半径 0.5 m (掃除機) でも
	# 縁の角が目立たない数
	disc.height = 0.002
	disc.radial_segments = 32
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = TRACE_COLOR
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	disc.material = material
	_trace = MeshInstance3D.new()
	_trace.name = "ToolTrace"
	_trace.mesh = disc
	_trace.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world.add_child(_trace)
	var basis: Basis = surface_def.basis.orthonormalized()
	_trace.global_transform = Transform3D(basis, point + basis.y * TRACE_LIFT_M)


## 粘着シートを敷いた部屋の床一面に、半透明のシートを出す (前の跡は消す)。取りこぼした毛はシートの上に残って見える
func _show_sheet_trace(room: MansionLayout.RoomDef) -> void:
	if get_trace() != null:
		_trace.queue_free()
	_trace = BigToolModelsScript.build_floor_sheet(room)
	_world.add_child(_trace)


## 道具の表示名を返す
static func _tool_name(tool_id: StringName) -> String:
	return str(ToolCatalogScript.find_tool(tool_id).get("name", ""))

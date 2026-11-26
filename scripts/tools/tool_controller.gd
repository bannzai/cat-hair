class_name ToolController
extends Node
## 手に持って使う道具 (手以外の 7 つ) を選んで使う操作。1〜8 キーで道具を選び、つまむ操作 (左クリック / E) で使う。
## 毛を取る道具は、画面中央で狙った点の周りの毛を 1 本ずつ抽選し、取りこぼした毛はそのまま残す。
## かけた範囲には跡の円盤を出し、残った割合を数字で出す。本数の正は GameState で、HairField も同じ本数だけ減らす。
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

## 道具を選ぶキー (表の順。1 = 手 〜 8 = ブラシ)
const SELECT_KEYS: Array[Key] = [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8]
## 跡の円盤の色 (半透明の水色。残った毛の白・黒・三毛と見分けやすい色)
const TRACE_COLOR: Color = Color(0.45, 0.8, 1.0, 0.28)
## 跡の円盤を表面から浮かせる距離 (m。表面と重なってちらつかないように)
const TRACE_LIFT_M: float = 0.004
## 毛を光らせるライトの色・強さ・届く距離・広がりの角度 (度)
const GLOW_LIGHT_COLOR: Color = Color(0.7, 0.85, 1.0)
## 毛を光らせるライトの強さ
const GLOW_LIGHT_ENERGY: float = 6.0
## 毛を光らせるライトの届く距離 (m。手の届く距離より少し遠くまで)
const GLOW_LIGHT_RANGE_M: float = 5.0
## 毛を光らせるライトの広がりの角度 (度)
const GLOW_LIGHT_ANGLE_DEG: float = 28.0

## 入力を受け付けるか (プレイ中で、画面が開いていない時だけ main が true にする)
var enabled: bool = false
## マウスを捕捉していなくても使えるようにする (headless の検証用。HandController.allow_uncaptured_pluck と同じ扱い)
var allow_uncaptured_use: bool = false

## 本数とお金の正を持つ GameState
var _game_state: Node = null
## 毛を持つ屋敷
var _world: MansionWorld = null
## 狙いの照会に使う手 (画面中央の光線と遮りの判定を共有する)
var _hand: HandController = null
## 選んでいる道具
var _selected_tool_id: StringName = ToolCatalogScript.TOOL_HAND
## 取りこぼしの抽選に使う乱数
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
## 最後にかけた跡の円盤 (屋敷を作り直すと一緒に消える)
var _trace: MeshInstance3D = null
## 毛を光らせるライト (カメラに付ける)
var _glow_light: SpotLight3D = null
## 最後に道具を使った結果の文言
var _last_message: String = ""
## 前のフレームでつまむ操作が押されていたか (押した瞬間だけ使うため)
var _was_pressed: bool = false


## GameState・屋敷・手・カメラを受け取り、毛を光らせるライトをカメラに付ける
func setup(game_state: Node, world: MansionWorld, hand: HandController, camera: Camera3D) -> void:
	_game_state = game_state
	_world = world
	_hand = hand
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
	var pressed: bool = (
		enabled
		and captured
		and _selected_tool_id != ToolCatalogScript.TOOL_HAND
		and Input.is_action_pressed(HandController.ACTION_PLUCK)
	)
	if pressed and not _was_pressed:
		use_selected_tool()
	_was_pressed = pressed


## 1〜8 キーで道具を選ぶ
func _unhandled_input(event: InputEvent) -> void:
	if not enabled or not (event is InputEventKey):
		return
	var key_event: InputEventKey = event
	if not key_event.pressed or key_event.echo:
		return
	var key_index: int = SELECT_KEYS.find(key_event.physical_keycode)
	if key_index >= 0:
		select_tool(ToolCatalogScript.TOOLS[key_index]["id"])


## 道具を選ぶ。持っていない道具は選ばずに false (文言で買う画面を案内する)
func select_tool(tool_id: StringName) -> bool:
	if ToolCatalogScript.find_tool(tool_id).is_empty():
		return false
	if not owns_tool(tool_id):
		_last_message = "%s はまだ持っていない (T で買う画面を開く)" % _tool_name(tool_id)
		tool_selected.emit(_selected_tool_id)
		return false
	_selected_tool_id = tool_id
	_last_message = ""
	if _hand != null and tool_id != ToolCatalogScript.TOOL_HAND:
		_hand.release_pull()
	tool_selected.emit(_selected_tool_id)
	return true


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
			ToolCatalogScript.KIND_LIGHT:
				_glow_light.visible = not _glow_light.visible
				result["used"] = true
				result["message"] = (
					"毛を光らせるライトを点けた" if _glow_light.visible else "毛を光らせるライトを消した"
				)
			ToolCatalogScript.KIND_CAT:
				result.merge(brush_cat(null), true)
			_:
				result["message"] = "手はつまむ操作で使う"
	_last_message = str(result["message"])
	tool_used.emit(result)
	return result


## ブラシで猫をブラッシングする入口 (猫に使う所は issue #11 で繋ぐ)。cat が null の時は何も変えずに使えなかった結果を返す
func brush_cat(cat: Node3D) -> Dictionary:
	if cat == null:
		return {"used": false, "message": "ブラシをかける猫がいない"}
	return {"used": false, "message": "猫のブラッシングはまだできない"}


## 毛を取る道具を狙った点の周りにかけ、範囲内の毛を 1 本ずつ抽選して取りこぼし以外を取る
func _use_sweep_tool(tool_def: Dictionary, result: Dictionary) -> void:
	var tool_id: StringName = tool_def["id"]
	var owned: OwnedTool = _game_state.find_owned_tool(tool_id)
	if not ToolRulesScript.can_use(tool_id, owned.consumable_count):
		result["message"] = "%s の%sが無い (T で買い足す)" % [tool_def["name"], tool_def["consumable_name"]]
		return
	var target: Dictionary = _hand.aim_target() if _hand != null else {}
	if target.is_empty():
		result["message"] = "狙いの先に毛の付く表面が無い"
		return
	var surface_index: int = target["surface_index"]
	var surface_def: MansionLayout.SurfaceDef = _world.get_surface_def(surface_index)
	var hair_field: Node3D = _world.get_hair_field()
	var hair_ids: PackedInt32Array = hair_field.find_hairs_near(
		surface_index, target["point"], float(tool_def["radius_m"]), int(tool_def["max_hairs"])
	)
	var ratio: float = ToolRulesScript.miss_ratio(tool_id, owned.level, surface_def.surface_type)
	var counts_by_color: Dictionary = {}
	var removed_ids: PackedInt32Array = PackedInt32Array()
	for hair_id: int in hair_ids:
		if ToolRulesScript.is_missed(_rng.randf(), ratio):
			continue
		var color_id: StringName = _world.get_hair_color_id(hair_id)
		counts_by_color[color_id] = int(counts_by_color.get(color_id, 0)) + 1
		removed_ids.append(hair_id)
	var removed: int = _game_state.apply_tool_sweep(tool_id, surface_def.surface_id, counts_by_color)
	for hair_id: int in removed_ids:
		hair_field.remove_hair(hair_id)
	_show_trace(target["point"], surface_def, float(tool_def["radius_m"]))
	var missed: int = hair_ids.size() - removed
	result["used"] = true
	result["in_range"] = hair_ids.size()
	result["removed"] = removed
	result["missed"] = missed
	result["message"] = (
		"%s: +%d 本 / 取りこぼし %d%% (%d / %d 本が残った)"
		% [
			tool_def["name"],
			removed,
			roundi(100.0 * float(missed) / float(hair_ids.size())) if hair_ids.size() > 0 else 0,
			missed,
			hair_ids.size(),
		]
	)
	if removed > 0:
		var audio_manager: AudioManagerScript = (
			AudioManagerScript.resolve(get_tree()) as AudioManagerScript
		)
		if audio_manager != null:
			audio_manager.play_sfx(AudioCatalog.SFX_PLUCK_HAIR)


## 道具をかけた範囲に、表面に沿った半透明の円盤を出す (前の跡は消す)。取りこぼした毛は円盤の中に残って見える
func _show_trace(point: Vector3, surface_def: MansionLayout.SurfaceDef, radius: float) -> void:
	if get_trace() != null:
		_trace.queue_free()
	var disc: CylinderMesh = CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius
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


## 道具の表示名を返す
static func _tool_name(tool_id: StringName) -> String:
	return str(ToolCatalogScript.find_tool(tool_id).get("name", ""))

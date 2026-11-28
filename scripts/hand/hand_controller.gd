class_name HandController
extends Node
## 画面中央の毛を押した瞬間に取り、在庫・屋敷の残り・表示をそろえる。

## 一度の操作で取った本数と、含まれていた珍しい毛を知らせる。
signal hairs_plucked(count: int, rare_ids: Array[StringName], new_rare_ids: Array[StringName])

const HandRulesScript := preload("res://scripts/hand/hand_rules.gd")
const HairFieldScript := preload("res://scripts/hair_field.gd")
const AudioCatalog := preload("res://scripts/audio/audio_catalog.gd")
const AudioManagerScript := preload("res://scripts/audio/audio_manager.gd")

const ACTION_PLUCK: StringName = &"pluck_hair"
## 目線から床や家具に手が届く距離。
const REACH_M: float = 2.6
## 表面そのものの衝突体を遮蔽物として数えないための余裕。
const OCCLUSION_TOLERANCE_M: float = 0.06

var enabled: bool = false:
	set(value):
		enabled = value
		if not enabled and _plucked != null:
			_plucked.hide()
var allow_uncaptured_pluck: bool = false
var _camera: Camera3D
var _world: MansionWorld
var _game_state: Node
var _excluded_rids: Array[RID] = []
var _rng := RandomNumberGenerator.new()
var _plucked: MeshInstance3D
var _lift: Tween


## カメラと屋敷に結び、取った毛を短く手前に見せるメッシュを用意する。
func setup(
	camera: Camera3D, world: MansionWorld, game_state: Node, excluded_body: CollisionObject3D
) -> void:
	_camera = camera
	_world = world
	_game_state = game_state
	_excluded_rids.clear()
	if excluded_body != null:
		_excluded_rids.append(excluded_body.get_rid())
	if _plucked != null:
		return
	_plucked = MeshInstance3D.new()
	_plucked.name = "PluckedHair"
	_plucked.mesh = HairFieldScript.build_hair_mesh()
	_plucked.material_override = HairFieldScript.build_hair_material()
	_plucked.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_plucked.hide()
	_camera.add_child(_plucked)


## マウスを捕捉したプレイ中の押下だけを受け付ける。キーの自動リピートは新たな押下に含めない。
func try_pluck(event: InputEvent) -> void:
	if not enabled or not _can_use_mouse() or not event.is_action_pressed(ACTION_PLUCK):
		return
	if pluck_at(aim_target()) == 0:
		_play_sfx(AudioCatalog.SFX_BUTTON)


## 今の照準に取れる毛があるか。案内と取得処理で同じ半径を使う。
func can_pluck() -> bool:
	return enabled and _can_use_mouse() and not Input.is_action_pressed(ACTION_PLUCK) \
		and not _hairs_at(aim_target(), 1, false).is_empty()


func _can_use_mouse() -> bool:
	return Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED or allow_uncaptured_pluck


## 面の材質と器用さから、照準が毛の根元からずれてよい距離を決める。
func _hairs_at(target: Dictionary, count: int, nearest_first: bool) -> PackedInt32Array:
	if target.is_empty():
		return PackedInt32Array()
	var surface: MansionLayout.SurfaceDef = _world.get_surface_def(target["surface_index"])
	if surface == null:
		return PackedInt32Array()
	var radius: float = HandRulesScript.grab_radius(
		surface.surface_type, _game_state.get_hand_upgrade_level(HandRulesScript.UPGRADE_DEXTERITY))
	return _world.get_hair_field().find_hairs_near(
		target["surface_index"], target["point"], radius, count, nearest_first)


## 照準の位置で取れた本数を返す。1 回の押下ごとに毛が減るため、この操作は冪等でない。
func pluck_at(target: Dictionary) -> int:
	if _world == null or _game_state == null or target.is_empty():
		return 0
	var ids := _hairs_at(target, HandRulesScript.grab_count(
		_game_state.get_hand_upgrade_level(HandRulesScript.UPGRADE_GRAB_COUNT)), true)
	var field: Node3D = _world.get_hair_field()
	var surface: MansionLayout.SurfaceDef = _world.get_surface_def(target["surface_index"])
	var count: int = 0
	var rare_ids: Array[StringName] = []
	var new_rare_ids: Array[StringName] = []
	for hair_id: int in ids:
		var color_id: StringName = _world.get_hair_color_id(hair_id)
		var rare_id: StringName = HandRulesScript.roll_rare_hair(color_id, _rng.randf())
		var result: Dictionary = _game_state.pluck_hair(surface.surface_id, color_id, rare_id)
		if not result["plucked"]:
			continue
		if count == 0:
			_show_plucked(field.get_hair_color(hair_id))
		field.remove_hair(hair_id)
		count += 1
		if rare_id != &"":
			rare_ids.append(rare_id)
		if result["new_rare"]:
			new_rare_ids.append(rare_id)
	if count > 0:
		_play_sfx(AudioCatalog.SFX_PLUCK_HAIR)
		hairs_plucked.emit(count, rare_ids, new_rare_ids)
	return count


## 照準で拾った色の毛を手前に浮かせる。素早く次を取った時は最新の 1 本を見せる。
func _show_plucked(color: Color) -> void:
	if _lift != null:
		_lift.kill()
	(_plucked.material_override as StandardMaterial3D).albedo_color = color
	_plucked.rotation = Vector3(deg_to_rad(-90.0), 0.0, deg_to_rad(-35.0))
	_plucked.position = Vector3(0.0, 0.0, -0.44)
	_plucked.show()
	_lift = create_tween()
	_lift.tween_property(_plucked, "position", Vector3(0.035, 0.038, -0.28), 0.16)
	_lift.tween_interval(0.32)
	_lift.tween_callback(_plucked.hide)


func _play_sfx(event_name: String) -> void:
	var audio: AudioManagerScript = AudioManagerScript.resolve(get_tree()) as AudioManagerScript
	if audio != null:
		audio.play_sfx(event_name)


## 珍しい毛の抽選を検証で再現するためのシード。
func set_rng_seed(seed_value: int) -> void:
	_rng.seed = seed_value


## 画面中央の光線が届く範囲で最初に当たる毛の表面と点を返す。
## 壁・家具の衝突体が表面より手前で光線を遮る時と、どの表面にも当たらない時は空の辞書
func aim_target() -> Dictionary:
	if _camera == null or _world == null or _world.get_hair_field() == null:
		return {}
	var from: Vector3 = _camera.global_position
	var direction: Vector3 = -_camera.global_basis.z
	var hit: Dictionary = _world.get_hair_field().intersect_surfaces(from, direction, REACH_M)
	if hit.is_empty() or is_view_blocked(hit["point"]):
		return {}
	return hit


## カメラから target (ワールド座標) までの間を、プレイヤー以外の衝突体 (壁・家具) が target より
## OCCLUSION_TOLERANCE_M 以上手前で遮るか (カメラが無い時と物理空間が無い時は遮らない扱い)
func is_view_blocked(target: Vector3) -> bool:
	if _camera == null:
		return false
	var space: PhysicsDirectSpaceState3D = _camera.get_world_3d().direct_space_state
	if space == null:
		return false
	var from: Vector3 = _camera.global_position
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, target)
	query.exclude = _excluded_rids
	var blocker: Dictionary = space.intersect_ray(query)
	return (
		not blocker.is_empty()
		and from.distance_to(blocker["position"])
		< from.distance_to(target) - OCCLUSION_TOLERANCE_M
	)

class_name HandController
extends Node
## 画面中央で狙った毛を手でつまんで引き、抜けたら GameState と HairField を 1 本ずつ同じだけ減らす。
## 押している間だけ引き続け、離すと毛を元に戻す。引く時間は表面の種類と手の強化 (HandRules) で決まる。
## 本数の正は GameState の SurfaceHair で、HairField は見た目と狙いの照会に使う。

## 毛を抜いた時 (count = 一度に抜けた本数、rare_ids = 混じっていた珍しい毛、new_rare_ids = 図鑑に新しく載った毛)
signal hairs_plucked(count: int, rare_ids: Array[StringName], new_rare_ids: Array[StringName])
## 引いている進み具合が変わった時 (progress = 0〜1、pulling = 毛をつまんでいるか。離した・抜けた時は false)
signal pull_progress_changed(progress: float, pulling: bool)
## つまむ操作で毛を抜けなかった時 (reason = REASON_*)。画面に理由を出すために使う
signal pull_failed(reason: StringName)

## 手で毛を取る時のルールの計算
const HandRulesScript := preload("res://scripts/hand/hand_rules.gd")
## 場面名・出来事名のカタログ
const AudioCatalog := preload("res://scripts/audio/audio_catalog.gd")
## AudioManager の型解決と実行時取得用スクリプト参照
const AudioManagerScript := preload("res://scripts/audio/audio_manager.gd")
## 画面に映る手のスクリプト
const HandViewScript := preload("res://scripts/player/hand_view.gd")

## 毛をつまむ操作の入力アクション名 (project.godot の input と一致させる)
const ACTION_PLUCK: StringName = &"pluck_hair"
## 手が届く距離 (m。目線 1.55m から斜め下の床までと、目の前の家具まで)
const REACH_M: float = 2.6
## 狙った点から毛の根元までの許容距離 (m。毛の長さ 4.8cm の 2 本分弱)
const GRAB_RADIUS_M: float = 0.08
## 狙った表面より手前に壁・家具の衝突体があるとみなす距離の余裕 (m)。
## 表面そのものの衝突体 (ソファの座面・上着の前面) に当たった時は手前と扱わない
const OCCLUSION_TOLERANCE_M: float = 0.06
## 引き終える直前の毛の長さの倍率 (伸びてから抜ける見た目)。以下の見た目の倍率は、CI の撮影で
## 目線 0.9m 先の床の毛が伸びて起きたと分かる大きさにした仮の値で、実機の手応えで調整する (issue #5)
const MAX_STRETCH_RATIO: float = 2.2
## 引いている間に毛を太く見せる倍率 (1〜2 ピクセルの細さでも引いている毛が見えるように)
const PULL_WIDTH_RATIO: float = 3.0
## 引き終える時に毛の先が面の法線へ向く割合
const LIFT_TOWARD_NORMAL_RATIO: float = 0.85
## 抜けなかった理由を見分ける時に、狙いの光線の先で何かに当たるかを調べる長さ (m)。
## 最大 4x4 部屋の屋敷 (64m 四方・対角約 90m) の端まで届く長さ
const AIM_PROBE_M: float = 100.0
## 抜けなかった理由: 押したまま引いている途中で離した
const REASON_RELEASED: StringName = &"released"
## 抜けなかった理由: 狙った所の近くに毛が無い (毛の付く表面が無い所を狙った時も含む)
const REASON_NO_HAIR: StringName = &"no_hair"
## 抜けなかった理由: 狙った所が手の届く距離より遠い (引いている途中で離れすぎた時も含む)
const REASON_OUT_OF_REACH: StringName = &"out_of_reach"
## 抜けなかった理由: 狙った毛の手前に壁・家具がある
const REASON_BLOCKED: StringName = &"blocked"

## 入力を受け付けるか (プレイ中で、開発者画面・図鑑が開いていない時だけ main が true にする)
var enabled: bool = false
## マウスを捕捉していなくてもつまめるようにする (headless の検証用。視点の allow_uncaptured_look と同じ扱い)
var allow_uncaptured_pluck: bool = false

## 狙いに使うカメラ
var _camera: Camera3D = null
## 毛を持つ屋敷 (HairField と表面の定義を引く)
var _world: MansionWorld = null
## 本数の正を持つ GameState
var _game_state: Node = null
## 狙いの光線から外す衝突体 (プレイヤー自身)
var _excluded_rids: Array[RID] = []
## 画面に映る手
var _hand_view: Node3D = null
## 珍しい毛の抽選に使う乱数
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
## 今つまんでいる毛の ID (空ならつまんでいない)
var _pulling_ids: PackedInt32Array = PackedInt32Array()
## 今つまんでいる毛が乗っている表面の添字
var _pull_surface_index: int = -1
## 引き始めてからの秒数
var _pull_elapsed: float = 0.0
## 引き抜くまでの秒数
var _pull_duration: float = 1.0
## 前のフレームでつまむ操作が押されていたか (押した瞬間だけ引き始めるため)
var _was_pressed: bool = false
## 前のフレームでマウスを捕捉していたか (捕捉を始める左クリックでは引き始めないため)
var _was_captured: bool = false


## 狙いのカメラ・屋敷・GameState・光線から外す衝突体を受け取り、カメラに手を付ける
func setup(
	camera: Camera3D, world: MansionWorld, game_state: Node, excluded_body: CollisionObject3D
) -> void:
	_camera = camera
	_world = world
	_game_state = game_state
	_excluded_rids.clear()
	if excluded_body != null:
		_excluded_rids.append(excluded_body.get_rid())
	if _hand_view == null:
		_hand_view = HandViewScript.new()
		_hand_view.name = "HandView"
		_camera.add_child(_hand_view)


## 毎フレーム、つまむ操作の押下に合わせて引き始め・引き続け・離すを行い、抜けなかった時は理由を知らせる。
## 操作を止めた (画面を開いた) 時とマウスの捕捉が外れた時に離すのは、遊ぶ人が離したのではないので理由を知らせない
func _process(delta: float) -> void:
	var captured: bool = (
		Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED or allow_uncaptured_pluck
	)
	var pressed: bool = enabled and captured and Input.is_action_pressed(ACTION_PLUCK)
	if is_pulling():
		if pressed and is_pull_in_reach():
			advance_pull(delta)
		else:
			# つまんでいた毛が残っているかは、release_pull が引いている毛を忘れる前に見る
			var pulled_hair_remains: bool = _has_pulled_hair()
			release_pull()
			if pressed and pulled_hair_remains:
				pull_failed.emit(REASON_OUT_OF_REACH)
			elif not pressed and enabled and captured and pulled_hair_remains:
				pull_failed.emit(REASON_RELEASED)
	elif pressed and not _was_pressed and _was_captured:
		if not begin_pull():
			pull_failed.emit(pull_failure_reason())
	_was_pressed = pressed
	_was_captured = captured


## 画面中央の狙いで毛をつまめない理由 (REASON_*) を返す。手の届く距離に毛の表面があれば、手前に物があるか
## (REASON_BLOCKED)、近くに毛が無いか (REASON_NO_HAIR)。無ければ、光線が最初に当たる床・壁・家具が手の届く
## 距離より遠いか (REASON_OUT_OF_REACH)、何にも当たらないか届く所の壁・家具に当たるか (REASON_NO_HAIR)
func pull_failure_reason() -> StringName:
	if _camera == null or _world == null or _world.get_hair_field() == null:
		return REASON_NO_HAIR
	var from: Vector3 = _camera.global_position
	var direction: Vector3 = -_camera.global_basis.z
	var hair_field: Node3D = _world.get_hair_field()
	var surface_hit_in_reach: Dictionary = hair_field.intersect_surfaces(from, direction, REACH_M)
	if not surface_hit_in_reach.is_empty():
		return REASON_BLOCKED if is_view_blocked(surface_hit_in_reach["point"]) else REASON_NO_HAIR
	var space: PhysicsDirectSpaceState3D = _camera.get_world_3d().direct_space_state
	if space == null:
		return REASON_NO_HAIR
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		from, from + direction.normalized() * AIM_PROBE_M
	)
	query.exclude = _excluded_rids
	var obstacle_hit: Dictionary = space.intersect_ray(query)
	if not obstacle_hit.is_empty() and from.distance_to(obstacle_hit["position"]) > REACH_M:
		return REASON_OUT_OF_REACH
	return REASON_NO_HAIR


## つまんでいる毛のうち、まだ屋敷に残っている毛があるか。引いている途中に道具・自動化が同じ毛を取ると、
## 全部が無くなる (その時は届かないのではないので、届かない理由を出さない)
func _has_pulled_hair() -> bool:
	if _world == null or _world.get_hair_field() == null:
		return false
	for hair_id: int in _pulling_ids:
		if _world.get_hair_field().has_hair(hair_id):
			return true
	return false


## 抜けなかった理由 (REASON_*) を画面に出す文言を返す (知らない理由は空文字)
static func failure_message(reason: StringName) -> String:
	match reason:
		REASON_RELEASED:
			return "途中で離したので毛が戻った (抜けるまで押したままにする)"
		REASON_NO_HAIR:
			return "狙った所に毛が無い (照準の + を手の届く毛に重ねる)"
		REASON_OUT_OF_REACH:
			return "毛まで手が届かない (%.1f m 以内の毛を狙う。足元を見下ろす)" % REACH_M
		REASON_BLOCKED:
			return "手前に物があって、毛に手が届かない"
	return ""


## 画面中央の狙いの先にある毛をつまんで引き始める。つまめたら true
func begin_pull() -> bool:
	if is_pulling() or _camera == null or _world == null or _game_state == null:
		return false
	var target: Dictionary = aim_target()
	if target.is_empty():
		return false
	var surface_index: int = target["surface_index"]
	var surface_def: MansionLayout.SurfaceDef = _world.get_surface_def(surface_index)
	if surface_def == null:
		return false
	var hair_ids: PackedInt32Array = _world.get_hair_field().find_hairs_near(
		surface_index,
		target["point"],
		GRAB_RADIUS_M,
		HandRulesScript.grab_count(
			_game_state.get_hand_upgrade_level(HandRulesScript.UPGRADE_GRAB_COUNT)
		),
	)
	if hair_ids.is_empty():
		return false
	_pulling_ids = hair_ids
	_pull_surface_index = surface_index
	_pull_elapsed = 0.0
	_pull_duration = HandRulesScript.pull_seconds(
		surface_def.surface_type,
		_game_state.get_hand_upgrade_level(HandRulesScript.UPGRADE_DEXTERITY),
	)
	_show_pull(0.0)
	return true


## 引いている時間を delta 秒進め、引き抜けたら抜いた本数を返す (まだ抜けていなければ 0)
func advance_pull(delta: float) -> int:
	if not is_pulling():
		return 0
	_pull_elapsed += maxf(0.0, delta)
	var progress: float = get_pull_progress()
	if progress < 1.0:
		_show_pull(progress)
		return 0
	return _finish_pull()


## 引くのをやめ、つまんでいた毛を元の見た目に戻す
func release_pull() -> void:
	var hair_field: Node3D = _world.get_hair_field() if _world != null else null
	if hair_field != null:
		for hair_id: int in _pulling_ids:
			hair_field.set_hair_display_transform(hair_id, hair_field.get_hair_transform(hair_id))
	_reset_pull()


## 毛を作り直す前に、つまんでいる状態を見た目を戻さずに捨てる (作り直した後の毛の ID は前と別物のため)
func cancel_pull() -> void:
	_reset_pull()


## 毛をつまんで引いている途中か
func is_pulling() -> bool:
	return not _pulling_ids.is_empty()


## つまんでいる毛のどれかが、まだ手の届く距離にあるか (引いている間に歩いて離れたら離す)。
## 狙いは面の点まで REACH_M、毛はその点から GRAB_RADIUS_M 以内でつまむため、届く距離の境目で
## つまんだ毛がすぐ離れないよう、毛の根元までの距離は REACH_M + GRAB_RADIUS_M と比べる
func is_pull_in_reach() -> bool:
	if not is_pulling() or _camera == null:
		return false
	var hair_field: Node3D = _world.get_hair_field()
	for hair_id: int in _pulling_ids:
		if (
			hair_field.has_hair(hair_id)
			and hair_field.get_hair_transform(hair_id).origin.distance_to(_camera.global_position)
			<= REACH_M + GRAB_RADIUS_M
		):
			return true
	return false


## 引き抜くまでの進み具合 (0〜1) を返す
func get_pull_progress() -> float:
	if not is_pulling():
		return 0.0
	return clampf(_pull_elapsed / maxf(0.0001, _pull_duration), 0.0, 1.0)


## 引き抜くまでの秒数を返す (つまんでいない時は最後につまんだ時の値)
func get_pull_duration() -> float:
	return _pull_duration


## 今つまんでいる毛の ID を返す
func get_pulling_ids() -> PackedInt32Array:
	return _pulling_ids


## 画面に映る手のノードを返す
func get_hand_view() -> Node3D:
	return _hand_view


## 珍しい毛の抽選の乱数のシードを設定する (検証で結果を固定するため)
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


## 引いている毛を伸ばし (面の法線の向きへ起こして長く・太くする)、手の指を閉じる
func _show_pull(progress: float) -> void:
	var hair_field: Node3D = _world.get_hair_field()
	var normal: Vector3 = _world.get_surface_def(_pull_surface_index).basis.y.normalized()
	for hair_id: int in _pulling_ids:
		hair_field.set_hair_display_transform(
			hair_id, stretched_hair_transform(hair_field.get_hair_transform(hair_id), normal, progress)
		)
	if _hand_view != null:
		_hand_view.set_pull_progress(progress)
	pull_progress_changed.emit(progress, true)


## 配置時の毛の transform を、引いている進み具合 progress に合わせて伸ばした見た目の transform を返す。
## 毛の長さの向き (局所 Z) を面の法線 normal へ起こし、長さと幅を伸ばす。根元の位置は変えない
static func stretched_hair_transform(
	rest: Transform3D, normal: Vector3, progress: float
) -> Transform3D:
	var t: float = clampf(progress, 0.0, 1.0)
	var length_dir: Vector3 = rest.basis.z.normalized()
	var target_dir: Vector3 = length_dir.slerp(normal.normalized(), t * LIFT_TOWARD_NORMAL_RATIO)
	var stretched: Basis = Basis(Quaternion(length_dir, target_dir)) * rest.basis
	stretched.z *= lerpf(1.0, MAX_STRETCH_RATIO, t)
	stretched.x *= lerpf(1.0, PULL_WIDTH_RATIO, minf(1.0, t * 4.0))
	return Transform3D(stretched, rest.origin)


## 引き抜いた毛を GameState と HairField から 1 本ずつ減らし、効果音を鳴らして抜いた本数を返す
func _finish_pull() -> int:
	var hair_field: Node3D = _world.get_hair_field()
	var surface_def: MansionLayout.SurfaceDef = _world.get_surface_def(_pull_surface_index)
	var plucked: int = 0
	var rare_ids: Array[StringName] = []
	var new_rare_ids: Array[StringName] = []
	for hair_id: int in _pulling_ids:
		var color_id: StringName = _world.get_hair_color_id(hair_id)
		var rare_id: StringName = HandRulesScript.roll_rare_hair(color_id, _rng.randf())
		var result: Dictionary = _game_state.pluck_hair(surface_def.surface_id, color_id, rare_id)
		if not bool(result["plucked"]):
			hair_field.set_hair_display_transform(hair_id, hair_field.get_hair_transform(hair_id))
			continue
		hair_field.remove_hair(hair_id)
		plucked += 1
		if rare_id != &"":
			rare_ids.append(rare_id)
		if bool(result["new_rare"]):
			new_rare_ids.append(rare_id)
	_reset_pull()
	if plucked > 0:
		var audio_manager: AudioManagerScript = (
			AudioManagerScript.resolve(get_tree()) as AudioManagerScript
		)
		if audio_manager != null:
			audio_manager.play_sfx(AudioCatalog.SFX_PLUCK_HAIR)
		hairs_plucked.emit(plucked, rare_ids, new_rare_ids)
	return plucked


## つまんでいる状態を空にし、手を開いた形に戻す
func _reset_pull() -> void:
	_pulling_ids = PackedInt32Array()
	_pull_surface_index = -1
	_pull_elapsed = 0.0
	if _hand_view != null:
		_hand_view.set_pull_progress(0.0)
	pull_progress_changed.emit(0.0, false)

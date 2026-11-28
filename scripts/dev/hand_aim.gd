extends RefCounted
## 検証と撮影で、一人称の目線を手の届く毛へ向ける手順。

## 屋敷レイアウト型スクリプト (表面の種類の定数を使う)
const MansionLayoutScript := preload("res://scripts/mansion/mansion_layout.gd")
## 表面と強化に合う、手でつまめる半径。
const HandRulesScript := preload("res://scripts/hand/hand_rules.gd")
## 毛から立つ位置までの水平距離 (m。手の届く距離より十分短く、足元の毛より少し先)
const STAND_DISTANCE_M: float = 0.9
## 狙いを試す毛の本数の上限 (家具に遮られる毛を飛ばして次を試す)
const MAX_CANDIDATES: int = 40


## 床の毛を順に試し、プレイヤーをその毛から部屋の中心の向きへ STAND_DISTANCE_M 離れた所に立たせて目線を向ける。
## 画面中央の狙い (hand.aim_target) がその毛の表面に当たり、その毛をつまめる時、その毛の ID を返す。見つからなければ -1
static func aim_at_floor_hair(tree: SceneTree, main: Node3D) -> int:
	return await _aim(tree, main, MansionLayout.SURFACE_FLOOR,
		HandRulesScript.grab_radius(MansionLayout.SURFACE_FLOOR, 0), 0, false)


## 床面から 8 cm 以上積もった毛の山で、表面にある 1 本に照準を合わせる。
static func aim_at_floor_pile(tree: SceneTree, main: Node3D) -> int:
	return await _aim(
		tree, main, MansionLayout.SURFACE_FLOOR,
		HandRulesScript.grab_radius(MansionLayout.SURFACE_FLOOR, 0), 0, true, 0.08)


## aim_at_floor_hair と同じ順に床の毛を試し、狙いの点から radius の中に毛が min_hairs 本以上ある所で止める
## (道具の検証用。毛の多い屋敷では、狙いの点にいちばん近い毛が試した 1 本と限らないため)。止めた毛の ID を返し、見つからなければ -1
static func aim_at_floor_hairs(tree: SceneTree, main: Node3D, radius: float, min_hairs: int) -> int:
	return await _aim(tree, main, MansionLayout.SURFACE_FLOOR, radius, min_hairs, false)


## 最初の部屋の指定面で実際につまめる毛を照準に入れ、その ID を返す。床では最も急な見下ろし角に近づける
static func aim_at_first_room_hair(tree: SceneTree, main: Node3D, surface_type: StringName) -> int:
	return await _aim(tree, main, surface_type, HandRulesScript.grab_radius(surface_type, 0), 0, true)


## 毛を順に試して目線を向ける。min_hairs が 0 の時は試した毛そのものをつまめる所、
## 1 以上の時は radius の中に毛が min_hairs 本以上ある所で止め、試した毛の ID を返す (見つからなければ -1)
static func _aim(
	tree: SceneTree, main: Node3D, surface_type: StringName, radius: float,
	min_hairs: int, first_room: bool, min_height: float = -INF,
) -> int:
	var world: MansionWorld = main.get_node("MansionWorld")
	var player: FirstPersonPlayer = main.get_node("Player")
	var hand: HandController = main.hand
	var hair_field: Node3D = world.get_hair_field()
	var room: MansionLayout.RoomDef = main.get_game_state().current_layout.rooms[0]
	var tried: int = 0
	for surface_idx: int in range(hair_field.get_surface_count()):
		var surface: MansionLayout.SurfaceDef = world.get_surface_def(surface_idx)
		if surface == null or surface.surface_type != surface_type:
			continue
		if first_room and surface.room_id != room.room_id:
			continue
		var slot_count: int = hair_field.get_surface_visible_instance_count(surface_idx)
		for slot: int in range(slot_count):
			if tried >= MAX_CANDIDATES:
				return -1
			var hair_id: int = hair_field.get_hair_id_at_slot(surface_idx, slot)
			var root: Vector3 = hair_field.get_hair_transform(hair_id).origin
			if root.y - surface.center.y < min_height:
				continue
			tried += 1
			player.set_spawn(_stand_position(surface, root, first_room), 0.0)
			await tree.physics_frame
			await tree.physics_frame
			player.look_at_point(root)
			await tree.physics_frame
			var target: Dictionary = hand.aim_target()
			if target.is_empty() or int(target["surface_index"]) != surface_idx:
				continue
			var near: PackedInt32Array = hair_field.find_hairs_near(
				surface_idx, target["point"], radius, maxi(1, min_hairs)
			)
			if min_hairs <= 0 and near.size() == 1 and near[0] == hair_id:
				return hair_id
			if min_hairs > 0 and near.size() >= min_hairs:
				return hair_id
	return -1


## ソファは背もたれの反対側、縦の面は法線側から見る。床は家具の下を避けるため部屋の内側から試す
static func _stand_position(
	surface: MansionLayout.SurfaceDef, hair: Vector3, steep_floor: bool,
) -> Vector3:
	var direction: Vector3 = Vector3(surface.center.x - hair.x, 0.0, surface.center.z - hair.z)
	var distance: float = STAND_DISTANCE_M
	if surface.surface_type == MansionLayoutScript.SURFACE_SOFA:
		direction = surface.basis.z
	elif absf(surface.basis.y.y) < 0.01:
		direction = surface.basis.y
	elif steep_floor:
		# 真下に近い角度を保ちつつ、目線の水平成分が消えず向きが定まる 2 cm。
		distance = 0.02
	if direction.length_squared() < 0.0001:
		direction = Vector3.RIGHT
	return Vector3(hair.x, 0.0, hair.z) + direction.normalized() * distance


## 照準だけが遮られるように、カメラと対象の中間に置く検証用の衝突体。呼び出し側が回収する。
static func block_view(
	main: Node3D, camera_position: Vector3, target_point: Vector3
) -> StaticBody3D:
	var blocker: StaticBody3D = StaticBody3D.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(0.3, 0.3, 0.05)
	shape.shape = box
	blocker.add_child(shape)
	main.add_child(blocker)
	blocker.global_position = camera_position.lerp(target_point, 0.5)
	return blocker

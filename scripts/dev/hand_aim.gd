extends RefCounted
## 検証と撮影で、一人称の目線を手の届く床の毛へ向ける手順 (integration_hand.gd と screenshot.gd が使う)。

## 屋敷レイアウト型スクリプト (表面の種類の定数を使う)
const MansionLayoutScript := preload("res://scripts/mansion/mansion_layout.gd")
## 毛から立つ位置までの水平距離 (m。手の届く距離より十分短く、足元の毛より少し先)
const STAND_DISTANCE_M: float = 0.9
## 狙いを試す毛の本数の上限 (家具に遮られる毛を飛ばして次を試す)
const MAX_CANDIDATES: int = 40


## 床の毛を順に試し、プレイヤーをその毛から部屋の中心の向きへ STAND_DISTANCE_M 離れた所に立たせて目線を向ける。
## 画面中央の狙い (hand.aim_target) がその毛の表面に当たり、その毛をつまめる時、その毛の ID を返す。見つからなければ -1
static func aim_at_floor_hair(tree: SceneTree, main: Node3D) -> int:
	return await _aim_at_floor(tree, main, HandController.GRAB_RADIUS_M, 0)


## aim_at_floor_hair と同じ順に床の毛を試し、狙いの点から radius の中に毛が min_hairs 本以上ある所で止める
## (道具の検証用。毛の多い屋敷では、狙いの点にいちばん近い毛が試した 1 本と限らないため)。止めた毛の ID を返し、見つからなければ -1
static func aim_at_floor_hairs(tree: SceneTree, main: Node3D, radius: float, min_hairs: int) -> int:
	return await _aim_at_floor(tree, main, radius, min_hairs)


## 床の毛を順に試して目線を向ける。min_hairs が 0 の時は試した毛そのものをつまめる所、
## 1 以上の時は radius の中に毛が min_hairs 本以上ある所で止め、試した毛の ID を返す (見つからなければ -1)
static func _aim_at_floor(tree: SceneTree, main: Node3D, radius: float, min_hairs: int) -> int:
	var world: MansionWorld = main.get_node("MansionWorld")
	var player: FirstPersonPlayer = main.get_node("Player")
	var hand: HandController = main.hand
	var hair_field: Node3D = world.get_hair_field()
	var tried: int = 0
	for surface_idx: int in range(hair_field.get_surface_count()):
		var surface: MansionLayout.SurfaceDef = world.get_surface_def(surface_idx)
		if surface == null or surface.surface_type != MansionLayoutScript.SURFACE_FLOOR:
			continue
		var slot_count: int = hair_field.get_surface_visible_instance_count(surface_idx)
		for slot: int in range(slot_count):
			if tried >= MAX_CANDIDATES:
				return -1
			tried += 1
			var hair_id: int = hair_field.get_hair_id_at_slot(surface_idx, slot)
			var root: Vector3 = hair_field.get_hair_transform(hair_id).origin
			var to_center: Vector3 = Vector3(surface.center.x - root.x, 0.0, surface.center.z - root.z)
			if to_center.length() < 0.01:
				to_center = Vector3(1.0, 0.0, 0.0)
			player.set_spawn(root + to_center.normalized() * STAND_DISTANCE_M, 0.0)
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

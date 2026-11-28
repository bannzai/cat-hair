extends RefCounted
## 屋敷に置く物の種別ごとの既製の 3D モデル (Poly Haven の CC0。出典は assets/CREDITS.md) と、モデルを物の箱に
## 合わせて置く関数。モデルの無い種別 (カーペット・スーツのラック) は MansionWorld が基本の形と写実の素材で描く。

## 屋敷のレイアウト定義スクリプト (物の種別の定数)
const MansionLayoutScript := preload("res://scripts/mansion/mansion_layout.gd")

## 物の種別から、その物を描くモデルのシーン
const SCENES: Dictionary = {
	MansionLayoutScript.OBJECT_SOFA: preload("res://assets/models/Sofa_01/Sofa_01_1k.gltf"),
	MansionLayoutScript.OBJECT_TABLE:
	preload("res://assets/models/wooden_table_02/wooden_table_02_1k.gltf"),
	MansionLayoutScript.OBJECT_SIDEBOARD:
	preload("res://assets/models/ClassicConsole_01/ClassicConsole_01_1k.gltf"),
	MansionLayoutScript.OBJECT_KNIT_CHAIR:
	preload("res://assets/models/GreenChair_01/GreenChair_01_1k.gltf"),
}


## 物の種別 object_kind にモデルがあるか
static func has_model(object_kind: StringName) -> bool:
	return SCENES.has(object_kind)


## object_kind のモデルを、底面の中心が原点で幅・高さ・奥行が box_size の箱にちょうど収まるよう伸縮して作る。
## 返すノードの名前は "Model"。モデルの無い種別では null
static func instantiate_fitted(object_kind: StringName, box_size: Vector3) -> Node3D:
	if not has_model(object_kind):
		return null
	var model: Node3D = (SCENES[object_kind] as PackedScene).instantiate() as Node3D
	var bounds: AABB = merged_mesh_aabb(model)
	var fitted: Node3D = Node3D.new()
	fitted.name = "Model"
	# 箱に合わせる倍率は軸ごと。物の大きさ (MansionBuilder.OBJECT_PRESETS) はモデルの実寸に合わせてあり、部屋が狭い時に
	# 床の上の幅と奥行だけを縮めるため、倍率の差は小さい
	fitted.scale = Vector3(
		box_size.x / bounds.size.x, box_size.y / bounds.size.y, box_size.z / bounds.size.z
	)
	model.position = -bottom_center(bounds)
	fitted.add_child(model)
	return fitted


## 箱 bounds の底面の中心の位置を返す (モデルの足元の中心を原点へ動かす量に使う)
static func bottom_center(bounds: AABB) -> Vector3:
	return Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)


## root の下の全部の MeshInstance3D のメッシュの範囲を、root の局所座標で合わせた箱を返す (root がツリーの外でも測れる)。
## メッシュが 1 つも無い時は大きさ 0 の箱
static func merged_mesh_aabb(root: Node3D) -> AABB:
	var merged: AABB = AABB()
	var found: bool = false
	for mesh_node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance: MeshInstance3D = mesh_node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var bounds: AABB = transform_to_ancestor(mesh_instance, root) * mesh_instance.mesh.get_aabb()
		merged = merged.merge(bounds) if found else bounds
		found = true
	return merged


## node の局所座標から祖先 ancestor の局所座標への変換を返す (ツリーの外でも使えるよう親を辿って掛け合わせる)
static func transform_to_ancestor(node: Node3D, ancestor: Node3D) -> Transform3D:
	var to_ancestor: Transform3D = Transform3D.IDENTITY
	var current: Node = node
	while current != ancestor and current is Node3D:
		to_ancestor = (current as Node3D).transform * to_ancestor
		current = current.get_parent()
	return to_ancestor

extends RefCounted
## 人の体 (買取業者・画面に映る自分の手と腕) を、Godot の基本の形 (カプセル・球・箱) の組み合わせで組み立てる部品。
## どの部品も衝突体を持たない見た目だけのメッシュで、影を落とすかは呼ぶ側が決める。


## 2 点 from・to を結ぶ太さ radius の手足・指の 1 節 (両端の丸いカプセル) を parent_node の子に足す
static func add_limb(
	parent_node: Node3D, node_name: String, from: Vector3, to: Vector3, radius: float,
	limb_material: Material, casts_shadow: bool,
) -> MeshInstance3D:
	var mesh: CapsuleMesh = CapsuleMesh.new()
	mesh.radius = radius
	var instance: MeshInstance3D = _add_mesh(parent_node, node_name, mesh, limb_material, casts_shadow)
	pose_limb(instance, from, to)
	return instance


## 体を動かした後も、関節どうしを同じ太さの手足で結ぶ
static func pose_limb(instance: MeshInstance3D, from: Vector3, to: Vector3) -> void:
	var span: Vector3 = to - from
	var mesh: CapsuleMesh = instance.mesh as CapsuleMesh
	var height: float = span.length() + mesh.radius * 2.0
	if not is_equal_approx(mesh.height, height):
		mesh.height = height
	instance.position = (from + to) * 0.5
	if span.length() > 0.0:
		# カプセルは局所の Y 軸に沿う。両端が同じ形なので向きの正負は問わず、上向きの側へそろえると
		# Quaternion の弧の作り方が真逆の向き (180 度) の不定な場合に当たらない
		var axis: Vector3 = span.normalized()
		if axis.y < 0.0:
			axis = -axis
		instance.quaternion = Quaternion(Vector3.UP, axis)


## 中心 center・半径 radius の球を、軸ごとの倍率 sphere_scale で伸ばして parent_node の子に足す (頭・手・関節)
static func add_sphere(
	parent_node: Node3D, node_name: String, center: Vector3, radius: float, sphere_scale: Vector3,
	sphere_material: Material, casts_shadow: bool,
) -> MeshInstance3D:
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	var instance: MeshInstance3D = _add_mesh(
		parent_node, node_name, mesh, sphere_material, casts_shadow
	)
	instance.position = center
	instance.scale = sphere_scale
	return instance


## 中心 center・大きさ box_size の直方体を parent_node の子に足す
static func add_box(
	parent_node: Node3D, node_name: String, center: Vector3, box_size: Vector3,
	box_material: Material, casts_shadow: bool,
) -> MeshInstance3D:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = box_size
	var instance: MeshInstance3D = _add_mesh(parent_node, node_name, mesh, box_material, casts_shadow)
	instance.position = center
	return instance


## mesh を material で塗った MeshInstance3D を parent_node の子に足す
static func _add_mesh(
	parent_node: Node3D, node_name: String, mesh: Mesh, mesh_material: Material, casts_shadow: bool,
) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = mesh_material
	instance.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if casts_shadow
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	parent_node.add_child(instance)
	return instance

extends RefCounted
## 照準の光線と屋敷の毛が乗っている表面の交点。


## from から direction 向きの半直線が表から当たる表面のうち、max_distance 以内で最も近いものを返す。
## 当たれば {"surface_index", "point", "distance"}、どこにも当たらなければ空の辞書
static func nearest(surfaces: Array[Dictionary], from: Vector3, direction: Vector3,
		max_distance: float) -> Dictionary:
	var best: Dictionary = {}
	var dir: Vector3 = direction.normalized()
	for surface_idx: int in range(surfaces.size()):
		var spec: Dictionary = surfaces[surface_idx]
		var surface_transform: Transform3D = spec["transform"]
		var normal: Vector3 = surface_transform.basis.y.normalized()
		var facing: float = dir.dot(normal)
		if facing >= -0.0001:
			continue
		var distance: float = (surface_transform.origin - from).dot(normal) / facing
		var fur: FloorFur = spec.get("fur")
		if fur != null and fur.visible:
			distance = fur.hit_distance(from, dir, max_distance, distance)
		if distance < 0.0 or distance > max_distance:
			continue
		if not best.is_empty() and distance >= float(best["distance"]):
			continue
		var point: Vector3 = from + dir * distance
		var local: Vector3 = surface_transform.affine_inverse() * point
		var rect_min: Vector2 = spec["rect_min"]
		var rect_max: Vector2 = spec["rect_max"]
		if (
			local.x < rect_min.x or local.x > rect_max.x
			or local.z < rect_min.y or local.z > rect_max.y
		):
			continue
		best = {"surface_index": surface_idx, "point": point, "distance": distance}
	return best

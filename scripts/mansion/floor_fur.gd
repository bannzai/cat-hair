class_name FloorFur
extends MeshInstance3D
## 床に埋もれた毛をひとつの起伏のある面で描く。表面に見える 1 本の配置と照準にも同じ三角形の高さを使う。

## 房の輪郭と家具の縁を表せる格子の間隔 (m)。1 辺 6 m の部屋で約 3,600 頂点。
const SPACING: float = 0.1
## 厚い塊の高さの上限 (m)。床に入った毛は床の裏に隠れる。
const MAX_HEIGHT: float = 0.26
## 1 m² にこの本数が埋もれているとき、毛が床全面を覆う。
const FULL_DENSITY: float = 14000.0
## 毛を 1 本取るたびに全員の位置を更新せず、1 cm 分薄くなったときに山の形を更新する。
const DEPTH_STEP: float = 0.01

var _bounds: Rect2
var _grid: Vector2i
var _heights: PackedFloat32Array
var _depth: float


## 山の上では毛の根元を山肌に乗せて傾ける。ほかの面の毛はそのまま返す。
static func drape(strand: Transform3D, fur: FloorFur) -> Transform3D:
	if fur == null or not fur.visible:
		return strand
	var h: float = fur.height_at(strand.origin)
	if h <= 0:
		return strand
	var dx: float = fur.height_at(strand.origin + Vector3.RIGHT * 0.01) - h
	var dz: float = fur.height_at(strand.origin + Vector3.BACK * 0.01) - h
	strand.basis = Basis(Quaternion(Vector3.UP, Vector3(-dx, 0.01, -dz).normalized())) * strand.basis
	strand.origin.y += h
	return strand


## 水平な床に残っている、1 本ずつは描かない毛の層を作る。家具と床端に近づくと塊は薄くなる。
func build(spec: Dictionary, buried: int) -> void:
	var frame: Transform3D = spec["transform"]
	var corner: Vector2 = spec["rect_min"] + Vector2(frame.origin.x, frame.origin.z)
	_bounds = Rect2(corner, spec["rect_max"] - spec["rect_min"])
	_grid = Vector2i((_bounds.size / SPACING).ceil()) + Vector2i.ONE
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.frequency = 1.35
	noise.fractal_octaves = 3
	_heights.resize(_grid.x * _grid.y)
	for z: int in range(_grid.y):
		for x: int in range(_grid.x):
			var uv: Vector2 = Vector2(x, z) / Vector2(_grid - Vector2i.ONE)
			var p: Vector2 = _bounds.position + uv * _bounds.size
			var relief: float = noise.get_noise_2dv(p)
			var edge: Vector2 = (_bounds.size * 0.5 - (p - _bounds.get_center()).abs())
			var margin: float = minf(edge.x, edge.y)
			for footprint: Dictionary in spec["exclusions"]:
				var local: Vector3 = footprint["inverse"] * Vector3(p.x, frame.origin.y, p.y)
				var outside: Vector2 = Vector2(absf(local.x), absf(local.z)) - footprint["half"]
				margin = minf(margin, maxf(outside.x, outside.y))
			var mound: float = smoothstep(-0.18, 0.47, relief)
			var mask: float = smoothstep(0.0, 0.18, margin)
			var h: float = lerpf(-0.008, 0.023 + (MAX_HEIGHT - 0.023) * mound * mound, mask)
			_heights[z * _grid.x + x] = h
			# 束ごとに毛並みの向きと色が少しずつ違う。隣り合う頂点の UV はつながったままにする。
			surface.set_uv(p * 1.85 + Vector2(relief, noise.get_noise_2dv(p + Vector2(7, 9))) * 0.13)
			var shade: float = clampf(0.83 + relief * 0.32, 0.65, 1.0)
			surface.set_color(Color(shade, shade, shade, 1))
			surface.add_vertex(Vector3(p.x, h, p.y))
	for z: int in range(_grid.y - 1):
		for x: int in range(_grid.x - 1):
			var i: int = z * _grid.x + x
			for idx: int in [i, i + 1, i + _grid.x, i + 1, i + _grid.x + 1, i + _grid.x]:
				surface.add_index(idx)
	surface.generate_normals()
	mesh = surface.commit()
	var coat: StandardMaterial3D = StandardMaterial3D.new()
	coat.albedo_texture = preload("res://assets/textures/floor_fur.png")
	coat.vertex_color_use_as_albedo = true
	coat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	coat.roughness = 0.98
	material_override = coat
	_depth = _depth_for(buried)
	position.y = -_depth
	visible = _depth < MAX_HEIGHT


## 埋もれた本数を厚みに換算し、目に見える厚みが変化した時だけ個々の毛の根元を追従させる。
func update_buried(buried: int, bucket: Dictionary) -> void:
	var next: float = _depth_for(buried)
	if is_equal_approx(next, _depth):
		return
	var old: float = _depth
	_depth = next
	position.y = -_depth
	visible = _depth < MAX_HEIGHT
	var transforms: Array[Transform3D] = bucket["transforms"]
	var strands: MultiMesh = bucket["multimesh"]
	for slot: int in range(strands.visible_instance_count):
		var strand: Transform3D = transforms[slot]
		var h: float = _sample(Vector2(strand.origin.x, strand.origin.z))
		strand.origin.y += maxf(h - _depth, 0.0) - maxf(h - old, 0.0)
		transforms[slot] = strand
		strands.set_instance_transform(slot, strand)


## 指でつまむ毛を床から持ち上げる高さ (m)。層が床に埋まった所は 0。
func height_at(point: Vector3) -> float:
	return maxf(0.0, _sample(Vector2(point.x, point.z)) - _depth)


## 床への光線が最初に山に当たる距離。格子間隔の半分ずつ進み、交点を二分探索する。
func hit_distance(from: Vector3, dir: Vector3, limit: float, floor_distance: float) -> float:
	var first: float = maxf(0.0, (MAX_HEIGHT - _depth - from.y) / dir.y)
	var last: float = minf(limit, floor_distance)
	var distance: float = first
	while distance < last:
		var previous: float = distance
		distance = minf(last, distance + SPACING * 0.5)
		var point: Vector3 = from + distance * dir
		if point.y > height_at(point):
			continue
		for _i: int in range(8):
			var mid: float = (previous + distance) * 0.5
			point = from + mid * dir
			if point.y > height_at(point):
				previous = mid
			else:
				distance = mid
		return distance
	return floor_distance


func _depth_for(buried: int) -> float:
	var fullness: float = clampf(float(buried) / (_bounds.get_area() * FULL_DENSITY), 0.0, 1.0)
	return snappedf((1.0 - fullness) * MAX_HEIGHT, DEPTH_STEP)


## 四角を描画と同じ対角線で 2 つに割り、各三角形の頂点から高さを内挿する。
func _sample(p: Vector2) -> float:
	if not _bounds.has_point(p):
		return 0.0
	var grid_pos: Vector2 = (p - _bounds.position) / _bounds.size * Vector2(_grid - Vector2i.ONE)
	var cell: Vector2i = Vector2i(grid_pos).clamp(Vector2i.ZERO, _grid - Vector2i(2, 2))
	var t: Vector2 = grid_pos - Vector2(cell)
	var i: int = cell.y * _grid.x + cell.x
	var b: float = _heights[i + 1]
	var c: float = _heights[i + _grid.x]
	if t.x + t.y <= 1.0:
		return _heights[i] * (1.0 - t.x - t.y) + b * t.x + c * t.y
	return _heights[i + _grid.x + 1] * (t.x + t.y - 1.0) + b * (1.0 - t.y) + c * (1.0 - t.x)

extends "res://scripts/dev/scenebench.gd"
## 一時的な実験 (issue #56)。毛 SCENE_EXPERIMENT_COUNT 本の屋敷で、描画の設定を 1 つずつ変えて部屋に入った直後の
## 1 フレームの時間を計り、tmp/scene-experiment.json に書く。どの設定が毛の描画の時間を減らすかを決めたら消す。

## 毛の描画ノードのスクリプト (毛のメッシュとマテリアルの寸法)
const HairFieldScript := preload("res://scripts/hair_field.gd")
## 実験する毛の本数
const SCENE_EXPERIMENT_COUNT: int = 240000
## 実験の結果の出力先
const EXPERIMENT_JSON_PATH: String = "tmp/scene-experiment.json"
## 実験する変え方の名前
const VARIANTS: Array[String] = [
	"base",
	"vertex_shading",
	"three_triangles",
	"unshaded",
	"no_ssao_no_shadow",
	"range_8m",
	"base_again",
]


## 変え方ごとに計って JSON に書く
func _run() -> void:
	var settings_path: String = ProjectSettings.globalize_path("res://tmp/experiment-audio.cfg")
	var audio_handle: Dictionary = HeadlessCheck.prepare_audio_manager(self, settings_path)
	SaveStorageScript.delete_save_file(BENCH_SAVE_PATH)
	var state_handle: Dictionary = HeadlessCheck.acquire_game_state(root, BENCH_SAVE_PATH)
	var game_state: Node = state_handle["node"]
	var main: Node3D = MAIN_SCENE.instantiate()
	main.auto_advance_automation = false
	root.add_child(main)
	current_scene = main
	await process_frame
	main.enter_mansion()
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	var results: Dictionary = {}
	for variant: String in VARIANTS:
		var tuning: MansionTuning = MansionTuningScript.new()
		tuning.hair_count = SCENE_EXPERIMENT_COUNT
		game_state.apply_tuning_and_rebuild(tuning, false)
		var ssao_before: bool = main.world_environment.environment.ssao_enabled
		_apply_variant(main, variant)
		_stand_at_entrance(main, game_state)
		await physics_frame
		var measured: Dictionary = await _measure_frames(main, false)
		results[variant] = {
			"frame_ms": measured["frame_ms"]["median"],
			"gpu_ms": measured["render_gpu_ms"]["median"],
			"primitives": measured["primitives"]["median"],
		}
		print("experiment %s %s" % [variant, str(results[variant])])
		root.get_viewport().get_texture().get_image().save_png(
			"tmp/scene-experiment-%s.png" % variant
		)
		main.world_environment.environment.ssao_enabled = ssao_before
		_set_shadows(main, true)
	HairbenchScript.write_json(EXPERIMENT_JSON_PATH, results)
	(audio_handle["manager"] as AudioManagerScript).stop_all()
	current_scene = null
	root.remove_child(main)
	main.free()
	if bool(state_handle["created"]) and is_instance_valid(game_state):
		game_state.get_parent().remove_child(game_state)
		game_state.free()
	SaveStorageScript.delete_save_file(BENCH_SAVE_PATH)
	var release_deadline_msec: int = (
		Time.get_ticks_msec() + int(AudioManagerScript.AUDIO_RELEASE_TIME_SEC * 1000.0)
	)
	while Time.get_ticks_msec() < release_deadline_msec:
		await process_frame
	HeadlessCheck.cleanup_audio_manager(self, audio_handle, settings_path)
	print("scene experiment OK")
	quit(0)


## 毛の MultiMeshInstance3D の一覧を返す
func _hair_instances(main: Node3D) -> Array[MultiMeshInstance3D]:
	var found: Array[MultiMeshInstance3D] = []
	for child: Node in main.mansion_world.get_hair_field().get_children():
		if child is MultiMeshInstance3D:
			found.append(child)
	return found


## 変え方を当てる
func _apply_variant(main: Node3D, variant: String) -> void:
	var instances: Array[MultiMeshInstance3D] = _hair_instances(main)
	match variant:
		"vertex_shading":
			var material: StandardMaterial3D = HairFieldScript.build_hair_material()
			material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
			for instance: MultiMeshInstance3D in instances:
				instance.material_override = material
		"unshaded":
			var material: StandardMaterial3D = HairFieldScript.build_hair_material()
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			for instance: MultiMeshInstance3D in instances:
				instance.material_override = material
		"three_triangles":
			var mesh: ArrayMesh = _three_triangle_mesh()
			for instance: MultiMeshInstance3D in instances:
				instance.multimesh.mesh = mesh
		"no_ssao_no_shadow":
			main.world_environment.environment.ssao_enabled = false
			_set_shadows(main, false)
		"range_8m":
			for instance: MultiMeshInstance3D in instances:
				instance.visibility_range_end = 8.0


## 屋敷の光の影を shadow にする (影を付けていた光だけ)
func _set_shadows(main: Node3D, shadow: bool) -> void:
	var daylight: SpotLight3D = main.look_room.get_daylight()
	if daylight != null:
		daylight.shadow_enabled = shadow
	var room_light: OmniLight3D = main.mansion_world.get_node_or_null(
		"LightsRoot/RoomLight_0"
	) as OmniLight3D
	if room_light != null:
		room_light.shadow_enabled = shadow


## 2 セグメント・5 頂点・3 三角形の毛のメッシュ (今の 3 セグメントの真ん中の点を抜いた形)
static func _three_triangle_mesh() -> ArrayMesh:
	var length: float = HairFieldScript.HAIR_LENGTH_M
	var width: float = HairFieldScript.HAIR_BASE_WIDTH_M
	var p0: Vector3 = Vector3.ZERO
	var p1: Vector3 = Vector3(0.0065, 0.0052, length * 0.5)
	var p2: Vector3 = Vector3(0.0042, 0.0018, length)
	var right0: Vector3 = (p1 - p0).cross(Vector3.UP).normalized()
	var right1: Vector3 = (p2 - p0).cross(Vector3.UP).normalized()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		p0 - right0 * width * 0.5,
		p0 + right0 * width * 0.5,
		p1 - right1 * width * 0.38,
		p1 + right1 * width * 0.38,
		p2,
	])
	var normals: PackedVector3Array = PackedVector3Array()
	normals.resize(5)
	normals.fill(Vector3.UP)
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 1, 3, 2, 2, 3, 4])
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

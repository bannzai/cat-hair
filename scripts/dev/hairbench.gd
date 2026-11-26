extends SceneTree
## 毛の描画のベンチマーク (描画付きで起動)。
## 本数を変えながら 1 部屋に毛を配置し、本数ごとの配置時間・1 フレームの描画時間・
## 1 本削除の可否・画面 PNG と輝度統計を JSON (既定 tmp/hairbench.json) に書き出す。
## すべての本数を終えたら「hairbench OK」を出して quit(0) する。

const HeadlessCheck := preload("res://scripts/dev/headless_check.gd")
const HAIR_PROTOTYPE_SCENE: PackedScene = preload("res://scenes/hair_prototype.tscn")

const DEFAULT_COUNTS: Array[int] = [1000, 10000, 100000, 1000000]
const DEFAULT_JSON_PATH: String = "tmp/hairbench.json"
const DEFAULT_PNG_DIR: String = "tmp"
const DEFAULT_PNG_PREFIX: String = "hairbench"
const WARMUP_FRAMES_FIRST: int = 4
const WARMUP_FRAMES_NEXT: int = 2
const MEASURE_FRAMES_MAX: int = 5
const SLOW_FRAME_THRESHOLD_MS: float = 2000.0
const MEASURE_FRAMES_SLOW: int = 2


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var counts: Array[int] = _parse_counts(OS.get_environment("HAIRBENCH_COUNTS"))
	var json_path: String = _env_or_default("HAIRBENCH_JSON", DEFAULT_JSON_PATH)
	var png_dir: String = _env_or_default("HAIRBENCH_PNG_DIR", DEFAULT_PNG_DIR)
	var png_prefix: String = _env_or_default("HAIRBENCH_PNG_PREFIX", DEFAULT_PNG_PREFIX)

	var prototype: Node3D = HAIR_PROTOTYPE_SCENE.instantiate()
	root.add_child(prototype)
	current_scene = prototype
	await process_frame

	var report: Dictionary = _build_report_header()
	var results: Array[Dictionary] = []
	report["results"] = results

	var failed: bool = false
	for idx: int in range(counts.size()):
		var target_count: int = counts[idx]
		var entry: Dictionary = await _measure_count(
			prototype, target_count, idx == 0, png_dir, png_prefix
		)
		results.append(entry)
		if not _write_json(json_path, report):
			failed = true
			break
		print(
			"hairbench count=%d rendered=%s setup_ms=%.2f frame_ms_avg=%.2f mean_lum=%.3f remove_ok=%s"
			% [
				target_count,
				str(entry["rendered"]),
				float(entry["setup_ms"]),
				float(entry["frame_ms_avg"]),
				float(entry["mean_luminance"]),
				str(entry["single_remove_ok"]),
			]
		)
		if not bool(entry["rendered"]):
			failed = true
			break

	root.remove_child(prototype)
	prototype.free()
	await create_timer(HeadlessCheck.AUDIO_RELEASE_TIME).timeout

	if failed:
		quit(1)
		return
	print("hairbench OK")
	quit(0)


func _measure_count(
	prototype: Node3D,
	target_count: int,
	is_first: bool,
	png_dir: String,
	png_prefix: String
) -> Dictionary:
	var setup_start: int = Time.get_ticks_usec()
	var placed: int = prototype.populate_hairs(target_count)
	var setup_ms: float = float(Time.get_ticks_usec() - setup_start) / 1000.0

	var warmup: int = WARMUP_FRAMES_FIRST if is_first else WARMUP_FRAMES_NEXT
	for _w: int in range(warmup):
		await process_frame

	var frame_times: Array[float] = []
	var target_frames: int = MEASURE_FRAMES_MAX
	var frame_idx: int = 0
	while frame_idx < target_frames:
		var t0: int = Time.get_ticks_usec()
		await process_frame
		var elapsed_ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
		frame_times.append(elapsed_ms)
		if frame_idx == 0 and elapsed_ms >= SLOW_FRAME_THRESHOLD_MS:
			target_frames = MEASURE_FRAMES_SLOW
		frame_idx += 1

	var png_path: String = "%s/%s-%d.png" % [png_dir, png_prefix, target_count]
	var image: Image = root.get_viewport().get_texture().get_image()
	var save_status: Error = image.save_png(png_path)
	var lum_stats: Dictionary = _sample_luminance(image)

	var before_remove: int = prototype.get_remaining_count()
	var removed: bool = prototype.remove_hair(0) if before_remove > 0 else false
	var after_remove: int = prototype.get_remaining_count()
	await process_frame
	var single_remove_ok: bool = (
		removed
		and after_remove == before_remove - 1
		and not prototype.get_hair_field().has_hair(0)
	)

	var frame_sum: float = 0.0
	var frame_min: float = frame_times[0]
	var frame_max: float = frame_times[0]
	for ft: float in frame_times:
		frame_sum += ft
		frame_min = minf(frame_min, ft)
		frame_max = maxf(frame_max, ft)
	var frame_avg: float = frame_sum / float(frame_times.size())

	var rendered: bool = (
		placed == target_count
		and save_status == OK
		and bool(lum_stats["not_blank"])
		and single_remove_ok
	)
	if save_status != OK:
		push_error("hairbench PNG 保存失敗: %s (%s)" % [png_path, error_string(save_status)])

	return {
		"count": target_count,
		"placed_count": placed,
		"rendered": rendered,
		"setup_ms": snappedf(setup_ms, 0.01),
		"frame_ms_avg": snappedf(frame_avg, 0.01),
		"frame_ms_min": snappedf(frame_min, 0.01),
		"frame_ms_max": snappedf(frame_max, 0.01),
		"measured_frames": frame_times.size(),
		"png_path": png_path,
		"mean_luminance": snappedf(float(lum_stats["mean"]), 0.0001),
		"min_luminance": snappedf(float(lum_stats["min"]), 0.0001),
		"max_luminance": snappedf(float(lum_stats["max"]), 0.0001),
		"not_blank": bool(lum_stats["not_blank"]),
		"single_remove_ok": single_remove_ok,
	}


func _sample_luminance(image: Image) -> Dictionary:
	var width: int = image.get_width()
	var height: int = image.get_height()
	if width <= 0 or height <= 0:
		return {"mean": 0.0, "min": 0.0, "max": 0.0, "not_blank": false}

	var cols: int = 32
	var rows: int = 18
	var sum_lum: float = 0.0
	var min_lum: float = 1.0
	var max_lum: float = 0.0
	var samples: int = 0

	for r: int in range(rows):
		var y: int = int(float(r + 0.5) * float(height) / float(rows))
		for c: int in range(cols):
			var x: int = int(float(c + 0.5) * float(width) / float(cols))
			var lum: float = image.get_pixel(x, y).get_luminance()
			sum_lum += lum
			min_lum = minf(min_lum, lum)
			max_lum = maxf(max_lum, lum)
			samples += 1

	var mean_lum: float = sum_lum / float(samples)
	var contrast: float = max_lum - min_lum
	var not_blank: bool = mean_lum > 0.02 and mean_lum < 0.98 and contrast > 0.03
	return {
		"mean": mean_lum,
		"min": min_lum,
		"max": max_lum,
		"not_blank": not_blank,
	}


func _build_report_header() -> Dictionary:
	var has_rd: bool = RenderingServer.get_rendering_device() != null
	return {
		"rendering_method_setting": str(
			ProjectSettings.get_setting("rendering/renderer/rendering_method", "")
		),
		"has_rendering_device": has_rd,
		"video_adapter_name": RenderingServer.get_video_adapter_name(),
		"video_adapter_vendor": RenderingServer.get_video_adapter_vendor(),
		"os_name": OS.get_name(),
		"godot_version": str(Engine.get_version_info().get("string", "")),
	}


func _write_json(path: String, data: Dictionary) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("hairbench JSON 書き込み失敗: %s" % path)
		return false
	file.store_string(JSON.stringify(data, "  ") + "\n")
	file.close()
	return true


func _parse_counts(raw: String) -> Array[int]:
	if raw.strip_edges().is_empty():
		return DEFAULT_COUNTS.duplicate()
	var parsed: Array[int] = []
	for token: String in raw.split(","):
		var trimmed: String = token.strip_edges()
		if trimmed.is_valid_int():
			var val: int = int(trimmed)
			if val > 0:
				parsed.append(val)
	if parsed.is_empty():
		return DEFAULT_COUNTS.duplicate()
	return parsed


func _env_or_default(key: String, fallback: String) -> String:
	var val: String = OS.get_environment(key).strip_edges()
	return fallback if val.is_empty() else val

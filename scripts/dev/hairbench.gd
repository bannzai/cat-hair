extends SceneTree
## 毛の描画のベンチマーク (描画付きで起動)。
## 本数を変えながら 1 部屋に毛を配置し、本数ごとの配置時間・1 フレームの描画時間・
## 1 本削除の可否・画面 PNG と輝度統計を JSON (既定 tmp/hairbench.json) に書き出す。
## すべての本数を終えたら「hairbench OK」を出して quit(0) する。

## 音の解放を待つ時間 (AUDIO_RELEASE_TIME) を借りる headless 検証の土台
const HeadlessCheck := preload("res://scripts/dev/headless_check.gd")
## 計測対象の試作シーン
const HAIR_PROTOTYPE_SCENE: PackedScene = preload("res://scenes/hair_prototype.tscn")

## 既定の計測本数 (issue #6 要件の 1,000〜1,000,000 本の 4 段階)
const DEFAULT_COUNTS: Array[int] = [1000, 10000, 100000, 1000000]
## JSON レポートの既定出力先 (Makefile の hairbench target が参照するパス)
const DEFAULT_JSON_PATH: String = "tmp/hairbench.json"
## PNG の既定出力ディレクトリ
const DEFAULT_PNG_DIR: String = "tmp"
## PNG ファイル名の既定プレフィックス (hairbench-<本数>.png)
const DEFAULT_PNG_PREFIX: String = "hairbench"
## 初回本数の描画安定待ちフレーム数 (scripts/dev/screenshot.gd の 4 フレーム待機に揃えた)
const WARMUP_FRAMES_FIRST: int = 4
## 2 本数目以降の描画安定待ちフレーム数 (パイプライン生成済みのため描画反映分 2 フレーム)
const WARMUP_FRAMES_NEXT: int = 2
## 通常時のフレーム時間計測フレーム数 (CI 実行時間と平均値の安定のバランスで 5 フレーム)
const MEASURE_FRAMES_MAX: int = 5
## 重い条件を判定する 1 フレーム所要時間の閾値 (ms。CI の 100 万本実測 ~1.8 秒に対し 2.0 秒超で短縮)
const SLOW_FRAME_THRESHOLD_MS: float = 2000.0
## 重い条件 (SLOW_FRAME_THRESHOLD_MS 以上) での計測フレーム数 (平均と最小・最大を取る最小 2)
const MEASURE_FRAMES_SLOW: int = 2
## 輝度サンプリングの横格子数 (16:9 画面を横 32 × 縦 18 = 576 点で等間隔計測し全画素走査を避ける)
const LUMINANCE_GRID_COLS: int = 32
## 輝度サンプリングの縦格子数 (16:9 の縦横比を保つ 18 行)
const LUMINANCE_GRID_ROWS: int = 18
## 画面が真っ黒 (0.0) でないと判定する平均輝度の下限 (実測 0.32〜0.38 に対し完全暗転を弾く 2% 余裕)
const MIN_MEAN_LUMINANCE: float = 0.02
## 画面が真っ白 (1.0) でないと判定する平均輝度の上限 (実測 0.32〜0.38 に対し完全白飛びを弾く 2% 余裕)
const MAX_MEAN_LUMINANCE: float = 0.98
## 画面が単色塗り潰しでないと判定する輝度差の下限 (実測 0.61 に対し 8bit 量子化誤差を除外する 3%)
const MIN_LUMINANCE_CONTRAST: float = 0.03


## 環境変数のカンマ区切り本数文字列を正の整数配列に解析する (空・全無効なら既定値)
static func parse_counts(raw: String) -> Array[int]:
	if raw.strip_edges().is_empty():
		return DEFAULT_COUNTS.duplicate()
	var parsed: Array[int] = []
	for token: String in raw.split(","):
		var trimmed: String = token.strip_edges()
		if trimmed.is_valid_int():
			var parsed_count: int = int(trimmed)
			if parsed_count > 0:
				parsed.append(parsed_count)
	if parsed.is_empty():
		return DEFAULT_COUNTS.duplicate()
	return parsed


## 文字列が空または空白のみなら fallback、そうでなければトリム済みの値を返す
static func env_or_default(raw_value: String, fallback: String) -> String:
	var trimmed: String = raw_value.strip_edges()
	return fallback if trimmed.is_empty() else trimmed


## 画像を等間隔格子でサンプリングし、平均・最小・最大輝度と非白黒・非単色判定を返す
static func sample_luminance(image: Image) -> Dictionary:
	if image == null:
		return {"mean": 0.0, "min": 0.0, "max": 0.0, "not_blank": false}
	var width: int = image.get_width()
	var height: int = image.get_height()
	if width <= 0 or height <= 0:
		return {"mean": 0.0, "min": 0.0, "max": 0.0, "not_blank": false}

	var sum_lum: float = 0.0
	var min_lum: float = 1.0
	var max_lum: float = 0.0
	var samples: int = 0

	for row: int in range(LUMINANCE_GRID_ROWS):
		var y: int = int(float(row + 0.5) * float(height) / float(LUMINANCE_GRID_ROWS))
		for column: int in range(LUMINANCE_GRID_COLS):
			var x: int = int(float(column + 0.5) * float(width) / float(LUMINANCE_GRID_COLS))
			var lum: float = image.get_pixel(x, y).get_luminance()
			sum_lum += lum
			min_lum = minf(min_lum, lum)
			max_lum = maxf(max_lum, lum)
			samples += 1

	var mean_lum: float = sum_lum / float(samples)
	var not_blank: bool = (
		mean_lum > MIN_MEAN_LUMINANCE
		and mean_lum < MAX_MEAN_LUMINANCE
		and (max_lum - min_lum) > MIN_LUMINANCE_CONTRAST
	)
	return {
		"mean": mean_lum,
		"min": min_lum,
		"max": max_lum,
		"not_blank": not_blank,
	}


## 初回フレームの所要時間に応じて、重い条件なら計測フレーム数を短縮する目標値を返す
static func select_measure_frame_target(
	frame_idx: int, elapsed_ms: float, current_target: int
) -> int:
	if frame_idx == 0 and elapsed_ms >= SLOW_FRAME_THRESHOLD_MS:
		return MEASURE_FRAMES_SLOW
	return current_target


## 1 本削除の結果がすべて期待どおり (戻り値 true・本数 1 減・対象 ID 消滅・MultiMesh 反映) かを判定する
static func evaluate_single_remove(
	removed: bool,
	before_count: int,
	after_count: int,
	still_exists: bool,
	multimesh_synced: bool = true
) -> bool:
	return removed and after_count == before_count - 1 and not still_exists and multimesh_synced


## 1 本数分の計測が描画成功の条件をすべて満たしたかを判定する
static func evaluate_rendered(
	placed: int, target_count: int, save_status: Error, not_blank: bool, single_remove_ok: bool
) -> bool:
	return placed == target_count and save_status == OK and not_blank and single_remove_ok


## レポート辞書を JSON 文字列として path へ書き出す。成功なら true
static func write_json(path: String, data: Dictionary) -> bool:
	if path.strip_edges().is_empty():
		return false
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("hairbench JSON 書き込み失敗: %s" % path)
		return false
	file.store_string(JSON.stringify(data, "  ") + "\n")
	file.close()
	return true


## SceneTree 初期化完了後にベンチマーク本体を遅延起動する
func _initialize() -> void:
	_run.call_deferred()


## 全本数のベンチマークを順次実行し、JSON 保存と終了コード出力を行う
func _run() -> void:
	var counts: Array[int] = parse_counts(OS.get_environment("HAIRBENCH_COUNTS"))
	var json_path: String = env_or_default(
		OS.get_environment("HAIRBENCH_JSON"), DEFAULT_JSON_PATH
	)
	var png_dir: String = env_or_default(
		OS.get_environment("HAIRBENCH_PNG_DIR"), DEFAULT_PNG_DIR
	)
	var png_prefix: String = env_or_default(
		OS.get_environment("HAIRBENCH_PNG_PREFIX"), DEFAULT_PNG_PREFIX
	)

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
		if not write_json(json_path, report):
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


## 指定本数を配置して描画時間・PNG・輝度・1 本削除を計測し結果辞書を返す
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

	for _w: int in range(WARMUP_FRAMES_FIRST if is_first else WARMUP_FRAMES_NEXT):
		await process_frame

	var frame_times: Array[float] = []
	var target_frames: int = MEASURE_FRAMES_MAX
	var frame_idx: int = 0
	while frame_idx < target_frames:
		var frame_start_usec: int = Time.get_ticks_usec()
		await process_frame
		var elapsed_ms: float = float(Time.get_ticks_usec() - frame_start_usec) / 1000.0
		frame_times.append(elapsed_ms)
		target_frames = select_measure_frame_target(frame_idx, elapsed_ms, target_frames)
		frame_idx += 1

	var png_path: String = "%s/%s-%d.png" % [png_dir, png_prefix, target_count]
	var image: Image = root.get_viewport().get_texture().get_image()
	var save_status: Error = image.save_png(png_path)
	var lum_stats: Dictionary = sample_luminance(image)

	var field: Node3D = prototype.get_hair_field()
	var surface0_count: int = field.get_surface_remaining_count(0)
	var tail_id: int = field.get_hair_id_at_slot(0, surface0_count - 1) if surface0_count >= 2 else -1
	var tail_xform_before: Transform3D = (
		field.get_hair_transform(tail_id) if tail_id >= 0 else Transform3D.IDENTITY
	)
	var tail_color_before: Color = (
		field.get_hair_color(tail_id) if tail_id >= 0 else Color(0.0, 0.0, 0.0, 0.0)
	)
	var before_remove: int = prototype.get_remaining_count()
	var removed: bool = prototype.remove_hair(0) if before_remove > 0 else false
	var after_remove: int = prototype.get_remaining_count()
	await process_frame
	# 描画付き実行で swap-remove が MultiMesh 本体の Transform/Color へ反映されたことも検証する
	var multimesh_synced: bool = true
	if tail_id >= 0:
		multimesh_synced = (
			field.get_multimesh_slot_transform(0, 0).is_equal_approx(tail_xform_before)
			and field.get_multimesh_slot_color(0, 0).is_equal_approx(tail_color_before)
		)
	var single_remove_ok: bool = evaluate_single_remove(
		removed, before_remove, after_remove, field.has_hair(0), multimesh_synced
	)

	var frame_sum: float = 0.0
	var frame_min: float = frame_times[0]
	var frame_max: float = frame_times[0]
	for frame_time_ms: float in frame_times:
		frame_sum += frame_time_ms
		frame_min = minf(frame_min, frame_time_ms)
		frame_max = maxf(frame_max, frame_time_ms)

	var rendered: bool = evaluate_rendered(
		placed, target_count, save_status, bool(lum_stats["not_blank"]), single_remove_ok
	)
	if save_status != OK:
		push_error("hairbench PNG 保存失敗: %s (%s)" % [png_path, error_string(save_status)])

	return {
		"count": target_count,
		"placed_count": placed,
		"rendered": rendered,
		"setup_ms": snappedf(setup_ms, 0.01),
		"frame_ms_avg": snappedf(frame_sum / float(frame_times.size()), 0.01),
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


## JSON レポート先頭の環境・レンダラ情報ヘッダー辞書を組み立てる
func _build_report_header() -> Dictionary:
	return {
		"rendering_method_setting": str(
			ProjectSettings.get_setting("rendering/renderer/rendering_method", "")
		),
		"has_rendering_device": RenderingServer.get_rendering_device() != null,
		"video_adapter_name": RenderingServer.get_video_adapter_name(),
		"video_adapter_vendor": RenderingServer.get_video_adapter_vendor(),
		"os_name": OS.get_name(),
		"godot_version": str(Engine.get_version_info().get("string", "")),
	}

extends SceneTree
## 屋敷の 1 フレームの時間のベンチマーク (描画付きで起動)。
## メインシーンで屋敷に入り、毛の本数を変えながら「部屋に入った直後」(最初の部屋の入口から見下ろす) と
## 「掃除ロボットが動いている間」(最初の部屋に掃除ロボット 4 台を置き、時計を進める) の 2 つの場面で、
## 1 フレームの時間・処理 (スクリプト) の時間・描画の CPU / GPU の時間・描いた三角形とドローコールの数を計る。
## 結果を JSON (既定 tmp/scenebench.json) に、本数ごとの部屋に入った直後の画面を tmp/scenebench-<本数>.png に書き、
## 全部の本数を終えたら「scenebench OK」を出して quit(0) する。CI のソフトウェア描画の数字は実機の fps ではなく、
## 変更の前後・本数の間の比として読む。

## AudioManager / GameState 準備・後始末を借りる検証の土台
const HeadlessCheck := preload("res://scripts/dev/headless_check.gd")
## 計測するメインシーン
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
## 音声管理ノード (AUDIO_RELEASE_TIME_SEC の単一の正と型解決用)
const AudioManagerScript := preload("res://scripts/audio/audio_manager.gd")
## JSON 保存ストレージスクリプト
const SaveStorageScript := preload("res://scripts/state/save_storage.gd")
## 開発者向け調整値データ型スクリプト (毛の本数を変える)
const MansionTuningScript := preload("res://scripts/data/mansion_tuning.gd")
## 部屋に入った直後を撮る時の見下ろす角度 (LOOK_OVERVIEW_PITCH) の単一の正
const ScreenshotScript := preload("res://scripts/dev/screenshot.gd")
## 掃除ロボットの値段
const RobotRulesScript := preload("res://scripts/automation/robot_rules.gd")
## 本数の文字列の解析 (parse_counts と同じ形) を借りる
const HairbenchScript := preload("res://scripts/dev/hairbench.gd")

## issue #56 で既定を上げる前の既定の毛の本数。変更の前後を同じ本数で比べるため、今の既定とは別に残す
const PREVIOUS_DEFAULT_HAIR_COUNT: int = 12000
## 既定の計測本数 (上げる前の既定、その 5 倍、今の既定、今の既定の 2 倍)
const DEFAULT_COUNTS: Array[int] = [
	PREVIOUS_DEFAULT_HAIR_COUNT,
	PREVIOUS_DEFAULT_HAIR_COUNT * 5,
	MansionTuningScript.DEFAULT_HAIR_COUNT,
	MansionTuningScript.DEFAULT_HAIR_COUNT * 2,
]
## JSON レポートの既定出力先 (Makefile の scenebench target が参照するパス)
const DEFAULT_JSON_PATH: String = "tmp/scenebench.json"
## ベンチマーク専用のセーブパス (遊んでいる人のセーブに左右されない)
const BENCH_SAVE_PATH: String = "user://scenebench_save_data.json"
## 屋敷を作り直した後、計測の前に進めるフレーム数 (screenshot.gd の撮影前の 4 フレームと揃え、
## パイプラインの生成を含む最初の重いフレームを計測から外すため倍にした)
const WARMUP_FRAMES: int = 8
## 1 つの場面で計るフレーム数 (ランナーのぶれを中央値で均すため。毛 24 万本で 1 フレーム 0.5 秒前後と見込み、
## 4 本数 × 2 場面の合計が job の時間の上限に収まる数)
const MEASURE_FRAMES: int = 20
## 掃除ロボットが動いている間の場面で、1 フレームごとに進める時計の秒数 (掃除ロボット 1 台が 1 秒に 1 本取るため、
## 持てる上限の台数で 1 フレームあたり 1 本前後を取る速さ)
const AUTOMATION_STEP_SECONDS: float = 0.25


## 値の列から中央値・最小・最大・平均を返す (空なら全部 0)
static func summarize(values: Array) -> Dictionary:
	if values.is_empty():
		return {"median": 0.0, "min": 0.0, "max": 0.0, "avg": 0.0}
	var sorted: Array = values.duplicate()
	sorted.sort()
	var middle: int = int(floor(sorted.size() * 0.5))
	var total: float = 0.0
	for value: Variant in sorted:
		total += float(value)
	return {
		"median": snappedf(
			(
				float(sorted[middle])
				if sorted.size() % 2 == 1
				else (float(sorted[middle - 1]) + float(sorted[middle])) * 0.5
			),
			0.01
		),
		"min": snappedf(float(sorted[0]), 0.01),
		"max": snappedf(float(sorted[sorted.size() - 1]), 0.01),
		"avg": snappedf(total / float(sorted.size()), 0.01),
	}


## SceneTree 初期化完了後にベンチマーク本体を遅延起動する
func _initialize() -> void:
	_run.call_deferred()


## 全本数のベンチマークを順に実行し、JSON 保存と終了コード出力を行う
func _run() -> void:
	var raw_counts: String = OS.get_environment("SCENEBENCH_COUNTS")
	var counts: Array[int] = (
		DEFAULT_COUNTS.duplicate()
		if raw_counts.strip_edges().is_empty()
		else HairbenchScript.parse_counts(raw_counts)
	)
	var json_path: String = HairbenchScript.env_or_default(
		OS.get_environment("SCENEBENCH_JSON"), DEFAULT_JSON_PATH
	)
	var settings_path: String = ProjectSettings.globalize_path("res://tmp/scenebench-audio.cfg")
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

	var results: Array[Dictionary] = []
	var report: Dictionary = {
		"video_adapter_name": RenderingServer.get_video_adapter_name(),
		"godot_version": str(Engine.get_version_info().get("string", "")),
		"measure_frames": MEASURE_FRAMES,
		"results": results,
	}
	var failed: bool = false
	for count: int in counts:
		var entry: Dictionary = await _measure_count(main, game_state, count)
		results.append(entry)
		if not HairbenchScript.write_json(json_path, report) or not bool(entry["ok"]):
			failed = true
			break

	(audio_handle["manager"] as AudioManagerScript).stop_all()
	if current_scene == main:
		current_scene = null
	root.remove_child(main)
	main.free()
	if bool(state_handle["created"]) and is_instance_valid(game_state):
		game_state.get_parent().remove_child(game_state)
		game_state.free()
	SaveStorageScript.delete_save_file(BENCH_SAVE_PATH)
	await HeadlessCheck.wait_audio_release(self)
	HeadlessCheck.cleanup_audio_manager(self, audio_handle, settings_path)
	if failed:
		quit(1)
		return
	print("scenebench OK")
	quit(0)


## count 本で屋敷を作り直し、2 つの場面を計って結果の辞書を返す
func _measure_count(main: Node3D, game_state: Node, count: int) -> Dictionary:
	var tuning: MansionTuning = MansionTuningScript.new()
	tuning.hair_count = count
	var rebuild_start: int = Time.get_ticks_usec()
	game_state.apply_tuning_and_rebuild(tuning, false)
	var rebuild_ms: float = float(Time.get_ticks_usec() - rebuild_start) / 1000.0
	var placed: int = main.mansion_world.get_hair_field().get_remaining_count()

	_stand_at_entrance(main, game_state)
	await physics_frame
	var enter: Dictionary = await _measure_frames(main, false)
	var png_path: String = "tmp/scenebench-%d.png" % count
	var save_status: Error = root.get_viewport().get_texture().get_image().save_png(png_path)
	if save_status != OK:
		push_error("scenebench PNG 保存失敗: %s (%s)" % [png_path, error_string(save_status)])

	# 掃除ロボットは持てる上限まで、最初の部屋に置く
	game_state.save_data.building_progress.money = (
		RobotRulesScript.ROBOT_PRICE * RobotRulesScript.MAX_ROBOTS
	)
	var robots_ok: bool = true
	for _robot: int in range(RobotRulesScript.MAX_ROBOTS):
		robots_ok = (
			robots_ok
			and game_state.automation.buy_robot(game_state.current_layout.rooms[0].room_id)
		)
	_stand_at_entrance(main, game_state)
	await physics_frame
	var robots: Dictionary = await _measure_frames(main, true)

	var ok: bool = placed == count and save_status == OK and robots_ok
	print(
		(
			"scenebench count=%d placed=%d ok=%s rebuild_ms=%.1f enter_frame_ms=%.1f"
			+ " enter_primitives=%d robots_frame_ms=%.1f robots_advance_ms=%.2f"
		)
		% [
			count, placed, str(ok), rebuild_ms,
			float(enter["frame_ms"]["median"]), int(enter["primitives"]["median"]),
			float(robots["frame_ms"]["median"]), float(robots["advance_ms"]["median"]),
		]
	)
	return {
		"count": count,
		"placed": placed,
		"ok": ok,
		"rebuild_ms": snappedf(rebuild_ms, 0.1),
		"png_path": png_path,
		"enter": enter,
		"robots": robots,
	}


## 最初の部屋の入口 (屋敷のスポーン位置) に立ち、部屋に入った直後の撮影と同じ角度で見下ろす
func _stand_at_entrance(main: Node3D, game_state: Node) -> void:
	var layout: MansionLayout = game_state.current_layout
	var player: FirstPersonPlayer = main.player
	player.set_spawn(layout.spawn_position, layout.spawn_yaw)
	ScreenshotScript.set_pitch(player, ScreenshotScript.LOOK_OVERVIEW_PITCH)


## WARMUP_FRAMES を進めてから MEASURE_FRAMES を計り、指標ごとの要約を返す。
## advance_automation が true の時は、毎フレームの前に猫と掃除ロボットの時計を AUTOMATION_STEP_SECONDS 進め、その時間も計る
func _measure_frames(main: Node3D, advance_automation: bool) -> Dictionary:
	for _i: int in range(WARMUP_FRAMES):
		await process_frame
	var viewport_rid: RID = root.get_viewport_rid()
	var samples: Dictionary = {
		"frame_ms": [],
		"process_ms": [],
		"render_cpu_ms": [],
		"render_gpu_ms": [],
		"primitives": [],
		"draw_calls": [],
		"objects": [],
		"advance_ms": [],
	}
	for _i: int in range(MEASURE_FRAMES):
		# 1 フレームの時間には、猫と掃除ロボットの時計を進める処理 (毛の削除を含む) も含める
		var frame_start: int = Time.get_ticks_usec()
		var advance_ms: float = 0.0
		if advance_automation:
			main.get_game_state().automation.advance(AUTOMATION_STEP_SECONDS)
			advance_ms = float(Time.get_ticks_usec() - frame_start) / 1000.0
		await process_frame
		(samples["frame_ms"] as Array).append(
			float(Time.get_ticks_usec() - frame_start) / 1000.0
		)
		(samples["advance_ms"] as Array).append(advance_ms)
		(samples["process_ms"] as Array).append(
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		)
		(samples["render_cpu_ms"] as Array).append(
			RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid)
		)
		(samples["render_gpu_ms"] as Array).append(
			RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid)
		)
		(samples["primitives"] as Array).append(
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		)
		(samples["draw_calls"] as Array).append(
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		)
		(samples["objects"] as Array).append(
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		)
	var summary: Dictionary = {}
	for key: String in samples.keys():
		summary[key] = summarize(samples[key])
	return summary

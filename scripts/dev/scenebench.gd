extends SceneTree
## 屋敷の 1 フレームの時間のベンチマーク (描画付きで起動)。
## メインシーンで屋敷に入り、毛の本数を既定 (MansionTuning.DEFAULT_HAIR_COUNT) のまま、1 本ずつ描く本数の上限
## (MansionWorld.hair_draw_budget) を変えながら「部屋に入った直後」(最初の部屋の入口から見下ろす) と
## 「掃除ロボットが動いている間」(最初の部屋に掃除ロボット 4 台を置き、時計を進める) の 2 つの場面で、
## 1 フレームの時間・処理 (スクリプト) の時間・描画の CPU / GPU の時間・描いた三角形とドローコールの数を計る。
## 結果を JSON (既定 tmp/scenebench.json) に、上限ごとの部屋に入った直後の画面を tmp/scenebench-<上限>.png に書き、
## 全部の上限を終えたら「scenebench OK」を出して quit(0) する。CI のソフトウェア描画の数字は実機の fps ではなく、
## 変更の前後・上限の間の比として読む。

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
## 描く本数の上限の既定値 (DEFAULT_DRAW_BUDGET) を借りる
const HairFieldScript := preload("res://scripts/hair_field.gd")

## issue #56 で既定の毛の本数を上げる前に描いていた本数 (その頃は全部の毛を描いていた)。変更の前後を同じ描く本数で比べるため残す
const BEFORE_ISSUE_56_DRAWN_COUNT: int = 12000
## issue #65 で描く本数に上限を置く前に描いていた本数 (その頃の既定の毛の本数 120,000 本を全部描いていた)
const BEFORE_ISSUE_65_DRAWN_COUNT: int = 120000
## 既定の計測する描く本数の上限。issue #56・#65 の前に描いていた本数と今の既定の上限に、上限を決める時に比べた
## 既定の上限の 2 倍と、hairbench が全部描けると確かめた本数を足した
const DEFAULT_DRAW_BUDGETS: Array[int] = [
	BEFORE_ISSUE_56_DRAWN_COUNT,
	BEFORE_ISSUE_65_DRAWN_COUNT,
	HairFieldScript.DEFAULT_DRAW_BUDGET,
	HairFieldScript.DEFAULT_DRAW_BUDGET * 2,
	HairbenchScript.FULL_DRAW_MAX_COUNT,
]
## JSON レポートの既定出力先 (Makefile の scenebench target が参照するパス)
const DEFAULT_JSON_PATH: String = "tmp/scenebench.json"
## ベンチマーク専用のセーブパス (遊んでいる人のセーブに左右されない)
const BENCH_SAVE_PATH: String = "user://scenebench_save_data.json"
## 屋敷を作り直した後、計測の前に進めるフレーム数 (screenshot.gd の撮影前の 4 フレームと揃え、
## パイプラインの生成を含む最初の重いフレームを計測から外すため倍にした)
const WARMUP_FRAMES: int = 8
## 1 つの場面で計るフレーム数 (ランナーのぶれを中央値で均すため。いちばん重い描く本数 1,000,000 本でも CI の実測
## (run 45942145058) で 1 フレーム 1 秒前後で、全部の上限 × 2 場面を計っても screenshot-and-movie の job が 7 分前後で
## 終わり、timeout-minutes に収まった数)
const MEASURE_FRAMES: int = 20
## 掃除ロボットが動いている間の場面で、1 フレームごとに進める時計の秒数 (掃除ロボット 1 台が 1 秒に 1 本取るため、
## 持てる上限の台数で 1 フレームあたり 1 本前後を取る速さ)
const AUTOMATION_STEP_SECONDS: float = 0.25


## 値の列から中央値・最小・最大・平均を返す (空なら全部 0)。0.01 に丸めるのは、ms の値で比べる差
## (変更の前後で数 ms〜数十 ms) より十分細かく、JSON を読みやすい桁数にするため
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


## 描く本数の上限ごとのベンチマークを順に実行し、JSON 保存と終了コード出力を行う
func _run() -> void:
	var raw_budgets: String = OS.get_environment("SCENEBENCH_DRAW_BUDGETS")
	var budgets: Array[int] = (
		DEFAULT_DRAW_BUDGETS.duplicate()
		if raw_budgets.strip_edges().is_empty()
		else HairbenchScript.parse_counts(raw_budgets)
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
	for budget: int in budgets:
		var entry: Dictionary = await _measure_budget(main, game_state, budget)
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


## 既定の毛の本数・描く本数の上限 budget で屋敷を作り直し、2 つの場面を計って結果の辞書を返す
func _measure_budget(main: Node3D, game_state: Node, budget: int) -> Dictionary:
	var count: int = MansionTuningScript.DEFAULT_HAIR_COUNT
	var tuning: MansionTuning = MansionTuningScript.new()
	tuning.hair_count = count
	main.mansion_world.hair_draw_budget = budget
	var rebuild_start: int = Time.get_ticks_usec()
	game_state.apply_tuning_and_rebuild(tuning, false)
	var rebuild_ms: float = float(Time.get_ticks_usec() - rebuild_start) / 1000.0
	var hair_field: Node3D = main.mansion_world.get_hair_field()
	var placed: int = hair_field.get_remaining_count()
	var drawn: int = 0
	for surface_index: int in range(hair_field.get_surface_count()):
		drawn += hair_field.get_surface_visible_instance_count(surface_index)

	_stand_at_entrance(main, game_state)
	await physics_frame
	var enter_metrics: Dictionary = await _measure_frames(main, false)
	var png_path: String = "tmp/scenebench-%d.png" % budget
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
	var robots_metrics: Dictionary = await _measure_frames(main, true)

	var ok: bool = placed == count and drawn <= budget and save_status == OK and robots_ok
	print(
		(
			"scenebench budget=%d count=%d placed=%d drawn=%d ok=%s rebuild_ms=%.1f enter_frame_ms=%.1f"
			+ " enter_primitives=%d robots_frame_ms=%.1f robots_advance_ms=%.2f"
		)
		% [
			budget, count, placed, drawn, str(ok), rebuild_ms,
			float(enter_metrics["frame_ms"]["median"]), int(enter_metrics["primitives"]["median"]),
			float(robots_metrics["frame_ms"]["median"]), float(robots_metrics["advance_ms"]["median"]),
		]
	)
	return {
		"draw_budget": budget,
		"count": count,
		"placed": placed,
		"drawn": drawn,
		"ok": ok,
		# 作り直しは数十〜数百 ms で、1 回だけ計るため 0.1 ms より細かい桁は意味を持たない
		"rebuild_ms": snappedf(rebuild_ms, 0.1),
		"png_path": png_path,
		"enter": enter_metrics,
		"robots": robots_metrics,
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

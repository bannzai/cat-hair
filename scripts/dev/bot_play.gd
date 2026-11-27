extends SceneTree
## 自動テストプレイ。bot (scripts/dev/playtest_bot.gd) が屋敷をはじめから遊ぶ。
## 引数 --simulate (make simulate): headless で、測る節目にすべて着くか MAX_GAME_SECONDS に届くまで 1 フレームの中で遊び切り、
## 節目までのゲーム内の時間を tmp/simulate.json に書いて「simulate OK」を出す。
## 引数 --frames=<N> --fps=<N> [--steps-per-frame=<N>] (make playtest): 描画付きで、1 フレームごとに bot の手を
## 行い (早送り)、録画を撮って「playtest OK」を出す。
## どちらも遊んでいる人のセーブと分けた一時セーブを使い、終わったら消す。

## AudioManager の準備・後始末と GameState の用意を借りる検証の土台
const HeadlessCheck := preload("res://scripts/dev/headless_check.gd")
## 遊ぶメインシーン
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
## 音声管理ノード (録画の終わりに音を止める)
const AudioManagerScript := preload("res://scripts/audio/audio_manager.gd")
## JSON 保存ストレージスクリプト (一時セーブを消す)
const SaveStorageScript := preload("res://scripts/state/save_storage.gd")
## 録画の引数の読み方と、音声解放待ちのフレーム数の計算 (movie target と同じ)
const MovieScript := preload("res://scripts/dev/movie.gd")
## 自動テストプレイの bot
const PlaytestBotScript := preload("res://scripts/dev/playtest_bot.gd")
## 環境変数が空の時に既定値を使う読み方 (hairbench.gd と同じ)
const HairbenchScript := preload("res://scripts/dev/hairbench.gd")
## 自動テストプレイだけが使う一時セーブのパス (遊んでいる人のセーブと分ける)
const SAVE_PATH: String = "user://bot_play_save_data.json"
## 集計の書き出し先 (make simulate の成果物)
const SIMULATE_JSON_PATH: String = "res://tmp/simulate.json"
## 取りこぼしと珍しい毛の抽選のシード。毎回同じ結果にして、値を変えた前後の所要時間を比べられるようにする
const BOT_SEED: int = 13
## make simulate を打ち切るゲーム内の秒 (3 時間)。目標の上限 120 分を超えても全員がご機嫌にならない時に、
## 届いた所までを JSON に書いて終える長さ
const MAX_GAME_SECONDS: float = 10800.0
## simulate (録画の固定 FPS が無い) で音声の解放を待つフレーム数を数える FPS。Godot の既定の
## physics/common/physics_ticks_per_second (60) に合わせ、headless の 1 フレームを 1/60 秒とみなす
const SIMULATE_RELEASE_FPS: int = 60


## tree の準備が終わってから _run() を始める
func _initialize() -> void:
	_run.call_deferred()


## 引数で simulate か playtest を選んで遊ぶ
func _run() -> void:
	var user_args: PackedStringArray = OS.get_cmdline_user_args()
	var simulate: bool = user_args.has("--simulate")
	var options: Dictionary = MovieScript.parse_movie_options(user_args)
	if not simulate and options.is_empty():
		push_error(
			"bot_play.gd には --simulate か、正の --frames=<N> と --fps=<N> が必要 (引数: %s)"
			% str(user_args)
		)
		quit(1)
		return
	# movie.gd・integration.gd と同じく、メインシーンを置く前に AudioManager を用意し、終わりに音を止めて解放を待つ
	# (再生中のまま終えると ObjectDB と Resource のリーク警告が出る。movie.gd の先頭の CI 実測)
	var audio_handle: Dictionary = HeadlessCheck.prepare_audio_manager(self, _audio_settings_path())
	SaveStorageScript.delete_save_file(SAVE_PATH)
	var state_handle: Dictionary = HeadlessCheck.acquire_game_state(root, SAVE_PATH)
	var main: Node3D = MAIN_SCENE.instantiate()
	main.auto_advance_time = false
	main.auto_advance_automation = false
	root.add_child(main)
	current_scene = main
	await process_frame
	main.enter_mansion()
	var bot: RefCounted = PlaytestBotScript.new()
	bot.setup(main, BOT_SEED)
	var ok: bool = false
	if simulate:
		ok = _simulate(bot)
	else:
		ok = await _play_frames(bot, options)
	(audio_handle["manager"] as AudioManagerScript).stop_all()
	for _i: int in range(
		MovieScript.calc_release_frames(int(options.get("fps", SIMULATE_RELEASE_FPS)))
	):
		await process_frame
	if simulate:
		# 録画は --quit-after で終えるため、メインシーンと GameState を残したまま終わる (movie.gd と同じ)。
		# headless の simulate は自分で quit するので、リーク警告を出さないよう解放する
		root.remove_child(main)
		main.free()
		if bool(state_handle["created"]):
			var game_state: Node = state_handle["node"]
			root.remove_child(game_state)
			game_state.free()
	HeadlessCheck.cleanup_audio_manager(self, audio_handle, _audio_settings_path())
	SaveStorageScript.delete_save_file(SAVE_PATH)
	quit(0 if ok else 1)


## 録画の時に AudioManager の音量設定を置く一時ファイル (遊んでいる人の設定と分ける)
func _audio_settings_path() -> String:
	return ProjectSettings.globalize_path("res://tmp/playtest-audio-settings.cfg")


## bot を測る節目にすべて着くか打ち切りの秒まで遊ばせ、集計を JSON に書く。
## 打ち切りの秒は環境変数 SIMULATE_MAX_SECONDS、書き出し先は SIMULATE_JSON で上書きできる
## (make failure-path がわざと失敗させるため。未指定の時は make simulate の既定 MAX_GAME_SECONDS・SIMULATE_JSON_PATH)。
## 書けて、最初の道具を買う節目に届いていたら true
func _simulate(bot: RefCounted) -> bool:
	var raw_max: String = OS.get_environment("SIMULATE_MAX_SECONDS")
	var max_seconds: float = raw_max.to_float() if raw_max.is_valid_float() else MAX_GAME_SECONDS
	var json_path: String = HairbenchScript.env_or_default(
		OS.get_environment("SIMULATE_JSON"), SIMULATE_JSON_PATH
	)
	while not bot.all_milestones_reached() and bot.elapsed_seconds() < max_seconds:
		bot.step()
	var report: Dictionary = bot.report()
	report["max_game_seconds"] = max_seconds
	report["seed"] = BOT_SEED
	var file: FileAccess = FileAccess.open(ProjectSettings.globalize_path(json_path), FileAccess.WRITE)
	if file == null:
		push_error("bot_play.gd: %s を書けない (%s)" % [json_path, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("simulate milestones (minutes): %s" % JSON.stringify(report["milestone_minutes"]))
	# 所要時間が目標から外れても結果は書いて成功にするが、最初の道具すら買えない時は bot か値の壊れなので失敗にする
	if not (report["milestone_minutes"] as Dictionary).has(PlaytestBotScript.MILESTONE_FIRST_TOOL):
		push_error("bot_play.gd: %d 秒遊んでも最初の道具を買えなかった" % int(max_seconds))
		return false
	print("simulate OK")
	return true


## 録画の総フレーム数 options["total_frames"] から音声解放待ちと終了の余裕を除いたフレームで、1 フレームに
## steps_per_frame 手ずつ遊ぶ (引数 --steps-per-frame=<N>。無い・正でない時は 1)。遊び終えたら true
func _play_frames(bot: RefCounted, options: Dictionary) -> bool:
	var steps_per_frame: int = maxi(1, _int_arg(OS.get_cmdline_user_args(), "--steps-per-frame="))
	for _i: int in range(
		MovieScript.calc_record_frames(
			int(options["total_frames"]), MovieScript.calc_release_frames(int(options["fps"]))
		)
	):
		for _step: int in range(steps_per_frame):
			bot.step()
		await process_frame
	# 録画に節目が映らなかった時に理由を追えるよう、集計の要点をログに残す
	var report: Dictionary = bot.report()
	for key: String in [
		"milestone_seconds", "purchases", "count_by_action", "removed_by_tool", "empty_results", "final"
	]:
		print("playtest %s: %s" % [key, JSON.stringify(report[key])])
	print("playtest OK")
	return true


## 引数 args のうち prefix で始まる物の後ろの整数 (無い時は 0)
static func _int_arg(args: PackedStringArray, prefix: String) -> int:
	for arg: String in args:
		if arg.begins_with(prefix):
			return arg.trim_prefix(prefix).to_int()
	return 0

extends SceneTree
## 自動テストプレイ。bot (scripts/dev/playtest_bot.gd) が屋敷をはじめから遊ぶ。
## 引数 --simulate (make simulate): headless で、住人全員がご機嫌になるか MAX_GAME_SECONDS に届くまで 1 フレームの中で遊び切り、
## 節目までのゲーム内の時間を tmp/simulate.json に書いて「simulate OK」を出す。
## 引数 --frames=<N> --fps=<N> (make playtest): 描画付きで、1 フレームごとに bot の 1 手を行い、録画を撮って「playtest OK」を出す。
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
	# acquire_game_state は調整値の引数を渡さないため、--room-count= などの引数 (make playtest の
	# PLAYTEST_TUNING_ARGS) で屋敷を組み直す。調整値の引数が無ければ既定の屋敷のまま
	(state_handle["node"] as Node).initialize_from_storage(SAVE_PATH, user_args)
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


## bot を住人全員のご機嫌か MAX_GAME_SECONDS まで遊ばせ、集計を SIMULATE_JSON_PATH に書く。書けたら true
func _simulate(bot: RefCounted) -> bool:
	while not bot.all_happy_reached() and bot.elapsed_seconds() < MAX_GAME_SECONDS:
		bot.step()
	var report: Dictionary = bot.report()
	report["max_game_seconds"] = MAX_GAME_SECONDS
	report["seed"] = BOT_SEED
	var file: FileAccess = FileAccess.open(
		ProjectSettings.globalize_path(SIMULATE_JSON_PATH), FileAccess.WRITE
	)
	if file == null:
		push_error("bot_play.gd: %s を書けない (%s)" % [SIMULATE_JSON_PATH, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("simulate milestones (minutes): %s" % JSON.stringify(report["milestone_minutes"]))
	print("simulate OK")
	return true


## 録画の総フレーム数 options["total_frames"] から音声解放待ちと終了の余裕を除いたフレームで、1 フレーム 1 手ずつ遊ぶ。
## 遊び終えたら true
func _play_frames(bot: RefCounted, options: Dictionary) -> bool:
	for _i: int in range(
		MovieScript.calc_record_frames(
			int(options["total_frames"]), MovieScript.calc_release_frames(int(options["fps"]))
		)
	):
		bot.step()
		await process_frame
	print("playtest milestones (seconds): %s" % JSON.stringify(bot.get_milestones()))
	print("playtest OK")
	return true

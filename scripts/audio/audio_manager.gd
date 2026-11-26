extends Node
## BGM と効果音の再生と設定管理を一元化する autoload ノード。
## どの場面・出来事でどの音を鳴らすかは AudioCatalog を正とし、
## オン・オフの永続化とバス消音は AudioSettings に委譲する。

## 設定が変更された時に通知する
signal settings_changed(bgm_enabled: bool, sfx_enabled: bool)

## 場面名・出来事名のカタログ
const AudioCatalog := preload("res://scripts/audio/audio_catalog.gd")
## オン・オフ設定の保存・適用クラス
const AudioSettings := preload("res://scripts/audio/audio_settings.gd")
## project.godot の [autoload] に登録するノード名 (実行時取得の単一の正)
const NODE_NAME: String = "AudioManager"
## 効果音を同時に重ねて鳴らせるプレイヤーの本数。手で毛を連続して抜く序盤に 1 秒あたり 2〜3 回鳴らしつつ
## UI 操作やお金取得の効果音が重なっても先行の音が途切れにくい余裕として 4 本にした (実機調整で変更可)
const SFX_POOL_SIZE: int = 4
## 再生中に終了した時に AudioServer の解放を待つ時間 (ms)。scripts/dev/headless_check.gd の
## AUDIO_RELEASE_TIME (0.25 秒) に合わせた値で、Godot 4.7.2-stable (ubuntu-24.04 / --audio-driver Dummy)
## の CI 実測で 0 ms では ObjectDB 4 件・Resource 2 件のリーク警告が出、250 ms で解消することを確認した
const EXIT_RELEASE_WAIT_MSEC: int = 250

## 現在のオン・オフ設定
var _settings: RefCounted = AudioSettings.new()
## 設定ファイルの保存先 (テスト時のみ差し替える)
var _settings_path: String = AudioSettings.DEFAULT_PATH
## BGM 再生用プレイヤー
var _bgm_player: AudioStreamPlayer = null
## 効果音再生用プレイヤープール
var _sfx_players: Array[AudioStreamPlayer] = []
## プールが全て再生中の時に上書きする次のインデックス
var _next_sfx_index: int = 0
## 現在再生中 (または一時停止中) の BGM 場面名
var _current_bgm_name: String = ""
## ウィンドウが裏に回ったことで一時停止中か
var _paused_by_focus: bool = false
## 読み込み済み AudioStream のキャッシュ (パス -> AudioStream)
var _stream_cache: Dictionary = {}
## 再生開始後に外部から stop_all() されていないか (_exit_tree() での解放待ち判定に使う)
var _needs_exit_release_wait: bool = false
## BGM プレイヤーで play() を実際に呼んだ回数 (同一曲の継続検証用)
var _bgm_play_count: int = 0
## 効果音プレイヤーで play() を実際に呼んだ回数
var _sfx_play_count: int = 0
## 直近に鳴らした効果音の出来事名
var _last_sfx_event_name: String = ""
## 直近に効果音を鳴らしたプール内のインデックス (-1 は未再生)
var _last_sfx_player_index: int = -1


## SceneTree の root から登録済みの AudioManager ノードを実行時に解決する
static func resolve(tree: SceneTree) -> Node:
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(NODE_NAME)


## プレイヤーを準備し、保存済みの設定を読み込んでバスへ適用する
func _ready() -> void:
	_setup_players()
	reload_settings(_settings_path)


## ツリーから外れる時にすべての再生を止め、AudioServer の解放を待つ
func _exit_tree() -> void:
	# Godot の Node._exit_tree() は子から親の順に呼ばれるため (公式ドキュメント:
	# https://docs.godotengine.org/en/stable/classes/class_node.html
	# #class-node-private-method-exit-tree、2026-11-26 確認)、この時点では子 AudioStreamPlayer の
	# playing は既に false になる。そのため再生中に終了したかは _needs_exit_release_wait で判定する
	var should_wait: bool = _needs_exit_release_wait
	stop_all()
	_clear_streams()
	if should_wait:
		OS.delay_msec(EXIT_RELEASE_WAIT_MSEC)


## アプリが裏に回った時に BGM を一時停止し、戻った時に再開する。
## 公式ドキュメント (https://docs.godotengine.org/en/stable/classes/class_mainloop.html 2026-11-26 確認):
## FOCUS_OUT / FOCUS_IN は desktop と mobile で OS から届き、PAUSED / RESUMED は Android / iOS 固有
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		_pause_bgm_for_focus()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_APPLICATION_RESUMED:
		_resume_bgm_from_focus()


## 指定パスの設定を読み直してバスへ適用する (初回起動時とテストで使用)
func reload_settings(path: String = AudioSettings.DEFAULT_PATH) -> Error:
	_settings_path = path
	var err: Error = _settings.load_from_path(_settings_path)
	AudioSettings.apply_to_audio_server(_settings.bgm_enabled, _settings.sfx_enabled)
	settings_changed.emit(_settings.bgm_enabled, _settings.sfx_enabled)
	return err


## 場面名に対応する BGM をループ再生する。同じ曲が再生中なら頭から流し直さず継続する
func play_bgm(scene_name: String) -> bool:
	if _bgm_player == null:
		return false
	var path: String = AudioCatalog.resolve_bgm_path(scene_name)
	if path.is_empty():
		return false
	if _current_bgm_name == scene_name and _bgm_player.playing:
		return true
	var stream: AudioStream = load_stream(path)
	if stream == null:
		return false
	_enable_loop(stream)
	_bgm_player.stream = stream
	_bgm_player.stream_paused = false
	_paused_by_focus = false
	_bgm_player.play()
	_bgm_play_count += 1
	_current_bgm_name = scene_name
	_needs_exit_release_wait = true
	return true


## 再生中の BGM を止める
func stop_bgm() -> void:
	if _bgm_player != null:
		_bgm_player.stop()
		_bgm_player.stream_paused = false
	_paused_by_focus = false
	_current_bgm_name = ""


## 出来事名に対応する効果音を鳴らす。未登録の出来事や読み込み失敗時はゲームを止めず false を返す
func play_sfx(event_name: String) -> bool:
	if _sfx_players.is_empty():
		return false
	var path: String = AudioCatalog.resolve_sfx_path(event_name)
	if path.is_empty():
		return false
	var stream: AudioStream = load_stream(path)
	if stream == null:
		return false
	var player_index: int = _pick_sfx_player_index()
	var player: AudioStreamPlayer = _sfx_players[player_index]
	player.stream = stream
	player.play()
	_sfx_play_count += 1
	_last_sfx_event_name = event_name
	_last_sfx_player_index = player_index
	_needs_exit_release_wait = true
	return true


## BGM とすべての効果音の再生を止める
func stop_all() -> void:
	stop_bgm()
	for player: AudioStreamPlayer in _sfx_players:
		if player != null:
			player.stop()
	_next_sfx_index = 0
	_needs_exit_release_wait = false


## 音声リソースをキャッシュ付きで読み込む。存在しない・AudioStream でないリソースは null を返す
func load_stream(path: String) -> AudioStream:
	if _stream_cache.has(path):
		return _stream_cache[path] as AudioStream
	if not ResourceLoader.exists(path):
		return null
	var loaded: Resource = ResourceLoader.load(path)
	if not (loaded is AudioStream):
		return null
	var stream: AudioStream = loaded as AudioStream
	_stream_cache[path] = stream
	return stream


## BGM がオンか
func is_bgm_enabled() -> bool:
	return _settings.bgm_enabled


## 効果音がオンか
func is_sfx_enabled() -> bool:
	return _settings.sfx_enabled


## BGM のオン・オフを切り替え、バスへ適用して端末へ保存する
func set_bgm_enabled(enabled: bool) -> Error:
	_settings.bgm_enabled = enabled
	AudioSettings.apply_to_audio_server(_settings.bgm_enabled, _settings.sfx_enabled)
	var err: Error = _settings.save_to_path(_settings_path)
	settings_changed.emit(_settings.bgm_enabled, _settings.sfx_enabled)
	return err


## 効果音のオン・オフを切り替え、バスへ適用して端末へ保存する
func set_sfx_enabled(enabled: bool) -> Error:
	_settings.sfx_enabled = enabled
	AudioSettings.apply_to_audio_server(_settings.bgm_enabled, _settings.sfx_enabled)
	var err: Error = _settings.save_to_path(_settings_path)
	settings_changed.emit(_settings.bgm_enabled, _settings.sfx_enabled)
	return err


## 現在選択中の BGM 場面名を返す (停止中は空文字)
func get_current_bgm_name() -> String:
	return _current_bgm_name


## BGM がフォーカス喪失で一時停止中か
func is_bgm_paused_by_focus() -> bool:
	return _paused_by_focus


## BGM プレイヤーで play() を実際に呼んだ累計回数を返す
func get_bgm_play_count() -> int:
	return _bgm_play_count


## 効果音プレイヤーで play() を実際に呼んだ累計回数を返す
func get_sfx_play_count() -> int:
	return _sfx_play_count


## 直近に鳴らした効果音の出来事名を返す
func get_last_sfx_event_name() -> String:
	return _last_sfx_event_name


## 直近に効果音を鳴らしたプール内のインデックスを返す (未再生は -1)
func get_last_sfx_player_index() -> int:
	return _last_sfx_player_index


## BGM 用と効果音用の AudioStreamPlayer を子ノードとして生成する
func _setup_players() -> void:
	if _bgm_player == null:
		_bgm_player = AudioStreamPlayer.new()
		_bgm_player.name = "BGMPlayer"
		_bgm_player.bus = AudioCatalog.BUS_BGM
		add_child(_bgm_player)
	if _sfx_players.is_empty():
		for index: int in range(SFX_POOL_SIZE):
			var player: AudioStreamPlayer = AudioStreamPlayer.new()
			player.name = "SFXPlayer%d" % index
			player.bus = AudioCatalog.BUS_SFX
			add_child(player)
			_sfx_players.append(player)


## 空いている効果音プレイヤーのインデックスを返す。全部再生中ならラウンドロビンで再利用する
func _pick_sfx_player_index() -> int:
	for index: int in range(_sfx_players.size()):
		if not _sfx_players[index].playing:
			return index
	var chosen_index: int = _next_sfx_index
	_next_sfx_index = (_next_sfx_index + 1) % _sfx_players.size()
	return chosen_index


## プレイヤーとキャッシュが保持する AudioStream 参照を解放する
func _clear_streams() -> void:
	if _bgm_player != null:
		_bgm_player.stream = null
	for player: AudioStreamPlayer in _sfx_players:
		if player != null:
			player.stream = null
	_stream_cache.clear()


## ループ対応のストリーム形式ならループ再生を有効にする
func _enable_loop(stream: AudioStream) -> void:
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true


## アプリが裏に回った時の BGM 一時停止
func _pause_bgm_for_focus() -> void:
	if _bgm_player != null and _bgm_player.playing and not _bgm_player.stream_paused:
		_bgm_player.stream_paused = true
		_paused_by_focus = true


## アプリが表に戻った時の BGM 再開 (明示停止中や未再生時は再開しない)
func _resume_bgm_from_focus() -> void:
	if _bgm_player != null and _paused_by_focus:
		_bgm_player.stream_paused = false
		_paused_by_focus = false

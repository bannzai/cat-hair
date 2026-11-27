extends RefCounted
## 「はじめる」で屋敷に入った後の BGM の入力統合テスト (scripts/dev/integration.gd から呼ぶ)。
## 屋敷の BGM として差し替えた素材 (issue #79) が再生中であることを、素材の長さで見分けて確かめる。

## 音声カタログ (屋敷の BGM の場面名とパス)
const AudioCatalog := preload("res://scripts/audio/audio_catalog.gd")
## 音声の再生の入口 (BGMPlayer のノード名)
const AudioManagerScript := preload("res://scripts/audio/audio_manager.gd")
## 屋敷の BGM の素材 (assets/audio/bgm_mansion.ogg = Hot Spring Town) の長さ (秒)。
## commit した素材を ffprobe で測った値 (160.000000 秒。issue #79)。差し替え前の Snowfall は 49.5 秒
const MANSION_BGM_LENGTH_SEC: float = 160.0
## 素材の長さの比較の許容幅 (秒)。デコーダが末尾のサンプル数を数え違えても誤検知せず、
## 差し替え前の素材 (110 秒以上の差) は確実に落とすため
const MANSION_BGM_LENGTH_TOLERANCE_SEC: float = 1.0


## 屋敷に入った直後 (main の enter_mansion の後) に呼び、屋敷の BGM が差し替えた素材で再生中であることを
## checker (integration の SceneTree) の _check に記録する
static func verify_mansion_bgm(checker: SceneTree, audio_manager: AudioManagerScript) -> void:
	checker._check(
		audio_manager.get_current_bgm_name() == AudioCatalog.BGM_MANSION,
		"屋敷に入ると屋敷 BGM に切り替わる (実際: %s)" % audio_manager.get_current_bgm_name(),
	)
	var bgm_player: AudioStreamPlayer = audio_manager.get_node_or_null(
		AudioManagerScript.BGM_PLAYER_NAME
	)
	checker._check(
		bgm_player != null and bgm_player.playing and bgm_player.stream != null,
		"屋敷に入ると BGMPlayer が素材を再生している",
	)
	if bgm_player == null or bgm_player.stream == null:
		return
	checker._check(
		bgm_player.stream.resource_path == AudioCatalog.resolve_bgm_path(AudioCatalog.BGM_MANSION),
		(
			"屋敷 BGM の素材のパスが %s (実際: %s)"
			% [AudioCatalog.resolve_bgm_path(AudioCatalog.BGM_MANSION), bgm_player.stream.resource_path]
		),
	)
	checker._check(
		(
			absf(bgm_player.stream.get_length() - MANSION_BGM_LENGTH_SEC)
			<= MANSION_BGM_LENGTH_TOLERANCE_SEC
		),
		(
			"屋敷 BGM の素材が差し替えた曲 (%s 秒) である (実際: %s 秒)"
			% [MANSION_BGM_LENGTH_SEC, bgm_player.stream.get_length()]
		),
	)

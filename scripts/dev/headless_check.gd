extends SceneTree
## headless で実行する検証 (scripts/dev/selfcheck.gd と scripts/dev/integration.gd) が継承する土台。
## 検証の失敗の記録と、結果を exit code と完了の行で返す終わり方を持つ。
## release ビルドでは assert が消えるため、assert ではなく _check() と _finish() で結果を返す。

## 音声解放待ち時間と AudioManager 解決の単一の正
const AudioManagerScript := preload("res://scripts/audio/audio_manager.gd")

## 検証が 1 件でも失敗したか。true なら exit code 1 で終わる
var failed: bool = false


## テスト・撮影用の一時ファイルが存在すれば削除する (全 dev スクリプト共通)
static func remove_file_if_exists(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


## 検証・撮影用に AudioManager を準備し、指定の一時設定パスを読み込む (無ければ新規生成して root へ置く)
static func prepare_audio_manager(tree: SceneTree, settings_path: String) -> Dictionary:
	remove_file_if_exists(settings_path)
	var audio_manager: AudioManagerScript = AudioManagerScript.resolve(tree) as AudioManagerScript
	var created: bool = false
	if audio_manager == null:
		audio_manager = AudioManagerScript.new()
		audio_manager.name = AudioManagerScript.NODE_NAME
		tree.root.add_child(audio_manager)
		created = true
	audio_manager.reload_settings(settings_path)
	return {"manager": audio_manager, "created": created}


## prepare_audio_manager で準備した AudioManager を後始末する (自分で作ったノードのみ解放)
static func cleanup_audio_manager(
	tree: SceneTree, handle: Dictionary, settings_path: String
) -> void:
	if bool(handle.get("created", false)):
		var audio_manager: Node = handle.get("manager") as Node
		if audio_manager != null:
			tree.root.remove_child(audio_manager)
			audio_manager.free()
	remove_file_if_exists(settings_path)


## cond が false なら label を ERROR として出し、失敗として記録する。
## ERROR の行頭には実行した検証のスクリプトの名前 (selfcheck / integration) を付ける
func _check(cond: bool, label: String) -> void:
	if not cond:
		push_error("%s FAIL: %s" % [_script_name(), label])
		failed = true


## 失敗が無ければ「<スクリプトの名前> OK」を出して exit code 0、あれば exit code 1 で終える。
## Makefile は exit code と OK の行の両方で成否を判定する
func _finish() -> void:
	if failed:
		quit(1)
		return
	print("%s OK" % _script_name())
	quit(0)


## 実行中の検証のスクリプトのファイル名 (拡張子なし)
func _script_name() -> String:
	return get_script().resource_path.get_file().get_basename()

extends SceneTree
## headless で実行する検証 (scripts/dev/selfcheck.gd と scripts/dev/integration.gd) が継承する土台。
## 検証の失敗の記録と、結果を exit code と完了の行で返す終わり方を持つ。
## release ビルドでは assert が消えるため、assert ではなく _check() と _finish() で結果を返す。

## 状態管理 autoload スクリプト (検証用 GameState 準備ヘルパーで使用)
const GameStateScript := preload("res://scripts/state/game_state.gd")
## 音を止めてから終了するまで待つ時間 (秒)。止めた BGM・効果音の再生は AudioServer がミキシングを数回進めてから
## 解放するため、待たずに終了すると再生がリークとして WARNING / ERROR に出る (bannzai/kageboshi の CI で実測した値。
## ミキシング数回分に余裕を持たせてある)。描画付きの scripts/dev/screenshot.gd もこの値で待つ
const AUDIO_RELEASE_TIME: float = 0.25

## 検証が 1 件でも失敗したか。true なら exit code 1 で終わる
var failed: bool = false


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


## 検証用の autoload GameState を取得 (未登録なら生成・登録) し、指定セーブパスで初期化する
static func acquire_game_state(tree_root: Window, target_save_path: String) -> Dictionary:
	var created: bool = false
	var game_state: Node = tree_root.get_node_or_null("GameState")
	if game_state == null:
		game_state = GameStateScript.new()
		game_state.name = "GameState"
		tree_root.add_child(game_state)
		created = true
	game_state.initialize_from_storage(target_save_path)
	return {"node": game_state, "created": created}

extends "res://scripts/dev/headless_check.gd"
## メインシーンを tree に置いて動かす入力統合テスト (headless)。画面の遷移や入力で変わる振る舞いを足したら、
## ここに検証を足す。実行方法は AGENTS.md「検証方法」を参照。

## 動かして確かめるメインシーン
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")


## tree の準備が終わってから _run() を始める (シーンの追加は _initialize() の後でないとできない)
func _initialize() -> void:
	_run.call_deferred()


## フレームを進めながら検証するため、同じ実行中に重ねて呼び出さない
func _run() -> void:
	var main: Control = MAIN_SCENE.instantiate()
	root.add_child(main)
	# _ready が走り、子のノードが tree に入るのを 1 フレーム待つ
	await process_frame
	var title_label: Label = main.get_node_or_null("Layout/TitleLabel")
	_check(title_label != null, "題名の Label (Layout/TitleLabel) がある")
	if title_label != null:
		_check(not title_label.text.is_empty(), "題名の Label に文字が入っている")
	_check(main.theme != null and main.theme.default_font != null, "メインシーンの theme に既定フォントが入っている")
	root.remove_child(main)
	main.free()
	_finish()

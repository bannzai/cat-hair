extends "res://scripts/dev/headless_check.gd"
## メインシーンを tree に置いて動かす入力統合テスト (headless)。画面の遷移や入力で変わる振る舞いを足したら、
## ここに検証を足す。実行方法は AGENTS.md「検証方法」を参照。

## 動かして確かめるメインシーン
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
## 毛の描画の試作シーン
const HAIR_PROTOTYPE_SCENE: PackedScene = preload("res://scenes/hair_prototype.tscn")


## tree の準備が終わってから _run() を始める (シーンの追加は _initialize() の後でないとできない)
func _initialize() -> void:
	_run.call_deferred()


## フレームを進めながら検証するため、同じ実行中に重ねて呼び出さない
func _run() -> void:
	await _verify_main_scene()
	await _verify_hair_prototype_scene()
	_finish()


## メインシーンの題名ラベルと既定フォントが正しく読み込まれるか検証する
func _verify_main_scene() -> void:
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


## 毛の描画試作シーンで 2 表面への配置と 1 本削除が連動するか検証する
func _verify_hair_prototype_scene() -> void:
	var hair_prototype: Node3D = HAIR_PROTOTYPE_SCENE.instantiate()
	root.add_child(hair_prototype)
	await process_frame

	var field: Node3D = hair_prototype.get_hair_field()
	_check(field != null, "HairPrototype に HairField ノードがある")
	_check(field.get_surface_count() == 2, "床とソファの 2 表面が登録されている")

	_check(
		hair_prototype.populate_hairs(100) == 100 and hair_prototype.get_remaining_count() == 100,
		"試作シーンに 100 本の毛を配置できる"
	)
	_check(
		field.get_surface_visible_instance_count(0)
		+ field.get_surface_visible_instance_count(1)
		== 100,
		"2 表面の visible_instance_count 合計が 100"
	)

	var removed: bool = hair_prototype.remove_hair(0)
	await process_frame
	_check(
		removed
		and hair_prototype.get_remaining_count() == 99
		and field.get_surface_visible_instance_count(0)
		+ field.get_surface_visible_instance_count(1)
		== 99,
		"試作シーンで 1 本だけ抜いて残り本数・visible_instance_count が 99 になる"
	)

	root.remove_child(hair_prototype)
	hair_prototype.free()

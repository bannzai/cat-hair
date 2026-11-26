extends Node
## ゲーム進行状態・調整値・セーブデータを 1 か所で管理する autoload シングルトン。
## UI ノードや 3D ノードは状態を持たず、このノードの参照とシグナルを通じて同期する。
## --headless --script 検証から安全に扱うため、他スクリプトからは登録名の静的参照を使わず
## root.get_node_or_null("GameState") で取得する。

## 進行状態や残り毛本数が変わった時に発火し、HUD 等の表示を更新する
signal state_changed
## 調整値から屋敷レイアウトが組み立て直された時に発火し、3D 空間を再構築する
signal mansion_rebuilt(layout: MansionLayout)

## セーブデータ全体型スクリプト
const SaveDataScript := preload("res://scripts/data/save_data.gd")
## 開発者向け調整値型スクリプト
const MansionTuningScript := preload("res://scripts/data/mansion_tuning.gd")
## 屋敷ビルダーロジックスクリプト
const MansionBuilderScript := preload("res://scripts/mansion/mansion_builder.gd")
## JSON 保存ストレージスクリプト
const SaveStorageScript := preload("res://scripts/state/save_storage.gd")

## セーブデータの保存先パス (テスト時に差し替え可能)
var save_path: String = SaveStorageScript.DEFAULT_SAVE_PATH
## 現在のセーブデータ (Single State of Truth)
var save_data: SaveData = null
## 現在の調整値から組み立てた屋敷レイアウト
var current_layout: MansionLayout = null
## 起動時に有効なセーブデータを整合したまま読み込めたか
var loaded_from_save: bool = false
## コマンドライン引数で調整値を上書き起動したか (既存セーブの意図しない終了時上書きを防ぐ)
var launched_with_cmdline_override: bool = false


## autoload 起動時に保存ファイルとコマンドライン引数から初期状態を構築する
func _ready() -> void:
	if save_data == null:
		initialize_from_storage(save_path, _collect_cmdline_args())


## ウィンドウ終了要求時に現在の状態を保存する。
## コマンドライン引数で調整値を上書きした試験起動では既存の進行を壊さないよう自動保存しない。
## 前提 (Godot 4 公式ドキュメント「Handling quit requests」):
## application/config/auto_accept_quit (既定 true) では終了直前に全ノードへ
## NOTIFICATION_WM_CLOSE_REQUEST が通知されるため、ここで保存を完了させる。
func _notification(what: int) -> void:
	if (
		what == NOTIFICATION_WM_CLOSE_REQUEST
		and save_data != null
		and not launched_with_cmdline_override
	):
		save_current_state()


## 指定パスの保存データとコマンドライン引数から状態を初期化する。
## コマンドライン引数で調整値が指定されている場合は、その値で屋敷を新しく組み立て、
## 終了時の自動保存による既存セーブ上書きを無効にする。
func initialize_from_storage(
	target_path: String = SaveStorageScript.DEFAULT_SAVE_PATH,
	cmdline_args: PackedStringArray = PackedStringArray(),
) -> void:
	save_path = target_path
	var loaded_save: SaveData = SaveStorageScript.load_from_path(save_path)
	launched_with_cmdline_override = MansionTuningScript.has_cmdline_override(cmdline_args)

	if loaded_save != null and not launched_with_cmdline_override:
		save_data = loaded_save
		loaded_from_save = true
		current_layout = MansionBuilderScript.build_layout(save_data.tuning)
		_reconcile_progress_with_layout()
	else:
		loaded_from_save = false
		_create_fresh_save(
			MansionTuningScript.from_cmdline_args(
				cmdline_args,
				loaded_save.tuning if loaded_save != null else MansionTuningScript.new(),
			)
		)
	mansion_rebuilt.emit(current_layout)
	state_changed.emit()


## 現在の調整値を使って新しい屋敷・進行データを作り直し、保存する
func start_new_game(custom_tuning: MansionTuning = null) -> void:
	loaded_from_save = false
	launched_with_cmdline_override = false
	_create_fresh_save(
		custom_tuning.clamped() if custom_tuning != null else get_tuning().clamped()
	)
	save_current_state()
	mansion_rebuilt.emit(current_layout)
	state_changed.emit()


## 開発者向けの調整値を適用し、その値の屋敷を作り直して永続化する
func apply_tuning_and_rebuild(new_tuning: MansionTuning, persist: bool = true) -> void:
	var safe_tuning: MansionTuning = (
		new_tuning.clamped() if new_tuning != null else MansionTuningScript.new()
	)
	if save_data == null:
		_create_fresh_save(safe_tuning)
	else:
		save_data.tuning = safe_tuning
		current_layout = MansionBuilderScript.build_layout(safe_tuning)
		save_data.building_progress = MansionBuilderScript.build_initial_progress(
			current_layout,
			safe_tuning,
		)
	if persist:
		launched_with_cmdline_override = false
		save_current_state()
	mansion_rebuilt.emit(current_layout)
	state_changed.emit()


## 現在の状態を JSON として保存する
func save_current_state() -> Error:
	if save_data == null:
		return ERR_UNCONFIGURED
	return SaveStorageScript.save_to_path(save_data, save_path)


## 現在の調整値を返す
func get_tuning() -> MansionTuning:
	if save_data == null or save_data.tuning == null:
		return MansionTuningScript.new()
	return save_data.tuning


## 屋敷全体に残っている毛の総本数を返す
func get_total_remaining_hairs() -> int:
	if save_data == null or save_data.building_progress == null:
		return 0
	return save_data.building_progress.total_remaining_hairs()


## 現在の所持金を返す
func get_money() -> int:
	if save_data == null or save_data.building_progress == null:
		return 0
	return save_data.building_progress.money


## 指定面の残り毛本数を返す
func get_surface_hair_count(surface_id: StringName) -> int:
	if save_data == null or save_data.building_progress == null:
		return 0
	var surface: SurfaceHair = save_data.building_progress.find_surface_hair(surface_id)
	return surface.total_count() if surface != null else 0


## 指定の調整値から新しいレイアウトと初期 SaveData を生成する
func _create_fresh_save(target_tuning: MansionTuning) -> void:
	var safe_tuning: MansionTuning = target_tuning.clamped()
	current_layout = MansionBuilderScript.build_layout(safe_tuning)
	save_data = SaveDataScript.new()
	save_data.schema_version = SaveDataScript.SCHEMA_VERSION
	save_data.tuning = safe_tuning
	save_data.building_progress = MansionBuilderScript.build_initial_progress(
		current_layout,
		safe_tuning,
	)


## 読み込んだ進行の面・探し物・住人の ID 一覧が現在レイアウトと一致しない場合は
## 進行を作り直し、タイトルで「続きから」を出さないよう loaded_from_save を降ろす
func _reconcile_progress_with_layout() -> void:
	if save_data == null or save_data.building_progress == null or current_layout == null:
		return
	if (
		not _surface_ids_match_layout()
		or not _found_item_ids_match_layout()
		or not _resident_ids_match_layout()
	):
		save_data.building_progress = MansionBuilderScript.build_initial_progress(
			current_layout,
			save_data.tuning,
		)
		loaded_from_save = false


## 保存データの surface_hairs の件数と ID 集合が現在レイアウトの surfaces と完全一致するか
func _surface_ids_match_layout() -> bool:
	var expected_ids: Dictionary = {}
	for surface: MansionLayout.SurfaceDef in current_layout.surfaces:
		expected_ids[surface.surface_id] = true
	var actual_ids: Dictionary = {}
	for entry: SurfaceHair in save_data.building_progress.surface_hairs:
		actual_ids[entry.surface_id] = true
	return _id_sets_equal(expected_ids, actual_ids)


## 保存データの found_items の件数と ID 集合が現在レイアウトの found_item_spots と完全一致するか
func _found_item_ids_match_layout() -> bool:
	var expected_ids: Dictionary = {}
	for spot: MansionLayout.FoundItemSpotDef in current_layout.found_item_spots:
		expected_ids[spot.found_item_id] = true
	var actual_ids: Dictionary = {}
	for item: FoundItemProgress in save_data.building_progress.found_items:
		actual_ids[item.found_item_id] = true
	return _id_sets_equal(expected_ids, actual_ids)


## 保存データの resident_moods の件数と住人 ID 集合が現在レイアウトの rooms と完全一致するか
func _resident_ids_match_layout() -> bool:
	var expected_ids: Dictionary = {}
	for room: MansionLayout.RoomDef in current_layout.rooms:
		expected_ids[MansionBuilderScript.resident_id_for_room(room.room_id)] = true
	return _id_sets_equal(expected_ids, save_data.building_progress.resident_moods)


## 2 つの辞書のキー集合が件数・要素ともに一致するか
static func _id_sets_equal(expected_keys: Dictionary, actual_keys: Dictionary) -> bool:
	if expected_keys.size() != actual_keys.size():
		return false
	for expected_key: Variant in expected_keys.keys():
		if not actual_keys.has(expected_key):
			return false
	return true


## 起動時のユーザー引数とエンジン引数をまとめて返す
static func _collect_cmdline_args() -> PackedStringArray:
	return PackedStringArray()

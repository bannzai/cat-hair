extends Node
## ゲーム進行状態・調整値・セーブデータを 1 か所で管理する autoload シングルトン。
## UI ノードや 3D ノードは状態を持たず、このノードの参照とシグナルを通じて同期する。
## --headless --script 検証から安全に扱うため、他スクリプトからは登録名の静的参照を使わず
## root.get_node_or_null("GameState") で取得する。

signal state_changed
signal mansion_rebuilt(layout: MansionLayout)

const SaveDataScript := preload("res://scripts/data/save_data.gd")
const MansionTuningScript := preload("res://scripts/data/mansion_tuning.gd")
const MansionBuilderScript := preload("res://scripts/mansion/mansion_builder.gd")
const SaveStorageScript := preload("res://scripts/state/save_storage.gd")

## セーブデータの保存先パス (テスト時に差し替え可能)
var save_path: String = SaveStorageScript.DEFAULT_SAVE_PATH
## 現在のセーブデータ (Single State of Truth)
var save_data: SaveData = null
## 現在の調整値から組み立てた屋敷レイアウト
var current_layout: MansionLayout = null
## 起動時に有効なセーブデータを読み込めたか
var loaded_from_save: bool = false


func _ready() -> void:
	if save_data == null:
		initialize_from_storage(save_path, _collect_cmdline_args())


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and save_data != null:
		save_current_state()


## 指定パスの保存データとコマンドライン引数から状態を初期化する。
## コマンドライン引数で調整値が指定されている場合は、その値で屋敷を新しく組み立てる。
func initialize_from_storage(
	target_path: String = SaveStorageScript.DEFAULT_SAVE_PATH,
	cmdline_args: PackedStringArray = PackedStringArray(),
) -> void:
	save_path = target_path
	var loaded: SaveData = SaveStorageScript.load_from_path(save_path)
	var has_override: bool = MansionTuningScript.has_cmdline_override(cmdline_args)

	if loaded != null and not has_override:
		save_data = loaded
		loaded_from_save = true
		current_layout = MansionBuilderScript.build_layout(save_data.tuning)
		_reconcile_progress_with_layout()
	else:
		var base_tuning: MansionTuning = (
			loaded.tuning if loaded != null else MansionTuningScript.new()
		)
		var effective_tuning: MansionTuning = MansionTuningScript.from_cmdline_args(
			cmdline_args,
			base_tuning,
		)
		loaded_from_save = false
		_create_fresh_save(effective_tuning)
	mansion_rebuilt.emit(current_layout)
	state_changed.emit()


## 現在の調整値を使って新しい屋敷・進行データを作り直し、保存する
func start_new_game(custom_tuning: MansionTuning = null) -> void:
	var target_tuning: MansionTuning = (
		custom_tuning.clamped()
		if custom_tuning != null
		else get_tuning().clamped()
	)
	loaded_from_save = false
	_create_fresh_save(target_tuning)
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


## 読み込んだセーブデータの面一覧と現在のレイアウトの面一覧が一致しない場合は補完する
func _reconcile_progress_with_layout() -> void:
	if save_data == null or save_data.building_progress == null or current_layout == null:
		return
	var expected_ids: Dictionary = {}
	for surface: MansionLayout.SurfaceDef in current_layout.surfaces:
		expected_ids[surface.surface_id] = true
	var actual_ids: Dictionary = {}
	for entry: SurfaceHair in save_data.building_progress.surface_hairs:
		actual_ids[entry.surface_id] = true
	if expected_ids.size() != actual_ids.size():
		save_data.building_progress = MansionBuilderScript.build_initial_progress(
			current_layout,
			save_data.tuning,
		)
		return
	for sid: Variant in expected_ids.keys():
		if not actual_ids.has(sid):
			save_data.building_progress = MansionBuilderScript.build_initial_progress(
				current_layout,
				save_data.tuning,
			)
			return


static func _collect_cmdline_args() -> PackedStringArray:
	var combined: PackedStringArray = PackedStringArray()
	for arg: String in OS.get_cmdline_user_args():
		combined.append(arg)
	for arg: String in OS.get_cmdline_args():
		combined.append(arg)
	return combined

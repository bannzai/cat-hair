class_name SaveStorage
extends RefCounted
## セーブデータの JSON ファイル永続化。
## 一時ファイルへ書き出して検証してから置換することで、書き込み途中の失敗時に既存セーブを保護する。
## 壊れたファイルや存在しないファイルを読み込んでもエンジンの ERROR ログを出さずに
## null を返し、呼び出し側で新規開始へ安全にフォールバックできる。

## セーブデータ全体型スクリプト
const SaveDataScript := preload("res://scripts/data/save_data.gd")

## 既定の保存先パス (Godot のユーザーデータ領域 user:// 直下の単一 JSON)
const DEFAULT_SAVE_PATH: String = "user://save_data.json"


## SaveData を一時ファイル経由で JSON として path に書き出す。成功時は OK を返す
static func save_to_path(save_data: SaveData, path: String = DEFAULT_SAVE_PATH) -> Error:
	if save_data == null or path.is_empty():
		return ERR_INVALID_PARAMETER
	var tmp_path: String = "%s.tmp" % path
	var file: FileAccess = FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var wrote: bool = file.store_string(JSON.stringify(save_data.to_dict(), "\t"))
	file.flush()
	var write_err: Error = file.get_error()
	file.close()
	if not wrote or write_err != OK or load_from_path(tmp_path) == null:
		delete_save_file(tmp_path)
		return write_err if write_err != OK else ERR_FILE_CANT_WRITE
	var rename_err: Error = DirAccess.rename_absolute(
		ProjectSettings.globalize_path(tmp_path),
		ProjectSettings.globalize_path(path),
	)
	if rename_err != OK:
		if FileAccess.file_exists(path):
			delete_save_file(tmp_path)
		return rename_err
	return OK


## path から SaveData を読み込む。ファイル不在・読込失敗・JSON 破損・型不一致時は null を返す
static func load_from_path(path: String = DEFAULT_SAVE_PATH) -> SaveData:
	if not FileAccess.file_exists(path):
		return null
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var text: String = file.get_as_text()
	file.close()
	if text.strip_edges().is_empty():
		return null
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return null
	return SaveDataScript.from_dict(json.data)


## 保存ファイルが存在するか
static func has_save_file(path: String = DEFAULT_SAVE_PATH) -> bool:
	return FileAccess.file_exists(path)


## 保存ファイルを削除する (存在しない場合は OK を返す)
static func delete_save_file(path: String = DEFAULT_SAVE_PATH) -> Error:
	if not FileAccess.file_exists(path):
		return OK
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

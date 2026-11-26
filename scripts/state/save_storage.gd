class_name SaveStorage
extends RefCounted
## セーブデータの JSON ファイル永続化。
## 壊れたファイルや存在しないファイルを読み込んでもエンジンの ERROR ログを出さずに
## null を返し、呼び出し側で新規開始へ安全にフォールバックできる。

const SaveDataScript := preload("res://scripts/data/save_data.gd")

## 既定の保存先パス
const DEFAULT_SAVE_PATH: String = "user://save_data.json"


## SaveData を JSON として path に書き出す。成功時は OK を返す
static func save_to_path(save_data: SaveData, path: String = DEFAULT_SAVE_PATH) -> Error:
	if save_data == null:
		return ERR_INVALID_PARAMETER
	var json_text: String = JSON.stringify(save_data.to_dict(), "\t")
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(json_text)
	file.close()
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
	var parse_err: Error = json.parse(text)
	if parse_err != OK:
		return null
	return SaveDataScript.from_dict(json.data)


## 保存ファイルが存在するか
static func has_save_file(path: String = DEFAULT_SAVE_PATH) -> bool:
	return FileAccess.file_exists(path)


## 保存ファイルを削除する (存在しない場合は OK を返す)
static func delete_save_file(path: String = DEFAULT_SAVE_PATH) -> Error:
	if not FileAccess.file_exists(path):
		return OK
	var abs_path: String = ProjectSettings.globalize_path(path)
	return DirAccess.remove_absolute(abs_path)

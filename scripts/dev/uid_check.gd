extends "res://scripts/dev/headless_check.gd"
## プロジェクトの全部の `<名前>.gd.uid` を、Godot が識別子として読めて、そのスクリプトに結び付けていることの検証 (headless)。
## make uid (Godot を起動せずに作る .uid。scripts/ci/create-missing-uid.sh) の .uid を Godot が使えるかを CI で確かめる。
## Godot は Godot が書かない表記の .uid があっても import で書き換えず警告も出さないため、中身の比較では分からない
## (確認用の PR https://github.com/bannzai/cat-hair/pull/50 で、uid://zz99 のまま import が通った)。
## 実行: make uidcheck (CI の check-and-export が実行する)。テスト: scripts/ci/test/test-uidcheck.sh

## 探さないディレクトリ (Godot のキャッシュ)
const SKIPPED_DIR: String = "res://.godot"
## .uid を付けるスクリプトの拡張子
const SCRIPT_EXTENSION: String = ".gd"
## Godot がスクリプトの横に置く識別子のファイルの拡張子
const UID_EXTENSION: String = ".uid"


func _initialize() -> void:
	var uid_paths: PackedStringArray = _find_uid_paths("res://")
	_check(not uid_paths.is_empty(), ".gd.uid が 1 つも見つからない")
	for uid_path: String in uid_paths:
		var script_path: String = uid_path.trim_suffix(UID_EXTENSION)
		var text: String = FileAccess.get_file_as_string(uid_path).strip_edges()
		var id: int = ResourceUID.text_to_id(text)
		_check(id != ResourceUID.INVALID_ID, "%s の %s を Godot が識別子として読めない" % [uid_path, text])
		# text_to_id は a〜z を 0〜25、0〜9 を 25〜34 と読むため、Godot が書かない表記 (z・9 を含む等) も
		# 別の識別子として読めてしまう。Godot が書く表記 (id_to_text) と一致することも見る
		_check(
			ResourceUID.id_to_text(id) == text,
			"%s の %s が Godot の書く表記 %s と違う" % [uid_path, text, ResourceUID.id_to_text(id)]
		)
		_check(
			ResourceLoader.get_resource_uid(script_path) == id,
			"%s の識別子 %s が %s に結び付いていない" % [uid_path, text, script_path]
		)
	_finish()


## dir の配下の `<名前>.gd.uid` のパスを集める (.gdignore を置いたディレクトリと .godot は Godot が読まないため除く)
func _find_uid_paths(dir: String) -> PackedStringArray:
	var found: PackedStringArray = []
	if dir.trim_suffix("/") == SKIPPED_DIR or FileAccess.file_exists(dir.path_join(".gdignore")):
		return found
	for file_name: String in DirAccess.get_files_at(dir):
		if file_name.ends_with(SCRIPT_EXTENSION + UID_EXTENSION):
			found.append(dir.path_join(file_name))
	for sub_dir: String in DirAccess.get_directories_at(dir):
		found.append_array(_find_uid_paths(dir.path_join(sub_dir)))
	return found

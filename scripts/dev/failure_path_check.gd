extends "res://scripts/dev/headless_check.gd"
## 検証の土台 (headless_check.gd) の失敗の経路を確かめる。わざと 1 件失敗させ、ERROR の行が出て exit code 1 で
## 終わり、完了の行が出ないことを Makefile の failure-path target が検査する (土台が壊れて常に OK を返すようになっても
## selfcheck / integration は通ってしまうため)。


## 必ず失敗する検証を 1 件記録して終える
func _initialize() -> void:
	_check(false, "わざと失敗させた検証")
	_finish()

#!/usr/bin/env bash
# Godot が生成する .uid / .import のうち、commit されていないものを 1 行 1 パスで出す。
# 対象は、未追跡のファイルと、commit 済みで中身が書き換わったファイル (Godot の版の更新で変わる等)。
# .gitignore で無視されるファイル (.godot/ の下等) は出さない。
# .github/workflows/ci.yml の check-and-export が、Godot の import の後にリポジトリの直下で実行する。
# 何も書き換えないため、何度実行しても結果は同じ (冪等)。
#
# 出力: 該当のパス (重複なし・辞書順)。無ければ何も出さない
# exit code: git の exit code (該当の有無では変わらない)
set -u
# core.quotePath=false: 既定のままだと、日本語などのファイル名が引用符と 8 進の表記で出て、呼び出し側が
# そのパスのファイルを見つけられない
git -c core.quotePath=false ls-files --others --modified --exclude-standard -- '*.uid' '*.import' | sort -u

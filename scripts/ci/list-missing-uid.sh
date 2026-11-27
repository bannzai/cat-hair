#!/usr/bin/env bash
# GDScript (.gd) のうち、Godot がリソース参照に使う付随ファイル `<名前>.gd.uid` が git の index に無いものについて、
# その .uid のパスを 1 行 1 パスで出す。Godot を起動しない手元で、push の前に .uid の欠けを見つけるために使う
# (Makefile の check-generated と uid が呼ぶ)。
# 対象の .gd は、index にあるものと、未追跡で .gitignore に無視されないもの。.gdignore を置いたディレクトリの
# 配下は Godot が読まないため対象外。.uid が作業ツリーにあっても index に無ければ出す (commit されないため)。
# .import (素材の取り込みの設定) は Godot の importer の既定値を含み手元では作れないため、この検査の対象外
# (CI の check-and-export が見つけて artifact cat-hair-generated に上げる。手順は AGENTS.md「検証方法」)。
# 何も書き換えないため、何度実行しても結果は同じ (冪等)。
#
# 出力: 該当の .uid のパス (重複なし・バイト順)。無ければ何も出さない
# exit code: 0 = 調べられた (該当の有無では変わらない) / 0 以外 = git が失敗した (git のリポジトリでない等)
set -u -o pipefail

# core.quotePath=false: 既定のままだと、日本語などのファイル名が引用符と 8 進の表記で出て、.uid の有無を調べられない
scripts=$(git -c core.quotePath=false ls-files --cached --others --exclude-standard -- '*.gd') || exit $?
indexed_uids=$(git -c core.quotePath=false ls-files --cached -- '*.gd.uid') || exit $?

# パスの祖先のディレクトリ (リポジトリの直下を除く) に .gdignore があれば 0 を返す
under_gdignore() {
  local dir
  dir=$(dirname "$1")
  while [ "$dir" != "." ] && [ "$dir" != "/" ]; do
    if [ -e "$dir/.gdignore" ]; then
      return 0
    fi
    dir=$(dirname "$dir")
  done
  return 1
}

[ -n "$scripts" ] || exit 0
printf '%s\n' "$scripts" | while IFS= read -r script; do
  # 削除したが index に残っている .gd は commit で消えるため対象外
  [ -f "$script" ] || continue
  under_gdignore "$script" && continue
  # grep -q は一致した所で読むのをやめ、pipefail の下では printf の書き込みの失敗が「無い」と取り違えられるため、
  # 入力を最後まで読む grep の出力を捨てる形で調べる
  if ! printf '%s\n' "$indexed_uids" | grep -xF -- "$script.uid" > /dev/null; then
    printf '%s\n' "$script.uid"
  fi
done | LC_ALL=C sort -u

#!/usr/bin/env bash
# scripts/ci/list-uncommitted-generated.sh のテスト。一時ディレクトリに git リポジトリを作り、出すべきファイルと、
# それに似ているが出さないファイルの両側で出力を確かめる。一時ディレクトリは終了時に消すため、何度実行しても
# 結果は同じ (冪等)。
# 使い方: bash scripts/ci/test/test-list-uncommitted-generated.sh (リポジトリのどこからでも実行できる)
# exit code: 0 = 全件 PASS / 1 = FAIL あり
set -u
target="$(cd "$(dirname "$0")/.." && pwd)/list-uncommitted-generated.sh"
failed=0
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# 一時リポジトリで git を実行する。利用者の hook と署名の設定を持ち込まない
repo_git() {
  git -C "$work" -c core.hooksPath=/dev/null -c commit.gpgsign=false -c user.name=test -c user.email=test@example.com "$@"
}

# 名前と期待する出力を受け取り、一時リポジトリでの検査の出力が期待と違えば FAIL として記録する
expect() {
  actual=$(cd "$work" && bash "$target")
  if [ "$actual" = "$2" ]; then
    echo "PASS: $1"
  else
    echo "FAIL: $1 (期待 [$2] 実際 [$actual])"
    failed=1
  fi
}

repo_git init -q
mkdir -p "$work/scripts" "$work/assets" "$work/.godot"
printf '.godot/\n' > "$work/.gitignore"
printf 'uid://aaa\n' > "$work/scripts/main.gd.uid"
printf '[remap]\n' > "$work/assets/font.ttf.import"
printf 'extends Node\n' > "$work/scripts/main.gd"
repo_git add -A
repo_git commit -q -m init

expect "全部 commit 済みなら何も出さない" ""

printf 'extends Control\n' > "$work/scripts/main.gd"
printf 'extends Node\n' > "$work/scripts/new.gd"
expect ".uid / .import でないファイルの変更と未追跡は出さない" ""

printf 'uid://zzz\n' > "$work/.godot/cache.uid"
expect ".gitignore で無視される場所の .uid は出さない" ""

printf 'uid://bbb\n' > "$work/scripts/new.gd.uid"
expect "未追跡の .uid を出す" "scripts/new.gd.uid"

printf '[remap]\nchanged=true\n' > "$work/assets/font.ttf.import"
expect "commit 済みで書き換わった .import も出す" "$(printf 'assets/font.ttf.import\nscripts/new.gd.uid')"

printf 'uid://ccc\n' > "$work/scripts/main.gd.uid"
expect "commit 済みで書き換わった .uid も出し、辞書順に並ぶ" "$(printf 'assets/font.ttf.import\nscripts/main.gd.uid\nscripts/new.gd.uid')"

repo_git add -A
repo_git commit -q -m update
expect "commit すると何も出さない" ""

exit "$failed"

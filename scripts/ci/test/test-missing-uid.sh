#!/usr/bin/env bash
# scripts/ci/list-missing-uid.sh と scripts/ci/create-missing-uid.sh のテスト。一時ディレクトリに git リポジトリを作り、
# 出すべき .uid と、それに似ているが出さない .uid の両側で出力を確かめ、作った .uid の形と冪等性を確かめる。
# 一時ディレクトリは終了時に消すため、何度実行しても結果は同じ (冪等)。
# 使い方: bash scripts/ci/test/test-missing-uid.sh (リポジトリのどこからでも実行できる)
# exit code: 0 = 全件 PASS / 1 = FAIL あり
set -u
# 呼び出し元が GIT_DIR 等を持っていると、一時リポジトリではなく呼び出し元のリポジトリに init・commit してしまうため外す
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
ci_dir="$(cd "$(dirname "$0")/.." && pwd)"
list="$ci_dir/list-missing-uid.sh"
create="$ci_dir/create-missing-uid.sh"
failed=0
work=$(mktemp -d)
not_a_repo=$(mktemp -d)
trap 'rm -rf "$work" "$not_a_repo"' EXIT

# 一時リポジトリで git を実行する。利用者の hook と署名の設定を持ち込まない
repo_git() {
  git -C "$work" -c core.hooksPath=/dev/null -c commit.gpgsign=false -c user.name=test -c user.email=test@example.com "$@"
}

# 一時リポジトリで、利用者の git の設定 (core.quotePath 等) が無い状態でスクリプトを実行する
run_in_work() {
  (cd "$work" && GIT_CONFIG_GLOBAL=/dev/null bash "$1")
}

# 名前 ($1)・実際の値 ($2)・期待する値 ($3) を受け取り、一致すれば PASS、違えば FAIL を出して failed を 1 にする
check() {
  if [ "$2" = "$3" ]; then
    echo "PASS: $1"
  else
    echo "FAIL: $1 (期待 [$3] 実際 [$2])"
    failed=1
  fi
}

repo_git init -q
mkdir -p "$work/scripts" "$work/documents/tools" "$work/.godot"
printf '.godot/\n' > "$work/.gitignore"
printf 'extends Node\n' > "$work/scripts/main.gd"
printf 'uid://cupfev30faqwj\n' > "$work/scripts/main.gd.uid"
repo_git add -A
repo_git commit -q -m init

check "全部の .gd の .uid が commit 済みなら何も出さない" "$(run_in_work "$list")" ""

printf 'extends Node\n' > "$work/scripts/new.gd"
check "未追跡の .gd の .uid が無ければ出す" "$(run_in_work "$list")" "scripts/new.gd.uid"

printf 'extends Node\n' > "$work/scripts/staged.gd"
repo_git add scripts/staged.gd
check "index にある .gd の .uid が無ければ出し、バイト順に並ぶ" "$(run_in_work "$list")" "$(printf 'scripts/new.gd.uid\nscripts/staged.gd.uid')"

printf 'uid://bbb\n' > "$work/scripts/new.gd.uid"
check ".uid が作業ツリーにあっても index に無ければ出す" "$(run_in_work "$list")" "$(printf 'scripts/new.gd.uid\nscripts/staged.gd.uid')"
repo_git add scripts/new.gd.uid
check "index に入れた .uid は出さない" "$(run_in_work "$list")" "scripts/staged.gd.uid"

printf 'extends Node\n' > "$work/.godot/cache.gd"
check ".gitignore で無視される場所の .gd は対象外" "$(run_in_work "$list")" "scripts/staged.gd.uid"

touch "$work/documents/.gdignore"
printf 'extends Node\n' > "$work/documents/tools/sample.gd"
check ".gdignore を置いたディレクトリの配下の .gd は対象外" "$(run_in_work "$list")" "scripts/staged.gd.uid"

printf 'extends Node\n' > "$work/scripts/猫.gd"
check "日本語のファイル名は、引用符や 8 進の表記にせずそのまま出す" "$(run_in_work "$list")" "$(printf 'scripts/staged.gd.uid\nscripts/猫.gd.uid')"
rm "$work/scripts/猫.gd"

repo_git rm -q --cached scripts/new.gd.uid
rm "$work/scripts/new.gd" "$work/scripts/new.gd.uid"
repo_git commit -q -m staged

# create-missing-uid.sh: 欠けた .uid を作り、作ったパスを出す
check "作業ツリーに無い .uid を作り、そのパスを出す" "$(run_in_work "$create")" "scripts/staged.gd.uid"
content=$(cat "$work/scripts/staged.gd.uid" 2> /dev/null)
# 形: Godot の id_to_text が書く uid:// と a〜y・0〜8 の 1〜13 文字 (63 bit の最大値 uid://d4n4ub6itg400 が 13 文字)
if printf '%s\n' "$content" | grep -qxE 'uid://[a-y0-8]{1,13}'; then
  echo "PASS: 作った .uid は Godot と同じ形の uid:// の 1 行"
else
  echo "FAIL: 作った .uid は Godot と同じ形の uid:// の 1 行 (実際 [$content])"
  failed=1
fi
check "作った .uid は既存の識別子と重ならない" "$([ "$content" != 'uid://cupfev30faqwj' ] && echo ok)" "ok"
check "作った .uid は改行で終わる" "$(tail -c 1 "$work/scripts/staged.gd.uid" | od -An -c | tr -d ' ')" '\n'

check "2 回目は何も作らない (冪等)" "$(run_in_work "$create")" ""
check "2 回目は作った .uid を書き換えない" "$(cat "$work/scripts/staged.gd.uid")" "$content"

printf 'uid://keepme\n' > "$work/scripts/other.gd.uid"
printf 'extends Node\n' > "$work/scripts/other.gd"
check "作業ツリーに既にある .uid は作らない (index に無くても書き換えない)" "$(run_in_work "$create")" ""
check "既にある .uid の中身は変わらない" "$(cat "$work/scripts/other.gd.uid")" "uid://keepme"

(cd "$not_a_repo" && GIT_CONFIG_GLOBAL=/dev/null GIT_CEILING_DIRECTORIES="$(dirname "$not_a_repo")" bash "$list" > /dev/null 2>&1)
if [ "$?" -ne 0 ]; then
  echo "PASS: git のリポジトリでない場所では失敗する (該当なしと取り違えない)"
else
  echo "FAIL: git のリポジトリでない場所では失敗する (exit 0 で終わった)"
  failed=1
fi

exit "$failed"

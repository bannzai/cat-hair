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
printf 'uid://ccc\n' > "$work/scripts/猫.gd.uid"
repo_git add scripts/猫.gd scripts/猫.gd.uid
check "日本語のファイル名の .uid が index にあれば出さない" "$(run_in_work "$list")" "scripts/staged.gd.uid"
repo_git rm -q --cached scripts/猫.gd scripts/猫.gd.uid
rm "$work/scripts/猫.gd" "$work/scripts/猫.gd.uid"

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

# git のリポジトリでない場所 ($not_a_repo) でスクリプトを実行し、exit code だけを出す (標準出力は $not_a_repo/out に残す)
exit_code_outside_repo() {
  (cd "$not_a_repo" && GIT_CONFIG_GLOBAL=/dev/null GIT_CEILING_DIRECTORIES="$(dirname "$not_a_repo")" "$@" > "$not_a_repo/out" 2> /dev/null)
  echo "$?"
}
check "list: git のリポジトリでない場所では失敗する (該当なしと取り違えない)" "$([ "$(exit_code_outside_repo bash "$list")" -ne 0 ] && echo nonzero)" "nonzero"

check "create: git のリポジトリでない場所では失敗する (list の失敗を伝える)" "$([ "$(exit_code_outside_repo bash "$create")" -ne 0 ] && echo nonzero)" "nonzero"
check "create: git のリポジトリでない場所では何も作ったと出さない" "$(cat "$not_a_repo/out")" ""

# 新しい一時リポジトリを作り直す (前のケースのファイルを持ち越さない)
reset_work() {
  chmod -R u+w "$work"
  rm -rf "$work"
  work=$(mktemp -d)
  repo_git init -q
}

reset_work
check "list: .gd が 1 つも無いリポジトリでは何も出さない" "$(run_in_work "$list")" ""
printf 'extends Node\n' > "$work/done.gd"
printf 'uid://ddd\n' > "$work/done.gd.uid"
repo_git add -A
repo_git commit -q -m done
check "create: 全部の .uid が commit 済みなら exit 0 で何も出さない" \
  "$(out=$(run_in_work "$create"); printf '%s exit=%s' "$out" "$?")" " exit=0"
check "create: 全部の .uid が commit 済みなら .uid を書き換えない" "$(cat "$work/done.gd.uid")" "uid://ddd"
printf 'extends Node\n' > "$work/deleted.gd"
repo_git add deleted.gd
repo_git commit -q -m deleted
rm "$work/deleted.gd"
check "list: 作業ツリーから消したが index に残る .gd は対象外" "$(run_in_work "$list")" ""

# 乱数を固定する: PATH の先頭に偽の od を置き、$FAKE_OD_VALUES のファイルの行を呼ばれるたびに 1 行ずつ出す
fake_bin=$(mktemp -d)
trap 'chmod -R u+w "$work"; rm -rf "$work" "$not_a_repo" "$fake_bin"' EXIT
cat > "$fake_bin/od" << 'EOF'
#!/usr/bin/env bash
count=$(( $(cat "$FAKE_OD_STATE" 2> /dev/null || echo 0) + 1 ))
echo "$count" > "$FAKE_OD_STATE"
sed -n "${count}p" "$FAKE_OD_VALUES"
EOF
chmod +x "$fake_bin/od"
# 偽の od に出させる値 (16 進の 8 byte。1 行が 1 回の呼び出し) を受け取り、create-missing-uid.sh を実行する
run_create_with_random() {
  printf '%s\n' "$@" > "$fake_bin/values"
  rm -f "$fake_bin/state"
  (cd "$work" && GIT_CONFIG_GLOBAL=/dev/null PATH="$fake_bin:$PATH" FAKE_OD_VALUES="$fake_bin/values" FAKE_OD_STATE="$fake_bin/state" bash "$create" > /dev/null)
}

# 期待する表記は Godot の id_to_text の値: 0 は 1 文字目の a、33 は 34 文字目の 8、34 は 2 桁の ba、
# 63 bit の最大値は core/io/resource_uid.cpp のコメントの uid://d4n4ub6itg400、
# 最後の値は Godot がこのリポジトリで作った uid://cupfev30faqwj の識別子に最上位の bit を立てたもの (落とされて同じ表記になる)
reset_work
for name in s1 s2 s3 s4 s5; do printf 'extends Node\n' > "$work/$name.gd"; done
run_create_with_random 0000000000000000 0000000000000021 0000000000000022 7fffffffffffffff d626e052a7d77025
check "create: 識別子を Godot の id_to_text と同じ表記にする" \
  "$(cat "$work/s1.gd.uid" "$work/s2.gd.uid" "$work/s3.gd.uid" "$work/s4.gd.uid" "$work/s5.gd.uid")" \
  "$(printf 'uid://a\nuid://8\nuid://ba\nuid://d4n4ub6itg400\nuid://cupfev30faqwj')"

reset_work
printf '[gd_scene format=3 uid="uid://ba"]\n' > "$work/main.tscn"
printf 'extends Node\n' > "$work/x.gd"
printf 'extends Node\n' > "$work/y.gd"
# 1 回目は main.tscn の uid://ba と、3 回目は同じ実行で x に付けた uid://a と重なるため、どちらも作り直す
run_create_with_random 0000000000000022 0000000000000000 0000000000000000 0000000000000021
check "create: .tscn にある識別子と、同じ実行で作った識別子に重なったら作り直す" \
  "$(cat "$work/x.gd.uid" "$work/y.gd.uid") $(cat "$fake_bin/state")" "$(printf 'uid://a\nuid://8') 4"

reset_work
mkdir "$work/readonly"
printf 'extends Node\n' > "$work/readonly/z.gd"
chmod 555 "$work/readonly"
created=$(cd "$work" && GIT_CONFIG_GLOBAL=/dev/null bash "$create" 2> /dev/null)
create_exit=$?
check "create: .uid を書き込めない時は失敗する" "$([ "$create_exit" -ne 0 ] && echo nonzero)" "nonzero"
check "create: 書き込めなかった .uid を作ったと出さない" "$created" ""
chmod 755 "$work/readonly"

# 一時ファイルへの書き込みの後の置き換え (mv) が失敗した時に、.uid も一時ファイルも残さない
fail_mv_bin=$(mktemp -d)
printf '#!/usr/bin/env bash\nexit 1\n' > "$fail_mv_bin/mv"
chmod +x "$fail_mv_bin/mv"
reset_work
printf 'extends Node\n' > "$work/m.gd"
(cd "$work" && GIT_CONFIG_GLOBAL=/dev/null PATH="$fail_mv_bin:$PATH" bash "$create" > /dev/null 2>&1)
mv_exit=$?
check "create: 置き換えに失敗した時は失敗する" "$([ "$mv_exit" -ne 0 ] && echo nonzero)" "nonzero"
check "create: 置き換えに失敗した時は .uid も一時ファイルも残さない" \
  "$(cd "$work" && ls -A | grep '^m\.gd\.uid' | tr '\n' ' ')" ""
rm -rf "$fail_mv_bin"

reset_work
printf 'extends Node\n' > "$work/-x.gd"
check "create: リポジトリの直下の - で始まる名前の .gd の .uid を作れる" \
  "$(run_in_work "$create" 2> /dev/null) / $(cd "$work" && ls -A | grep -- '^-x\.gd\.uid' | tr '\n' ' ')" "-x.gd.uid / -x.gd.uid "

# <名前>.gd.uid.tmp という名前で別の .uid への symlink が置かれていても、その先の .uid を書き換えない
reset_work
printf 'uid://keepme\n' > "$work/other.gd.uid"
printf 'extends Node\n' > "$work/n.gd"
ln -s other.gd.uid "$work/n.gd.uid.tmp"
check "create: 決まった名前の一時ファイルの symlink の先を書き換えない" \
  "$(run_in_work "$create") $(cat "$work/other.gd.uid")" "n.gd.uid uid://keepme"

# make check-generated: 一時リポジトリに Makefile と scripts/ci のスクリプトを写して実行する
# 一時リポジトリ (または $1 のディレクトリ) に Makefile と scripts/ci を写す
copy_make_files() {
  mkdir -p "$1/scripts/ci"
  cp "$ci_dir/../../Makefile" "$1/"
  cp "$ci_dir/list-missing-uid.sh" "$ci_dir/list-uncommitted-generated.sh" "$ci_dir/create-missing-uid.sh" "$1/scripts/ci/"
}
# 一時リポジトリで make check-generated を実行し、標準出力と exit code を 1 つの文字列で出す (標準エラーは $work.err)
run_check_generated() {
  local out code
  out=$(cd "$work" && GIT_CONFIG_GLOBAL=/dev/null make --no-print-directory check-generated 2> "$work.err")
  code=$?
  printf '%s exit=%s' "$out" "$([ "$code" -eq 0 ] && echo 0 || echo nonzero)"
}

reset_work
copy_make_files "$work"
mkdir -p "$work/scripts"
printf 'extends Node\n' > "$work/scripts/k.gd"
printf 'uid://keep\n' > "$work/scripts/k.gd.uid"
repo_git add -A
repo_git commit -q -m init
check "check-generated: 欠けが無ければ check-generated OK で成功する" "$(run_check_generated)" "check-generated OK exit=0"

printf 'extends Node\n' > "$work/scripts/new.gd"
check "check-generated: .gd の .uid が無ければそのパスを出して失敗する" "$(run_check_generated)" "scripts/new.gd.uid exit=nonzero"

printf 'uid://made\n' > "$work/scripts/new.gd.uid"
check "check-generated: 2 つの検査が同じ .uid を出しても 1 行にまとめる" "$(run_check_generated)" "scripts/new.gd.uid exit=nonzero"
check "check-generated: 件数を標準エラーに出す" "$(grep -c 'が 1 件あります' "$work.err")" "1"
rm "$work/scripts/new.gd" "$work/scripts/new.gd.uid" "$work.err"

printf 'dummy' > "$work/scripts/a.png.import"
check "check-generated: 未 commit の .import だけでも失敗する" "$(run_check_generated)" "scripts/a.png.import exit=nonzero"
rm "$work/scripts/a.png.import"

# 2 つの一覧のスクリプトの片方だけを失敗する偽物に差し替えても、check-generated が成功と出さずに失敗する
for broken in list-missing-uid.sh list-uncommitted-generated.sh; do
  cp "$work/scripts/ci/$broken" "$work.bak"
  printf '#!/usr/bin/env bash\nexit 3\n' > "$work/scripts/ci/$broken"
  check "check-generated: $broken だけが失敗しても成功と出さずに失敗する" "$(run_check_generated)" " exit=nonzero"
  mv "$work.bak" "$work/scripts/ci/$broken"
done
rm -f "$work.err"

copy_make_files "$not_a_repo"
check "check-generated: git のリポジトリでない場所では成功と出さずに失敗する" \
  "$(exit_code_outside_repo make --no-print-directory check-generated | sed 's/^0$/0/;s/^[1-9][0-9]*$/nonzero/') $(cat "$not_a_repo/out")" "nonzero "
rm -f "$work.err"

exit "$failed"

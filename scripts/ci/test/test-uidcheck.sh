#!/usr/bin/env bash
# make uidcheck (scripts/dev/uid_check.gd) のテスト。Godot を起動するため CI の check-and-export だけが実行する
# (このマシンでは実行しない。AGENTS.md「検証方法」)。
# 作業ツリーに検証用の .gd / .gd.uid を一時的に置き、通るべき状態で通り、壊れた .uid で落ちることを確かめる。
# 置いたファイルは終了時に消すため、何度実行しても結果は同じ (冪等)。
# 使い方: bash scripts/ci/test/test-uidcheck.sh <Godot の実行ファイル> (リポジトリの直下で実行する)
# exit code: 0 = 全件 PASS / 1 = FAIL あり / 2 = 引数が無い
set -u
if [ "$#" -lt 1 ]; then
  echo "使い方: bash scripts/ci/test/test-uidcheck.sh <Godot の実行ファイル>" >&2
  exit 2
fi
godot=$1
probe=scripts/dev/ci_uidcheck_probe.gd
ignored_dir=scripts/dev/ci_uidcheck_ignored
failed=0
trap 'rm -rf "$probe" "$probe.uid" "$ignored_dir" .godot/ci_uidcheck_probe.gd.uid' EXIT

# ケースの名前 ($1) のディレクトリ tmp/uidcheck-test/<名前>/ をログの置き場にして make uidcheck を実行し、成否と、
# ログの uid_check の FAIL の行のうち $probe の行を 1 つの文字列で出す。ケースごとにログを分けて残し
# (CI の Upload logs が artifact に上げる)、make の出力も make.log に残す。
# uidcheck.log が無い (import で落ちた) 時は no-log を出す
run_uidcheck() {
  local status=0 dir=tmp/uidcheck-test/$1
  rm -rf "$dir"
  mkdir -p "$dir"
  make --no-print-directory uidcheck GODOT="$godot" LOG_DIR="$dir" > "$dir/make.log" 2>&1 || status=$?
  printf '%s %s' "$([ "$status" -eq 0 ] && echo ok || echo failed)" \
    "$(if [ -f "$dir/uidcheck.log" ]; then
      grep -oE "uid_check FAIL: res://$probe\.uid .*" "$dir/uidcheck.log"
    else
      echo no-log
    fi)"
}

# 名前 ($1)・実際の値 ($2)・期待する値の正規表現 ($3) を受け取り、一致すれば PASS、違えば FAIL を出す
check() {
  if printf '%s' "$2" | grep -qE -- "$3"; then
    echo "PASS: $1"
  else
    echo "FAIL: $1 (期待 [$3] 実際 [$2])"
    failed=1
  fi
}

printf 'extends Node\n' > "$probe"
make --no-print-directory uid > /dev/null
check "make uid の .uid は通る" "$(run_uidcheck case-1)" '^ok $'

printf 'uid://BAD\n' > "$probe.uid"
check "Godot が読めない .uid (大文字) で落ちる" "$(run_uidcheck case-2)" \
  "^failed uid_check FAIL: res://$probe.uid の uid://BAD を Godot が識別子として読めない"

printf 'uid://zz99\n' > "$probe.uid"
check "Godot の書く表記と違う .uid (z・9 を含む) で落ちる" "$(run_uidcheck case-3)" \
  "^failed uid_check FAIL: res://$probe.uid の uid://zz99 が Godot の書く表記 uid://01ba と違う"

cp scripts/main.gd.uid "$probe.uid"
check "別のスクリプトと同じ識別子の .uid で落ちる" "$(run_uidcheck case-4)" \
  "^failed uid_check FAIL: res://$probe.uid の識別子 $(cat scripts/main.gd.uid) が res://$probe に結び付いていない"

rm -f "$probe" "$probe.uid"
mkdir -p "$ignored_dir"
touch "$ignored_dir/.gdignore"
printf 'extends Node\n' > "$ignored_dir/x.gd"
printf 'uid://BAD\n' > "$ignored_dir/x.gd.uid"
check ".gdignore を置いたディレクトリの .uid は見ない" "$(run_uidcheck case-5)" '^ok $'
rm -rf "$ignored_dir"

printf 'uid://BAD\n' > .godot/ci_uidcheck_probe.gd.uid
check ".godot の下の .uid は見ない" "$(run_uidcheck case-6)" '^ok $'

exit "$failed"

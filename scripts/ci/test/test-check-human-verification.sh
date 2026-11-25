#!/usr/bin/env bash
# scripts/ci/check-human-verification.sh のテスト。止まるべき PR 本文と、それに似ているが通るべき PR 本文の
# 両側で exit code を確かめる。何も書き換えない (冪等)。
# 使い方: bash scripts/ci/test/test-check-human-verification.sh (リポジトリのどこからでも実行できる)
# exit code: 0 = 全件 PASS / 1 = FAIL あり
set -u
target="$(cd "$(dirname "$0")/.." && pwd)/check-human-verification.sh"
failed=0

# 名前・期待する exit code・PR 本文を受け取り、検査の exit code が期待と違えば FAIL として記録する
expect() {
  PR_BODY="$3" bash "$target" > /dev/null 2>&1
  actual=$?
  if [ "$actual" -eq "$2" ]; then
    echo "PASS: $1"
  else
    echo "FAIL: $1 (期待 exit=$2 実際 exit=$actual)"
    failed=1
  fi
}

expect "節が無い本文は通る" 0 $'## 概要\n本文'
expect "「なし」だけの節は通る" 0 $'## 人間が確認\n\nなし\n\n## 次'
expect "- [ ] は止まる" 1 $'## 人間が確認\n- [ ] 実機で見る'
expect "* [ ] は止まる" 1 $'## 人間が確認\n* [ ] 実機で見る'
expect "1. [ ] は止まる" 1 $'## 人間が確認\n1. [ ] 実機で見る'
expect "字下げした - [ ] は止まる" 1 $'## 人間が確認\n  - [ ] 実機で見る'
expect "- [x] は通る" 0 $'## 人間が確認\n- [x] 実機で見る'
expect "チェック済みと未チェックが混ざると止まる" 1 $'## 人間が確認\n- [x] 済み\n- [ ] まだ'
expect "CRLF の - [ ] は止まる" 1 $'## 人間が確認\r\n- [ ] 実機で見る\r\n'
expect "CRLF の見出しでも節として読み、- [x] は通る" 0 $'## 人間が確認\r\n- [x] 実機で見る\r\n'
expect "次の節の - [ ] は数えない" 0 $'## 人間が確認\nなし\n## 別の節\n- [ ] これは対象外'
expect "前の節の - [ ] は数えない" 0 $'## 概要\n- [ ] これは対象外\n## 人間が確認\nなし'
expect "本文が空でも通る" 0 ""

exit "$failed"

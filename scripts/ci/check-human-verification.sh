#!/usr/bin/env bash
# PR 本文の「## 人間が確認」の節に、未チェックの項目 (`- [ ]` 等) が残っていないかを検査する。
# .github/workflows/human-verification-check.yml が、PR 本文を環境変数 PR_BODY に入れて実行する。
# 何も書き換えないため、同じ PR_BODY で何度実行しても結果は同じ (冪等)。
#
# 入力: 環境変数 PR_BODY (PR 本文)
# exit code: 0 = 節が無い、または未チェックの項目が無い / 1 = 未チェックの項目がある (該当の行と件数を出す)
set -u

# PR 本文の行末には CRLF が混入するため、先に CR を除去してから行単位で照合する。
# 節が無い PR (dependabot 等、テンプレートを通らない自動生成の PR) は対象外として成功させる
section=$(printf '%s\n' "${PR_BODY:-}" | tr -d '\r' | awk '/^## 人間が確認 *$/{flag=1; next} /^## /{flag=0} flag')
if [ -z "$section" ]; then
  echo "「## 人間が確認」セクションが無いためチェック対象外です"
  exit 0
fi
unchecked_pattern='^[[:space:]]*([-*+]|[0-9]+[.)])[[:space:]]+\[ \]'
unchecked=$(printf '%s\n' "$section" | grep -Ec "$unchecked_pattern" || true)
if [ "$unchecked" -gt 0 ]; then
  printf '%s\n' "$section" | grep -En "$unchecked_pattern"
  echo "::error::「## 人間が確認」に未チェック項目が ${unchecked} 件あります。人間が確認してチェックを入れてください"
  exit 1
fi
echo "「## 人間が確認」の項目はすべてチェック済みです"

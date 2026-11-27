#!/usr/bin/env bash
# list-missing-uid.sh が出す .uid のうち、作業ツリーにまだ無いものを作り、作ったパスを 1 行 1 パスで出す。
# Godot を起動しない手元で、足した .gd の .uid を同じ commit に入れるために使う (Makefile の uid が呼ぶ)。
# 作業ツリーに既にある .uid は書き換えない (Godot が付けた識別子を変えると、そのスクリプトへの参照が切れるため)。
# 既にある .uid を作り直さないため、2 回目の実行は何も作らない (冪等)。git add はしない。
#
# 中身は Godot と同じ形の `uid://<識別子>` と改行。Godot 4.7.2 の core/io/resource_uid.cpp
# (https://github.com/godotengine/godot/blob/4.7.2-stable/core/io/resource_uid.cpp) の create_id が
# 乱数の 64 bit の上位 1 bit を落とした値を作り、id_to_text がそれを 34 文字 (a〜y と 0〜8) の基数で上位の桁から
# 書くのと同じ手順で作る。リポジトリ内の既存の識別子 (uid://...) と重なったら作り直す。
# 作った .uid を Godot がそのまま使うことは、CI の check-and-export の step
# 「Check that Godot uses the .uid made by make uid」(make uidcheck) が確かめる。
#
# exit code: 0 = 作れた (作るものが無かった時を含む) / 0 以外 = git の失敗か、書き込みに失敗した
set -u -o pipefail

uid_characters=(a b c d e f g h i j k l m n o p q r s t u v w x y 0 1 2 3 4 5 6 7 8)

# 0 以上 2^63 未満の乱数を 10 進で出す (/dev/urandom の 8 byte のうち先頭の 1 byte の最上位の bit を落とす)
random_id() {
  local hex
  hex=$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')
  printf '%d\n' "$(( (16#${hex:0:2} & 0x7f) << 56 | 16#${hex:2} ))"
}

# 識別子 (10 進) を Godot の id_to_text と同じ `uid://...` の表記にする
id_to_text() {
  local id=$1 text=""
  while :; do
    text="${uid_characters[id % ${#uid_characters[@]}]}$text"
    id=$(( id / ${#uid_characters[@]} ))
    [ "$id" -eq 0 ] && break
  done
  printf 'uid://%s\n' "$text"
}

missing_uid_paths=$(bash "$(dirname "$0")/list-missing-uid.sh") || exit $?
[ -n "$missing_uid_paths" ] || exit 0

# 重なりを調べる既存の識別子。.uid のほか、.tscn・.tres・.import・project.godot に書かれた uid://... も含む
existing_uid_texts=$(git -c core.quotePath=false ls-files -z --cached --others --exclude-standard \
  | xargs -0 grep -hoE 'uid://[a-y0-8]+' 2> /dev/null | sort -u)

while IFS= read -r uid_path; do
  [ -e "$uid_path" ] && continue
  while :; do
    text=$(id_to_text "$(random_id)")
    # grep -q を使わない理由は list-missing-uid.sh の同じ形の行のコメント
    printf '%s\n' "$existing_uid_texts" | grep -xF -- "$text" > /dev/null || break
  done
  # 書き込みの途中で失敗した時に空や途中までの .uid を残さないよう、隣の一時ファイルに書いてから置き換える
  # (残った .uid は次の実行で「既にある」として飛ばされるため)
  printf '%s\n' "$text" > "$uid_path.tmp" && mv -- "$uid_path.tmp" "$uid_path" || { rm -f -- "$uid_path.tmp"; exit 1; }
  existing_uid_texts=$(printf '%s\n%s\n' "$existing_uid_texts" "$text")
  printf '%s\n' "$uid_path"
done <<< "$missing_uid_paths"

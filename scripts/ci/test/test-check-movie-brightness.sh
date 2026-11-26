#!/usr/bin/env bash
# scripts/ci/check-movie-brightness.sh のテスト。ffmpeg で単色の録画を作り、真っ黒・ほぼ黒は失敗し、暗い灰色・灰色は
# 通ることを確かめる。ffmpeg が必要。一時ディレクトリは終了時に消すため、何度実行しても結果は同じ (冪等)。
# 使い方: bash scripts/ci/test/test-check-movie-brightness.sh (リポジトリのどこからでも実行できる)
# exit code: 0 = 全件 PASS / 1 = FAIL あり
set -u
target="$(cd "$(dirname "$0")/.." && pwd)/check-movie-brightness.sh"
failed=0
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# 名前・期待する exit code・録画のパスを受け取り、検査の exit code が期待と違えば FAIL として記録する
expect() {
  bash "$target" "$3" > /dev/null 2>&1
  actual=$?
  if [ "$actual" -eq "$2" ]; then
    echo "PASS: $1"
  else
    echo "FAIL: $1 (期待 exit=$2 実際 exit=$actual)"
    failed=1
  fi
}

# 色 (ffmpeg の color の値) と出力先を受け取り、Makefile の movie target と同じ形式 (libx264・yuv420p・30 fps) で
# 2 秒の単色の録画を作る
make_movie() {
  ffmpeg -loglevel error -y -f lavfi -i "color=c=$1:s=320x180:d=2:r=30" -c:v libx264 -pix_fmt yuv420p "$2"
}

make_movie black "$work/black.mp4"
make_movie 0x0a0a0a "$work/near-black.mp4"
make_movie 0x303030 "$work/dark-gray.mp4"
make_movie gray "$work/gray.mp4"
printf 'not a movie\n' > "$work/text.mp4"

expect "真っ黒な録画は失敗する" 1 "$work/black.mp4"
expect "ほぼ黒 (#0a0a0a) の録画は失敗する" 1 "$work/near-black.mp4"
expect "暗い灰色 (#303030) の録画は通る" 0 "$work/dark-gray.mp4"
expect "灰色の録画は通る" 0 "$work/gray.mp4"
expect "動画でないファイルは失敗する" 1 "$work/text.mp4"
expect "無いファイルは失敗する" 1 "$work/missing.mp4"

exit "$failed"

#!/usr/bin/env bash
# 録画 (mp4) の終了 1 秒前のフレームが真っ黒でないかを検査する。Makefile の movie target が、起動の録画を
# 成功と誤認しないために実行する (描画に失敗した録画は真っ黒になる)。ffmpeg が必要。
# 何も書き換えないため、同じ録画で何度実行しても結果は同じ (冪等)。
#
# 使い方: check-movie-brightness.sh <mp4 のパス>
# exit code: 0 = 輝度の平均が基準以上 / 1 = 基準未満、または輝度を読めない (ファイルが無い・動画でない)
set -u

# 輝度の平均 (YAVG) の下限は 32。mp4 は limited range のため真っ黒が 16 で、その 2 倍を下限にした
# (bannzai/card-rationing の movie target から引き継いだ値)。暗い画面を足して録画が下限を割る時は、画面ではなく
# この値を見直す
ffmpeg -v error -sseof -1 -i "$1" -frames:v 1 -vf signalstats,metadata=print:key=lavfi.signalstats.YAVG:file=- -f null - \
  | awk -F= '/YAVG/ { found = 1; exit ($2 >= 32) ? 0 : 1 } END { if (!found) exit 1 }'

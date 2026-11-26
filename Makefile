# cat-hair の検証・ビルド入口。target 命名は ~/.claude/rules/makefile-target-naming.md に従う
# (`build-<対象>` = エクスポートだけ。`run` = エディタなしでの起動)。
# このマシンで実行してよい target は AGENTS.md「検証方法」を参照 (Godot を起動する target は CI で実行する)。
#
# GODOT は Godot 4.7 の実行ファイル。macOS ローカルの既定値は /Applications/Godot.app。CI では
# make の引数 (`make check GODOT=<Linux バイナリのパス>`) で Linux バイナリを渡す。
GODOT ?= /Applications/Godot.app/Contents/MacOS/Godot
LOG_DIR := tmp
# Godot 自身のログの出力先。指定しないと user:// に書こうとし、書き込みを拒否するサンドボックスでは
# 起動に失敗するため、すべての Godot 起動に付ける ($@ は実行中の target 名)
ENGINE_LOG = --log-file "$(CURDIR)/$(LOG_DIR)/$@.godot.log"

# --script で動かす検証 (selfcheck / integration / screenshot) の上限 (フレーム数)。検証スクリプトが実行時
# エラーで quit() に届かないと Godot が終わらず、CI の job が timeout-minutes まで待つため、
# `--quit-after` でこのフレーム数に達したら Godot を終わらせる (CI の Linux とローカルの macOS の両方で動く。
# macOS には timeout コマンドが無い)。上限で終わると exit code は 0 だが、各 target は完了の行 (`selfcheck OK` /
# `integration OK` / `screenshot OK`) も検査するので失敗になる。
# 12000 の根拠 (bannzai/card-rationing の Makefile から引き継いだ値): headless は 1 フレームが数 ms で、正常な検証は
# 数百フレームで終わる。描画付きの screenshot は llvmpipe の fps が読めず (数十〜数千 fps)、最初の撮影の前だけ
# 0.3 秒を時間で待ち、以後の撮影はフレームの数 (撮影ごとに 4 フレーム) で待つため、数千 fps の環境でも収まる値にした
# (時間で待つ撮影を足して待ちの合計が 2 秒を超えるなら上限も見直す)。
# GDScript の無限ループはフレームが進まず止められないため、そちらは CI の timeout-minutes が最後の砦
SCRIPT_FRAME_LIMIT ?= 12000
SCRIPT_FLAGS = --quit-after $(SCRIPT_FRAME_LIMIT)

# Godot がログに出すエラー・警告の行頭 (core/io/logger.h の error_type_string: ERROR / WARNING / SCRIPT ERROR /
# SHADER ERROR。push_error は ERROR、GDScript の実行時エラーは SCRIPT ERROR)。stdout が端末でない時は色コードが
# 付かない (drivers/unix/os_unix.cpp の UnixTerminalLogger)。行頭で絞るため、print の文に error /
# warning の語があっても落ちない。続く「   at: ...」の行は対象外 (本体の行で検出できる)
LOG_ERROR_PATTERN := ^(SCRIPT |SHADER )?(ERROR|WARNING):

# 描画付きで起動する target (screenshot / movie / hairbench) の共通オプション。headless では描画されないため付けない。
# レンダラは Forward+ (ADR 0002)。CI の Linux では Xvfb + Mesa lavapipe (Vulkan) 上で実行する
RENDERING_DRIVER ?= vulkan
RENDERING_METHOD ?= forward_plus
WINDOWED_FLAGS := --audio-driver Dummy --rendering-driver $(RENDERING_DRIVER) --rendering-method $(RENDERING_METHOD) --resolution 1280x720 --windowed --position 0,0
# 描画付き起動でだけ出る、描画に影響しない OS / ドライバ由来の行。ログの WARNING / ERROR 検査から除外する
# (llvmpipe は V-Sync を設定できない WARNING を毎回 1 件出す。macOS は入力メソッドの mach port のエラーを稀に出す)
WINDOWED_LOG_NOISE := -e 'Could not set V-Sync mode' -e 'IMKCFRunLoopWakeUpReliable'
# movie target が録画する固定 FPS とフレーム数 (30 fps × 5 秒 = 150。movie.gd へ渡す単一の正)。
# 操作なしの起動〜メインシーン表示の確認には数秒あれば足り、CI の録画時間と artifact のサイズを抑えるため
MOVIE_FPS ?= 30
MOVIE_FRAMES ?= 150
# hairbench target の計測本数の上書き (カンマ区切り。未指定時は scripts/dev/hairbench.gd の DEFAULT_COUNTS が SSOT)
HAIRBENCH_COUNTS ?=

.PHONY: import check selfcheck integration failure-path lint test verify screenshot movie hairbench run build-macos build-windows build-linux build-web build-all clean

# ログ・撮影の出力先。.gdignore を置き、撮影した PNG を Godot に import させない
$(LOG_DIR)/.gdignore:
	@mkdir -p $(LOG_DIR)
	@touch $@

# エクスポートの出力先。.gdignore を置き、成果物を Godot に読ませない
build/.gdignore:
	@mkdir -p build
	@touch $@

# アセットのインポート (初回・素材追加後)。.godot/ を生成する
import: $(LOG_DIR)/.gdignore
	"$(GODOT)" --headless $(ENGINE_LOG) --path . --import > $(LOG_DIR)/import.log 2>&1; \
	echo "exit=$$?" >> $(LOG_DIR)/import.log; \
	tail -n 1 $(LOG_DIR)/import.log | grep -q '^exit=0$$'
	! grep -E '$(LOG_ERROR_PATTERN)' $(LOG_DIR)/import.log

# 起動検証。メインシーンとスクリプトがロードでき、_ready が走ることを boot 出力で確認する
check: import
	"$(GODOT)" --headless $(ENGINE_LOG) --path . --quit > $(LOG_DIR)/check.log 2>&1; \
	echo "exit=$$?" >> $(LOG_DIR)/check.log; \
	grep -q '^cat-hair boot$$' $(LOG_DIR)/check.log
	tail -n 1 $(LOG_DIR)/check.log | grep -q '^exit=0$$'
	! grep -E '$(LOG_ERROR_PATTERN)' $(LOG_DIR)/check.log

# 純粋なロジックとプロジェクト設定の検証 (headless。検証の一覧は scripts/dev/selfcheck.gd)
selfcheck: import
	"$(GODOT)" --headless $(ENGINE_LOG) --path . $(SCRIPT_FLAGS) --script res://scripts/dev/selfcheck.gd > $(LOG_DIR)/selfcheck.log 2>&1; \
	echo "exit=$$?" >> $(LOG_DIR)/selfcheck.log; \
	grep -q '^selfcheck OK$$' $(LOG_DIR)/selfcheck.log
	tail -n 1 $(LOG_DIR)/selfcheck.log | grep -q '^exit=0$$'
	! grep -E '$(LOG_ERROR_PATTERN)' $(LOG_DIR)/selfcheck.log

# メインシーンを tree に置いて動かす入力統合テスト (headless。検証の一覧は scripts/dev/integration.gd)。
# 後半では実プロセスの OS コマンドライン引数 (-- --verify-cmdline ...) による調整値上書き起動も検証する
integration: import
	"$(GODOT)" --headless $(ENGINE_LOG) --path . $(SCRIPT_FLAGS) --script res://scripts/dev/integration.gd > $(LOG_DIR)/integration.log 2>&1; \
	echo "exit=$$?" >> $(LOG_DIR)/integration.log; \
	grep -q '^integration OK$$' $(LOG_DIR)/integration.log
	tail -n 1 $(LOG_DIR)/integration.log | grep -q '^exit=0$$'
	! grep -E '$(LOG_ERROR_PATTERN)' $(LOG_DIR)/integration.log
	"$(GODOT)" --headless --log-file "$(CURDIR)/$(LOG_DIR)/integration-cmdline.godot.log" --path . $(SCRIPT_FLAGS) --script res://scripts/dev/integration.gd -- --verify-cmdline --room-count=2 --hair-count=321 --object-count=4 --found-item-count=1 --room-size=5.0 > $(LOG_DIR)/integration-cmdline.log 2>&1; \
	echo "exit=$$?" >> $(LOG_DIR)/integration-cmdline.log; \
	grep -q '^integration OK$$' $(LOG_DIR)/integration-cmdline.log
	tail -n 1 $(LOG_DIR)/integration-cmdline.log | grep -q '^exit=0$$'
	! grep -E '$(LOG_ERROR_PATTERN)' $(LOG_DIR)/integration-cmdline.log

# 検証の土台 (scripts/dev/headless_check.gd) と hairbench.gd の失敗の経路の検証。わざと失敗する条件で動かし、
# exit code 1 で終わり、完了の行が出ないことを確かめる (失敗を握り潰して常に OK を返す退行を検出する)
failure-path: import
	"$(GODOT)" --headless $(ENGINE_LOG) --path . $(SCRIPT_FLAGS) --script res://scripts/dev/failure_path_check.gd > $(LOG_DIR)/failure-path.log 2>&1; \
	echo "exit=$$?" >> $(LOG_DIR)/failure-path.log; \
	tail -n 1 $(LOG_DIR)/failure-path.log | grep -q '^exit=1$$'
	grep -q 'failure_path_check FAIL' $(LOG_DIR)/failure-path.log
	! grep -q '^failure_path_check OK$$' $(LOG_DIR)/failure-path.log
	HAIRBENCH_COUNTS="10" HAIRBENCH_JSON="$(LOG_DIR)/hairbench-fail.json" HAIRBENCH_PNG_PREFIX="hairbench-fail" "$(GODOT)" --headless $(ENGINE_LOG) --path . $(SCRIPT_FLAGS) --script res://scripts/dev/hairbench.gd > $(LOG_DIR)/hairbench-failure-path.log 2>&1; \
	echo "exit=$$?" >> $(LOG_DIR)/hairbench-failure-path.log; \
	rm -f $(LOG_DIR)/hairbench-fail.json $(LOG_DIR)/hairbench-fail-*.png; \
	tail -n 1 $(LOG_DIR)/hairbench-failure-path.log | grep -q '^exit=1$$'
	grep -q '^hairbench count=10 rendered=false' $(LOG_DIR)/hairbench-failure-path.log
	! grep -q '^hairbench OK$$' $(LOG_DIR)/hairbench-failure-path.log
	HAIRBENCH_COUNTS="10" HAIRBENCH_JSON="$(LOG_DIR)/nonexistent-hairbench-dir/out.json" HAIRBENCH_PNG_PREFIX="hairbench-fail" "$(GODOT)" --headless $(ENGINE_LOG) --path . $(SCRIPT_FLAGS) --script res://scripts/dev/hairbench.gd > $(LOG_DIR)/hairbench-json-failure-path.log 2>&1; \
	echo "exit=$$?" >> $(LOG_DIR)/hairbench-json-failure-path.log; \
	rm -f $(LOG_DIR)/hairbench-fail-*.png; \
	tail -n 1 $(LOG_DIR)/hairbench-json-failure-path.log | grep -q '^exit=1$$'
	grep -q 'hairbench JSON 書き込み失敗' $(LOG_DIR)/hairbench-json-failure-path.log
	! grep -q '^hairbench count=' $(LOG_DIR)/hairbench-json-failure-path.log
	! grep -q '^hairbench OK$$' $(LOG_DIR)/hairbench-json-failure-path.log

# GDScript の lint (gdtoolkit の gdlint。設定は ./gdlintrc)
lint:
	gdlint scripts/

# headless 検証の一括実行 (CI の lint job と、check-and-export job のうちエクスポートを除いた部分。描画付きの
# screenshot / movie は含まない)
test: lint check selfcheck integration failure-path

# 人の操作なしで終わる検査・テスト・ビルドの一括実行
verify: test build-all

# 実際の描画で代表画面を撮影する (headless の検証では見た目の崩れを検出できない)。撮影した PNG は目視してから
# 完了報告する。全部の撮影を終えた印の `screenshot OK` の行も検査する (上限で止まった時に、1 枚目の PNG だけで
# pass しないため)
screenshot: import
	rm -f $(LOG_DIR)/screenshot-*.png
	"$(GODOT)" $(ENGINE_LOG) --path . $(WINDOWED_FLAGS) $(SCRIPT_FLAGS) --script res://scripts/dev/screenshot.gd > $(LOG_DIR)/screenshot.log 2>&1; \
	echo "exit=$$?" >> $(LOG_DIR)/screenshot.log; \
	grep -q '^screenshot OK$$' $(LOG_DIR)/screenshot.log
	tail -n 1 $(LOG_DIR)/screenshot.log | grep -q '^exit=0$$'
	! grep -E '$(LOG_ERROR_PATTERN)' $(LOG_DIR)/screenshot.log | grep -v $(WINDOWED_LOG_NOISE) | grep -q .
	ls $(LOG_DIR)/screenshot-*.png

# 操作を伴わない起動〜メインシーン表示を Movie Maker モードで録画して mp4 にする (起動直後の描画崩れ・真っ黒を
# 検出する。headless は dummy レンダラで落ちるため描画付きで起動する)。真っ黒な動画を成功と誤認しないよう、
# 終了 1 秒前のフレームの輝度の平均が下限以上であることも検査する (下限と判定は scripts/ci/check-movie-brightness.sh)
movie: import
	rm -f $(LOG_DIR)/movie.avi $(LOG_DIR)/movie.mp4
	"$(GODOT)" $(ENGINE_LOG) --path . $(WINDOWED_FLAGS) --write-movie $(LOG_DIR)/movie.avi --fixed-fps $(MOVIE_FPS) --quit-after $(MOVIE_FRAMES) --script res://scripts/dev/movie.gd -- --frames=$(MOVIE_FRAMES) --fps=$(MOVIE_FPS) > $(LOG_DIR)/movie.log 2>&1; \
	echo "exit=$$?" >> $(LOG_DIR)/movie.log; \
	grep -q '^movie OK$$' $(LOG_DIR)/movie.log
	tail -n 1 $(LOG_DIR)/movie.log | grep -q '^exit=0$$'
	! grep -E '$(LOG_ERROR_PATTERN)' $(LOG_DIR)/movie.log | grep -v $(WINDOWED_LOG_NOISE) | grep -q .
	ffmpeg -loglevel error -y -i $(LOG_DIR)/movie.avi -c:v libx264 -pix_fmt yuv420p $(LOG_DIR)/movie.mp4
	rm -f $(LOG_DIR)/movie.avi
	bash scripts/ci/check-movie-brightness.sh $(LOG_DIR)/movie.mp4

# 毛の描画の試作ベンチマーク。1,000 / 10,000 / 100,000 / 1,000,000 本の描画可否と 1 フレームの描画時間を
# tmp/hairbench.json に出力し、本数ごとの画面を tmp/hairbench-<本数>.png に撮る
hairbench: import
	rm -f $(LOG_DIR)/hairbench-*.png $(LOG_DIR)/hairbench.json
	HAIRBENCH_COUNTS="$(HAIRBENCH_COUNTS)" "$(GODOT)" $(ENGINE_LOG) --path . $(WINDOWED_FLAGS) $(SCRIPT_FLAGS) --script res://scripts/dev/hairbench.gd > $(LOG_DIR)/hairbench.log 2>&1; \
	echo "exit=$$?" >> $(LOG_DIR)/hairbench.log; \
	grep -q '^hairbench OK$$' $(LOG_DIR)/hairbench.log
	tail -n 1 $(LOG_DIR)/hairbench.log | grep -q '^exit=0$$'
	! grep -E '$(LOG_ERROR_PATTERN)' $(LOG_DIR)/hairbench.log | grep -v $(WINDOWED_LOG_NOISE) | grep -q .
	test -f $(LOG_DIR)/hairbench.json
	ls $(LOG_DIR)/hairbench-*.png

# エディタなしでゲームを起動する (人が遊んで確かめる)。先にアセットをインポートする (.godot/ が無い初回や素材の
# 追加後に、エディタを開かずに起動すると素材が読み込めず起動に失敗するため)
run: import
	"$(GODOT)" $(ENGINE_LOG) --path .

# デスクトップ向けエクスポート。プリセット名は export_presets.cfg と一致させる。
# 実行には Godot 4.7 の export templates が必要 (AGENTS.md「検証方法」参照)。
# エクスポートは WARNING / ERROR を出しても exit 0 で終わることがあるため、エンジンのログ (ENGINE_LOG) も検査する
build-macos: import build/.gdignore
	@mkdir -p build/macos
	"$(GODOT)" --headless $(ENGINE_LOG) --path . --export-release "macOS" build/macos/cat-hair.zip
	! grep -E '$(LOG_ERROR_PATTERN)' $(LOG_DIR)/$@.godot.log
	test -f build/macos/cat-hair.zip

build-windows: import build/.gdignore
	@mkdir -p build/windows
	"$(GODOT)" --headless $(ENGINE_LOG) --path . --export-release "Windows Desktop" build/windows/cat-hair.exe
	! grep -E '$(LOG_ERROR_PATTERN)' $(LOG_DIR)/$@.godot.log
	test -f build/windows/cat-hair.exe
	test -f build/windows/cat-hair.pck

build-linux: import build/.gdignore
	@mkdir -p build/linux
	"$(GODOT)" --headless $(ENGINE_LOG) --path . --export-release "Linux" build/linux/cat-hair.x86_64
	! grep -E '$(LOG_ERROR_PATTERN)' $(LOG_DIR)/$@.godot.log
	test -f build/linux/cat-hair.x86_64
	test -f build/linux/cat-hair.pck

# Web 版は配布しない。入力で変わる振る舞いをランナー上のブラウザで触って確かめる時 (.github/workflows/browser-session.yml)
# だけ書き出すため、build-all には含めない
build-web: import build/.gdignore
	@mkdir -p build/web
	"$(GODOT)" --headless $(ENGINE_LOG) --path . --export-release "Web" build/web/index.html
	! grep -E '$(LOG_ERROR_PATTERN)' $(LOG_DIR)/$@.godot.log
	test -f build/web/index.html
	test -f build/web/index.wasm
	test -f build/web/index.pck

build-all: build-macos build-windows build-linux

# ビルド成果物と、この Makefile が tmp/ に書いたログ・撮影・録画だけを消す (tmp/ は agent の作業ファイルも置くため
# ディレクトリごとや *.log をまとめては消さない)。ログは target ごとの <target>.log と、ENGINE_LOG の <target>.godot.log
clean:
	rm -rf build
	rm -f $(foreach target,import check selfcheck integration integration-cmdline failure-path hairbench-failure-path hairbench-json-failure-path screenshot movie hairbench run build-macos build-windows build-linux build-web,$(LOG_DIR)/$(target).log $(LOG_DIR)/$(target).godot.log)
	rm -f $(LOG_DIR)/screenshot-*.png $(LOG_DIR)/hairbench-*.png $(LOG_DIR)/hairbench.json $(LOG_DIR)/movie.avi $(LOG_DIR)/movie.mp4

# 引数なしの make で run を実行する (人が手で動作確認するための入口。検査・テストは CI が行う)
.DEFAULT_GOAL := run

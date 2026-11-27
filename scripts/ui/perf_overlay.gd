class_name PerfOverlay
extends Label
## 遊んでいる間に fps と 1 フレームにかかる時間を画面の上の中央に出す、切り替えできる小さな表示。
## owner が実機で数字を読んで伝えるためのもの。出している間だけ、描画の CPU / GPU の時間の計測を有効にする。

## 表示を描き直す間隔 (秒)。毎フレーム描き直すと数字が読めないほど変わるため、目で追える 4 回 / 秒にした
const REFRESH_INTERVAL_SECONDS: float = 0.25
## 画面の上端からの距離 (px)。左上の住人の表示と右上の残り毛本数の表示の間 (上の中央) に置き、
## どちらの枠にも重ならない高さにした
const TOP_MARGIN: float = 8.0
## 文字の大きさ (px)。HUD のほかの数字より小さく、1,280 × 720 で 1 行に収まる大きさ
const FONT_SIZE: int = 16
## 文字の縁取りの色。背景の枠を置かずに、明るい天井・壁の上でも白い文字を読めるようにほぼ不透明の黒にした
const OUTLINE_COLOR: Color = Color(0.0, 0.0, 0.0, 0.9)
## 文字の縁取りの太さ (px)。16 px の文字で、縁取りが字の中を潰さずに読める太さ (CI の撮影で確かめた)
const OUTLINE_SIZE: int = 4

## 次に描き直すまでの残り秒数
var _refresh_remaining: float = 0.0


## 計測値から表示する 1 行の文言を作る (検証用に static にする)
static func format_metrics(
	fps: float, frame_ms: float, process_ms: float, render_cpu_ms: float, render_gpu_ms: float
) -> String:
	return "%d fps   1 フレーム %.1f ms   処理 %.1f ms   描画 CPU %.1f ms / GPU %.1f ms" % [
		roundi(fps), frame_ms, process_ms, render_cpu_ms, render_gpu_ms
	]


## fps (直近 1 秒の平均) から 1 フレームの時間 (ms) を返す。fps がまだ出ていない (0 以下) 時は 0 を返す
static func frame_ms_from_fps(fps: float) -> float:
	return 1000.0 / fps if fps > 0.0 else 0.0


## 位置と文字の見た目を決め、隠した状態で始める
func _ready() -> void:
	name = "PerfOverlay"
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	offset_top = TOP_MARGIN
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_font_size_override("font_size", FONT_SIZE)
	add_theme_color_override("font_outline_color", OUTLINE_COLOR)
	add_theme_constant_override("outline_size", OUTLINE_SIZE)
	set_overlay_visible(false)


## 表示の出し入れを切り替える
func toggle() -> void:
	set_overlay_visible(not visible)


## 表示を出す・隠す。出す時はすぐに描き直す
func set_overlay_visible(shown: bool) -> void:
	visible = shown
	set_process(shown)
	if is_inside_tree():
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), shown)
	if shown:
		_refresh_remaining = 0.0
		_refresh_text()


## REFRESH_INTERVAL_SECONDS ごとに文言を描き直す
func _process(delta: float) -> void:
	_refresh_remaining -= delta
	if _refresh_remaining > 0.0:
		return
	_refresh_remaining = REFRESH_INTERVAL_SECONDS
	_refresh_text()


## 今の計測値で文言を描き直す
func _refresh_text() -> void:
	var fps: float = Performance.get_monitor(Performance.TIME_FPS)
	var viewport_rid: RID = get_viewport().get_viewport_rid()
	text = format_metrics(
		fps,
		frame_ms_from_fps(fps),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid),
		RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid),
	)

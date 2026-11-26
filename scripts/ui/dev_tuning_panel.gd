class_name DevTuningPanel
extends PanelContainer
## 開発者向けの調整値編集パネル。
## 5 つの調整値を変更して屋敷を作り直す操作を提供する。

## 「屋敷を作り直す」押下時に現在の入力値から組み立てた調整値を通知する
signal apply_requested(tuning: MansionTuning)
## 「閉じる」押下時にパネル終了要求を通知する
signal close_requested

## 開発者向け調整値データ型スクリプト
const MansionTuningScript := preload("res://scripts/data/mansion_tuning.gd")

## 毛の本数 SpinBox の矢印ボタン増減幅 (千〜万単位を調整しやすい 100 本刻み。step は 1 で任意整数を保持)
const HAIR_COUNT_ARROW_STEP: float = 100.0
## 部屋幅 (m) SpinBox の矢印ボタン増減幅 (0.5m 刻み。step は 0.01 で任意の小数値を丸めず保持)
const ROOM_SIZE_ARROW_STEP: float = 0.5
## 部屋幅 (m) SpinBox の内部刻み (小数第 2 位までのコマンドライン引数値等を丸めず保持するため)
const ROOM_SIZE_VALUE_STEP: float = 0.01

## 毛の本数の入力欄
var hair_count_spin: SpinBox = null
## 埋める探し物の数の入力欄
var found_item_count_spin: SpinBox = null
## 屋敷の広さ (1 部屋の幅 m) の入力欄
var room_size_spin: SpinBox = null
## 物の数の入力欄
var object_count_spin: SpinBox = null
## 部屋の数の入力欄
var room_count_spin: SpinBox = null
## 調整値を適用して屋敷を作り直すボタン
var apply_button: Button = null
## パネルを閉じるボタン
var close_button: Button = null

## UI 構築済みフラグ (遅延構築の重複実行を防ぐ)
var _built: bool = false


## シーンツリー参加時にパネル内のフォーム UI を構築する
func _ready() -> void:
	_ensure_ui()


## 指定された調整値を各入力欄に反映する
func load_from_tuning(tuning: MansionTuning) -> void:
	_ensure_ui()
	var safe_tuning: MansionTuning = (
		tuning.clamped() if tuning != null else MansionTuningScript.new()
	)
	hair_count_spin.value = float(safe_tuning.hair_count)
	found_item_count_spin.value = float(safe_tuning.found_item_count)
	room_size_spin.value = safe_tuning.room_size_m
	object_count_spin.value = float(safe_tuning.object_count)
	room_count_spin.value = float(safe_tuning.room_count)


## 現在の入力欄の値から MansionTuning を組み立てて返す
func build_tuning_from_inputs() -> MansionTuning:
	_ensure_ui()
	var tuning: MansionTuning = MansionTuningScript.new()
	tuning.hair_count = int(round(hair_count_spin.value))
	tuning.found_item_count = int(round(found_item_count_spin.value))
	tuning.room_size_m = float(room_size_spin.value)
	tuning.object_count = int(round(object_count_spin.value))
	tuning.room_count = int(round(room_count_spin.value))
	return tuning.clamped()


## パネルの背景・見出し・5 項目の入力欄・操作ボタンを 1 度だけ生成する
func _ensure_ui() -> void:
	if _built:
		return
	_built = true

	var panel_style: StyleBoxFlat = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.11, 0.11, 0.14, 0.94)
	panel_style.border_color = Color(0.55, 0.52, 0.46, 1.0)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(8)
	panel_style.set_content_margin_all(20)
	add_theme_stylebox_override("panel", panel_style)

	var content_box: VBoxContainer = VBoxContainer.new()
	content_box.name = "Content"
	content_box.add_theme_constant_override("separation", 12)
	add_child(content_box)

	var title_label: Label = Label.new()
	title_label.name = "PanelTitle"
	title_label.text = "開発者向け 調整値"
	title_label.add_theme_font_size_override("font_size", 24)
	content_box.add_child(title_label)

	var fields_grid: GridContainer = GridContainer.new()
	fields_grid.name = "Fields"
	fields_grid.columns = 2
	fields_grid.add_theme_constant_override("h_separation", 18)
	fields_grid.add_theme_constant_override("v_separation", 10)
	content_box.add_child(fields_grid)

	hair_count_spin = _add_spin_row(
		fields_grid,
		"HairCountSpin",
		"毛の本数",
		float(MansionTuningScript.MIN_HAIR_COUNT),
		float(MansionTuningScript.MAX_HAIR_COUNT),
		1.0,
		HAIR_COUNT_ARROW_STEP,
		float(MansionTuningScript.DEFAULT_HAIR_COUNT),
	)
	found_item_count_spin = _add_spin_row(
		fields_grid,
		"FoundItemCountSpin",
		"埋める探し物の数",
		float(MansionTuningScript.MIN_FOUND_ITEM_COUNT),
		float(MansionTuningScript.MAX_FOUND_ITEM_COUNT),
		1.0,
		1.0,
		float(MansionTuningScript.DEFAULT_FOUND_ITEM_COUNT),
	)
	room_size_spin = _add_spin_row(
		fields_grid,
		"RoomSizeSpin",
		"屋敷の広さ (1部屋の幅 m)",
		MansionTuningScript.MIN_ROOM_SIZE_M,
		MansionTuningScript.MAX_ROOM_SIZE_M,
		ROOM_SIZE_VALUE_STEP,
		ROOM_SIZE_ARROW_STEP,
		MansionTuningScript.DEFAULT_ROOM_SIZE_M,
	)
	object_count_spin = _add_spin_row(
		fields_grid,
		"ObjectCountSpin",
		"物の数",
		float(MansionTuningScript.MIN_OBJECT_COUNT),
		float(MansionTuningScript.MAX_OBJECT_COUNT),
		1.0,
		1.0,
		float(MansionTuningScript.DEFAULT_OBJECT_COUNT),
	)
	room_count_spin = _add_spin_row(
		fields_grid,
		"RoomCountSpin",
		"部屋の数",
		float(MansionTuningScript.MIN_ROOM_COUNT),
		float(MansionTuningScript.MAX_ROOM_COUNT),
		1.0,
		1.0,
		float(MansionTuningScript.DEFAULT_ROOM_COUNT),
	)

	var button_row: HBoxContainer = HBoxContainer.new()
	button_row.name = "Buttons"
	button_row.add_theme_constant_override("separation", 12)
	button_row.alignment = BoxContainer.ALIGNMENT_END
	content_box.add_child(button_row)

	close_button = Button.new()
	close_button.name = "CloseButton"
	close_button.text = "閉じる"
	close_button.pressed.connect(_on_close_pressed)
	button_row.add_child(close_button)

	apply_button = Button.new()
	apply_button.name = "ApplyButton"
	apply_button.text = "屋敷を作り直す"
	apply_button.pressed.connect(_on_apply_pressed)
	button_row.add_child(apply_button)


## ラベルと SpinBox の 1 行を grid に追加して SpinBox を返す
func _add_spin_row(
	fields_grid: GridContainer,
	spin_name: String,
	label_text: String,
	min_value: float,
	max_value: float,
	step_value: float,
	arrow_step_value: float,
	default_value: float,
) -> SpinBox:
	var row_label: Label = Label.new()
	row_label.text = label_text
	row_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fields_grid.add_child(row_label)

	var spin_box: SpinBox = SpinBox.new()
	spin_box.name = spin_name
	spin_box.min_value = min_value
	spin_box.max_value = max_value
	spin_box.step = step_value
	spin_box.custom_arrow_step = arrow_step_value
	spin_box.value = default_value
	spin_box.custom_minimum_size = Vector2(160.0, 0.0)
	fields_grid.add_child(spin_box)
	return spin_box


## 「屋敷を作り直す」ボタン押下ハンドラ
func _on_apply_pressed() -> void:
	apply_requested.emit(build_tuning_from_inputs())


## 「閉じる」ボタン押下ハンドラ
func _on_close_pressed() -> void:
	close_requested.emit()

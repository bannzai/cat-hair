class_name DevTuningPanel
extends PanelContainer
## 開発者向けの調整値編集パネル。
## 5 つの調整値を変更して屋敷を作り直す操作を提供する。

signal apply_requested(tuning: MansionTuning)
signal close_requested

const MansionTuningScript := preload("res://scripts/data/mansion_tuning.gd")

var hair_count_spin: SpinBox = null
var found_item_count_spin: SpinBox = null
var room_size_spin: SpinBox = null
var object_count_spin: SpinBox = null
var room_count_spin: SpinBox = null
var apply_button: Button = null
var close_button: Button = null

var _built: bool = false


func _ready() -> void:
	_ensure_ui()


## 指定された調整値を各入力欄に反映する
func load_from_tuning(tuning: MansionTuning) -> void:
	_ensure_ui()
	var safe: MansionTuning = tuning.clamped() if tuning != null else MansionTuningScript.new()
	hair_count_spin.value = float(safe.hair_count)
	found_item_count_spin.value = float(safe.found_item_count)
	room_size_spin.value = safe.room_size_m
	object_count_spin.value = float(safe.object_count)
	room_count_spin.value = float(safe.room_count)


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


func _ensure_ui() -> void:
	if _built:
		return
	_built = true

	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.11, 0.11, 0.14, 0.94)
	style.border_color = Color(0.55, 0.52, 0.46, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(20)
	add_theme_stylebox_override("panel", style)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.name = "Content"
	vbox.add_theme_constant_override("separation", 12)
	add_child(vbox)

	var title: Label = Label.new()
	title.name = "PanelTitle"
	title.text = "開発者向け 調整値"
	title.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title)

	var grid: GridContainer = GridContainer.new()
	grid.name = "Fields"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 10)
	vbox.add_child(grid)

	hair_count_spin = _add_spin_row(
		grid,
		"HairCountSpin",
		"毛の本数",
		float(MansionTuningScript.MIN_HAIR_COUNT),
		float(MansionTuningScript.MAX_HAIR_COUNT),
		100.0,
		float(MansionTuningScript.DEFAULT_HAIR_COUNT),
	)
	found_item_count_spin = _add_spin_row(
		grid,
		"FoundItemCountSpin",
		"埋める探し物の数",
		float(MansionTuningScript.MIN_FOUND_ITEM_COUNT),
		float(MansionTuningScript.MAX_FOUND_ITEM_COUNT),
		1.0,
		float(MansionTuningScript.DEFAULT_FOUND_ITEM_COUNT),
	)
	room_size_spin = _add_spin_row(
		grid,
		"RoomSizeSpin",
		"屋敷の広さ (1部屋の幅 m)",
		MansionTuningScript.MIN_ROOM_SIZE_M,
		MansionTuningScript.MAX_ROOM_SIZE_M,
		0.5,
		MansionTuningScript.DEFAULT_ROOM_SIZE_M,
	)
	object_count_spin = _add_spin_row(
		grid,
		"ObjectCountSpin",
		"物の数",
		float(MansionTuningScript.MIN_OBJECT_COUNT),
		float(MansionTuningScript.MAX_OBJECT_COUNT),
		1.0,
		float(MansionTuningScript.DEFAULT_OBJECT_COUNT),
	)
	room_count_spin = _add_spin_row(
		grid,
		"RoomCountSpin",
		"部屋の数",
		float(MansionTuningScript.MIN_ROOM_COUNT),
		float(MansionTuningScript.MAX_ROOM_COUNT),
		1.0,
		float(MansionTuningScript.DEFAULT_ROOM_COUNT),
	)

	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.name = "Buttons"
	buttons.add_theme_constant_override("separation", 12)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_child(buttons)

	close_button = Button.new()
	close_button.name = "CloseButton"
	close_button.text = "閉じる"
	close_button.pressed.connect(_on_close_pressed)
	buttons.add_child(close_button)

	apply_button = Button.new()
	apply_button.name = "ApplyButton"
	apply_button.text = "屋敷を作り直す"
	apply_button.pressed.connect(_on_apply_pressed)
	buttons.add_child(apply_button)


func _add_spin_row(
	grid: GridContainer,
	spin_name: String,
	label_text: String,
	min_val: float,
	max_val: float,
	step_val: float,
	default_val: float,
) -> SpinBox:
	var label: Label = Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(label)

	var spin: SpinBox = SpinBox.new()
	spin.name = spin_name
	spin.min_value = min_val
	spin.max_value = max_val
	spin.step = step_val
	spin.value = default_val
	spin.custom_minimum_size = Vector2(160.0, 0.0)
	grid.add_child(spin)
	return spin


func _on_apply_pressed() -> void:
	apply_requested.emit(build_tuning_from_inputs())


func _on_close_pressed() -> void:
	close_requested.emit()

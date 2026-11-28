extends RefCounted
## 大型の道具 (業務用の吸引車・建物を覆う粘着シート・アンドロイド・毛の加工機・毛を運ぶダンプカー) と加工の検証スイート
## (scripts/dev/selfcheck.gd から呼ぶ)。加工の段階ごとの売値・色を分けるか混ぜるかの差・シートの消費・吸引車が部屋から取る本数・
## アンドロイドが探し物を傷めないこと・ダンプカーが運ぶ量を確かめる。

## 道具・お金の検証スイート (表面の種類の一覧と在庫の作り方を共有する)
const SelfcheckToolsScript := preload("res://scripts/dev/selfcheck_tools.gd")
## 道具の定義
const ToolCatalogScript := preload("res://scripts/tools/tool_catalog.gd")
## 道具のルールの計算
const ToolRulesScript := preload("res://scripts/tools/tool_rules.gd")
## 毛の加工機とダンプカーの計算
const ProcessingRulesScript := preload("res://scripts/economy/processing_rules.gd")
## 毛を売る値段の計算
const EconomyRulesScript := preload("res://scripts/economy/economy_rules.gd")
## 手で毛を取る時のルールの計算 (珍しい毛の id)
const HandRulesScript := preload("res://scripts/hand/hand_rules.gd")
## 屋敷レイアウト型スクリプト
const MansionLayoutScript := preload("res://scripts/mansion/mansion_layout.gd")
## 屋敷の 3D 表現 (毛を HairField で持つ)
const MansionWorldScript := preload("res://scripts/mansion/mansion_world.gd")
## 面ごとの毛データ型スクリプト
const SurfaceHairScript := preload("res://scripts/data/surface_hair.gd")
## 毛・加工品在庫データ型スクリプト
const HairStockScript := preload("res://scripts/data/hair_stock.gd")
## JSON 保存ストレージスクリプト (一時セーブファイルの後片付けに使う)
const SaveStorageScript := preload("res://scripts/state/save_storage.gd")
## 状態管理 autoload スクリプト
const GameStateScript := preload("res://scripts/state/game_state.gd")
## 道具を買う画面のスクリプト
const ToolShopPanelScript := preload("res://scripts/ui/tool_shop_panel.gd")
## selfcheck が使う一時セーブファイルパス (GameState の初期化だけに使い、保存はしない)
const TEST_SAVE_PATH: String = "user://selfcheck_big_tools_save_data.json"
## 部屋ごとにかける毛を取る大型の道具
const ROOM_TOOLS: Array[StringName] = [
	ToolCatalogScript.TOOL_SUCTION_TRUCK,
	ToolCatalogScript.TOOL_ADHESIVE_SHEET,
	ToolCatalogScript.TOOL_ANDROID,
]

## 検証結果を記録する selfcheck の SceneTree 参照
var _checker: SceneTree = null


## 大型の道具と加工の検証をすべて実行する
static func run_all(checker: SceneTree) -> void:
	var suite: RefCounted = load("res://scripts/dev/selfcheck_big_tools.gd").new()
	suite._checker = checker
	suite._check_catalog()
	suite._check_room_tool_miss_ratio()
	suite._check_unit_prices()
	suite._check_processing_lines()
	suite._check_process_once()
	suite._check_haul_plan()
	suite._check_game_state_processing()
	suite._check_game_state_haul()
	suite._check_game_state_room_tools()
	suite._check_shop_panel()
	suite._check_vacuum_pack_rules()
	suite._check_vacuum_pack_in_game_state()


## 検証結果を selfcheck 本体へ記録する
func _check(cond: bool, label: String) -> void:
	_checker._check(cond, label)


## 大型の道具 5 つが表にあり、キーで選ぶのは吸引車 (9) と粘着シート (0) だけで、探し物を傷めるのは吸引車、並べられるのは加工機か
func _check_catalog() -> void:
	var selectable: Array[StringName] = ToolCatalogScript.selectable_tool_ids()
	_check(
		selectable.size() == 10
		and selectable[8] == ToolCatalogScript.TOOL_SUCTION_TRUCK
		and selectable[9] == ToolCatalogScript.TOOL_ADHESIVE_SHEET
		and not selectable.has(ToolCatalogScript.TOOL_ANDROID)
		and not selectable.has(ToolCatalogScript.TOOL_HAIR_PROCESSOR)
		and not selectable.has(ToolCatalogScript.TOOL_DUMP_TRUCK),
		"キーで選ぶ道具は 10 で、9 が吸引車・0 が粘着シート、アンドロイド・加工機・ダンプカーは選ばない (実際: %s)"
		% str(selectable),
	)
	_check(
		ToolRulesScript.damages_found_items(ToolCatalogScript.TOOL_SUCTION_TRUCK)
		and not ToolRulesScript.damages_found_items(ToolCatalogScript.TOOL_ANDROID)
		and not ToolRulesScript.damages_found_items(ToolCatalogScript.TOOL_ADHESIVE_SHEET)
		and not ToolRulesScript.damages_found_items(&"no_such_tool"),
		"吸引車は探し物を傷め、アンドロイドと粘着シートは傷めない (表に無い道具は傷めない)",
	)
	_check(
		ToolCatalogScript.max_owned(ToolCatalogScript.TOOL_HAIR_PROCESSOR) == 6
		and ToolCatalogScript.max_owned(ToolCatalogScript.TOOL_DUMP_TRUCK) == 1
		and ToolCatalogScript.max_owned(ToolCatalogScript.TOOL_TWEEZERS) == 1
		and ToolCatalogScript.max_owned(&"no_such_tool") == 0,
		"加工機は 6 台まで並べられ、ほかの道具は 1 つ、表に無い道具は 0",
	)
	_check(
		ToolRulesScript.removes_hair(ToolCatalogScript.TOOL_SUCTION_TRUCK)
		and ToolRulesScript.removes_hair(ToolCatalogScript.TOOL_ADHESIVE_SHEET)
		and ToolRulesScript.removes_hair(ToolCatalogScript.TOOL_ANDROID)
		and ToolRulesScript.removes_hair(ToolCatalogScript.TOOL_VACUUM)
		and not ToolRulesScript.removes_hair(ToolCatalogScript.TOOL_HAIR_PROCESSOR)
		and not ToolRulesScript.removes_hair(ToolCatalogScript.TOOL_DUMP_TRUCK)
		and not ToolRulesScript.removes_hair(ToolCatalogScript.TOOL_HAND),
		"毛を取る道具は手に持つ 5 つと吸引車・粘着シート・アンドロイドで、加工機・ダンプカー・手は毛を取らない",
	)


## 部屋ごとにかける道具も、どのレベル・表面でも取りこぼしが 0 より大きく 1 未満で (1 回では取り切らない)、レベルで減り、
## 粘着シートは床とカーペットだけ、吸引車とアンドロイドは部屋のすべての表面にかかるか
func _check_room_tool_miss_ratio() -> void:
	var all_in_range: bool = true
	for tool_id: StringName in ROOM_TOOLS:
		for level: int in range(1, ToolRulesScript.MAX_TOOL_LEVEL + 1):
			for surface_type: StringName in SelfcheckToolsScript.ALL_SURFACES:
				var ratio: float = ToolRulesScript.miss_ratio(tool_id, level, surface_type)
				if ratio <= 0.0 or ratio >= 1.0:
					all_in_range = false
	_check(all_in_range, "吸引車・粘着シート・アンドロイドは、どのレベル・表面でも取りこぼしが 0 より大きく 1 未満")
	var truck: StringName = ToolCatalogScript.TOOL_SUCTION_TRUCK
	_check(
		ToolRulesScript.miss_ratio(truck, 2, MansionLayoutScript.SURFACE_FLOOR)
		< ToolRulesScript.miss_ratio(truck, 1, MansionLayoutScript.SURFACE_FLOOR)
		and ToolRulesScript.level_up_price(truck, 1) == int(ToolCatalogScript.find_tool(truck)["price"])
		and ToolRulesScript.level_up_price(ToolCatalogScript.TOOL_HAIR_PROCESSOR, 1) == -1,
		"吸引車もレベルを上げると取りこぼしが減り (1→2 は買う値段と同じ)、加工機にはレベルが無い",
	)
	_check(
		ToolRulesScript.miss_ratio(truck, 1, MansionLayoutScript.SURFACE_FLOOR)
		< ToolRulesScript.miss_ratio(truck, 1, MansionLayoutScript.SURFACE_KNIT),
		"吸引車は床の方がニットより取りこぼしが少ない",
	)
	var sheet: StringName = ToolCatalogScript.TOOL_ADHESIVE_SHEET
	var sheet_surfaces: Array[StringName] = []
	var truck_surfaces: int = 0
	for surface_type: StringName in SelfcheckToolsScript.ALL_SURFACES:
		if ToolRulesScript.covers_surface(sheet, surface_type):
			sheet_surfaces.append(surface_type)
		if ToolRulesScript.covers_surface(truck, surface_type):
			truck_surfaces += 1
	_check(
		sheet_surfaces == [MansionLayoutScript.SURFACE_FLOOR, MansionLayoutScript.SURFACE_CARPET]
		and truck_surfaces == SelfcheckToolsScript.ALL_SURFACES.size()
		and ToolRulesScript.covers_surface(
			ToolCatalogScript.TOOL_ANDROID, MansionLayoutScript.SURFACE_SUIT
		)
		and not ToolRulesScript.covers_surface(
			ToolCatalogScript.TOOL_VACUUM, MansionLayoutScript.SURFACE_FLOOR
		),
		"粘着シートは床とカーペットだけ、吸引車とアンドロイドは全部の表面にかかり、手に持つ道具は部屋ごとにかけない (実際: %s)"
		% str(sheet_surfaces),
	)


## 加工した物の売値が段階ごとに上がり、色を分けた物 > 混ぜた物 > 毛のまま の順で、どの色でも毛のままより高いか
func _check_unit_prices() -> void:
	var white: StringName = SurfaceHairScript.COLOR_WHITE
	var calico: StringName = SurfaceHairScript.COLOR_CALICO
	var mixed: StringName = HairStockScript.COLOR_MIXED
	_check(
		ProcessingRulesScript.unit_price(HairStockScript.FORM_RAW, white, &"") == 1
		and ProcessingRulesScript.unit_price(HairStockScript.FORM_BALL, white, &"") == 30
		and ProcessingRulesScript.unit_price(HairStockScript.FORM_FELT, white, &"") == 200
		and ProcessingRulesScript.unit_price(HairStockScript.FORM_DOLL, white, &"") == 1200,
		"白の売値は 毛 1 円・毛玉 (20 本) 30 円・フェルト (100 本) 200 円・人形 (400 本) 1200 円",
	)
	_check(
		ProcessingRulesScript.unit_price(HairStockScript.FORM_BALL, calico, &"") == 60
		and ProcessingRulesScript.unit_price(HairStockScript.FORM_BALL, mixed, &"") == 24
		and ProcessingRulesScript.unit_price(HairStockScript.FORM_DOLL, mixed, &"") == 960,
		"三毛の毛玉 60 円、白と黒を混ぜた毛玉 24 円・人形 960 円",
	)
	var increasing: bool = true
	var beats_raw: bool = true
	for color_id: StringName in SurfaceHairScript.STANDARD_COLORS + [mixed]:
		var previous_per_hair: float = 0.0
		for form: StringName in ProcessingRulesScript.FORMS_IN_ORDER:
			if color_id == mixed and form == HairStockScript.FORM_RAW:
				continue
			var per_hair: float = (
				float(ProcessingRulesScript.unit_price(form, color_id, &""))
				/ float(ProcessingRulesScript.HAIRS_PER_UNIT[form])
			)
			if per_hair <= previous_per_hair:
				increasing = false
			previous_per_hair = per_hair
			# 混ぜた物は白と黒からできるため、白・黒の毛のままと比べる
			var raw_color: StringName = white if color_id == mixed else color_id
			if form != HairStockScript.FORM_RAW and per_hair <= float(
				EconomyRulesScript.hair_price(raw_color, &"")
			):
				beats_raw = false
	_check(increasing, "どの色 (混ぜた物を含む) でも、毛 1 本あたりの売値は 毛玉 < フェルト < 人形 と段階ごとに上がる")
	_check(beats_raw, "どの色・段階でも、加工した物は使った毛を毛のまま売るより高い (混ぜた物も白・黒の毛のままより高い)")
	var sorted_beats_mixed: bool = true
	for form: StringName in ProcessingRulesScript.FORMS_IN_ORDER:
		if form == HairStockScript.FORM_RAW:
			continue
		if (
			ProcessingRulesScript.unit_price(form, white, &"")
			<= ProcessingRulesScript.unit_price(form, mixed, &"")
		):
			sorted_beats_mixed = false
	_check(sorted_beats_mixed, "どの段階でも、色を分けて加工した物は混ぜて加工した物より高い")
	_check(
		ProcessingRulesScript.unit_price(
			HairStockScript.FORM_RAW, white, HandRulesScript.RARE_GOLDEN
		) == 300
		and ProcessingRulesScript.unit_price(&"no_such_form", white, &"") == 1,
		"珍しい毛は毛のままの値段 (金色 300 円) で売れ、表に無い形は毛のままの値段",
	)


## 加工機の台数で、混ぜる列・分ける列の数と 1 回に加工できる量が決まるか
func _check_processing_lines() -> void:
	var white: StringName = SurfaceHairScript.COLOR_WHITE
	var black: StringName = SurfaceHairScript.COLOR_BLACK
	var calico: StringName = SurfaceHairScript.COLOR_CALICO
	_check(
		ProcessingRulesScript.processing_lines(0).is_empty()
		and ProcessingRulesScript.processing_lines(-1).is_empty()
		and ProcessingRulesScript.processing_lines(1) == [[white, black]]
		and ProcessingRulesScript.processing_lines(2) == [[calico], [white, black]]
		and ProcessingRulesScript.processing_lines(3) == [[white], [black], [calico]]
		and ProcessingRulesScript.processing_lines(6) == [[white], [black], [calico]],
		"加工機 0 台は無し、1 台は白と黒を混ぜる 1 列、2 台は三毛と白・黒、3 台以上は色ごとの 3 列 (実際: 1 台 %s / 2 台 %s)"
		% [
			str(ProcessingRulesScript.processing_lines(1)),
			str(ProcessingRulesScript.processing_lines(2)),
		],
	)
	_check(
		ProcessingRulesScript.line_capacity(1, 0) == 400
		and ProcessingRulesScript.line_capacity(4, 0) == 800
		and ProcessingRulesScript.line_capacity(4, 1) == 400
		and ProcessingRulesScript.line_capacity(6, 2) == 800
		and ProcessingRulesScript.line_capacity(1, 1) == 0
		and ProcessingRulesScript.line_capacity(1, -1) == 0
		and ProcessingRulesScript.line_capacity(0, 0) == 0,
		"1 列の 1 回の量は受け持つ台数 × 400 本 (4 台は 2・1・1 台、6 台は 2 台ずつ)、無い列と負の列番号は 0",
	)
	_check(
		ProcessingRulesScript.runs_due(0.0, 9.9) == 0
		and ProcessingRulesScript.runs_due(9.9, 10.0) == 1
		and ProcessingRulesScript.runs_due(0.0, 35.0) == 3
		and ProcessingRulesScript.runs_due(10.0, 10.0) == 0
		and ProcessingRulesScript.runs_due(20.0, 5.0) == 0,
		"加工機は 10 秒の区切りをまたぐたびに 1 回加工し、時間が進まなければ加工しない",
	)
	_check(
		ProcessingRulesScript.split_into_products(520)
		== {HairStockScript.FORM_DOLL: 1, HairStockScript.FORM_FELT: 1, HairStockScript.FORM_BALL: 1}
		and ProcessingRulesScript.split_into_products(19) == {HairStockScript.FORM_RAW: 19}
		and ProcessingRulesScript.split_into_products(-5).is_empty(),
		"毛 520 本は人形 1・フェルト 1・毛玉 1 にし、19 本は毛のまま、負の本数は何も作らない",
	)


## 1 回の加工で、受け持つ色のふつうの毛だけを上限まで使い、珍しい毛と端数は毛のまま残し、渡した在庫は変えないか
func _check_process_once() -> void:
	var white: StringName = SurfaceHairScript.COLOR_WHITE
	var black: StringName = SurfaceHairScript.COLOR_BLACK
	var calico: StringName = SurfaceHairScript.COLOR_CALICO
	var stocks: Array[HairStock] = [
		SelfcheckToolsScript.make_stock(white, &"", HairStockScript.FORM_RAW, 450),
		SelfcheckToolsScript.make_stock(black, &"", HairStockScript.FORM_RAW, 30),
		SelfcheckToolsScript.make_stock(calico, &"", HairStockScript.FORM_RAW, 50),
		SelfcheckToolsScript.make_stock(white, HandRulesScript.RARE_GOLDEN, HairStockScript.FORM_RAW, 1),
	]
	var mixed_once: Array[HairStock] = ProcessingRulesScript.process_once(stocks, 1)
	_check(
		_count(mixed_once, HairStockScript.FORM_DOLL, HairStockScript.COLOR_MIXED) == 1
		and _count(mixed_once, HairStockScript.FORM_RAW, white) == 50
		and _count(mixed_once, HairStockScript.FORM_RAW, black) == 30
		and _count(mixed_once, HairStockScript.FORM_RAW, calico) == 50
		and _rare_count(mixed_once) == 1
		and stocks[0].count == 450,
		"加工機 1 台は白と黒から 400 本を使って混ぜた人形 1 体にし、三毛・珍しい毛は加工せず、渡した在庫は変えない",
	)
	var sorted_once: Array[HairStock] = ProcessingRulesScript.process_once(stocks, 3)
	_check(
		_count(sorted_once, HairStockScript.FORM_DOLL, white) == 1
		and _count(sorted_once, HairStockScript.FORM_RAW, white) == 50
		and _count(sorted_once, HairStockScript.FORM_BALL, black) == 1
		and _count(sorted_once, HairStockScript.FORM_RAW, black) == 10
		and _count(sorted_once, HairStockScript.FORM_BALL, calico) == 2
		and _count(sorted_once, HairStockScript.FORM_RAW, calico) == 10
		and _rare_count(sorted_once) == 1,
		"加工機 3 台は色ごとに分け、白の人形 1・黒の毛玉 1・三毛の毛玉 2 にし、20 本に満たない端数は毛のまま残す",
	)
	var raw_value: int = ProcessingRulesScript.stock_value(stocks)
	var mixed_value: int = ProcessingRulesScript.stock_value(mixed_once)
	var sorted_value: int = ProcessingRulesScript.stock_value(sorted_once)
	_check(
		raw_value < mixed_value and mixed_value < sorted_value,
		"同じ在庫を、毛のまま < 混ぜて加工 < 色を分けて加工 の順に高く売れる (実際: %d / %d / %d 円)"
		% [raw_value, mixed_value, sorted_value],
	)
	var none: Array[HairStock] = ProcessingRulesScript.process_once(stocks, 0)
	var too_few: Array[HairStock] = ProcessingRulesScript.process_once(
		[SelfcheckToolsScript.make_stock(white, &"", HairStockScript.FORM_RAW, 19)], 3
	)
	_check(
		ProcessingRulesScript.stock_value(none) == raw_value
		and _count(too_few, HairStockScript.FORM_RAW, white) == 19
		and _count(too_few, HairStockScript.FORM_BALL, white) == 0,
		"加工機 0 台では何も変わらず、毛玉 1 個 (20 本) に足りない毛は加工しない",
	)
	var with_doll: Array[HairStock] = ProcessingRulesScript.process_once(
		[
			SelfcheckToolsScript.make_stock(white, &"", HairStockScript.FORM_DOLL, 2),
			SelfcheckToolsScript.make_stock(white, &"", HairStockScript.FORM_RAW, 400),
		],
		3,
	)
	_check(
		_count(with_doll, HairStockScript.FORM_DOLL, white) == 3 and with_doll.size() == 2,
		"同じ色の人形がある在庫で人形をもう 1 体作ると、同じ行の個数が 2 → 3 になり行は増えない",
	)


## ダンプカーが、毛の本数に直した量で積める量まで在庫の並び順に積み、1 個が大きすぎる物はその回は積まないか
func _check_haul_plan() -> void:
	var white: StringName = SurfaceHairScript.COLOR_WHITE
	var stocks: Array[HairStock] = [
		SelfcheckToolsScript.make_stock(white, &"", HairStockScript.FORM_RAW, 3000),
		SelfcheckToolsScript.make_stock(white, &"", HairStockScript.FORM_DOLL, 10),
		SelfcheckToolsScript.make_stock(
			SurfaceHairScript.COLOR_BLACK, &"", HairStockScript.FORM_RAW, 1000
		),
	]
	var plan: Dictionary = ProcessingRulesScript.haul_plan(
		stocks, ProcessingRulesScript.DUMP_TRUCK_CAPACITY_HAIRS
	)
	_check(
		plan == {0: 3000, 1: 5}
		and ProcessingRulesScript.plan_hairs(stocks, plan) == 5000
		and ProcessingRulesScript.plan_value(stocks, plan) == 3000 + 5 * 1200,
		"ダンプカーは 1 回 5000 本分まで積み、毛 3000 本と人形 5 体 (2000 本分) で満杯、黒の毛は次の回 (実際: %s)"
		% str(plan),
	)
	var small: Dictionary = ProcessingRulesScript.haul_plan(
		[SelfcheckToolsScript.make_stock(white, &"", HairStockScript.FORM_DOLL, 3)], 399
	)
	_check(
		small.is_empty()
		and ProcessingRulesScript.haul_plan(stocks, 0).is_empty()
		and ProcessingRulesScript.haul_plan([], 5000).is_empty(),
		"人形 1 体 (400 本分) は 399 本分の空きには積まず、積める量 0 と在庫が空の時は何も積まない",
	)
	var with_empty_rows: Array[HairStock] = [
		null,
		SelfcheckToolsScript.make_stock(white, &"", HairStockScript.FORM_RAW, 0),
		SelfcheckToolsScript.make_stock(white, &"", HairStockScript.FORM_RAW, -3),
		SelfcheckToolsScript.make_stock(white, &"", HairStockScript.FORM_RAW, 7),
	]
	_check(
		ProcessingRulesScript.haul_plan(with_empty_rows, 5000) == {3: 7},
		"ダンプカーは null の行と、本数が 0 以下の行を積まない (実際: %s)"
		% str(ProcessingRulesScript.haul_plan(with_empty_rows, 5000)),
	)


## GameState で加工機を 6 台まで並べて買え、時間を進めると在庫が加工されて高く売れ、加工機が無ければ何も変わらないか
func _check_game_state_processing() -> void:
	var state: Node = GameStateScript.new()
	state.initialize_from_storage(TEST_SAVE_PATH, PackedStringArray(["--hair-count=300"]))
	var processor: StringName = ToolCatalogScript.TOOL_HAIR_PROCESSOR
	var progress: BuildingProgress = state.save_data.building_progress
	var white: StringName = SurfaceHairScript.COLOR_WHITE
	var calico: StringName = SurfaceHairScript.COLOR_CALICO
	progress.hair_stocks = [
		SelfcheckToolsScript.make_stock(white, &"", HairStockScript.FORM_RAW, 500),
		SelfcheckToolsScript.make_stock(calico, &"", HairStockScript.FORM_RAW, 100),
	]
	var raw_value: int = ProcessingRulesScript.stock_value(progress.hair_stocks)
	state.advance_time(30.0)
	_check(
		ProcessingRulesScript.stock_value(progress.hair_stocks) == raw_value,
		"加工機を持っていなければ、時間を進めても在庫は毛のまま",
	)
	progress.money = 4000 * 7
	var bought: int = 0
	for _step: int in range(7):
		if state.purchase(GameStateScript.PURCHASE_TOOL, processor):
			bought += 1
	_check(
		bought == 6 and ToolRulesScript.count_owned(progress.owned_tools, processor) == 6
		and state.get_money() == 4000,
		"加工機は 4000 円で 6 台まで並べて買え、7 台目は買えずお金が減らない (実際: %d 台)" % bought,
	)
	for _step: int in range(5):
		progress.owned_tools.erase(state.find_owned_tool(processor))
	var notified: Array[int] = [0]
	state.state_changed.connect(func() -> void: notified[0] += 1)
	state.advance_time(10.0)
	_check(
		_count(progress.hair_stocks, HairStockScript.FORM_DOLL, HairStockScript.COLOR_MIXED) == 1
		and _count(progress.hair_stocks, HairStockScript.FORM_RAW, white) == 100
		and _count(progress.hair_stocks, HairStockScript.FORM_RAW, calico) == 100
		and notified[0] >= 1,
		"加工機 1 台で 10 秒進めると、白 400 本が混ぜた人形 1 体になり、三毛は残り、知らせる",
	)
	state.advance_time(30.0)
	var notified_after_done: int = notified[0]
	state.advance_time(10.0)
	_check(
		notified[0] == notified_after_done,
		"加工機はあっても加工できる毛 (加工機 1 台の時の白・黒) が無くなった後は、時間が進んでも知らせない",
	)
	var processed_value: int = ProcessingRulesScript.stock_value(progress.hair_stocks)
	_check(
		_count(progress.hair_stocks, HairStockScript.FORM_FELT, HairStockScript.COLOR_MIXED) == 1
		and _count(progress.hair_stocks, HairStockScript.FORM_RAW, white) == 0
		and processed_value > raw_value,
		"続けて進めると残りの白 100 本も混ぜたフェルトになり、在庫の売値が毛のままより上がる (%d → %d 円)"
		% [raw_value, processed_value],
	)
	progress.hair_stocks.append(
		SelfcheckToolsScript.make_stock(white, &"", HairStockScript.FORM_RAW, 0)
	)
	var money_before: int = state.get_money()
	var earned: int = state.sell_hair_stocks()
	_check(
		earned == processed_value and state.get_money() == money_before + earned
		and earned > raw_value and progress.hair_stocks.is_empty(),
		"加工してから売ると、毛のまま売るより多く入る (%d 円 > %d 円)" % [earned, raw_value],
	)
	state.free()
	SaveStorageScript.delete_save_file(TEST_SAVE_PATH)


## GameState でダンプカーを呼ぶと、持っていれば積める量まで運び出して売り (買取業者の近くでなくてよい)、持っていなければ何も変えないか
func _check_game_state_haul() -> void:
	var state: Node = GameStateScript.new()
	state.initialize_from_storage(TEST_SAVE_PATH, PackedStringArray(["--hair-count=300"]))
	var progress: BuildingProgress = state.save_data.building_progress
	progress.hair_stocks = [
		SelfcheckToolsScript.make_stock(
			SurfaceHairScript.COLOR_WHITE, &"", HairStockScript.FORM_RAW, 6000
		)
	]
	var without: Dictionary = state.haul_with_dump_truck()
	_check(
		int(without["earned"]) == 0 and int(without["hauled_hairs"]) == 0
		and progress.hair_stocks[0].count == 6000,
		"ダンプカーを持っていなければ運び出せず、在庫が変わらない",
	)
	progress.money = 12500
	state.purchase(GameStateScript.PURCHASE_TOOL, ToolCatalogScript.TOOL_DUMP_TRUCK)
	var first: Dictionary = state.haul_with_dump_truck()
	_check(
		int(first["hauled_hairs"]) == 5000 and int(first["earned"]) == 5000
		and state.get_money() == 5000 and progress.hair_stocks[0].count == 1000,
		"ダンプカーは 1 回で 5000 本分を運んで売り、残りの 1000 本は在庫に残る (実際: %s)" % str(first),
	)
	var second: Dictionary = state.haul_with_dump_truck()
	var third: Dictionary = state.haul_with_dump_truck()
	_check(
		int(second["hauled_hairs"]) == 1000 and progress.hair_stocks.is_empty()
		and int(third["earned"]) == 0 and state.get_money() == 6000,
		"2 回目で残りを運び切り、在庫が空の 3 回目は何も変えない",
	)
	state.free()
	SaveStorageScript.delete_save_file(TEST_SAVE_PATH)


## 粘着シートは床とカーペットにまとめて 1 回かけてシートを 1 枚だけ使い、吸引車とアンドロイドは部屋の表面から
## 1 回では取り切らない本数を取り、取った毛は HairField からも同じだけ消えるか
func _check_game_state_room_tools() -> void:
	var state: Node = GameStateScript.new()
	state.initialize_from_storage(TEST_SAVE_PATH, PackedStringArray(["--hair-count=6000"]))
	var progress: BuildingProgress = state.save_data.building_progress
	var world: MansionWorld = MansionWorldScript.new()
	world.rebuild(state.current_layout, progress)
	progress.money = 1000000
	for tool_id: StringName in ROOM_TOOLS:
		state.purchase(GameStateScript.PURCHASE_TOOL, tool_id)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 12
	var room_id: StringName = state.current_layout.rooms[0].room_id
	var sheet: StringName = ToolCatalogScript.TOOL_ADHESIVE_SHEET
	var sheet_owned: OwnedTool = state.find_owned_tool(sheet)
	var sheet_plan: Dictionary = ToolController.plan_room_removal(world, room_id, sheet, 1, rng)
	var sheet_surfaces: Array = (sheet_plan["counts_by_surface"] as Dictionary).keys()
	var only_floor_like: bool = not sheet_surfaces.is_empty()
	for surface_id: Variant in sheet_surfaces:
		var surface_def: MansionLayout.SurfaceDef = _surface_def(state.current_layout, surface_id)
		if not ToolRulesScript.SHEET_SURFACE_TYPES.has(surface_def.surface_type):
			only_floor_like = false
	var notified: Array[int] = [0]
	state.state_changed.connect(func() -> void: notified[0] += 1)
	var sheet_removed: int = state.apply_tool_sweep(sheet, sheet_plan["counts_by_surface"])
	_remove_from_field(world, sheet_plan["removed_ids"])
	_check(
		only_floor_like and sheet_owned.consumable_count == 2 and notified[0] == 1
		and sheet_removed == (sheet_plan["removed_ids"] as PackedInt32Array).size()
		and sheet_removed > 0 and sheet_removed < int(sheet_plan["in_range"]),
		"粘着シートは床とカーペットだけにかかり、表面がいくつあってもシートを 1 枚 (3 → 2) だけ使い、1 回知らせ、取り切らない (%d / %d 本)"
		% [sheet_removed, int(sheet_plan["in_range"])],
	)
	sheet_owned.consumable_count = 0
	_check(
		state.apply_tool_sweep(sheet, {}) == -1 and sheet_owned.consumable_count == 0,
		"シートが 0 枚の粘着シートは敷けない",
	)
	var truck: StringName = ToolCatalogScript.TOOL_SUCTION_TRUCK
	var before_room: int = int(state.get_room_status(room_id)["hair_count"])
	var truck_plan: Dictionary = ToolController.plan_room_removal(world, room_id, truck, 1, rng)
	var truck_removed: int = state.apply_tool_sweep(truck, truck_plan["counts_by_surface"])
	_remove_from_field(world, truck_plan["removed_ids"])
	var after_room: int = int(state.get_room_status(room_id)["hair_count"])
	var truck_in_range: int = int(truck_plan["in_range"])
	_check(
		int(truck_plan["in_range"]) == before_room
		and truck_removed > 0 and after_room == before_room - truck_removed
		and after_room > 0
		and float(truck_in_range - truck_removed) / float(truck_in_range)
		>= ToolRulesScript.MIN_MISS_RATIO,
		"吸引車は部屋のすべての表面 (%d 本) から 1 回で %d 本を取り、部屋の毛が同じだけ減り、取り切らない (残り %d 本)"
		% [before_room, truck_removed, after_room],
	)
	_check(
		world.get_hair_field().get_remaining_count() == state.get_total_remaining_hairs(),
		"粘着シートと吸引車で取った毛は、描く毛 (HairField) からも同じ本数だけ消える",
	)
	var other_room: StringName = state.current_layout.rooms[1].room_id
	var other_before: int = int(state.get_room_status(other_room)["hair_count"])
	var android_plan: Dictionary = ToolController.plan_room_removal(
		world, other_room, ToolCatalogScript.TOOL_ANDROID, 1, rng
	)
	var android_removed: int = state.apply_tool_sweep(
		ToolCatalogScript.TOOL_ANDROID, android_plan["counts_by_surface"]
	)
	_check(
		android_removed > 0 and android_removed < other_before
		and not ToolRulesScript.damages_found_items(ToolCatalogScript.TOOL_ANDROID),
		"アンドロイドは部屋の毛を取りきらずに取り (%d / %d 本)、探し物を傷めない" % [android_removed, other_before],
	)
	_check_room_plan_per_surface(world, android_plan, other_room)
	_check_last_hair_kept(world, rng)
	# 部屋の選び方の検証は全部の表面を 1 本ずつにするため、毛が要る掃除の間隔の検証を先に行う
	_check_android_timing(state, world)
	_check_android_room_choice(state, world)
	_check_select_only_keyed_tools(state)
	_check_sweep_rejects_partly_unknown_surfaces(state)
	_check(
		(ToolController.plan_room_removal(world, room_id, &"no_such_tool", 1, rng)["removed_ids"]
		as PackedInt32Array).is_empty(),
		"表に無い道具の id では部屋の毛を取る計画が空になる",
	)
	world.free()
	state.free()
	SaveStorageScript.delete_save_file(TEST_SAVE_PATH)


## アンドロイドの 1 回の計画 plan (部屋 room_id) が、表面ごとに max_hairs (30 本) までしか取らず、表面ごとに 1 本以上残すか
func _check_room_plan_per_surface(
	world: MansionWorld, plan: Dictionary, room_id: StringName
) -> void:
	var max_hairs: int = int(
		ToolCatalogScript.find_tool(ToolCatalogScript.TOOL_ANDROID)["max_hairs"]
	)
	var hair_field: Node3D = world.get_hair_field()
	var within_cap: bool = true
	var over_cap_surface_seen: bool = false
	for surface_index: int in range(hair_field.get_surface_count()):
		var surface_def: MansionLayout.SurfaceDef = world.get_surface_def(surface_index)
		if surface_def.room_id != room_id:
			continue
		var on_surface: int = hair_field.get_surface_remaining_count(surface_index)
		over_cap_surface_seen = over_cap_surface_seen or on_surface > max_hairs + 1
		var taken: int = 0
		var counts_by_color: Dictionary = plan["counts_by_surface"].get(surface_def.surface_id, {})
		for count: Variant in counts_by_color.values():
			taken += int(count)
		if taken > max_hairs or (on_surface > 0 and taken > on_surface - 1):
			within_cap = false
	_check(
		over_cap_surface_seen and within_cap,
		"アンドロイドは表面 1 つから %d 本までしか取らず、どの表面にも 1 本以上残す (%d 本より多い表面を含む部屋で確かめた)"
		% [max_hairs, max_hairs + 1],
	)


## 毛が 1 本だけ・2 本だけの表面に部屋ごとの道具をかけると、1 本だけの表面からは取らず、2 本の表面からは 1 本までしか取らないか
func _check_last_hair_kept(world: MansionWorld, rng: RandomNumberGenerator) -> void:
	var hair_field: Node3D = world.get_hair_field()
	var room_id: StringName = world.get_surface_def(0).room_id
	var one_index: int = -1
	var two_index: int = -1
	for surface_index: int in range(hair_field.get_surface_count()):
		if world.get_surface_def(surface_index).room_id != room_id:
			continue
		var keep: int = 1 if one_index < 0 else (2 if two_index < 0 else -1)
		if keep < 0:
			break
		if hair_field.get_surface_remaining_count(surface_index) < keep:
			continue
		while hair_field.get_surface_remaining_count(surface_index) > keep:
			hair_field.remove_hair(hair_field.get_hair_id_at_slot(surface_index, 0))
		if keep == 1:
			one_index = surface_index
		else:
			two_index = surface_index
	var removed_from: Dictionary = {}
	for _attempt: int in range(20):
		var plan: Dictionary = ToolController.plan_room_removal(
			world, room_id, ToolCatalogScript.TOOL_SUCTION_TRUCK, ToolRulesScript.MAX_TOOL_LEVEL, rng
		)
		for surface_id: Variant in (plan["counts_by_surface"] as Dictionary).keys():
			var taken: int = 0
			for count: Variant in (plan["counts_by_surface"][surface_id] as Dictionary).values():
				taken += int(count)
			removed_from[surface_id] = maxi(int(removed_from.get(surface_id, 0)), taken)
	_check(
		one_index >= 0 and two_index >= 0
		and int(removed_from.get(world.get_surface_def(one_index).surface_id, 0)) == 0
		and int(removed_from.get(world.get_surface_def(two_index).surface_id, 0)) == 1,
		"部屋ごとの道具を 20 回計画しても、毛が 1 本の表面からは取らず、2 本の表面からは 1 本までしか取らない (最後の 1 本を残す)",
	)


## アンドロイドは掃除の間隔 (4 秒) の直前では掃除せず、間隔ごとに掃除し、進行を作り直すとたまった時間が戻り、
## 持っていなければ何も変えないか
func _check_android_timing(state: Node, world: MansionWorld) -> void:
	var site: BigToolSite = BigToolSite.new()
	site.setup(state, world)
	site.set_rng_seed(7)
	var owned: OwnedTool = state.find_owned_tool(ToolCatalogScript.TOOL_ANDROID)
	var progress: BuildingProgress = state.save_data.building_progress
	progress.owned_tools.erase(owned)
	var total_before: int = state.get_total_remaining_hairs()
	var unowned: Dictionary = site.step_android()
	var unowned_advance: int = site.advance(BigToolSite.ANDROID_INTERVAL_SECONDS * 2.0)
	progress.owned_tools.append(owned)
	site.reset_for_new_progress()
	_check(
		unowned.is_empty() and unowned_advance == 0 and state.get_total_remaining_hairs() == total_before,
		"アンドロイドを持っていない時は掃除せず、時間が進んでも毛が変わらない",
	)
	var just_before: int = site.advance(BigToolSite.ANDROID_INTERVAL_SECONDS - 0.1)
	site.reset_for_new_progress()
	var after_reset: int = site.advance(0.2)
	var on_time: int = site.advance(BigToolSite.ANDROID_INTERVAL_SECONDS)
	_check(
		just_before == 0 and after_reset == 0 and on_time > 0,
		"アンドロイドは 4 秒の直前では掃除せず、作り直すとたまった時間が戻り (3.9 秒 + 0.2 秒では掃除しない)、4 秒で掃除する (%d 本)"
		% on_time,
	)
	site.free()


## キーで選ばない道具 (アンドロイド・加工機・ダンプカー) は持っていても選べず、キーで選ぶ大型の道具は持っていれば選べるか
func _check_select_only_keyed_tools(state: Node) -> void:
	var controller: ToolController = ToolController.new()
	controller._game_state = state
	state.save_data.building_progress.money = 100000
	for tool_id: StringName in [
		ToolCatalogScript.TOOL_HAIR_PROCESSOR, ToolCatalogScript.TOOL_DUMP_TRUCK
	]:
		state.purchase(GameStateScript.PURCHASE_TOOL, tool_id)
	_check(
		not controller.select_tool(ToolCatalogScript.TOOL_ANDROID)
		and not controller.select_tool(ToolCatalogScript.TOOL_HAIR_PROCESSOR)
		and not controller.select_tool(ToolCatalogScript.TOOL_DUMP_TRUCK)
		and controller.get_selected_tool_id() == ToolCatalogScript.TOOL_HAND
		and controller.select_tool(ToolCatalogScript.TOOL_SUCTION_TRUCK)
		and controller.get_selected_tool_id() == ToolCatalogScript.TOOL_SUCTION_TRUCK,
		"持っているアンドロイド・加工機・ダンプカーは選べず手のまま、持っている吸引車は選べる",
	)
	controller.free()


## 道具を面ごとにかける時、無い面が 1 つでも混ざると、ほかの面の毛・在庫・消耗品を変えずに -1 を返すか
func _check_sweep_rejects_partly_unknown_surfaces(state: Node) -> void:
	var sheet: StringName = ToolCatalogScript.TOOL_ADHESIVE_SHEET
	var owned: OwnedTool = state.find_owned_tool(sheet)
	owned.consumable_count = 2
	var surface: SurfaceHair = null
	for candidate: SurfaceHair in state.save_data.building_progress.surface_hairs:
		if candidate.count_for_color(SurfaceHairScript.COLOR_WHITE) > 0:
			surface = candidate
			break
	var before_white: int = surface.count_for_color(SurfaceHairScript.COLOR_WHITE)
	var before_stock: int = state.get_raw_hair_stock_count()
	_check(
		state.apply_tool_sweep(
			sheet,
			{surface.surface_id: {SurfaceHairScript.COLOR_WHITE: 1}, &"no_such_surface": {}},
		) == -1
		and surface.count_for_color(SurfaceHairScript.COLOR_WHITE) == before_white
		and state.get_raw_hair_stock_count() == before_stock
		and owned.consumable_count == 2,
		"有る面と無い面が混ざると、有る面の毛・在庫・シートの枚数を変えずに -1 を返す",
	)


## アンドロイドが掃除する部屋は、道具で取れる毛 (表面ごとの最後の 1 本を除いた本数) のいちばん多い部屋で、
## 表面ごとに 1 本ずつしか残っていない部屋は毛の合計が多くても選ばず、どの部屋も取れなければ選ばないか
func _check_android_room_choice(state: Node, world: MansionWorld) -> void:
	var site: BigToolSite = BigToolSite.new()
	site.setup(state, world)
	var hair_field: Node3D = world.get_hair_field()
	var rooms: Array = state.current_layout.rooms
	var expected_room: StringName = rooms[rooms.size() - 1].room_id
	for surface_index: int in range(hair_field.get_surface_count()):
		if world.get_surface_def(surface_index).room_id == expected_room:
			continue
		while hair_field.get_surface_remaining_count(surface_index) > 2:
			hair_field.remove_hair(hair_field.get_hair_id_at_slot(surface_index, 0))
	var first_choice: StringName = site.dirtiest_room_id()
	_check(
		first_choice == expected_room,
		"ほかの部屋の表面を 2 本以下にすると、毛を残した最後の部屋 %s を選ぶ (実際: %s)" % [expected_room, first_choice],
	)
	var leftover: int = 0
	for surface_index: int in range(hair_field.get_surface_count()):
		if world.get_surface_def(surface_index).room_id != first_choice:
			continue
		while hair_field.get_surface_remaining_count(surface_index) > 1:
			hair_field.remove_hair(hair_field.get_hair_id_at_slot(surface_index, 0))
		leftover += hair_field.get_surface_remaining_count(surface_index)
	var second_choice: StringName = site.dirtiest_room_id()
	_check(
		first_choice != &"" and leftover > 0 and second_choice != &"" and second_choice != first_choice,
		"表面ごとに 1 本ずつ (%d 本) しか残っていない部屋 %s は選ばず、取れる毛のある部屋 %s を選ぶ"
		% [leftover, first_choice, second_choice],
	)
	for surface_index: int in range(hair_field.get_surface_count()):
		while hair_field.get_surface_remaining_count(surface_index) > 1:
			hair_field.remove_hair(hair_field.get_hair_id_at_slot(surface_index, 0))
	_check(
		site.dirtiest_room_id() == &"" and hair_field.get_remaining_count() > 0,
		"どの表面も 1 本ずつしか残っていない時は、アンドロイドが掃除する部屋は無い",
	)
	site.free()


## 掃除機のパックは「あと何回吸えるか」で数え、交換すると 25 回に戻り (足さない)、紙・シートは買い足すと足され、
## 尽きた時の文言がパックは「一杯」、紙は「無い」になるか
func _check_vacuum_pack_rules() -> void:
	var vacuum: StringName = ToolCatalogScript.TOOL_VACUUM
	var roller: StringName = ToolCatalogScript.TOOL_LINT_ROLLER
	_check(
		ToolRulesScript.refill_replaces(vacuum)
		and not ToolRulesScript.refill_replaces(roller)
		and not ToolRulesScript.refill_replaces(ToolCatalogScript.TOOL_ADHESIVE_SHEET)
		and not ToolRulesScript.refill_replaces(&"no_such_tool"),
		"交換で戻す消耗品は掃除機のパックだけで、紙・シート・表に無い道具は足す",
	)
	_check(
		ToolRulesScript.refilled_count(vacuum, 0) == 25
		and ToolRulesScript.refilled_count(vacuum, 7) == 25
		and ToolRulesScript.refilled_count(roller, 3) == 23
		and ToolRulesScript.refilled_count(&"no_such_tool", 4) == 4,
		"パックの交換は残りによらず 25 回に戻り、紙は 20 枚足され (3 → 23)、表に無い道具は変わらない",
	)
	_check(
		ToolRulesScript.consumable_unit(vacuum) == "回"
		and ToolRulesScript.consumable_unit(roller) == "枚"
		and ToolRulesScript.consumable_unit(ToolCatalogScript.TOOL_TWEEZERS) == "枚",
		"パックの空きは「回」、紙は「枚」で数え、消耗品の無い道具も既定の「枚」",
	)
	_check(
		ToolRulesScript.consumable_empty_message(vacuum).contains("パックが一杯")
		and ToolRulesScript.consumable_empty_message(vacuum).contains("アンドロイド")
		and (
			ToolRulesScript.consumable_empty_message(roller) == "粘着ローラー の紙が無い (T で買い足す)"
		),
		"尽きた時の文言は、掃除機は「パックが一杯」でアンドロイドの自動の交換を案内し、粘着ローラーは「紙が無い」 (実際: %s)"
		% ToolRulesScript.consumable_empty_message(vacuum),
	)


## GameState で掃除機を 25 回使うとパックが一杯になって使えなくなり、手で交換すると 30 円で 25 回に戻り、
## アンドロイドを持っていれば一杯の時だけ同じ値段で交換させられるか
func _check_vacuum_pack_in_game_state() -> void:
	var state: Node = GameStateScript.new()
	state.initialize_from_storage(TEST_SAVE_PATH, PackedStringArray(["--hair-count=6000"]))
	var progress: BuildingProgress = state.save_data.building_progress
	var vacuum: StringName = ToolCatalogScript.TOOL_VACUUM
	var exchange: StringName = GameStateScript.PURCHASE_ANDROID_PACK_EXCHANGE
	progress.money = int(ToolCatalogScript.find_tool(vacuum)["price"])
	state.purchase(GameStateScript.PURCHASE_TOOL, vacuum)
	var owned: OwnedTool = state.find_owned_tool(vacuum)
	var surface: SurfaceHair = null
	for candidate: SurfaceHair in progress.surface_hairs:
		if candidate.count_for_color(SurfaceHairScript.COLOR_WHITE) > 30:
			surface = candidate
			break
	var used: int = 0
	for _step: int in range(30):
		var sweep: Dictionary = {surface.surface_id: {SurfaceHairScript.COLOR_WHITE: 1}}
		if state.apply_tool_sweep(vacuum, sweep) >= 0:
			used += 1
	_check(
		owned.consumable_count == 0 and used == 25,
		"掃除機は買うとパックの空きが 25 回で、25 回使うと一杯になり 26 回目からは使えない (使えた回数 %d)" % used,
	)
	progress.money = 1000
	_check(
		not state.purchase(exchange, vacuum)
		and state.get_money() == 1000 and owned.consumable_count == 0,
		"アンドロイドを持っていない時は、一杯のパックをアンドロイドに交換させられず、お金も減らない",
	)
	_check(
		state.purchase(GameStateScript.PURCHASE_CONSUMABLE, vacuum)
		and owned.consumable_count == 25 and state.get_money() == 970,
		"手でパックを交換すると 30 円で空きが 25 回に戻る",
	)
	_check(
		not state.purchase(GameStateScript.PURCHASE_CONSUMABLE, vacuum)
		and owned.consumable_count == 25 and state.get_money() == 970,
		"空きが満タン (25 回) のパックは交換できず、お金が減らない",
	)
	progress.money = 100000 + 1000
	state.purchase(GameStateScript.PURCHASE_TOOL, ToolCatalogScript.TOOL_ANDROID)
	owned.consumable_count = 3
	_check(
		not state.purchase(exchange, vacuum)
		and owned.consumable_count == 3 and state.get_money() == 1000,
		"アンドロイドを持っていても、パックがまだ一杯でない時は交換しない",
	)
	owned.consumable_count = 0
	var exchanged: bool = state.purchase(exchange, vacuum)
	_check(
		exchanged and owned.consumable_count == 25 and state.get_money() == 970,
		"アンドロイドを持っていてパックが一杯の時は、アンドロイドが 30 円で交換し、空きが 25 回に戻る",
	)
	state.purchase(GameStateScript.PURCHASE_TOOL, ToolCatalogScript.TOOL_LINT_ROLLER)
	var roller_owned: OwnedTool = state.find_owned_tool(ToolCatalogScript.TOOL_LINT_ROLLER)
	roller_owned.consumable_count = 0
	owned.consumable_count = 0
	progress.money = 29
	_check(
		not state.purchase(exchange, vacuum) and owned.consumable_count == 0 and state.get_money() == 29
		and not state.purchase(exchange, ToolCatalogScript.TOOL_LINT_ROLLER)
		and roller_owned.consumable_count == 0,
		"お金が交換の値段に 1 円足りない時と、パックでない消耗品 (紙) は、アンドロイドに交換させられない",
	)
	state.free()
	SaveStorageScript.delete_save_file(TEST_SAVE_PATH)


## 道具を買う画面が、加工機の並べた台数・ダンプカーのボタン・加工品の個数を出すか
func _check_shop_panel() -> void:
	var state: Node = GameStateScript.new()
	state.initialize_from_storage(TEST_SAVE_PATH, PackedStringArray(["--hair-count=300"]))
	var panel: PanelContainer = ToolShopPanelScript.new()
	var processor: StringName = ToolCatalogScript.TOOL_HAIR_PROCESSOR
	var progress: BuildingProgress = state.save_data.building_progress
	progress.money = 4000
	panel.refresh(state, false)
	var unowned_text: String = ToolShopPanelScript.describe_tool(processor, null, 0)
	_check(
		unowned_text.contains("未購入") and not unowned_text.contains("台 ("),
		"持っていない加工機の説明は「未購入」で、並べた台数を出さない (実際: %s)" % unowned_text,
	)
	_check(
		panel.get_tool_button(processor).text == "買う (4000 円)"
		and not panel.get_haul_button().visible,
		"加工機を持っていない時は「買う」で、ダンプカーを持っていなければ運び出すボタンを出さない",
	)
	state.purchase(GameStateScript.PURCHASE_TOOL, processor)
	progress.money = 100000
	panel.refresh(state, false)
	var requested: Array = []
	panel.purchase_requested.connect(
		func(kind: StringName, item_id: StringName) -> void: requested.append([kind, item_id])
	)
	panel.get_tool_button(processor).pressed.emit()
	_check(
		panel.get_tool_button(processor).text == "もう 1 台並べる (4000 円)"
		and requested == [[GameStateScript.PURCHASE_TOOL, processor]]
		and ToolShopPanelScript.describe_tool(processor, state.find_owned_tool(processor), 1).contains(
			"1 台 (6 台まで)"
		),
		"加工機は 1 台持っていても「もう 1 台並べる」で、押すと買う操作を出し、説明に台数が出る (実際: %s)"
		% panel.get_tool_button(processor).text,
	)
	for _step: int in range(5):
		state.purchase(GameStateScript.PURCHASE_TOOL, processor)
	state.purchase(GameStateScript.PURCHASE_TOOL, ToolCatalogScript.TOOL_DUMP_TRUCK)
	progress.hair_stocks = [
		SelfcheckToolsScript.make_stock(SurfaceHairScript.COLOR_WHITE, &"", HairStockScript.FORM_BALL, 3),
		SelfcheckToolsScript.make_stock(SurfaceHairScript.COLOR_WHITE, &"", HairStockScript.FORM_DOLL, 1),
	]
	panel.refresh(state, false)
	var haul_requested: Array[int] = [0]
	panel.haul_requested.connect(func() -> void: haul_requested[0] += 1)
	panel.get_haul_button().pressed.emit()
	_check(
		panel.get_tool_button(processor).text == "6 台並べた (上限)"
		and panel.get_tool_button(processor).disabled
		and panel.get_haul_button().visible and not panel.get_haul_button().disabled
		and haul_requested[0] == 1
		and panel.get_sell_button().disabled,
		"加工機 6 台で上限と出て押せず、ダンプカーがあれば買取業者から離れていても運び出すボタンが押せる",
	)
	_check(
		ToolShopPanelScript.describe_products(progress.hair_stocks) == " / 毛玉 3 個・人形 1 個"
		and ToolShopPanelScript.describe_products([]) == "",
		"所持金の見出しに加工品の個数 (毛玉 3 個・人形 1 個) を出し、加工品が無ければ何も足さない (実際: %s)"
		% ToolShopPanelScript.describe_products(progress.hair_stocks),
	)
	panel.free()
	state.free()
	SaveStorageScript.delete_save_file(TEST_SAVE_PATH)


## HairField から毛 ID の並びを消す
func _remove_from_field(world: MansionWorld, hair_ids: PackedInt32Array) -> void:
	for hair_id: int in hair_ids:
		world.get_hair_field().remove_hair(hair_id)


## レイアウトから面の定義を返す
func _surface_def(layout: MansionLayout, surface_id: Variant) -> MansionLayout.SurfaceDef:
	for surface_def: MansionLayout.SurfaceDef in layout.surfaces:
		if surface_def.surface_id == StringName(surface_id):
			return surface_def
	return null


## 在庫のうち、形と色が一致するふつうの (珍しい毛でない) 物の個数を返す
func _count(stocks: Array[HairStock], form: StringName, color_id: StringName) -> int:
	var total: int = 0
	for stock: HairStock in stocks:
		if stock.form == form and stock.hair_color == color_id and stock.rare_hair_id == &"":
			total += stock.count
	return total


## 在庫のうち珍しい毛の本数を返す
func _rare_count(stocks: Array[HairStock]) -> int:
	var total: int = 0
	for stock: HairStock in stocks:
		if stock.rare_hair_id != &"":
			total += stock.count
	return total


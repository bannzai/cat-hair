extends RefCounted
## 手に持って使う道具 (取りこぼし・得意な表面・レベル・消耗品・値段)、お金の入り口 (毛を売る・掃除代)、
## 住人の機嫌と部屋のきれいさ、GameState の買う・道具をかける・売る・時間を進める入口、道具を買う画面の検証スイート
## (scripts/dev/selfcheck.gd から呼ぶ)。

## 手に持って使う道具の定義
const ToolCatalogScript := preload("res://scripts/tools/tool_catalog.gd")
## 手に持って使う道具のルールの計算
const ToolRulesScript := preload("res://scripts/tools/tool_rules.gd")
## 加工した物を含む在庫の売値の計算
const ProcessingRulesScript := preload("res://scripts/economy/processing_rules.gd")
## 毛を売る・掃除代・機嫌の計算
const EconomyRulesScript := preload("res://scripts/economy/economy_rules.gd")
## 手で毛を取る時のルールの計算 (珍しい毛・手の強化の id)
const HandRulesScript := preload("res://scripts/hand/hand_rules.gd")
## 屋敷レイアウト型スクリプト
const MansionLayoutScript := preload("res://scripts/mansion/mansion_layout.gd")
## 屋敷ビルダーロジックスクリプト (住人の id)
const MansionBuilderScript := preload("res://scripts/mansion/mansion_builder.gd")
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
const TEST_SAVE_PATH: String = "user://selfcheck_tools_save_data.json"
## 表面の種類の一覧 (取りこぼしの割合を全部の組み合わせで確かめる)
const ALL_SURFACES: Array[StringName] = [
	MansionLayoutScript.SURFACE_FLOOR,
	MansionLayoutScript.SURFACE_CARPET,
	MansionLayoutScript.SURFACE_SOFA,
	MansionLayoutScript.SURFACE_KNIT,
	MansionLayoutScript.SURFACE_SUIT,
	MansionLayoutScript.SURFACE_FURNITURE,
]

## 検証結果を記録する selfcheck の SceneTree 参照
var _checker: SceneTree = null


## 道具とお金の検証をすべて実行する
static func run_all(checker: SceneTree) -> void:
	var suite: RefCounted = load("res://scripts/dev/selfcheck_tools.gd").new()
	suite._checker = checker
	suite._check_tool_catalog()
	suite._check_miss_ratio()
	suite._check_prices_and_consumables()
	suite._check_hair_prices()
	suite._check_cleanliness_mood_and_fee()
	suite._check_game_state_purchase()
	suite._check_game_state_tool_sweep_and_sell()
	suite._check_game_state_advance_time()
	suite._check_tool_shop_panel()


## 検証結果を selfcheck 本体へ記録する
func _check(cond: bool, label: String) -> void:
	_checker._check(cond, label)


## 道具が手を含めて 13 (手に持つ 8 つと大型の 5 つ) あり、id が重ならず、消耗品と探し物を傷める道具が想定どおりか
func _check_tool_catalog() -> void:
	var ids: Array[StringName] = ToolCatalogScript.all_tool_ids()
	var unique: Dictionary = {}
	for tool_id: StringName in ids:
		unique[tool_id] = true
	_check(
		ids.size() == 13 and unique.size() == 13 and ids[0] == ToolCatalogScript.TOOL_HAND,
		"道具は手を先頭に 13 (手に持つ 8 つと大型の 5 つ) で id が重ならない (実際: %s)" % str(ids),
	)
	var consumable_tools: Array[StringName] = []
	var damaging_tools: Array[StringName] = []
	for tool_def: Dictionary in ToolCatalogScript.TOOLS:
		if ToolRulesScript.uses_consumable(tool_def["id"]):
			consumable_tools.append(tool_def["id"])
		if bool(tool_def["damages_found_items"]):
			damaging_tools.append(tool_def["id"])
	_check(
		consumable_tools == [ToolCatalogScript.TOOL_LINT_ROLLER, ToolCatalogScript.TOOL_ADHESIVE_SHEET],
		"消耗品を使う道具は粘着ローラーと建物を覆う粘着シートだけ (実際: %s)" % str(consumable_tools),
	)
	_check(
		damaging_tools.has(ToolCatalogScript.TOOL_PACKING_TAPE)
		and damaging_tools.has(ToolCatalogScript.TOOL_VACUUM)
		and not damaging_tools.has(ToolCatalogScript.TOOL_TWEEZERS),
		"ガムテープと掃除機は探し物を傷め、ピンセットは傷めない",
	)
	_check(
		ToolCatalogScript.find_tool(&"no_such_tool").is_empty(),
		"表に無い道具の id は空の定義を返す",
	)
	var controller: ToolController = ToolController.new()
	var no_cat: Dictionary = controller.brush_cat(&"")
	_check(
		not bool(no_cat["used"]) and str(no_cat["message"]).contains("猫がいない"),
		"ブラシは狙いの先に猫がいなければ「猫がいない」と出して使わない",
	)
	controller.free()


## 取りこぼしはどの道具・レベル・表面でも 0 より大きく 1 未満で、得意な表面ほど少なく、レベルで減り、上下限で止まるか
func _check_miss_ratio() -> void:
	var all_in_range: bool = true
	var sweep_count: int = 0
	for tool_def: Dictionary in ToolCatalogScript.TOOLS:
		if tool_def["kind"] != ToolCatalogScript.KIND_SWEEP:
			continue
		sweep_count += 1
		for level: int in range(1, ToolRulesScript.MAX_TOOL_LEVEL + 1):
			for surface_type: StringName in ALL_SURFACES:
				var ratio: float = ToolRulesScript.miss_ratio(tool_def["id"], level, surface_type)
				if ratio <= 0.0 or ratio >= 1.0:
					all_in_range = false
	_check(
		sweep_count == 5 and all_in_range,
		"毛を取る 5 つの道具は、どのレベル・表面でも取りこぼしが 0 より大きく 1 未満 (取り切れない)",
	)
	var roller: StringName = ToolCatalogScript.TOOL_LINT_ROLLER
	var good: float = ToolRulesScript.miss_ratio(roller, 1, MansionLayoutScript.SURFACE_SUIT)
	var normal: float = ToolRulesScript.miss_ratio(roller, 1, MansionLayoutScript.SURFACE_FURNITURE)
	var bad: float = ToolRulesScript.miss_ratio(roller, 1, MansionLayoutScript.SURFACE_FLOOR)
	_check(
		is_equal_approx(normal, 0.35) and is_equal_approx(good, 0.175) and is_equal_approx(bad, 0.56),
		"粘着ローラーの取りこぼしはスーツ (得意) 17.5%%・家具 35%%・床 (不得意) 56%% (実際: %f / %f / %f)"
		% [good, normal, bad],
	)
	_check(
		ToolRulesScript.surface_rating(roller, MansionLayoutScript.SURFACE_SUIT)
		== ToolRulesScript.RATING_GOOD
		and ToolRulesScript.surface_rating(roller, MansionLayoutScript.SURFACE_FLOOR)
		== ToolRulesScript.RATING_BAD
		and ToolRulesScript.surface_rating(roller, MansionLayoutScript.SURFACE_FURNITURE)
		== ToolRulesScript.RATING_NORMAL,
		"粘着ローラーはスーツが得意・床が不得意・家具はどちらでもない",
	)
	var vacuum: StringName = ToolCatalogScript.TOOL_VACUUM
	_check(
		ToolRulesScript.miss_ratio(vacuum, 1, MansionLayoutScript.SURFACE_FLOOR)
		< ToolRulesScript.miss_ratio(vacuum, 1, MansionLayoutScript.SURFACE_KNIT),
		"掃除機は床の方がニットより取りこぼしが少ない",
	)
	var level1: float = ToolRulesScript.miss_ratio(roller, 1, &"")
	_check(
		is_equal_approx(
			ToolRulesScript.miss_ratio(roller, 2, &""), level1 * ToolRulesScript.MISS_FACTOR_PER_LEVEL),
		"レベルが 1 上がると取りこぼしが 0.75 倍になる",
	)
	_check(
		is_equal_approx(ToolRulesScript.miss_ratio(roller, 0, &""), level1)
		and is_equal_approx(
			ToolRulesScript.miss_ratio(roller, 99, &""),
			ToolRulesScript.miss_ratio(roller, ToolRulesScript.MAX_TOOL_LEVEL, &"")
		),
		"範囲外のレベルは 1 と上限のレベルに丸める",
	)
	_check(
		is_equal_approx(
			ToolRulesScript.miss_ratio(
				ToolCatalogScript.TOOL_TWEEZERS,
				ToolRulesScript.MAX_TOOL_LEVEL,
				MansionLayoutScript.SURFACE_KNIT
			),
			ToolRulesScript.MIN_MISS_RATIO
		),
		"ピンセットを上限のレベルで得意なニットにかけても取りこぼしは下限 5% で止まる",
	)
	_check(
		is_equal_approx(ToolRulesScript.miss_ratio(ToolCatalogScript.TOOL_GLOW_LIGHT, 1, &""), 0.0)
		and is_equal_approx(ToolRulesScript.miss_ratio(ToolCatalogScript.TOOL_HAND, 1, &""), 0.0)
		and is_equal_approx(ToolRulesScript.miss_ratio(&"no_such_tool", 1, &""), 0.0),
		"毛を取らない道具 (手・ライト) と表に無い道具の取りこぼしは 0",
	)
	_check(
		ToolRulesScript.touchable_count(10, 4) == 4
		and ToolRulesScript.touchable_count(5, 60) == 4
		and ToolRulesScript.touchable_count(1, 60) == 0
		and ToolRulesScript.touchable_count(0, 60) == 0
		and ToolRulesScript.touchable_count(10, 0) == 0,
		"1 回で抽選するのは触れる上限までで、範囲の最後の 1 本は残す (範囲 1 本・0 本・上限 0 では抽選しない)",
	)
	_check(
		ToolRulesScript.is_missed(0.29, 0.3) and not ToolRulesScript.is_missed(0.3, 0.3)
		and not ToolRulesScript.is_missed(0.5, 0.3),
		"乱数が取りこぼしの割合より小さい時だけ、その毛が残る (同じ値は取れる)",
	)


## レベルを上げる値段・消耗品で使えるか・お金で買えるか・手の強化の値段が想定どおりで、上限で買えなくなるか
func _check_prices_and_consumables() -> void:
	var roller: StringName = ToolCatalogScript.TOOL_LINT_ROLLER
	_check(
		ToolRulesScript.level_up_price(roller, 1) == 150
		and ToolRulesScript.level_up_price(roller, 4) == 600
		and ToolRulesScript.level_up_price(roller, ToolRulesScript.MAX_TOOL_LEVEL) == -1
		and ToolRulesScript.level_up_price(roller, 0) == -1,
		"粘着ローラーのレベル上げは 1→2 が 150 円・4→5 が 600 円で、上限と 0 では上げられない",
	)
	_check(
		ToolRulesScript.level_up_price(ToolCatalogScript.TOOL_HAND, 1) == -1
		and ToolRulesScript.level_up_price(ToolCatalogScript.TOOL_BRUSH, 1) == -1
		and ToolRulesScript.level_up_price(&"no_such_tool", 1) == -1,
		"手・毛を取らない道具・表に無い道具はレベルを上げられない",
	)
	_check(
		not ToolRulesScript.can_use(roller, 0) and ToolRulesScript.can_use(roller, 1)
		and not ToolRulesScript.can_use(roller, -1),
		"粘着ローラーは紙が 0 枚 (以下) で使えず、1 枚あれば使える",
	)
	_check(
		ToolRulesScript.can_use(ToolCatalogScript.TOOL_TWEEZERS, 0)
		and not ToolRulesScript.can_use(&"no_such_tool", 5),
		"消耗品を使わない道具は消耗品 0 でも使え、表に無い道具は使えない",
	)
	_check(
		ToolRulesScript.can_afford(100, 100) and not ToolRulesScript.can_afford(99, 100)
		and ToolRulesScript.can_afford(0, 0) and not ToolRulesScript.can_afford(1000, -1),
		"所持金が値段以上なら買え、1 円でも足りなければ買えず、値段が負 (買えない物) は買えない",
	)
	_check(
		ToolRulesScript.hand_upgrade_price(0) == 40
		and ToolRulesScript.hand_upgrade_price(ToolRulesScript.MAX_HAND_UPGRADE_LEVEL - 1) == 360
		and ToolRulesScript.hand_upgrade_price(ToolRulesScript.MAX_HAND_UPGRADE_LEVEL) == -1
		and ToolRulesScript.hand_upgrade_price(-1) == -1,
		"手の強化は段 0→1 が 40 円・8→9 が 360 円で、上限の段 9 と負の段では買えない",
	)


## 毛のままの売値が色と珍しい毛で決まり、在庫を売った額は毛のままの物だけを数えるか
func _check_hair_prices() -> void:
	_check(
		EconomyRulesScript.hair_price(SurfaceHairScript.COLOR_WHITE, &"") == 1
		and EconomyRulesScript.hair_price(SurfaceHairScript.COLOR_CALICO, &"") == 2
		and EconomyRulesScript.hair_price(&"no_such_color", &"") == 1,
		"ふつうの毛は白・黒 1 円、三毛 2 円、表に無い色 1 円",
	)
	_check(
		EconomyRulesScript.hair_price(SurfaceHairScript.COLOR_WHITE, HandRulesScript.RARE_GOLDEN) == 300
		and EconomyRulesScript.hair_price(SurfaceHairScript.COLOR_WHITE, HandRulesScript.RARE_WHISKER)
		== 100
		and EconomyRulesScript.hair_price(SurfaceHairScript.COLOR_WHITE, &"no_such_rare") == 1,
		"珍しい毛は種類の値段 (金色 300 円・ひげ 100 円) で、表に無い種類は色の値段",
	)
	var stocks: Array[HairStock] = [
		make_stock(SurfaceHairScript.COLOR_WHITE, &"", HairStockScript.FORM_RAW, 10),
		make_stock(SurfaceHairScript.COLOR_CALICO, &"", HairStockScript.FORM_RAW, 3),
		make_stock(
			SurfaceHairScript.COLOR_BLACK, HandRulesScript.RARE_WHISKER, HairStockScript.FORM_RAW, 1
		),
		make_stock(SurfaceHairScript.COLOR_WHITE, &"", HairStockScript.FORM_FELT, 50),
		make_stock(SurfaceHairScript.COLOR_WHITE, &"", HairStockScript.FORM_RAW, -4),
		null,
	]
	_check(
		ProcessingRulesScript.stock_value(stocks) == 10 + 6 + 100 + 50 * 200,
		"在庫を売った額は毛のままの物と加工品 (白のフェルト 1 枚 200 円) を数え、負の本数・空の行は 0 円 (実際: %d)"
		% ProcessingRulesScript.stock_value(stocks),
	)


## きれいさ・機嫌の近づき方・掃除代・払う回数の計算が境界で想定どおりか
func _check_cleanliness_mood_and_fee() -> void:
	_check(
		is_equal_approx(EconomyRulesScript.cleanliness(10, 10), 0.0)
		and is_equal_approx(EconomyRulesScript.cleanliness(5, 10), 0.5)
		and is_equal_approx(EconomyRulesScript.cleanliness(0, 10), 1.0),
		"きれいさは最初と同じ本数で 0、半分で 0.5、0 本で 1",
	)
	_check(
		is_equal_approx(EconomyRulesScript.cleanliness(0, 0), 1.0)
		and is_equal_approx(EconomyRulesScript.cleanliness(3, 0), 0.0)
		and is_equal_approx(EconomyRulesScript.cleanliness(15, 10), 0.0)
		and is_equal_approx(EconomyRulesScript.cleanliness(-1, 10), 1.0),
		"最初から 0 本の部屋は 1 (毛が増えたら 0)、最初より増えた部屋は 0、負の残りは 0 本と同じ",
	)
	_check(
		is_equal_approx(EconomyRulesScript.next_mood(0.5, 1.0, 10.0), 0.6)
		and is_equal_approx(EconomyRulesScript.next_mood(0.5, 0.0, 10.0), 0.4)
		and is_equal_approx(EconomyRulesScript.next_mood(0.5, 1.0, 1000000.0), 1.0)
		and is_equal_approx(EconomyRulesScript.next_mood(0.5, 0.0, 1000000.0), 0.0),
		"機嫌は 1 秒に 0.01 ずつきれいさへ近づき、長い時間でも行き過ぎない",
	)
	_check(
		is_equal_approx(EconomyRulesScript.next_mood(0.5, 1.0, -10.0), 0.5)
		and is_equal_approx(EconomyRulesScript.next_mood(0.5, 3.0, 1000.0), 1.0),
		"負の時間では機嫌が変わらず、1 を超える目標は 1 に丸める",
	)
	_check(
		EconomyRulesScript.cleaning_fee(1.0) == 30 and EconomyRulesScript.cleaning_fee(0.5) == 15
		and EconomyRulesScript.cleaning_fee(0.0) == 0 and EconomyRulesScript.cleaning_fee(2.0) == 30
		and EconomyRulesScript.cleaning_fee(-1.0) == 0,
		"掃除代はご機嫌 (1.0) で 30 円、機嫌に比例し、0〜1 の外は丸める",
	)
	_check(
		EconomyRulesScript.payments_due(0.0, 59.9) == 0
		and EconomyRulesScript.payments_due(59.9, 60.0) == 1
		and EconomyRulesScript.payments_due(0.0, 180.0) == 3
		and EconomyRulesScript.payments_due(60.0, 60.0) == 0
		and EconomyRulesScript.payments_due(100.0, 50.0) == 0,
		"掃除代は 60 秒の区切りをまたぐたびに 1 回払い、時間が進まなければ払わない",
	)


## GameState で道具・レベル・消耗品・手の強化を買え、お金が足りない・持っている・上限では何も変わらないか
func _check_game_state_purchase() -> void:
	var state: Node = GameStateScript.new()
	state.initialize_from_storage(TEST_SAVE_PATH, PackedStringArray(["--hair-count=300"]))
	var roller: StringName = ToolCatalogScript.TOOL_LINT_ROLLER
	var notified: Array[int] = [0]
	state.state_changed.connect(func() -> void: notified[0] += 1)
	_check(
		state.get_money() == 0
		and not state.purchase(GameStateScript.PURCHASE_TOOL, roller)
		and state.find_owned_tool(roller) == null
		and state.get_money() == 0
		and notified[0] == 0,
		"はじめからの 0 円では粘着ローラーを買えず、持ち物・お金・通知が変わらない",
	)
	state.save_data.building_progress.money = 149
	_check(
		not state.purchase(GameStateScript.PURCHASE_TOOL, roller) and state.get_money() == 149,
		"値段 150 円に 1 円足りない時は買えない",
	)
	state.save_data.building_progress.money = 150
	var bought: bool = state.purchase(GameStateScript.PURCHASE_TOOL, roller)
	var owned: OwnedTool = state.find_owned_tool(roller)
	_check(
		bought and owned != null and owned.level == 1 and owned.consumable_count == 20
		and state.get_money() == 0 and notified[0] == 1,
		"ちょうど 150 円で粘着ローラーを買うと 0 円になり、レベル 1・紙 20 枚で持ち物に入り、1 回知らせる",
	)
	state.save_data.building_progress.money = 10000
	_check(
		not state.purchase(GameStateScript.PURCHASE_TOOL, roller)
		and not state.purchase(GameStateScript.PURCHASE_TOOL, ToolCatalogScript.TOOL_HAND)
		and not state.purchase(GameStateScript.PURCHASE_TOOL, &"no_such_tool")
		and state.save_data.building_progress.owned_tools.size() == 1
		and state.get_money() == 10000,
		"持っている道具・手・表に無い道具は買えず、お金が減らない",
	)
	_check(
		state.purchase(GameStateScript.PURCHASE_LEVEL_UP, roller) and owned.level == 2
		and state.get_money() == 10000 - 150,
		"レベル上げを買うとレベル 2 になり 150 円減る",
	)
	for _step: int in range(10):
		state.purchase(GameStateScript.PURCHASE_LEVEL_UP, roller)
	_check(
		owned.level == ToolRulesScript.MAX_TOOL_LEVEL
		and state.get_money() == 10000 - 150 - 300 - 450 - 600,
		"レベルは上限 5 で止まり、上限からは買えずお金が減らない (実際: Lv %d・%d 円)"
		% [owned.level, state.get_money()],
	)
	_check(
		not state.purchase(GameStateScript.PURCHASE_LEVEL_UP, ToolCatalogScript.TOOL_VACUUM)
		and not state.purchase(GameStateScript.PURCHASE_CONSUMABLE, ToolCatalogScript.TOOL_VACUUM),
		"持っていない道具はレベルを上げられず、消耗品も買えない",
	)
	state.save_data.building_progress.owned_tools.erase(owned)
	var money_unowned_roller: int = state.get_money()
	_check(
		not state.purchase(GameStateScript.PURCHASE_CONSUMABLE, roller)
		and state.get_money() == money_unowned_roller,
		"消耗品を使う道具 (粘着ローラー) でも、持っていなければ紙を買えず、お金が減らない",
	)
	state.save_data.building_progress.owned_tools.append(owned)
	state.purchase(GameStateScript.PURCHASE_TOOL, ToolCatalogScript.TOOL_TWEEZERS)
	var money_owned_tweezers: int = state.get_money()
	_check(
		not state.purchase(GameStateScript.PURCHASE_CONSUMABLE, ToolCatalogScript.TOOL_TWEEZERS)
		and state.get_money() == money_owned_tweezers,
		"持っていても消耗品を使わない道具 (ピンセット) は消耗品を買えず、お金が減らない",
	)
	var money_before_refill: int = state.get_money()
	owned.consumable_count = 0
	_check(
		state.purchase(GameStateScript.PURCHASE_CONSUMABLE, roller) and owned.consumable_count == 20
		and state.get_money() == money_before_refill - 10,
		"粘着ローラーの紙を買い足すと 20 枚増え 10 円減る",
	)
	state.save_data.building_progress.money = 0
	_check(
		not state.purchase(GameStateScript.PURCHASE_CONSUMABLE, roller) and owned.consumable_count == 20,
		"お金が足りない時は紙を買い足せない",
	)
	state.save_data.building_progress.money = 40
	_check(
		state.purchase(GameStateScript.PURCHASE_HAND_UPGRADE, HandRulesScript.UPGRADE_DEXTERITY)
		and state.get_hand_upgrade_level(HandRulesScript.UPGRADE_DEXTERITY) == 1
		and state.get_money() == 0
		and not state.purchase(GameStateScript.PURCHASE_HAND_UPGRADE, HandRulesScript.UPGRADE_DEXTERITY),
		"手の強化 (器用さ) を 40 円で 1 段上げ、0 円では次の段 (80 円) を買えない",
	)
	state.save_data.building_progress.money = 40
	_check(
		state.purchase(GameStateScript.PURCHASE_HAND_UPGRADE, HandRulesScript.UPGRADE_GRAB_COUNT)
		and state.get_hand_upgrade_level(HandRulesScript.UPGRADE_GRAB_COUNT) == 1
		and state.get_money() == 0,
		"手の強化 (一度につまめる本数) も 40 円で 1 段上がる",
	)
	state.save_data.building_progress.money = 1000
	_check(
		not state.purchase(GameStateScript.PURCHASE_HAND_UPGRADE, &"no_such_upgrade")
		and not state.purchase(&"no_such_kind", roller)
		and state.get_money() == 1000,
		"手の強化の種類でない id と、買う物の種類でない kind は買えない",
	)
	state.free()
	SaveStorageScript.delete_save_file(TEST_SAVE_PATH)


## 道具をかけると面の毛が減って毛のままの在庫に入り (珍しい毛は出ない)、紙を 1 枚使い、紙 0 枚では何も変わらず、
## 売ると在庫の毛のままの物が無くなってお金が増えるか
func _check_game_state_tool_sweep_and_sell() -> void:
	var state: Node = GameStateScript.new()
	state.initialize_from_storage(TEST_SAVE_PATH, PackedStringArray(["--hair-count=300"]))
	var roller: StringName = ToolCatalogScript.TOOL_LINT_ROLLER
	var surface: SurfaceHair = state.save_data.building_progress.surface_hairs[0]
	var color_id: StringName = _first_color(surface)
	var before_color: int = surface.count_for_color(color_id)
	_check(
		state.apply_tool_sweep(roller, {surface.surface_id: {color_id: 1}}) == -1
		and surface.count_for_color(color_id) == before_color,
		"持っていない道具はかけられず、毛が減らない",
	)
	state.save_data.building_progress.money = 150
	state.purchase(GameStateScript.PURCHASE_TOOL, roller)
	var owned: OwnedTool = state.find_owned_tool(roller)
	var notified: Array[int] = [0]
	state.state_changed.connect(func() -> void: notified[0] += 1)
	_check(
		state.apply_tool_sweep(roller, {&"no_such_surface": {color_id: 1}}) == -1
		and owned.consumable_count == 20 and notified[0] == 0,
		"無い面にはかけられず、紙も減らず、知らせない",
	)
	_check(
		state.apply_tool_sweep(roller, {surface.surface_id: {}}) == 0
		and owned.consumable_count == 19 and notified[0] == 1,
		"範囲に毛が無くても粘着ローラーをかけると紙を 1 枚使い、1 回知らせる",
	)
	owned.consumable_count = 20
	var removed: int = state.apply_tool_sweep(roller, {surface.surface_id: {color_id: 2}})
	_check(
		removed == 2 and surface.count_for_color(color_id) == before_color - 2
		and state.get_raw_hair_stock_count() == 2 and owned.consumable_count == 19
		and state.get_found_rare_hair_ids().is_empty() and notified[0] == 2,
		"粘着ローラーで 2 本取ると面が 2 減り、在庫に 2 本入り、紙を 1 枚使い、図鑑は変わらない",
	)
	var huge: int = state.apply_tool_sweep(roller, {surface.surface_id: {color_id: 1000000}})
	_check(
		huge == before_color - 2 and surface.count_for_color(color_id) == 0,
		"面に残っている本数より多くは取れない (実際: %d 本)" % huge,
	)
	owned.consumable_count = 0
	var stock_before: int = state.get_raw_hair_stock_count()
	_check(
		state.apply_tool_sweep(roller, {surface.surface_id: {color_id: 1}}) == -1
		and owned.consumable_count == 0 and state.get_raw_hair_stock_count() == stock_before,
		"紙が 0 枚の粘着ローラーはかけられず、紙・在庫が変わらない",
	)
	state.pluck_hair(
		state.save_data.building_progress.surface_hairs[1].surface_id,
		_first_color(state.save_data.building_progress.surface_hairs[1]),
		HandRulesScript.RARE_GOLDEN,
	)
	var felt: HairStock = make_stock(color_id, &"", HairStockScript.FORM_FELT, 5)
	state.save_data.building_progress.hair_stocks.append(felt)
	var expected: int = ProcessingRulesScript.stock_value(
		state.save_data.building_progress.hair_stocks
	)
	var earned: int = state.sell_hair_stocks()
	_check(
		earned == expected
		and earned >= stock_before + 300 + 5 * ProcessingRulesScript.unit_price(
			HairStockScript.FORM_FELT, color_id, &""
		)
		and state.get_money() == earned
		and state.get_raw_hair_stock_count() == 0
		and state.save_data.building_progress.hair_stocks.is_empty(),
		"売ると毛のままの物 (珍しい毛 300 円を含む) と加工品 (フェルト 5 枚) が無くなり、売値の合計だけお金が増える (%d 円)"
		% earned,
	)
	_check(
		state.sell_hair_stocks() == 0 and state.get_money() == earned,
		"売る毛が無い時はお金が変わらない",
	)
	var tweezers: StringName = ToolCatalogScript.TOOL_TWEEZERS
	state.purchase(GameStateScript.PURCHASE_TOOL, tweezers)
	var other: SurfaceHair = state.save_data.building_progress.surface_hairs[1]
	var notified_before_tweezers: int = notified[0]
	_check(
		state.apply_tool_sweep(tweezers, {other.surface_id: {}}) == 0
		and notified[0] == notified_before_tweezers,
		"消耗品を使わない道具 (ピンセット) で 1 本も取れない時は、何も変わらず知らせない",
	)
	_check(
		state.apply_tool_sweep(tweezers, {other.surface_id: {_first_color(other): 1}}) == 1
		and notified[0] == notified_before_tweezers + 1,
		"消耗品を使わない道具でも、毛が取れた時は 1 回知らせる",
	)
	state.free()
	SaveStorageScript.delete_save_file(TEST_SAVE_PATH)


## 時間を進めると機嫌が部屋のきれいさへ近づき、60 秒ごとに機嫌に比例した掃除代が入るか
func _check_game_state_advance_time() -> void:
	var state: Node = GameStateScript.new()
	state.initialize_from_storage(TEST_SAVE_PATH, PackedStringArray(["--hair-count=300"]))
	var rooms: Array[MansionLayout.RoomDef] = state.current_layout.rooms
	var clean_room: StringName = rooms[0].room_id
	var start_status: Dictionary = state.get_room_status(clean_room)
	_check(
		int(start_status["hair_count"]) > 0
		and is_equal_approx(float(start_status["cleanliness"]), 0.0)
		and is_equal_approx(float(start_status["mood"]), MansionBuilderScript.INITIAL_RESIDENT_MOOD)
		and int(start_status["cleaning_fee"]) == 15,
		"はじめの部屋はきれいさ 0・機嫌 0.5・掃除代 15 円",
	)
	for surface_def: MansionLayout.SurfaceDef in state.current_layout.surfaces:
		if surface_def.room_id == clean_room:
			state.save_data.building_progress.find_surface_hair(surface_def.surface_id).hair_counts.clear()
	_check(
		is_equal_approx(float(state.get_room_status(clean_room)["cleanliness"]), 1.0),
		"部屋の毛を全部取るときれいさが 1 になる",
	)
	var dirty_room: StringName = &""
	var clean_room_count: int = 0
	for room: MansionLayout.RoomDef in rooms:
		var status: Dictionary = state.get_room_status(room.room_id)
		if is_equal_approx(float(status["cleanliness"]), 1.0):
			clean_room_count += 1
		elif dirty_room == &"" and is_equal_approx(float(status["cleanliness"]), 0.0):
			dirty_room = room.room_id
	_check(dirty_room != &"", "毛が最初のまま残る部屋がある")
	var earned_first: int = state.advance_time(30.0)
	_check(
		earned_first == 0 and state.get_money() == 0
		and is_equal_approx(float(state.get_room_status(clean_room)["mood"]), 0.8)
		and is_equal_approx(float(state.get_room_status(dirty_room)["mood"]), 0.2)
		and is_equal_approx(state.save_data.building_progress.elapsed_seconds, 30.0),
		"30 秒進めると、きれいな部屋の機嫌は 0.8、毛が残る部屋は 0.2 になり、掃除代はまだ入らない",
	)
	var expected_fee: int = 0
	for room: MansionLayout.RoomDef in rooms:
		expected_fee += EconomyRulesScript.cleaning_fee(
			EconomyRulesScript.next_mood(
				float(state.get_room_status(room.room_id)["mood"]),
				float(state.get_room_status(room.room_id)["cleanliness"]),
				30.0
			)
		)
	var earned_second: int = state.advance_time(30.0)
	_check(
		earned_second == expected_fee and earned_second > 0 and state.get_money() == earned_second,
		"60 秒の区切りで、部屋ごとの機嫌に比例した掃除代の合計が入る (実際: %d 円 / 期待: %d 円)"
		% [earned_second, expected_fee],
	)
	var earned_long: int = state.advance_time(600.0)
	_check(
		is_equal_approx(float(state.get_room_status(clean_room)["mood"]), 1.0)
		and is_equal_approx(float(state.get_room_status(dirty_room)["mood"]), 0.0)
		and earned_long == 10 * EconomyRulesScript.BASE_CLEANING_FEE * clean_room_count,
		"長く進めると機嫌はきれいさで止まり (1.0 と 0.0)、10 回分の掃除代はきれいな部屋だけの 30 円 × 10 (実際: %d 円)"
		% earned_long,
	)
	_check(
		state.advance_time(-5.0) == 0
		and is_equal_approx(state.save_data.building_progress.elapsed_seconds, 660.0),
		"負の時間を渡しても時間は戻らず、掃除代も入らない",
	)
	state.free()
	SaveStorageScript.delete_save_file(TEST_SAVE_PATH)

	var empty_mansion: Node = GameStateScript.new()
	empty_mansion.initialize_from_storage(TEST_SAVE_PATH, PackedStringArray(["--hair-count=0"]))
	var empty_status: Dictionary = empty_mansion.get_room_status(
		empty_mansion.current_layout.rooms[0].room_id
	)
	_check(
		int(empty_status["hair_count"]) == 0 and is_equal_approx(float(empty_status["cleanliness"]), 1.0),
		"毛が 0 本の屋敷の部屋はきれいさ 1 (0 で割らない)",
	)
	empty_mansion.free()
	SaveStorageScript.delete_save_file(TEST_SAVE_PATH)

	var unloaded: Node = GameStateScript.new()
	_check(
		unloaded.advance_time(100.0) == 0
		and not unloaded.purchase(GameStateScript.PURCHASE_TOOL, ToolCatalogScript.TOOL_TWEEZERS)
		and unloaded.sell_hair_stocks() == 0
		and int(unloaded.haul_with_dump_truck()["earned"]) == 0
		and unloaded.apply_tool_sweep(ToolCatalogScript.TOOL_TWEEZERS, {&"any": {}}) == -1,
		"保存データを読む前の GameState では時間・買う・売る・運び出す・道具をかける入口が何も変えない",
	)
	unloaded.free()


## 道具を買う画面が、お金・持ち物に合わせてボタンを押せる / 押せないにし、説明に得意な表面・消耗品・探し物を傷めるかを出すか
func _check_tool_shop_panel() -> void:
	var state: Node = GameStateScript.new()
	state.initialize_from_storage(TEST_SAVE_PATH, PackedStringArray(["--hair-count=300"]))
	var panel: PanelContainer = ToolShopPanelScript.new()
	panel.refresh(state, false)
	var roller: StringName = ToolCatalogScript.TOOL_LINT_ROLLER
	_check(
		panel.get_tool_button(roller).disabled
		and panel.get_tool_button(roller).text == "買う (150 円)"
		and not panel.get_refill_button(roller).visible
		and panel.get_sell_button().disabled,
		"0 円では道具を買えず、持っていない粘着ローラーの紙は出さず、買取業者から離れていると売れない",
	)
	state.save_data.building_progress.money = 150
	state.purchase(GameStateScript.PURCHASE_TOOL, roller)
	state.pluck_hair(
		state.save_data.building_progress.surface_hairs[0].surface_id,
		_first_color(state.save_data.building_progress.surface_hairs[0]),
	)
	panel.refresh(state, true)
	_check(
		panel.get_tool_button(roller).text == "レベルを上げる (150 円)"
		and panel.get_refill_button(roller).visible
		and not panel.get_sell_button().disabled,
		"買った道具はレベルを上げるボタンになり、紙の買い足しが出て、買取業者の近くで在庫があれば売れる",
	)
	state.save_data.building_progress.money = 100
	state.purchase(GameStateScript.PURCHASE_TOOL, ToolCatalogScript.TOOL_BRUSH)
	panel.refresh(state, true)
	_check(
		panel.get_tool_button(ToolCatalogScript.TOOL_BRUSH).text == "持っている"
		and panel.get_tool_button(ToolCatalogScript.TOOL_BRUSH).disabled,
		"レベルの無い道具 (ブラシ) は買った後「持っている」と出て押せない (実際: %s)"
		% panel.get_tool_button(ToolCatalogScript.TOOL_BRUSH).text,
	)
	var roller_text: String = ToolShopPanelScript.describe_tool(roller, state.find_owned_tool(roller))
	var vacuum_text: String = ToolShopPanelScript.describe_tool(ToolCatalogScript.TOOL_VACUUM, null)
	_check(
		ToolShopPanelScript.describe_tool(ToolCatalogScript.TOOL_HAND, null) == "手",
		"最初から持っている手の説明には「未購入」を出さない (実際: %s)"
		% ToolShopPanelScript.describe_tool(ToolCatalogScript.TOOL_HAND, null),
	)
	_check(
		roller_text.contains("Lv 1") and roller_text.contains("得意: スーツ")
		and roller_text.contains("不得意: 床") and roller_text.contains("紙: 20 枚")
		and vacuum_text.contains("未購入") and vacuum_text.contains("探し物を傷める"),
		"道具の説明にレベル・得意 / 不得意な表面・紙の残り・探し物を傷めるかが出る (実際: %s / %s)"
		% [roller_text, vacuum_text],
	)
	_check_tool_shop_limits(state, panel)
	panel.free()
	state.free()
	SaveStorageScript.delete_save_file(TEST_SAVE_PATH)


## 道具を買う画面の手の強化のボタン (文言・押せるか・押した時の操作・上限)、レベル上限の道具、
## 買取業者の近くでも在庫が無い時の売るボタンを検証する
func _check_tool_shop_limits(state: Node, panel: PanelContainer) -> void:
	var dexterity: StringName = HandRulesScript.UPGRADE_DEXTERITY
	var requested: Array = []
	panel.purchase_requested.connect(
		func(kind: StringName, item_id: StringName) -> void: requested.append([kind, item_id])
	)
	state.save_data.building_progress.money = 39
	panel.refresh(state, true)
	_check(
		panel.get_hand_upgrade_button(dexterity).text.contains("段 0 → 1 (40 円)")
		and panel.get_hand_upgrade_button(dexterity).disabled,
		"手の強化のボタンは段と値段を出し、1 円足りないと押せない (実際: %s)"
		% panel.get_hand_upgrade_button(dexterity).text,
	)
	state.save_data.building_progress.money = 40
	panel.refresh(state, true)
	panel.get_hand_upgrade_button(dexterity).pressed.emit()
	_check(
		not panel.get_hand_upgrade_button(dexterity).disabled
		and requested == [[GameStateScript.PURCHASE_HAND_UPGRADE, dexterity]],
		"40 円あれば手の強化のボタンが押せ、押すと手の強化を買う操作を出す (実際: %s)" % str(requested),
	)
	state.save_data.hand_upgrade_levels[dexterity] = ToolRulesScript.MAX_HAND_UPGRADE_LEVEL
	state.find_owned_tool(ToolCatalogScript.TOOL_LINT_ROLLER).level = ToolRulesScript.MAX_TOOL_LEVEL
	state.save_data.building_progress.money = 100000
	panel.refresh(state, true)
	_check(
		panel.get_hand_upgrade_button(dexterity).text.ends_with("段 9 (上限)")
		and panel.get_hand_upgrade_button(dexterity).disabled
		and panel.get_tool_button(ToolCatalogScript.TOOL_LINT_ROLLER).text == "レベル上限"
		and panel.get_tool_button(ToolCatalogScript.TOOL_LINT_ROLLER).disabled,
		"上限の段の手の強化と上限のレベルの道具は、お金があっても押せず「上限」と出る",
	)
	state.sell_hair_stocks()
	panel.refresh(state, true)
	_check(
		panel.get_sell_button().disabled,
		"買取業者の近くでも、売る毛が無い時は売るボタンが押せない",
	)


## 在庫 1 件を作る (大型の道具の検証 scripts/dev/selfcheck_big_tools.gd も使う)
static func make_stock(
	color_id: StringName, rare_id: StringName, form: StringName, count: int
) -> HairStock:
	var stock: HairStock = HairStockScript.new()
	stock.hair_color = color_id
	stock.rare_hair_id = rare_id
	stock.form = form
	stock.count = count
	return stock


## 面に 1 本以上残っている最初の色を返す (無ければ白)
func _first_color(surface: SurfaceHair) -> StringName:
	for candidate: StringName in SurfaceHairScript.STANDARD_COLORS:
		if surface.count_for_color(candidate) > 0:
			return candidate
	return SurfaceHairScript.COLOR_WHITE

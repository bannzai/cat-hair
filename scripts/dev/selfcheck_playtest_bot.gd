extends RefCounted
## 自動テストプレイの bot の方針 (scripts/dev/playtest_bot_policy.gd) の検証スイート (scripts/dev/selfcheck.gd から呼ぶ)。
## ゲームの様子 (snapshot) を作って渡し、次の 1 手 (毛を取る部屋と道具・買う物・売る・ブラシ・待つ) を確かめる。

## 検証する方針
const PolicyScript := preload("res://scripts/dev/playtest_bot_policy.gd")
## 道具の定義
const ToolCatalogScript := preload("res://scripts/tools/tool_catalog.gd")
## 手で毛を取る時のルールの計算 (手の強化の id)
const HandRulesScript := preload("res://scripts/hand/hand_rules.gd")
## 掃除ロボットの値段
const RobotRulesScript := preload("res://scripts/automation/robot_rules.gd")
## 掃除代・機嫌の計算 (ご機嫌の線)
const EconomyRulesScript := preload("res://scripts/economy/economy_rules.gd")
## 屋敷に入った時の住人の機嫌
const MansionBuilderScript := preload("res://scripts/mansion/mansion_builder.gd")
## 状態管理 autoload スクリプト (買う物の種類の定数を使う)
const GameStateScript := preload("res://scripts/state/game_state.gd")
## 手に持って使う道具のルールの計算 (レベルの上限)
const ToolRulesScript := preload("res://scripts/tools/tool_rules.gd")
## 大型の道具 (アンドロイドが働く間隔)
const BigToolSiteScript := preload("res://scripts/tools/big_tool_site.gd")
## 検証の部屋 1 つの毛の本数 (屋敷の既定 12,000 本を 4 部屋に分けた本数)
const ROOM_HAIRS: int = 3000
## 検証の部屋 1 つの毛の付く表面の面積 (m2。既定の 6 m 四方の部屋の床)
const ROOM_AREA_M2: float = 36.0
## 元を取るまでの秒を比べる時に、浮動小数の誤差で同じ値の候補を「もっと短い」と数えない幅 (秒)
const SCORE_TOLERANCE: float = 0.001
## お金が足りないことで選び方が変わらないよう持たせる所持金。いちばん高いアンドロイドの値段より十分多い
const PLENTY_OF_MONEY: int = 1000000
## 速さの伸びる物を買い続ける検証の回数の上限。買える物 (道具・レベル上げ・手の強化・掃除ロボット) の総数より
## 十分多く、買い終えずに止まった時もループを終える
const MAX_PURCHASE_ROUNDS: int = 200

## 検証結果を記録する selfcheck の SceneTree 参照
var _checker: SceneTree = null


## bot の方針の検証をすべて実行する
static func run_all(checker: SceneTree) -> void:
	var suite: RefCounted = load("res://scripts/dev/selfcheck_playtest_bot.gd").new()
	suite._checker = checker
	suite._check_happy_mood_line()
	suite._check_cleans_dirtiest_room_by_hand()
	suite._check_waits_when_no_hair()
	suite._check_buys_affordable_best_purchase()
	suite._check_sells_to_afford_purchase()
	suite._check_bought_tool_beats_hand()
	suite._check_uses_fastest_owned_tool()
	suite._check_refills_empty_tool()
	suite._check_brushes_ready_cat()
	suite._check_robot_raises_rate()
	suite._check_after_cleaning_tools()
	suite._check_room_tool_needs_covered_hairs()
	suite._check_purchase_score_counts_saving_time()
	suite._check_brush_needs_brush_and_speed()
	suite._check_purchase_candidates()
	suite._check_buys_at_exact_price()
	suite._check_action_seconds()
	suite._check_total_rate_parts()
	suite._check_room_tool_cap()
	suite._check_candidates_at_max_level()


## 手しか持たず、お金も在庫も無い屋敷の様子 (部屋 a・b。b の方がきれいさが低い)
static func _base_snapshot() -> Dictionary:
	return {
		"money": 0,
		"stock_value": 0,
		"owned": {},
		"hand_levels": {HandRulesScript.UPGRADE_DEXTERITY: 0, HandRulesScript.UPGRADE_GRAB_COUNT: 0},
		"robots": 0,
		"rooms": [_room(&"a", 0.6), _room(&"b", 0.2)],
		"ready_cat_ids": [],
	}


## きれいさ cleanliness の検証の部屋 room_id (毛は ROOM_HAIRS 本、機嫌は屋敷に入った時の値。
## 部屋ごとにかける道具がかかる表面は無い)
static func _room(room_id: StringName, cleanliness: float) -> Dictionary:
	return {
		"room_id": room_id,
		"hair_count": ROOM_HAIRS,
		"cleanliness": cleanliness,
		"mood": MansionBuilderScript.INITIAL_RESIDENT_MOOD,
		"area_m2": ROOM_AREA_M2,
		"covered": {},
	}


## snapshot に道具 tool_id を持たせる (レベル 1、消耗品は買った時の数)
static func _with_tool(snapshot: Dictionary, tool_id: StringName) -> Dictionary:
	var after: Dictionary = snapshot.duplicate(true)
	after["owned"][tool_id] = {
		"level": 1,
		"consumable_count": int(ToolCatalogScript.find_tool(tool_id)["initial_consumables"]),
	}
	return after


## ご機嫌の線は屋敷に入った時の機嫌より上で、1 より下 (入った直後に全員ご機嫌にならず、掃除すれば届く)
func _check_happy_mood_line() -> void:
	_checker._check(
		not EconomyRulesScript.is_happy(MansionBuilderScript.INITIAL_RESIDENT_MOOD)
		and EconomyRulesScript.is_happy(1.0)
		and EconomyRulesScript.is_happy(EconomyRulesScript.HAPPY_MOOD)
		and not EconomyRulesScript.is_happy(EconomyRulesScript.HAPPY_MOOD - 0.001),
		"ご機嫌の線 HAPPY_MOOD (%.2f) は屋敷に入った時の機嫌 (%.2f) より上で、1 以下"
		% [EconomyRulesScript.HAPPY_MOOD, MansionBuilderScript.INITIAL_RESIDENT_MOOD]
	)


## 手しか持たずお金も在庫も無い時は、きれいさがいちばん低い部屋の毛を手で取る
func _check_cleans_dirtiest_room_by_hand() -> void:
	var action: Dictionary = PolicyScript.choose_action(_base_snapshot())
	_checker._check(
		action.get("kind") == PolicyScript.ACTION_CLEAN
		and action.get("tool_id") == ToolCatalogScript.TOOL_HAND
		and action.get("room_id") == &"b",
		"お金も道具も無い時は、きれいさの低い部屋 b の毛を手で取る (実際: %s)" % str(action)
	)
	var snapshot: Dictionary = _base_snapshot()
	snapshot["rooms"][1]["hair_count"] = 0
	var skipped: Dictionary = PolicyScript.choose_action(snapshot)
	_checker._check(
		skipped.get("room_id") == &"a",
		"きれいさが低くても毛が残っていない部屋は飛ばし、毛の残る部屋 a を取る (実際: %s)" % str(skipped)
	)


## どの部屋にも毛が残っておらず、買える物も無い時は待つ
func _check_waits_when_no_hair() -> void:
	var snapshot: Dictionary = _base_snapshot()
	for room: Dictionary in snapshot["rooms"]:
		room["hair_count"] = 0
	var action: Dictionary = PolicyScript.choose_action(snapshot)
	_checker._check(
		action.get("kind") == PolicyScript.ACTION_WAIT,
		"毛がどこにも残っていない時は待つ (実際: %s)" % str(action)
	)


## お金が足りる時は、貯めて買って元を取るまでの秒がいちばん短い物を買う。最初は安い道具が高い道具より先に来る
func _check_buys_affordable_best_purchase() -> void:
	var snapshot: Dictionary = _base_snapshot()
	snapshot["money"] = PLENTY_OF_MONEY
	var best: Dictionary = PolicyScript.best_purchase(snapshot)
	var base_rate: float = PolicyScript.total_rate(snapshot)
	var best_is_min: bool = not best.is_empty()
	for candidate: Dictionary in PolicyScript.purchase_candidates(snapshot):
		var gain: float = (
			PolicyScript.total_rate(PolicyScript.apply_purchase(snapshot, candidate)) - base_rate
		)
		if (
			gain > 0.0
			and PolicyScript.purchase_score_seconds(int(candidate["price"]), base_rate, gain)
			< float(best.get("score_seconds", 0.0)) - SCORE_TOLERANCE
		):
			best_is_min = false
	_checker._check(
		best_is_min, "選んだ物 %s は、候補のうち貯めて元を取るまでの秒がいちばん短い" % str(best)
	)
	var truck_price: int = int(
		ToolCatalogScript.find_tool(ToolCatalogScript.TOOL_SUCTION_TRUCK)["price"]
	)
	_checker._check(
		int(best.get("price", 0)) < truck_price,
		"手しか持たない時に最初に選ぶ物 %s は、吸引車 (%d 円) より安い" % [str(best), truck_price]
	)
	# 期待値をテスト対象の計算で出し直さずに固定する: 手しか持たない 2 部屋 (毛 3,000 本・36 m2) では、
	# 範囲が広く 1 回で触れる本数の多いガムテープ (300 円) の伸びが、ピンセット (250 円) と手の強化 (300 円) より大きい
	_checker._check(
		best.get("item_id") == ToolCatalogScript.TOOL_PACKING_TAPE
		and best.get("purchase_kind") == GameStateScript.PURCHASE_TOOL,
		"手しか持たない時に最初に選ぶ物はガムテープ (実際: %s)" % str(best)
	)
	var action: Dictionary = PolicyScript.choose_action(snapshot)
	_checker._check(
		action.get("kind") in [PolicyScript.ACTION_BUY, PolicyScript.ACTION_BUY_ROBOT]
		and action.get("item_id", &"") == best.get("item_id"),
		"お金が足りる時は選んだ物 %s を買う (実際: %s)" % [best.get("item_id"), str(action)]
	)


## お金だけでは足りず、在庫を売れば足りる時は売りに行く (ダンプカーを持っていれば呼ぶ)。売っても足りなければ毛を取る
func _check_sells_to_afford_purchase() -> void:
	var snapshot: Dictionary = _base_snapshot()
	var price: int = int(PolicyScript.best_purchase(snapshot)["price"])
	snapshot["money"] = price - 1
	snapshot["stock_value"] = 1
	var sell: Dictionary = PolicyScript.choose_action(snapshot)
	_checker._check(
		sell.get("kind") == PolicyScript.ACTION_SELL,
		"在庫を売れば %d 円に届く時は買取業者へ売りに行く (実際: %s)" % [price, str(sell)]
	)
	var hauled: Dictionary = PolicyScript.choose_action(
		_with_tool(snapshot, ToolCatalogScript.TOOL_DUMP_TRUCK)
	)
	_checker._check(
		hauled.get("kind") == PolicyScript.ACTION_HAUL,
		"ダンプカーを持っていれば買取業者へ行かずにダンプカーで売る (実際: %s)" % str(hauled)
	)
	snapshot["stock_value"] = 0
	var short: Dictionary = PolicyScript.choose_action(snapshot)
	_checker._check(
		short.get("kind") == PolicyScript.ACTION_CLEAN,
		"売っても足りない時は毛を取り続ける (実際: %s)" % str(short)
	)


## 最初に買う道具は手より速く毛を取れる (買っても速くならない道具は、bot が買う理由が無い)
func _check_bought_tool_beats_hand() -> void:
	var snapshot: Dictionary = _base_snapshot()
	var room: Dictionary = snapshot["rooms"][1]
	var hand_rate: float = PolicyScript.tool_rate(snapshot, ToolCatalogScript.TOOL_HAND, room)
	for tool_id: StringName in [
		ToolCatalogScript.TOOL_TWEEZERS,
		ToolCatalogScript.TOOL_PACKING_TAPE,
		ToolCatalogScript.TOOL_VACUUM,
	]:
		var rate: float = PolicyScript.tool_rate(_with_tool(snapshot, tool_id), tool_id, room)
		_checker._check(
			rate > hand_rate,
			"%s で取る速さ (%.2f 本 / 秒) は手 (%.2f 本 / 秒) より速い" % [tool_id, rate, hand_rate]
		)


## 道具をいくつか持っている時は、いちばん速く取れる道具で毛を取る
func _check_uses_fastest_owned_tool() -> void:
	var action: Dictionary = PolicyScript.choose_action(
		_with_tool(
			_with_tool(_base_snapshot(), ToolCatalogScript.TOOL_TWEEZERS),
			ToolCatalogScript.TOOL_VACUUM
		)
	)
	_checker._check(
		action.get("kind") == PolicyScript.ACTION_CLEAN
		and action.get("tool_id") == ToolCatalogScript.TOOL_VACUUM,
		"ピンセットと掃除機を持っている時は速い掃除機で取る (実際: %s)" % str(action)
	)


## いちばん速い道具の消耗品が尽きた時、買い足すお金があれば買い足し、無ければ次に速い道具で取る
func _check_refills_empty_tool() -> void:
	var snapshot: Dictionary = _with_tool(
		_with_tool(_base_snapshot(), ToolCatalogScript.TOOL_TWEEZERS), ToolCatalogScript.TOOL_VACUUM
	)
	snapshot["owned"][ToolCatalogScript.TOOL_VACUUM]["consumable_count"] = 0
	var broke: Dictionary = PolicyScript.choose_action(snapshot)
	_checker._check(
		broke.get("kind") == PolicyScript.ACTION_CLEAN
		and broke.get("tool_id") == ToolCatalogScript.TOOL_TWEEZERS,
		"掃除機のパックが尽きて買い足すお金も無い時はピンセットで取る (実際: %s)" % str(broke)
	)
	snapshot["money"] = int(ToolCatalogScript.find_tool(ToolCatalogScript.TOOL_VACUUM)["refill_price"])
	var refill: Dictionary = PolicyScript.choose_action(snapshot)
	_checker._check(
		refill.get("kind") == PolicyScript.ACTION_BUY
		and refill.get("purchase_kind") == GameStateScript.PURCHASE_CONSUMABLE
		and refill.get("item_id") == ToolCatalogScript.TOOL_VACUUM,
		"掃除機のパックを買い足すお金があれば買い足す (実際: %s)" % str(refill)
	)


## ブラシを持ち、休んでいない猫がいて、ブラシの方が速く取れる時は猫にブラシをかける。猫が休んでいれば毛を取る
func _check_brushes_ready_cat() -> void:
	var snapshot: Dictionary = _with_tool(_base_snapshot(), ToolCatalogScript.TOOL_BRUSH)
	snapshot["ready_cat_ids"] = [&"cat_0"]
	var hand_rate: float = PolicyScript.tool_rate(
		snapshot, ToolCatalogScript.TOOL_HAND, snapshot["rooms"][1]
	)
	var action: Dictionary = PolicyScript.choose_action(snapshot)
	_checker._check(
		action.get("kind") == PolicyScript.ACTION_BRUSH
		and action.get("cat_id") == &"cat_0"
		and PolicyScript.brush_rate() > hand_rate,
		"手しか持たない時はブラシ (%.2f 本 / 秒) の方が手 (%.2f 本 / 秒) より速く、休んでいない猫にブラシをかける (実際: %s)"
		% [PolicyScript.brush_rate(), hand_rate, str(action)]
	)
	snapshot["ready_cat_ids"] = []
	var resting: Dictionary = PolicyScript.choose_action(snapshot)
	_checker._check(
		resting.get("kind") == PolicyScript.ACTION_CLEAN,
		"猫が休んでいる時は毛を取る (実際: %s)" % str(resting)
	)


## 掃除ロボットを置くと屋敷全体で毛を取る速さが上がり、上限の台数まで置いたら候補から外れる
func _check_robot_raises_rate() -> void:
	var snapshot: Dictionary = _base_snapshot()
	_checker._check(
		(
			PolicyScript.total_rate(
				PolicyScript.apply_purchase(
					snapshot,
					{
						"purchase_kind": PolicyScript.PURCHASE_ROBOT,
						"item_id": &"",
						"price": RobotRulesScript.ROBOT_PRICE,
					}
				)
			)
			> PolicyScript.total_rate(snapshot)
		),
		"掃除ロボットを置くと屋敷全体の速さが上がる"
	)
	snapshot["robots"] = RobotRulesScript.MAX_ROBOTS
	var has_robot: bool = false
	for candidate: Dictionary in PolicyScript.purchase_candidates(snapshot):
		has_robot = has_robot or candidate["purchase_kind"] == PolicyScript.PURCHASE_ROBOT
	_checker._check(not has_robot, "上限の台数まで置いたら掃除ロボットは候補から外れる")


## 速さが伸びる物を買い終えたら、加工機・ダンプカーを 1 つずつ順に買う
func _check_after_cleaning_tools() -> void:
	var snapshot: Dictionary = _base_snapshot()
	snapshot["money"] = PLENTY_OF_MONEY
	for _round: int in range(MAX_PURCHASE_ROUNDS):
		var purchase: Dictionary = PolicyScript.best_purchase(snapshot)
		if purchase.is_empty() or float(purchase["gain"]) <= 0.0:
			break
		snapshot = PolicyScript.apply_purchase(snapshot, purchase)
	var first: Dictionary = PolicyScript.best_purchase(snapshot)
	_checker._check(
		first.get("item_id") == ToolCatalogScript.TOOL_HAIR_PROCESSOR,
		"速さの伸びる物を買い終えたら加工機を買う (実際: %s)" % str(first)
	)
	var second: Dictionary = PolicyScript.best_purchase(PolicyScript.apply_purchase(snapshot, first))
	_checker._check(
		second.get("item_id") == ToolCatalogScript.TOOL_DUMP_TRUCK,
		"加工機の次はダンプカーを買う (実際: %s)" % str(second)
	)


## 粘着シートを持っていても、きれいさの低い部屋のシートがかかる表面 (床とカーペット) に毛が無ければ
## シートを使わず手で取る。かかる表面に毛があればシートを使う (部屋の毛の総数で見積もると、
## かかる表面に毛の無い部屋でシートを無駄に使い続ける)
func _check_room_tool_needs_covered_hairs() -> void:
	var snapshot: Dictionary = _with_tool(_base_snapshot(), ToolCatalogScript.TOOL_ADHESIVE_SHEET)
	snapshot["rooms"][1]["covered"] = {
		ToolCatalogScript.TOOL_ADHESIVE_SHEET: {"hairs": 0, "surfaces": 1}
	}
	var empty: Dictionary = PolicyScript.choose_action(snapshot)
	_checker._check(
		empty.get("kind") == PolicyScript.ACTION_CLEAN
		and empty.get("tool_id") == ToolCatalogScript.TOOL_HAND,
		"シートのかかる表面に毛が無い部屋では手で取る (実際: %s)" % str(empty)
	)
	snapshot["rooms"][1]["covered"] = {
		ToolCatalogScript.TOOL_ADHESIVE_SHEET: {"hairs": ROOM_HAIRS, "surfaces": 1}
	}
	var covered: Dictionary = PolicyScript.choose_action(snapshot)
	_checker._check(
		covered.get("kind") == PolicyScript.ACTION_CLEAN
		and covered.get("tool_id") == ToolCatalogScript.TOOL_ADHESIVE_SHEET
		and covered.get("room_id") == &"b",
		"シートのかかる表面に毛がある部屋 b ではシートを使う (実際: %s)" % str(covered)
	)


## 買う物の点数は「貯める秒 (値段 ÷ 今の速さ) + 元を取る秒 (値段 ÷ 伸び)」で、1 円あたりの伸びが大きくても
## 今の稼ぎで貯めるのに長くかかる高い物より、安い物を先に選ぶ
func _check_purchase_score_counts_saving_time() -> void:
	_checker._check(
		is_equal_approx(PolicyScript.purchase_score_seconds(100, 2.0, 4.0), 75.0)
		and is_equal_approx(PolicyScript.purchase_score_seconds(100, 0.0, 4.0), 100000.0 + 25.0),
		"値段 100 円・速さ 2 本 / 秒・伸び 4 本 / 秒の点数は 50 + 25 = 75 秒、速さ 0 は下限 0.001 で割る (実際: %s / %s)"
		% [
			PolicyScript.purchase_score_seconds(100, 2.0, 4.0),
			PolicyScript.purchase_score_seconds(100, 0.0, 4.0),
		]
	)
	_checker._check(
		(
			PolicyScript.purchase_score_seconds(100, 1.0, 1.0)
			< PolicyScript.purchase_score_seconds(1000, 1.0, 20.0)
		),
		"1 円あたりの伸びが 2 倍の 1000 円の物より、今の速さ 1 本 / 秒で早く貯まる 100 円の物の点数が小さい"
	)


## ブラシをかけるのは、ブラシを持ち、休んでいない猫がいて、ブラシの方が持っている道具より速い時だけ
func _check_brush_needs_brush_and_speed() -> void:
	var no_brush: Dictionary = _base_snapshot()
	no_brush["ready_cat_ids"] = [&"cat_0"]
	var without: Dictionary = PolicyScript.choose_action(no_brush)
	_checker._check(
		without.get("kind") == PolicyScript.ACTION_CLEAN,
		"休んでいない猫がいてもブラシを持っていなければ毛を取る (実際: %s)" % str(without)
	)
	var fast_tool: Dictionary = _with_tool(
		_with_tool(_base_snapshot(), ToolCatalogScript.TOOL_BRUSH), ToolCatalogScript.TOOL_VACUUM
	)
	fast_tool["ready_cat_ids"] = [&"cat_0"]
	var vacuum_rate: float = PolicyScript.tool_rate(
		fast_tool, ToolCatalogScript.TOOL_VACUUM, fast_tool["rooms"][1]
	)
	var with_vacuum: Dictionary = PolicyScript.choose_action(fast_tool)
	_checker._check(
		vacuum_rate > PolicyScript.brush_rate()
		and with_vacuum.get("kind") == PolicyScript.ACTION_CLEAN
		and with_vacuum.get("tool_id") == ToolCatalogScript.TOOL_VACUUM,
		"ブラシと猫がいても、掃除機 (%.2f 本 / 秒) がブラシ (%.2f 本 / 秒) より速ければ掃除機で取る (実際: %s)"
		% [vacuum_rate, PolicyScript.brush_rate(), str(with_vacuum)]
	)


## 買う物の候補は、持っていない毛を取る道具とブラシ (ライトのような毛を取らない道具は入らない)、
## 持っている道具のレベル上げ、手の強化 2 つ、上限まで置いていない掃除ロボット
func _check_purchase_candidates() -> void:
	var snapshot: Dictionary = _with_tool(_base_snapshot(), ToolCatalogScript.TOOL_TWEEZERS)
	var kinds_by_item: Dictionary = {}
	for candidate: Dictionary in PolicyScript.purchase_candidates(snapshot):
		kinds_by_item[candidate["item_id"]] = candidate["purchase_kind"]
	_checker._check(
		kinds_by_item.get(ToolCatalogScript.TOOL_PACKING_TAPE) == GameStateScript.PURCHASE_TOOL
		and kinds_by_item.get(ToolCatalogScript.TOOL_BRUSH) == GameStateScript.PURCHASE_TOOL
		and kinds_by_item.get(ToolCatalogScript.TOOL_TWEEZERS) == GameStateScript.PURCHASE_LEVEL_UP
		and not kinds_by_item.has(ToolCatalogScript.TOOL_GLOW_LIGHT)
		and not kinds_by_item.has(ToolCatalogScript.TOOL_HAND)
		and kinds_by_item.get(HandRulesScript.UPGRADE_DEXTERITY)
		== GameStateScript.PURCHASE_HAND_UPGRADE
		and kinds_by_item.get(HandRulesScript.UPGRADE_GRAB_COUNT)
		== GameStateScript.PURCHASE_HAND_UPGRADE
		and kinds_by_item.get(&"") == PolicyScript.PURCHASE_ROBOT,
		"候補は持っていない毛を取る道具とブラシ・持っている道具のレベル上げ・手の強化・掃除ロボットで、ライトと手は入らない (実際: %s)"
		% str(kinds_by_item)
	)


## 所持金が値段ちょうどの時は売りに行かずに買う
func _check_buys_at_exact_price() -> void:
	var snapshot: Dictionary = _base_snapshot()
	var best: Dictionary = PolicyScript.best_purchase(snapshot)
	snapshot["money"] = int(best["price"])
	snapshot["stock_value"] = 100
	var action: Dictionary = PolicyScript.choose_action(snapshot)
	_checker._check(
		action.get("kind") in [PolicyScript.ACTION_BUY, PolicyScript.ACTION_BUY_ROBOT]
		and action.get("item_id", &"") == best["item_id"],
		"所持金が値段 %d 円ちょうどなら売らずに %s を買う (実際: %s)"
		% [int(best["price"]), best["item_id"], str(action)]
	)


## 1 手にかける秒は手の種類で決まる: 手は狙う秒 + 引く秒、手に持つ道具は狙う秒 + かける秒、部屋ごとの道具・買う・
## 売る・ブラシ・待つはそれぞれの見積もり (所要時間はこの秒の合計なので、取り違えると所要時間が変わる)
func _check_action_seconds() -> void:
	for pair: Array in [
		[{"kind": PolicyScript.ACTION_CLEAN, "tool_id": ToolCatalogScript.TOOL_HAND}, 1.0 + 2.0],
		[{"kind": PolicyScript.ACTION_CLEAN, "tool_id": ToolCatalogScript.TOOL_TWEEZERS}, 1.0 + 0.5],
		[{"kind": PolicyScript.ACTION_CLEAN, "tool_id": ToolCatalogScript.TOOL_SUCTION_TRUCK}, 3.0],
		[{"kind": PolicyScript.ACTION_CLEAN, "tool_id": ToolCatalogScript.TOOL_ADHESIVE_SHEET}, 3.0],
		[{"kind": PolicyScript.ACTION_BUY}, 3.0],
		[{"kind": PolicyScript.ACTION_BUY_ROBOT}, 3.0],
		[{"kind": PolicyScript.ACTION_HAUL}, 3.0],
		[{"kind": PolicyScript.ACTION_SELL}, 20.0],
		[{"kind": PolicyScript.ACTION_BRUSH}, 4.0],
		[{"kind": PolicyScript.ACTION_WAIT}, 1.0],
	]:
		var seconds: float = PolicyScript.action_seconds(pair[0], 2.0)
		_checker._check(
			is_equal_approx(seconds, float(pair[1])),
			"1 手 %s の秒は %.1f 秒 (引く秒 2 秒。実際: %.2f 秒)" % [str(pair[0]), float(pair[1]), seconds]
		)


## 屋敷全体の速さは、ブラシを持ち休んでいない猫がいる時だけブラシの速さを数え、アンドロイドを持つと
## 部屋の平均でかかる本数 ÷ 働く間隔を足す
func _check_total_rate_parts() -> void:
	var base: Dictionary = _base_snapshot()
	var base_rate: float = PolicyScript.total_rate(base)
	var brush_only: Dictionary = _with_tool(base, ToolCatalogScript.TOOL_BRUSH)
	var cats_only: Dictionary = base.duplicate(true)
	cats_only["ready_cat_ids"] = [&"cat_0"]
	var both: Dictionary = brush_only.duplicate(true)
	both["ready_cat_ids"] = [&"cat_0"]
	_checker._check(
		is_equal_approx(PolicyScript.total_rate(brush_only), base_rate)
		and is_equal_approx(PolicyScript.total_rate(cats_only), base_rate)
		and is_equal_approx(PolicyScript.total_rate(both), PolicyScript.brush_rate()),
		"ブラシだけ・猫だけでは速さが変わらず、両方そろうと手 (%.2f) より速いブラシ (%.2f) の速さになる (実際: %.2f / %.2f / %.2f)"
		% [
			base_rate,
			PolicyScript.brush_rate(),
			PolicyScript.total_rate(brush_only),
			PolicyScript.total_rate(cats_only),
			PolicyScript.total_rate(both),
		]
	)
	var android: Dictionary = _with_tool(base, ToolCatalogScript.TOOL_ANDROID)
	for room: Dictionary in android["rooms"]:
		room["covered"] = {ToolCatalogScript.TOOL_ANDROID: {"hairs": 20, "surfaces": 2}}
	_checker._check(
		is_equal_approx(
			PolicyScript.total_rate(android) - base_rate,
			20.0 / BigToolSiteScript.ANDROID_INTERVAL_SECONDS
		),
		"アンドロイドは部屋の平均でかかる 20 本 (上限 30 本 × 2 面より少ない) ÷ %.0f 秒の速さを足す (実際: %.3f)"
		% [BigToolSiteScript.ANDROID_INTERVAL_SECONDS, PolicyScript.total_rate(android) - base_rate]
	)


## 部屋ごとにかける道具の本数は、かかる表面の毛の本数と「1 回の上限 × かかる表面の数」の小さい方で、
## かかる表面が無ければ 0
func _check_room_tool_cap() -> void:
	var sheet: StringName = ToolCatalogScript.TOOL_ADHESIVE_SHEET
	var snapshot: Dictionary = _with_tool(_base_snapshot(), sheet)
	var max_hairs: float = float(ToolCatalogScript.find_tool(sheet)["max_hairs"])
	var rates: Array[float] = []
	for covered: Dictionary in [
		{"hairs": ROOM_HAIRS, "surfaces": 1},
		{"hairs": 10, "surfaces": 1},
		{"hairs": ROOM_HAIRS, "surfaces": 0},
	]:
		var room: Dictionary = _room(&"c", 0.0)
		room["covered"] = {sheet: covered}
		rates.append(PolicyScript.tool_rate(snapshot, sheet, room))
	var per_hair: float = rates[1] / 10.0
	_checker._check(
		is_equal_approx(rates[0], per_hair * max_hairs) and rates[2] == 0.0 and per_hair > 0.0,
		"粘着シートの本数は毛 3000 本・1 面なら上限 %.0f 本、毛 10 本なら 10 本、0 面なら 0 本 (実際の速さ: %s)"
		% [max_hairs, str(rates)]
	)


## レベルの上限まで上げた道具と、上限の段まで上げた手の強化は、買う物の候補から外れる
func _check_candidates_at_max_level() -> void:
	var snapshot: Dictionary = _with_tool(_base_snapshot(), ToolCatalogScript.TOOL_TWEEZERS)
	snapshot["owned"][ToolCatalogScript.TOOL_TWEEZERS]["level"] = ToolRulesScript.MAX_TOOL_LEVEL
	snapshot["hand_levels"][HandRulesScript.UPGRADE_DEXTERITY] = (
		ToolRulesScript.MAX_HAND_UPGRADE_LEVEL
	)
	var items: Array = []
	for candidate: Dictionary in PolicyScript.purchase_candidates(snapshot):
		items.append(candidate["item_id"])
	_checker._check(
		not items.has(ToolCatalogScript.TOOL_TWEEZERS)
		and not items.has(HandRulesScript.UPGRADE_DEXTERITY)
		and items.has(HandRulesScript.UPGRADE_GRAB_COUNT),
		"レベル上限のピンセットと上限の段の器用さは候補に無く、上限でない一度につまめる本数は残る (実際: %s)"
		% str(items)
	)

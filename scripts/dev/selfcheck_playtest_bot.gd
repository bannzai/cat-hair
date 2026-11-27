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
## 検証の部屋 1 つの毛の本数 (屋敷の既定 12,000 本を 4 部屋に分けた本数)
const ROOM_HAIRS: int = 3000
## 検証の部屋 1 つの毛の付く表面の面積 (m2。既定の 6 m 四方の部屋の床)
const ROOM_AREA_M2: float = 36.0
## 元を取るまでの秒を比べる時に、浮動小数の誤差で同じ値の候補を「もっと短い」と数えない幅 (秒)
const SCORE_TOLERANCE: float = 0.001

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


## 手しか持たず、お金も在庫も無い屋敷の様子 (部屋 a・b。b の方がきれいさが低い)
static func _base_snapshot() -> Dictionary:
	return {
		"money": 0,
		"stock_value": 0,
		"owned": {},
		"hand_levels": {HandRulesScript.UPGRADE_DEXTERITY: 0, HandRulesScript.UPGRADE_GRAB_COUNT: 0},
		"robots": 0,
		"rooms": [_room(&"a", 0.6), _room(&"b", 0.2)],
		"room_tool_surfaces": {},
		"ready_cat_ids": [],
	}


## きれいさ cleanliness の検証の部屋 room_id (毛は ROOM_HAIRS 本、機嫌は屋敷に入った時の値)
static func _room(room_id: StringName, cleanliness: float) -> Dictionary:
	return {
		"room_id": room_id,
		"hair_count": ROOM_HAIRS,
		"cleanliness": cleanliness,
		"mood": MansionBuilderScript.INITIAL_RESIDENT_MOOD,
		"area_m2": ROOM_AREA_M2,
	}


## snapshot に道具 tool_id を持たせる (レベル 1、消耗品は買った時の数)
static func _with_tool(snapshot: Dictionary, tool_id: StringName) -> Dictionary:
	var after: Dictionary = snapshot.duplicate(true)
	after["owned"][tool_id] = {
		"level": 1,
		"consumables": int(ToolCatalogScript.find_tool(tool_id)["initial_consumables"]),
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
	snapshot["money"] = 1000000
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
	_checker._check(
		(
			int(best.get("price", 0))
			< int(ToolCatalogScript.find_tool(ToolCatalogScript.TOOL_SUCTION_TRUCK)["price"])
		),
		"手しか持たない時に最初に選ぶ物 %s は、吸引車 (3,000 円) より安い" % str(best)
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
	var snapshot: Dictionary = _with_tool(
		_with_tool(_base_snapshot(), ToolCatalogScript.TOOL_TWEEZERS), ToolCatalogScript.TOOL_VACUUM
	)
	var action: Dictionary = PolicyScript.choose_action(snapshot)
	_checker._check(
		action.get("kind") == PolicyScript.ACTION_CLEAN
		and action.get("tool_id") == ToolCatalogScript.TOOL_VACUUM,
		"毛抜きと掃除機を持っている時は速い掃除機で取る (実際: %s)" % str(action)
	)


## いちばん速い道具の消耗品が尽きた時、買い足すお金があれば買い足し、無ければ次に速い道具で取る
func _check_refills_empty_tool() -> void:
	var snapshot: Dictionary = _with_tool(
		_with_tool(_base_snapshot(), ToolCatalogScript.TOOL_TWEEZERS), ToolCatalogScript.TOOL_VACUUM
	)
	snapshot["owned"][ToolCatalogScript.TOOL_VACUUM]["consumables"] = 0
	var broke: Dictionary = PolicyScript.choose_action(snapshot)
	_checker._check(
		broke.get("kind") == PolicyScript.ACTION_CLEAN
		and broke.get("tool_id") == ToolCatalogScript.TOOL_TWEEZERS,
		"掃除機のパックが尽きて買い足すお金も無い時は毛抜きで取る (実際: %s)" % str(broke)
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
	var robot: Dictionary = {
		"purchase_kind": PolicyScript.PURCHASE_ROBOT,
		"item_id": &"",
		"price": RobotRulesScript.ROBOT_PRICE,
	}
	_checker._check(
		(
			PolicyScript.total_rate(PolicyScript.apply_purchase(snapshot, robot))
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
	snapshot["money"] = 1000000
	for _round: int in range(200):
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

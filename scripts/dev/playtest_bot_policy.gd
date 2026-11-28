extends RefCounted
## 自動テストプレイ (make simulate / make playtest) の bot が、次にする 1 手を選ぶ方針。状態を持たない純粋な計算だけを置き、
## selfcheck が入力 (ゲームの様子) と出力 (1 手) で検証する。
## 方針は「いちばん効率のよい手を選ぶ」: 毛を取る速さ (本 / 秒) を見積もり、貯めて買って元を取るまでの秒がいちばん短い物を、
## お金が貯まり次第買う (足りない分は毛を売って作る)。買う物が無い時は、持っている道具のうちいちばん速い物で、
## きれいさがいちばん低い部屋の毛を取る。
##
## ゲームの様子 (snapshot) の形 (playtest_bot.gd が作る):
## {"money": 所持金, "stock_value": 在庫をすべて売った時の額,
##  "owned": {持っている道具の id -> {"level", "consumable_count"}},
##  "hand_levels": {HandRules.UPGRADE_* -> 段}, "robots": 掃除ロボットの台数,
##  "rooms": [{"room_id", "hair_count": 残り, "cleanliness": きれいさ, "mood": 機嫌, "area_m2": 毛の付く表面の面積,
##    "covered": {ROOM_TOOL_IDS の id -> {"hairs": 道具がかかる表面の毛の本数, "surfaces": かかる表面の数}}}],
##  "ready_cat_ids": [ブラシをかけられる猫]}

## 手に持って使う道具の定義
const ToolCatalogScript := preload("res://scripts/tools/tool_catalog.gd")
## 手に持って使う道具のルールの計算
const ToolRulesScript := preload("res://scripts/tools/tool_rules.gd")
## 手で毛を取る時のルールの計算
const HandRulesScript := preload("res://scripts/hand/hand_rules.gd")
## 掃除ロボットの計算 (値段・台数・取る間隔)
const RobotRulesScript := preload("res://scripts/automation/robot_rules.gd")
## 猫のブラッシングの計算 (1 回で取れる本数)
const CatRulesScript := preload("res://scripts/automation/cat_rules.gd")
## 屋敷レイアウト型スクリプト (表面の種類の定数を使う)
const MansionLayoutScript := preload("res://scripts/mansion/mansion_layout.gd")
## 状態管理 autoload スクリプト (買う物の種類の定数を使う)
const GameStateScript := preload("res://scripts/state/game_state.gd")
## 大型の道具 (アンドロイドが働く間隔)
const BigToolSiteScript := preload("res://scripts/tools/big_tool_site.gd")

## 人が遊ぶ速さの見積もり (bot が 1 手にかけるゲーム内の秒)。実機で人が遊んで測っていない見積もりで、
## 所要時間はこの値に比例して伸び縮みするため、変えた時は DIRECTION.md「決めたこと」の自動テストプレイの行も直す。
## 次に取る毛へ目線を向ける秒。マウスで照準を隣の毛へ動かして止める 1 動作の見積もり
const AIM_SECONDS: float = 1.0
## 手に持つ道具を 1 回かける秒 (狙いを合わせた後)。クリック 1 回で使い終わるため、狙う秒の半分と見積もった
const SWEEP_USE_SECONDS: float = 0.5
## 部屋ごとにかける道具 (吸引車・粘着シート) を部屋に 1 回かける秒。キーで持ち替えてクリックするまでの見積もり
const ROOM_TOOL_SECONDS: float = 3.0
## 隣の部屋へ歩いて移る秒 (取る部屋を変えた時)。既定の部屋の幅 6 m の半分ずつを歩く 6 m を、歩く速さ 4.2 m/s
## (FirstPersonPlayer.DEFAULT_MOVE_SPEED) と曲がる・ドアを抜ける時間で約 1.5 秒 + 余裕に見積もり、6 秒にした
const ROOM_MOVE_SECONDS: float = 6.0
## 買取業者まで歩いて毛を売り、戻る秒。4 部屋の屋敷の端から端 (約 24 m) の往復を 4.2 m/s で約 12 秒、
## 画面を開いて売る数秒を足して 20 秒にした
const TRADER_TRIP_SECONDS: float = 20.0
## 道具を買う画面を開いて 1 つ買う秒。T で開き、ボタンを探して押し、閉じる 3 動作を 1 秒ずつと見積もった
const SHOP_SECONDS: float = 3.0
## 猫に近づいてブラシをかける秒。動いている猫に照準を合わせる分、道具を床にかけるより長く見積もった
const BRUSH_SECONDS: float = 4.0
## することが無い時に待つ秒。何もしない 1 手も、狙う 1 動作と同じ長さとみなす
const WAIT_SECONDS: float = AIM_SECONDS
## 道具の取れる本数を見積もる表面の種類 (屋敷の毛のほとんどが乗る床)
const ESTIMATE_SURFACE: StringName = MansionLayoutScript.SURFACE_FLOOR

## 1 手の種類: 道具 tool_id (手を含む) で部屋 room_id の毛を取る
const ACTION_CLEAN: StringName = &"clean"
## 1 手の種類: purchase_kind (GameState.PURCHASE_*) の item_id を買う
const ACTION_BUY: StringName = &"buy"
## 1 手の種類: 掃除ロボットを 1 台買う (回らせる部屋は playtest_bot.gd が選ぶ)
const ACTION_BUY_ROBOT: StringName = &"buy_robot"
## 1 手の種類: 買取業者へ行き、在庫をすべて売る
const ACTION_SELL: StringName = &"sell"
## 1 手の種類: ダンプカーを呼んで在庫を運び出して売る
const ACTION_HAUL: StringName = &"haul"
## 1 手の種類: 猫 cat_id にブラシをかける
const ACTION_BRUSH: StringName = &"brush"
## 1 手の種類: することが無いので待つ
const ACTION_WAIT: StringName = &"wait"
## 買う物の種類 (bot だけが使う): 掃除ロボット。GameState.purchase ではなく automation.buy_robot で買う
const PURCHASE_ROBOT: StringName = &"robot"

## 速さで割る時の下限 (本 / 秒)。速さが 0 の時に 0 で割らないための値で、手 1 本の速さより十分小さい
const MIN_RATE: float = 0.001
## 部屋ごとにかける道具 (アンドロイドを含む)。部屋の様子に、これらがかかる表面の毛の本数を持たせる
const ROOM_TOOL_IDS: Array[StringName] = [
	ToolCatalogScript.TOOL_SUCTION_TRUCK,
	ToolCatalogScript.TOOL_ADHESIVE_SHEET,
	ToolCatalogScript.TOOL_ANDROID,
]
## 毛の密度を求める時に面積で割る下限 (m2)。毛の付く表面の無い部屋で 0 で割らないための値で、
## 道具の範囲 (いちばん小さいピンセットで約 0.045 m2) より小さい
const MIN_AREA_M2: float = 0.01
## 人が持って毛を取る道具の種類 (手のほか。アンドロイドは自分で働くので含めない)
const MANUAL_TOOL_KINDS: Array[StringName] = [
	ToolCatalogScript.KIND_SWEEP, ToolCatalogScript.KIND_ROOM, ToolCatalogScript.KIND_SHEET
]
## 毛を取る速さで比べず、毛を取る道具を買い終えた後にこの順で 1 つずつ買う道具 (加工機・ダンプカー)
const AFTER_CLEANING_TOOL_IDS: Array[StringName] = [
	ToolCatalogScript.TOOL_HAIR_PROCESSOR, ToolCatalogScript.TOOL_DUMP_TRUCK
]


## ゲームの様子 snapshot から次の 1 手を返す ({"kind": ACTION_*, ...})
static func choose_action(snapshot: Dictionary) -> Dictionary:
	var purchase: Dictionary = best_purchase(snapshot)
	if not purchase.is_empty():
		var price: int = int(purchase["price"])
		if int(snapshot["money"]) >= price:
			return _purchase_action(purchase)
		if int(snapshot["money"]) + int(snapshot["stock_value"]) >= price:
			return {"kind": _sell_kind(snapshot)}
	var room: Dictionary = dirtiest_room(snapshot)
	if room.is_empty():
		return {"kind": ACTION_WAIT}
	var cats: Array = snapshot["ready_cat_ids"]
	var tool_id: StringName = best_cleaning_tool(snapshot, room)
	if (
		_owns(snapshot, ToolCatalogScript.TOOL_BRUSH)
		and not cats.is_empty()
		and brush_rate() > tool_rate(snapshot, tool_id, room)
	):
		return {"kind": ACTION_BRUSH, "cat_id": cats[0]}
	if not ToolRulesScript.can_use(
		tool_id, int(_owned_entry(snapshot, tool_id).get("consumable_count", 0))
	):
		return {
			"kind": ACTION_BUY,
			"purchase_kind": GameStateScript.PURCHASE_CONSUMABLE,
			"item_id": tool_id,
		}
	return {"kind": ACTION_CLEAN, "tool_id": tool_id, "room_id": room["room_id"]}


## 買う物 purchase (best_purchase の戻り値) を買う 1 手
static func _purchase_action(purchase: Dictionary) -> Dictionary:
	if purchase["purchase_kind"] == PURCHASE_ROBOT:
		return {"kind": ACTION_BUY_ROBOT}
	return {
		"kind": ACTION_BUY,
		"purchase_kind": purchase["purchase_kind"],
		"item_id": purchase["item_id"],
	}


## 毛を売る 1 手の種類 (ダンプカーを持っていれば呼び、無ければ買取業者へ行く)
static func _sell_kind(snapshot: Dictionary) -> StringName:
	return ACTION_HAUL if _owns(snapshot, ToolCatalogScript.TOOL_DUMP_TRUCK) else ACTION_SELL


## 毛が残っている部屋のうち、きれいさがいちばん低い部屋 (snapshot["rooms"] の 1 件。毛が残っている部屋が無ければ空)
static func dirtiest_room(snapshot: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	for room: Dictionary in snapshot["rooms"]:
		if int(room["hair_count"]) <= 0:
			continue
		if best.is_empty() or float(room["cleanliness"]) < float(best["cleanliness"]):
			best = room
	return best


## 次に買う物を返す: {"purchase_kind", "item_id", "price", "gain": 速さの伸び, "score_seconds"}。
## 毛を取る速さ (total_rate) を伸ばす物のうち、score_seconds (purchase_score_seconds) がいちばん短い物を選ぶ。
## 伸びる物が無ければ AFTER_CLEANING_TOOL_IDS の持っていない物を順に (gain は 0)。買う物が無ければ空
static func best_purchase(snapshot: Dictionary) -> Dictionary:
	var base_rate: float = total_rate(snapshot)
	var best: Dictionary = {}
	for candidate: Dictionary in purchase_candidates(snapshot):
		var gain: float = total_rate(apply_purchase(snapshot, candidate)) - base_rate
		if gain <= 0.0:
			continue
		var score: float = purchase_score_seconds(int(candidate["price"]), base_rate, gain)
		if best.is_empty() or score < float(best["score_seconds"]):
			best = candidate.duplicate()
			best["gain"] = gain
			best["score_seconds"] = score
	if not best.is_empty():
		return best
	for tool_id: StringName in AFTER_CLEANING_TOOL_IDS:
		if not _owns(snapshot, tool_id):
			var candidate: Dictionary = _candidate(
				GameStateScript.PURCHASE_TOOL,
				tool_id,
				int(ToolCatalogScript.find_tool(tool_id)["price"])
			)
			candidate["gain"] = 0.0
			return candidate
	return {}


## 値段 price の物を、今の速さ base_rate (本 / 秒。毛 1 本はおよそ 1 円) で貯めて買い、
## 伸びた速さ gain で元を取るまでの秒 (貯める秒 + 元を取る秒)。短いほど先に買う。
## 1 円あたりの伸びだけで比べると、今の稼ぎでは何十分も貯める高い物を待ち続けるため、貯める秒も足す
static func purchase_score_seconds(price: int, base_rate: float, gain: float) -> float:
	return float(price) / maxf(MIN_RATE, base_rate) + float(price) / maxf(MIN_RATE, gain)


## 今買える候補 (値段の付いた物) の一覧: 毛を取る道具とブラシを買う・持っている道具のレベルを上げる・手の強化・掃除ロボット
static func purchase_candidates(snapshot: Dictionary) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	for tool_def: Dictionary in ToolCatalogScript.TOOLS:
		var tool_id: StringName = tool_def["id"]
		if tool_id == ToolCatalogScript.TOOL_HAND:
			continue
		var owned: Dictionary = _owned_entry(snapshot, tool_id)
		if owned.is_empty():
			if ToolRulesScript.removes_hair(tool_id) or tool_id == ToolCatalogScript.TOOL_BRUSH:
				candidates.append(_candidate(GameStateScript.PURCHASE_TOOL, tool_id, int(tool_def["price"])))
			continue
		var level_price: int = ToolRulesScript.level_up_price(tool_id, int(owned["level"]))
		if level_price >= 0:
			candidates.append(_candidate(GameStateScript.PURCHASE_LEVEL_UP, tool_id, level_price))
	for upgrade_id: StringName in [
		HandRulesScript.UPGRADE_DEXTERITY, HandRulesScript.UPGRADE_GRAB_COUNT
	]:
		var upgrade_price: int = ToolRulesScript.hand_upgrade_price(_hand_level(snapshot, upgrade_id))
		if upgrade_price >= 0:
			candidates.append(_candidate(GameStateScript.PURCHASE_HAND_UPGRADE, upgrade_id, upgrade_price))
	if int(snapshot["robots"]) < RobotRulesScript.MAX_ROBOTS:
		candidates.append(_candidate(PURCHASE_ROBOT, &"", RobotRulesScript.ROBOT_PRICE))
	return candidates


## 買う物の候補 1 件
static func _candidate(purchase_kind: StringName, item_id: StringName, price: int) -> Dictionary:
	return {"purchase_kind": purchase_kind, "item_id": item_id, "price": price}


## snapshot に候補 candidate を買った後の様子を返す (snapshot は変えない。お金は減らさない)
static func apply_purchase(snapshot: Dictionary, candidate: Dictionary) -> Dictionary:
	var after: Dictionary = snapshot.duplicate(true)
	var item_id: StringName = candidate["item_id"]
	match candidate["purchase_kind"]:
		GameStateScript.PURCHASE_TOOL:
			after["owned"][item_id] = {
				"level": 1,
				"consumable_count": int(ToolCatalogScript.find_tool(item_id)["initial_consumables"]),
			}
		GameStateScript.PURCHASE_LEVEL_UP:
			after["owned"][item_id]["level"] = int(after["owned"][item_id]["level"]) + 1
		GameStateScript.PURCHASE_HAND_UPGRADE:
			after["hand_levels"][item_id] = _hand_level(snapshot, item_id) + 1
		PURCHASE_ROBOT:
			after["robots"] = int(snapshot["robots"]) + 1
	return after


## 屋敷全体で毛を取る速さ (本 / 秒) の見積もり: 人が持つ道具でいちばん速い物と、掃除ロボット・アンドロイドの合計。
## 部屋は全部屋の平均で見積もる
static func total_rate(snapshot: Dictionary) -> float:
	var average: Dictionary = average_room(snapshot)
	var manual: float = 0.0
	for tool_id: StringName in cleaning_tool_ids(snapshot):
		manual = maxf(manual, tool_rate(snapshot, tool_id, average))
	if (
		_owns(snapshot, ToolCatalogScript.TOOL_BRUSH)
		and not (snapshot["ready_cat_ids"] as Array).is_empty()
	):
		manual = maxf(manual, brush_rate())
	var automatic: float = float(snapshot["robots"]) / RobotRulesScript.PICK_INTERVAL_SECONDS
	if _owns(snapshot, ToolCatalogScript.TOOL_ANDROID):
		automatic += (
			_room_tool_hairs(ToolCatalogScript.TOOL_ANDROID, average)
			/ BigToolSiteScript.ANDROID_INTERVAL_SECONDS
		)
	return manual + automatic


## 全部屋の平均の部屋 (残りの本数・面積・部屋ごとにかける道具のかかる本数と表面の数の平均。
## dirtiest_room の 1 件と同じ形)
static func average_room(snapshot: Dictionary) -> Dictionary:
	var rooms: Array = snapshot["rooms"]
	var count: float = float(maxi(1, rooms.size()))
	var hair_count: float = 0.0
	var area: float = 0.0
	var covered: Dictionary = {}
	for room: Dictionary in rooms:
		hair_count += float(room["hair_count"])
		area += float(room["area_m2"])
		var room_covered: Dictionary = room.get("covered", {})
		for tool_id: Variant in room_covered.keys():
			var entry: Dictionary = covered.get(tool_id, {"hairs": 0.0, "surfaces": 0.0})
			entry["hairs"] = float(entry["hairs"]) + float(room_covered[tool_id]["hairs"]) / count
			entry["surfaces"] = (
				float(entry["surfaces"]) + float(room_covered[tool_id]["surfaces"]) / count
			)
			covered[tool_id] = entry
	return {
		"room_id": &"",
		"hair_count": hair_count / count,
		"area_m2": area / count,
		"covered": covered,
	}


## 人が持って毛を取る道具の id の一覧 (手と、持っている毛を取る道具。アンドロイドは自分で働くので除く)
static func cleaning_tool_ids(snapshot: Dictionary) -> Array[StringName]:
	var ids: Array[StringName] = [ToolCatalogScript.TOOL_HAND]
	for tool_def: Dictionary in ToolCatalogScript.TOOLS:
		var tool_id: StringName = tool_def["id"]
		if (
			tool_def["kind"] in MANUAL_TOOL_KINDS and _owns(snapshot, tool_id)
		):
			ids.append(tool_id)
	return ids


## 部屋 room で使う、いちばん速い道具の id。消耗品が尽きていて買い足すお金も無い道具は除く
static func best_cleaning_tool(snapshot: Dictionary, room: Dictionary) -> StringName:
	var best_id: StringName = ToolCatalogScript.TOOL_HAND
	var best_rate: float = tool_rate(snapshot, best_id, room)
	for tool_id: StringName in cleaning_tool_ids(snapshot):
		if (
			tool_id != ToolCatalogScript.TOOL_HAND
			and not ToolRulesScript.can_use(
				tool_id, int(_owned_entry(snapshot, tool_id).get("consumable_count", 0))
			)
			and int(snapshot["money"]) < int(ToolCatalogScript.find_tool(tool_id)["refill_price"])
		):
			continue
		var rate: float = tool_rate(snapshot, tool_id, room)
		if rate > best_rate:
			best_rate = rate
			best_id = tool_id
	return best_id


## 道具 tool_id で部屋 room の毛を取る速さ (本 / 秒) の見積もり。手は一度につまむ本数 / 狙って押す秒、
## 手に持つ道具は範囲の本数 (部屋の毛の密度 × 範囲の面積。1 回で触れる上限まで) × 取れる割合 / (狙う + かける秒)、
## 部屋ごとにかける道具は部屋の毛 (かかる表面ごとに上限まで) × 取れる割合 / 部屋にかける秒
static func tool_rate(snapshot: Dictionary, tool_id: StringName, room: Dictionary) -> float:
	if tool_id == ToolCatalogScript.TOOL_HAND:
		return float(
			HandRulesScript.grab_count(_hand_level(snapshot, HandRulesScript.UPGRADE_GRAB_COUNT))
		) / AIM_SECONDS
	var tool_def: Dictionary = ToolCatalogScript.find_tool(tool_id)
	if tool_def.is_empty():
		return 0.0
	var taken_ratio: float = 1.0 - ToolRulesScript.miss_ratio(
		tool_id, int(_owned_entry(snapshot, tool_id).get("level", 1)), ESTIMATE_SURFACE
	)
	if tool_def["kind"] == ToolCatalogScript.KIND_SWEEP:
		var radius: float = float(tool_def["radius_m"])
		return (
			minf(
				float(tool_def["max_hairs"]),
				(
					float(room["hair_count"]) / maxf(MIN_AREA_M2, float(room["area_m2"]))
					* PI * radius * radius
				)
			)
			* taken_ratio / (AIM_SECONDS + SWEEP_USE_SECONDS)
		)
	return _room_tool_hairs(tool_id, room) * taken_ratio / ROOM_TOOL_SECONDS


## 部屋ごとにかける道具 tool_id が部屋 room に 1 回かかる本数の見積もり
## (道具がかかる表面の毛の本数まで、かかる表面の数 × 1 回の上限まで)
static func _room_tool_hairs(tool_id: StringName, room: Dictionary) -> float:
	var covered: Dictionary = (room.get("covered", {}) as Dictionary).get(tool_id, {})
	return minf(
		float(ToolCatalogScript.find_tool(tool_id)["max_hairs"]) * float(covered.get("surfaces", 0)),
		float(covered.get("hairs", 0)),
	)


## ブラシで猫から毛を取る速さ (本 / 秒。1 回で取れる本数 / 近づいてかける秒)
static func brush_rate() -> float:
	return float(CatRulesScript.BRUSH_HAIRS) / BRUSH_SECONDS


## 1 手にかけるゲーム内の秒 (毛を取る 1 手の秒は道具で変わる。手は狙って押す時間のみ)
static func action_seconds(action: Dictionary) -> float:
	match action["kind"]:
		ACTION_CLEAN:
			match ToolCatalogScript.find_tool(action["tool_id"]).get(
				"kind", ToolCatalogScript.KIND_HAND
			):
				ToolCatalogScript.KIND_HAND:
					return AIM_SECONDS
				ToolCatalogScript.KIND_SWEEP:
					return AIM_SECONDS + SWEEP_USE_SECONDS
			return ROOM_TOOL_SECONDS
		ACTION_BUY, ACTION_BUY_ROBOT, ACTION_HAUL:
			return SHOP_SECONDS
		ACTION_SELL:
			return TRADER_TRIP_SECONDS
		ACTION_BRUSH:
			return BRUSH_SECONDS
	return WAIT_SECONDS


## 道具 tool_id を持っているか (手は最初から持っている)
static func _owns(snapshot: Dictionary, tool_id: StringName) -> bool:
	return tool_id == ToolCatalogScript.TOOL_HAND or not _owned_entry(snapshot, tool_id).is_empty()


## snapshot["owned"] の tool_id の 1 件 (持っていなければ空)。呼び出し側は空の時にレベル 1・消耗品 0 を使う:
## 持っていない道具 (と、owned に入らない手) は、買った直後の最初の段 (レベル 1) で、消耗品を持たない扱い
static func _owned_entry(snapshot: Dictionary, tool_id: StringName) -> Dictionary:
	return (snapshot["owned"] as Dictionary).get(tool_id, {})


## 手の強化 upgrade_id の段
static func _hand_level(snapshot: Dictionary, upgrade_id: StringName) -> int:
	return int((snapshot["hand_levels"] as Dictionary).get(upgrade_id, 0))

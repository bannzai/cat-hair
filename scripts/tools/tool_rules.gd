extends RefCounted
## 手に持って使う道具のルールの計算 (取りこぼしの割合・得意な表面・レベルを上げる値段・消耗品・手の強化の値段)。
## 状態を持たない純粋な計算だけを置き、selfcheck が入力と出力で検証する。値は仮の値 (ToolCatalog と同じ)。

## 手に持って使う道具の定義
const ToolCatalogScript := preload("res://scripts/tools/tool_catalog.gd")
## 屋敷レイアウト型スクリプト (表面の種類の定数を使う)
const MansionLayoutScript := preload("res://scripts/mansion/mansion_layout.gd")

## 道具のレベルの上限。取りこぼしが 1 の 0.75 倍を 4 回重ねて約 3 分の 1 になる所で止め、下限 (5%) に届く前に上げる余地を残す
const MAX_TOOL_LEVEL: int = 5
## レベルが 1 上がるごとに取りこぼしの割合に掛ける倍率。1 段上げると残る毛が 4 分の 3 になり、上げた差が 1 回で見える倍率
const MISS_FACTOR_PER_LEVEL: float = 0.75
## 取りこぼしの割合の下限。どの道具も 1 回では範囲内の毛を取り切れないようにする (PROJECT.md「道具」)
const MIN_MISS_RATIO: float = 0.05
## 取りこぼしの割合の上限 (不得意な表面でも 1 回で少しは取れる)
const MAX_MISS_RATIO: float = 0.9
## 手の強化 1 段目の値段 (円)。段 n から n + 1 へ上げる値段は (n + 1) 倍。最初の掃除代 (30 円 × 機嫌) を 2 回ためると買え、
## 道具 (ピンセット 30 円) と同じ頃に手を育てるか道具を買うかを選べる値段
const HAND_UPGRADE_BASE_PRICE: int = 40
## 手の強化の段の上限 (一度につまめる本数が HandRules.MAX_GRAB_COUNT の 10 本になる段)
const MAX_HAND_UPGRADE_LEVEL: int = 9

## 建物を覆う粘着シートが毛を捕まえる表面 (床一面に敷くため、床とカーペット)
const SHEET_SURFACE_TYPES: Array[StringName] = [
	MansionLayoutScript.SURFACE_FLOOR, MansionLayoutScript.SURFACE_CARPET
]

## 表面の得意・不得意: 得意
const RATING_GOOD: int = 1
## 表面の得意・不得意: 得意でも不得意でもない
const RATING_NORMAL: int = 0
## 表面の得意・不得意: 不得意
const RATING_BAD: int = -1


## 道具がその表面を得意か (RATING_GOOD)・不得意か (RATING_BAD)・どちらでもないか (RATING_NORMAL) を返す
static func surface_rating(tool_id: StringName, surface_type: StringName) -> int:
	var tool_def: Dictionary = ToolCatalogScript.find_tool(tool_id)
	if tool_def.is_empty():
		return RATING_NORMAL
	if (tool_def["good"] as Array).has(surface_type):
		return RATING_GOOD
	if (tool_def["bad"] as Array).has(surface_type):
		return RATING_BAD
	return RATING_NORMAL


## 毛を取る道具 (取りこぼしとレベルがある道具。ToolCatalog.HAIR_REMOVING_KINDS) か
static func removes_hair(tool_id: StringName) -> bool:
	var tool_def: Dictionary = ToolCatalogScript.find_tool(tool_id)
	return not tool_def.is_empty() and ToolCatalogScript.HAIR_REMOVING_KINDS.has(tool_def["kind"])


## 道具・レベル・表面の種類から、1 回かけた範囲に残る毛の割合 (取りこぼし。MIN_MISS_RATIO〜MAX_MISS_RATIO) を返す。
## 毛を取らない道具 (手・ライト・ブラシ・加工機・ダンプカー) と表に無い道具は 0
static func miss_ratio(tool_id: StringName, level: int, surface_type: StringName) -> float:
	var tool_def: Dictionary = ToolCatalogScript.find_tool(tool_id)
	if not removes_hair(tool_id):
		return 0.0
	var safe_level: int = clampi(level, 1, MAX_TOOL_LEVEL)
	var ratio: float = (
		float(tool_def["base_miss_ratio"]) * pow(MISS_FACTOR_PER_LEVEL, float(safe_level - 1))
	)
	match surface_rating(tool_id, surface_type):
		RATING_GOOD:
			ratio *= ToolCatalogScript.GOOD_SURFACE_FACTOR
		RATING_BAD:
			ratio *= ToolCatalogScript.BAD_SURFACE_FACTOR
	return clampf(ratio, MIN_MISS_RATIO, MAX_MISS_RATIO)


## 範囲に range_count 本ある所に道具を 1 回かけた時に、抽選する (取れる見込みのある) 本数を返す。
## 道具が 1 回で触れる上限 max_hairs までで、範囲の最後の 1 本は残す (PROJECT.md「道具」: どの道具も 1 回では
## 範囲内の毛を取り切れない。最後の 1 本は手でつまむか、別の所からかけ直す)
static func touchable_count(range_count: int, max_hairs: int) -> int:
	return clampi(mini(max_hairs, range_count - 1), 0, maxi(0, range_count))


## 範囲内の 1 本について、0 以上 1 未満の乱数 roll が取りこぼし (その毛が残る) になるか
static func is_missed(roll: float, ratio: float) -> bool:
	return roll < ratio


## 道具を今のレベルから 1 上げる値段 (円) を返す。上限のレベルと表に無い道具・手は -1 (上げられない)
static func level_up_price(tool_id: StringName, current_level: int) -> int:
	var tool_def: Dictionary = ToolCatalogScript.find_tool(tool_id)
	if (
		not removes_hair(tool_id)
		or current_level < 1
		or current_level >= MAX_TOOL_LEVEL
	):
		return -1
	return int(tool_def["price"]) * current_level


## 部屋ごとにかける道具 (吸引車・粘着シート・アンドロイド) が、部屋の中の surface_type の表面の毛を取るか。
## 粘着シートは床一面に敷くため床とカーペットだけ、吸引車とアンドロイドは部屋のすべての表面。部屋ごとにかけない道具は false
static func covers_surface(tool_id: StringName, surface_type: StringName) -> bool:
	var tool_def: Dictionary = ToolCatalogScript.find_tool(tool_id)
	if tool_def.is_empty():
		return false
	match tool_def["kind"]:
		ToolCatalogScript.KIND_ROOM, ToolCatalogScript.KIND_AUTO:
			return true
		ToolCatalogScript.KIND_SHEET:
			return SHEET_SURFACE_TYPES.has(surface_type)
	return false


## 探し物にかけると傷める道具か (表に無い道具は false)
static func damages_found_items(tool_id: StringName) -> bool:
	return bool(ToolCatalogScript.find_tool(tool_id).get("damages_found_items", false))


## 買った道具の一覧 owned_tools のうち tool_id の道具の数 (加工機のように並べた台数) を返す
static func count_owned(owned_tools: Array[OwnedTool], tool_id: StringName) -> int:
	var count: int = 0
	for owned: OwnedTool in owned_tools:
		if owned != null and owned.tool_id == tool_id:
			count += 1
	return count


## 消耗品を使う道具か
static func uses_consumable(tool_id: StringName) -> bool:
	var tool_def: Dictionary = ToolCatalogScript.find_tool(tool_id)
	return not tool_def.is_empty() and not str(tool_def["consumable_name"]).is_empty()


## 消耗品の残り consumable_count でその道具を使えるか (消耗品を使う道具は 0 以下なら使えない)
static func can_use(tool_id: StringName, consumable_count: int) -> bool:
	if ToolCatalogScript.find_tool(tool_id).is_empty():
		return false
	return not uses_consumable(tool_id) or consumable_count > 0


## 所持金 money で値段 price の物を買えるか (値段が負 = 買えない物は false)
static func can_afford(money: int, price: int) -> bool:
	return price >= 0 and money >= price


## 手の強化を段 current_level から 1 上げる値段 (円) を返す。上限の段は -1 (上げられない)
static func hand_upgrade_price(current_level: int) -> int:
	if current_level < 0 or current_level >= MAX_HAND_UPGRADE_LEVEL:
		return -1
	return HAND_UPGRADE_BASE_PRICE * (current_level + 1)

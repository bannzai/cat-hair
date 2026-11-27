class_name BuildingProgress
extends Resource
## 今いる建物の進行。お金と道具は建物ごとに持ち、次の建物へ進むと作り直す。

## 面ごとの毛データ型スクリプト
const SurfaceHairScript := preload("res://scripts/data/surface_hair.gd")
## 毛・加工品在庫データ型スクリプト
const HairStockScript := preload("res://scripts/data/hair_stock.gd")
## 所持道具データ型スクリプト
const OwnedToolScript := preload("res://scripts/data/owned_tool.gd")
## 探し物進捗データ型スクリプト
const FoundItemProgressScript := preload("res://scripts/data/found_item_progress.gd")

## 最初の建物の id (屋敷)
const BUILDING_MANSION: StringName = &"mansion"

## どの建物か
@export var building_id: StringName = BUILDING_MANSION
## この建物で遊んだ時間 (秒)
@export var elapsed_seconds: float = 0.0
## 所持金 (協力プレイでも参加者ごとではなく建物全体で 1 つ)
@export var money: int = 0
## 面ごとに残っている毛
@export var surface_hairs: Array[SurfaceHair] = []
## 取ってまだ売っていない毛と、加工した物
@export var hair_stocks: Array[HairStock] = []
## 買った道具 (同じ道具を 2 つ買うと 2 件になる)
@export var owned_tools: Array[OwnedTool] = []
## 住人ごとの機嫌 (StringName -> float。0.0 = 不機嫌 〜 1.0 = ご機嫌)
@export var resident_moods: Dictionary = {}
## 探し物ごとの状態
@export var found_items: Array[FoundItemProgress] = []
## 黒いスーツの服の毛の依頼で、出かける前に取り切って上乗せを受け取ったスーツの面の id
@export var cleared_suit_surface_ids: Array[StringName] = []
## 逃げた猫を持ち主に届けたか
@export var runaway_cat_returned: bool = false
## 住人 id -> 次の掃除代に上乗せするお礼 (円)。探し物を返した・スーツの毛を取り切った時に足し、掃除代を払う時に払って消す
@export var pending_rewards: Dictionary = {}


## 建物全体に残っている毛の総本数を返す
func total_remaining_hairs() -> int:
	var total: int = 0
	for surface: SurfaceHair in surface_hairs:
		if surface != null:
			total += surface.total_count()
	return total


## 指定した面 id の SurfaceHair を返す。見つからなければ null
func find_surface_hair(surface_id: StringName) -> SurfaceHair:
	for surface: SurfaceHair in surface_hairs:
		if surface != null and surface.surface_id == surface_id:
			return surface
	return null


## JSON 保存用の辞書に変換する
func to_dict() -> Dictionary:
	var surfaces_out: Array[Dictionary] = []
	for surface: SurfaceHair in surface_hairs:
		if surface != null:
			surfaces_out.append(surface.to_dict())
	var stocks_out: Array[Dictionary] = []
	for stock: HairStock in hair_stocks:
		if stock != null:
			stocks_out.append(stock.to_dict())
	var tools_out: Array[Dictionary] = []
	for tool: OwnedTool in owned_tools:
		if tool != null:
			tools_out.append(tool.to_dict())
	var moods_out: Dictionary = {}
	for resident_key: Variant in resident_moods.keys():
		moods_out[String(resident_key)] = clampf(float(resident_moods[resident_key]), 0.0, 1.0)
	var rewards_out: Dictionary = {}
	for resident_key: Variant in pending_rewards.keys():
		rewards_out[String(resident_key)] = maxi(0, int(pending_rewards[resident_key]))
	var items_out: Array[Dictionary] = []
	for item: FoundItemProgress in found_items:
		if item != null:
			items_out.append(item.to_dict())
	return {
		"building_id": String(building_id),
		"elapsed_seconds": maxf(0.0, elapsed_seconds),
		"money": maxi(0, money),
		"surface_hairs": surfaces_out,
		"hair_stocks": stocks_out,
		"owned_tools": tools_out,
		"resident_moods": moods_out,
		"found_items": items_out,
		"cleared_suit_surface_ids": cleared_suit_surface_ids.map(
			func(surface_id: StringName) -> String: return String(surface_id)
		),
		"runaway_cat_returned": runaway_cat_returned,
		"pending_rewards": rewards_out,
	}


## 辞書から復元する。不正な構造の場合は null を返す
static func from_dict(raw_progress_dict: Variant) -> BuildingProgress:
	if not (raw_progress_dict is Dictionary):
		return null
	var progress_dict: Dictionary = raw_progress_dict
	if not (progress_dict.get("building_id") is String):
		return null
	var raw_elapsed: Variant = progress_dict.get("elapsed_seconds")
	var raw_money: Variant = progress_dict.get("money")
	if not (raw_elapsed is int or raw_elapsed is float):
		return null
	if not (raw_money is int or raw_money is float):
		return null
	var progress: BuildingProgress = BuildingProgress.new()
	progress.building_id = StringName(progress_dict["building_id"])
	progress.elapsed_seconds = maxf(0.0, float(raw_elapsed))
	progress.money = maxi(0, int(raw_money))
	if not _load_surface_hairs(progress_dict.get("surface_hairs"), progress):
		return null
	if not _load_hair_stocks(progress_dict.get("hair_stocks"), progress):
		return null
	if not _load_owned_tools(progress_dict.get("owned_tools"), progress):
		return null
	if not _load_resident_moods(progress_dict.get("resident_moods"), progress):
		return null
	if not _load_found_items(progress_dict.get("found_items"), progress):
		return null
	if not _load_requests(progress_dict, progress):
		return null
	return progress


## 面の毛配列を復元して target_progress へ格納する。要素が不正なら false
static func _load_surface_hairs(raw_entries: Variant, target_progress: BuildingProgress) -> bool:
	if not (raw_entries is Array):
		return false
	for entry: Variant in raw_entries:
		var parsed: SurfaceHair = SurfaceHairScript.from_dict(entry)
		if parsed == null:
			return false
		target_progress.surface_hairs.append(parsed)
	return true


## 毛・加工品の在庫配列を復元して target_progress へ格納する。要素が不正なら false
static func _load_hair_stocks(raw_entries: Variant, target_progress: BuildingProgress) -> bool:
	if not (raw_entries is Array):
		return false
	for entry: Variant in raw_entries:
		var parsed: HairStock = HairStockScript.from_dict(entry)
		if parsed == null:
			return false
		target_progress.hair_stocks.append(parsed)
	return true


## 所持道具配列を復元して target_progress へ格納する。要素が不正なら false
static func _load_owned_tools(raw_entries: Variant, target_progress: BuildingProgress) -> bool:
	if not (raw_entries is Array):
		return false
	for entry: Variant in raw_entries:
		var parsed: OwnedTool = OwnedToolScript.from_dict(entry)
		if parsed == null:
			return false
		target_progress.owned_tools.append(parsed)
	return true


## 住人ごとの機嫌辞書を復元して target_progress へ格納する。型が不正なら false
static func _load_resident_moods(raw_moods: Variant, target_progress: BuildingProgress) -> bool:
	if not (raw_moods is Dictionary):
		return false
	var moods_dict: Dictionary = raw_moods
	for resident_key: Variant in moods_dict.keys():
		if not (resident_key is String):
			return false
		var mood_value: Variant = moods_dict[resident_key]
		if not (mood_value is int or mood_value is float):
			return false
		target_progress.resident_moods[StringName(resident_key)] = clampf(
			float(mood_value),
			0.0,
			1.0,
		)
	return true


## 探し物進捗配列を復元して target_progress へ格納する。要素が不正なら false
static func _load_found_items(raw_entries: Variant, target_progress: BuildingProgress) -> bool:
	if not (raw_entries is Array):
		return false
	for entry: Variant in raw_entries:
		var parsed: FoundItemProgress = FoundItemProgressScript.from_dict(entry)
		if parsed == null:
			return false
		target_progress.found_items.append(parsed)
	return true


## 依頼の進み (取り切ったスーツの面・猫を届けたか・次の掃除代に上乗せするお礼) を復元して target_progress へ格納する。
## 依頼を足す前の保存データにはキーが無いため、キーが無い時は依頼を始める前の値のままにする。型が不正なら false
static func _load_requests(progress_dict: Dictionary, target_progress: BuildingProgress) -> bool:
	var raw_suits: Variant = progress_dict.get("cleared_suit_surface_ids", [])
	var raw_returned: Variant = progress_dict.get("runaway_cat_returned", false)
	var raw_rewards: Variant = progress_dict.get("pending_rewards", {})
	if not (raw_suits is Array) or not (raw_returned is bool) or not (raw_rewards is Dictionary):
		return false
	for resident_key: Variant in raw_rewards.keys():
		var amount: Variant = raw_rewards[resident_key]
		if not (resident_key is String) or not (amount is float or amount is int):
			return false
		target_progress.pending_rewards[StringName(resident_key)] = int(amount)
	for entry: Variant in raw_suits:
		if not (entry is String):
			return false
		target_progress.cleared_suit_surface_ids.append(StringName(entry))
	target_progress.runaway_cat_returned = raw_returned
	return true

class_name BuildingProgress
extends Resource
## 今いる建物の進行。お金と道具は建物ごとに持ち、次の建物へ進むと作り直す。

const SurfaceHairScript := preload("res://scripts/data/surface_hair.gd")
const HairStockScript := preload("res://scripts/data/hair_stock.gd")
const OwnedToolScript := preload("res://scripts/data/owned_tool.gd")
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
	}


## 辞書から復元する。不正な構造の場合は null を返す
static func from_dict(data: Variant) -> BuildingProgress:
	if not (data is Dictionary):
		return null
	var dict: Dictionary = data
	if not (dict.get("building_id") is String):
		return null
	var raw_elapsed: Variant = dict.get("elapsed_seconds")
	var raw_money: Variant = dict.get("money")
	if not (raw_elapsed is int or raw_elapsed is float):
		return null
	if not (raw_money is int or raw_money is float):
		return null
	var progress: BuildingProgress = BuildingProgress.new()
	progress.building_id = StringName(dict["building_id"])
	progress.elapsed_seconds = maxf(0.0, float(raw_elapsed))
	progress.money = 0
	if not _load_surface_hairs(dict.get("surface_hairs"), progress):
		return null
	if not _load_hair_stocks(dict.get("hair_stocks"), progress):
		return null
	if not _load_owned_tools(dict.get("owned_tools"), progress):
		return null
	if not _load_resident_moods(dict.get("resident_moods"), progress):
		return null
	if not _load_found_items(dict.get("found_items"), progress):
		return null
	return progress


static func _load_surface_hairs(raw: Variant, target: BuildingProgress) -> bool:
	if not (raw is Array):
		return false
	for entry: Variant in raw:
		var parsed: SurfaceHair = SurfaceHairScript.from_dict(entry)
		if parsed == null:
			return false
		target.surface_hairs.append(parsed)
	return true


static func _load_hair_stocks(raw: Variant, target: BuildingProgress) -> bool:
	if not (raw is Array):
		return false
	for entry: Variant in raw:
		var parsed: HairStock = HairStockScript.from_dict(entry)
		if parsed == null:
			return false
		target.hair_stocks.append(parsed)
	return true


static func _load_owned_tools(raw: Variant, target: BuildingProgress) -> bool:
	if not (raw is Array):
		return false
	for entry: Variant in raw:
		var parsed: OwnedTool = OwnedToolScript.from_dict(entry)
		if parsed == null:
			return false
		target.owned_tools.append(parsed)
	return true


static func _load_resident_moods(raw: Variant, target: BuildingProgress) -> bool:
	if not (raw is Dictionary):
		return false
	var moods: Dictionary = raw
	for key: Variant in moods.keys():
		if not (key is String):
			return false
		var val: Variant = moods[key]
		if not (val is int or val is float):
			return false
		target.resident_moods[StringName(key)] = clampf(float(val), 0.0, 1.0)
	return true


static func _load_found_items(raw: Variant, target: BuildingProgress) -> bool:
	if not (raw is Array):
		return false
	for entry: Variant in raw:
		var parsed: FoundItemProgress = FoundItemProgressScript.from_dict(entry)
		if parsed == null:
			return false
		target.found_items.append(parsed)
	return true

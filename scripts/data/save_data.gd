class_name SaveData
extends Resource
## セーブデータ全体。建物をまたいで残る物と、今いる建物の進行・開発者向けの調整値を持つ。

const BuildingRecordScript := preload("res://scripts/data/building_record.gd")
const BuildingProgressScript := preload("res://scripts/data/building_progress.gd")
const MansionTuningScript := preload("res://scripts/data/mansion_tuning.gd")

## 現在の保存スキーマ版
const SCHEMA_VERSION: int = 1

## 保存スキーマのバージョン
@export var schema_version: int = SCHEMA_VERSION
## 持ち越す手の強化。強化の種類 (指先の器用さ・一度につまめる本数等) ごとのレベル (StringName -> int)
@export var hand_upgrade_levels: Dictionary = {}
## 図鑑に載った珍しい毛の種類
@export var found_rare_hair_ids: Array[StringName] = []
## 終えた建物の成績 (終えた順)
@export var building_records: Array[BuildingRecord] = []
## 今いる建物の進行。次の建物へ進むと新しく作り直す
@export var building_progress: BuildingProgress = null
## 屋敷の組み立てに使う開発者向けの調整値
@export var tuning: MansionTuning = null


## JSON 保存用の辞書に変換する
func to_dict() -> Dictionary:
	var upgrades_out: Dictionary = {}
	for key: Variant in hand_upgrade_levels.keys():
		upgrades_out[String(key)] = maxi(0, int(hand_upgrade_levels[key]))
	var rare_out: Array[String] = []
	for rare_id: StringName in found_rare_hair_ids:
		rare_out.append(String(rare_id))
	var records_out: Array[Dictionary] = []
	for record: BuildingRecord in building_records:
		if record != null:
			records_out.append(record.to_dict())
	var safe_progress: BuildingProgress = (
		building_progress if building_progress != null else BuildingProgressScript.new()
	)
	var safe_tuning: MansionTuning = tuning if tuning != null else MansionTuningScript.new()
	return {
		"schema_version": schema_version,
		"hand_upgrade_levels": upgrades_out,
		"found_rare_hair_ids": rare_out,
		"building_records": records_out,
		"building_progress": safe_progress.to_dict(),
		"tuning": safe_tuning.to_dict(),
	}


## 辞書から復元する。壊れたデータや未対応スキーマの場合は null を返す
static func from_dict(data: Variant) -> SaveData:
	if not (data is Dictionary):
		return null
	var dict: Dictionary = data
	var raw_version: Variant = dict.get("schema_version")
	if not (raw_version is int or raw_version is float):
		return null
	if int(raw_version) != SCHEMA_VERSION:
		return null
	var parsed_progress: BuildingProgress = BuildingProgressScript.from_dict(
		dict.get("building_progress")
	)
	if parsed_progress == null:
		return null
	var parsed_tuning: MansionTuning = MansionTuningScript.from_dict(dict.get("tuning"))
	if parsed_tuning == null:
		return null
	var save: SaveData = SaveData.new()
	save.schema_version = SCHEMA_VERSION
	save.building_progress = parsed_progress
	save.tuning = parsed_tuning
	if not _load_hand_upgrades(dict.get("hand_upgrade_levels"), save):
		return null
	if not _load_rare_hairs(dict.get("found_rare_hair_ids"), save):
		return null
	if not _load_building_records(dict.get("building_records"), save):
		return null
	return save


static func _load_hand_upgrades(raw: Variant, target: SaveData) -> bool:
	if not (raw is Dictionary):
		return false
	var upgrades: Dictionary = raw
	for key: Variant in upgrades.keys():
		if not (key is String):
			return false
		var val: Variant = upgrades[key]
		if not (val is int or val is float):
			return false
		target.hand_upgrade_levels[StringName(key)] = maxi(0, int(val))
	return true


static func _load_rare_hairs(raw: Variant, target: SaveData) -> bool:
	if not (raw is Array):
		return false
	for entry: Variant in raw:
		if not (entry is String):
			return false
		target.found_rare_hair_ids.append(StringName(entry))
	return true


static func _load_building_records(raw: Variant, target: SaveData) -> bool:
	if not (raw is Array):
		return false
	for entry: Variant in raw:
		var parsed: BuildingRecord = BuildingRecordScript.from_dict(entry)
		if parsed == null:
			return false
		target.building_records.append(parsed)
	return true

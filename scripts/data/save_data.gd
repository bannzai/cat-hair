class_name SaveData
extends Resource
## セーブデータ全体。建物をまたいで残る物と、今いる建物の進行・開発者向けの調整値を持つ。

## 終えた建物成績データ型スクリプト
const BuildingRecordScript := preload("res://scripts/data/building_record.gd")
## 建物進行データ型スクリプト
const BuildingProgressScript := preload("res://scripts/data/building_progress.gd")
## 開発者向け調整値データ型スクリプト
const MansionTuningScript := preload("res://scripts/data/mansion_tuning.gd")

## 保存版。版 2 からは初期本数を 12 万本に調整した屋敷も再開できる。
const SCHEMA_VERSION: int = 2
## 描画本数に上限を設ける前、版 1 で新規の屋敷に保存していた初期本数。
const LEGACY_DEFAULT_HAIR_COUNT: int = 120000

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
	for upgrade_key: Variant in hand_upgrade_levels.keys():
		upgrades_out[String(upgrade_key)] = maxi(0, int(hand_upgrade_levels[upgrade_key]))
	var rare_out: Array[String] = []
	for rare_id: StringName in found_rare_hair_ids:
		rare_out.append(String(rare_id))
	var records_out: Array[Dictionary] = []
	for record: BuildingRecord in building_records:
		if record != null:
			records_out.append(record.to_dict())
	return {
		"schema_version": schema_version,
		"hand_upgrade_levels": upgrades_out,
		"found_rare_hair_ids": rare_out,
		"building_records": records_out,
		"building_progress": (
			building_progress.to_dict()
			if building_progress != null
			else BuildingProgressScript.new().to_dict()
		),
		"tuning": tuning.to_dict() if tuning != null else MansionTuningScript.new().to_dict(),
	}


## 辞書から復元する。壊れたデータや未対応スキーマの場合は null を返す
static func from_dict(raw_save_dict: Variant) -> SaveData:
	if not (raw_save_dict is Dictionary):
		return null
	var save_dict: Dictionary = raw_save_dict
	var raw_version: Variant = save_dict.get("schema_version")
	if not (raw_version is int or raw_version is float):
		return null
	if float(raw_version) not in [1.0, float(SCHEMA_VERSION)]:
		return null
	var parsed_progress: BuildingProgress = BuildingProgressScript.from_dict(
		save_dict.get("building_progress")
	)
	if parsed_progress == null:
		return null
	var parsed_tuning: MansionTuning = MansionTuningScript.from_dict(save_dict.get("tuning"))
	if parsed_tuning == null:
		return null
	# 少ない毛で始まった旧版の屋敷だけを作り直す。掃除で減った現在の本数は判定に使わない。
	if float(raw_version) == 1.0 and parsed_tuning.hair_count == LEGACY_DEFAULT_HAIR_COUNT:
		return null
	var save_data: SaveData = SaveData.new()
	save_data.schema_version = SCHEMA_VERSION
	save_data.building_progress = parsed_progress
	save_data.tuning = parsed_tuning
	if not _load_hand_upgrades(save_dict.get("hand_upgrade_levels"), save_data):
		return null
	if not _load_rare_hairs(save_dict.get("found_rare_hair_ids"), save_data):
		return null
	if not _load_building_records(save_dict.get("building_records"), save_data):
		return null
	return save_data


## 手の強化レベル辞書を復元して target_save へ格納する。型が不正なら false
static func _load_hand_upgrades(raw_upgrades: Variant, target_save: SaveData) -> bool:
	if not (raw_upgrades is Dictionary):
		return false
	var upgrades_dict: Dictionary = raw_upgrades
	for upgrade_key: Variant in upgrades_dict.keys():
		if not (upgrade_key is String):
			return false
		var level_value: Variant = upgrades_dict[upgrade_key]
		if not (level_value is int or level_value is float):
			return false
		target_save.hand_upgrade_levels[StringName(upgrade_key)] = maxi(0, int(level_value))
	return true


## 図鑑の珍しい毛 id 配列を復元して target_save へ格納する。要素が不正なら false
static func _load_rare_hairs(raw_rare_ids: Variant, target_save: SaveData) -> bool:
	if not (raw_rare_ids is Array):
		return false
	for rare_entry: Variant in raw_rare_ids:
		if not (rare_entry is String):
			return false
		target_save.found_rare_hair_ids.append(StringName(rare_entry))
	return true


## 建物成績配列を復元して target_save へ格納する。要素が不正なら false
static func _load_building_records(raw_records: Variant, target_save: SaveData) -> bool:
	if not (raw_records is Array):
		return false
	for record_entry: Variant in raw_records:
		var parsed: BuildingRecord = BuildingRecordScript.from_dict(record_entry)
		if parsed == null:
			return false
		target_save.building_records.append(parsed)
	return true

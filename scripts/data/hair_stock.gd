class_name HairStock
extends Resource
## 取ってまだ売っていない毛、または加工した物の在庫 1 種類。

## 加工の形: 取ったままの毛 (PROJECT.md「道具」の毛の加工機に対応)
const FORM_RAW: StringName = &"raw"
## 加工の形: 毛玉
const FORM_BALL: StringName = &"hairball"
## 加工の形: フェルト
const FORM_FELT: StringName = &"felt"
## 加工の形: 猫の毛の人形
const FORM_DOLL: StringName = &"doll"

## 毛の色 (白・黒・三毛・混ざった物)
@export var hair_color: StringName = &""
## 珍しい毛の種類 (ヒゲ・金色の毛等)。ふつうの毛は空
@export var rare_hair_id: StringName = &""
## 形 (毛のまま・毛玉・フェルト・人形)
@export var form: StringName = FORM_RAW
## 数 (毛のままなら本数、加工した物なら個数)
@export var count: int = 0


## JSON 保存用の辞書に変換する
func to_dict() -> Dictionary:
	return {
		"hair_color": String(hair_color),
		"rare_hair_id": String(rare_hair_id),
		"form": String(form),
		"count": maxi(0, count),
	}


## 辞書から復元する。不正な構造の場合は null を返す
static func from_dict(raw_stock_dict: Variant) -> HairStock:
	if not (raw_stock_dict is Dictionary):
		return null
	var stock_dict: Dictionary = raw_stock_dict
	if (
		not (stock_dict.get("hair_color") is String)
		or not (stock_dict.get("rare_hair_id") is String)
		or not (stock_dict.get("form") is String)
	):
		return null
	var raw_count: Variant = stock_dict.get("count")
	if not (raw_count is int or raw_count is float):
		return null
	var stock: HairStock = HairStock.new()
	stock.hair_color = StringName(stock_dict["hair_color"])
	stock.rare_hair_id = StringName(stock_dict["rare_hair_id"])
	stock.form = StringName(stock_dict["form"])
	stock.count = maxi(0, int(raw_count))
	return stock

extends RefCounted
## 手に持って使う道具 8 つの定義 (値段・レベルごとの取りこぼし・得意な表面・消耗品・探し物を傷めるか)。
## 値は触れる版の感想を取るための仮の値で、自動テストプレイ (issue #13) の結果で調整する。
## 掃除ロボットは issue #11、大型の道具は issue #12 が足す。

## 屋敷レイアウト型スクリプト (表面の種類の定数を使う)
const MansionLayoutScript := preload("res://scripts/mansion/mansion_layout.gd")

## 道具の id: 手 (無料。最初から持っている。保存データの owned_tools には入れない)
const TOOL_HAND: StringName = &"hand"
## 道具の id: ピンセット
const TOOL_TWEEZERS: StringName = &"tweezers"
## 道具の id: ガムテープ
const TOOL_PACKING_TAPE: StringName = &"packing_tape"
## 道具の id: ゴム手袋とスポンジ
const TOOL_RUBBER_GLOVE: StringName = &"rubber_glove"
## 道具の id: 粘着ローラー
const TOOL_LINT_ROLLER: StringName = &"lint_roller"
## 道具の id: 掃除機
const TOOL_VACUUM: StringName = &"vacuum"
## 道具の id: 毛を光らせるライト
const TOOL_GLOW_LIGHT: StringName = &"glow_light"
## 道具の id: ブラシ
const TOOL_BRUSH: StringName = &"brush"

## 道具の使い方: 狙った点の近くの毛をつまんで抜く (手。HandController が扱う)
const KIND_HAND: StringName = &"hand"
## 道具の使い方: 狙った点の周りの毛をまとめて取る
const KIND_SWEEP: StringName = &"sweep"
## 道具の使い方: 点けている間、毛を光らせて見つけやすくする
const KIND_LIGHT: StringName = &"light"
## 道具の使い方: 猫をブラッシングして、落ちる前の毛を取る
const KIND_CAT: StringName = &"cat"

## 得意な表面で取りこぼしの割合に掛ける倍率
const GOOD_SURFACE_FACTOR: float = 0.5
## 不得意な表面で取りこぼしの割合に掛ける倍率
const BAD_SURFACE_FACTOR: float = 1.6

## 道具の表。並び順が選ぶキー (1〜8) と買う画面の並び。
## price は買う値段 (円)、radius_m は 1 回かけた時に届く狙いの点からの半径、max_hairs は 1 回で触れる本数の上限、
## base_miss_ratio はレベル 1 で得意でも不得意でもない表面の取りこぼしの割合、good・bad は得意・不得意な表面、
## consumable_name が空でなければ消耗品を使う (initial_consumables は買った時の数、refill_price・refill_count は
## 買い足す値段と増える数)、damages_found_items は探し物にかけると傷めるか
const TOOLS: Array[Dictionary] = [
	{
		"id": TOOL_HAND,
		"name": "手",
		"kind": KIND_HAND,
		"price": 0,
		"radius_m": 0.0,
		"max_hairs": 0,
		"base_miss_ratio": 0.0,
		"good": [],
		"bad": [],
		"consumable_name": "",
		"initial_consumables": 0,
		"refill_price": 0,
		"refill_count": 0,
		"damages_found_items": false,
	},
	{
		"id": TOOL_TWEEZERS,
		"name": "ピンセット",
		"kind": KIND_SWEEP,
		"price": 30,
		"radius_m": 0.12,
		"max_hairs": 4,
		"base_miss_ratio": 0.3,
		"good": [MansionLayoutScript.SURFACE_KNIT, MansionLayoutScript.SURFACE_CARPET],
		"bad": [MansionLayoutScript.SURFACE_FLOOR],
		"consumable_name": "",
		"initial_consumables": 0,
		"refill_price": 0,
		"refill_count": 0,
		"damages_found_items": false,
	},
	{
		"id": TOOL_PACKING_TAPE,
		"name": "ガムテープ",
		"kind": KIND_SWEEP,
		"price": 60,
		"radius_m": 0.18,
		"max_hairs": 25,
		"base_miss_ratio": 0.45,
		"good": [MansionLayoutScript.SURFACE_SOFA, MansionLayoutScript.SURFACE_SUIT],
		"bad": [MansionLayoutScript.SURFACE_CARPET, MansionLayoutScript.SURFACE_KNIT],
		"consumable_name": "",
		"initial_consumables": 0,
		"refill_price": 0,
		"refill_count": 0,
		"damages_found_items": true,
	},
	{
		"id": TOOL_RUBBER_GLOVE,
		"name": "ゴム手袋とスポンジ",
		"kind": KIND_SWEEP,
		"price": 120,
		"radius_m": 0.25,
		"max_hairs": 40,
		"base_miss_ratio": 0.4,
		"good": [MansionLayoutScript.SURFACE_SOFA, MansionLayoutScript.SURFACE_CARPET],
		"bad": [MansionLayoutScript.SURFACE_SUIT],
		"consumable_name": "",
		"initial_consumables": 0,
		"refill_price": 0,
		"refill_count": 0,
		"damages_found_items": false,
	},
	{
		"id": TOOL_LINT_ROLLER,
		"name": "粘着ローラー",
		"kind": KIND_SWEEP,
		"price": 150,
		"radius_m": 0.3,
		"max_hairs": 60,
		"base_miss_ratio": 0.35,
		"good": [
			MansionLayoutScript.SURFACE_SUIT,
			MansionLayoutScript.SURFACE_SOFA,
			MansionLayoutScript.SURFACE_KNIT,
		],
		"bad": [MansionLayoutScript.SURFACE_FLOOR],
		"consumable_name": "紙",
		"initial_consumables": 20,
		"refill_price": 10,
		"refill_count": 20,
		"damages_found_items": false,
	},
	{
		"id": TOOL_VACUUM,
		"name": "掃除機",
		"kind": KIND_SWEEP,
		"price": 400,
		"radius_m": 0.5,
		"max_hairs": 200,
		"base_miss_ratio": 0.4,
		"good": [MansionLayoutScript.SURFACE_FLOOR, MansionLayoutScript.SURFACE_CARPET],
		"bad": [MansionLayoutScript.SURFACE_KNIT, MansionLayoutScript.SURFACE_SUIT],
		"consumable_name": "",
		"initial_consumables": 0,
		"refill_price": 0,
		"refill_count": 0,
		"damages_found_items": true,
	},
	{
		"id": TOOL_GLOW_LIGHT,
		"name": "毛を光らせるライト",
		"kind": KIND_LIGHT,
		"price": 80,
		"radius_m": 0.0,
		"max_hairs": 0,
		"base_miss_ratio": 0.0,
		"good": [],
		"bad": [],
		"consumable_name": "",
		"initial_consumables": 0,
		"refill_price": 0,
		"refill_count": 0,
		"damages_found_items": false,
	},
	{
		"id": TOOL_BRUSH,
		"name": "ブラシ",
		"kind": KIND_CAT,
		"price": 100,
		"radius_m": 0.0,
		"max_hairs": 0,
		"base_miss_ratio": 0.0,
		"good": [],
		"bad": [],
		"consumable_name": "",
		"initial_consumables": 0,
		"refill_price": 0,
		"refill_count": 0,
		"damages_found_items": false,
	},
]


## 道具の id から定義を返す (表に無い id は空の辞書)
static func find_tool(tool_id: StringName) -> Dictionary:
	for tool_def: Dictionary in TOOLS:
		if tool_def["id"] == tool_id:
			return tool_def
	return {}


## 道具の id を表の順に返す
static func all_tool_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for tool_def: Dictionary in TOOLS:
		ids.append(tool_def["id"])
	return ids

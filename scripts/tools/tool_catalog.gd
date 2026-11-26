extends RefCounted
## 道具の定義 (値段・レベルごとの取りこぼし・得意な表面・消耗品・探し物を傷めるか)。手に持って使う道具 8 つと、
## 大型の道具 (業務用の吸引車・建物を覆う粘着シート・アンドロイド・毛の加工機・毛を運ぶダンプカー) を持つ。
## 値は触れる版の感想を取るための仮の値で、自動テストプレイ (issue #13) の結果で調整する。
## 掃除ロボットは issue #11 が足す。

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
## 道具の id: 業務用の吸引車
const TOOL_SUCTION_TRUCK: StringName = &"suction_truck"
## 道具の id: 建物を覆う粘着シート
const TOOL_ADHESIVE_SHEET: StringName = &"adhesive_sheet"
## 道具の id: アンドロイド
const TOOL_ANDROID: StringName = &"android"
## 道具の id: 毛の加工機
const TOOL_HAIR_PROCESSOR: StringName = &"hair_processor"
## 道具の id: 毛を運ぶダンプカー
const TOOL_DUMP_TRUCK: StringName = &"dump_truck"

## 道具の使い方: 狙った点の近くの毛をつまんで抜く (手。HandController が扱う)
const KIND_HAND: StringName = &"hand"
## 道具の使い方: 狙った点の周りの毛をまとめて取る
const KIND_SWEEP: StringName = &"sweep"
## 道具の使い方: 点けている間、毛を光らせて見つけやすくする
const KIND_LIGHT: StringName = &"light"
## 道具の使い方: 猫をブラッシングして、落ちる前の毛を取る
const KIND_CAT: StringName = &"cat"
## 道具の使い方: 建物の外から太いホースで、今いる部屋のすべての表面の毛を吸う (運転席から使う)
const KIND_ROOM: StringName = &"room"
## 道具の使い方: 今いる部屋の床一面に敷き、床とカーペットに落ちた毛を捕まえる (1 回敷くとシートを 1 枚使う)
const KIND_SHEET: StringName = &"sheet"
## 道具の使い方: 持っていると、毛のいちばん多い部屋を選んで自動で掃除し続ける
const KIND_AUTO: StringName = &"auto"
## 道具の使い方: 持っていると、在庫の毛を時間ごとに加工する (並べるほど多く加工できる)
const KIND_PROCESS: StringName = &"process"
## 道具の使い方: 在庫を積み、加工場と売り先へ運び出して売る (どこからでも呼べる)
const KIND_TRANSPORT: StringName = &"transport"
## 1〜0 キーで選んで使う道具の使い方 (アンドロイド・加工機・ダンプカーは選ばずに働く)
const SELECTABLE_KINDS: Array[StringName] = [
	KIND_HAND, KIND_SWEEP, KIND_LIGHT, KIND_CAT, KIND_ROOM, KIND_SHEET
]
## 道具の表の先頭から、手に持って使う道具 (手〜ブラシ) の数。後ろに大型の道具が並ぶ
const HAND_HELD_TOOL_COUNT: int = 8
## 毛を取る道具の使い方 (取りこぼしとレベルがある)
const HAIR_REMOVING_KINDS: Array[StringName] = [KIND_SWEEP, KIND_ROOM, KIND_SHEET, KIND_AUTO]

## 得意な表面で取りこぼしの割合に掛ける倍率。得意な表面にかけると残る毛が半分になり、表面ごとに道具を持ち替える理由が 1 回で見える
const GOOD_SURFACE_FACTOR: float = 0.5
## 不得意な表面で取りこぼしの割合に掛ける倍率。取りこぼしの多い道具 (45%) でも上限 90% を超えない最大の倍率に近い値
const BAD_SURFACE_FACTOR: float = 1.6

## 道具の表。並び順が選ぶキー (選べる道具の 1〜9・0) と買う画面の並び。
## price は買う値段 (円)、radius_m は 1 回かけた時に届く狙いの点からの半径、max_hairs は 1 回で触れる本数の上限
## (部屋ごとにかける道具は表面 1 つあたり)、base_miss_ratio はレベル 1 で得意でも不得意でもない表面の取りこぼしの割合、
## good・bad は得意・不得意な表面、consumable_name が空でなければ消耗品を使う (initial_consumables は買った時の数、
## refill_price・refill_count は買い足す値段と増える数)、damages_found_items は探し物にかけると傷めるか。
## max_owned がある道具は同じ物を max_owned 台まで並べて持てる (無い道具は 1 つ)
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
	{
		"id": TOOL_SUCTION_TRUCK,
		"name": "業務用の吸引車",
		"kind": KIND_ROOM,
		"price": 3000,
		"radius_m": 0.0,
		"max_hairs": 400,
		"base_miss_ratio": 0.35,
		"good": [
			MansionLayoutScript.SURFACE_FLOOR,
			MansionLayoutScript.SURFACE_CARPET,
			MansionLayoutScript.SURFACE_SOFA,
		],
		"bad": [MansionLayoutScript.SURFACE_KNIT, MansionLayoutScript.SURFACE_SUIT],
		"consumable_name": "",
		"initial_consumables": 0,
		"refill_price": 0,
		"refill_count": 0,
		"damages_found_items": true,
	},
	{
		"id": TOOL_ADHESIVE_SHEET,
		"name": "建物を覆う粘着シート",
		"kind": KIND_SHEET,
		"price": 1500,
		"radius_m": 0.0,
		"max_hairs": 600,
		"base_miss_ratio": 0.3,
		"good": [MansionLayoutScript.SURFACE_FLOOR, MansionLayoutScript.SURFACE_CARPET],
		"bad": [],
		"consumable_name": "シート",
		"initial_consumables": 3,
		"refill_price": 200,
		"refill_count": 3,
		"damages_found_items": false,
	},
	{
		"id": TOOL_ANDROID,
		"name": "アンドロイド",
		"kind": KIND_AUTO,
		"price": 20000,
		"radius_m": 0.0,
		"max_hairs": 30,
		"base_miss_ratio": 0.4,
		"good": [
			MansionLayoutScript.SURFACE_FLOOR,
			MansionLayoutScript.SURFACE_CARPET,
			MansionLayoutScript.SURFACE_SOFA,
			MansionLayoutScript.SURFACE_KNIT,
			MansionLayoutScript.SURFACE_SUIT,
			MansionLayoutScript.SURFACE_FURNITURE,
		],
		"bad": [],
		"consumable_name": "",
		"initial_consumables": 0,
		"refill_price": 0,
		"refill_count": 0,
		"damages_found_items": false,
	},
	{
		"id": TOOL_HAIR_PROCESSOR,
		"name": "毛の加工機",
		"kind": KIND_PROCESS,
		"price": 800,
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
		"max_owned": 6,
	},
	{
		"id": TOOL_DUMP_TRUCK,
		"name": "毛を運ぶダンプカー",
		"kind": KIND_TRANSPORT,
		"price": 2500,
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


## キーで選んで使う道具の id を表の順に返す (並びの位置がキーの 1〜9・0)
static func selectable_tool_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for tool_def: Dictionary in TOOLS:
		if SELECTABLE_KINDS.has(tool_def["kind"]):
			ids.append(tool_def["id"])
	return ids


## 手に持って使う道具 (表の先頭の HAND_HELD_TOOL_COUNT 個) の定義を表の順に返す
static func hand_held_tools() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index: int in range(HAND_HELD_TOOL_COUNT):
		result.append(TOOLS[index])
	return result


## 同じ道具を並べて持てる数を返す (表に無い道具は 0)
static func max_owned(tool_id: StringName) -> int:
	var tool_def: Dictionary = find_tool(tool_id)
	return int(tool_def.get("max_owned", 1)) if not tool_def.is_empty() else 0

extends RefCounted
## 次の建物へ進む決まり (進める条件・成績・持ち越す手の強化・次の建物の作り) の計算。
## 状態を持たない純粋な計算だけを置き、selfcheck が入力と出力で検証する (PROJECT.md「建物と進み方」)。

## 建物進行データ型スクリプト (屋敷の id)
const BuildingProgressScript := preload("res://scripts/data/building_progress.gd")
## 終えた建物成績データ型スクリプト
const BuildingRecordScript := preload("res://scripts/data/building_record.gd")
## 探し物進捗データ型スクリプト
const FoundItemProgressScript := preload("res://scripts/data/found_item_progress.gd")
## 開発者向け調整値データ型スクリプト
const MansionTuningScript := preload("res://scripts/data/mansion_tuning.gd")
## 掃除代・機嫌の計算 (ご機嫌の線)
const EconomyRulesScript := preload("res://scripts/economy/economy_rules.gd")
## 手で毛を取る時のルールの計算 (手の強化の id)
const HandRulesScript := preload("res://scripts/hand/hand_rules.gd")
## 手に持って使う道具のルールの計算 (手の強化の段の上限)
const ToolRulesScript := preload("res://scripts/tools/tool_rules.gd")

## 2 つ目の建物の id (ホテル)
const BUILDING_HOTEL: StringName = &"hotel"
## 3 つ目の建物の id (猫島)
const BUILDING_CAT_ISLAND: StringName = &"cat_island"
## 4 つ目の建物の id (街全体)
const BUILDING_CITY: StringName = &"city"
## 建物の並び (PROJECT.md「建物と進み方」の owner の決定)。n 番目 (0 始まり) は、終えた建物が n 個の時にいる建物
const BUILDING_ORDER: Array[StringName] = [
	BuildingProgressScript.BUILDING_MANSION,
	BUILDING_HOTEL,
	BUILDING_CAT_ISLAND,
	BUILDING_CITY,
]
## 建物の表示名
const BUILDING_NAMES: Dictionary = {
	BuildingProgressScript.BUILDING_MANSION: "屋敷",
	BUILDING_HOTEL: "ホテル",
	BUILDING_CAT_ISLAND: "猫島",
	BUILDING_CITY: "街全体",
}
## 建物が 1 つ進むごとに増やす部屋の数。建物そのもの (#17) を作るまでは、屋敷の部屋を増やした物を次の建物にする。
## 毛・物・探し物の数は部屋の数に比例させ、部屋あたりの量を最初の屋敷と同じにする。
## 2 にしたのは、既定 (MansionTuning.DEFAULT_ROOM_COUNT = 4) の屋敷から街全体 (3 つ進んだ 10 部屋) まで、
## 部屋の上限 (MansionTuning.MAX_ROOM_COUNT = 16) で丸めずに建物ごとに広くなるため。
## 値は建物そのものを作る #17 で建物ごとの作りに置き換える
const EXTRA_ROOMS_PER_BUILDING: int = 2
## 住人に返した探し物 1 つにつき持ち越しで足す手の強化の段の数。1 にしたのは、屋敷の既定の探し物
## (MansionTuning.DEFAULT_FOUND_ITEM_COUNT = 5 個) を全部返しても、2 種類の強化の合計の上限 18 段の 3 割弱にとどまり、
## 持ち越しだけで手の強化を買う楽しみが無くならないため
const HAND_LEVELS_PER_RETURNED_ITEM: int = 1


## 終えた建物の数 finished_count から、今いる建物の並びの番号 (0 始まり。最後の建物より先へは進まない) を返す
static func building_index(finished_count: int) -> int:
	return clampi(finished_count, 0, BUILDING_ORDER.size() - 1)


## 並びの番号 index の建物の id を返す
static func building_id_at(index: int) -> StringName:
	return BUILDING_ORDER[building_index(index)]


## 並びの番号 index の建物の次に建物があるか (最後の建物ではエンディング (#17) になり、次へは進まない)
static func has_next_building(index: int) -> bool:
	return index >= 0 and index < BUILDING_ORDER.size() - 1


## 建物 building_id の表示名 (並びに無い id はそのまま)
static func building_name(building_id: StringName) -> String:
	return str(BUILDING_NAMES.get(building_id, String(building_id)))


## 開発者向けの調整値 base_tuning (最初の屋敷の作り) から、並びの番号 index の建物の作りを返す。
## 部屋を EXTRA_ROOMS_PER_BUILDING ずつ増やし、毛・物・探し物の数を部屋の数に比例させる (どれも上限で丸める)
static func building_tuning(base_tuning: MansionTuning, index: int) -> MansionTuning:
	var base: MansionTuning = (
		base_tuning.clamped() if base_tuning != null else MansionTuningScript.new()
	)
	var result: MansionTuning = base.clamped()
	result.room_count = base.room_count + EXTRA_ROOMS_PER_BUILDING * building_index(index)
	result = result.clamped()
	var room_ratio: float = float(result.room_count) / float(base.room_count)
	result.hair_count = roundi(float(base.hair_count) * room_ratio)
	result.object_count = roundi(float(base.object_count) * room_ratio)
	result.found_item_count = roundi(float(base.found_item_count) * room_ratio)
	return result.clamped()


## 住人の機嫌の一覧 moods (0〜1) で、住人が 1 人以上いて全員がご機嫌か
static func everyone_happy(moods: Array[float]) -> bool:
	if moods.is_empty():
		return false
	for mood: float in moods:
		if not EconomyRulesScript.is_happy(mood):
			return false
	return true


## 今いる建物 (並びの番号 index) から次の建物へ進めるか。進むのに要るのは住人全員がご機嫌なことだけ
static func can_advance(index: int, moods: Array[float]) -> bool:
	return has_next_building(index) and everyone_happy(moods)


## 探し物の一覧 found_items のうち、住人に返した数 (探し物がまだ無い時は 0)
static func returned_found_item_count(found_items: Array[FoundItemProgress]) -> int:
	var count: int = 0
	for item: FoundItemProgress in found_items:
		if item != null and item.is_returned:
			count += 1
	return count


## 今いる建物の進行 progress から成績を作る。かかった時間は進んだ時までにこの建物で遊んだ時間 (報酬には効かない)
static func make_record(progress: BuildingProgress) -> BuildingRecord:
	var record: BuildingRecord = BuildingRecordScript.new()
	record.building_id = progress.building_id
	record.clear_seconds = maxf(0.0, progress.elapsed_seconds)
	record.returned_found_item_count = returned_found_item_count(progress.found_items)
	return record


## 次の建物へ持ち越す手の強化の段 (強化の id -> 段) を返す。levels は今の段 (買った段) で、そのまま残す。
## そこへ住人に返した探し物の数 returned_count × HAND_LEVELS_PER_RETURNED_ITEM 段を、1 段ずつ段のいちばん低い
## 強化に足す (上限 ToolRules.MAX_HAND_UPGRADE_LEVEL の段には足さず、全部が上限なら足しきれない分は捨てる)。levels は変えない
static func carried_hand_upgrades(levels: Dictionary, returned_count: int) -> Dictionary:
	var carried: Dictionary = {}
	for upgrade_key: Variant in levels.keys():
		carried[upgrade_key] = HandRulesScript.upgrade_level(levels, StringName(upgrade_key))
	for _bonus: int in range(maxi(0, returned_count) * HAND_LEVELS_PER_RETURNED_ITEM):
		var lowest_id: StringName = &""
		for upgrade_id: StringName in HandRulesScript.UPGRADE_IDS:
			var level: int = HandRulesScript.upgrade_level(carried, upgrade_id)
			if level >= ToolRulesScript.MAX_HAND_UPGRADE_LEVEL:
				continue
			if lowest_id == &"" or level < HandRulesScript.upgrade_level(carried, lowest_id):
				lowest_id = upgrade_id
		if lowest_id == &"":
			break
		carried[lowest_id] = HandRulesScript.upgrade_level(carried, lowest_id) + 1
	return carried

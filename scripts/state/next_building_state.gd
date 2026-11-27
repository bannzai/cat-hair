extends RefCounted
## GameState が持つ、次の建物へ進む入口 (GameState.next_building)。
## 状態は持たず、正は GameState の保存データ (終えた建物の成績・手の強化・今いる建物の進行) にある。
## 今いる建物は終えた建物の数で決まり、その建物の作りは開発者向けの調整値 (最初の屋敷の作り) から求める (BuildingRules)。

## 次の建物へ進む決まりの計算
const BuildingRulesScript := preload("res://scripts/building/building_rules.gd")

## 保存データと屋敷の作り直しの入口を持つ GameState (Node のため参照の循環で解放が止まらない)
var _game_state: Node = null


## game_state は持ち主の GameState
func _init(game_state: Node) -> void:
	_game_state = game_state


## 今いる建物の並びの番号 (0 = 屋敷)
func building_index() -> int:
	if _game_state.save_data == null:
		return 0
	return BuildingRulesScript.building_index(_game_state.save_data.building_records.size())


## 住人ごとの機嫌の一覧 (今の屋敷の作りの部屋の順)
func resident_moods() -> Array[float]:
	var moods: Array[float] = []
	if _game_state.current_layout == null:
		return moods
	for room: MansionLayout.RoomDef in _game_state.current_layout.rooms:
		moods.append(float(_game_state.get_room_status(room.room_id)["mood"]))
	return moods


## 住人全員がご機嫌か
func everyone_happy() -> bool:
	return BuildingRulesScript.everyone_happy(resident_moods())


## 次の建物へ進めるか (住人全員がご機嫌で、次の建物がある)
func can_advance() -> bool:
	return (
		_game_state.save_data != null
		and _game_state.save_data.building_progress != null
		and BuildingRulesScript.can_advance(building_index(), resident_moods())
	)


## 次の建物へ進む。今の建物の成績を記録し、手の強化に探し物を返した数の分を足して持ち越し、図鑑と成績を残して、
## お金と道具を置いていった次の建物を組み立てて保存する。戻り値は記録した成績 (進めない時は何も変えずに null)
func advance() -> BuildingRecord:
	if not can_advance():
		return null
	var save_data: SaveData = _game_state.save_data
	var record: BuildingRecord = BuildingRulesScript.make_record(save_data.building_progress)
	save_data.hand_upgrade_levels = BuildingRulesScript.carried_hand_upgrades(
		save_data.hand_upgrade_levels, record.returned_found_item_count
	)
	save_data.building_records.append(record)
	# 調整値は最初の屋敷の作りのまま渡し、終えた建物の数が 1 つ増えたことで次の建物の作りになる
	_game_state.apply_tuning_and_rebuild(_game_state.get_tuning(), true)
	return record

extends RefCounted
## 住人の依頼 (探し物・黒いスーツの服の毛・逃げた猫) の状態と入口。GameState が 1 つ持ち、保存する値は
## BuildingProgress (探し物の状態・取り切ったスーツの面・猫を届けたか) に置く。猫を抱えているかは保存せず、
## 読み込んだ時は隠れている所に戻る。計算は RequestRules が持つ。

## 依頼の計算
const RequestRulesScript := preload("res://scripts/requests/request_rules.gd")
## 探し物の状態の型 (Condition の定数)
const FoundItemProgressScript := preload("res://scripts/data/found_item_progress.gd")
## 屋敷ビルダー (部屋の住人の id)
const MansionBuilderScript := preload("res://scripts/mansion/mansion_builder.gd")

## 出来事の種類: 探し物が毛の上に出てきた ({"kind", "found_item_id"})
const EVENT_REVEALED: StringName = &"revealed"
## 出来事の種類: 道具で探し物を取った ({"kind", "found_item_id", "condition"})
const EVENT_TAKEN: StringName = &"taken"
## 出来事の種類: 探し物を返し、お礼が次の掃除代に上乗せされた ({"kind", "found_item_id", "reward"})
const EVENT_RETURNED: StringName = &"returned"
## 出来事の種類: スーツの毛を取り切り、次の掃除代に上乗せされた ({"kind", "surface_id", "reward"})
const EVENT_SUIT_CLEARED: StringName = &"suit_cleared"
## 出来事の種類: 猫が逃げた ({"kind", "cat_id"})
const EVENT_CAT_ESCAPED: StringName = &"cat_escaped"
## 出来事の種類: 隠れていた逃げた猫を抱えた ({"kind", "cat_id"})
const EVENT_CAT_CARRIED: StringName = &"cat_carried"
## 出来事の種類: 逃げた猫を持ち主に届けた ({"kind", "cat_id", "room_id"})
const EVENT_CAT_RETURNED: StringName = &"cat_returned"

## 持ち主の GameState
var _game_state: Node = null
## 逃げた猫を抱えているか (保存しない)
var _carrying_cat: bool = false


## game_state は持ち主の GameState
func _init(game_state: Node) -> void:
	_game_state = game_state


## 屋敷を組み直した・読み込んだ時に、抱えている猫を下ろし、毛の残りで出てくる探し物を出す
func reset() -> void:
	_carrying_cat = false
	after_hairs_removed()


## 探し物 found_item_id の状態を返す (無ければ null)
func find_item(found_item_id: StringName) -> FoundItemProgress:
	var progress: BuildingProgress = _progress()
	if progress == null:
		return null
	for item: FoundItemProgress in progress.found_items:
		if item != null and item.found_item_id == found_item_id:
			return item
	return null


## 探し物 found_item_id の置き場所を返す (無ければ null)
func find_spot(found_item_id: StringName) -> MansionLayout.FoundItemSpotDef:
	var layout: MansionLayout = _game_state.current_layout
	if layout == null:
		return null
	for spot: MansionLayout.FoundItemSpotDef in layout.found_item_spots:
		if spot.found_item_id == found_item_id:
			return spot
	return null


## まだ持ち主に返していない探し物の数 (依頼の一覧の「残り」)
func remaining_item_count() -> int:
	var progress: BuildingProgress = _progress()
	if progress == null:
		return 0
	var remaining: int = 0
	for item: FoundItemProgress in progress.found_items:
		if item != null and not item.is_returned:
			remaining += 1
	return remaining


## 毛が減った後に呼ぶ。埋めた面の毛が RequestRules.REVEAL_REMAINING_RATIO まで減った探し物を出し (一度出たら埋もれ直さない)、
## 出かける前にスーツの毛が 0 本になった依頼の上乗せを払う。変わった時だけ出来事を通知する
func after_hairs_removed() -> void:
	var progress: BuildingProgress = _progress()
	if progress == null or _game_state.current_layout == null:
		return
	for item: FoundItemProgress in progress.found_items:
		if item == null or item.condition != FoundItemProgressScript.Condition.HIDDEN:
			continue
		var spot: MansionLayout.FoundItemSpotDef = find_spot(item.found_item_id)
		if spot != null and RequestRulesScript.is_revealed(
			_game_state.get_surface_hair_count(spot.surface_id),
			_game_state.automation.get_initial_surface_hairs(spot.surface_id),
		):
			item.condition = FoundItemProgressScript.Condition.FOUND
			_emit({"kind": EVENT_REVEALED, "found_item_id": item.found_item_id})
	for suit: MansionLayout.SurfaceDef in RequestRulesScript.suit_surfaces(_game_state.current_layout):
		if (
			not progress.cleared_suit_surface_ids.has(suit.surface_id)
			and _game_state.automation.get_initial_surface_hairs(suit.surface_id) > 0
			and RequestRulesScript.suit_cleared_now(
				_game_state.get_surface_hair_count(suit.surface_id), progress.elapsed_seconds
			)
		):
			progress.cleared_suit_surface_ids.append(suit.surface_id)
			_add_pending_reward(suit.room_id, RequestRulesScript.SUIT_BONUS)
			_emit({
				"kind": EVENT_SUIT_CLEARED,
				"surface_id": suit.surface_id,
				"reward": RequestRulesScript.SUIT_BONUS,
			})


## 道具 tool_id を探し物 found_item_ids にかけた結果で状態を変え (RequestRules.condition_after_tool)、取った探し物を
## 出来事で通知する。毛を減らした後 (after_hairs_removed の後) に呼ぶ。戻り値は状態が変わった探し物の id
func apply_tool(tool_id: StringName, found_item_ids: Array[StringName]) -> Array[StringName]:
	var changed: Array[StringName] = []
	for found_item_id: StringName in found_item_ids:
		var item: FoundItemProgress = find_item(found_item_id)
		if item == null:
			continue
		var after: FoundItemProgress.Condition = RequestRulesScript.condition_after_tool(
			RequestRulesScript.kind_for_item_id(found_item_id), tool_id, item.condition
		)
		if after == item.condition:
			continue
		item.condition = after
		changed.append(found_item_id)
		_emit({"kind": EVENT_TAKEN, "found_item_id": found_item_id, "condition": after})
	return changed


## 面 surface_id の点 point から半径 radius の道具の範囲に入る探し物の id を返す
func items_in_reach(surface_id: StringName, point: Vector3, radius: float) -> Array[StringName]:
	var ids: Array[StringName] = []
	if _game_state.current_layout != null:
		for spot: MansionLayout.FoundItemSpotDef in _game_state.current_layout.found_item_spots:
			if RequestRulesScript.is_in_reach(spot, surface_id, point, radius):
				ids.append(spot.found_item_id)
	return ids


## 面 surface_ids (部屋ごとにかける道具がかかった面) に埋めた探し物の id を返す
func items_on_surfaces(surface_ids: Array) -> Array[StringName]:
	var ids: Array[StringName] = []
	if _game_state.current_layout != null:
		for spot: MansionLayout.FoundItemSpotDef in _game_state.current_layout.found_item_spots:
			if surface_ids.has(spot.surface_id):
				ids.append(spot.found_item_id)
	return ids


## 取った探し物 found_item_id を、持ち主の部屋 (今いる部屋 room_id) で返し、お礼 (RequestRules.reward) を持ち主の住人の
## 次の掃除代に上乗せする (掃除代を払う時に所持金へ入る)。
## 戻り値はお礼 (円)。取っていない・返した・持ち主の部屋にいない時は何も変えずに 0
func return_item(found_item_id: StringName, room_id: StringName) -> int:
	var item: FoundItemProgress = find_item(found_item_id)
	var spot: MansionLayout.FoundItemSpotDef = find_spot(found_item_id)
	if item == null or spot == null or item.is_returned or spot.room_id != room_id:
		return 0
	var paid: int = RequestRulesScript.reward(item.condition)
	if paid <= 0:
		return 0
	item.is_returned = true
	_add_pending_reward(room_id, paid)
	_emit({"kind": EVENT_RETURNED, "found_item_id": found_item_id, "reward": paid})
	_game_state.state_changed.emit()
	return paid


## 黒いスーツの服の毛の依頼を表の順に返す。要素は {"surface_id", "room_id", "remaining": 残りの本数,
## "status": RequestRules.suit_status, "seconds_left": 出かけるまでの秒}。最初から毛の無いスーツは依頼にしない
func suit_requests() -> Array[Dictionary]:
	var requests: Array[Dictionary] = []
	var progress: BuildingProgress = _progress()
	if progress == null:
		return requests
	for suit: MansionLayout.SurfaceDef in RequestRulesScript.suit_surfaces(_game_state.current_layout):
		if _game_state.automation.get_initial_surface_hairs(suit.surface_id) <= 0:
			continue
		requests.append({
			"surface_id": suit.surface_id,
			"room_id": suit.room_id,
			"remaining": _game_state.get_surface_hair_count(suit.surface_id),
			"status": RequestRulesScript.suit_status(
				progress.cleared_suit_surface_ids.has(suit.surface_id), progress.elapsed_seconds
			),
			"seconds_left": maxf(
				0.0, RequestRulesScript.SUIT_DEADLINE_SECONDS - progress.elapsed_seconds
			),
		})
	return requests


## 遊んだ時間が elapsed_before 秒から elapsed_after 秒へ進んだ時に呼ぶ。猫が逃げ出す時刻をまたいだら知らせる
func after_time_advanced(elapsed_before: float, elapsed_after: float) -> void:
	var progress: BuildingProgress = _progress()
	if (
		progress != null
		and not progress.runaway_cat_returned
		and _game_state.current_layout != null
		and not _game_state.current_layout.rooms.is_empty()
		and elapsed_before < RequestRulesScript.RUNAWAY_START_SECONDS
		and elapsed_after >= RequestRulesScript.RUNAWAY_START_SECONDS
	):
		_emit({"kind": EVENT_CAT_ESCAPED, "cat_id": RequestRulesScript.runaway_cat_id()})


## 逃げた猫の状態 (RequestRules.runaway_status)。部屋の無い屋敷では &"home"
func runaway_status() -> StringName:
	var progress: BuildingProgress = _progress()
	var layout: MansionLayout = _game_state.current_layout
	if progress == null or layout == null or layout.rooms.is_empty():
		return &"home"
	return RequestRulesScript.runaway_status(
		progress.runaway_cat_returned, _carrying_cat, progress.elapsed_seconds
	)


## 猫 cat_id が通り道を離れている (逃げて隠れているか抱えられている) か。離れている猫は毛を落とさない
func is_cat_away(cat_id: StringName) -> bool:
	return (
		cat_id == RequestRulesScript.runaway_cat_id()
		and runaway_status() in [&"escaped", &"carried"]
	)


## 隠れている逃げた猫を抱える。抱えたら true (猫が逃げていない・もう抱えている・届けた後は false)
func carry_runaway_cat() -> bool:
	if runaway_status() != &"escaped":
		return false
	_carrying_cat = true
	_emit({"kind": EVENT_CAT_CARRIED, "cat_id": RequestRulesScript.runaway_cat_id()})
	_game_state.state_changed.emit()
	return true


## 抱えている逃げた猫を、今いる部屋 room_id が持ち主の部屋なら届け、持ち主の住人をご機嫌にする。届けたら true
func deliver_runaway_cat(room_id: StringName) -> bool:
	var owner_room: MansionLayout.RoomDef = RequestRulesScript.runaway_owner_room(
		_game_state.current_layout
	)
	if runaway_status() != &"carried" or owner_room == null or owner_room.room_id != room_id:
		return false
	_carrying_cat = false
	var progress: BuildingProgress = _progress()
	progress.runaway_cat_returned = true
	progress.resident_moods[MansionBuilderScript.resident_id_for_room(room_id)] = (
		RequestRulesScript.RUNAWAY_RETURN_MOOD
	)
	_emit({
		"kind": EVENT_CAT_RETURNED,
		"cat_id": RequestRulesScript.runaway_cat_id(),
		"room_id": room_id,
	})
	_game_state.state_changed.emit()
	return true


## 部屋 room_id の住人が次の掃除代に上乗せするお礼 (円)
func pending_reward(room_id: StringName) -> int:
	var progress: BuildingProgress = _progress()
	if progress == null:
		return 0
	return int(progress.pending_rewards.get(MansionBuilderScript.resident_id_for_room(room_id), 0))


## 部屋 room_id の住人が掃除代を払う時に呼ぶ。上乗せするお礼 (円) を返して消す
func take_pending_reward(room_id: StringName) -> int:
	var amount: int = pending_reward(room_id)
	if amount > 0:
		_progress().pending_rewards.erase(MansionBuilderScript.resident_id_for_room(room_id))
	return amount


## 部屋 room_id の住人の次の掃除代に amount 円を上乗せする
func _add_pending_reward(room_id: StringName, amount: int) -> void:
	var resident: StringName = MansionBuilderScript.resident_id_for_room(room_id)
	var progress: BuildingProgress = _progress()
	progress.pending_rewards[resident] = int(progress.pending_rewards.get(resident, 0)) + amount


## GameState の保存データの進行 (読み込み前は null)
func _progress() -> BuildingProgress:
	var save_data: SaveData = _game_state.save_data
	return save_data.building_progress if save_data != null else null


## 出来事を GameState の request_event で知らせる。state_changed は出さない (毛を減らす GameState の入口が 1 回の操作で
## 1 回だけ知らせる決まりを保つため。依頼の見た目は RequestController が request_event で描き直す)
func _emit(event: Dictionary) -> void:
	_game_state.request_event.emit(event)

extends RefCounted
## 住人の依頼の計算 (純粋な計算。状態は RequestState、見た目は RequestController が持つ)。
## 依頼は 3 種類: 毛の山から出てくる探し物を返す、黒いスーツの服の毛を出かける前に取り切る、逃げた猫を連れ戻す。
## 値段・秒数は触れる版の感想を取るための仮の値で、自動テストプレイ (make simulate) の結果で調整する

## 探し物の状態の型 (Condition の定数)
const FoundItemProgressScript := preload("res://scripts/data/found_item_progress.gd")
## 道具の定義 (道具の id)
const ToolCatalogScript := preload("res://scripts/tools/tool_catalog.gd")
## 道具のルールの計算 (探し物を傷める道具か)
const ToolRulesScript := preload("res://scripts/tools/tool_rules.gd")
## 屋敷レイアウト型スクリプト (表面の種類の定数)
const MansionLayoutScript := preload("res://scripts/mansion/mansion_layout.gd")
## 猫の通り道の計算 (猫の表と、部屋の中の空いた所)
const CatRulesScript := preload("res://scripts/automation/cat_rules.gd")

## 探し物の分類: 衣類のように毛が付きやすい物
const CATEGORY_CLOTH: StringName = &"cloth"
## 探し物の分類: 機械のように毛が入ると壊れやすい物
const CATEGORY_MACHINE: StringName = &"machine"
## 探し物の種類。置き場所の番号の順に繰り返して割り当てる。match_tool は丁寧に取れる道具
## (衣類は毛を巻き取る粘着ローラー、機械は隙間の毛を 1 本ずつ抜くピンセット。PROJECT.md「道具」)。
## color は屋敷に置く見た目の色
const ITEM_KINDS: Array[Dictionary] = [
	{
		"id": &"pocket_watch",
		"name": "懐中時計",
		"category": CATEGORY_MACHINE,
		"match_tool": ToolCatalogScript.TOOL_TWEEZERS,
		"color": Color(0.83, 0.68, 0.3),
	},
	{
		"id": &"silk_scarf",
		"name": "絹のスカーフ",
		"category": CATEGORY_CLOTH,
		"match_tool": ToolCatalogScript.TOOL_LINT_ROLLER,
		"color": Color(0.62, 0.12, 0.2),
	},
	{
		"id": &"earphones",
		"name": "イヤホン",
		"category": CATEGORY_MACHINE,
		"match_tool": ToolCatalogScript.TOOL_TWEEZERS,
		"color": Color(0.93, 0.93, 0.95),
	},
	{
		"id": &"knit_glove",
		"name": "毛糸の手袋",
		"category": CATEGORY_CLOTH,
		"match_tool": ToolCatalogScript.TOOL_LINT_ROLLER,
		"color": Color(0.2, 0.42, 0.68),
	},
]
## 探し物の種類と関係なく、見分けて丁寧に取る道具 (アンドロイド。PROJECT.md「道具」: 探し物の見分けと適切な掃除を自動でする)。
## 毛に埋もれたままの探し物も取る
const SORTING_TOOLS: Array[StringName] = [ToolCatalogScript.TOOL_ANDROID]
## きれいな状態で返した時のお礼 (円)。2 件返すと最初の道具 (ピンセット 250 円) に届き、1 件で手で取る段階の掃除代の
## 数回分になる額。探し物は 1 軒に 5 件なので、全部返しても手で取る段階の後の道具 (掃除機 6,000 円) に届かない
const REWARD_CLEAN: int = 200
## 傷めて返した時のお礼 (円)。きれいな時の 4 分の 1
const REWARD_DAMAGED: int = 50
## 探し物が出てくる、置かれた面の毛の残りの割合 (面の最初の本数に対する割合。この値以下で出てくる)。
## 0 に近いと面を片付け切るまで出ず、合う道具へ持ち替える前に傷める道具で取り切ってしまうため、片付けの途中の半分にした
const REVEAL_REMAINING_RATIO: float = 0.5
## 毛を取る道具の範囲に探し物が入るとみなす余白 (m)。道具の半径にこの分を足した距離の中にあれば当たる。探し物の大きさの半分ほど
const ITEM_REACH_MARGIN_M: float = 0.1
## 黒いスーツの住人が出かけるまでの、建物で遊んだ時間 (秒)。この時間までにスーツの毛を取り切ると上乗せがある。
## 粘着ローラーを買ってスーツにかけ、最後の毛を手で抜く時間を見込んだ
const SUIT_DEADLINE_SECONDS: float = 1800.0
## スーツの毛を取り切った時の上乗せ (円)。最後の 1 本を手で抜く手間に見合い、探し物 1 件のお礼 (REWARD_CLEAN) より少ない額
const SUIT_BONUS: int = 150
## 猫が逃げ出す、建物で遊んだ時間 (秒)。手で取る段階 (10〜15 分) の途中で、屋敷を歩き回る理由になる時刻
const RUNAWAY_START_SECONDS: float = 300.0
## 逃げる猫 (猫の表の最初の 1 匹)。持ち主は猫が最初にいる部屋の住人
const RUNAWAY_CAT_INDEX: int = 0
## 逃げた猫を届けた時の、持ち主の住人の機嫌 (ご機嫌の最大)
const RUNAWAY_RETURN_MOOD: float = 1.0
## 毛の跡の毛の塊の間隔 (m)。歩幅 (約 0.7 m) ほどで、立った目線から次の塊が 2〜3 個先まで見える間隔
const TRAIL_SPACING_M: float = 0.8


## 置き場所の番号 spot_index の探し物の種類 (ITEM_KINDS の 1 件) を返す
static func kind_for_index(spot_index: int) -> Dictionary:
	return ITEM_KINDS[posmod(spot_index, ITEM_KINDS.size())]


## 探し物の id ("found_item_<番号>") から種類を返す。番号が読めない時は最初の種類
static func kind_for_item_id(found_item_id: StringName) -> Dictionary:
	var text: String = String(found_item_id)
	var number_text: String = text.get_slice("_", text.get_slice_count("_") - 1)
	return kind_for_index(number_text.to_int() if number_text.is_valid_int() else 0)


## 道具 tool_id を、今の状態 condition の探し物 (種類 kind) にかけた後の状態を返す。
## 探し物を傷める道具 (ToolCatalog の damages_found_items) は、埋もれていても見つけた後でも吸い込んで傷める。
## 見分ける道具 (SORTING_TOOLS) は、埋もれていても見つけた後でも丁寧に取る。
## 種類に合う道具は、見つけた (毛の上に出てきた) 探し物だけを丁寧に取る (埋もれた物には届かない)。
## それ以外の道具と、取った後・返した後の探し物は状態を変えない
static func condition_after_tool(
	kind: Dictionary, tool_id: StringName, condition: FoundItemProgress.Condition
) -> FoundItemProgress.Condition:
	if condition not in [
		FoundItemProgressScript.Condition.HIDDEN, FoundItemProgressScript.Condition.FOUND
	]:
		return condition
	if ToolRulesScript.damages_found_items(tool_id):
		return FoundItemProgressScript.Condition.DAMAGED
	if SORTING_TOOLS.has(tool_id):
		return FoundItemProgressScript.Condition.CLEAN
	if condition == FoundItemProgressScript.Condition.FOUND and kind.get("match_tool") == tool_id:
		return FoundItemProgressScript.Condition.CLEAN
	return condition


## 状態 condition の探し物を返した時のお礼 (円)。取っていない探し物は 0
static func reward(condition: FoundItemProgress.Condition) -> int:
	match condition:
		FoundItemProgressScript.Condition.CLEAN:
			return REWARD_CLEAN
		FoundItemProgressScript.Condition.DAMAGED:
			return REWARD_DAMAGED
	return 0


## 面の毛の残り remaining (最初の本数 initial) の時に、その面に埋めた探し物が出てくるか
static func is_revealed(remaining: int, initial: int) -> bool:
	return float(maxi(0, remaining)) <= float(maxi(0, initial)) * REVEAL_REMAINING_RATIO


## 探し物 spot が、面 surface_id の点 point から半径 radius の道具の範囲に入るか (同じ面で、半径に余白を足した距離の中)
static func is_in_reach(
	spot: MansionLayout.FoundItemSpotDef, surface_id: StringName, point: Vector3, radius: float
) -> bool:
	return (
		spot.surface_id == surface_id
		and spot.position.distance_to(point) <= maxf(0.0, radius) + ITEM_REACH_MARGIN_M
	)


## 黒いスーツの服の毛の依頼の状態を返す: &"done" (取り切って上乗せを受け取った)、&"missed" (取り切る前に出かけた)、&"open" (受付中)
static func suit_status(already_cleared: bool, elapsed_seconds: float) -> StringName:
	if already_cleared:
		return &"done"
	if elapsed_seconds >= SUIT_DEADLINE_SECONDS:
		return &"missed"
	return &"open"


## スーツの面の毛が remaining 本の時、遊んだ時間 elapsed_seconds で上乗せを受け取れるか (出かける前に 0 本)
static func suit_cleared_now(remaining: int, elapsed_seconds: float) -> bool:
	return remaining <= 0 and elapsed_seconds < SUIT_DEADLINE_SECONDS


## 屋敷のスーツの面 (服の毛の依頼の対象) を表の順に返す
static func suit_surfaces(layout: MansionLayout) -> Array[MansionLayout.SurfaceDef]:
	var suits: Array[MansionLayout.SurfaceDef] = []
	if layout != null:
		for surface: MansionLayout.SurfaceDef in layout.surfaces:
			if surface.surface_type == MansionLayoutScript.SURFACE_SUIT:
				suits.append(surface)
	return suits


## 逃げる猫の id
static func runaway_cat_id() -> StringName:
	return CatRulesScript.CATS[RUNAWAY_CAT_INDEX]["id"]


## 逃げる猫の持ち主の部屋 (猫が最初にいる部屋。CatRules.build_routes と同じく猫の番号を部屋の数で割った余り)。部屋が無ければ null
static func runaway_owner_room(layout: MansionLayout) -> MansionLayout.RoomDef:
	if layout == null or layout.rooms.is_empty():
		return null
	return layout.rooms[RUNAWAY_CAT_INDEX % layout.rooms.size()]


## 逃げた猫の状態を返す: &"home" (まだ逃げていない)、&"escaped" (隠れている)、&"carried" (抱えている)、&"returned" (届けた)
static func runaway_status(returned: bool, carried: bool, elapsed_seconds: float) -> StringName:
	if returned:
		return &"returned"
	if elapsed_seconds < RUNAWAY_START_SECONDS:
		return &"home"
	return &"carried" if carried else &"escaped"


## 持ち主の部屋から、ドアでつながった部屋をたどって最も遠い部屋までの部屋の並び (持ち主の部屋から隠れる部屋まで) を返す。
## 同じ遠さなら表の前の部屋。部屋が無ければ空
static func runaway_path(layout: MansionLayout) -> Array[MansionLayout.RoomDef]:
	var path: Array[MansionLayout.RoomDef] = []
	var owner_room: MansionLayout.RoomDef = runaway_owner_room(layout)
	if owner_room == null:
		return path
	var previous: Dictionary = {owner_room.room_id: null}
	var queue: Array[MansionLayout.RoomDef] = [owner_room]
	var farthest: MansionLayout.RoomDef = owner_room
	while not queue.is_empty():
		var here: MansionLayout.RoomDef = queue.pop_front()
		farthest = here
		for other: MansionLayout.RoomDef in layout.rooms:
			if not previous.has(other.room_id) and _rooms_connected(here, other):
				previous[other.room_id] = here
				queue.append(other)
	var step: MansionLayout.RoomDef = farthest
	while step != null:
		path.push_front(step)
		step = previous[step.room_id]
	return path


## 逃げた猫が隠れている所 (隠れる部屋の、猫が立ち止まる所と同じずれの空いた所)。部屋が無ければ原点
static func runaway_hiding_point(layout: MansionLayout) -> Vector3:
	var path: Array[MansionLayout.RoomDef] = runaway_path(layout)
	if path.is_empty():
		return Vector3.ZERO
	return CatRulesScript.free_point(
		layout, path[path.size() - 1], CatRulesScript.CATS[RUNAWAY_CAT_INDEX]["offset"]
	)


## 毛の跡の毛の塊を置く所を、持ち主の部屋の中心から部屋の中心を順に通って隠れている所まで TRAIL_SPACING_M ごとに返す
## (隠れている所そのものは含めない)
static func trail_points(layout: MansionLayout) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var path: Array[MansionLayout.RoomDef] = runaway_path(layout)
	if path.is_empty():
		return points
	var corners: Array[Vector3] = []
	for room: MansionLayout.RoomDef in path:
		corners.append(room.center)
	corners.append(runaway_hiding_point(layout))
	for index: int in range(corners.size() - 1):
		var from: Vector3 = corners[index]
		var span: Vector3 = corners[index + 1] - from
		var steps: int = floori(span.length() / TRAIL_SPACING_M)
		for step: int in range(steps):
			points.append(from + span * (float(step) * TRAIL_SPACING_M / span.length()))
	return points


## 部屋 a と b が隣り合い、間の壁にドアがあるか
static func _rooms_connected(a: MansionLayout.RoomDef, b: MansionLayout.RoomDef) -> bool:
	if b.grid_x == a.grid_x + 1 and b.grid_z == a.grid_z:
		return a.open_east
	if b.grid_x == a.grid_x - 1 and b.grid_z == a.grid_z:
		return a.open_west
	if b.grid_z == a.grid_z + 1 and b.grid_x == a.grid_x:
		return a.open_south
	if b.grid_z == a.grid_z - 1 and b.grid_x == a.grid_x:
		return a.open_north
	return false

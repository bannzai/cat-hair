extends Node
## ゲーム進行状態・調整値・セーブデータを 1 か所で管理する autoload シングルトン。
## UI ノードや 3D ノードは状態を持たず、このノードの参照とシグナルを通じて同期する。
## --headless --script 検証から安全に扱うため、他スクリプトからは登録名の静的参照を使わず
## root.get_node_or_null("GameState") で取得する。

## 進行状態や残り毛本数が変わった時に発火し、HUD 等の表示を更新する
signal state_changed
## 猫と掃除ロボットの時間を進めて毛が増減した時に発火する (changes は automation.advance の戻り値)。
## 屋敷の毛の見た目 (HairField) を同じ本数だけ増減するため
signal automation_advanced(changes: Dictionary)
## 調整値から屋敷レイアウトが組み立て直された時に発火し、3D 空間を再構築する
signal mansion_rebuilt(layout: MansionLayout)

## セーブデータ全体型スクリプト
const SaveDataScript := preload("res://scripts/data/save_data.gd")
## 開発者向け調整値型スクリプト
const MansionTuningScript := preload("res://scripts/data/mansion_tuning.gd")
## 屋敷ビルダーロジックスクリプト
const MansionBuilderScript := preload("res://scripts/mansion/mansion_builder.gd")
## JSON 保存ストレージスクリプト
const SaveStorageScript := preload("res://scripts/state/save_storage.gd")
## 毛・加工品在庫データ型スクリプト
const HairStockScript := preload("res://scripts/data/hair_stock.gd")
## 手で毛を取る時のルールの計算
const HandRulesScript := preload("res://scripts/hand/hand_rules.gd")
## 手に持って使う道具の定義
const ToolCatalogScript := preload("res://scripts/tools/tool_catalog.gd")
## 手に持って使う道具のルールの計算
const ToolRulesScript := preload("res://scripts/tools/tool_rules.gd")
## 毛を売る・掃除代・機嫌の計算
const EconomyRulesScript := preload("res://scripts/economy/economy_rules.gd")
## 買った道具 1 つのデータ型スクリプト
const OwnedToolScript := preload("res://scripts/data/owned_tool.gd")
## 毛の加工機とダンプカーの計算
const ProcessingRulesScript := preload("res://scripts/economy/processing_rules.gd")
## 猫と掃除ロボットの状態と入口のスクリプト
const AutomationStateScript := preload("res://scripts/state/automation_state.gd")
## お金で買う物の種類: 道具
const PURCHASE_TOOL: StringName = &"tool"
## お金で買う物の種類: 道具のレベルを 1 上げる
const PURCHASE_LEVEL_UP: StringName = &"level_up"
## お金で買う物の種類: 道具の消耗品の買い足し
const PURCHASE_CONSUMABLE: StringName = &"consumable"
## お金で買う物の種類: 手の強化を 1 段上げる
const PURCHASE_HAND_UPGRADE: StringName = &"hand_upgrade"
## お金で買う物の種類: アンドロイドが、一杯になった道具のパックを交換する (アンドロイドを持っている時だけ買える)
const PURCHASE_ANDROID_PACK_EXCHANGE: StringName = &"android_pack_exchange"

## セーブデータの保存先パス (テスト時に差し替え可能)
var save_path: String = SaveStorageScript.DEFAULT_SAVE_PATH
## 現在のセーブデータ (Single State of Truth)
var save_data: SaveData = null
## 現在の調整値から組み立てた屋敷レイアウト
var current_layout: MansionLayout = null
## 起動時に有効なセーブデータを整合したまま読み込めたか
var loaded_from_save: bool = false
## コマンドライン引数で調整値を上書き起動したか (既存セーブの意図しない終了時上書きを防ぐ)
var launched_with_cmdline_override: bool = false
## 猫と掃除ロボットの状態 (時計・猫の通り道) と、時計を進める・掃除ロボットを買う・回る順を変える・猫をブラッシングする入口
## (scripts/state/automation_state.gd)
var automation: RefCounted = null
## 部屋ごとの最初の毛の本数 (room_id -> int。きれいさの分母)。屋敷を組み直した時に 1 回だけ求める。
## 保存データには入れない (調整値とレイアウトから同じ値が求まるため)
var _initial_room_hairs: Dictionary = {}


## 猫と掃除ロボットの状態を持つ
func _init() -> void:
	automation = AutomationStateScript.new(self)


## autoload 起動時に保存ファイルとコマンドライン引数から初期状態を構築する
func _ready() -> void:
	if save_data == null:
		initialize_from_storage(save_path, _collect_cmdline_args())


## ウィンドウ終了要求時に現在の状態を保存する。
## コマンドライン引数で調整値を上書きした試験起動では既存の進行を壊さないよう自動保存しない。
## 前提 (Godot 4 公式ドキュメント「Handling quit requests」):
## application/config/auto_accept_quit (既定 true) では終了直前に全ノードへ
## NOTIFICATION_WM_CLOSE_REQUEST が通知されるため、ここで保存を完了させる。
func _notification(what: int) -> void:
	if (
		what == NOTIFICATION_WM_CLOSE_REQUEST
		and save_data != null
		and not launched_with_cmdline_override
	):
		save_current_state()


## 指定パスの保存データとコマンドライン引数から状態を初期化する。
## コマンドライン引数で調整値が指定されている場合は、その値で屋敷を新しく組み立て、
## 終了時の自動保存による既存セーブ上書きを無効にする。
func initialize_from_storage(
	target_path: String = SaveStorageScript.DEFAULT_SAVE_PATH,
	cmdline_args: PackedStringArray = PackedStringArray(),
) -> void:
	save_path = target_path
	var loaded_save: SaveData = SaveStorageScript.load_from_path(save_path)
	launched_with_cmdline_override = MansionTuningScript.has_cmdline_override(cmdline_args)

	if loaded_save != null and not launched_with_cmdline_override:
		save_data = loaded_save
		loaded_from_save = true
		current_layout = MansionBuilderScript.build_layout(save_data.tuning)
		_reconcile_progress_with_layout()
	else:
		loaded_from_save = false
		_create_fresh_save(
			MansionTuningScript.from_cmdline_args(
				cmdline_args,
				loaded_save.tuning if loaded_save != null else MansionTuningScript.new(),
			)
		)
	_recompute_initial_room_hairs()
	mansion_rebuilt.emit(current_layout)
	state_changed.emit()


## 現在の調整値を使って新しい屋敷・進行データを作り直し、保存する
func start_new_game(custom_tuning: MansionTuning = null) -> void:
	loaded_from_save = false
	launched_with_cmdline_override = false
	_create_fresh_save(
		custom_tuning.clamped() if custom_tuning != null else get_tuning().clamped()
	)
	save_current_state()
	_recompute_initial_room_hairs()
	mansion_rebuilt.emit(current_layout)
	state_changed.emit()


## 開発者向けの調整値を適用し、その値の屋敷を作り直す。
## persist の既定値を true とするのは、開発者画面からの適用時にそのまま保存して
## 次回起動でも同じ調整値の屋敷を再開できるようにするため (保存不要な検証のみ false を渡す)。
func apply_tuning_and_rebuild(new_tuning: MansionTuning, persist: bool = true) -> void:
	var safe_tuning: MansionTuning = (
		new_tuning.clamped() if new_tuning != null else MansionTuningScript.new()
	)
	if save_data == null:
		_create_fresh_save(safe_tuning)
	else:
		save_data.tuning = safe_tuning
		current_layout = MansionBuilderScript.build_layout(safe_tuning)
		save_data.building_progress = MansionBuilderScript.build_initial_progress(
			current_layout,
			safe_tuning,
		)
	if persist:
		launched_with_cmdline_override = false
		save_current_state()
	_recompute_initial_room_hairs()
	mansion_rebuilt.emit(current_layout)
	state_changed.emit()


## 現在の状態を JSON として保存する
func save_current_state() -> Error:
	if save_data == null:
		return ERR_UNCONFIGURED
	return SaveStorageScript.save_to_path(save_data, save_path)


## 現在の調整値を返す
func get_tuning() -> MansionTuning:
	if save_data == null or save_data.tuning == null:
		return MansionTuningScript.new()
	return save_data.tuning


## 屋敷全体に残っている毛の総本数を返す
func get_total_remaining_hairs() -> int:
	if save_data == null or save_data.building_progress == null:
		return 0
	return save_data.building_progress.total_remaining_hairs()


## 現在の所持金を返す
func get_money() -> int:
	if save_data == null or save_data.building_progress == null:
		return 0
	return save_data.building_progress.money


## 指定面の残り毛本数を返す
func get_surface_hair_count(surface_id: StringName) -> int:
	if save_data == null or save_data.building_progress == null:
		return 0
	var surface: SurfaceHair = save_data.building_progress.find_surface_hair(surface_id)
	return surface.total_count() if surface != null else 0


## 指定面から指定色の毛を 1 本取り、在庫 (毛のまま) に入れる。珍しい毛なら図鑑に載せる。
## 戻り値は {"plucked": 取れたか, "new_rare": 図鑑に新しく載ったか}。その面にその色が残っていなければ何も変えない
func pluck_hair(
	surface_id: StringName, hair_color: StringName, rare_hair_id: StringName = &""
) -> Dictionary:
	var result: Dictionary = {"plucked": false, "new_rare": false}
	if save_data == null or save_data.building_progress == null:
		return result
	var surface: SurfaceHair = save_data.building_progress.find_surface_hair(surface_id)
	if surface == null or surface.count_for_color(hair_color) <= 0:
		return result
	surface.hair_counts[hair_color] = surface.count_for_color(hair_color) - 1
	_add_raw_stock(hair_color, rare_hair_id)
	result["plucked"] = true
	result["new_rare"] = HandRulesScript.register_rare_hair(
		save_data.found_rare_hair_ids, rare_hair_id
	)
	state_changed.emit()
	return result


## 在庫にある毛のまま (加工していない) の本数の合計を返す
func get_raw_hair_stock_count() -> int:
	if save_data == null or save_data.building_progress == null:
		return 0
	var total: int = 0
	for stock: HairStock in save_data.building_progress.hair_stocks:
		if stock != null and stock.form == HairStockScript.FORM_RAW:
			total += stock.count
	return total


## 手の強化の段を返す (upgrade_id は HandRules.UPGRADE_*)
func get_hand_upgrade_level(upgrade_id: StringName) -> int:
	if save_data == null:
		return 0
	return HandRulesScript.upgrade_level(save_data.hand_upgrade_levels, upgrade_id)


## 手の強化の段を設定する (強化を買う処理と検証から呼ぶ。お金のやり取りはここでは行わない)
func set_hand_upgrade_level(upgrade_id: StringName, level: int) -> void:
	if save_data == null:
		return
	save_data.hand_upgrade_levels[upgrade_id] = maxi(0, level)
	state_changed.emit()


## 図鑑に載った珍しい毛の種類の一覧を返す
func get_found_rare_hair_ids() -> Array[StringName]:
	var empty_ids: Array[StringName] = []
	return save_data.found_rare_hair_ids if save_data != null else empty_ids


## 持っている道具を 1 回かけ、面ごとの色ごとの本数 (surface_id -> {color -> int}) だけまとめて減らして在庫 (毛のまま) に入れる。
## 部屋ごとにかける道具 (吸引車・粘着シート) も 1 回は 1 回で、消耗品を使う道具は面の数に関わらず 1 つ使う。
## 消耗品の残りが 0 の時は何も変えずに -1 を返す (持っていない道具と、無い面が 1 つでもある時も -1)。
## 道具で取った毛は珍しい毛を見分けない (PROJECT.md「毛と表面」: 手でつまむ段階でしか見分けられない)。
## その面に残っている本数より多くは減らさない。戻り値は減らした本数の合計で、変わった時だけ 1 回通知する
func apply_tool_sweep(tool_id: StringName, counts_by_surface: Dictionary) -> int:
	var owned: OwnedTool = find_owned_tool(tool_id)
	if owned == null or not ToolRulesScript.can_use(tool_id, owned.consumable_count):
		return -1
	for surface_key: Variant in counts_by_surface.keys():
		if save_data.building_progress.find_surface_hair(StringName(surface_key)) == null:
			return -1
	var consumed: bool = ToolRulesScript.uses_consumable(tool_id)
	if consumed:
		owned.consumable_count -= 1
	var removed_total: int = 0
	for surface_key: Variant in counts_by_surface.keys():
		var surface: SurfaceHair = save_data.building_progress.find_surface_hair(
			StringName(surface_key)
		)
		var counts_by_color: Dictionary = counts_by_surface[surface_key]
		for color_key: Variant in counts_by_color.keys():
			var color_id: StringName = StringName(color_key)
			var removed: int = mini(
				maxi(0, int(counts_by_color[color_key])), surface.count_for_color(color_id)
			)
			if removed <= 0:
				continue
			surface.hair_counts[color_id] = surface.count_for_color(color_id) - removed
			_add_raw_stock(color_id, &"", removed)
			removed_total += removed
	if consumed or removed_total > 0:
		state_changed.emit()
	return removed_total


## 在庫 (毛のままと加工した物) をすべて買取業者に売り、入ったお金 (円) を返す (売る物が無ければ 0 で何も変えない)
func sell_hair_stocks() -> int:
	if save_data == null or save_data.building_progress == null:
		return 0
	var progress: BuildingProgress = save_data.building_progress
	var plan: Dictionary = {}
	for index: int in range(progress.hair_stocks.size()):
		var stock: HairStock = progress.hair_stocks[index]
		if stock != null and stock.count > 0:
			plan[index] = stock.count
	return _sell_plan(plan)


## 毛を運ぶダンプカーで、在庫を積める量 (ProcessingRules.DUMP_TRUCK_CAPACITY_HAIRS) まで運び出して売る。
## 買取業者の近くにいなくても売れる。戻り値は {"hauled_hairs": 毛の本数に直した積み荷の量, "earned": 入ったお金}。
## ダンプカーを持っていない時と積む物が無い時は何も変えずに両方 0
func haul_with_dump_truck() -> Dictionary:
	var result: Dictionary = {"hauled_hairs": 0, "earned": 0}
	if find_owned_tool(ToolCatalogScript.TOOL_DUMP_TRUCK) == null:
		return result
	var stocks: Array[HairStock] = save_data.building_progress.hair_stocks
	var plan: Dictionary = ProcessingRulesScript.haul_plan(
		stocks, ProcessingRulesScript.DUMP_TRUCK_CAPACITY_HAIRS
	)
	result["hauled_hairs"] = ProcessingRulesScript.plan_hairs(stocks, plan)
	result["earned"] = _sell_plan(plan)
	return result


## 在庫の添字ごとの個数 plan を売ってお金を足し、売り切った在庫を除く。戻り値は入ったお金 (円)。売る物が無ければ何も変えない
func _sell_plan(plan: Dictionary) -> int:
	if plan.is_empty():
		return 0
	var progress: BuildingProgress = save_data.building_progress
	var earned: int = ProcessingRulesScript.plan_value(progress.hair_stocks, plan)
	var kept: Array[HairStock] = []
	for index: int in range(progress.hair_stocks.size()):
		var stock: HairStock = progress.hair_stocks[index]
		if stock == null:
			continue
		stock.count -= int(plan.get(index, 0))
		if stock.count > 0:
			kept.append(stock)
	progress.hair_stocks = kept
	progress.money += earned
	state_changed.emit()
	return earned


## 買った道具のうち tool_id の 1 件を返す (買っていなければ null。手は買わないので常に null)
func find_owned_tool(tool_id: StringName) -> OwnedTool:
	if save_data == null or save_data.building_progress == null:
		return null
	for owned: OwnedTool in save_data.building_progress.owned_tools:
		if owned != null and owned.tool_id == tool_id:
			return owned
	return null


## お金で買う。kind は PURCHASE_* で、item_id は道具の id (手の強化は HandRules.UPGRADE_* の id)。
## 買えない時 (表に無い・既に持っている・持っていない道具のレベル上げ・上限・お金が足りない) は何も変えずに false
func purchase(kind: StringName, item_id: StringName) -> bool:
	if save_data == null or save_data.building_progress == null:
		return false
	var bought: bool = false
	match kind:
		PURCHASE_TOOL:
			bought = _buy_tool(item_id)
		PURCHASE_LEVEL_UP:
			bought = _level_up_tool(item_id)
		PURCHASE_CONSUMABLE:
			bought = _buy_consumable(item_id)
		PURCHASE_HAND_UPGRADE:
			bought = _buy_hand_upgrade(item_id)
		PURCHASE_ANDROID_PACK_EXCHANGE:
			bought = _exchange_pack_by_android(item_id)
	if bought:
		state_changed.emit()
	return bought


## 道具を買う。手 (最初から持っている)・表に無い道具・既に並べられる数 (ToolCatalog.max_owned) だけ持っている道具・
## お金が足りない時は買わずに false
func _buy_tool(tool_id: StringName) -> bool:
	var tool_def: Dictionary = ToolCatalogScript.find_tool(tool_id)
	if (
		tool_def.is_empty()
		or tool_id == ToolCatalogScript.TOOL_HAND
		or (
			ToolRulesScript.count_owned(save_data.building_progress.owned_tools, tool_id)
			>= ToolCatalogScript.max_owned(tool_id)
		)
	):
		return false
	if not _spend(int(tool_def["price"])):
		return false
	var owned: OwnedTool = OwnedToolScript.new()
	owned.tool_id = tool_id
	owned.level = 1
	owned.consumable_count = int(tool_def["initial_consumables"])
	save_data.building_progress.owned_tools.append(owned)
	return true


## 持っている道具のレベルを 1 上げる。持っていない・上限・お金が足りない時は false
func _level_up_tool(tool_id: StringName) -> bool:
	var owned: OwnedTool = find_owned_tool(tool_id)
	if owned == null:
		return false
	if not _spend(ToolRulesScript.level_up_price(tool_id, owned.level)):
		return false
	owned.level += 1
	return true


## 持っている道具の消耗品を買い足す。消耗品を使わない・持っていない・お金が足りない時は false
func _buy_consumable(tool_id: StringName) -> bool:
	var owned: OwnedTool = find_owned_tool(tool_id)
	if owned == null or not ToolRulesScript.uses_consumable(tool_id):
		return false
	var tool_def: Dictionary = ToolCatalogScript.find_tool(tool_id)
	if not _spend(int(tool_def["refill_price"])):
		return false
	owned.consumable_count = ToolRulesScript.refilled_count(tool_id, owned.consumable_count)
	return true


## アンドロイドを持っていて、tool_id の道具のパック (ToolRules.refill_replaces の消耗品) が一杯の時に、
## アンドロイドがパックを交換する (値段は手で交換する時と同じだけ払う)。交換したら true。
## アンドロイドを持っていない・パックの道具でない・まだ一杯でない・お金が足りない時は何も変えずに false
func _exchange_pack_by_android(tool_id: StringName) -> bool:
	var owned: OwnedTool = find_owned_tool(tool_id)
	return (
		owned != null
		and ToolRulesScript.refill_replaces(tool_id)
		and owned.consumable_count <= 0
		and find_owned_tool(ToolCatalogScript.TOOL_ANDROID) != null
		and _buy_consumable(tool_id)
	)


## 手の強化を 1 段上げる。手の強化の種類でない id・上限・お金が足りない時は false
func _buy_hand_upgrade(upgrade_id: StringName) -> bool:
	if upgrade_id not in [HandRulesScript.UPGRADE_DEXTERITY, HandRulesScript.UPGRADE_GRAB_COUNT]:
		return false
	var level: int = get_hand_upgrade_level(upgrade_id)
	if not _spend(ToolRulesScript.hand_upgrade_price(level)):
		return false
	save_data.hand_upgrade_levels[upgrade_id] = level + 1
	return true


## 部屋の今の様子を返す: {"hair_count": 残りの本数, "cleanliness": きれいさ (0〜1),
## "mood": 住人の機嫌 (0〜1), "cleaning_fee": 住人が次に払う掃除代 (円)}
func get_room_status(room_id: StringName) -> Dictionary:
	var hair_count: int = 0
	var mood: float = 0.0
	if save_data != null and save_data.building_progress != null and current_layout != null:
		for surface_def: MansionLayout.SurfaceDef in current_layout.surfaces:
			if surface_def.room_id == room_id:
				hair_count += get_surface_hair_count(surface_def.surface_id)
		mood = float(
			save_data.building_progress.resident_moods.get(
				MansionBuilderScript.resident_id_for_room(room_id), 0.0
			)
		)
	return {
		"hair_count": hair_count,
		"cleanliness": EconomyRulesScript.cleanliness(
			hair_count, int(_initial_room_hairs.get(room_id, 0))
		),
		"mood": mood,
		"cleaning_fee": EconomyRulesScript.cleaning_fee(mood),
	}


## 遊んだ時間を delta_seconds 秒進め、加工機が加工する時期が来た分だけ在庫の毛を加工し、
## 住人の機嫌を部屋のきれいさへ近づけ、払う時期が来た掃除代を所持金に足す。
## 戻り値はこの呼び出しで入った掃除代 (円)。加工した時と掃除代が入った時だけ通知する
func advance_time(delta_seconds: float) -> int:
	if save_data == null or save_data.building_progress == null or current_layout == null:
		return 0
	var progress: BuildingProgress = save_data.building_progress
	var safe_delta: float = maxf(0.0, delta_seconds)
	var before: float = progress.elapsed_seconds
	progress.elapsed_seconds = before + safe_delta
	_run_processors(ProcessingRulesScript.runs_due(before, progress.elapsed_seconds))
	for room: MansionLayout.RoomDef in current_layout.rooms:
		var status: Dictionary = get_room_status(room.room_id)
		progress.resident_moods[MansionBuilderScript.resident_id_for_room(room.room_id)] = (
			EconomyRulesScript.next_mood(status["mood"], status["cleanliness"], safe_delta)
		)
	var payments: int = EconomyRulesScript.payments_due(before, progress.elapsed_seconds)
	if payments <= 0:
		return 0
	var earned: int = 0
	for room: MansionLayout.RoomDef in current_layout.rooms:
		earned += int(get_room_status(room.room_id)["cleaning_fee"]) * payments
	if earned > 0:
		progress.money += earned
		state_changed.emit()
	return earned


## 持っている加工機で在庫を runs 回加工する。在庫が変わった時だけ通知する
func _run_processors(runs: int) -> void:
	var progress: BuildingProgress = save_data.building_progress
	var machines: int = ToolRulesScript.count_owned(
		progress.owned_tools, ToolCatalogScript.TOOL_HAIR_PROCESSOR
	)
	if runs <= 0 or machines <= 0:
		return
	var stocks: Array[HairStock] = progress.hair_stocks
	# 加工すると売値は必ず上がる (どの段階も毛のままより高い) ため、売値が変わらなくなったら加工する毛が残っていない
	for _run: int in range(runs):
		var next_stocks: Array[HairStock] = ProcessingRulesScript.process_once(stocks, machines)
		if ProcessingRulesScript.stock_value(next_stocks) == ProcessingRulesScript.stock_value(stocks):
			break
		stocks = next_stocks
	if (
		ProcessingRulesScript.stock_value(stocks)
		!= ProcessingRulesScript.stock_value(progress.hair_stocks)
	):
		var kept: Array[HairStock] = []
		for stock: HairStock in stocks:
			if stock.count > 0:
				kept.append(stock)
		progress.hair_stocks = kept
		state_changed.emit()


## 所持金から price を払う。値段が負 (買えない物) かお金が足りない時は払わずに false
func _spend(price: int) -> bool:
	if save_data == null or save_data.building_progress == null:
		return false
	if not ToolRulesScript.can_afford(save_data.building_progress.money, price):
		return false
	save_data.building_progress.money -= price
	return true


## 今の調整値とレイアウトから、部屋ごと・面ごとの最初の毛の本数と猫の通り道を求め直し、猫と掃除ロボットの時計を
## 0 に戻す (屋敷を組み直した時に呼ぶ)
func _recompute_initial_room_hairs() -> void:
	_initial_room_hairs.clear()
	var initial_surface_hairs: Dictionary = {}
	if current_layout != null:
		var initial: BuildingProgress = MansionBuilderScript.build_initial_progress(
			current_layout, get_tuning()
		)
		for surface_def: MansionLayout.SurfaceDef in current_layout.surfaces:
			var surface: SurfaceHair = initial.find_surface_hair(surface_def.surface_id)
			var count: int = surface.total_count() if surface != null else 0
			initial_surface_hairs[surface_def.surface_id] = count
			_initial_room_hairs[surface_def.room_id] = (
				int(_initial_room_hairs.get(surface_def.room_id, 0)) + count
			)
	automation.reset(current_layout, initial_surface_hairs)


## 毛のままの在庫のうち、色と珍しい毛の種類が一致する 1 件に count 本足す (無ければ作る)
func _add_raw_stock(hair_color: StringName, rare_hair_id: StringName, count: int = 1) -> void:
	for stock: HairStock in save_data.building_progress.hair_stocks:
		if (
			stock != null
			and stock.form == HairStockScript.FORM_RAW
			and stock.hair_color == hair_color
			and stock.rare_hair_id == rare_hair_id
		):
			stock.count += count
			return
	var new_stock: HairStock = HairStockScript.new()
	new_stock.hair_color = hair_color
	new_stock.rare_hair_id = rare_hair_id
	new_stock.form = HairStockScript.FORM_RAW
	new_stock.count = count
	save_data.building_progress.hair_stocks.append(new_stock)


## 指定の調整値から新しいレイアウトと初期 SaveData を生成する
func _create_fresh_save(target_tuning: MansionTuning) -> void:
	var safe_tuning: MansionTuning = target_tuning.clamped()
	current_layout = MansionBuilderScript.build_layout(safe_tuning)
	save_data = SaveDataScript.new()
	save_data.schema_version = SaveDataScript.SCHEMA_VERSION
	save_data.tuning = safe_tuning
	save_data.building_progress = MansionBuilderScript.build_initial_progress(
		current_layout,
		safe_tuning,
	)


## 読み込んだ進行の面・探し物・住人の ID 一覧が現在レイアウトと一致しない場合は
## 進行を作り直し、タイトルで「続きから」を出さないよう loaded_from_save を降ろす
func _reconcile_progress_with_layout() -> void:
	if save_data == null or save_data.building_progress == null or current_layout == null:
		return
	if (
		not _surface_ids_match_layout()
		or not _found_item_ids_match_layout()
		or not _resident_ids_match_layout()
	):
		save_data.building_progress = MansionBuilderScript.build_initial_progress(
			current_layout,
			save_data.tuning,
		)
		loaded_from_save = false


## 保存データの surface_hairs の件数と ID 集合が現在レイアウトの surfaces と完全一致するか
func _surface_ids_match_layout() -> bool:
	if save_data.building_progress.surface_hairs.size() != current_layout.surfaces.size():
		return false
	var expected_ids: Dictionary = {}
	for surface: MansionLayout.SurfaceDef in current_layout.surfaces:
		expected_ids[surface.surface_id] = true
	var actual_ids: Dictionary = {}
	for entry: SurfaceHair in save_data.building_progress.surface_hairs:
		actual_ids[entry.surface_id] = true
	return _id_sets_equal(expected_ids, actual_ids)


## 保存データの found_items の件数と ID 集合が現在レイアウトの found_item_spots と完全一致するか
func _found_item_ids_match_layout() -> bool:
	if save_data.building_progress.found_items.size() != current_layout.found_item_spots.size():
		return false
	var expected_ids: Dictionary = {}
	for spot: MansionLayout.FoundItemSpotDef in current_layout.found_item_spots:
		expected_ids[spot.found_item_id] = true
	var actual_ids: Dictionary = {}
	for item: FoundItemProgress in save_data.building_progress.found_items:
		actual_ids[item.found_item_id] = true
	return _id_sets_equal(expected_ids, actual_ids)


## 保存データの resident_moods の件数と住人 ID 集合が現在レイアウトの rooms と完全一致するか
func _resident_ids_match_layout() -> bool:
	var expected_ids: Dictionary = {}
	for room: MansionLayout.RoomDef in current_layout.rooms:
		expected_ids[MansionBuilderScript.resident_id_for_room(room.room_id)] = true
	return _id_sets_equal(expected_ids, save_data.building_progress.resident_moods)


## 2 つの辞書のキー集合が件数・要素ともに一致するか
static func _id_sets_equal(expected_keys: Dictionary, actual_keys: Dictionary) -> bool:
	if expected_keys.size() != actual_keys.size():
		return false
	for expected_key: Variant in expected_keys.keys():
		if not actual_keys.has(expected_key):
			return false
	return true


## 起動時のユーザー引数 (`--` 以降) を返す
static func _collect_cmdline_args() -> PackedStringArray:
	return OS.get_cmdline_user_args()

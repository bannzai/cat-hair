extends RefCounted
## 毛の加工機 (毛玉 → フェルト → 猫の毛の人形) と毛を運ぶダンプカーの計算。
## 状態を持たない純粋な計算だけを置き、selfcheck が入力と出力で検証する。
## 値は触れる版の感想を取るための仮の値で、自動テストプレイ (issue #13) の結果で調整する

## 面ごとの毛データ型スクリプト (色の定数を使う)
const SurfaceHairScript := preload("res://scripts/data/surface_hair.gd")
## 毛・加工品在庫データ型スクリプト
const HairStockScript := preload("res://scripts/data/hair_stock.gd")
## 毛を売る値段の計算 (毛のままの 1 本の売値)
const EconomyRulesScript := preload("res://scripts/economy/economy_rules.gd")

## 加工の形を、加工の進む順 (毛のまま → 毛玉 → フェルト → 人形) に並べた表
const FORMS_IN_ORDER: Array[StringName] = [
	HairStockScript.FORM_RAW,
	HairStockScript.FORM_BALL,
	HairStockScript.FORM_FELT,
	HairStockScript.FORM_DOLL,
]
## 加工した物 1 個に使う毛の本数。毛玉 20 本、フェルトは毛玉 5 個分、人形はフェルト 4 枚分。
## 毛玉は手で数十本取ればできる量にして最初の加工機ですぐ結果が見え、人形は既定の屋敷の 1 部屋の毛
## (既定の毛の本数が 12,000 本だった時の、既定の部屋数で割った本数) を片付けると数体できる大きさにした
## (既定を 120,000 本に上げた issue #56 では変えず、値の調整 (#13) に任せた)
const HAIRS_PER_UNIT: Dictionary = {
	HairStockScript.FORM_RAW: 1,
	HairStockScript.FORM_BALL: 20,
	HairStockScript.FORM_FELT: 100,
	HairStockScript.FORM_DOLL: 400,
}
## 加工した物の売値を、使った毛を毛のまま売った値段の何倍にするか。段階が進むほど高い。
## 加工機 1 台の値段の元が、人形 1 体分の毛を加工すると取れ、毛玉だけでは何倍もの毛が要る差にして、
## 加工を進めるほど元が早く取れるようにした
const STAGE_PRICE_FACTOR: Dictionary = {
	HairStockScript.FORM_RAW: 1.0,
	HairStockScript.FORM_BALL: 1.5,
	HairStockScript.FORM_FELT: 2.0,
	HairStockScript.FORM_DOLL: 3.0,
}
## 色を混ぜて加工した物の売値に掛ける倍率。混ぜない物より安く、毛のまま売るより高い
## (毛玉でも 1.5 × 0.8 = 1.2 倍で、毛のままの 1 倍を上回る)
const MIXED_PRICE_FACTOR: float = 0.8
## 色を混ぜて加工する毛の色。値段の同じ白と黒だけを混ぜる。三毛は混ぜると見栄えの良さ (毛のままで白・黒の 2 倍) が
## 消えるため混ぜず、三毛の専用の加工機が並ぶまで毛のまま残す
const MIXABLE_COLORS: Array[StringName] = [
	SurfaceHairScript.COLOR_WHITE,
	SurfaceHairScript.COLOR_BLACK,
]
## 加工機 1 台が 1 回の加工で使う毛の本数の上限 (人形 1 体分。1 回で最上位の段階まで作れる量)
const HAIRS_PER_MACHINE_RUN: int = 400
## 加工機が 1 回加工する間隔 (遊んだ時間の秒)。台数を並べると同じ時間で加工できる量が増える。
## 掃除代を払う間隔 (60 秒) より短くし、道具を買う画面を開け閉めする間に加工が進んだと見て分かる長さにした
const PROCESS_INTERVAL_SECONDS: float = 10.0
## 毛を運ぶダンプカーが 1 回で運べる量 (毛の本数に直した量。加工した物は使った毛の本数で数える)。
## 屋敷の毛の既定の本数が 12,000 本だった時に 3 回ほどで運び切れる量にし、在庫が多くなると何度か呼ぶ必要が出るようにした
## (既定を 120,000 本に上げた issue #56 では変えず、値の調整 (#13) に任せた)
const DUMP_TRUCK_CAPACITY_HAIRS: int = 5000


## 加工機の台数から、加工の列 (1 台が受け持つ毛の色の並び) を返す。
## 0 台は無し、1 台は白と黒を混ぜる 1 列 (三毛は加工しない)、2 台は三毛と白・黒を混ぜる 2 列、3 台以上は色ごとの 3 列。
## 4 台目からは列が増えず、同じ列を受け持つ台が増えて 1 回に加工できる量が増える
static func processing_lines(machine_count: int) -> Array[Array]:
	var lines: Array[Array] = []
	if machine_count <= 0:
		return lines
	if machine_count == 1:
		lines.append(MIXABLE_COLORS.duplicate())
	elif machine_count == 2:
		lines.append([SurfaceHairScript.COLOR_CALICO])
		lines.append(MIXABLE_COLORS.duplicate())
	else:
		for color_id: StringName in SurfaceHairScript.STANDARD_COLORS:
			lines.append([color_id])
	return lines


## 加工機の台数で、1 列が 1 回の加工で使える毛の本数の上限を返す (台数を列に均等に割り、余りの台は前の列から受け持つ)
static func line_capacity(machine_count: int, line_index: int) -> int:
	var line_count: int = processing_lines(machine_count).size()
	if line_count <= 0 or line_index < 0 or line_index >= line_count:
		return 0
	return (
		_whole_part(machine_count, line_count) + (1 if line_index < machine_count % line_count else 0)
	) * HAIRS_PER_MACHINE_RUN


## 在庫 1 種類の 1 個の売値 (円) を返す。毛のままは EconomyRules.hair_price、加工した物は
## 使った毛を毛のまま売った値段 × 段階の倍率 (色を混ぜた物はさらに MIXED_PRICE_FACTOR 倍)
static func unit_price(form: StringName, hair_color: StringName, rare_hair_id: StringName) -> int:
	if form == HairStockScript.FORM_RAW or not HAIRS_PER_UNIT.has(form):
		return EconomyRulesScript.hair_price(hair_color, rare_hair_id)
	var mixed: bool = hair_color == HairStockScript.COLOR_MIXED
	# 混ぜた物は白と黒だけでできているため、白・黒の 1 本の値段を元にする
	return roundi(
		float(
			EconomyRulesScript.hair_price(SurfaceHairScript.COLOR_WHITE if mixed else hair_color, &"")
			* int(HAIRS_PER_UNIT[form])
		)
		* float(STAGE_PRICE_FACTOR[form])
		* (MIXED_PRICE_FACTOR if mixed else 1.0)
	)


## 在庫をすべて売った時に入るお金 (円) を返す (毛のままと加工した物の両方)
static func stock_value(stocks: Array[HairStock]) -> int:
	var total: int = 0
	for stock: HairStock in stocks:
		if stock != null:
			total += unit_price(stock.form, stock.hair_color, stock.rare_hair_id) * maxi(0, stock.count)
	return total


## 毛 hair_count 本を、使える限り上の段階から加工した個数を返す ({form: 個数}。加工しきれず残る毛は FORM_RAW)
static func split_into_products(hair_count: int) -> Dictionary:
	var result: Dictionary = {}
	var rest: int = maxi(0, hair_count)
	for index: int in range(FORMS_IN_ORDER.size() - 1, -1, -1):
		var form: StringName = FORMS_IN_ORDER[index]
		var per_unit: int = int(HAIRS_PER_UNIT[form])
		var units: int = _whole_part(rest, per_unit)
		if units > 0:
			result[form] = units
			rest -= units * per_unit
	return result


## 加工機 machine_count 台で 1 回加工した後の在庫を、新しい配列で返す (渡した在庫は変えない)。
## 各列は受け持つ色のふつうの毛 (珍しい毛は加工しない) を上限まで使い、毛玉にならない端数 (20 本未満) は毛のまま残す
static func process_once(stocks: Array[HairStock], machine_count: int) -> Array[HairStock]:
	var result: Array[HairStock] = []
	for stock: HairStock in stocks:
		if stock != null:
			result.append(_copy_stock(stock))
	var lines: Array[Array] = processing_lines(machine_count)
	for line_index: int in range(lines.size()):
		var colors: Array = lines[line_index]
		var available: int = 0
		for color_id: Variant in colors:
			available += _raw_count(result, StringName(color_id))
		var used: int = mini(available, line_capacity(machine_count, line_index))
		used -= used % int(HAIRS_PER_UNIT[HairStockScript.FORM_BALL])
		if used <= 0:
			continue
		var remaining_to_take: int = used
		for color_id: Variant in colors:
			remaining_to_take -= _take_raw(result, StringName(color_id), remaining_to_take)
		var product_color: StringName = (
			StringName(colors[0]) if colors.size() == 1 else HairStockScript.COLOR_MIXED
		)
		var products: Dictionary = split_into_products(used)
		for form: Variant in products.keys():
			_add_stock(result, StringName(form), product_color, int(products[form]))
	return result


## 遊んだ時間が elapsed_before 秒から elapsed_after 秒へ進む間に、加工機が加工する回数を返す
static func runs_due(elapsed_before: float, elapsed_after: float) -> int:
	if elapsed_after <= elapsed_before:
		return 0
	return maxi(
		0,
		floori(elapsed_after / PROCESS_INTERVAL_SECONDS)
		- floori(maxf(0.0, elapsed_before) / PROCESS_INTERVAL_SECONDS),
	)


## 在庫 1 種類 1 個を毛の本数に直した量 (ダンプカーの積む量の単位) を返す
static func hairs_in_unit(form: StringName) -> int:
	return int(HAIRS_PER_UNIT.get(form, 1))


## ダンプカーで 1 回運ぶ積み荷を返す。在庫の並び順に、毛の本数に直した量の合計が capacity_hairs を超えない所まで積む。
## 戻り値は在庫の添字ごとの個数 ({stock_index: 個数})。1 個が残りの積める量より大きい物はその回は積まない
static func haul_plan(stocks: Array[HairStock], capacity_hairs: int) -> Dictionary:
	var plan: Dictionary = {}
	var room_left: int = maxi(0, capacity_hairs)
	for index: int in range(stocks.size()):
		var stock: HairStock = stocks[index]
		if stock == null or stock.count <= 0:
			continue
		var per_unit: int = hairs_in_unit(stock.form)
		var units: int = mini(stock.count, _whole_part(room_left, per_unit))
		if units <= 0:
			continue
		plan[index] = units
		room_left -= units * per_unit
	return plan


## 積み荷 plan (haul_plan の戻り値) を毛の本数に直した量の合計を返す
static func plan_hairs(stocks: Array[HairStock], plan: Dictionary) -> int:
	var total: int = 0
	for index: Variant in plan.keys():
		total += hairs_in_unit(stocks[int(index)].form) * int(plan[index])
	return total


## 積み荷 plan を売った時に入るお金 (円) を返す
static func plan_value(stocks: Array[HairStock], plan: Dictionary) -> int:
	var total: int = 0
	for index: Variant in plan.keys():
		var stock: HairStock = stocks[int(index)]
		total += unit_price(stock.form, stock.hair_color, stock.rare_hair_id) * int(plan[index])
	return total


## 在庫のうち、色が color_id のふつうの毛のままの本数を返す
static func _raw_count(stocks: Array[HairStock], color_id: StringName) -> int:
	var total: int = 0
	for stock: HairStock in stocks:
		if _is_plain_raw(stock, color_id):
			total += stock.count
	return total


## 在庫から色が color_id のふつうの毛のままを最大 wanted 本減らし、減らした本数を返す
static func _take_raw(stocks: Array[HairStock], color_id: StringName, wanted: int) -> int:
	var taken: int = 0
	for stock: HairStock in stocks:
		if taken >= wanted:
			break
		if _is_plain_raw(stock, color_id):
			var amount: int = mini(stock.count, wanted - taken)
			stock.count -= amount
			taken += amount
	return taken


## 在庫に形・色の一致する加工した物を count 個足す (無ければ作る)
static func _add_stock(
	stocks: Array[HairStock], form: StringName, hair_color: StringName, count: int
) -> void:
	for stock: HairStock in stocks:
		if stock.form == form and stock.hair_color == hair_color and stock.rare_hair_id == &"":
			stock.count += count
			return
	var new_stock: HairStock = HairStockScript.new()
	new_stock.form = form
	new_stock.hair_color = hair_color
	new_stock.count = count
	stocks.append(new_stock)


## 色が color_id のふつうの (珍しい毛でない) 毛のままの在庫か
static func _is_plain_raw(stock: HairStock, color_id: StringName) -> bool:
	return (
		stock != null
		and stock.form == HairStockScript.FORM_RAW
		and stock.hair_color == color_id
		and stock.rare_hair_id == &""
	)


## 0 以上の整数 numerator を正の整数 denominator で割った商 (切り捨て) を返す
static func _whole_part(numerator: int, denominator: int) -> int:
	return floori(float(numerator) / float(denominator))


## 在庫 1 種類の写しを作る
static func _copy_stock(stock: HairStock) -> HairStock:
	var copy: HairStock = HairStockScript.new()
	copy.hair_color = stock.hair_color
	copy.rare_hair_id = stock.rare_hair_id
	copy.form = stock.form
	copy.count = stock.count
	return copy

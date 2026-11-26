extends RefCounted
## お金の入り口 2 つ (買取業者に毛を売る・住人が掃除代を払う) と、住人の機嫌の計算。
## 状態を持たない純粋な計算だけを置き、selfcheck が入力と出力で検証する。
## 値段・掃除代・機嫌の変わる速さは触れる版の感想を取るための仮の値で、自動テストプレイ (issue #13) の結果で調整する

## 面ごとの毛データ型スクリプト (色の定数を使う)
const SurfaceHairScript := preload("res://scripts/data/surface_hair.gd")
## 毛・加工品在庫データ型スクリプト (毛のままの形の定数を使う)
const HairStockScript := preload("res://scripts/data/hair_stock.gd")
## 手で毛を取る時のルールの計算 (珍しい毛の id)
const HandRulesScript := preload("res://scripts/hand/hand_rules.gd")

## ふつうの毛 1 本の売値 (円)。三毛は 3 色が混じって見栄えがよいので高い
const HAIR_PRICE_BY_COLOR: Dictionary = {
	SurfaceHairScript.COLOR_WHITE: 1,
	SurfaceHairScript.COLOR_BLACK: 1,
	SurfaceHairScript.COLOR_CALICO: 2,
}
## 表に無い色の毛 1 本の売値 (円)
const DEFAULT_HAIR_PRICE: int = 1
## 珍しい毛 1 本の売値 (円)。出る確率が低いほど高い
const RARE_HAIR_PRICES: Dictionary = {
	HandRulesScript.RARE_WHISKER: 100,
	HandRulesScript.RARE_TRICOLOR: 40,
	HandRulesScript.RARE_GOLDEN: 300,
}
## 住人が掃除代を払う間隔 (遊んだ時間の秒)
const PAYMENT_INTERVAL_SECONDS: float = 60.0
## 機嫌が 1.0 (ご機嫌) の住人が 1 回に払う掃除代 (円)。機嫌に比例して減る
const BASE_CLEANING_FEE: int = 30
## 機嫌が目標 (きれいさ) へ近づく速さ (1 秒あたり)。0 から 1 まで 100 秒で変わる
const MOOD_CHANGE_PER_SECOND: float = 0.01


## 毛のままの 1 本の売値 (円) を返す。珍しい毛は種類の値段、ふつうの毛は色の値段
static func hair_price(hair_color: StringName, rare_hair_id: StringName) -> int:
	if rare_hair_id != &"" and RARE_HAIR_PRICES.has(rare_hair_id):
		return int(RARE_HAIR_PRICES[rare_hair_id])
	return int(HAIR_PRICE_BY_COLOR.get(hair_color, DEFAULT_HAIR_PRICE))


## 在庫のうち毛のままの物をすべて売った時に入るお金 (円) を返す (加工品は issue #12 が値段を決めるので含めない)
static func raw_stock_value(stocks: Array[HairStock]) -> int:
	var total: int = 0
	for stock: HairStock in stocks:
		if stock != null and stock.form == HairStockScript.FORM_RAW:
			total += hair_price(stock.hair_color, stock.rare_hair_id) * maxi(0, stock.count)
	return total


## 部屋のきれいさ (0.0 = 最初と同じだけ毛がある 〜 1.0 = 毛が無い) を返す。
## 最初から毛が 0 本の部屋は 1.0、最初より毛が増えた部屋 (猫が落とす。issue #11) は 0.0
static func cleanliness(remaining: int, initial: int) -> float:
	if initial <= 0:
		return 0.0
	return clampf(1.0 - float(maxi(0, remaining)) / float(initial), 0.0, 1.0)


## 今の機嫌 mood を、きれいさ target へ delta_seconds 秒分だけ近づけた機嫌を返す (行き過ぎない。0〜1)
static func next_mood(mood: float, target: float, delta_seconds: float) -> float:
	var safe_target: float = clampf(target, 0.0, 1.0)
	return clampf(
		move_toward(mood, safe_target, MOOD_CHANGE_PER_SECOND * maxf(0.0, delta_seconds)), 0.0, 1.0
	)


## 機嫌 mood の住人が 1 回に払う掃除代 (円) を返す
static func cleaning_fee(mood: float) -> int:
	return int(round(float(BASE_CLEANING_FEE) * clampf(mood, 0.0, 1.0)))


## 遊んだ時間が elapsed_before 秒から elapsed_after 秒へ進む間に、掃除代を払う回数を返す
static func payments_due(elapsed_before: float, elapsed_after: float) -> int:
	if elapsed_after <= elapsed_before:
		return 0
	return maxi(
		0,
		floori(elapsed_after / PAYMENT_INTERVAL_SECONDS)
		- floori(maxf(0.0, elapsed_before) / PAYMENT_INTERVAL_SECONDS),
	)

extends RefCounted
## お金の入り口 2 つ (買取業者に毛を売る・住人が掃除代を払う) と、住人の機嫌の計算。
## 状態を持たない純粋な計算だけを置き、selfcheck が入力と出力で検証する。
## 値段・掃除代・機嫌の変わる速さは触れる版の感想を取るための仮の値で、自動テストプレイ (issue #13) の結果で調整する

## 面ごとの毛データ型スクリプト (色の定数を使う)
const SurfaceHairScript := preload("res://scripts/data/surface_hair.gd")
## 手で毛を取る時のルールの計算 (珍しい毛の id)
const HandRulesScript := preload("res://scripts/hand/hand_rules.gd")

## ふつうの毛 1 本の売値 (円)。三毛は 3 色が混じって見栄えがよいので高い
const HAIR_PRICE_BY_COLOR: Dictionary = {
	SurfaceHairScript.COLOR_WHITE: 1,
	SurfaceHairScript.COLOR_BLACK: 1,
	SurfaceHairScript.COLOR_CALICO: 2,
}
## 表に無い色の毛 1 本の売値 (円)。ふつうの白・黒と同じ、いちばん安い値段にする
const DEFAULT_HAIR_PRICE: int = 1
## 珍しい毛 1 本の売値 (円)。出る確率が低いほど高い
const RARE_HAIR_PRICES: Dictionary = {
	HandRulesScript.RARE_WHISKER: 100,
	HandRulesScript.RARE_TRICOLOR: 40,
	HandRulesScript.RARE_GOLDEN: 300,
}
## 住人が掃除代を払う間隔 (遊んだ時間の秒)。手で毛を抜きながら 1 部屋を歩いて回る間に 1 回は入ったと分かる長さ
const PAYMENT_INTERVAL_SECONDS: float = 60.0
## 機嫌が 1.0 (ご機嫌) の住人が 1 回に払う掃除代 (円)。機嫌に比例して減る。4 部屋がご機嫌なら 60 秒で 120 円入り、
## 最初の道具 (ピンセット 30 円) を 1 回目の支払いで買え、粘着ローラー (150 円) には毛を売るお金も要る額
const BASE_CLEANING_FEE: int = 30
## 機嫌が目標 (きれいさ) へ近づく速さ (1 秒あたり)。0 から 1 まで 100 秒で変わり、片付けた部屋の機嫌が
## 次の掃除代 (60 秒後) までに目に見えて上がる速さ
const MOOD_CHANGE_PER_SECOND: float = 0.01
## 住人がご機嫌になる機嫌の線 (この値以上でご機嫌)。全員がご機嫌になると次の建物へ進める (DIRECTION.md「用語」の機嫌)。
## 屋敷に入った時の機嫌 (MansionBuilder.INITIAL_RESIDENT_MOOD の 0.5) より上にし、猫が毛を落とし続けても
## 部屋の毛を最初の 2 割以下に保てばご機嫌でいられる線
const HAPPY_MOOD: float = 0.8


## 毛のままの 1 本の売値 (円) を返す。珍しい毛は種類の値段、ふつうの毛は色の値段
static func hair_price(hair_color: StringName, rare_hair_id: StringName) -> int:
	if rare_hair_id != &"" and RARE_HAIR_PRICES.has(rare_hair_id):
		return int(RARE_HAIR_PRICES[rare_hair_id])
	return int(HAIR_PRICE_BY_COLOR.get(hair_color, DEFAULT_HAIR_PRICE))


## 部屋のきれいさ (0.0 = 最初と同じだけ毛がある 〜 1.0 = 毛が無い) を返す。
## 最初から毛が 0 本の部屋は 1.0、最初より毛が増えた部屋 (猫が落とす。issue #11) は 0.0
static func cleanliness(remaining: int, initial: int) -> float:
	if initial <= 0:
		return 1.0 if remaining <= 0 else 0.0
	return clampf(1.0 - float(maxi(0, remaining)) / float(initial), 0.0, 1.0)


## 今の機嫌 mood を、きれいさ target へ delta_seconds 秒分だけ近づけた機嫌を返す (行き過ぎない。0〜1)
static func next_mood(mood: float, target: float, delta_seconds: float) -> float:
	return clampf(
		move_toward(
			mood, clampf(target, 0.0, 1.0), MOOD_CHANGE_PER_SECOND * maxf(0.0, delta_seconds)
		),
		0.0,
		1.0
	)


## 機嫌 mood の住人がご機嫌か (HAPPY_MOOD 以上)
static func is_happy(mood: float) -> bool:
	return mood >= HAPPY_MOOD


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

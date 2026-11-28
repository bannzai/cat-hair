extends RefCounted
## 手で毛を取る時のルールの計算 (表面ごとのつまむ範囲・手の強化の効き方・珍しい毛の表と抽選・図鑑への登録)。
## 状態を持たない純粋な計算だけを置き、selfcheck が入力と出力で検証する。
## 確率・秒数・倍率は、触れる版の感想を取るための仮の値。序盤の 10〜15 分 (DIRECTION.md「判定基準」) を手だけで
## 遊ぶ時に、珍しい毛が数分に 1 本見つかり (1 本 1 秒前後で抜くと 1/400 + 1/1500 で約 5 分に 1 本)、
## 強化 1 段の差が体感できる程度にした。bannzai が make run で遊んだ感想で調整する

## 屋敷レイアウト型スクリプト (表面の種類の定数を使う)
const MansionLayoutScript := preload("res://scripts/mansion/mansion_layout.gd")
## 面ごとの毛データ型スクリプト (色の定数を使う)
const SurfaceHairScript := preload("res://scripts/data/surface_hair.gd")

## 手の強化の種類: 指先の器用さ (照準の周りでつまめる範囲が広がる)。保存データの hand_upgrade_levels のキー
const UPGRADE_DEXTERITY: StringName = &"dexterity"
## 手の強化の種類: 一度につまめる本数。保存データの hand_upgrade_levels のキー
const UPGRADE_GRAB_COUNT: StringName = &"grab_count"
## 強化していない手で一度につまめる本数
const BASE_GRAB_COUNT: int = 1
## 一度につまめる本数の上限 (指でつまめる束として不自然にならない本数)
const MAX_GRAB_COUNT: int = 10

## 珍しい毛の種類: 猫のヒゲ
const RARE_WHISKER: StringName = &"whisker"
## 珍しい毛の種類: 三毛の 3 色がそろった 1 本
const RARE_TRICOLOR: StringName = &"tricolor"
## 珍しい毛の種類: 金色の毛
const RARE_GOLDEN: StringName = &"golden"

## 珍しい毛の表。並び順が抽選と図鑑の表示の順。
## chance はつまんだ 1 本がその種類になる確率、colors は出る毛の色 (空ならどの色でも出る)
const RARE_HAIRS: Array[Dictionary] = [
	{
		"id": RARE_WHISKER,
		"name": "猫のヒゲ",
		"chance": 1.0 / 400.0,
		"colors": [],
	},
	{
		"id": RARE_TRICOLOR,
		"name": "三毛の 3 色そろい",
		"chance": 1.0 / 250.0,
		"colors": [SurfaceHairScript.COLOR_CALICO],
	},
	{
		"id": RARE_GOLDEN,
		"name": "金色の毛",
		"chance": 1.0 / 1500.0,
		"colors": [],
	},
]


## 平らな面は根元から 8 cm、布では繊維に絡んだ毛を狙って 4 cm。器用さ 1 段につき半径を 1 cm 広げる。
static func grab_radius(surface_type: StringName, dexterity_level: int) -> float:
	var flat: bool = surface_type in [
		MansionLayoutScript.SURFACE_FLOOR, MansionLayoutScript.SURFACE_FURNITURE]
	return (0.08 if flat else 0.04) + 0.01 * maxi(0, dexterity_level)


## 一度につまめる本数の段から、一度につまめる本数を返す
static func grab_count(grab_count_level: int) -> int:
	return clampi(BASE_GRAB_COUNT + maxi(0, grab_count_level), BASE_GRAB_COUNT, MAX_GRAB_COUNT)


## 手の強化の段の辞書 (保存データの hand_upgrade_levels) から指定した種類の段を返す (無ければ 0)
static func upgrade_level(hand_upgrade_levels: Dictionary, upgrade_id: StringName) -> int:
	return maxi(0, int(hand_upgrade_levels.get(upgrade_id, 0)))


## 指定した色の毛が珍しい毛のどれかになる確率の合計を返す
static func rare_chance_for_color(hair_color: StringName) -> float:
	var total: float = 0.0
	for rare: Dictionary in RARE_HAIRS:
		if _rare_applies_to_color(rare, hair_color):
			total += float(rare["chance"])
	return total


## つまんだ毛の色と 0 以上 1 未満の乱数 roll から、珍しい毛の種類を返す (ふつうの毛は空)。
## 表の並び順に確率を積み上げ、roll が入った区間の種類にする
static func roll_rare_hair(hair_color: StringName, roll: float) -> StringName:
	var threshold: float = 0.0
	for rare: Dictionary in RARE_HAIRS:
		if not _rare_applies_to_color(rare, hair_color):
			continue
		threshold += float(rare["chance"])
		if roll < threshold:
			return rare["id"]
	return &""


## 珍しい毛の表示名を返す (表に無い id は空文字)
static func rare_hair_name(rare_hair_id: StringName) -> String:
	for rare: Dictionary in RARE_HAIRS:
		if rare["id"] == rare_hair_id:
			return str(rare["name"])
	return ""


## 図鑑 (見つけた珍しい毛の一覧) に rare_hair_id を載せる。新しく載せたら true、既に載っているか空なら false
static func register_rare_hair(
	found_rare_hair_ids: Array[StringName], rare_hair_id: StringName
) -> bool:
	if rare_hair_id == &"" or found_rare_hair_ids.has(rare_hair_id):
		return false
	found_rare_hair_ids.append(rare_hair_id)
	return true


## 珍しい毛の表の 1 行が、指定した色の毛に出るか
static func _rare_applies_to_color(rare: Dictionary, hair_color: StringName) -> bool:
	var colors: Array = rare["colors"]
	return colors.is_empty() or colors.has(hair_color)

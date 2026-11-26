extends RefCounted
## 撮影と録画で、見たい所 (猫・掃除ロボット・部屋の中心) との間に家具を挟まずに立つ所を選ぶ手順
## (screenshot.gd と movie.gd が使う)。

## 猫の通り道の計算 (部屋の家具と壁際に入るかの判定を使う)
const CatRulesScript := preload("res://scripts/automation/cat_rules.gd")
## 立つ所と見たい所の間で、家具に入るかを確かめる点の数。撮る距離 (1.3〜2 m ほど) を 15 cm ほどの間隔で見て、いちばん薄い家具 (スーツ掛けの奥行き) を飛ばさない数
const LINE_SAMPLES: int = 12
## 試す向きの数 (真後ろから 45 度ずつ回す)。8 方向で、家具の間の通り道のどれかに当たる細かさ
const DIRECTIONS: int = 8


## room の中で、target (ワールド座標) から水平に distance 離れた所のうち、target との間に家具が無く、
## 立つ所が家具と壁際に入らない所を返す。preferred (水平の向き) から 45 度ずつ回して探し、どの向きも塞がる時は
## preferred の向きの所を返す
static func clear_spot(
	layout: MansionLayout,
	room: MansionLayout.RoomDef,
	target: Vector3,
	distance: float,
	preferred: Vector3,
) -> Vector3:
	var target_floor: Vector3 = Vector3(target.x, 0.0, target.z)
	var first: Vector3 = Vector3(preferred.x, 0.0, preferred.z)
	# 見たい所の真上・真下を向く向きは水平の向きが決まらないため、後ろの向きに置き換える (長さ 1 cm 未満)
	if first.length() < 0.01:
		first = Vector3.BACK
	first = first.normalized()
	for step: int in range(DIRECTIONS):
		var spot: Vector3 = (
			target_floor
			+ first.rotated(Vector3.UP, TAU * float(step) / float(DIRECTIONS)) * distance
		)
		if _is_line_clear(layout, room.room_id, spot, target_floor):
			return spot
	return target_floor + first * distance


## from から to までの床の上の点 (to の手前 15% は除く。見たい物そのものの足元は家具と重なってよい) が、
## どれも家具と壁際に入らないか
static func _is_line_clear(
	layout: MansionLayout, room_id: StringName, from: Vector3, to: Vector3
) -> bool:
	for sample: int in range(LINE_SAMPLES):
		var weight: float = 0.85 * float(sample) / float(LINE_SAMPLES - 1)
		if CatRulesScript.is_blocked(layout, room_id, from.lerp(to, weight)):
			return false
	return true

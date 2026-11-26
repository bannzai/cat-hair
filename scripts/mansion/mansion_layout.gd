class_name MansionLayout
extends RefCounted
## 調整値から決定論的に組み立てた屋敷 1 階の構造定義。
## 3D シーン構築とヘッドレス検証 (selfcheck) の両方がこの構造を入力にする。

## 表面の種類 (documents/DIRECTION.md「用語」・PROJECT.md「毛と表面」準拠)
const SURFACE_FLOOR: StringName = &"floor"
const SURFACE_CARPET: StringName = &"carpet"
const SURFACE_SOFA: StringName = &"sofa"
const SURFACE_KNIT: StringName = &"knit"
const SURFACE_SUIT: StringName = &"suit"
const SURFACE_FURNITURE: StringName = &"furniture"

## 屋敷 1 階の天井高さ (m)。洋館の開放感を出しつつ室内照明が床まで届く高さ
const CEILING_HEIGHT_M: float = 3.2
## 隣り合う部屋の間のドア開口幅 (m)。プレイヤー直径 0.7m の約 2.5 倍で引っかからず通過できる幅
const DOOR_WIDTH_M: float = 1.8
## ドア開口の高さ (m)。身長 1.7m に対して十分な頭上余裕がある標準的な洋館ドア高さ
const DOOR_HEIGHT_M: float = 2.4

## このレイアウトの入力になった調整値
var tuning: MansionTuning = null
## 1 階の部屋一覧 (RoomDef)
var rooms: Array[RoomDef] = []
## 屋敷に配置した物一覧 (ObjectDef)
var objects: Array[ObjectDef] = []
## 毛が付く表面一覧 (SurfaceDef。各部屋の床 + 各物の表面)
var surfaces: Array[SurfaceDef] = []
## 探し物の置き場所一覧 (FoundItemSpotDef)
var found_item_spots: Array[FoundItemSpotDef] = []
## 一人称プレイヤーの初期スポーン位置
var spawn_position: Vector3 = Vector3.ZERO
## 一人称プレイヤーの初期水平向き (ラジアン)
var spawn_yaw: float = 0.0


## 屋敷全体の床面積 (m^2) を返す
func total_floor_area() -> float:
	var area: float = 0.0
	for room: RoomDef in rooms:
		area += room.size.x * room.size.z
	return area


## 指定した表面 id の定義を返す。見つからなければ null
func find_surface(surface_id: StringName) -> SurfaceDef:
	for surface: SurfaceDef in surfaces:
		if surface.surface_id == surface_id:
			return surface
	return null


## 1 部屋分の間取りと開口部の定義
class RoomDef:
	extends RefCounted
	## 部屋を一意に識別する id
	var room_id: StringName = &""
	## 部屋の表示名 (玄関ホール・居間等)
	var display_name: String = ""
	## グリッド上の X 列番号 (0 起点)
	var grid_x: int = 0
	## グリッド上の Z 行番号 (0 起点)
	var grid_z: int = 0
	## 部屋床面の中心ワールド座標
	var center: Vector3 = Vector3.ZERO
	## 部屋の幅・天井高・奥行 (m)
	var size: Vector3 = Vector3.ZERO
	## 北側 (-Z) に隣室がありドア開口を設けるか
	var open_north: bool = false
	## 南側 (+Z) に隣室がありドア開口を設けるか
	var open_south: bool = false
	## 東側 (+X) に隣室がありドア開口を設けるか
	var open_east: bool = false
	## 西側 (-X) に隣室がありドア開口を設けるか
	var open_west: bool = false


## 屋敷に配置する 1 つの物 (家具・布など) の定義
class ObjectDef:
	extends RefCounted
	## 物を一意に識別する id
	var object_id: StringName = &""
	## この物が属する部屋の id
	var room_id: StringName = &""
	## 物の形状種別 (carpet / sofa / table / suit_rack / knit_chair / sideboard)
	var object_kind: StringName = &""
	## この物が持つ表面の種類 (MansionLayout.SURFACE_* 定数)
	var surface_type: StringName = &""
	## 物の底面中心のワールド座標
	var position: Vector3 = Vector3.ZERO
	## 物の幅・高さ・奥行 (m)
	var size: Vector3 = Vector3.ZERO
	## 物の Y 軸回転角 (ラジアン)
	var rotation_y: float = 0.0


## 毛が付く 1 つの表面の定義
class SurfaceDef:
	extends RefCounted
	## 表面を一意に識別する id (SurfaceHair.surface_id と対応)
	var surface_id: StringName = &""
	## この表面が属する部屋の id
	var room_id: StringName = &""
	## 表面の種類 (床・カーペット・ソファ・ニット・スーツ・家具)
	var surface_type: StringName = &""
	## 毛が乗る面の中心ワールド座標
	var center: Vector3 = Vector3.ZERO
	## 毛を散らす範囲の X / Z 全幅 (m)
	var extents: Vector2 = Vector2.ONE
	## 屋敷全体の毛を各表面へ分配する時の相対重み
	var hair_weight: float = 1.0


## 探し物を埋める置き場所 1 つの定義
class FoundItemSpotDef:
	extends RefCounted
	## 探し物を一意に識別する id (FoundItemProgress.found_item_id と対応)
	var found_item_id: StringName = &""
	## 置き場所がある部屋の id
	var room_id: StringName = &""
	## 置き場所が属する表面の id
	var surface_id: StringName = &""
	## 置き場所のワールド座標
	var position: Vector3 = Vector3.ZERO

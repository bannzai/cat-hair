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

## 屋敷の天井高さ (m)
const CEILING_HEIGHT_M: float = 3.2
## 隣り合う部屋の間のドア開口幅 (m)
const DOOR_WIDTH_M: float = 1.8
## ドア開口の高さ (m)
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


## 1 部屋分の定義
class RoomDef:
	extends RefCounted
	var room_id: StringName = &""
	var display_name: String = ""
	var grid_x: int = 0
	var grid_z: int = 0
	var center: Vector3 = Vector3.ZERO
	var size: Vector3 = Vector3.ZERO
	var open_north: bool = false
	var open_south: bool = false
	var open_east: bool = false
	var open_west: bool = false


## 屋敷に配置する 1 つの物 (家具・布など) の定義
class ObjectDef:
	extends RefCounted
	var object_id: StringName = &""
	var room_id: StringName = &""
	var object_kind: StringName = &""
	var surface_type: StringName = &""
	var position: Vector3 = Vector3.ZERO
	var size: Vector3 = Vector3.ZERO
	var rotation_y: float = 0.0


## 毛が付く 1 つの表面の定義
class SurfaceDef:
	extends RefCounted
	var surface_id: StringName = &""
	var room_id: StringName = &""
	var surface_type: StringName = &""
	var center: Vector3 = Vector3.ZERO
	var extents: Vector2 = Vector2.ONE
	var hair_weight: float = 1.0


## 探し物を埋める置き場所 1 つの定義
class FoundItemSpotDef:
	extends RefCounted
	var found_item_id: StringName = &""
	var room_id: StringName = &""
	var surface_id: StringName = &""
	var position: Vector3 = Vector3.ZERO

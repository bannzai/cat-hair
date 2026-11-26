class_name FirstPersonPlayer
extends CharacterBody3D
## 屋敷の中を歩く一人称プレイヤー。WASD / 矢印キーで移動し、マウスで視点を回す。

## 6m 部屋を約 1.4 秒で横切る一人称の標準歩行速度 (m/s)
const DEFAULT_MOVE_SPEED: float = 4.2
## 画面幅の半分 (640px) のマウス移動で約 90 度回転する標準感度 (rad/px)
const DEFAULT_MOUSE_SENSITIVITY: float = 0.0025
## 段差落下時に素早く接地させる重力加速度 (m/s^2)
const DEFAULT_GRAVITY: float = 18.0
## 初期ピッチ角 (rad。約 -10 度下向きで床・カーペット・家具が視界中央に収まる角度)
const INITIAL_PITCH_RADIANS: float = -0.18
## 上下視点のクランプ上限 (rad。約 ±77 度で真上・真下の視点反転を防ぐ)
const MAX_PITCH_RADIANS: float = 1.35
## 16:9 画面で室内空間を窮屈にせず端の歪みを抑えるカメラ視野角 (度)
const CAMERA_FOV_DEG: float = 72.0
## 壁際で近接クリッピングしにくいカメラ近平面 (m)
const CAMERA_NEAR_M: float = 0.05
## 最大 4x4 部屋 (64m 四方・対角約 90m) を見渡せるカメラ遠平面 (m)
const CAMERA_FAR_M: float = 120.0
## ドア幅 1.8m を余裕をもって通れるプレイヤー衝突カプセル半径 (m)
const CAPSULE_RADIUS_M: float = 0.35
## 成人の平均身長に相当する衝突カプセル全高 (m)
const CAPSULE_HEIGHT_M: float = 1.7
## 身長 1.7m に対応する一人称カメラの目線高さ (m)
const EYE_HEIGHT_M: float = 1.55

## 歩行速度 (m/s)
@export var move_speed: float = DEFAULT_MOVE_SPEED
## マウス感度 (rad/px)
@export var mouse_sensitivity: float = DEFAULT_MOUSE_SENSITIVITY
## 重力加速度 (m/s^2)
@export var gravity: float = DEFAULT_GRAVITY
## 入力を受け付けるか (タイトル画面や開発者画面が開いている間は false)
var controls_enabled: bool = false
## テスト等でマウス未捕捉のまま視点イベントを受け取るためのフラグ
var allow_uncaptured_look: bool = false

## 現在のカメラ上下ピッチ角 (ラジアン)
var _pitch: float = INITIAL_PITCH_RADIANS
## カメラのピッチ回転を担う頭部ノード
var _head: Node3D = null
## 一人称視点のカメラノード
var _camera: Camera3D = null


## シーンツリー参加時に衝突体とカメラリグを整える
func _ready() -> void:
	_ensure_rig()


## 屋敷内のスポーン位置と向きを設定し、移動速度をリセットする
func set_spawn(spawn_pos: Vector3, spawn_yaw: float) -> void:
	_ensure_rig()
	global_position = spawn_pos
	rotation = Vector3(0.0, spawn_yaw, 0.0)
	_pitch = INITIAL_PITCH_RADIANS
	_head.rotation = Vector3(_pitch, 0.0, 0.0)
	velocity = Vector3.ZERO


## 相対の視点移動量を適用する (テストやマウスイベントから呼ぶ)
func apply_look_delta(relative_delta: Vector2) -> void:
	_ensure_rig()
	rotate_y(-relative_delta.x * mouse_sensitivity)
	_pitch = clampf(
		_pitch - relative_delta.y * mouse_sensitivity,
		-MAX_PITCH_RADIANS,
		MAX_PITCH_RADIANS,
	)
	_head.rotation.x = _pitch


## 現在のピッチ角 (ラジアン) を返す
func get_pitch() -> float:
	return _pitch


## 一人称カメラを返す
func get_camera() -> Camera3D:
	_ensure_rig()
	return _camera


## 入力イベントがマウス捕捉を開始すべき左クリック押下かを判定する (純粋判定)
static func should_capture_mouse(event: InputEvent) -> bool:
	if not (event is InputEventMouseButton):
		return false
	var mouse_button_event: InputEventMouseButton = event
	return mouse_button_event.button_index == MOUSE_BUTTON_LEFT and mouse_button_event.pressed


## プレイ中のマウス捕捉・視点回転・Esc 解放を処理する
func _unhandled_input(event: InputEvent) -> void:
	if not controls_enabled:
		return
	if should_capture_mouse(event):
		if DisplayServer.get_name() != "headless":
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	elif event is InputEventMouseMotion:
		var mouse_motion_event: InputEventMouseMotion = event
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED or allow_uncaptured_look:
			apply_look_delta(mouse_motion_event.relative)
	elif event.is_action_pressed("release_mouse"):
		if DisplayServer.get_name() != "headless":
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


## 重力と WASD / 矢印キー入力から移動ベクトルを更新し衝突付きで移動する
func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	if controls_enabled:
		var input_vec: Vector2 = Input.get_vector(
			"move_left",
			"move_right",
			"move_forward",
			"move_back",
		)
		var move_direction: Vector3 = transform.basis * Vector3(input_vec.x, 0.0, input_vec.y)
		move_direction.y = 0.0
		if move_direction.length_squared() > 0.0001:
			move_direction = move_direction.normalized()
			velocity.x = move_direction.x * move_speed
			velocity.z = move_direction.z * move_speed
		else:
			velocity.x = 0.0
			velocity.z = 0.0
	else:
		velocity.x = 0.0
		velocity.z = 0.0

	move_and_slide()


## 衝突カプセル・頭部ノード・カメラが未生成なら組み立てる
func _ensure_rig() -> void:
	if _head != null and _camera != null:
		return
	if get_node_or_null("CollisionShape3D") == null:
		var capsule_shape: CapsuleShape3D = CapsuleShape3D.new()
		capsule_shape.radius = CAPSULE_RADIUS_M
		capsule_shape.height = CAPSULE_HEIGHT_M
		var collider: CollisionShape3D = CollisionShape3D.new()
		collider.name = "CollisionShape3D"
		collider.shape = capsule_shape
		collider.position = Vector3(0.0, CAPSULE_HEIGHT_M * 0.5, 0.0)
		add_child(collider)

	_head = get_node_or_null("Head")
	if _head == null:
		_head = Node3D.new()
		_head.name = "Head"
		_head.position = Vector3(0.0, EYE_HEIGHT_M, 0.0)
		add_child(_head)

	_camera = _head.get_node_or_null("Camera3D")
	if _camera == null:
		_camera = Camera3D.new()
		_camera.name = "Camera3D"
		_camera.fov = CAMERA_FOV_DEG
		_camera.near = CAMERA_NEAR_M
		_camera.far = CAMERA_FAR_M
		_camera.current = true
		_head.add_child(_camera)

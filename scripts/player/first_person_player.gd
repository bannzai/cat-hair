class_name FirstPersonPlayer
extends CharacterBody3D
## 屋敷の中を歩く一人称プレイヤー。WASD / 矢印キーで移動し、マウスで視点を回す。

## 歩行速度 (m/s)
@export var move_speed: float = 4.2
## マウス感度 (rad/px)
@export var mouse_sensitivity: float = 0.0025
## 重力加速度 (m/s^2)
@export var gravity: float = 18.0
## 入力を受け付けるか (タイトル画面や開発者画面が開いている間は false)
var controls_enabled: bool = false
## テスト等でマウス未捕捉のまま視点イベントを受け取るためのフラグ
var allow_uncaptured_look: bool = false

var _pitch: float = -0.18
var _head: Node3D = null
var _camera: Camera3D = null


func _ready() -> void:
	_ensure_rig()


## 屋敷内のスポーン位置と向きを設定し、移動速度をリセットする
func set_spawn(pos: Vector3, yaw: float) -> void:
	_ensure_rig()
	global_position = pos
	rotation = Vector3(0.0, yaw, 0.0)
	_pitch = -0.18
	_head.rotation = Vector3(_pitch, 0.0, 0.0)
	velocity = Vector3.ZERO


## 相対の視点移動量を適用する (テストやマウスイベントから呼ぶ)
func apply_look_delta(relative: Vector2) -> void:
	_ensure_rig()
	rotate_y(-relative.x * mouse_sensitivity)
	_pitch = clampf(_pitch - relative.y * mouse_sensitivity, -1.35, 1.35)
	_head.rotation.x = _pitch


## 現在のピッチ角 (ラジアン) を返す
func get_pitch() -> float:
	return _pitch


## 一人称カメラを返す
func get_camera() -> Camera3D:
	_ensure_rig()
	return _camera


func _unhandled_input(event: InputEvent) -> void:
	if not controls_enabled:
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if DisplayServer.get_name() != "headless":
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED or allow_uncaptured_look:
			apply_look_delta(mm.relative)
	elif event.is_action_pressed("release_mouse"):
		if DisplayServer.get_name() != "headless":
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


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
		var direction: Vector3 = (transform.basis * Vector3(input_vec.x, 0.0, input_vec.y))
		direction.y = 0.0
		if direction.length_squared() > 0.0001:
			velocity.x = 0.0
			velocity.z = 0.0
		else:
			velocity.x = 0.0
			velocity.z = 0.0
	else:
		velocity.x = 0.0
		velocity.z = 0.0

	move_and_slide()


func _ensure_rig() -> void:
	if _head != null and _camera != null:
		return
	if get_node_or_null("CollisionShape3D") == null:
		var shape: CapsuleShape3D = CapsuleShape3D.new()
		shape.radius = 0.35
		shape.height = 1.7
		var collider: CollisionShape3D = CollisionShape3D.new()
		collider.name = "CollisionShape3D"
		collider.shape = shape
		collider.position = Vector3(0.0, 0.85, 0.0)
		add_child(collider)

	_head = get_node_or_null("Head")
	if _head == null:
		_head = Node3D.new()
		_head.name = "Head"
		_head.position = Vector3(0.0, 1.55, 0.0)
		add_child(_head)

	_camera = _head.get_node_or_null("Camera3D")
	if _camera == null:
		_camera = Camera3D.new()
		_camera.name = "Camera3D"
		_camera.fov = 72.0
		_camera.near = 0.05
		_camera.far = 120.0
		_camera.current = true
		_head.add_child(_camera)

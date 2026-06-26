extends CharacterBody3D
## 🟦 即放即用的可控角色方块（俯视角搜打撤原型用）。
## 把 kit_player.tscn 拖进任意关卡场景即可：WASD / 方向键移动，按住 Shift 跑。
## 自带顶视跟随相机（auto_camera）。美术替换：把角色模型放进 player_model 槽，占位方块会自动隐藏。

@export var move_speed: float = 5.0       # 走速 m/s（与策划走速一致）
@export var run_speed: float = 8.0        # 跑速 m/s（按住 Shift）
@export var gravity: float = 24.0         # 重力（贴地/下台阶）；放在无地面的展示场景里可设 0 让其悬浮平移
@export var turn_lerp: float = 12.0       # 朝向插值速度
@export var auto_camera: bool = true      # true=自带顶视相机设为当前（即放即用）；想用关卡自己的相机时设 false
@export var control_enabled: bool = true  # 关掉则不响应输入（过场/被抓住时）
@export var player_model: PackedScene     # 美术替换槽：放角色模型则隐藏占位方块

@onready var _body: Node3D = $Body
@onready var _cam: Camera3D = $FollowCam


func _ready() -> void:
	if player_model != null:
		var inst: Node = player_model.instantiate()
		add_child(inst)
		if _body != null:
			_body.visible = false
	if auto_camera and _cam != null:
		_cam.current = true


func _physics_process(delta: float) -> void:
	var inp: Vector2 = _read_move() if control_enabled else Vector2.ZERO
	var dir := Vector3(inp.x, 0.0, inp.y)
	if dir.length() > 1.0:
		dir = dir.normalized()

	var running: bool = control_enabled and Input.is_key_pressed(KEY_SHIFT)
	var spd: float = run_speed if running else move_speed
	velocity.x = dir.x * spd
	velocity.z = dir.z * spd
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= gravity * delta
	move_and_slide()

	if dir.length() > 0.01 and _body != null:
		var target_yaw := atan2(-dir.x, -dir.z)
		_body.rotation.y = lerp_angle(_body.rotation.y, target_yaw, clampf(turn_lerp * delta, 0.0, 1.0))


## WASD + 方向键 → 平面移动向量（屏幕上：W=上=世界 -Z，D=右=世界 +X）。
## 直接读物理键，无需在 project.godot 里配置自定义输入动作。
func _read_move() -> Vector2:
	var v := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		v.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		v.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		v.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		v.y += 1.0
	return v

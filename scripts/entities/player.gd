extends CharacterBody3D

# ============================================================
# v11 Player: 状态机 + 走/跑动画反向修复（实测+ sign）
# ============================================================

# v11 §3：动画符号控制（实测后写死）。anim_test_mode 提交时必须为 false。
# 实测结论（2026-12-09，详见 CHANGELOG_v10_to_v11.md §3）：
#   静态 ArmL.rotation.x=-75°*sign 时 HandL 在 BodyRoot 局部坐标系下
#   z = -0.42 * sin(-75°*sign)。player facing -Z（前=-Z）。
#   sign=+1 → HandL.z=+0.406（身后，错）
#   sign=-1 → HandL.z=-0.406（身前，对）  ← 实测正确值
@export var anim_test_mode: bool = false
@export var arm_swing_sign: float = -1.0   # 走/跑摆臂方向
@export var leg_swing_sign: float = -1.0   # 走/跑腿摆方向
@export var arm_lift_sign: float = -1.0    # LOOTING/EXTRACTING/庆祝/弯腰 静态前抬

const WALK_SPEED: float = 4.5
const RUN_SPEED: float = 7.5
const ACCEL: float = 30.0
const DECEL: float = 20.0
const GRAVITY: float = 18.0

# v8 §3 落地兜底
const FALL_THRESHOLD: float = -1.5
const RESPAWN_POS: Vector3 = Vector3(0, 1, 0)

# §8 Idle 参数
const IDLE_BREATH_FREQ: float = 1.6
const IDLE_BREATH_AMP: float = 0.015
const IDLE_SWAY_FREQ: float = 0.7
const IDLE_SWAY_AMP: float = 0.012
const HEAD_TURN_MIN: float = 2.5
const HEAD_TURN_MAX: float = 5.0
const HEAD_TURN_DEG: float = 20.0
const TURN_SPEED: float = 10.0
const RESET_LERP: float = 10.0

enum PlayerState { IDLE, WALK, RUN, LOOTING, EXTRACTING }

var movement_locked: bool = false
var nearby_container: Node = null

# 外卖侠 §四:当前动作档位 + 声音半径(给 §五 声音系统)
var current_stance: int = Stance.Mode.WALK
var current_sound_radius: float = Stance.WALK_SOUND_RADIUS

# v8 §4.3 interactables
var _candidates: Array = []
var _nearest: Node = null

var _state: int = PlayerState.IDLE
var _state_time: float = 0.0
var _current_speed_v: Vector3 = Vector3.ZERO
var _bob_timer: float = 0.0
var _yaw: float = 0.0
var _idle_t: float = 0.0
var _next_head_turn_at: float = 3.0
var _head_target_yaw_offset: float = 0.0
var _current_head_yaw: float = 0.0

# v10：节点引用使用 @onready 简化别名（同时保留旧字段名以最小改动）
@onready var body_root: Node3D = $BodyRoot
@onready var head: Node3D = $BodyRoot/Head
@onready var head_outline: Node3D = $BodyRoot/HeadOutline
@onready var helmet: Node3D = $BodyRoot/Helmet
@onready var arm_l: Node3D = $BodyRoot/ArmL
@onready var arm_r: Node3D = $BodyRoot/ArmR
@onready var leg_l: Node3D = $BodyRoot/LegL
@onready var leg_r: Node3D = $BodyRoot/LegR

var _stamina: Node = null
var _bus: Node = null

func _ready() -> void:
	add_to_group("player")
	_stamina = get_node_or_null("/root/Stamina")
	_bus = get_node_or_null("/root/EventBus")

	# v9 §4.B 防御：确保 player 碰撞层正确
	collision_layer = 2
	collision_mask = 1

	if _bus != null:
		if _bus.has_signal("container_opened") and not _bus.container_opened.is_connected(_on_container_opened):
			_bus.container_opened.connect(_on_container_opened)
		if _bus.has_signal("container_closed") and not _bus.container_closed.is_connected(_on_container_closed):
			_bus.container_closed.connect(_on_container_closed)
		if _bus.has_signal("round_ended") and not _bus.round_ended.is_connected(_on_round_ended):
			_bus.round_ended.connect(_on_round_ended)

	for ez in get_tree().get_nodes_in_group("extraction_zone"):
		if ez.has_signal("countdown_started") and not ez.countdown_started.is_connected(_on_extraction_started):
			ez.countdown_started.connect(_on_extraction_started)
		if ez.has_signal("countdown_aborted") and not ez.countdown_aborted.is_connected(_on_extraction_aborted):
			ez.countdown_aborted.connect(_on_extraction_aborted)
		if ez.has_signal("countdown_succeeded") and not ez.countdown_succeeded.is_connected(_on_extraction_succeeded):
			ez.countdown_succeeded.connect(_on_extraction_succeeded)

	# v11 §3：anim_test_mode 仅在调试时启用（提交时为 false）；运行时即把
	# arm_l/leg_l 设到测试姿势，并把 transform 比对结果存到 test_* 字段供 assert 读
	if anim_test_mode:
		_run_anim_test_sync()

# v8 §4.3 interactables 注册
func register_interactable(obj: Node) -> void:
	if obj == null:
		return
	if not _candidates.has(obj):
		_candidates.append(obj)

func unregister_interactable(obj: Node) -> void:
	_candidates.erase(obj)
	if _nearest == obj:
		_nearest = null

func _update_nearest_interactable() -> void:
	var cleaned: Array = []
	for c in _candidates:
		if c == null:
			continue
		if not is_instance_valid(c):
			continue
		if c.has_method("is_available") and not c.is_available():
			continue
		cleaned.append(c)
	_candidates = cleaned

	var best: Node = null
	var best_d: float = INF
	for c in _candidates:
		var p: Vector3
		if c.has_method("get_interact_position"):
			p = c.get_interact_position()
		elif c is Node3D:
			p = (c as Node3D).global_position
		else:
			continue
		var d: float = global_position.distance_to(p)
		if d < best_d:
			best_d = d
			best = c
	_nearest = best
	if _bus != null and _bus.has_signal("interact_prompt"):
		var txt: String = ""
		if _nearest != null and _nearest.has_method("get_prompt"):
			txt = _nearest.get_prompt()
		_bus.interact_prompt.emit(txt)

func _input(event: InputEvent) -> void:
	if movement_locked:
		return
	if event.is_action_pressed("interact"):
		_update_nearest_interactable()
		if _nearest != null and is_instance_valid(_nearest) and _nearest.has_method("interact"):
			if _nearest.is_in_group("doors"):
				_nearest.interact(self)
				get_viewport().set_input_as_handled()

func _physics_process(delta: float) -> void:
	if global_position.y < FALL_THRESHOLD:
		global_position = RESPAWN_POS
		velocity = Vector3.ZERO
		_current_speed_v = Vector3.ZERO

	var input_v := Vector2.ZERO
	if not movement_locked:
		input_v.x = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
		input_v.y = Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
		if input_v.length() > 1.0:
			input_v = input_v.normalized()

	var direction: Vector3 = Vector3(input_v.x, 0.0, input_v.y)

	# 外卖侠 §四 三档:潜行 / 走路 / 奔跑
	var wants_sneak: bool = not movement_locked and Input.is_action_pressed("sneak")
	var raw_wants_run: bool = (
		not movement_locked
		and direction != Vector3.ZERO
		and Input.is_action_pressed("sprint")
	)
	# sneak 优先:潜行时 sprint 输入忽略,且强制停掉 stamina running
	var wants_run: bool = raw_wants_run and not wants_sneak
	var is_running: bool = false
	if _stamina != null:
		if wants_run:
			is_running = _stamina.try_start_run()
		else:
			if _stamina.is_running():
				_stamina.stop_run()
			is_running = false

	current_stance = Stance.resolve(wants_sneak, raw_wants_run, is_running)
	current_sound_radius = Stance.sound_radius(current_stance)
	var target_speed: float = Stance.speed(current_stance)
	var target_v: Vector3 = direction * target_speed
	var rate: float = ACCEL if direction != Vector3.ZERO else DECEL
	_current_speed_v = _current_speed_v.move_toward(target_v, rate * delta)

	velocity.x = _current_speed_v.x
	velocity.z = _current_speed_v.z
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0
	move_and_slide()

	if direction != Vector3.ZERO:
		_yaw = atan2(-direction.x, -direction.z)
	if body_root != null:
		var cur_y: float = body_root.rotation.y
		body_root.rotation.y = lerp_angle(cur_y, _yaw, clamp(TURN_SPEED * delta, 0.0, 1.0))

	_update_state(delta, direction, is_running)
	_update_nearest_interactable()

func _update_state(delta: float, direction: Vector3, is_running: bool) -> void:
	var moving: bool = direction != Vector3.ZERO
	var prev_state: int = _state
	if _state == PlayerState.LOOTING or _state == PlayerState.EXTRACTING:
		pass
	else:
		if not moving:
			_state = PlayerState.IDLE
		elif is_running:
			_state = PlayerState.RUN
		else:
			_state = PlayerState.WALK

	if _state != prev_state:
		_state_time = 0.0
		_bob_timer = 0.0

	_state_time += delta

	match _state:
		PlayerState.IDLE:
			_animate_idle(delta)
		PlayerState.WALK:
			_animate_walk(delta)
		PlayerState.RUN:
			_animate_walk(delta)
		PlayerState.LOOTING:
			_animate_looting(delta)
		PlayerState.EXTRACTING:
			_animate_extracting(delta)

# ============================================================
# §3-A v10：走/跑动画 反向摆臂修复
# ============================================================
func _animate_walk(delta: float) -> void:
	var current_speed := Vector2(velocity.x, velocity.z).length()
	if current_speed < 0.1:
		return
	var is_running := false
	if _stamina != null and _stamina.has_method("is_running"):
		is_running = _stamina.is_running()
	var freq: float = current_speed * 0.55
	_bob_timer += delta * freq
	var phase := _bob_timer * TAU
	var bob_amp: float = 0.03 if is_running else 0.02
	body_root.position.y = lerpf(body_root.position.y, -abs(sin(phase * 2.0)) * bob_amp, delta * 12.0)
	var target_tilt: float = deg_to_rad(-12.0) if is_running else 0.0
	body_root.rotation.x = lerpf(body_root.rotation.x, target_tilt, delta * 4.0)
	var arm_swing_amp: float = deg_to_rad(20.0) if is_running else deg_to_rad(14.0)
	var elbow_lift: float = deg_to_rad(-35.0) * arm_lift_sign if is_running else 0.0
	var arm_swing := sin(phase) * arm_swing_amp * arm_swing_sign
	# v11 §3：sign 实测后写死（v9/v10 推理修两次都没修对，这次走 print + run）
	arm_l.rotation.x = lerpf(arm_l.rotation.x, elbow_lift - arm_swing, delta * 14.0)
	arm_r.rotation.x = lerpf(arm_r.rotation.x, elbow_lift + arm_swing, delta * 14.0)
	if is_running:
		arm_l.rotation.z = lerpf(arm_l.rotation.z, deg_to_rad(8.0), delta * 6.0)
		arm_r.rotation.z = lerpf(arm_r.rotation.z, deg_to_rad(-8.0), delta * 6.0)
	else:
		arm_l.rotation.z = lerpf(arm_l.rotation.z, 0.0, delta * 6.0)
		arm_r.rotation.z = lerpf(arm_r.rotation.z, 0.0, delta * 6.0)
	var leg_swing_amp: float = deg_to_rad(18.0) if is_running else deg_to_rad(12.0)
	var leg_swing := sin(phase) * leg_swing_amp * leg_swing_sign
	# v11 §3：腿与手反相（同侧手脚反相 = 真实步态）
	leg_l.rotation.x = lerpf(leg_l.rotation.x, leg_swing, delta * 14.0)
	leg_r.rotation.x = lerpf(leg_r.rotation.x, -leg_swing, delta * 14.0)
	if head != null:
		head.rotation = Vector3.ZERO
	if helmet != null:
		helmet.rotation = Vector3.ZERO

# ============================================================
# §8 Idle 动画
# ============================================================
func _animate_idle(delta: float) -> void:
	if body_root == null:
		return
	_idle_t += delta

	if _state_time < delta * 1.5:
		_lerp_limbs_to_zero(1.0)

	var breath: float = sin(_idle_t * TAU * IDLE_BREATH_FREQ * 0.5) * IDLE_BREATH_AMP
	body_root.scale = Vector3(1.0, 1.0 + breath, 1.0)

	var sway: float = sin(_idle_t * TAU * IDLE_SWAY_FREQ * 0.5) * IDLE_SWAY_AMP
	body_root.position.y = sway

	body_root.rotation.x = lerp(body_root.rotation.x, 0.0, clamp(delta * RESET_LERP, 0.0, 1.0))
	_lerp_limbs_to_zero(clamp(delta * RESET_LERP, 0.0, 1.0))

	if _idle_t >= _next_head_turn_at:
		_head_target_yaw_offset = deg_to_rad(randf_range(-HEAD_TURN_DEG, HEAD_TURN_DEG))
		_next_head_turn_at = _idle_t + randf_range(HEAD_TURN_MIN, HEAD_TURN_MAX)
	_current_head_yaw = lerp(_current_head_yaw, _head_target_yaw_offset, clamp(delta * 3.0, 0.0, 1.0))
	if head != null:
		head.rotation.y = _current_head_yaw

# ============================================================
# §3-B v10：LOOTING 动画
# ============================================================
func _animate_looting(delta: float) -> void:
	body_root.rotation.x = lerpf(body_root.rotation.x, deg_to_rad(-20.0), delta * 4.0)
	body_root.position.y = lerpf(body_root.position.y, -0.08, delta * 4.0)
	# 腿保持垂直（蹲感由 body_root 下移+前倾达成；单段腿没膝盖不要弯）
	leg_l.rotation.x = lerpf(leg_l.rotation.x, 0.0, delta * 4.0)
	leg_r.rotation.x = lerpf(leg_r.rotation.x, 0.0, delta * 4.0)
	var t := fmod(_state_time, 1.6)
	var half := 0.8
	if t < half:
		var p := t / half
		var lh := -sin(p * PI) * deg_to_rad(75.0) * arm_lift_sign  # v11 §3 sign
		arm_l.rotation.x = lerpf(arm_l.rotation.x, lh, delta * 12.0)
		arm_r.rotation.x = lerpf(arm_r.rotation.x, deg_to_rad(-15.0) * arm_lift_sign, delta * 6.0)
	else:
		var p := (t - half) / half
		var rh := -sin(p * PI) * deg_to_rad(75.0) * arm_lift_sign
		arm_r.rotation.x = lerpf(arm_r.rotation.x, rh, delta * 12.0)
		arm_l.rotation.x = lerpf(arm_l.rotation.x, deg_to_rad(-15.0) * arm_lift_sign, delta * 6.0)
	arm_l.rotation.z = lerpf(arm_l.rotation.z, deg_to_rad(15.0), delta * 4.0)
	arm_r.rotation.z = lerpf(arm_r.rotation.z, deg_to_rad(-15.0), delta * 4.0)
	head.rotation.x = lerpf(head.rotation.x, deg_to_rad(-25.0), delta * 5.0)
	if head_outline != null:
		head_outline.rotation.x = head.rotation.x
	# v10 §4：hair → helmet（同步低头）
	if helmet:
		helmet.rotation.x = head.rotation.x

# §6.5 退出 LOOTING 时回正
func _exit_looting_reset() -> void:
	var dur: float = 0.25
	var tw := create_tween()
	tw.set_parallel(true)
	tw.set_trans(Tween.TRANS_SINE)
	if head != null:
		tw.tween_property(head, "rotation:x", 0.0, dur)
		tw.tween_property(head, "rotation:y", 0.0, dur)
	if head_outline != null:
		tw.tween_property(head_outline, "rotation:x", 0.0, dur)
	if helmet != null:
		tw.tween_property(helmet, "rotation:x", 0.0, dur)
	if arm_l != null:
		tw.tween_property(arm_l, "rotation:z", 0.0, dur)
	if arm_r != null:
		tw.tween_property(arm_r, "rotation:z", 0.0, dur)

# ============================================================
# §3-C v10：EXTRACTING 动画（去掉腿弯，scale.y 压扁 + 下移）
# ============================================================
func _animate_extracting(delta: float) -> void:
	body_root.scale = body_root.scale.lerp(Vector3(1, 0.85, 1), delta * 5.0)
	body_root.position.y = lerpf(body_root.position.y, -0.15, delta * 5.0)
	arm_l.rotation.x = lerpf(arm_l.rotation.x, deg_to_rad(-80.0) * arm_lift_sign, delta * 5.0)
	arm_r.rotation.x = lerpf(arm_r.rotation.x, deg_to_rad(-80.0) * arm_lift_sign, delta * 5.0)
	arm_l.rotation.y = lerpf(arm_l.rotation.y, deg_to_rad(20.0), delta * 5.0)
	arm_r.rotation.y = lerpf(arm_r.rotation.y, deg_to_rad(-20.0), delta * 5.0)
	leg_l.rotation.x = lerpf(leg_l.rotation.x, 0.0, delta * 5.0)
	leg_r.rotation.x = lerpf(leg_r.rotation.x, 0.0, delta * 5.0)

# ============================================================
# 工具
# ============================================================
func _lerp_limbs_to_zero(t: float) -> void:
	t = clamp(t, 0.0, 1.0)
	if arm_l != null:
		arm_l.rotation = arm_l.rotation.lerp(Vector3.ZERO, t)
	if arm_r != null:
		arm_r.rotation = arm_r.rotation.lerp(Vector3.ZERO, t)
	if leg_l != null:
		leg_l.rotation = leg_l.rotation.lerp(Vector3.ZERO, t)
	if leg_r != null:
		leg_r.rotation = leg_r.rotation.lerp(Vector3.ZERO, t)

func reset_motion() -> void:
	velocity = Vector3.ZERO
	_current_speed_v = Vector3.ZERO
	_bob_timer = 0.0
	_state = PlayerState.IDLE
	_state_time = 0.0
	if body_root != null:
		body_root.position = Vector3.ZERO
		body_root.rotation = Vector3.ZERO
		body_root.scale = Vector3.ONE
	if arm_l != null:
		arm_l.rotation = Vector3.ZERO
	if arm_r != null:
		arm_r.rotation = Vector3.ZERO
	if leg_l != null:
		leg_l.rotation = Vector3.ZERO
	if leg_r != null:
		leg_r.rotation = Vector3.ZERO
	if head != null:
		head.rotation = Vector3.ZERO
	if head_outline != null:
		head_outline.rotation = Vector3.ZERO
	if helmet != null:
		helmet.rotation = Vector3.ZERO
	if _stamina != null:
		_stamina.stop_run()

func set_nearby(c: Node) -> void:
	nearby_container = c

func clear_nearby(c: Node) -> void:
	if nearby_container == c:
		nearby_container = null

# ============================================================
# 信号回调
# ============================================================
func _on_container_opened(_c) -> void:
	_state = PlayerState.LOOTING
	_state_time = 0.0
	_bob_timer = 0.0

func _on_container_closed(_c) -> void:
	if _state == PlayerState.LOOTING:
		_state = PlayerState.IDLE
		_state_time = 0.0
		_exit_looting_reset()
		_lerp_limbs_to_zero(1.0)

func _on_extraction_started(_total_time: float) -> void:
	_state = PlayerState.EXTRACTING
	_state_time = 0.0
	_bob_timer = 0.0

func _on_extraction_aborted() -> void:
	if _state == PlayerState.EXTRACTING:
		_state = PlayerState.IDLE
		_state_time = 0.0
		_lerp_limbs_to_zero(1.0)

func _on_extraction_succeeded() -> void:
	_play_celebration()

func _on_round_ended(_total: int, reason: String) -> void:
	if reason == "extracted":
		_play_celebration()
	else:
		_play_defeat()

func _play_celebration() -> void:
	if body_root == null:
		return
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.set_trans(Tween.TRANS_SINE)
	tw.tween_property(body_root, "position:y", 0.6, 0.25)
	tw.tween_property(body_root, "position:y", 0.0, 0.30)
	tw.tween_property(body_root, "position:y", 0.4, 0.20)
	tw.tween_property(body_root, "position:y", 0.0, 0.25)
	if arm_l != null:
		var tw2 := create_tween()
		tw2.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tw2.tween_property(arm_l, "rotation:x", deg_to_rad(-160.0) * arm_lift_sign, 0.3)
	if arm_r != null:
		var tw3 := create_tween()
		tw3.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tw3.tween_property(arm_r, "rotation:x", deg_to_rad(-160.0) * arm_lift_sign, 0.3)

# §3-D v11：弯腰（-30），双臂前抬带 sign
func _play_defeat() -> void:
	if body_root == null:
		return
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.set_trans(Tween.TRANS_SINE)
	tw.set_parallel(true)
	tw.tween_property(body_root, "rotation:x", deg_to_rad(-30) * arm_lift_sign, 0.5)  # 弯腰带 sign
	tw.tween_property(arm_l, "rotation:x", deg_to_rad(-150) * arm_lift_sign, 0.5)
	tw.tween_property(arm_r, "rotation:x", deg_to_rad(-150) * arm_lift_sign, 0.5)
	tw.tween_property(arm_l, "rotation:y", deg_to_rad(40), 0.5)
	tw.tween_property(arm_r, "rotation:y", deg_to_rad(-40), 0.5)

# v11 §3：anim_test_mode 静态前抬测试 + 把结果存到 metadata 供 assert 读
var test_hand_z_minus_arm_z: float = 0.0
var test_hand_in_front: bool = false
var test_arm_l_pos: Vector3 = Vector3.ZERO
var test_hand_l_pos: Vector3 = Vector3.ZERO
var test_leg_l_pos: Vector3 = Vector3.ZERO
var test_facing: Vector3 = Vector3.ZERO

func _run_anim_test_sync() -> void:
	if arm_l != null:
		arm_l.rotation = Vector3.ZERO
		arm_l.rotation.x = deg_to_rad(-75.0) * arm_lift_sign
	else:
		return
	if arm_r != null:
		arm_r.rotation = Vector3.ZERO
	if leg_l != null:
		leg_l.rotation = Vector3.ZERO
		leg_l.rotation.x = deg_to_rad(20.0) * leg_swing_sign
	if leg_r != null:
		leg_r.rotation = Vector3.ZERO
	if body_root != null:
		body_root.rotation = Vector3.ZERO
	movement_locked = true
	# 用 local transform 直接算 HandL 在 BodyRoot 空间下的 z 坐标
	var arm_l_node := arm_l as Node3D
	var hand_l := get_node_or_null("BodyRoot/ArmL/HandL") as Node3D
	var leg_l_node := leg_l as Node3D
	var foot_l := get_node_or_null("BodyRoot/LegL/BootL") as Node3D
	if arm_l_node != null and hand_l != null:
		var hand_in_armL: Transform3D = hand_l.transform
		var hand_in_bodyroot: Transform3D = arm_l_node.transform * hand_in_armL
		test_arm_l_pos = arm_l_node.transform.origin
		test_hand_l_pos = hand_in_bodyroot.origin
		test_hand_z_minus_arm_z = hand_in_bodyroot.origin.z - arm_l_node.transform.origin.z
		test_hand_in_front = hand_in_bodyroot.origin.z < arm_l_node.transform.origin.z
	var leg_z: float = 0.0
	var foot_z: float = 0.0
	if leg_l_node != null:
		test_leg_l_pos = leg_l_node.transform.origin
		leg_z = leg_l_node.transform.origin.z
		if foot_l != null:
			var foot_in_bodyroot: Transform3D = leg_l_node.transform * foot_l.transform
			foot_z = foot_in_bodyroot.origin.z
	# player.basis.z（Vector3.BACK 方向，即 +Z）；玩家朝向 -Z = -basis.z
	test_facing = -global_transform.basis.z

	# 写到 res://anim_test_dump.txt（编辑模式可写）
	var f := FileAccess.open("res://anim_test_dump.txt", FileAccess.WRITE)
	if f != null:
		f.store_line("=== ANIM TEST DUMP ===")
		f.store_line("signs: arm_swing=%f leg_swing=%f arm_lift=%f" % [arm_swing_sign, leg_swing_sign, arm_lift_sign])
		f.store_line("player.basis.z = " + str(global_transform.basis.z) + " (player faces -basis.z)")
		f.store_line("player_facing (-basis.z) = " + str(test_facing))
		f.store_line("--- ArmL test (rotation.x = -75deg * arm_lift_sign = %fdeg) ---" % rad_to_deg(deg_to_rad(-75.0) * arm_lift_sign))
		f.store_line("ArmL.local_pos = " + str(test_arm_l_pos))
		f.store_line("HandL.in_bodyroot.pos = " + str(test_hand_l_pos))
		f.store_line("HandL.z - ArmL.z = %f (negative = HandL more forward when player faces -Z)" % test_hand_z_minus_arm_z)
		f.store_line("hand_in_front (HandL.z < ArmL.z) = " + str(test_hand_in_front))
		f.store_line("--- LegL test (rotation.x = 20deg * leg_swing_sign = %fdeg) ---" % rad_to_deg(deg_to_rad(20.0) * leg_swing_sign))
		f.store_line("LegL.local_pos = " + str(test_leg_l_pos))
		f.store_line("FootL.in_bodyroot.z = %f" % foot_z)
		f.store_line("FootL.z - LegL.z = %f (negative = foot forward; positive = foot behind)" % (foot_z - leg_z))
		f.store_line("foot_in_front (FootL.z < LegL.z) = " + str(foot_z < leg_z))
		# 各 rotation.x（rad + deg）
		f.store_line("--- rotations.x ---")
		if arm_l != null:
			f.store_line("arm_l.rotation.x = %f rad / %f deg" % [arm_l.rotation.x, rad_to_deg(arm_l.rotation.x)])
		if arm_r != null:
			f.store_line("arm_r.rotation.x = %f rad / %f deg" % [arm_r.rotation.x, rad_to_deg(arm_r.rotation.x)])
		if leg_l != null:
			f.store_line("leg_l.rotation.x = %f rad / %f deg" % [leg_l.rotation.x, rad_to_deg(leg_l.rotation.x)])
		if leg_r != null:
			f.store_line("leg_r.rotation.x = %f rad / %f deg" % [leg_r.rotation.x, rad_to_deg(leg_r.rotation.x)])
		if head != null:
			f.store_line("head.rotation.x = %f rad / %f deg" % [head.rotation.x, rad_to_deg(head.rotation.x)])
		f.store_line("=== END ===")
		f.close()
	# quit 让 godot_run_project 提早结束
	get_tree().quit()

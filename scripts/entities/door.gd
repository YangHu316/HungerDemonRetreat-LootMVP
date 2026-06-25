extends StaticBody3D
class_name Door

# v9 §4.B —— 门接口（DoorAssembly 子节点 Door）
# v11 fix-3 §2 修复关键：DoorCollision 移回 Door 直接子节点（Godot 4
# 要求 CollisionShape3D 是 CollisionObject3D 的直接子，否则不参与物理碰撞）。
# 开/关门时通过 Tween 同步驱动 _door_coll 的 transform，使其围绕铰链旋转。

const OPEN_ANGLE_DEG: float = 90.0
const CLOSE_ANGLE_DEG: float = 0.0
const TWEEN_TIME: float = 0.18
# §06 Phase 3B 发声覆盖 — spec 05§1.2:大门·开门 8-10m。取 8 作 MVP
const DOOR_TOGGLE_SOUND_RADIUS: float = 8.0

# 铰链相对 Door 的局部位置（左侧边）
const HINGE_LOCAL: Vector3 = Vector3(-0.6, 0.0, 0.0)
# CollisionShape 在关门状态下相对 Door 原点的位置（关门正中线）
const COLL_BASE_POS: Vector3 = Vector3(0.0, 1.0, 0.0)

var is_open: bool = false
var _busy: bool = false
var _bus: Node = null
var _pivot: Node3D = null
var _door_coll: CollisionShape3D = null
var _interact_area: Area3D = null
var _current_angle: float = 0.0  # 当前门角度（弧度），由 _process 同步 collision

func _ready() -> void:
	add_to_group("interactables")
	add_to_group("doors")
	_bus = get_node_or_null("/root/EventBus")
	_pivot = get_node_or_null("DoorPivot") as Node3D

	# v9 §4.B 防御代码：保证门在 World 层 / 玩家可碰撞
	collision_layer = 1
	collision_mask = 0

	# v11 fix-3：DoorCollision 是 Door 直接子节点（脱离 Pivot）
	_door_coll = get_node_or_null("DoorCollision") as CollisionShape3D
	if _door_coll != null:
		if _door_coll.shape == null:
			var bs := BoxShape3D.new()
			bs.size = Vector3(1.2, 2.0, 0.15)
			_door_coll.shape = bs
		_door_coll.disabled = false
		_apply_collision_transform(0.0)

	# v10 修复：InteractArea body_entered → 玩家 register_interactable
	var parent_node: Node = get_parent()
	if parent_node != null:
		_interact_area = parent_node.get_node_or_null("InteractArea") as Area3D
	if _interact_area != null:
		if not _interact_area.body_entered.is_connected(_on_body_entered):
			_interact_area.body_entered.connect(_on_body_entered)
		if not _interact_area.body_exited.is_connected(_on_body_exited):
			_interact_area.body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node) -> void:
	if body == null:
		return
	if body.is_in_group("player") and body.has_method("register_interactable"):
		body.register_interactable(self)

func _on_body_exited(body: Node) -> void:
	if body == null:
		return
	if body.is_in_group("player") and body.has_method("unregister_interactable"):
		body.unregister_interactable(self)

func _exit_tree() -> void:
	pass

# ── interactables 协议 ──
func get_interact_position() -> Vector3:
	var p: Node3D = get_parent() as Node3D
	if p != null:
		return p.global_position
	return global_position

func get_prompt() -> String:
	return "按 F 关门" if is_open else "按 F 开门"

func is_available() -> bool:
	return true

func interact(_player: Node) -> void:
	toggle()

func toggle() -> void:
	# Phase 2B fix bug 6:门状态多人同步
	# 单人:本地直接 _apply_toggle_local
	# 多人:走 mm.notify_door_toggle → host 校验 + 广播 → 各 peer _apply_toggle_local
	var mm = get_node_or_null("/root/MultiplayerManager")
	if mm == null or (mm.has_method("is_single") and mm.is_single()):
		_apply_toggle_local()
	else:
		if mm.has_method("notify_door_toggle"):
			mm.notify_door_toggle(String(self.get_path()))

# 真正执行开/关门的本地逻辑(给 RPC 和单人共用,幂等于 is_open 状态切换)
func _apply_toggle_local() -> void:
	if _pivot == null:
		_pivot = get_node_or_null("DoorPivot") as Node3D
	if _pivot == null:
		return
	is_open = not is_open
	var target_deg: float = OPEN_ANGLE_DEG if is_open else CLOSE_ANGLE_DEG
	var target_rad: float = deg_to_rad(target_deg)
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE)
	tw.set_ease(Tween.EASE_IN_OUT)
	tw.set_parallel(true)
	# 视觉：DoorPivot 旋转
	tw.tween_property(_pivot, "rotation:y", target_rad, TWEEN_TIME)
	# 物理：CollisionShape3D 同步旋转（绕 HINGE_LOCAL 旋转）
	tw.tween_method(Callable(self, "_apply_collision_transform"), _current_angle, target_rad, TWEEN_TIME)
	tw.chain().tween_callback(Callable(self, "_on_tween_done"))
	if _bus != null and _bus.has_signal("door_toggled"):
		_bus.door_toggled.emit(self, is_open)
	# §06 Phase 3B 发声 — 大门开关 8m(单人;多人 host 权威 Phase 2C 再做)
	_emit_door_sound()

# §06 Phase 3B 大门开/关声音(spec 05§1.2)
func _emit_door_sound() -> void:
	var mm = get_node_or_null("/root/MultiplayerManager")
	if mm != null and mm.has_method("is_single") and not mm.is_single():
		return
	if _bus == null or not _bus.has_signal("sound_emitted"):
		return
	# 用 DoorAssembly(parent)的位置作声源点 — 门本身在 hinge 旋转,位置不准
	var pos: Vector3 = global_position
	var p: Node3D = get_parent() as Node3D
	if p != null:
		pos = p.global_position
	_bus.sound_emitted.emit(pos, DOOR_TOGGLE_SOUND_RADIUS)

func _apply_collision_transform(angle_rad: float) -> void:
	# 围绕 HINGE_LOCAL 把 COLL_BASE_POS 旋转 angle_rad
	_current_angle = angle_rad
	if _door_coll == null:
		return
	var local := COLL_BASE_POS - HINGE_LOCAL  # = (0.6, 1.0, 0)
	var c := cos(angle_rad)
	var s := sin(angle_rad)
	# 绕 Y 轴旋转
	var rotated := Vector3(local.x * c + local.z * s, local.y, -local.x * s + local.z * c)
	var final_pos := HINGE_LOCAL + rotated
	var t := Transform3D.IDENTITY
	t.basis = Basis(Vector3.UP, angle_rad)
	t.origin = final_pos
	_door_coll.transform = t

func _on_tween_done() -> void:
	_busy = false

func reset_state() -> void:
	# 跨局重置：关闭并归位
	_busy = false
	is_open = false
	rotation = Vector3.ZERO
	if _pivot == null:
		_pivot = get_node_or_null("DoorPivot") as Node3D
	if _pivot != null:
		_pivot.rotation = Vector3.ZERO
	if _door_coll == null:
		_door_coll = get_node_or_null("DoorCollision") as CollisionShape3D
	if _door_coll != null:
		if _door_coll.shape == null:
			var bs := BoxShape3D.new()
			bs.size = Vector3(1.2, 2.0, 0.15)
			_door_coll.shape = bs
		_door_coll.disabled = false
		_apply_collision_transform(0.0)

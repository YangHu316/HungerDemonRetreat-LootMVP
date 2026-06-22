extends Node3D

@export var tuning: Resource  # CameraTuning
@export var target_path: NodePath

var target: Node3D
var virtual_target: Vector3 = Vector3.ZERO
var offset_from_target_x: float = 0.0
var offset_from_target_z: float = 0.0
var forward_horiz: Vector3 = Vector3.FORWARD
var right_horiz: Vector3 = Vector3.RIGHT

@onready var yaw_root: Node3D = $YawRoot
@onready var pitch_root: Node3D = $YawRoot/PitchRoot
@onready var camera: Camera3D = $YawRoot/PitchRoot/Camera3D

func _ready() -> void:
	if tuning == null:
		tuning = load("res://resources/tuning/camera_default.tres")
	if target_path != NodePath("") and target == null:
		var n: Node = get_node_or_null(target_path)
		if n is Node3D:
			target = n
	yaw_root.rotation_degrees = Vector3(0, tuning.yaw_degrees, 0)
	pitch_root.rotation_degrees = Vector3(-tuning.pitch_degrees, 0, 0)
	camera.transform.origin = Vector3(0, 0, tuning.distance)
	camera.fov = tuning.fov
	_update_camera_vectors()

func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	_update_camera_vectors()
	_update_aim_offset(delta)
	var base: Vector3 = target.global_position + Vector3(0, tuning.height_offset, 0)
	virtual_target = base + forward_horiz * offset_from_target_z + right_horiz * offset_from_target_x
	var t: float = clamp(tuning.lerp_speed_normal * delta, 0.0, 1.0)
	global_position = global_position.lerp(virtual_target, t)

func _update_camera_vectors() -> void:
	var basis: Basis = camera.global_transform.basis
	var fwd: Vector3 = -basis.z
	var rgt: Vector3 = basis.x
	fwd.y = 0.0
	rgt.y = 0.0
	if fwd.length() > 0.0001:
		forward_horiz = fwd.normalized()
	if rgt.length() > 0.0001:
		right_horiz = rgt.normalized()

func _screen_point_to_character_plane(screen_pos: Vector2) -> Vector3:
	if target == null:
		return Vector3.ZERO
	var plane_y: float = target.global_position.y + tuning.height_offset
	var origin: Vector3 = camera.project_ray_origin(screen_pos)
	var dir: Vector3 = camera.project_ray_normal(screen_pos)
	if abs(dir.y) < 0.0001:
		return target.global_position
	var t: float = (plane_y - origin.y) / dir.y
	if t < 0.0:
		return target.global_position
	return origin + dir * t

func _update_aim_offset(delta: float) -> void:
	var vp: Viewport = get_viewport()
	if vp == null:
		return
	var vp_size: Vector2 = vp.get_visible_rect().size
	var mouse_pos: Vector2 = vp.get_mouse_position()
	var screen_center: Vector2 = vp_size * 0.5
	var center_world: Vector3 = _screen_point_to_character_plane(screen_center)
	var mouse_world: Vector3 = _screen_point_to_character_plane(mouse_pos)
	var diff: Vector3 = mouse_world - center_world
	diff.y = 0.0
	var max_len: float = tuning.default_aim_offset
	if diff.length() > max_len:
		diff = diff.normalized() * max_len
	var fwd_amt: float = diff.dot(forward_horiz)
	var right_amt: float = diff.dot(right_horiz)
	var factor: float = tuning.aim_offset_distance_factor
	var tgt_z: float = clamp(fwd_amt, -max_len, max_len) * factor
	var tgt_x: float = clamp(right_amt, -max_len, max_len) * factor
	var t: float = clamp(tuning.lerp_speed_normal * delta, 0.0, 1.0)
	offset_from_target_z = lerp(offset_from_target_z, tgt_z, t)
	offset_from_target_x = lerp(offset_from_target_x, tgt_x, t)

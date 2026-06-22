extends Control

# 自绘搜索进度（圆环 + 旋转放大镜）
@export var examine_time: float = 0.8
var progress: float = 0.0
var angle: float = 0.0

signal completed

func _ready() -> void:
	custom_minimum_size = Vector2(80, 80)
	size = Vector2(80, 80)

func _process(delta: float) -> void:
	progress += delta / examine_time
	angle += TAU * delta
	queue_redraw()
	if progress >= 1.0:
		progress = 1.0
		completed.emit()
		set_process(false)

func _draw() -> void:
	var center := Vector2(40, 40)
	var ring_color := Color("#ffd040")
	var bg_color := Color(0, 0, 0, 0.5)
	# 背景圆
	draw_circle(center, 32, bg_color)
	# 进度弧
	var pts := PackedVector2Array()
	var steps: int = 48
	var end_a: float = -PI * 0.5 + TAU * progress
	for i in steps + 1:
		var t: float = float(i) / steps
		var a: float = -PI * 0.5 + (end_a - (-PI * 0.5)) * t
		pts.append(center + Vector2(cos(a), sin(a)) * 28)
	for i in pts.size() - 1:
		draw_line(pts[i], pts[i + 1], ring_color, 4.0)
	# 放大镜（围绕中心旋转）
	var r: float = angle
	var lens_offset := Vector2(cos(r), sin(r)) * 14
	var lens_center: Vector2 = center + lens_offset
	draw_arc(lens_center, 8, 0, TAU, 24, Color.WHITE, 2.0)
	var handle_dir := lens_offset.normalized() if lens_offset.length() > 0.01 else Vector2(1, 1).normalized()
	draw_line(lens_center + handle_dir * 6, lens_center + handle_dir * 14, Color.WHITE, 2.5)

@tool
extends Node3D
## 关卡度量 / 校验 HUD（编辑器内可见·不影响运行）。
## 用法：在你的关卡根下加一个 Node3D，把本脚本拖给它；在 Inspector 里：
##   · 设 spawn_path / extract_path（指到出生/撤离的 Marker3D 或节点）→ 画连线 + 显示路程/估时；
##   · 拖动 probe（声音探针位置）→ 在该点画 1.5/5/8/12/15m 声半径环，看"这里有多吵/谁会被惊动"；
##   · 勾一下 redraw 可强制刷新。
## 这是给【人手搓】关卡时的尺子：判断声音暴露、视线长度、单程距离是否~5min。

@export var spawn_path: NodePath
@export var extract_path: NodePath
@export var walk_speed := 5.0                       ## 普通行走 m/s（用于估时）
@export var probe := Vector3.ZERO                    ## 声音探针位置（看这点的声半径环）
@export var sound_radii: Array[float] = [1.5, 5.0, 8.0, 12.0, 15.0]  ## 静步/走/搜中噪/跑/落水
@export var redraw := false: set = _set_redraw

var _mi: MeshInstance3D
var _label: Label3D
var _font: SystemFont


func _set_redraw(_v: bool) -> void:
	_rebuild()


func _ready() -> void:
	if Engine.is_editor_hint():
		_ensure()
		_rebuild()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_rebuild()


func _ensure() -> void:
	if _mi == null:
		_mi = MeshInstance3D.new()
		_mi.mesh = ImmediateMesh.new()
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		m.no_depth_test = true
		_mi.material_override = m
		add_child(_mi)
	if _label == null:
		_font = SystemFont.new()
		_font.font_names = PackedStringArray(["Microsoft YaHei", "SimHei", "Noto Sans CJK SC"])
		_label = Label3D.new()
		_label.font = _font
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_label.no_depth_test = true
		_label.modulate = Color(1, 1, 0.6)
		_label.outline_size = 6
		add_child(_label)


func _rebuild() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	_ensure()
	var im := _mi.mesh as ImmediateMesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for r: float in sound_radii:
		_ring(im, probe, r, Color(0.4, 0.8, 1.0))
	var sp := _np(spawn_path)
	var ex := _np(extract_path)
	if sp != null and ex != null:
		_line(im, sp.global_position, ex.global_position, Color(0.3, 1.0, 0.4))
	im.surface_end()

	if sp != null and ex != null:
		var d := sp.global_position.distance_to(ex.global_position)
		_label.text = "出生→撤离 直线 %.0fm ≈ %.0fs（走 %.1fm/s）\n注：含搜刮/小游戏/躲避，实际单局应≈300s" % [d, d / max(walk_speed, 0.1), walk_speed]
		_label.global_position = (sp.global_position + ex.global_position) * 0.5 + Vector3(0, 5, 0)
	else:
		_label.text = "设置 spawn_path / extract_path"
		_label.global_position = probe + Vector3(0, 5, 0)


func _ring(im: ImmediateMesh, c: Vector3, r: float, col: Color) -> void:
	var seg := 48
	for i in seg:
		var a0 := TAU * float(i) / float(seg)
		var a1 := TAU * float(i + 1) / float(seg)
		im.surface_set_color(col)
		im.surface_add_vertex(c + Vector3(cos(a0) * r, 0.15, sin(a0) * r))
		im.surface_set_color(col)
		im.surface_add_vertex(c + Vector3(cos(a1) * r, 0.15, sin(a1) * r))


func _line(im: ImmediateMesh, a: Vector3, b: Vector3, col: Color) -> void:
	im.surface_set_color(col)
	im.surface_add_vertex(a + Vector3(0, 0.2, 0))
	im.surface_set_color(col)
	im.surface_add_vertex(b + Vector3(0, 0.2, 0))


func _np(p: NodePath) -> Node3D:
	if p.is_empty():
		return null
	return get_node_or_null(p) as Node3D

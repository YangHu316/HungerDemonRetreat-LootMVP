extends Node3D
## 《饿魔退散！外卖侠》小游戏 · 🧊敲冰开柜 —— 白盒复现（多格盲盒 + 擦玻璃 + 连点砸碎）
## 玩法：冰柜分 1×1/2×2/3×3，每格一件按概率随机稀有度食物，初始毛玻璃看不清。
##  · 每个冰柜给 1 次"擦玻璃"机会（只能擦 1 格）→ 擦开的格能看清内容（含名称）。
##  · 玩家选 1 格，连点砸碎该格（点击数随稀有度 4/6/10/15/20）取出。
##  · 砸开后：所有格内容名称揭示（知道选了什么、舍弃了什么），其余格食物变质报废（发黑+绿烟）。
##  · 名称悬浮在内容上方，颜色＝品质色。无失败。
##
## 操作：左键=砸冰(首击锁定该格) / 右键=擦玻璃(1次,看清1格) / 1·2·3=冰柜大小 / R=重置

enum Rarity { COMMON, QUALITY, RARE, LEGENDARY, MYTH }
enum CabinetSize { S1X1 = 1, S2X2 = 2, S3X3 = 3 }

# ───────── 可配置参数（不写死）─────────
@export var cabinet_size: CabinetSize = CabinetSize.S2X2
@export var click_counts: Dictionary = {
	Rarity.COMMON: 4, Rarity.QUALITY: 6, Rarity.RARE: 10,
	Rarity.LEGENDARY: 15, Rarity.MYTH: 20,
}
## 稀有度生成概率（权重）：白40 / 绿30 / 蓝20 / 紫9 / 金1
@export var rarity_weights: Dictionary = {
	Rarity.COMMON: 40.0, Rarity.QUALITY: 30.0, Rarity.RARE: 20.0,
	Rarity.LEGENDARY: 9.0, Rarity.MYTH: 1.0,
}
@export var frosted_doors: bool = true     # 初始毛玻璃看不清；靠擦玻璃揭示
@export var wipes_per_cabinet: int = 1      # 每柜可擦玻璃次数
@export var crack_stages: int = 4
@export var refreeze_delay: float = 5.0

@export_group("爽感 Juice（人手调）")
@export var hit_trauma: float = 0.16
@export var hit_trauma_growth: float = 0.16
@export var shatter_trauma: float = 1.0
@export var trauma_decay: float = 1.5
@export var freeze_frame_time: float = 0.09

# ───────── 接入大地图 ─────────
signal finished(result: Dictionary)         # 取出食物(完成)时发出 → 主循环收回控制
## standalone=true：沙盒模式，自带相机/环境/光照/地面并自动开始（仅 F5 调试）。
## false（默认，接大地图）：只搭冰柜几何体作为世界道具，用宿主相机拾取/取景。
@export var standalone := false

# ───────── 美术替换槽（留空=灰盒；大部分应换成 3D 模型）─────────
@export_group("美术替换槽")
@export var cabinet_model: PackedScene      # 冰柜外壳（背板/四壁/机头/踢脚整体）
@export var food_models: Dictionary = {}    # 食物名 → PackedScene(3D 模型)，替换图片
@export var shard_model: PackedScene        # 碎玻璃 / 碎冰 单片
@export_group("")

const RARITY_COLOR := {
	Rarity.COMMON: Color(0.86, 0.87, 0.90),
	Rarity.QUALITY: Color(0.34, 0.86, 0.40),
	Rarity.RARE: Color(0.30, 0.60, 1.00),
	Rarity.LEGENDARY: Color(0.70, 0.38, 0.98),
	Rarity.MYTH: Color(1.00, 0.82, 0.20),
}
const RARITY_NAME := {
	Rarity.COMMON: "普通", Rarity.QUALITY: "优质", Rarity.RARE: "稀有",
	Rarity.LEGENDARY: "传说", Rarity.MYTH: "神话",
}
## 内容物命名库
const RARITY_FOODS := {
	Rarity.COMMON: ["米饭", "馒头", "面包", "地瓜", "玉米", "挂面"],
	Rarity.QUALITY: ["包子", "饺子", "炒饭", "蘑菇汤"],
	Rarity.RARE: ["汉堡", "盖饭", "水果蛋糕"],
	Rarity.LEGENDARY: ["黯然销魂饭", "烧鹅"],
	Rarity.MYTH: ["佛跳墙"],
}

# ───────── 状态机 ─────────
enum State { IDLE, SMASHING, SHATTER, RESOLVE, DONE }
var state: int = State.IDLE
var chosen: int = -1
var wipes_left: int = 1
var time_since_hit: float = 0.0
var refreeze_accum: float = 0.0

# 布局
const FACE_W := 2.0
const FACE_H := 2.3
const CELL_GAP := 0.07
const BODY_DEPTH := 0.85          # 冰箱箱体深度（向后延伸；玻璃门在最前）
var glass_center := Vector3(0.0, 1.35, 0.5)   # 冰箱正面（玻璃门）平面中心

# 节点
var cam_rig: Node3D
var camera: Camera3D
var cam_base_pos: Vector3
var cam_base_rot: Vector3
var cam_base_fov: float
var trauma: float = 0.0

var cabinet_root: Node3D
var shards_root: Node3D
var cells: Array = []

var ui_font: Font          # 中文字体（系统字体，解决 CJK 显示）
var _tex_cache: Dictionary = {}   # 食物图片缓存
var overlay: Control
var lbl_title: Label
var lbl_prompt: Label
var flash: ColorRect


func _ready() -> void:
	randomize()
	_make_font()
	_build_world()
	_build_ui()
	if standalone:
		_setup_standalone_view()
	start_round()


## 公开入口：宿主在玩家交互时调用，开一局新柜。
func begin() -> void:
	start_round()


## 是否处于开发者模式（F1 开关 · 全局 Dev autoload）——决定测试快捷键是否生效。
func _dev_on() -> bool:
	var n := get_node_or_null("/root/Dev")
	return n != null and bool(n.get("enabled"))


## 当前用于拾取/裂纹投影的相机：自带相机优先，否则用宿主(视口)当前相机。
func _cam() -> Camera3D:
	return camera if camera != null else get_viewport().get_camera_3d()


func _make_font() -> void:
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "SimHei", "SimSun", "Noto Sans CJK SC"])
	sf.allow_system_fallback = true
	ui_font = sf


# ════════════════════ 世界（几何容器，相对自身原点，可整体摆进大地图）════════════════════
func _build_world() -> void:
	cabinet_root = Node3D.new()
	add_child(cabinet_root)
	shards_root = Node3D.new()
	add_child(shards_root)


## 沙盒/独立运行：自带环境 + 光照 + 相机 + 地面（接大地图时不调用，用宿主的）。
func _setup_standalone_view() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.06, 0.09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.50, 0.62)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -34.0, 0.0)
	sun.light_energy = 1.15
	add_child(sun)

	cam_rig = Node3D.new()
	add_child(cam_rig)
	camera = Camera3D.new()
	camera.fov = 50.0
	cam_rig.add_child(camera)
	camera.position = Vector3(0.0, 2.6, 4.2)
	camera.look_at(Vector3(0.0, 1.3, 0.35), Vector3.UP)
	camera.current = true
	cam_base_pos = camera.position
	cam_base_rot = camera.rotation
	cam_base_fov = camera.fov

	var floor_body := StaticBody3D.new()
	var floor_col := CollisionShape3D.new()
	floor_col.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(floor_col)
	var floor_mi := MeshInstance3D.new()
	var floor_pm := PlaneMesh.new()
	floor_pm.size = Vector2(16.0, 16.0)
	floor_mi.mesh = floor_pm
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.11, 0.12, 0.15)
	floor_mi.material_override = floor_mat
	floor_body.add_child(floor_mi)
	add_child(floor_body)


## 加载食物图片（res://eft_greybox/assets/food/<名称>.jpg）；缺图则返回纯色占位贴图
func _food_texture(food_name: String, fallback: Color) -> Texture2D:
	if _tex_cache.has(food_name):
		return _tex_cache[food_name]
	var tex: Texture2D = null
	for ext in [".jpg", ".png", ".jpeg", ".webp"]:
		var path := "res://eft_greybox/assets/food/%s%s" % [food_name, ext]
		if ResourceLoader.exists(path):
			tex = load(path)          # 已导入纹理（编辑器内/导出安全）
			if tex != null:
				break
		if FileAccess.file_exists(path):
			var img := Image.new()    # 原始加载兜底（未导入时，如纯命令行）
			if img.load(path) == OK:
				tex = ImageTexture.create_from_image(img)
				break
	if tex == null:
		var pimg := Image.create_empty(8, 8, false, Image.FORMAT_RGBA8)
		pimg.fill(fallback)
		tex = ImageTexture.create_from_image(pimg)
	_tex_cache[food_name] = tex
	return tex


func _pick_rarity() -> int:
	var total := 0.0
	for k in rarity_weights:
		total += float(rarity_weights[k])
	if total <= 0.0:
		return Rarity.COMMON
	var r := randf() * total
	var acc := 0.0
	for k in [Rarity.COMMON, Rarity.QUALITY, Rarity.RARE, Rarity.LEGENDARY, Rarity.MYTH]:
		acc += float(rarity_weights.get(k, 0.0))
		if r < acc:
			return k
	return Rarity.COMMON


# ════════════════════ 冰柜（网格）════════════════════
func _build_cabinet() -> void:
	for ch in cabinet_root.get_children():
		ch.queue_free()
	cells.clear()
	var dim := int(cabinet_size)

	var c := glass_center
	var bz := c.z - BODY_DEPTH * 0.5   # 箱体中心 z：玻璃门在前 c.z，箱体向后延伸
	var t := 0.14
	var border := 0.16

	# 内壁（冷白，内胆感）—— 分隔 / 背板用
	var inner_mat := StandardMaterial3D.new()
	inner_mat.albedo_color = Color(0.82, 0.87, 0.94)
	inner_mat.roughness = 0.55
	# 门把手 / 踢脚（深灰金属）
	var trim_mat := StandardMaterial3D.new()
	trim_mat.albedo_color = Color(0.26, 0.27, 0.30)
	trim_mat.roughness = 0.35
	trim_mat.metallic = 0.6

	# 冰箱外壳：美术模型整体替换，或灰盒方块拼
	if cabinet_model != null:
		var cmnode := cabinet_model.instantiate() as Node3D
		cmnode.position = glass_center   # 约定：模型以正面(玻璃门)中心为锚点
		cabinet_root.add_child(cmnode)
	else:
		var body_mat := StandardMaterial3D.new()   # 白色微金属外壳
		body_mat.albedo_color = Color(0.91, 0.92, 0.94)
		body_mat.roughness = 0.45
		body_mat.metallic = 0.18
		# 背板（箱体最后面，内胆色）
		_box(Vector3(c.x, c.y, c.z - BODY_DEPTH), Vector3(FACE_W + border, FACE_H + border, 0.06), inner_mat)
		# 箱体四壁（全部在玻璃门后方，深度 BODY_DEPTH）
		_box(Vector3(c.x, c.y + FACE_H * 0.5 + t * 0.5, bz), Vector3(FACE_W + border + 2 * t, t, BODY_DEPTH), body_mat)   # 顶
		_box(Vector3(c.x, c.y - FACE_H * 0.5 - t * 0.5, bz), Vector3(FACE_W + border + 2 * t, t, BODY_DEPTH), body_mat)   # 底
		_box(Vector3(c.x - FACE_W * 0.5 - t * 0.5, c.y, bz), Vector3(t, FACE_H + border, BODY_DEPTH), body_mat)           # 左
		_box(Vector3(c.x + FACE_W * 0.5 + t * 0.5, c.y, bz), Vector3(t, FACE_H + border, BODY_DEPTH), body_mat)           # 右
		# 顶部机头
		_box(Vector3(c.x, c.y + FACE_H * 0.5 + t + 0.13, bz - 0.02), Vector3(FACE_W + border + 2 * t, 0.24, BODY_DEPTH - 0.04), body_mat)
		# 底部踢脚
		_box(Vector3(c.x, c.y - FACE_H * 0.5 - t - 0.14, bz), Vector3(FACE_W + border + 2 * t, 0.2, BODY_DEPTH), trim_mat)

	# 内部分隔（箱体内、玻璃门后）
	var cw := FACE_W / dim
	var ch_ := FACE_H / dim
	for i in range(1, dim):
		_box(Vector3(c.x - FACE_W * 0.5 + cw * i, c.y, bz), Vector3(0.045, FACE_H, BODY_DEPTH * 0.92), inner_mat)
		_box(Vector3(c.x, c.y + FACE_H * 0.5 - ch_ * i, bz), Vector3(FACE_W, 0.045, BODY_DEPTH * 0.92), inner_mat)

	var idx := 0
	for r in dim:
		for col in dim:
			_build_cell(idx, r, col, cw, ch_, trim_mat)
			idx += 1


func _build_cell(index: int, r: int, col: int, cw: float, ch_: float, trim_mat: Material) -> void:
	var c := glass_center
	var center := Vector3(c.x - FACE_W * 0.5 + cw * (col + 0.5), c.y + FACE_H * 0.5 - ch_ * (r + 0.5), c.z)
	var gw := cw - CELL_GAP
	var gh := ch_ - CELL_GAP
	var rar := _pick_rarity()
	var col_food: Color = RARITY_COLOR[rar]
	var foods: Array = RARITY_FOODS[rar]
	var food_name: String = foods[randi() % foods.size()]

	# 食物：用图片（Sprite3D）替代圆球，藏玻璃后；缺图自动用纯色占位
	var food := RigidBody3D.new()
	food.freeze = true
	food.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	var fr := minf(gw, gh) * 0.30
	food.position = center + Vector3(0.0, 0.0, -0.42)
	var sprite: Sprite3D = null
	if food_models.has(food_name):
		food.add_child((food_models[food_name] as PackedScene).instantiate())   # 3D 食物模型替换图片
	else:
		sprite = Sprite3D.new()
		sprite.texture = _food_texture(food_name, col_food)
		sprite.shaded = false
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		var ts := sprite.texture.get_size()
		var target := minf(gw, gh) * 0.80   # 缩放让图片容纳在格子中
		sprite.pixel_size = target / maxf(maxf(ts.x, ts.y), 1.0)
		food.add_child(sprite)
	var fcol := CollisionShape3D.new()
	var fsh := SphereShape3D.new()
	fsh.radius = fr
	fcol.shape = fsh
	food.add_child(fcol)
	food.visible = not frosted_doors
	cabinet_root.add_child(food)

	# 悬浮名称（Label3D，颜色＝品质色）
	var nl := Label3D.new()
	nl.text = food_name
	nl.font = ui_font
	nl.font_size = 80
	nl.modulate = col_food
	nl.outline_size = 10
	nl.outline_modulate = Color(0, 0, 0, 0.9)
	nl.pixel_size = 0.0018   # 名称字体缩小到原来的 1/2
	nl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	nl.no_depth_test = true
	nl.position = center + Vector3(0.0, gh * 0.5 + 0.14, 0.12)
	nl.visible = not frosted_doors
	cabinet_root.add_child(nl)

	# 玻璃
	var glass := MeshInstance3D.new()
	var gbm := BoxMesh.new()
	gbm.size = Vector3(gw, gh, 0.05)
	glass.mesh = gbm
	glass.position = center + Vector3(0, 0, 0.05)   # 玻璃门前移：作为正面盖子，而非格中挡板
	var gmat := StandardMaterial3D.new()
	gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.material_override = gmat
	cabinet_root.add_child(glass)

	# 点击碰撞体（与前移的玻璃门对齐）
	var body := StaticBody3D.new()
	body.position = center + Vector3(0, 0, 0.05)
	var bcol := CollisionShape3D.new()
	var bsh := BoxShape3D.new()
	bsh.size = Vector3(gw, gh, 0.1)
	bcol.shape = bsh
	body.add_child(bcol)
	body.set_meta("cell_index", index)
	cabinet_root.add_child(body)

	# 冰箱门把手（深灰金属竖条，正面右侧）
	var handle := MeshInstance3D.new()
	var hbm := BoxMesh.new()
	hbm.size = Vector3(0.04, gh * 0.55, 0.05)
	handle.mesh = hbm
	handle.material_override = trim_mat
	handle.position = center + Vector3(gw * 0.42, 0.0, 0.10)
	cabinet_root.add_child(handle)

	var cell := {
		"index": index, "center": center, "gw": gw, "gh": gh,
		"glass": glass, "glass_mat": gmat, "body": body,
		"food": food, "food_sprite": sprite, "name_label": nl,
		"rarity": rar, "name": food_name,
		"required": int(click_counts.get(rar, 10)), "clicks": 0,
		"cracks": [], "opened": false, "spoiled": false, "revealed": not frosted_doors,
	}
	cells.append(cell)
	_set_glass_frosted(cell, frosted_doors)


func _box(pos: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	cabinet_root.add_child(mi)


func _set_glass_frosted(cell: Dictionary, frosted: bool) -> void:
	var gmat: StandardMaterial3D = cell["glass_mat"]
	if frosted:
		gmat.albedo_color = Color(0.85, 0.91, 1.00, 0.97)  # 毛玻璃：看不清
		gmat.roughness = 0.8
	else:
		gmat.albedo_color = Color(0.80, 0.90, 1.00, 0.26)  # 擦开：透明可见
		gmat.roughness = 0.16


## 揭示一格内容（擦玻璃 / 砸开时全揭示）
func _reveal_cell(cell: Dictionary, wipe_anim: bool = false) -> void:
	cell["revealed"] = true
	cell["food"].visible = true
	cell["name_label"].visible = true
	if wipe_anim:
		var gmat: StandardMaterial3D = cell["glass_mat"]
		gmat.roughness = 0.16
		var tw := create_tween()
		tw.tween_method(func(a): _glass_alpha(cell, a), 0.97, 0.26, 0.3)
	else:
		_set_glass_frosted(cell, false)


func _glass_alpha(cell: Dictionary, a: float) -> void:
	var gmat: StandardMaterial3D = cell["glass_mat"]
	var col := gmat.albedo_color
	col.a = a
	gmat.albedo_color = col


# ════════════════════ UI ════════════════════
func _build_ui() -> void:
	var cl := CanvasLayer.new()
	add_child(cl)

	flash = ColorRect.new()
	flash.color = Color(1, 1, 1, 0)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(flash)

	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(_on_overlay_draw)
	cl.add_child(overlay)

	lbl_title = _mk_label(cl, 24, Vector2(24, 18))
	lbl_title.add_theme_color_override("font_color", Color.WHITE)

	lbl_prompt = Label.new()
	lbl_prompt.add_theme_font_override("font", ui_font)
	lbl_prompt.add_theme_font_size_override("font_size", 23)
	lbl_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_prompt.anchor_left = 0.5
	lbl_prompt.anchor_right = 0.5
	lbl_prompt.anchor_top = 1.0
	lbl_prompt.anchor_bottom = 1.0
	lbl_prompt.offset_left = -420
	lbl_prompt.offset_right = 420
	lbl_prompt.offset_top = -120
	lbl_prompt.offset_bottom = -78
	cl.add_child(lbl_prompt)

	var help := Label.new()
	help.add_theme_font_override("font", ui_font)
	help.text = "左键 = 砸冰（破碎前可随时改敲别格）    右键 = 擦玻璃（每柜 1 次，看清 1 格）    1·2·3 = 冰柜大小    R = 重置"
	help.add_theme_font_size_override("font_size", 15)
	help.anchor_top = 1.0
	help.anchor_bottom = 1.0
	help.offset_left = 24
	help.offset_top = -34
	help.offset_bottom = -12
	cl.add_child(help)


func _mk_label(parent: Node, size: int, pos: Vector2) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", ui_font)
	l.add_theme_font_size_override("font_size", size)
	l.position = pos
	parent.add_child(l)
	return l


# ════════════════════ 回合 ════════════════════
func start_round() -> void:
	state = State.IDLE
	chosen = -1
	wipes_left = wipes_per_cabinet
	time_since_hit = 0.0
	refreeze_accum = 0.0
	for ch in shards_root.get_children():
		ch.queue_free()
	_build_cabinet()
	overlay.queue_redraw()

	if cam_rig != null:        # 自带相机的入场推近；接大地图取景由主循环控制
		cam_rig.position = Vector3(0.0, 0.45, 0.85)
		var tw := create_tween()
		tw.tween_property(cam_rig, "position", Vector3.ZERO, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_update_ui()


func _set_size(s: int) -> void:
	cabinet_size = s
	start_round()


# ════════════════════ 输入 ════════════════════
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_try_smash(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_try_wipe(event.position)
	elif event is InputEventKey and event.pressed and not event.echo and _dev_on():
		match event.keycode:   # 测试快捷键：需开发者模式(F1)
			KEY_1: _set_size(CabinetSize.S1X1)
			KEY_2: _set_size(CabinetSize.S2X2)
			KEY_3: _set_size(CabinetSize.S3X3)
			KEY_R: start_round()


func _raycast_cell(screen_pos: Vector2):
	var cam := _cam()
	if cam == null:
		return null
	var from := cam.project_ray_origin(screen_pos)
	var to := from + cam.project_ray_normal(screen_pos) * 30.0
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collide_with_areas = false
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return null
	var coll = hit.get("collider")
	if coll == null or not coll.has_meta("cell_index"):
		return null
	return {"cell": cells[coll.get_meta("cell_index")], "pos": hit.position}


func _try_wipe(screen_pos: Vector2) -> void:
	if wipes_left <= 0 or state == State.SHATTER or state == State.RESOLVE or state == State.DONE:
		return
	var r = _raycast_cell(screen_pos)
	if r == null:
		return
	var cell = r["cell"]
	if cell["revealed"] or cell["opened"]:
		return
	wipes_left -= 1
	_reveal_cell(cell, true)
	_flash(0.10)
	_update_ui()


func _try_smash(screen_pos: Vector2) -> void:
	if state == State.SHATTER or state == State.RESOLVE or state == State.DONE:
		return
	var r = _raycast_cell(screen_pos)
	if r == null:
		return
	var cell = r["cell"]
	if cell["opened"] or cell["spoiled"]:
		return
	# 随时可改：点哪格就砸哪格、并切换焦点；各格各自累计进度（破碎前都能改敲别格）
	chosen = cell["index"]
	state = State.SMASHING
	_smash_cell(cell, r["pos"])


func _smash_cell(cell: Dictionary, point: Vector3) -> void:
	cell["clicks"] += 1
	time_since_hit = 0.0
	refreeze_accum = 0.0
	var progress := float(cell["clicks"]) / float(cell["required"])
	_add_crack_burst(cell, point, progress)
	_add_trauma(hit_trauma + hit_trauma_growth * progress)
	_punch_fov(1.2 + 3.0 * (0.35 + progress))
	_flash(0.10 + 0.13 * progress)
	_update_ui()
	if cell["clicks"] >= cell["required"]:
		_open_cell(cell)


# ════════════════════ 裂纹 ════════════════════
func _add_crack_burst(cell: Dictionary, point: Vector3, progress: float) -> void:
	var stage := clampi(int(progress * crack_stages), 0, crack_stages - 1)
	var n := 4 + stage * 2
	var width := 1.6 + float(stage) * 0.9
	var ccol := Color(0.93, 0.97, 1.0, 0.96)
	var base := point + Vector3(0, 0, 0.03)
	var segs: Array = cell["cracks"]
	for i in n:
		var ang := randf() * TAU
		var ln := randf_range(0.05, 0.10 + progress * 0.16)
		var b := _clamp_to_cell(cell, base + Vector3(cos(ang), sin(ang), 0.0) * ln)
		segs.append({"a": base, "b": b, "w": width, "c": ccol})
		if randf() < 0.55:
			var b2 := _clamp_to_cell(cell, b + Vector3(cos(ang + 0.7), sin(ang + 0.7), 0.0) * ln * 0.6)
			segs.append({"a": b, "b": b2, "w": width * 0.7, "c": ccol})
	overlay.queue_redraw()


func _clamp_to_cell(cell: Dictionary, p: Vector3) -> Vector3:
	var c: Vector3 = cell["center"]
	p.x = clamp(p.x, c.x - cell["gw"] * 0.5, c.x + cell["gw"] * 0.5)
	p.y = clamp(p.y, c.y - cell["gh"] * 0.5, c.y + cell["gh"] * 0.5)
	return p


func _on_overlay_draw() -> void:
	var cam := _cam()
	if cam == null:
		return
	for cell in cells:
		for seg in cell["cracks"]:
			if cam.is_position_behind(seg["a"]) or cam.is_position_behind(seg["b"]):
				continue
			var pa := cam.unproject_position(seg["a"])
			var pb := cam.unproject_position(seg["b"])
			overlay.draw_line(pa, pb, seg["c"], seg["w"], true)


# ════════════════════ 砸开 + 全揭示 + 其余变质 ════════════════════
func _open_cell(cell: Dictionary) -> void:
	state = State.SHATTER
	cell["opened"] = true
	_reveal_cell(cell)            # 显示被选格名称
	_update_ui()
	_add_trauma(shatter_trauma)
	_punch_fov(8.0)
	_flash(0.55)
	Engine.time_scale = 0.06
	await get_tree().create_timer(freeze_frame_time, true, false, true).timeout
	Engine.time_scale = 1.0

	cell["cracks"].clear()       # 裂纹随玻璃消失
	overlay.queue_redraw()
	cell["glass"].visible = false
	_spawn_shards(cell)

	state = State.RESOLVE
	var food: RigidBody3D = cell["food"]
	food.visible = true
	# 不弹出：食物留在格子内、移到靠前位置方便看清（保持冻结、不掉落）
	food.position = cell["center"] + Vector3(0.0, 0.0, -0.12)

	# 其余格：全揭示名称（知道舍弃了什么）＋ 变质报废
	for other in cells:
		if other["index"] != cell["index"] and not other["opened"]:
			_reveal_cell(other)
			_spoil_cell(other)

	_update_ui()
	await get_tree().create_timer(1.2).timeout
	if state == State.RESOLVE:
		state = State.DONE
		finished.emit({"won": true, "food": cell["name"], "rarity": cell["rarity"]})
		_update_ui()


func _spoil_cell(cell: Dictionary) -> void:
	cell["spoiled"] = true
	var sprite: Sprite3D = cell["food_sprite"]
	if sprite != null:    # 图片变暗腐败 + 更透明（用 3D 模型时仅冒绿烟，模型外观留给美术）
		sprite.modulate = Color(0.32, 0.36, 0.22, 0.55)
	# 名称保持原稀有度颜色（让玩家清楚舍弃了什么稀有度的食物），不改成腐败绿
	var gmat: StandardMaterial3D = cell["glass_mat"]
	gmat.albedo_color = Color(0.45, 0.62, 0.32, 0.20)   # 变质格玻璃更透明
	_spawn_green_smoke(cell["center"])


func _spawn_green_smoke(pos: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.position = pos + Vector3(0, 0, 0.05)
	p.amount = 14
	p.lifetime = 1.8
	p.explosiveness = 0.05
	p.direction = Vector3(0, 1, 0)
	p.spread = 22.0
	p.initial_velocity_min = 0.35
	p.initial_velocity_max = 0.8
	p.gravity = Vector3(0, 0.5, 0)
	p.scale_amount_min = 0.10
	p.scale_amount_max = 0.26
	p.color = Color(0.35, 0.75, 0.22, 0.55)
	var pm := SphereMesh.new()
	pm.radius = 0.09
	pm.height = 0.18
	var smat := StandardMaterial3D.new()
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.albedo_color = Color(0.35, 0.75, 0.22, 0.5)
	smat.vertex_color_use_as_albedo = true
	pm.material = smat
	p.mesh = pm
	p.emitting = true
	cabinet_root.add_child(p)


func _spawn_shards(cell: Dictionary) -> void:
	var smat := StandardMaterial3D.new()
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.albedo_color = Color(0.86, 0.93, 1.0, 0.72)
	smat.roughness = 0.18
	var c: Vector3 = cell["center"]
	var hw: float = cell["gw"] * 0.5
	var hh: float = cell["gh"] * 0.5
	for i in 48:
		var rb := RigidBody3D.new()
		var sz := randf_range(0.05, 0.13)
		var size := Vector3(sz, sz * randf_range(0.7, 1.7), 0.03)
		if shard_model != null:
			rb.add_child(shard_model.instantiate())   # 碎片美术模型替换
		else:
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = size
			mi.mesh = bm
			mi.material_override = smat
			rb.add_child(mi)
		var rcol := CollisionShape3D.new()
		var rsh := BoxShape3D.new()
		rsh.size = size
		rcol.shape = rsh
		rb.add_child(rcol)
		rb.position = c + Vector3(randf_range(-hw, hw), randf_range(-hh, hh), 0.05)
		shards_root.add_child(rb)
		var outward := rb.position - c
		outward.z = 1.0
		rb.apply_central_impulse(outward.normalized() * randf_range(1.4, 3.2) + Vector3(0, 1.3, 1.7))
		rb.apply_torque_impulse(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.4)
	# 碎片落地后停留在场上，不自动清除（仅在 R 重置 / 换柜时清空）


func _clear_shards() -> void:
	for ch in shards_root.get_children():
		ch.queue_free()


# ════════════════════ 镜头爽感 ════════════════════
func _process(delta: float) -> void:
	trauma = max(trauma - trauma_decay * delta, 0.0)
	if camera != null:        # 震屏仅自带相机时；接大地图震屏交给主循环
		var amt := trauma * trauma
		if amt > 0.0001:
			camera.position = cam_base_pos + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * amt * 0.13
			camera.rotation = cam_base_rot + Vector3(0, 0, randf_range(-1, 1) * amt * 0.045)
		else:
			camera.position = cam_base_pos
			camera.rotation = cam_base_rot

	for cell in cells:
		if not cell["cracks"].is_empty():
			overlay.queue_redraw()
			break

	if state == State.SMASHING and chosen != -1:
		var cell = cells[chosen]
		if cell["clicks"] > 0:
			time_since_hit += delta
			if time_since_hit > refreeze_delay:
				refreeze_accum += delta
				if refreeze_accum >= 0.5:
					refreeze_accum = 0.0
					cell["clicks"] -= 1
					var segs: Array = cell["cracks"]
					for i in mini(6, segs.size()):
						segs.pop_back()
					overlay.queue_redraw()
					_update_ui()
					# 注：不释放锁定——首击选定后只能砸这一格，不可中途改格（只能砸开或 R 重置）


func _add_trauma(amount: float) -> void:
	trauma = min(trauma + amount, 1.0)


func _punch_fov(strength: float) -> void:
	if camera == null:
		return
	camera.fov = cam_base_fov - strength
	var tw := create_tween()
	tw.tween_property(camera, "fov", cam_base_fov, 0.12).set_trans(Tween.TRANS_QUAD)


func _flash(a: float) -> void:
	flash.color = Color(1, 1, 1, clamp(a, 0.0, 0.6))
	var tw := create_tween()
	tw.tween_property(flash, "color:a", 0.0, 0.18)


# ════════════════════ UI ════════════════════
func _update_ui() -> void:
	var dim := int(cabinet_size)
	lbl_title.text = "敲冰开柜  ·  %d×%d  ·  只能砸开 1 格（其余变质）   擦玻璃剩 %d" % [dim, dim, wipes_left]
	lbl_title.add_theme_color_override("font_color", Color.WHITE)  # 标题恒为白色，不随敲击格稀有度变色
	match state:
		State.IDLE:
			lbl_prompt.text = "右键擦 1 格看清内容 · 左键选 1 格连点砸开（其余变质）"
		State.SMASHING:
			# 不显示剩余敲击数——靠裂纹大小 + 屏幕抖动判断进度
			var cell = cells[chosen]
			if cell["revealed"]:
				lbl_prompt.text = "正在砸：%s（%s）" % [RARITY_NAME[cell["rarity"]], cell["name"]]
			else:
				lbl_prompt.text = "正在砸开这一格…"
		State.SHATTER:
			lbl_prompt.text = "碎！"
		State.RESOLVE:
			var cell = cells[chosen]
			lbl_prompt.text = "取出【%s】！其余格已变质失效" % cell["name"]
		State.DONE:
			lbl_prompt.text = "完成   （R 重置 · 1/2/3 换大小）"

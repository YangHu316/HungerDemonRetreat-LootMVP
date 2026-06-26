extends Node3D
## ⚡ 凌波渡电（跳一跳）· Godot 白盒复现
## 严格遵循《策划文件/小游戏策划案/饿魔退散外卖侠-小游戏-凌波渡电.md》：
##   通电水池拦路 → 首名【长按蓄力 → 松开抛物线起跳】踩落脚点过池（落点预测圈辅助）
##   → 落水触电【弹回起点 + 损失时间】（不致死可重试）→ 抵达对岸【按 E 拉电闸】
##   → 全池永久断电、水面恢复安全 → 后续两人轻松趟水通过（首名紧张 vs 后续轻松的反差）。
## 镜头按 §五 难点处理为 ~30° 斜俯视，使「落点间距 + 跳跃弧线 + 危险水面」皆可读。

# ---------------- 可配置参数（§四 · 程序读表不写死）----------------
@export var jump_min_dist := 0.8       # 最小蓄力跳距
@export var jump_max_dist := 2.6       # 满蓄力跳距（蓄力时长→跳距：线性起步、封顶）
@export var charge_time := 1.2         # 满蓄力所需秒数 🔴手感核心
@export var jump_air_time := 0.55      # 单跳腾空时间
@export var jump_arc_height := 1.25    # 抛物线峰高
@export var fall_reset_delay := 2.2    # 落水弹回损失时间（2~4s）
@export var switch_pull_time := 1.2    # 拉电闸交互时长（1~1.5s）
@export var follower_speed := 2.6      # 后续玩家趟水移速
@export var landing_bonus := 0.0       # 落点判定额外宽容（=落脚点半宽 + 此值）🔴落点预测精度
@export var sound_radius_splash := 15.0  # 落水/电弧声音半径（接《感知与寻人》，§七）

# ---------------- 接入大地图 ----------------
signal finished(result: Dictionary)         # 拉闸成功(过池)时发出 → 主循环收回控制
## standalone=true：开发沙盒模式，自带相机/环境/光照并自动开始（仅 F5 调试）。
## standalone=false（默认，接大地图用）：只搭建几何体，等宿主调用 begin()、用宿主相机取景。
@export var standalone := false

# ---------------- 美术替换槽（留空=灰盒方块占位；大部分应换成 3D 模型）----------------
@export_group("美术替换槽")
@export var stone_model: PackedScene         # 落脚点（锈管/水泥块/漂浮外卖箱）
@export var bank_model: PackedScene          # 两岸地台
@export var player_model: PackedScene        # 玩家（外卖员）
@export var follower_model: PackedScene      # 后续队友
@export var switch_base_model: PackedScene   # 电闸底座
@export var switch_lever_model: PackedScene  # 电闸闸刀（杆，会绕底座转动）
@export var water_material: Material          # 通电水面材质（填了就用它，并停用脚本电光脉动）
@export_group("")

# ---------------- 布局 ----------------
const CROSS_Z := 0.0
var base_y := 0.55       # 落脚点顶面 / 玩家落脚高度
var stand_y := 1.0       # 站立时玩家中心
var platforms: Array = []   # [{x, hw, type, node}] 起点 + 4 落脚点 + 终点

# ---------------- 状态 ----------------
var player_index := 0
var charge := 0.0
var charging := false
var jumping := false
var resetting := false
var at_end := false
var pulling := false
var powered_off := false
var trauma := 0.0
var _water_t := 0.0

# ---------------- 节点 ----------------
var camera: Camera3D
var player: Node3D
var player_mesh: MeshInstance3D
var water: MeshInstance3D
var water_mat: StandardMaterial3D
var switch_root: Node3D
var switch_lever: Node3D
var lever_mat: StandardMaterial3D     # 闸刀灰盒材质（用了模型则为 null，脚本不再变红/绿）
var followers_root: Node3D
var ui_charge: ProgressBar
var ui_prompt: Label
var ui_help: Label
var ui_title: Label
var ui_flash: ColorRect
var _font: SystemFont


func _ready() -> void:
	_build_world()
	_build_ui()
	if standalone:
		_setup_standalone_view()
		begin()


## 公开入口：宿主在玩家交互时调用，开始一局渡电。
func begin() -> void:
	start_round()


## 沙盒/独立运行：自带相机 + 环境 + 光照（接大地图时不调用，用宿主的）。
func _setup_standalone_view() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.06, 0.09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.48, 0.58)
	env.ambient_light_energy = 0.65
	env.fog_enabled = true
	env.fog_light_color = Color(0.06, 0.08, 0.12)
	env.fog_density = 0.012
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -38, 0)
	sun.light_energy = 1.05
	add_child(sun)

	# 相机：§五 难点——~30° 侧斜俯视，看清落点间距 + 跳跃弧线 + 危险水面
	camera = Camera3D.new()
	camera.fov = 55
	camera.current = true
	add_child(camera)
	camera.look_at_from_position(Vector3(4.9, 5.0, 7.4), Vector3(5.0, 0.7, -0.3), Vector3.UP)


# ======================= 世界搭建（几何体，相对自身原点，可整体摆进大地图）=======================
func _build_world() -> void:
	# 落脚点（起点 + 4 块 + 终点；间距不等，§四）
	platforms = [
		{"x": 0.7, "hw": 0.8, "type": "start"},
		{"x": 2.5, "hw": 0.5, "type": "stone"},
		{"x": 4.1, "hw": 0.5, "type": "stone"},
		{"x": 6.0, "hw": 0.5, "type": "stone"},
		{"x": 7.4, "hw": 0.5, "type": "stone"},
		{"x": 9.2, "hw": 0.9, "type": "end"},
	]
	for i in platforms.size():
		var p: Dictionary = platforms[i]
		var node := _make_platform(p)
		p["node"] = node
		add_child(node)

	# 通电水池（蓝白电光、危险可读；断电后转安全暗色）
	water = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(7.6, 3.8)
	water.mesh = pm
	water.position = Vector3(5.0, 0.18, CROSS_Z)
	if water_material != null:
		water.material_override = water_material   # 美术材质：自带电光，脚本不再驱动脉动
		water_mat = null
	else:
		water_mat = StandardMaterial3D.new()
		water_mat.albedo_color = Color(0.10, 0.45, 0.78, 0.80)
		water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		water_mat.emission_enabled = true
		water_mat.emission = Color(0.30, 0.72, 1.0)
		water_mat.emission_energy_multiplier = 1.0
		water.material_override = water_mat
	add_child(water)

	# 终点电闸（旧式工业闸刀，醒目可交互）
	_make_switch()

	# 玩家（外卖员·橙）
	player = Node3D.new()
	if player_model != null:
		player.add_child(player_model.instantiate())
	else:
		player_mesh = MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius = 0.28
		cap.height = 0.9
		player_mesh.mesh = cap
		var pmat := StandardMaterial3D.new()
		pmat.albedo_color = Color(0.96, 0.52, 0.10)
		player_mesh.material_override = pmat
		player.add_child(player_mesh)
	player.position = Vector3(float(platforms[0]["x"]), stand_y, CROSS_Z)
	add_child(player)

	followers_root = Node3D.new()
	add_child(followers_root)


func _make_platform(p: Dictionary) -> Node3D:
	var is_stone: bool = p["type"] == "stone"
	var model: PackedScene = stone_model if is_stone else bank_model
	var node: Node3D
	if model != null:
		node = model.instantiate() as Node3D     # 美术模型替换
	else:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var depth: float = 1.1 if is_stone else 3.0
		bm.size = Vector3(float(p["hw"]) * 2.0, 0.5, depth)
		mi.mesh = bm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.58, 0.54, 0.48) if is_stone else Color(0.28, 0.31, 0.29)
		mi.material_override = m
		node = mi
	node.position = Vector3(float(p["x"]), base_y - 0.25, CROSS_Z)
	return node


func _make_switch() -> void:
	switch_root = Node3D.new()
	switch_root.position = Vector3(float(platforms[-1]["x"]), base_y, CROSS_Z - 0.55)
	add_child(switch_root)
	# 底座
	if switch_base_model != null:
		var bnode := switch_base_model.instantiate() as Node3D
		bnode.position = Vector3(0, 0.25, 0)
		switch_root.add_child(bnode)
	else:
		var base := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.42, 0.5, 0.32)
		base.mesh = bm
		base.position = Vector3(0, 0.25, 0)
		var bmat := StandardMaterial3D.new()
		bmat.albedo_color = Color(0.20, 0.20, 0.23)
		base.material_override = bmat
		switch_root.add_child(base)
	# 闸刀杆（switch_lever 是转轴 pivot，内放杆模型/方块）
	switch_lever = Node3D.new()
	switch_lever.position = Vector3(0, 0.5, 0)
	switch_root.add_child(switch_lever)
	if switch_lever_model != null:
		var lnode := switch_lever_model.instantiate() as Node3D
		lnode.position = Vector3(0, 0.35, 0)
		switch_lever.add_child(lnode)
		lever_mat = null                  # 美术模型自带外观，脚本不再变红/绿
	else:
		var lever := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.13, 0.7, 0.13)
		lever.mesh = lm
		lever.position = Vector3(0, 0.35, 0)
		lever_mat = StandardMaterial3D.new()
		lever_mat.albedo_color = Color(0.88, 0.20, 0.15)
		lever_mat.emission_enabled = true
		lever_mat.emission = Color(0.85, 0.12, 0.10)
		lever_mat.emission_energy_multiplier = 0.5
		lever.material_override = lever_mat
		switch_lever.add_child(lever)


# ======================= UI =======================
func _build_ui() -> void:
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Microsoft YaHei", "Microsoft YaHei UI", "SimHei", "Noto Sans CJK SC", "sans-serif"])
	var layer := CanvasLayer.new()
	add_child(layer)

	ui_flash = ColorRect.new()
	ui_flash.color = Color(0.6, 0.85, 1.0, 0.0)
	ui_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui_flash)

	ui_title = _label(layer, "⚡ 凌波渡电（跳一跳） · 白盒", 24, Color(0.72, 0.9, 1.0))
	ui_title.position = Vector2(24, 16)

	ui_help = _label(layer, "长按 [空格] 蓄力，松开起跳 → 落到下一落脚点 → 到对岸按 [E] 拉电闸断电 · [R] 重来", 15, Color(0.8, 0.85, 0.92))
	ui_help.position = Vector2(24, 50)

	ui_prompt = _label(layer, "", 22, Color(1, 1, 1))
	ui_prompt.position = Vector2(256, 96)
	ui_prompt.size = Vector2(640, 40)
	ui_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	ui_charge = ProgressBar.new()
	ui_charge.min_value = 0.0
	ui_charge.max_value = 1.0
	ui_charge.value = 0.0
	ui_charge.show_percentage = false
	ui_charge.position = Vector2(456, 566)
	ui_charge.size = Vector2(240, 22)
	layer.add_child(ui_charge)
	var lab := _label(ui_charge, "蓄力", 13, Color(0.95, 0.95, 0.8))
	lab.position = Vector2(102, 1)


func _label(parent: Node, text: String, fsize: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 4)
	parent.add_child(l)
	return l


# ======================= 回合控制 =======================
func start_round() -> void:
	player_index = 0
	player.position = Vector3(float(platforms[0]["x"]), stand_y, CROSS_Z)
	player.scale = Vector3.ONE
	charge = 0.0
	charging = false
	jumping = false
	resetting = false
	at_end = false
	pulling = false
	powered_off = false
	trauma = 0.0
	# 水池恢复通电
	if water_mat != null:
		water_mat.albedo_color = Color(0.10, 0.45, 0.78, 0.80)
		water_mat.emission = Color(0.30, 0.72, 1.0)
		water_mat.emission_energy_multiplier = 1.0
	# 闸刀复位 + 变红（带电）
	switch_lever.rotation = Vector3.ZERO
	if lever_mat != null:
		lever_mat.albedo_color = Color(0.88, 0.20, 0.15)
		lever_mat.emission = Color(0.85, 0.12, 0.10)
	for f in followers_root.get_children():
		f.queue_free()
	ui_charge.value = 0.0
	ui_flash.color = Color(0.6, 0.85, 1.0, 0.0)
	_update_prompt()


# ======================= 主循环 =======================
func _process(delta: float) -> void:
	_water_t += delta
	# 通电水面：蓝白电光脉动（断电后熄灭；用了美术材质则交给材质、不在此驱动）
	if not powered_off and water_mat != null:
		water_mat.emission_energy_multiplier = 0.85 + 0.65 * (0.5 + 0.5 * sin(_water_t * 9.0))

	# 蓄力跳输入（长按蓄力 → 松开起跳）
	if _can_charge():
		if Input.is_key_pressed(KEY_SPACE):
			charging = true
			charge = min(charge + delta / charge_time, 1.0)
			ui_charge.value = charge
			# 压低蓄力姿态（§六 可读性）
			player.scale = Vector3(1.0 + 0.18 * charge, 1.0 - 0.30 * charge, 1.0 + 0.18 * charge)
			_update_prompt()
		elif charging:
			charging = false
			var c := charge
			charge = 0.0
			ui_charge.value = 0.0
			player.scale = Vector3.ONE
			_do_jump(c)

	# 相机抖动（落水冲击）——仅自带相机时；接大地图用宿主相机，震屏交给主循环
	if camera != null:
		if trauma > 0.0:
			trauma = max(trauma - delta * 1.6, 0.0)
			var amt := trauma * trauma
			camera.h_offset = randf_range(-1.0, 1.0) * 0.12 * amt
			camera.v_offset = randf_range(-1.0, 1.0) * 0.12 * amt
		else:
			camera.h_offset = 0.0
			camera.v_offset = 0.0

	# 后续玩家趟水通过（断电后）
	if powered_off:
		var end_x := float(platforms[-1]["x"])
		for f in followers_root.get_children():
			var m3 := f as Node3D
			if m3 != null and m3.position.x < end_x:
				m3.position.x += follower_speed * delta


func _can_charge() -> bool:
	return not jumping and not resetting and not at_end and not pulling and not powered_off


## 是否处于开发者模式（F1 开关 · 全局 Dev autoload）——决定测试快捷键是否生效。
func _dev_on() -> bool:
	var n := get_node_or_null("/root/Dev")
	return n != null and bool(n.get("enabled"))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R and _dev_on():   # 测试快捷键：需开发者模式(F1)
			begin()
		elif event.keycode == KEY_E and at_end and not pulling and not powered_off:
			_pull_switch()


# ======================= 蓄力跳 =======================
func _do_jump(c: float) -> void:
	jumping = true
	_update_prompt()
	var dist := jump_min_dist + c * (jump_max_dist - jump_min_dist)
	var sx := player.position.x   # 从玩家实际所在位置起跳（不吸附格中心）
	var tx := sx + dist
	var tw := create_tween()
	tw.tween_method(func(t: float): _set_jump_pos(t, sx, tx), 0.0, 1.0, jump_air_time)
	tw.tween_callback(_resolve_landing.bind(tx))


func _set_jump_pos(t: float, sx: float, tx: float) -> void:
	var x := lerpf(sx, tx, t)
	var y := stand_y + jump_arc_height * sin(PI * t)
	player.position = Vector3(x, y, CROSS_Z)


func _resolve_landing(tx: float) -> void:
	jumping = false
	var idx := _platform_at(tx)
	if idx >= 0:
		player_index = idx
		player.position = Vector3(tx, stand_y, CROSS_Z)   # 停在实际落点，不吸附格中心
		if platforms[idx]["type"] == "end":
			at_end = true
		_update_prompt()
	else:
		_fall_in_water(tx)


func _platform_at(x: float) -> int:
	for i in platforms.size():
		var p: Dictionary = platforms[i]
		if abs(x - float(p["x"])) <= float(p["hw"]) + landing_bonus:
			return i
	return -1


# ======================= 落水触电（弹回起点 + 损失时间）=======================
func _fall_in_water(tx: float) -> void:
	resetting = true
	var px := clampf(tx, float(platforms[0]["x"]), float(platforms[-1]["x"]))
	player.position = Vector3(px, base_y - 0.12, CROSS_Z)
	_electric_flash()
	trauma = 0.85
	_emit_noise(Vector3(px, base_y, CROSS_Z))
	_update_prompt("⚡ 触电！弹回起点（损失时间）")
	# 触电弹飞小动画
	var tw := create_tween()
	tw.tween_property(player, "position:y", base_y + 0.9, 0.16)
	tw.tween_property(player, "position:y", base_y - 0.12, 0.20)
	await get_tree().create_timer(fall_reset_delay).timeout
	if not powered_off:
		player_index = 0
		player.position = Vector3(float(platforms[0]["x"]), stand_y, CROSS_Z)
		_update_prompt()
	resetting = false


func _electric_flash() -> void:
	ui_flash.color = Color(0.62, 0.86, 1.0, 0.6)
	var tw := create_tween()
	tw.tween_property(ui_flash, "color:a", 0.0, 0.35)


func _emit_noise(_pos: Vector3) -> void:
	# 接口位（§七）：落水/电弧 = 15m 高噪（sound_radius_splash）。白盒不发实声，接感知系统时在此触发。
	pass


# ======================= 拉电闸 → 断电 =======================
func _pull_switch() -> void:
	pulling = true
	_update_prompt("拉电闸中…")
	var tw := create_tween()
	tw.tween_property(switch_lever, "rotation:z", deg_to_rad(-78), switch_pull_time)
	tw.tween_callback(_power_off)


func _power_off() -> void:
	pulling = false
	powered_off = true
	# 断电：水面恢复安全暗色、电光熄灭
	if water_mat != null:
		water_mat.emission_energy_multiplier = 0.0
		water_mat.emission = Color(0, 0, 0)
		water_mat.albedo_color = Color(0.10, 0.13, 0.16, 0.72)
	# 闸刀转绿（安全）
	if lever_mat != null:
		lever_mat.albedo_color = Color(0.20, 0.80, 0.32)
		lever_mat.emission = Color(0.10, 0.70, 0.22)
	_spawn_followers()
	finished.emit({"crossed": true})   # 过池成功 → 通知主循环收回控制
	_update_prompt("✅ 断电成功！通路已开 —— 后续两人轻松趟水通过")


func _spawn_followers() -> void:
	for i in 2:
		var f: Node3D
		if follower_model != null:
			f = follower_model.instantiate() as Node3D
		else:
			var mi := MeshInstance3D.new()
			var cm := CapsuleMesh.new()
			cm.radius = 0.26
			cm.height = 0.85
			mi.mesh = cm
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(0.30, 0.75, 0.88) if i == 0 else Color(0.55, 0.82, 0.42)
			mi.material_override = m
			f = mi
		f.position = Vector3(float(platforms[0]["x"]) - 0.5 - i * 0.7, stand_y, CROSS_Z + (0.55 if i == 0 else -0.55))
		followers_root.add_child(f)


# ======================= 提示 =======================
func _update_prompt(custom := "") -> void:
	if custom != "":
		ui_prompt.text = custom
		return
	if powered_off:
		ui_prompt.text = "✅ 断电成功！通路已开"
	elif at_end:
		ui_prompt.text = "已抵达对岸 —— 按 [E] 拉电闸断电开路"
	elif jumping:
		ui_prompt.text = "腾空中…"
	elif resetting:
		ui_prompt.text = "⚡ 触电！弹回起点"
	elif charging:
		ui_prompt.text = "蓄力中… 松开起跳（按住越久跳越远）"
	else:
		ui_prompt.text = "进度 %d / %d —— 长按 [空格] 蓄力跳" % [player_index, platforms.size() - 1]

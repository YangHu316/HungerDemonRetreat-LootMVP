extends Node3D

# 容器类型（保留，兼容旧逻辑）
enum CType { DRAWER, CABINET, SAFE }

# Phase 2B Q1 fix:apply_entries(host RPC 同步)后 emit,让 search_ui 监听并刷新 UI
# 否则 B 端 search_ui 打开时是 snapshot,A 拿走东西后 B 看不见变化
signal entries_synced

@export var type: CType = CType.DRAWER
@export var data: Resource  # ContainerData（可选，为空时用 type enum）

var contents: GridInventory
var opened: bool = false
# 第一次被打开过 → 永久 true,视觉标"已搜刮",但仍可继续打开
var has_been_opened: bool = false
# 完整 inspect 流程跑完(由 search_ui 设),再次打开会跳过 inspect 阶段
var is_searched: bool = false
# 内容被拿空 → true(可重复打开,看里面是不是真空了)
var is_emptied: bool = false
var _rng: RandomNumberGenerator

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var collision_shape: CollisionShape3D = $Body/CollisionShape3D
@onready var trigger_area: Area3D = $Trigger
@onready var looted_label: Label3D = $LootedLabel

func _ready() -> void:
	_rng = RandomNumberGenerator.new()
	_rng.randomize()
	add_to_group("containers")
	add_to_group("interactables")
	_apply_visual()
	# Phase 2B:多人 client 跳过本地生成,等 host 的 _rpc_apply_round_start 填充
	var mm = get_node_or_null("/root/MultiplayerManager")
	if mm != null and mm.has_method("is_client") and mm.is_client():
		var gs: Vector2i = get_grid_size()
		contents = GridInventory.new()
		contents.setup(gs.x, gs.y)
	else:
		_generate_contents()
	looted_label.visible = false
	trigger_area.body_entered.connect(_on_body_entered)
	trigger_area.body_exited.connect(_on_body_exited)

# ── v8 §4.2 interactables 协议 ──
func get_interact_position() -> Vector3:
	return global_position

func get_prompt() -> String:
	# 第一次显示"按 F 搜刮",再开显示"按 F 再开"
	if has_been_opened:
		return "按 F 再开 [%s]" % get_type_name()
	return "按 F 搜刮 [%s]" % get_type_name()

func is_available() -> bool:
	# 容器永远可交互,只要不是正在打开状态
	return not opened

func interact(_player: Node) -> void:
	# 实际打开搜刮 UI 由 main.gd 处理（保留旧的双击/UI 流转，
	# 这里只是协议入口，不重复打开 UI）
	pass

func _apply_visual() -> void:
	var size: Vector3
	var col: Color
	var t: String = get_type_name_key()
	match t:
		"drawer":
			size = Vector3(0.8, 0.4, 0.5)
			col = Color("#8b6f3a")
		"cabinet":
			size = Vector3(1.2, 1.6, 0.6)
			col = Color("#6a4f2a")
		"safe":
			size = Vector3(0.8, 0.8, 0.6)
			col = Color("#8b3a3a")
		_:
			size = Vector3(0.8, 0.4, 0.5)
			col = Color("#8b6f3a")
	var bm := BoxMesh.new()
	bm.size = size
	mesh_instance.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mesh_instance.material_override = mat
	mesh_instance.position.y = size.y * 0.5
	var bs := BoxShape3D.new()
	bs.size = size
	collision_shape.shape = bs
	collision_shape.position.y = size.y * 0.5
	looted_label.position.y = size.y + 0.5
	# §6.2 容器装饰子节点（仅 MeshInstance3D，无碰撞）
	_apply_decor(t, size, col)

func get_type_name_key() -> String:
	if data != null:
		return String(data.container_type)
	match type:
		CType.DRAWER: return "drawer"
		CType.CABINET: return "cabinet"
		CType.SAFE: return "safe"
	return "drawer"

func get_grid_size() -> Vector2i:
	if data != null:
		return Vector2i(int(data.grid_cols), int(data.grid_rows))
	match type:
		CType.DRAWER: return Vector2i(2, 2)
		CType.CABINET: return Vector2i(3, 3)
		CType.SAFE: return Vector2i(4, 3)
	return Vector2i(2, 2)

func get_type_name() -> String:
	var k: String = get_type_name_key()
	match k:
		"drawer": return "抽屉"
		"cabinet": return "衣柜"
		"safe": return "保险箱"
	return "容器"

func get_search_time() -> float:
	if data != null:
		return float(data.search_time)
	match type:
		CType.DRAWER: return 1.5
		CType.CABINET: return 2.5
		CType.SAFE: return 4.0
	return 1.5

func _loot_table_path() -> String:
	match type:
		CType.DRAWER: return "res://resources/loot_tables/drawer_loot.tres"
		CType.CABINET: return "res://resources/loot_tables/cabinet_loot.tres"
		CType.SAFE: return "res://resources/loot_tables/safe_loot.tres"
	return ""

func _generate_contents() -> void:
	var gs: Vector2i = get_grid_size()
	contents = GridInventory.new()
	contents.setup(gs.x, gs.y)
	var table: Resource = null
	if data != null and data.loot_table != null:
		table = data.loot_table
	else:
		table = load(_loot_table_path())
	if table == null:
		return
	# Phase 2B:从 GameSession 取 round-scoped uid 计数器
	var session = get_node_or_null("/root/GameSession")
	var rolled: Array = (table as ContainerLootTable).roll(_rng)
	for item in rolled:
		var fit = GridPlacer.find_first_fit(contents, item)
		if fit == null:
			continue
		var uid: int = -1
		if session != null and session.has_method("next_entry_uid"):
			uid = session.next_entry_uid()
		var entry: Dictionary = {
			"uid": uid,            # Phase 2B:host 分配 uid,wire 传输用
			"item": item,
			"x": fit[0],
			"y": fit[1],
			"rotated": fit[2],
			"freshness_elapsed": 0.0,  # 食物变质 — wire 也传
			"examined": false,
			"inspected": false,
			"inspecting": false,
		}
		contents.place(entry, fit[0], fit[1])

# Phase 2B:把 contents.entries 序列化成 wire 格式(host → client)
func serialize_entries() -> Array:
	var out: Array = []
	if contents == null:
		return out
	for e in contents.entries:
		var item: ItemData = e.get("item", null)
		out.append({
			"uid": int(e.get("uid", -1)),
			"item_path": item.resource_path if item != null else "",
			"x": int(e.get("x", 0)),
			"y": int(e.get("y", 0)),
			"rotated": bool(e.get("rotated", false)),
			"freshness_elapsed": float(e.get("freshness_elapsed", 0.0)),
		})
	return out

# Phase 2B:从 wire 格式 apply(client 收 RPC 时调用)
# 完全覆盖现有 contents,reload item 资源
func apply_entries(wire_entries: Array) -> void:
	var gs: Vector2i = get_grid_size()
	if contents == null:
		contents = GridInventory.new()
	contents.cells.clear()
	contents.entries.clear()
	contents.setup(gs.x, gs.y)
	for w in wire_entries:
		var path: String = String(w.get("item_path", ""))
		if path == "":
			continue
		var item: ItemData = load(path) as ItemData
		if item == null:
			continue
		var entry: Dictionary = {
			"uid": int(w.get("uid", -1)),
			"item": item,
			"x": int(w.get("x", 0)),
			"y": int(w.get("y", 0)),
			"rotated": bool(w.get("rotated", false)),
			"freshness_elapsed": float(w.get("freshness_elapsed", 0.0)),
			"examined": false,
			"inspected": false,
			"inspecting": false,
		}
		contents.place(entry, int(w.get("x", 0)), int(w.get("y", 0)))
	# Phase 2B Q1 fix:emit 让 search_ui 知道实时更新(其他 peer 拿物品/放回都会触发)
	entries_synced.emit()

func reset_and_regenerate() -> void:
	# 清空内容、重置状态、重新填充
	if contents != null:
		contents.cells.clear()
		contents.entries.clear()
	is_searched = false
	is_emptied = false
	has_been_opened = false
	opened = false
	if looted_label != null:
		looted_label.visible = false
	# 恢复材质颜色
	_apply_visual()
	_generate_contents()

func remove_slot(entry: Dictionary) -> void:
	if contents != null:
		contents.remove_entry(entry)

func add_slot(entry: Dictionary, x: int, y: int) -> bool:
	if contents == null:
		return false
	return contents.place(entry, x, y)

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		body.set_nearby(self)
		if body.has_method("register_interactable"):
			body.register_interactable(self)
		get_node("/root/EventBus").container_approached.emit(self)

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		body.clear_nearby(self)
		if body.has_method("unregister_interactable"):
			body.unregister_interactable(self)
		get_node("/root/EventBus").container_left.emit(self)

func open() -> void:
	if opened:
		return
	opened = true
	get_node("/root/EventBus").container_opened.emit(self)
	# Phase 2B Tier B4:has_been_opened 全局同步(已搜 badge 给所有 peer 显示)
	# - 单人:本地标记
	# - 多人:走 mm.notify_container_opened → host 广播 → 各 peer _apply_opened_local
	# 注意:has_been_opened 用于"已搜刮"视觉,首次开过永久标。
	# is_searched(完整 inspect 流程跑完) 在 search_ui per-peer 计算,不在这里设。
	if not has_been_opened:
		var mm = get_node_or_null("/root/MultiplayerManager")
		if mm == null or (mm.has_method("is_single") and mm.is_single()):
			_apply_opened_local()
		else:
			# 多人:host/client 都走 mm.notify_container_opened
			# host 直接广播 _rpc_apply_container_opened
			# client 发 _rpc_request_container_opened 给 host,host 再广播
			if mm.has_method("notify_container_opened"):
				mm.notify_container_opened(String(self.get_path()))

# Phase 2B Tier B4:本地应用"已搜"badge(给 _rpc_apply_container_opened 调)
# 单人也走这条(open() 直接调)。幂等:重复调安全。
func _apply_opened_local() -> void:
	if has_been_opened:
		return
	has_been_opened = true
	_set_searched_visual()

func close() -> void:
	if not opened:
		return
	opened = false
	_check_emptied()
	get_node("/root/EventBus").container_closed.emit(self)

func _check_emptied() -> void:
	# 容器空了只是 is_emptied=true,不再锁死 interact
	if contents == null or contents.entries.is_empty():
		is_emptied = true

func _set_searched_visual() -> void:
	if mesh_instance.material_override is StandardMaterial3D:
		var m: StandardMaterial3D = mesh_instance.material_override
		m.albedo_color = m.albedo_color * Color(0.4, 0.4, 0.4, 1.0)
	looted_label.visible = true

# §6.2 容器装饰：drawer 抽屉缝+把手；cabinet 门缝+把手；safe 密码盘+门缝
# 防 z-fight:所有装饰 z 推到 size.z*0.5 + 0.020,后面留 5-10mm 空(消除共面)
# 注:render_priority 在 Godot 4 不透明材质上无效,只能靠几何 clearance
func _apply_decor(t: String, size: Vector3, base_col: Color) -> void:
	# 清除旧装饰节点（可能由前一次 _apply_visual 创建）
	var prev = get_node_or_null("Decor")
	if prev != null:
		prev.queue_free()
	var decor := Node3D.new()
	decor.name = "Decor"
	add_child(decor)
	var dark := base_col * Color(0.55, 0.55, 0.55, 1.0)
	dark.a = 1.0
	var metal := Color("#c0c0c0")
	# 防 z-fight:装饰前推距离
	var seam_z: float = size.z * 0.5 + 0.020   # seam 厚 0.02 → 后面 z = front + 0.010
	var handle_z: float = size.z * 0.5 + 0.060  # handle 球后端 z = front + 0.010
	var dial_z: float = size.z * 0.5 + 0.030    # dial 后端 z = front + 0.010
	var rivet_z: float = size.z * 0.5 + 0.030   # rivet 球后端 z = front + 0.005
	match t:
		"drawer":
			# 一条横向抽屉缝（在正面 +z 略外）+ 一个圆形把手
			var seam := _make_box_mesh(Vector3(size.x * 0.85, 0.02, 0.02), dark)
			seam.position = Vector3(0, size.y * 0.5, seam_z)
			decor.add_child(seam)
			var handle := _make_sphere_mesh(0.05, metal)
			handle.position = Vector3(0, size.y * 0.5, handle_z)
			decor.add_child(handle)
		"cabinet":
			# 中央竖直门缝 + 左右两个把手
			var seam := _make_box_mesh(Vector3(0.02, size.y * 0.85, 0.02), dark)
			seam.position = Vector3(0, size.y * 0.5, seam_z)
			decor.add_child(seam)
			var handle_l := _make_sphere_mesh(0.05, metal)
			handle_l.position = Vector3(-0.15, size.y * 0.5, handle_z)
			decor.add_child(handle_l)
			var handle_r := _make_sphere_mesh(0.05, metal)
			handle_r.position = Vector3(0.15, size.y * 0.5, handle_z)
			decor.add_child(handle_r)
		"safe":
			# 圆形密码盘 + 周围 4 个铆钉
			var dial := _make_cylinder_mesh(0.12, 0.04, Color("#3a3a3a"))
			dial.transform = Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(0, size.y * 0.5, dial_z))
			decor.add_child(dial)
			var center_y: float = size.y * 0.5
			for offset in [Vector2(-0.3, 0.3), Vector2(0.3, 0.3), Vector2(-0.3, -0.3), Vector2(0.3, -0.3)]:
				var rivet := _make_sphere_mesh(0.025, metal)
				rivet.position = Vector3(offset.x, center_y + offset.y, rivet_z)
				decor.add_child(rivet)

func _make_box_mesh(s: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = s
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mi.material_override = mat
	return mi

func _make_sphere_mesh(radius: float, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.metallic = 0.6
	mi.material_override = mat
	return mi

func _make_cylinder_mesh(radius: float, height: float, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	mi.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.metallic = 0.4
	mi.material_override = mat
	return mi

extends Node3D

# ============================================================
# v11 Main scene controller
# - 保留 v10 全部玩法（窗户、墙体、容器、扩展逻辑）
# - v11 §4-6：装饰布置完全程序化重建（卧室重摆 / 主厅治乱 / 生活细节）
# - Phase 2A §联机:Player 改动态 spawn(MultiplayerManager.mode 决定)
# ============================================================

const PlayerScene := preload("res://scenes/entities/player.tscn")

@onready var camera_rig: Node3D = $CameraRig
@onready var search_ui: CanvasLayer = $SearchUI
@onready var spawn_marker: Marker3D = $World/PlayerSpawn
@onready var players_root: Node3D = $PlayersRoot

var local_player: CharacterBody3D = null

const WALL_HEIGHT: float = 3.0
const WALL_THICKNESS: float = 0.3
const SKIRT_HEIGHT: float = 0.12
const DOOR_WIDTH: float = 1.2

var _wall_main_mat: StandardMaterial3D
var _wall_bed_mat: StandardMaterial3D
var _wall_stor_mat: StandardMaterial3D
var _skirt_mat: StandardMaterial3D
var _glass_shader: Shader = null
var _frame_mat: StandardMaterial3D = null

func _ready() -> void:
	_init_wall_materials()
	_build_walls()
	_build_skirting()
	_build_windows()
	_build_extra_decor()
	_ensure_decor_collisions()

	_spawn_players()

	var gs = get_node("/root/GameSession")
	if not gs.round_started.is_connected(_on_round_started):
		gs.round_started.connect(_on_round_started)
	gs.start_round()

	call_deferred("_verify_reachability")

func _spawn_players() -> void:
	# Phase 2A:依 MultiplayerManager 状态决定 spawn 数量 + authority
	#   SINGLE → 1 个 player,不设 authority(单机 multiplayer_peer == null)
	#   HOST / CLIENT → 为 mm.players.keys() 每个 peer 各 spawn 一个
	#     authority 设为 peer_id;只有 authority 节点跑 physics + 输入
	var mm = get_node_or_null("/root/MultiplayerManager")
	if mm == null or mm.is_single():
		var p := _make_player(0, 0)
		players_root.add_child(p)
		_position_player(p, 0)
		_bind_local(p)
		return
	# 多人:peer_ids 排序保证各 peer 顺序一致,position 偏移可复现
	var peer_ids: Array = mm.players.keys()
	peer_ids.sort()
	var my_id: int = multiplayer.get_unique_id()
	for i in range(peer_ids.size()):
		var pid: int = int(peer_ids[i])
		var p := _make_player(pid, i)
		players_root.add_child(p)
		# set_multiplayer_authority recursive=true(默认),propagate 到 MultiplayerSynchronizer
		p.set_multiplayer_authority(pid)
		_position_player(p, i)
		if pid == my_id:
			_bind_local(p)

func _make_player(peer_id: int, _slot: int) -> CharacterBody3D:
	var p: CharacterBody3D = PlayerScene.instantiate()
	p.name = "Player_%d" % peer_id if peer_id > 0 else "Player"
	return p

func _position_player(p: CharacterBody3D, slot: int) -> void:
	if spawn_marker == null:
		return
	# 多人时按 slot 偏移,避免重叠
	var offset: Vector3 = Vector3((slot - 0.5) * 1.2, 0, 0) if slot > 0 or _is_multiplayer() else Vector3.ZERO
	p.global_position = spawn_marker.global_position + offset

func _bind_local(p: CharacterBody3D) -> void:
	local_player = p
	# §联机:本地 Player 注册到 autoload 代理(只有 local 该绑 HUD/SearchUI)
	var pinv = get_node_or_null("/root/PlayerInventory")
	if pinv != null:
		pinv.register_local_player(p)
	var stam = get_node_or_null("/root/Stamina")
	if stam != null:
		stam.register_local_player(p)
	if camera_rig != null:
		camera_rig.target_path = camera_rig.get_path_to(p)
		camera_rig.target = p
	if search_ui != null and search_ui.has_method("bind_player"):
		search_ui.bind_player(p)

func _is_multiplayer() -> bool:
	var mm = get_node_or_null("/root/MultiplayerManager")
	return mm != null and not mm.is_single()

func _on_round_started() -> void:
	# 本地玩家位置 reset(Phase 2A 简化:每个 peer 本地 reset,不走 RPC)
	if local_player != null and spawn_marker != null:
		local_player.global_position = spawn_marker.global_position
		if local_player.has_method("reset_motion"):
			local_player.reset_motion()
	for c in get_tree().get_nodes_in_group("containers"):
		if c.has_method("reset_and_regenerate"):
			c.reset_and_regenerate()
	for d in get_tree().get_nodes_in_group("doors"):
		if d.has_method("reset_state"):
			d.reset_state()
		else:
			if d is Node3D:
				(d as Node3D).rotation = Vector3.ZERO
			if "is_open" in d:
				d.is_open = false
			if "_busy" in d:
				d._busy = false

func _unhandled_input(event: InputEvent) -> void:
	var gs = get_node("/root/GameSession")
	if not gs.round_active:
		return
	if event.is_action_pressed("interact"):
		if gs.state == "PLAYING":
			if local_player == null:
				return
			var c = local_player.nearby_container
			if c != null and is_instance_valid(c):
				search_ui.open_for(c)
				get_viewport().set_input_as_handled()

func _init_wall_materials() -> void:
	_wall_main_mat = StandardMaterial3D.new()
	_wall_main_mat.albedo_color = Color(0.30, 0.31, 0.34)
	_wall_main_mat.roughness = 0.85

	_wall_bed_mat = StandardMaterial3D.new()
	_wall_bed_mat.albedo_color = Color(0.55, 0.40, 0.28)
	_wall_bed_mat.roughness = 0.85

	_wall_stor_mat = StandardMaterial3D.new()
	_wall_stor_mat.albedo_color = Color(0.50, 0.50, 0.52)
	_wall_stor_mat.roughness = 0.9

	_skirt_mat = StandardMaterial3D.new()
	_skirt_mat.albedo_color = Color(0.06, 0.06, 0.08)
	_skirt_mat.roughness = 0.7

	_frame_mat = StandardMaterial3D.new()
	_frame_mat.albedo_color = Color(0.753, 0.753, 0.753)
	_frame_mat.roughness = 0.4

	_glass_shader = load("res://shaders/window_glass.gdshader") as Shader

# ============================================================
# 墙体（v10 完整保留）
# ============================================================
func _build_walls() -> void:
	var walls_root: Node3D = get_node_or_null("World/Walls")
	if walls_root == null:
		walls_root = Node3D.new()
		walls_root.name = "Walls"
		$World.add_child(walls_root)
	for c in walls_root.get_children():
		c.queue_free()

	var h: float = WALL_HEIGHT
	var t: float = WALL_THICKNESS
	var hy: float = h * 0.5

	# 主厅南墙（5 段）
	_add_wall(walls_root, Vector3(-6.4, hy, 9), Vector3(3.2, h, t), _wall_main_mat, "MainWallS_Seg1")
	_add_wall(walls_root, Vector3(-4, 0.5, 9), Vector3(1.6, 1.0, t), _wall_main_mat, "MainWallS_Seg2Lower")
	_add_wall(walls_root, Vector3(-4, 2.45, 9), Vector3(1.6, 1.1, t), _wall_main_mat, "MainWallS_Seg2Upper")
	_add_wall(walls_root, Vector3(0, hy, 9), Vector3(6.4, h, t), _wall_main_mat, "MainWallS_Seg3")
	_add_wall(walls_root, Vector3(4, 0.5, 9), Vector3(1.6, 1.0, t), _wall_main_mat, "MainWallS_Seg4Lower")
	_add_wall(walls_root, Vector3(4, 2.45, 9), Vector3(1.6, 1.1, t), _wall_main_mat, "MainWallS_Seg4Upper")
	_add_wall(walls_root, Vector3(6.4, hy, 9), Vector3(3.2, h, t), _wall_main_mat, "MainWallS_Seg5")

	# 主厅东墙（3 段，窗在 Z=4）
	_add_wall(walls_root, Vector3(8, hy, 6.9), Vector3(t, h, 4.2), _wall_main_mat, "MainWallE_North")
	_add_wall(walls_root, Vector3(8, 0.5, 4), Vector3(t, 1.0, 1.6), _wall_main_mat, "MainWallE_MidLower")
	_add_wall(walls_root, Vector3(8, 2.45, 4), Vector3(t, 1.1, 1.6), _wall_main_mat, "MainWallE_MidUpper")
	_add_wall(walls_root, Vector3(8, hy, 1.1), Vector3(t, h, 4.2), _wall_main_mat, "MainWallE_South")

	# 主厅西墙
	_add_wall(walls_root, Vector3(-8, hy, 4), Vector3(t, h, 10), _wall_main_mat, "MainWallW")

	# 主厅↔卧室/储藏室 内墙
	_add_wall(walls_root, Vector3(-5.8, hy, -1), Vector3(4.4, h, t), _wall_main_mat, "DivSegA")
	_add_wall(walls_root, Vector3(-1.2, hy, -1), Vector3(2.4, h, t), _wall_main_mat, "DivSegB1")
	_add_wall(walls_root, Vector3(1.7, hy, -1), Vector3(3.4, h, t), _wall_stor_mat, "StorWallN1")
	_add_wall(walls_root, Vector3(6.3, hy, -1), Vector3(3.4, h, t), _wall_stor_mat, "StorWallN2")

	# 卧室西墙（3 段，窗在 Z=-5）
	_add_wall(walls_root, Vector3(-8, hy, -2.65), Vector3(t, h, 3.3), _wall_bed_mat, "BedWallW_North")
	_add_wall(walls_root, Vector3(-8, 0.5, -5), Vector3(t, 1.0, 1.4), _wall_bed_mat, "BedWallW_MidLower")
	_add_wall(walls_root, Vector3(-8, 2.45, -5), Vector3(t, 1.1, 1.4), _wall_bed_mat, "BedWallW_MidUpper")
	_add_wall(walls_root, Vector3(-8, hy, -7.35), Vector3(t, h, 3.3), _wall_bed_mat, "BedWallW_South")

	# 卧室南墙
	_add_wall(walls_root, Vector3(-4, hy, -9), Vector3(8, h, t), _wall_bed_mat, "BedWallS")

	# 储藏室东墙（3 段，窗在 Z=-5）
	_add_wall(walls_root, Vector3(8, hy, -2.85), Vector3(t, h, 3.7), _wall_stor_mat, "StorWallE_North")
	_add_wall(walls_root, Vector3(8, 0.7, -5), Vector3(t, 1.4, 0.6), _wall_stor_mat, "StorWallE_MidLower")
	_add_wall(walls_root, Vector3(8, 2.4, -5), Vector3(t, 1.2, 0.6), _wall_stor_mat, "StorWallE_MidUpper")
	_add_wall(walls_root, Vector3(8, hy, -7.15), Vector3(t, h, 3.7), _wall_stor_mat, "StorWallE_South")

	# 储藏室南墙
	_add_wall(walls_root, Vector3(4, hy, -9), Vector3(8, h, t), _wall_stor_mat, "StorWallS")

	# 卧室↔储藏室 纵向 8m 实心墙
	_add_wall(walls_root, Vector3(0, hy, -5), Vector3(t, h, 8), _wall_main_mat, "InnerWallEW")

func _add_wall(parent: Node, pos: Vector3, size: Vector3, mat: Material, n: String) -> void:
	var sb := StaticBody3D.new()
	sb.name = n
	sb.collision_layer = 1
	sb.collision_mask = 0
	sb.position = pos
	parent.add_child(sb)

	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	sb.add_child(mi)

	var cs := CollisionShape3D.new()
	cs.name = "Coll"
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	sb.add_child(cs)

func _build_skirting() -> void:
	var walls_root: Node3D = get_node_or_null("World/Walls")
	if walls_root == null:
		return
	for w in walls_root.get_children():
		if not (w is StaticBody3D):
			continue
		var mesh_node := w.get_node_or_null("Mesh") as MeshInstance3D
		if mesh_node == null:
			continue
		var bm := mesh_node.mesh as BoxMesh
		if bm == null:
			continue
		var sz: Vector3 = bm.size
		if sz.y < 0.5:
			continue
		var skirt := MeshInstance3D.new()
		skirt.name = "Skirt"
		var sm := BoxMesh.new()
		sm.size = Vector3(sz.x + 0.02, SKIRT_HEIGHT, sz.z + 0.02)
		skirt.mesh = sm
		skirt.material_override = _skirt_mat
		skirt.position = Vector3(0, -sz.y * 0.5 + SKIRT_HEIGHT * 0.5, 0)
		w.add_child(skirt)

# ============================================================
# v10 §5.4 窗户构建（5 扇）
# ============================================================
func _build_windows() -> void:
	var windows_root: Node3D = get_node_or_null("World/Windows")
	if windows_root == null:
		windows_root = Node3D.new()
		windows_root.name = "Windows"
		$World.add_child(windows_root)
	for c in windows_root.get_children():
		c.queue_free()

	_add_window(windows_root, "Win_MainS1", Vector3(-4, 1.4, 9), Vector2(1.6, 0.9), "south", false)
	_add_window(windows_root, "Win_MainS2", Vector3(4, 1.4, 9), Vector2(1.6, 0.9), "south", false)
	_add_window(windows_root, "Win_MainE", Vector3(8, 1.4, 4), Vector2(1.6, 0.9), "east", false)
	_add_window(windows_root, "Win_BedW", Vector3(-8, 1.4, -5), Vector2(1.4, 0.9), "west", false)
	_add_window(windows_root, "Win_StorE", Vector3(8, 1.6, -5), Vector2(0.6, 0.4), "east", true)

func _add_window(parent: Node, n: String, center: Vector3, size: Vector2, axis: String, frosted: bool) -> void:
	var w := Vector2(size.x, size.y)
	var win := Node3D.new()
	win.name = n
	win.position = center
	parent.add_child(win)

	var glass_mat := ShaderMaterial.new()
	if _glass_shader != null:
		glass_mat.shader = _glass_shader
	if frosted:
		glass_mat.set_shader_parameter("tint", Color(0.85, 0.85, 0.85, 0.7))
		glass_mat.set_shader_parameter("roughness_value", 0.6)
		glass_mat.set_shader_parameter("fresnel_strength", 0.6)
	else:
		glass_mat.set_shader_parameter("tint", Color(0.55, 0.75, 0.95, 0.35))
		glass_mat.set_shader_parameter("roughness_value", 0.05)
		glass_mat.set_shader_parameter("fresnel_strength", 0.6)

	var glass := MeshInstance3D.new()
	glass.name = "Glass"
	var gm := BoxMesh.new()
	gm.size = Vector3(w.x, w.y, 0.04)
	glass.mesh = gm
	glass.material_override = glass_mat
	glass.cast_shadow = 0
	win.add_child(glass)

	var frame_thick := 0.05
	var frame_depth := 0.08
	var ft := MeshInstance3D.new()
	ft.name = "FrameTop"
	var ftm := BoxMesh.new()
	ftm.size = Vector3(w.x + frame_thick * 2, frame_thick, frame_depth)
	ft.mesh = ftm
	ft.material_override = _frame_mat
	ft.position = Vector3(0, w.y * 0.5 + frame_thick * 0.5, 0)
	win.add_child(ft)
	var fb := MeshInstance3D.new()
	fb.name = "FrameBottom"
	var fbm := BoxMesh.new()
	fbm.size = Vector3(w.x + frame_thick * 2, frame_thick, frame_depth)
	fb.mesh = fbm
	fb.material_override = _frame_mat
	fb.position = Vector3(0, -w.y * 0.5 - frame_thick * 0.5, 0)
	win.add_child(fb)
	var fl := MeshInstance3D.new()
	fl.name = "FrameLeft"
	var flm := BoxMesh.new()
	flm.size = Vector3(frame_thick, w.y, frame_depth)
	fl.mesh = flm
	fl.material_override = _frame_mat
	fl.position = Vector3(-w.x * 0.5 - frame_thick * 0.5, 0, 0)
	win.add_child(fl)
	var fr := MeshInstance3D.new()
	fr.name = "FrameRight"
	var frm := BoxMesh.new()
	frm.size = Vector3(frame_thick, w.y, frame_depth)
	fr.mesh = frm
	fr.material_override = _frame_mat
	fr.position = Vector3(w.x * 0.5 + frame_thick * 0.5, 0, 0)
	win.add_child(fr)
	if w.x >= 1.0:
		var fmid := MeshInstance3D.new()
		fmid.name = "FrameMid"
		var fmm := BoxMesh.new()
		fmm.size = Vector3(frame_thick * 0.6, w.y, frame_depth * 0.6)
		fmid.mesh = fmm
		fmid.material_override = _frame_mat
		win.add_child(fmid)
		var fmidh := MeshInstance3D.new()
		fmidh.name = "FrameMidH"
		var fmhm := BoxMesh.new()
		fmhm.size = Vector3(w.x, frame_thick * 0.6, frame_depth * 0.6)
		fmidh.mesh = fmhm
		fmidh.material_override = _frame_mat
		win.add_child(fmidh)

	var sun := SpotLight3D.new()
	sun.name = "SunLight"
	sun.light_color = Color(1.0, 0.961, 0.816)
	sun.light_energy = 1.0 if frosted else 2.5
	sun.spot_range = 8.0
	sun.spot_angle = 28.0
	sun.shadow_enabled = false
	win.add_child(sun)

	match axis:
		"south":
			sun.position = Vector3(0, 0.4, 1.5)
			sun.look_at(win.global_position + Vector3(0, 0, -1) - sun.position, Vector3.UP)
		"east":
			win.rotation.y = deg_to_rad(-90.0)
			sun.position = Vector3(0, 0.4, -1.5)
		"west":
			win.rotation.y = deg_to_rad(90.0)
			sun.position = Vector3(0, 0.4, -1.5)

	sun.rotation.y = deg_to_rad(180.0)

# ============================================================
# v11 §4-6 装饰布置（完全程序化构建）
#   §4 卧室重摆：床(-7,0,-7)靠西、衣柜(-3.5,0,-8.7)靠北、化妆台(-1.5,0,-3.5)靠东
#                床头柜(-7,0,-8.5)、地毯(-5.5,0.005,-7) 2.5×1.8m，无 Cabinet/Safe
#   §5 主厅治乱：客厅(西半 X<0)：沙发(-5.5,0,4)、茶几(-5.5,0,2.5)、TVStand(-5.5,0,0.5)、
#                TV(-5.5,0.55,0.3) rot.y=PI、落地灯(-7,0,1.5)、大地毯 4×5
#                餐厅(东半)：餐桌(4,0,4)、4椅、餐边柜(7,0,0.5)、小地毯 3×3
#                玄关：鞋柜(-3,0,8.5)+盆栽(-1.5,0,8.5)
#   §6 生活细节：茶几加 2 杂志+咖啡杯；TV 柜加相框+小盆栽；餐桌加碗+2 瓶+4 双筷子；
#                床头柜加闹钟(emission 0.3)+3 本书；卧室西墙挂画；
#                储藏室加报纸堆+充电器(绿 LED)+保险箱(已搬到 Containers/Storage_Safe)；
#                玄关加钥匙挂钩+脚垫+雨伞架。所有装饰无 collision（碰撞由 _DECOR_NO_COLLISION 排除）。
# 装饰 y 分层避免 z-fight：桌面 0.76 / 碗底 0.79 / 瓶 0.83
# ============================================================
func _build_extra_decor() -> void:
	var decor: Node3D = get_node_or_null("World/Decor") as Node3D
	if decor == null:
		decor = Node3D.new()
		decor.name = "Decor"
		$World.add_child(decor)
	for c in decor.get_children():
		c.queue_free()

	_build_living_room(decor)
	_build_dining_room(decor)
	_build_entrance(decor)
	_build_bedroom(decor)
	_build_storage(decor)


func _build_living_room(decor: Node) -> void:
	var lr := Node3D.new()
	lr.name = "LivingRoom"
	decor.add_child(lr)

	# 大地毯 4×5
	var rug := MeshInstance3D.new()
	rug.name = "Rug"
	var rugm := PlaneMesh.new(); rugm.size = Vector2(4.0, 5.0); rug.mesh = rugm
	rug.material_override = _make_mat(Color(0.32, 0.20, 0.20), 0.95)
	rug.transform.origin = Vector3(-5.5, 0.005, 2.0)
	lr.add_child(rug)

	# 沙发 (-5.5,0,4) 正面朝北（朝茶几z=2.5），靠背朝南墙z=9
	var sofa := Node3D.new()
	sofa.name = "Sofa"
	sofa.transform.origin = Vector3(-5.5, 0, 4)
	# v11.1 修复：去掉 rotation.y=PI，让正面朝向茶几（z=2.5），靠背朝南墙（z=9）
	lr.add_child(sofa)
	var sofa_base := MeshInstance3D.new()
	sofa_base.name = "Base"
	var sbm := BoxMesh.new(); sbm.size = Vector3(2.4, 0.45, 0.85); sofa_base.mesh = sbm
	sofa_base.material_override = _make_mat(Color(0.227, 0.290, 0.412), 0.85)
	sofa_base.transform.origin = Vector3(0, 0.25, 0)
	sofa.add_child(sofa_base)
	var sofa_back := MeshInstance3D.new()
	sofa_back.name = "Back"
	var sbkm := BoxMesh.new(); sbkm.size = Vector3(2.4, 0.55, 0.20); sofa_back.mesh = sbkm
	sofa_back.material_override = _make_mat(Color(0.227, 0.290, 0.412), 0.85)
	sofa_back.transform.origin = Vector3(0, 0.75, 0.4)
	sofa.add_child(sofa_back)
	for i in range(3):
		var cushion := MeshInstance3D.new()
		cushion.name = "Cushion%d" % (i + 1)
		var cm := BoxMesh.new(); cm.size = Vector3(0.75, 0.18, 0.65); cushion.mesh = cm
		cushion.material_override = _make_mat(Color(0.27, 0.34, 0.46), 0.85)
		cushion.transform.origin = Vector3(-0.78 + i * 0.78, 0.55, -0.05)
		sofa.add_child(cushion)

	# 茶几 (-5.5,0,2.5)
	var coffee := Node3D.new()
	coffee.name = "CoffeeTable"
	coffee.transform.origin = Vector3(-5.5, 0, 2.5)
	lr.add_child(coffee)
	var top := MeshInstance3D.new()
	top.name = "Top"
	var topm := BoxMesh.new(); topm.size = Vector3(1.2, 0.06, 0.7); top.mesh = topm
	top.material_override = _make_mat(Color(0.45, 0.30, 0.18), 0.6)
	top.transform.origin = Vector3(0, 0.40, 0)
	coffee.add_child(top)
	for i in range(4):
		var leg := MeshInstance3D.new()
		leg.name = "Leg%d" % (i + 1)
		var lm := BoxMesh.new(); lm.size = Vector3(0.06, 0.40, 0.06); leg.mesh = lm
		leg.material_override = _make_mat(Color(0.45, 0.30, 0.18), 0.6)
		var lx: float = -0.55 if i % 2 == 0 else 0.55
		var lz: float = -0.30 if i / 2 == 0 else 0.30
		leg.transform.origin = Vector3(lx, 0.20, lz)
		coffee.add_child(leg)
	# §6 茶几细节：2 杂志 + 1 咖啡杯（桌面 y=0.43 上方）
	var magm := BoxMesh.new(); magm.size = Vector3(0.30, 0.012, 0.22)
	var mag1 := MeshInstance3D.new()
	mag1.name = "Magazine1"
	mag1.mesh = magm
	mag1.material_override = _make_mat(Color(0.85, 0.20, 0.30), 0.7)
	mag1.transform.origin = Vector3(-0.30, 0.44, -0.10)
	mag1.rotation.y = deg_to_rad(15.0)
	coffee.add_child(mag1)
	var mag2 := MeshInstance3D.new()
	mag2.name = "Magazine2"
	mag2.mesh = magm
	mag2.material_override = _make_mat(Color(0.18, 0.45, 0.80), 0.7)
	mag2.transform.origin = Vector3(-0.20, 0.452, -0.05)
	mag2.rotation.y = deg_to_rad(-8.0)
	coffee.add_child(mag2)
	var cup := Node3D.new()
	cup.name = "CoffeeCup"
	cup.transform.origin = Vector3(0.30, 0.43, 0.10)
	coffee.add_child(cup)
	var cup_body := MeshInstance3D.new()
	cup_body.name = "Body"
	var cbm := CylinderMesh.new(); cbm.top_radius = 0.05; cbm.bottom_radius = 0.045; cbm.height = 0.08
	cup_body.mesh = cbm
	cup_body.material_override = _make_mat(Color(0.95, 0.95, 0.92), 0.5)
	cup_body.transform.origin = Vector3(0, 0.04, 0)
	cup.add_child(cup_body)
	var cup_coffee := MeshInstance3D.new()
	cup_coffee.name = "Coffee"
	var ccm := CylinderMesh.new(); ccm.top_radius = 0.045; ccm.bottom_radius = 0.045; ccm.height = 0.005
	cup_coffee.mesh = ccm
	cup_coffee.material_override = _make_mat(Color(0.20, 0.10, 0.05), 0.4)
	cup_coffee.transform.origin = Vector3(0, 0.078, 0)
	cup.add_child(cup_coffee)

	# TVStand (-5.5,0,0.5) + TV (-5.5,0.55,0.3) rot.y=PI（屏幕朝 +Z=沙发）
	var tvstand := MeshInstance3D.new()
	tvstand.name = "TVStand"
	var tvsm := BoxMesh.new(); tvsm.size = Vector3(2.0, 0.5, 0.45); tvstand.mesh = tvsm
	tvstand.material_override = _make_mat(Color(0.18, 0.13, 0.10), 0.6)
	tvstand.transform.origin = Vector3(-5.5, 0.25, 0.5)
	lr.add_child(tvstand)
	var tv := MeshInstance3D.new()
	tv.name = "TV"
	var tvm := BoxMesh.new(); tvm.size = Vector3(1.6, 0.9, 0.08); tv.mesh = tvm
	var tv_mat := _make_mat(Color(0.05, 0.05, 0.07), 0.2)
	tv_mat.emission_enabled = true
	tv_mat.emission = Color(0.10, 0.30, 0.55)
	tv_mat.emission_energy_multiplier = 0.4
	tv.material_override = tv_mat
	tv.transform.origin = Vector3(-5.5, 0.55, 0.3)
	tv.rotation.y = PI
	lr.add_child(tv)
	# §6 TV 柜细节：相框 + 小盆栽（柜面 y=0.5）
	var frame := MeshInstance3D.new()
	frame.name = "PhotoFrame"
	var fmsh := BoxMesh.new(); fmsh.size = Vector3(0.18, 0.22, 0.02); frame.mesh = fmsh
	var frame_mat := _make_mat(Color(0.85, 0.75, 0.55), 0.4)
	frame_mat.emission_enabled = true
	frame_mat.emission = Color(0.95, 0.85, 0.65)
	frame_mat.emission_energy_multiplier = 0.10
	frame.material_override = frame_mat
	frame.transform.origin = Vector3(-6.2, 0.62, 0.5)
	lr.add_child(frame)
	var sm_pot := Node3D.new()
	sm_pot.name = "SmallPot"
	sm_pot.transform.origin = Vector3(-4.8, 0.5, 0.5)
	lr.add_child(sm_pot)
	var sm_pot_body := MeshInstance3D.new()
	sm_pot_body.name = "Pot"
	var smpm := CylinderMesh.new(); smpm.top_radius = 0.10; smpm.bottom_radius = 0.08; smpm.height = 0.14
	sm_pot_body.mesh = smpm
	sm_pot_body.material_override = _make_mat(Color(0.42, 0.28, 0.18), 0.85)
	sm_pot_body.transform.origin = Vector3(0, 0.07, 0)
	sm_pot.add_child(sm_pot_body)
	var sm_leaves := MeshInstance3D.new()
	sm_leaves.name = "Leaves"
	var smlvm := SphereMesh.new(); smlvm.radius = 0.14; smlvm.height = 0.22
	sm_leaves.mesh = smlvm
	sm_leaves.material_override = _make_mat(Color(0.20, 0.50, 0.25), 0.85)
	sm_leaves.transform.origin = Vector3(0, 0.24, 0)
	sm_pot.add_child(sm_leaves)

	# 落地灯 (-7,0,1.5)
	var lamp_pole := MeshInstance3D.new()
	lamp_pole.name = "Stand"
	var lpm := CylinderMesh.new(); lpm.top_radius = 0.03; lpm.bottom_radius = 0.04; lpm.height = 1.5
	lamp_pole.mesh = lpm
	lamp_pole.material_override = _make_mat(Color(0.18, 0.13, 0.08), 0.5)
	lamp_pole.transform.origin = Vector3(-7, 0.75, 1.5)
	lr.add_child(lamp_pole)
	var lamp_shade := MeshInstance3D.new()
	lamp_shade.name = "Shade"
	var lsm := CylinderMesh.new(); lsm.top_radius = 0.18; lsm.bottom_radius = 0.22; lsm.height = 0.25
	lamp_shade.mesh = lsm
	var ls_mat := _make_mat(Color(0.95, 0.85, 0.55), 0.7)
	ls_mat.emission_enabled = true
	ls_mat.emission = Color(1.0, 0.85, 0.55)
	ls_mat.emission_energy_multiplier = 0.5
	lamp_shade.material_override = ls_mat
	lamp_shade.transform.origin = Vector3(-7, 1.55, 1.5)
	lr.add_child(lamp_shade)
	var lamp_bulb := OmniLight3D.new()
	lamp_bulb.name = "Bulb"
	lamp_bulb.transform.origin = Vector3(-7, 1.55, 1.5)
	lamp_bulb.light_color = Color(1.0, 0.85, 0.6)
	lamp_bulb.light_energy = 1.5
	lamp_bulb.omni_range = 4.0
	lamp_bulb.shadow_enabled = false
	lr.add_child(lamp_bulb)


func _build_dining_room(decor: Node) -> void:
	var dr := Node3D.new()
	dr.name = "DiningRoom"
	decor.add_child(dr)

	# 小地毯 3×3
	var rug := MeshInstance3D.new()
	rug.name = "Rug"
	var rugm := PlaneMesh.new(); rugm.size = Vector2(3.0, 3.0); rug.mesh = rugm
	rug.material_override = _make_mat(Color(0.40, 0.32, 0.20), 0.95)
	rug.transform.origin = Vector3(4, 0.005, 4)
	dr.add_child(rug)

	# 餐桌 (4,0,4)（桌面 y=0.76）
	var dtable := MeshInstance3D.new()
	dtable.name = "DiningTable"
	var dtm := BoxMesh.new(); dtm.size = Vector3(1.6, 0.06, 0.9); dtable.mesh = dtm
	dtable.material_override = _make_mat(Color(0.50, 0.32, 0.18), 0.55)
	dtable.transform.origin = Vector3(4, 0.76, 4)
	dr.add_child(dtable)

	# 4 椅 (3/5, 0, 3/5)
	var chair_positions := [Vector3(4, 0, 3.15), Vector3(4, 0, 4.85), Vector3(2.85, 0, 4), Vector3(5.15, 0, 4)]
	for i in range(chair_positions.size()):
		var chair := MeshInstance3D.new()
		chair.name = "Chair%d" % (i + 1)
		var chm := BoxMesh.new(); chm.size = Vector3(0.40, 0.40, 0.40); chair.mesh = chm
		chair.material_override = _make_mat(Color(0.40, 0.27, 0.16), 0.6)
		var p: Vector3 = chair_positions[i]
		chair.transform.origin = Vector3(p.x, 0.20, p.z)
		dr.add_child(chair)

	# 餐边柜 (7,0,0.5)
	var dcab := MeshInstance3D.new()
	dcab.name = "DiningCabinet"
	var dcm := BoxMesh.new(); dcm.size = Vector3(1.2, 1.4, 0.4); dcab.mesh = dcm
	dcab.material_override = _make_mat(Color(0.30, 0.22, 0.14), 0.7)
	dcab.transform.origin = Vector3(7, 0.7, 0.5)
	dr.add_child(dcab)

	# §6 餐桌细节：2 碗 + 2 瓶 + 4 双筷子
	for i in range(2):
		var bowl := MeshInstance3D.new()
		bowl.name = "Bowl%d" % (i + 1)
		var bowm := CylinderMesh.new(); bowm.top_radius = 0.10; bowm.bottom_radius = 0.06; bowm.height = 0.05
		bowl.mesh = bowm
		bowl.material_override = _make_mat(Color(0.95, 0.95, 0.92), 0.4)
		bowl.transform.origin = Vector3(4 + (i - 0.5) * 0.45, 0.79 + 0.025, 4)
		dr.add_child(bowl)
	for i in range(2):
		var bottle := MeshInstance3D.new()
		bottle.name = "Bottle%d" % (i + 1)
		var bm := CylinderMesh.new(); bm.top_radius = 0.04; bm.bottom_radius = 0.045; bm.height = 0.30
		bottle.mesh = bm
		var bcol: Color = Color(0.10, 0.30, 0.20) if i == 0 else Color(0.45, 0.20, 0.10)
		bottle.material_override = _make_mat(bcol, 0.3)
		bottle.transform.origin = Vector3(3.50 + i * 1.0, 0.83 + 0.15, 3.85)
		dr.add_child(bottle)
	var chop_corners := [Vector2(3.55, 3.55), Vector2(4.45, 3.55), Vector2(3.55, 4.45), Vector2(4.45, 4.45)]
	for i in range(chop_corners.size()):
		for j in range(2):
			var chop := MeshInstance3D.new()
			chop.name = "Chopstick_%d_%d" % [i, j]
			var cm := BoxMesh.new(); cm.size = Vector3(0.012, 0.012, 0.24); chop.mesh = cm
			chop.material_override = _make_mat(Color(0.65, 0.45, 0.25), 0.4)
			var c: Vector2 = chop_corners[i]
			chop.transform.origin = Vector3(c.x + (j - 0.5) * 0.025, 0.795 + 0.006, c.y)
			dr.add_child(chop)


func _build_entrance(decor: Node) -> void:
	var en := Node3D.new()
	en.name = "Entrance"
	decor.add_child(en)

	# 鞋柜 (-3,0,8.5)
	var shoebox := MeshInstance3D.new()
	shoebox.name = "ShoeCabinet"
	var sbm := BoxMesh.new(); sbm.size = Vector3(1.2, 0.5, 0.4); shoebox.mesh = sbm
	shoebox.material_override = _make_mat(Color(0.30, 0.22, 0.14), 0.7)
	shoebox.transform.origin = Vector3(-3, 0.25, 8.5)
	en.add_child(shoebox)

	# 玄关盆栽 (-1.5,0,8.5)
	var plant := Node3D.new()
	plant.name = "EntrancePlant"
	plant.transform.origin = Vector3(-1.5, 0, 8.5)
	en.add_child(plant)
	var pot := MeshInstance3D.new()
	pot.name = "Pot"
	var ptm := CylinderMesh.new(); ptm.top_radius = 0.20; ptm.bottom_radius = 0.16; ptm.height = 0.30
	pot.mesh = ptm
	pot.material_override = _make_mat(Color(0.36, 0.24, 0.16), 0.85)
	pot.transform.origin = Vector3(0, 0.15, 0)
	plant.add_child(pot)
	var leaves := MeshInstance3D.new()
	leaves.name = "Leaves"
	var lvm := SphereMesh.new(); lvm.radius = 0.32; lvm.height = 0.7
	leaves.mesh = lvm
	leaves.material_override = _make_mat(Color(0.18, 0.45, 0.22), 0.85)
	leaves.transform.origin = Vector3(0, 0.55, 0)
	plant.add_child(leaves)

	# §6 钥匙挂钩（板 + 3 钩）（北墙 z=8.85）
	var hookboard := MeshInstance3D.new()
	hookboard.name = "KeyHookBoard"
	var hbm := BoxMesh.new(); hbm.size = Vector3(0.40, 0.10, 0.02); hookboard.mesh = hbm
	hookboard.material_override = _make_mat(Color(0.50, 0.35, 0.20), 0.5)
	hookboard.transform.origin = Vector3(-2.2, 1.60, 8.85)
	en.add_child(hookboard)
	for i in range(3):
		var hook := MeshInstance3D.new()
		hook.name = "Hook%d" % (i + 1)
		var hm := CylinderMesh.new(); hm.top_radius = 0.008; hm.bottom_radius = 0.008; hm.height = 0.05
		hook.mesh = hm
		hook.material_override = _make_mat(Color(0.85, 0.85, 0.85), 0.3)
		hook.transform.origin = Vector3(-2.32 + i * 0.12, 1.55, 8.85)
		hook.rotation.x = deg_to_rad(90.0)
		en.add_child(hook)

	# §6 脚垫 0.8×0.5
	var mat := MeshInstance3D.new()
	mat.name = "Doormat"
	var mm := PlaneMesh.new(); mm.size = Vector2(0.8, 0.5); mat.mesh = mm
	mat.material_override = _make_mat(Color(0.18, 0.22, 0.16), 0.95)
	mat.transform.origin = Vector3(-3, 0.005, 7.9)
	en.add_child(mat)

	# §6 雨伞架（cylinder + 2 把伞）
	var stand := Node3D.new()
	stand.name = "UmbrellaStand"
	stand.transform.origin = Vector3(-3.9, 0, 8.5)
	en.add_child(stand)
	var stand_body := MeshInstance3D.new()
	stand_body.name = "Body"
	var stm := CylinderMesh.new(); stm.top_radius = 0.10; stm.bottom_radius = 0.10; stm.height = 0.50
	stand_body.mesh = stm
	stand_body.material_override = _make_mat(Color(0.30, 0.30, 0.32), 0.5)
	stand_body.transform.origin = Vector3(0, 0.25, 0)
	stand.add_child(stand_body)
	for i in range(2):
		var um := MeshInstance3D.new()
		um.name = "Umbrella%d" % (i + 1)
		var umm := CylinderMesh.new(); umm.top_radius = 0.025; umm.bottom_radius = 0.025; umm.height = 0.85
		um.mesh = umm
		um.material_override = _make_mat(Color(0.20, 0.30, 0.55) if i == 0 else Color(0.55, 0.20, 0.30), 0.6)
		um.transform.origin = Vector3((i - 0.5) * 0.08, 0.55, 0.0)
		um.rotation.z = deg_to_rad((i - 0.5) * 14.0)
		stand.add_child(um)


func _build_bedroom(decor: Node) -> void:
	var br := Node3D.new()
	br.name = "Bedroom"
	decor.add_child(br)

	# 地毯 (-5.5,0.005,-7) 2.5×1.8
	var rug := MeshInstance3D.new()
	rug.name = "Rug"
	var rugm := PlaneMesh.new(); rugm.size = Vector2(2.5, 1.8); rug.mesh = rugm
	rug.material_override = _make_mat(Color(0.54, 0.22, 0.22), 0.95)
	rug.transform.origin = Vector3(-5.5, 0.005, -7)
	br.add_child(rug)

	# 床 (-7,0,-7) 靠西墙
	var bed := Node3D.new()
	bed.name = "Bed"
	bed.transform.origin = Vector3(-7, 0, -7)
	br.add_child(bed)
	var frame := MeshInstance3D.new()
	frame.name = "Frame"
	var fmesh := BoxMesh.new(); fmesh.size = Vector3(1.4, 0.25, 2.0); frame.mesh = fmesh
	frame.material_override = _make_mat(Color(0.30, 0.20, 0.12), 0.8)
	frame.transform.origin = Vector3(0, 0.20, 0)
	bed.add_child(frame)
	var mattress := MeshInstance3D.new()
	mattress.name = "Mattress"
	var mmesh := BoxMesh.new(); mmesh.size = Vector3(1.3, 0.18, 1.9); mattress.mesh = mmesh
	mattress.material_override = _make_mat(Color(0.92, 0.88, 0.78), 0.9)
	mattress.transform.origin = Vector3(0, 0.42, 0)
	bed.add_child(mattress)
	var pillow := MeshInstance3D.new()
	pillow.name = "Pillow"
	var pmesh := BoxMesh.new(); pmesh.size = Vector3(1.1, 0.10, 0.45); pillow.mesh = pmesh
	pillow.material_override = _make_mat(Color(0.95, 0.94, 0.90), 0.95)
	pillow.transform.origin = Vector3(0, 0.56, -0.7)
	bed.add_child(pillow)
	var blanket := MeshInstance3D.new()
	blanket.name = "Blanket"
	var blmesh := BoxMesh.new(); blmesh.size = Vector3(1.30, 0.05, 1.20); blanket.mesh = blmesh
	blanket.material_override = _make_mat(Color(0.40, 0.18, 0.20), 0.9)
	blanket.transform.origin = Vector3(0, 0.54, 0.35)
	bed.add_child(blanket)

	# 衣柜 (-3.5,0,-8.7) 靠北
	var wardrobe := MeshInstance3D.new()
	wardrobe.name = "Wardrobe"
	var wm := BoxMesh.new(); wm.size = Vector3(1.4, 2.0, 0.6); wardrobe.mesh = wm
	wardrobe.material_override = _make_mat(Color(0.22, 0.15, 0.08), 0.7)
	wardrobe.transform.origin = Vector3(-3.5, 1.0, -8.7)
	br.add_child(wardrobe)

	# 化妆台 (-1.5,0,-3.5)
	var dresser := Node3D.new()
	dresser.name = "DressingTable"
	dresser.transform.origin = Vector3(-1.5, 0, -3.5)
	br.add_child(dresser)
	var d_body := MeshInstance3D.new()
	d_body.name = "Body"
	var dbm := BoxMesh.new(); dbm.size = Vector3(0.9, 0.85, 0.45); d_body.mesh = dbm
	d_body.material_override = _make_mat(Color(0.48, 0.32, 0.20), 0.6)
	d_body.transform.origin = Vector3(0, 0.425, 0)
	dresser.add_child(d_body)
	var mirror := MeshInstance3D.new()
	mirror.name = "Mirror"
	var mirm := BoxMesh.new(); mirm.size = Vector3(0.55, 0.70, 0.03); mirror.mesh = mirm
	var mir_mat := StandardMaterial3D.new()
	mir_mat.albedo_color = Color(0.85, 0.90, 0.95)
	mir_mat.metallic = 0.9
	mir_mat.roughness = 0.10
	mirror.material_override = mir_mat
	mirror.transform.origin = Vector3(0, 1.40, 0.20)
	dresser.add_child(mirror)

	# §4 床头柜 (-7,0,-8.5) + §6 闹钟 + 3 本书
	var ns := Node3D.new()
	ns.name = "Nightstand"
	ns.transform.origin = Vector3(-7, 0, -8.5)
	br.add_child(ns)
	var ns_body := MeshInstance3D.new()
	ns_body.name = "Body"
	var nsm := BoxMesh.new(); nsm.size = Vector3(0.45, 0.50, 0.40); ns_body.mesh = nsm
	ns_body.material_override = _make_mat(Color(0.30, 0.20, 0.12), 0.7)
	ns_body.transform.origin = Vector3(0, 0.25, 0)
	ns.add_child(ns_body)
	var alarm := MeshInstance3D.new()
	alarm.name = "AlarmClock"
	var am := BoxMesh.new(); am.size = Vector3(0.18, 0.10, 0.10); alarm.mesh = am
	var alarm_mat := _make_mat(Color(0.85, 0.10, 0.10), 0.4)
	alarm_mat.emission_enabled = true
	alarm_mat.emission = Color(1.0, 0.20, 0.15)
	alarm_mat.emission_energy_multiplier = 0.30  # 严格 0.3
	alarm.material_override = alarm_mat
	alarm.transform.origin = Vector3(-0.10, 0.55, 0.0)
	ns.add_child(alarm)
	var book_cols := [Color(0.18, 0.45, 0.65), Color(0.65, 0.30, 0.20), Color(0.30, 0.55, 0.30)]
	for i in range(3):
		var book := MeshInstance3D.new()
		book.name = "Book%d" % (i + 1)
		var bkm := BoxMesh.new(); bkm.size = Vector3(0.20, 0.04, 0.15); book.mesh = bkm
		book.material_override = _make_mat(book_cols[i], 0.7)
		book.transform.origin = Vector3(0.10, 0.50 + 0.022 + i * 0.044, 0.0)
		book.rotation.y = deg_to_rad((i - 1) * 6.0)
		ns.add_child(book)

	# §6 卧室西墙挂画
	var painting := MeshInstance3D.new()
	painting.name = "BedroomPainting"
	var pmsh := BoxMesh.new(); pmsh.size = Vector3(0.05, 0.8, 1.2); painting.mesh = pmsh
	var paint_mat := _make_mat(Color(0.55, 0.42, 0.32), 0.5)
	paint_mat.emission_enabled = true
	paint_mat.emission = Color(0.65, 0.50, 0.35)
	paint_mat.emission_energy_multiplier = 0.12
	painting.material_override = paint_mat
	painting.transform.origin = Vector3(-7.94, 1.6, -5.2)
	br.add_child(painting)


func _build_storage(decor: Node) -> void:
	var st := Node3D.new()
	st.name = "Storage"
	decor.add_child(st)

	# 钢架 + 3 层板 + 3 纸箱
	var shelf := Node3D.new()
	shelf.name = "Shelf"
	shelf.transform.origin = Vector3(2.0, 0, -8.5)
	st.add_child(shelf)
	var sframe := MeshInstance3D.new()
	sframe.name = "Frame"
	var sfm := BoxMesh.new(); sfm.size = Vector3(2.0, 1.8, 0.4); sframe.mesh = sfm
	sframe.material_override = _make_mat(Color(0.18, 0.20, 0.24), 0.4)
	sframe.transform.origin = Vector3(0, 0.9, 0)
	shelf.add_child(sframe)
	for i in range(3):
		var plank := MeshInstance3D.new()
		plank.name = "Plank%d" % (i + 1)
		var plm := BoxMesh.new(); plm.size = Vector3(2.0, 0.04, 0.4); plank.mesh = plm
		plank.material_override = _make_mat(Color(0.18, 0.20, 0.24), 0.4)
		plank.transform.origin = Vector3(0, 0.40 + i * 0.55, 0)
		shelf.add_child(plank)
	for i in range(3):
		var box := MeshInstance3D.new()
		box.name = "Box%d" % (i + 1)
		var bxm := BoxMesh.new(); bxm.size = Vector3(0.55, 0.45, 0.4); box.mesh = bxm
		box.material_override = _make_mat(Color(0.62, 0.45, 0.28), 0.95)
		box.transform.origin = Vector3(-0.55 + i * 0.55, 0.65 + (i % 2) * 0.55, 0)
		shelf.add_child(box)

	# §6 报纸堆（5 层薄 BoxMesh 错位旋转）
	for i in range(5):
		var paper := MeshInstance3D.new()
		paper.name = "Newspaper%d" % (i + 1)
		var pm := BoxMesh.new(); pm.size = Vector3(0.32, 0.012, 0.24); paper.mesh = pm
		paper.material_override = _make_mat(Color(0.92, 0.90, 0.85) if i % 2 == 0 else Color(0.85, 0.82, 0.75), 0.8)
		paper.transform.origin = Vector3(4.5, 0.012 + i * 0.013, -8.5)
		paper.rotation.y = deg_to_rad((i - 2) * 7.0)
		st.add_child(paper)

	# §6 充电器（黑 box + 绿 LED）
	var charger := Node3D.new()
	charger.name = "Charger"
	charger.transform.origin = Vector3(3.0, 0, -3.5)
	st.add_child(charger)
	var ch_body := MeshInstance3D.new()
	ch_body.name = "Body"
	var chm := BoxMesh.new(); chm.size = Vector3(0.18, 0.06, 0.12); ch_body.mesh = chm
	ch_body.material_override = _make_mat(Color(0.10, 0.10, 0.12), 0.5)
	ch_body.transform.origin = Vector3(0, 0.03, 0)
	charger.add_child(ch_body)
	var led := MeshInstance3D.new()
	led.name = "LED"
	var lm := SphereMesh.new(); lm.radius = 0.012; lm.height = 0.024
	led.mesh = lm
	var led_mat := _make_mat(Color(0.20, 0.95, 0.30), 0.2)
	led_mat.emission_enabled = true
	led_mat.emission = Color(0.30, 1.0, 0.35)
	led_mat.emission_energy_multiplier = 1.5
	led.material_override = led_mat
	led.transform.origin = Vector3(0.05, 0.062, 0.05)
	charger.add_child(led)

	# 老纸箱堆（保留 v10 现场感）
	for i in range(3):
		var cb := MeshInstance3D.new()
		cb.name = "CardPile%d" % (i + 1)
		var cbm := BoxMesh.new()
		cbm.size = Vector3([0.6, 0.7, 0.5][i], [0.5, 0.4, 0.6][i], [0.5, 0.6, 0.4][i])
		cb.mesh = cbm
		cb.material_override = _make_mat(Color(0.62, 0.45, 0.28), 0.95)
		cb.transform.origin = Vector3(1.5 + i * 0.4, [0.25, 0.20, 0.30][i], -7.8 - i * 0.4)
		cb.rotation.y = deg_to_rad(i * 25.0)
		st.add_child(cb)

	# 垃圾桶
	var trash := Node3D.new()
	trash.name = "TrashBin"
	trash.transform.origin = Vector3(7.4, 0, -3.6)
	st.add_child(trash)
	var trash_body := MeshInstance3D.new()
	trash_body.name = "Body"
	var trbm := CylinderMesh.new(); trbm.top_radius = 0.22; trbm.bottom_radius = 0.20; trbm.height = 0.5
	trash_body.mesh = trbm
	trash_body.material_override = _make_mat(Color(0.20, 0.22, 0.24), 0.55)
	trash_body.transform.origin = Vector3(0, 0.25, 0)
	trash.add_child(trash_body)
	var trash_lid := MeshInstance3D.new()
	trash_lid.name = "Lid"
	var trlm := CylinderMesh.new(); trlm.top_radius = 0.23; trlm.bottom_radius = 0.23; trlm.height = 0.04
	trash_lid.mesh = trlm
	trash_lid.material_override = _make_mat(Color(0.20, 0.22, 0.24), 0.55)
	trash_lid.transform.origin = Vector3(0, 0.52, 0)
	trash.add_child(trash_lid)

	# 立管
	var pipe := MeshInstance3D.new()
	pipe.name = "Pipe"
	var ppm := CylinderMesh.new(); ppm.top_radius = 0.08; ppm.bottom_radius = 0.08; ppm.height = 2.8
	pipe.mesh = ppm
	pipe.material_override = _make_mat(Color(0.42, 0.42, 0.42), 0.4)
	pipe.transform.origin = Vector3(7.7, 1.4, -5)
	st.add_child(pipe)


func _make_mat(col: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	return m

# ============================================================
# 装饰物碰撞补齐 + 排除清单（v11 §6：所有装饰小物无 collision）
# ============================================================
const _DECOR_NO_COLLISION := [
	# v10 已有
	"Painting", "Rug", "Pipe", "Bulb", "Shade", "Stand",
	"TV", "Mirror",
	"Coat1", "Coat2", "Pole", "Knob1", "Knob2", "Knob3",
	"ControlPanel", "Door",
	# v11 §6 装饰小物
	"Magazine1", "Magazine2",
	"PhotoFrame", "AlarmClock",
	"Book1", "Book2", "Book3",
	"Bowl1", "Bowl2", "Bottle1", "Bottle2",
	"BedroomPainting",
	"Newspaper1", "Newspaper2", "Newspaper3", "Newspaper4", "Newspaper5",
	"KeyHookBoard", "Hook1", "Hook2", "Hook3",
	"Doormat",
	"Umbrella1", "Umbrella2",
	"LED",
	"Plate1", "Plate2", "Plate3"
]

func _ensure_decor_collisions() -> void:
	var decor: Node = get_node_or_null("World/Decor")
	if decor == null:
		return
	_wrap_decor_recursive(decor)

func _wrap_decor_recursive(n: Node) -> void:
	var to_wrap: Array = []
	for child in n.get_children():
		if child is MeshInstance3D:
			if _DECOR_NO_COLLISION.has(child.name):
				continue
			# 筷子/装饰小物（命名前缀匹配）跳过 collision
			var cn: String = child.name
			if cn.begins_with("Chopstick_"):
				continue
			if n is StaticBody3D:
				continue
			to_wrap.append(child)
		else:
			_wrap_decor_recursive(child)
	for mi in to_wrap:
		_wrap_meshinstance_with_static_body(mi as MeshInstance3D)

func _wrap_meshinstance_with_static_body(mi: MeshInstance3D) -> void:
	var bm := mi.mesh as BoxMesh
	if bm == null:
		return
	var sb := StaticBody3D.new()
	sb.name = mi.name + "_Body"
	sb.collision_layer = 1
	sb.collision_mask = 0
	sb.transform = mi.transform

	var parent: Node = mi.get_parent()
	var idx: int = mi.get_index()
	parent.remove_child(mi)
	parent.add_child(sb)
	parent.move_child(sb, idx)

	mi.transform = Transform3D.IDENTITY
	sb.add_child(mi)

	var cs := CollisionShape3D.new()
	cs.name = "Coll"
	var sh := BoxShape3D.new()
	sh.size = bm.size
	cs.shape = sh
	sb.add_child(cs)

# ============================================================
# 房间可达性自检
# ============================================================
func _verify_reachability() -> void:
	var space := get_world_3d().direct_space_state
	if space == null:
		return
	var spawn: Vector3 = Vector3(0, 1, 0)
	if spawn_marker != null:
		spawn = spawn_marker.global_position
	var checks := [
		{"name": "Bedroom door", "from": spawn, "to": Vector3(-3.0, 1.0, -1.5)},
		{"name": "Bedroom center", "from": Vector3(-3.0, 1.0, -1.5), "to": Vector3(-4.0, 1.0, -5.0)},
		{"name": "Storage door", "from": spawn, "to": Vector3(4.0, 1.0, -1.5)},
		{"name": "Storage center", "from": Vector3(4.0, 1.0, -1.5), "to": Vector3(4.0, 1.0, -5.0)},
	]
	for chk in checks:
		var params := PhysicsRayQueryParameters3D.create(chk["from"], chk["to"])
		params.collision_mask = 1
		params.collide_with_areas = false
		params.collide_with_bodies = true
		var hit: Dictionary = space.intersect_ray(params)
		if not hit.is_empty():
			var hitter: Object = hit.get("collider", null)
			var is_door := false
			if hitter is Node:
				is_door = (hitter as Node).is_in_group("doors")
			if not is_door:
				push_warning("[v11 reachability] %s blocked by %s at %s" % [chk["name"], str(hitter), str(hit.get("position", Vector3.ZERO))])

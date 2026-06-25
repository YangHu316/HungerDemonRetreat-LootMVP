extends CharacterBody3D
class_name Monster

# 外卖侠 §五:饕餮怪物寻人系统(单人 MVP)
# 状态机(简化版,跳过"搜寻/锁定/吸入" — 后续 Phase 接小游戏遭遇):
#   IDLE         — 在 spawn 点静止,订阅 EventBus.sound_emitted
#   INVESTIGATE  — 听到声音 → 朝声源点(非玩家当前位置)走 → 接触玩家 catch
#   COOLDOWN     — catch 后 teleport 回 spawn,5s 内忽略所有声音
#
# 听到判定(用户选 C):dist ≤ radius AND random < radius/MAX_RADIUS
#   - sneak 1.5m/12m = 12.5%
#   - walk  5.0m/12m = 41.6%
#   - run  12.0m/12m = 100%
# 移动(用户选 B):朝目标走,前向 raycast 检测墙体 → 墙挡住时侧偏
# Catch(用户选 A.A):≤ 0.8m → gs.apply_time_penalty(180);怪物回 spawn,player 2s 无敌

const MAX_HEAR_RADIUS: float = 12.0  # = run sound radius(spec 05§1.2:run 12m)
const MOVE_SPEED: float = 2.5
const CATCH_RADIUS: float = 0.8
const CATCH_TIME_PENALTY: float = 180.0  # 3 分钟(MVP 占位,spec 是转盘小游戏)
const COOLDOWN_TIME: float = 5.0
const REACH_TARGET_DIST: float = 0.5     # 到声源算"到达"
const WALL_RAYCAST_LEN: float = 1.0      # 前方探墙距离
const SIDE_OFFSET_DEG: float = 35.0      # 撞墙时左右偏角
# §五 SEARCH:到声源后游荡找人,超时回家
# spec 05§2.1:搜寻 12-15s,移动 ×1.1。取中值 13s
const SEARCH_DURATION: float = 13.0
const SEARCH_WANDER_RADIUS: float = 2.0
const SEARCH_CHANGE_INTERVAL: float = 1.5
const SEARCH_SPEED_MUL: float = 1.1  # spec T2 base
# §五 Plan A 视野:仅在已警觉状态(INVESTIGATE/SEARCH/CHASE/RETURNING)生效
# IDLE 是聋瞎 — 玩家声圈外绝对安全(契约)
# spec 05§2.2:视距 ~8-10m / 锥角 90°。取中值 9m
const SEE_RADIUS: float = 9.0
const VISION_HALF_ANGLE_DEG: float = 45.0  # 90° 前向锥 → 半角 45°
# spec 05§2.1:放弃倒计时 ~10s(无新线索)
const CHASE_LOSE_TIME: float = 10.0
const CHASE_SPEED_MUL: float = 1.2
# §五 RETURNING:SEARCH 失败后走回 spawn,到家后才 IDLE
const RETURN_REACH_DIST: float = 0.6
# §06 玩家躲避系统:监测玩家 hidden 时视野返 false;SEARCH 态极近(1.5m)躲点 roll detect_prob 一次
const SPOT_DETECT_DIST: float = 1.5

enum State { IDLE, INVESTIGATE, SEARCH, CHASE, RETURNING, COOLDOWN }

var state: int = State.IDLE
var spawn_pos: Vector3 = Vector3.ZERO
var sound_target: Vector3 = Vector3.ZERO
var _cooldown_timer: float = 0.0
var _search_timer: float = 0.0
var _search_change_timer: float = 0.0
var _search_wander_pos: Vector3 = Vector3.ZERO
var _chase_lose_timer: float = 0.0
# §06 SEARCH 态躲点检测:同一 spot 同一次 SEARCH 只 roll 一次。状态切出 SEARCH 时清空
var _rolled_spots: Dictionary = {}  # instance_id → bool
var _bus: Node = null
var _gs: Node = null
var _rng: RandomNumberGenerator = null
var _wall_raycast: RayCast3D = null
var _mesh: MeshInstance3D = null
var _light: OmniLight3D = null

func _ready() -> void:
	add_to_group("monster")
	collision_layer = 0  # 怪物不被玩家撞(避免阻挡)
	collision_mask = 1   # 但能 raycast 探墙
	spawn_pos = global_position
	_rng = RandomNumberGenerator.new()
	_rng.randomize()
	_bus = get_node_or_null("/root/EventBus")
	_gs = get_node_or_null("/root/GameSession")
	if _bus != null and _bus.has_signal("sound_emitted"):
		if not _bus.sound_emitted.is_connected(_on_sound_emitted):
			_bus.sound_emitted.connect(_on_sound_emitted)
	_build_visual()
	_build_raycast()

func _build_visual() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.name = "Mesh"
	var cap := CapsuleMesh.new()
	cap.radius = 0.35
	cap.height = 1.6
	_mesh.mesh = cap
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.10, 0.12)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.20, 0.15)
	mat.emission_energy_multiplier = 0.6
	_mesh.material_override = mat
	_mesh.position.y = 0.8
	add_child(_mesh)

	_light = OmniLight3D.new()
	_light.name = "Light"
	_light.light_color = Color(1.0, 0.25, 0.20)
	_light.light_energy = 1.5
	_light.omni_range = 3.5
	_light.shadow_enabled = false
	_light.position.y = 1.0
	add_child(_light)

	# 简单碰撞(给 raycast 检测用,虽然 collision_layer=0 玩家不撞)
	var coll := CollisionShape3D.new()
	coll.name = "Coll"
	var sh := CapsuleShape3D.new()
	sh.radius = 0.35
	sh.height = 1.6
	coll.shape = sh
	coll.position.y = 0.8
	add_child(coll)
	# 不画怪物圈 — 判定是"玩家声音圈是否包住怪物",怪物本身没有"听感半径"

func _build_raycast() -> void:
	_wall_raycast = RayCast3D.new()
	_wall_raycast.name = "WallRay"
	_wall_raycast.target_position = Vector3(0, 0, -WALL_RAYCAST_LEN)
	_wall_raycast.collision_mask = 1
	_wall_raycast.position.y = 1.0
	add_child(_wall_raycast)

func _physics_process(delta: float) -> void:
	# round 不活跃 → idle 静止
	if _gs == null or not _gs.round_active:
		velocity = Vector3.ZERO
		return
	# §06:状态切出 SEARCH 时清空 _rolled_spots(下次进 SEARCH 重新 roll)
	if state != State.SEARCH and not _rolled_spots.is_empty():
		_rolled_spots.clear()
	# §五 Plan A 视野:仅在已警觉状态(INVESTIGATE/SEARCH/CHASE/RETURNING)生效
	# IDLE 是聋瞎 — 玩家声圈外绝对安全(核心契约)
	# COOLDOWN 期间不响应任何事件
	var alerted: bool = (state == State.INVESTIGATE \
		or state == State.SEARCH \
		or state == State.CHASE \
		or state == State.RETURNING)
	if alerted:
		var p := _find_local_player()
		if p != null and is_instance_valid(p) and not _player_is_invincible(p) and _can_see_player(p):
			state = State.CHASE
			_chase_lose_timer = 0.0
		elif state == State.CHASE:
			# 看不见了 → 累计 LOSE_TIME 后回 SEARCH
			_chase_lose_timer += delta
			if _chase_lose_timer >= CHASE_LOSE_TIME:
				state = State.SEARCH
				_search_timer = 0.0
				_search_change_timer = SEARCH_CHANGE_INTERVAL
				_chase_lose_timer = 0.0
				# 用最后看见的玩家位置作 search 中心
				if p != null and is_instance_valid(p):
					sound_target = p.global_position
	match state:
		State.IDLE:
			velocity = Vector3.ZERO
		State.INVESTIGATE:
			_tick_investigate(delta)
		State.SEARCH:
			_tick_search(delta)
		State.CHASE:
			_tick_chase(delta)
		State.RETURNING:
			_tick_return(delta)
		State.COOLDOWN:
			_cooldown_timer -= delta
			velocity = Vector3.ZERO
			if _cooldown_timer <= 0.0:
				state = State.IDLE
	move_and_slide()

# §五 CHASE:实时追玩家当前位置(看见才进此态)
func _tick_chase(delta: float) -> void:
	var player: Node3D = _find_local_player()
	if player == null or not is_instance_valid(player):
		state = State.SEARCH
		return
	# §06 玩家躲了 → 切 SEARCH(看不见目标)
	if _player_is_hidden(player):
		state = State.SEARCH
		return
	var d2: float = global_position.distance_squared_to(player.global_position)
	if d2 <= CATCH_RADIUS * CATCH_RADIUS:
		_catch(player)
		return
	# 朝玩家当前位置走(实时,不是 sound_target 锁死)
	_move_toward(player.global_position, MOVE_SPEED * CHASE_SPEED_MUL, delta)

# 视野判定:dist ≤ SEE_RADIUS + 90° 前向锥 + raycast 没墙挡
# §五 Plan A:玩家可绕到背后躲过视野(锥外不算看见)
# §06:玩家在躲点中(is_hidden_now)直接返 false
func _can_see_player(player: Node3D) -> bool:
	if player == null or not is_instance_valid(player):
		return false
	# §06 躲点遮断视野
	if player.has_method("is_hidden_now") and player.is_hidden_now():
		return false
	var to_player: Vector3 = player.global_position - global_position
	to_player.y = 0.0
	var d: float = to_player.length()
	if d > SEE_RADIUS or d < 0.001:
		return false
	# 90° 前向锥:Godot 默认 forward = -basis.z
	var forward: Vector3 = -global_transform.basis.z
	forward.y = 0.0
	var fl: float = forward.length()
	if fl < 0.001:
		return false
	forward = forward / fl
	var dir_xz: Vector3 = to_player / d
	var dot: float = forward.dot(dir_xz)
	var cos_half: float = cos(deg_to_rad(VISION_HALF_ANGLE_DEG))
	if dot < cos_half:
		return false  # 在锥外(背后/侧面)
	# 墙体遮挡
	var space := get_world_3d().direct_space_state
	if space == null:
		return true  # fallback no-raycast
	var from := global_position + Vector3(0, 1.0, 0)
	var to := player.global_position + Vector3(0, 1.0, 0)
	var params := PhysicsRayQueryParameters3D.create(from, to)
	params.collision_mask = 1  # walls only
	params.exclude = [self]
	var hit: Dictionary = space.intersect_ray(params)
	# 命中 = 有墙挡;空 = 无遮挡(看得见)
	return hit.is_empty()

# 玩家无敌期:catch 后 2s 内不再触发 CHASE/Catch
func _player_is_invincible(player: Node) -> bool:
	if player == null or not is_instance_valid(player):
		return false
	if player.has_method("is_invincible"):
		return player.is_invincible()
	return false

# §06:玩家是否在躲点中(hidden)→ 距离 catch / 视野 / CHASE 都跳过
# 唯一抓到躲藏玩家的途径是 _check_hiding_spot_detect 的概率 roll
func _player_is_hidden(player: Node) -> bool:
	if player == null or not is_instance_valid(player):
		return false
	if player.has_method("is_hidden_now"):
		return player.is_hidden_now()
	return false

func _tick_investigate(delta: float) -> void:
	# 接触玩家 → catch(§06 躲藏中跳过,只能走 _check_hiding_spot_detect)
	var player: Node3D = _find_local_player()
	if player != null and is_instance_valid(player) and not _player_is_hidden(player):
		var d2: float = global_position.distance_squared_to(player.global_position)
		if d2 <= CATCH_RADIUS * CATCH_RADIUS:
			_catch(player)
			return
	# 到达声源 → 切 SEARCH(原地游荡 SEARCH_DURATION 秒,等新声音)
	var dist_to_target: float = global_position.distance_to(sound_target)
	if dist_to_target <= REACH_TARGET_DIST:
		state = State.SEARCH
		_search_timer = 0.0
		_search_change_timer = SEARCH_CHANGE_INTERVAL  # 立刻选新游荡点
		velocity = Vector3.ZERO
		return
	_move_toward(sound_target, MOVE_SPEED, delta)

# §五 SEARCH 状态:到达声源后在附近游荡,等新声音 / catch 玩家
func _tick_search(delta: float) -> void:
	# Catch 检查同 INVESTIGATE(§06 躲藏中跳过)
	var player: Node3D = _find_local_player()
	if player != null and is_instance_valid(player) and not _player_is_hidden(player):
		var d2: float = global_position.distance_squared_to(player.global_position)
		if d2 <= CATCH_RADIUS * CATCH_RADIUS:
			_catch(player)
			return
	# 总计时:超 SEARCH_DURATION 没新声音 → §五 Plan A:走回 spawn(RETURNING)
	_search_timer += delta
	if _search_timer >= SEARCH_DURATION:
		state = State.RETURNING
		velocity = Vector3.ZERO
		return
	# 重选游荡点:超时 OR 已到达当前游荡点
	_search_change_timer += delta
	var reached_wander: bool = global_position.distance_to(_search_wander_pos) <= REACH_TARGET_DIST
	if _search_change_timer >= SEARCH_CHANGE_INTERVAL or reached_wander:
		var ang: float = _rng.randf() * TAU
		var r: float = _rng.randf_range(0.5, SEARCH_WANDER_RADIUS)
		_search_wander_pos = sound_target + Vector3(cos(ang) * r, 0.0, sin(ang) * r)
		_search_change_timer = 0.0
	# 朝当前游荡点走(spec 05§2.1 SEARCH 移动 ×1.1)
	_move_toward(_search_wander_pos, MOVE_SPEED * SEARCH_SPEED_MUL, delta)
	# §06 极近躲点 detect roll(同一 spot 同一次 SEARCH 只 roll 一次)
	_check_hiding_spot_detect()

# §06 SEARCH 态极近躲点 detect:遍历 hiding_spots group,在 SPOT_DETECT_DIST 内、
# 且有 occupants、且本次 SEARCH 还没 roll 过 → roll detect_prob
# 命中:第一个 occupant 被 unhide + _catch
func _check_hiding_spot_detect() -> void:
	for spot in get_tree().get_nodes_in_group("hiding_spots"):
		if not is_instance_valid(spot):
			continue
		var s3 := spot as Node3D
		if s3 == null:
			continue
		if global_position.distance_to(s3.global_position) > SPOT_DETECT_DIST:
			continue
		var occs: Array = []
		if spot.has_method("get_occupants"):
			occs = spot.get_occupants()
		if occs.is_empty():
			continue
		var key: int = spot.get_instance_id()
		if _rolled_spots.get(key, false):
			continue
		_rolled_spots[key] = true
		var prob: float = 0.0
		if "detection_prob" in spot:
			prob = float(spot.detection_prob)
		if _rng.randf() < prob:
			var first_occ = occs[0]
			if first_occ != null and is_instance_valid(first_occ):
				if first_occ.has_method("unhide"):
					first_occ.unhide()
				_catch(first_occ)
			return

# §五 Plan A RETURNING:SEARCH 失败 → 直线走回 spawn 点
# 路上仍可被新声音(_on_sound_emitted)/ 视野(_physics_process gate)重新触发 INVESTIGATE/CHASE
# 走到家 → IDLE(回到聋瞎,玩家声圈外再次绝对安全)
func _tick_return(delta: float) -> void:
	# 意外撞上玩家仍 catch(§06 躲藏中跳过)
	var player: Node3D = _find_local_player()
	if player != null and is_instance_valid(player) and not _player_is_hidden(player):
		var d2: float = global_position.distance_squared_to(player.global_position)
		if d2 <= CATCH_RADIUS * CATCH_RADIUS:
			_catch(player)
			return
	# 到家 → IDLE
	var d: float = global_position.distance_to(spawn_pos)
	if d <= RETURN_REACH_DIST:
		state = State.IDLE
		velocity = Vector3.ZERO
		return
	_move_toward(spawn_pos, MOVE_SPEED * 0.8, delta)

# 朝目标移动 + 简单墙体绕行(给 INVESTIGATE / SEARCH 共用)
func _move_toward(target: Vector3, speed: float, delta: float) -> void:
	var dir: Vector3 = (target - global_position)
	dir.y = 0.0
	if dir.length() < 0.01:
		velocity = Vector3.ZERO
		return
	dir = dir.normalized()
	var target_yaw: float = atan2(dir.x, dir.z) + PI
	rotation.y = lerp_angle(rotation.y, target_yaw, delta * 6.0)
	# 前方探墙 → 撞了就侧偏
	if _wall_raycast != null:
		_wall_raycast.force_raycast_update()
		if _wall_raycast.is_colliding():
			var side_sign: float = 1.0 if _rng.randf() < 0.5 else -1.0
			var rot := Basis(Vector3.UP, deg_to_rad(SIDE_OFFSET_DEG) * side_sign)
			dir = rot * dir
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	velocity.y = 0.0

func _on_sound_emitted(pos: Vector3, radius: float) -> void:
	if _gs == null or not _gs.round_active:
		return
	if state == State.COOLDOWN:
		return
	# 距离 gate
	var d: float = global_position.distance_to(pos)
	if d > radius:
		return
	# 概率 gate(C 选项):radius 越大概率越高
	var prob: float = clamp(radius / MAX_HEAR_RADIUS, 0.0, 1.0)
	if _rng.randf() > prob:
		return
	# 听到 → 切 INVESTIGATE,目标 = 声源点(非玩家当前位置)
	sound_target = pos
	state = State.INVESTIGATE
	# 重置 SEARCH 计时(若正在 SEARCH 时收到新声音 → 立刻去新声源)
	_search_timer = 0.0
	_search_change_timer = 0.0

func _catch(player: Node3D) -> void:
	# 玩家无敌期间不 catch
	if player.has_method("is_invincible") and player.is_invincible():
		return
	# §06 防御:玩家躲藏中不 catch(_check_hiding_spot_detect 内部会先 unhide 再 catch)
	if player.has_method("is_hidden_now") and player.is_hidden_now():
		return
	# 扣时间
	if _gs != null and _gs.has_method("apply_time_penalty"):
		_gs.apply_time_penalty(CATCH_TIME_PENALTY)
	# 玩家无敌 2s
	if player.has_method("grant_invincibility"):
		player.grant_invincibility(2.0)
	# teleport 回 spawn + cooldown
	global_position = spawn_pos
	velocity = Vector3.ZERO
	state = State.COOLDOWN
	_cooldown_timer = COOLDOWN_TIME

func _find_local_player() -> Node3D:
	# 单人模式只有 1 个 player;多人下 monster 不该 spawn(main.gd._spawn_monster 检查)
	# 兜底:在 group "player" 找 first
	var players: Array = get_tree().get_nodes_in_group("player")
	for p in players:
		if p is Node3D:
			return p as Node3D
	return null

# round 重启时重置(给 main.gd._on_round_started 调)
func reset_to_spawn() -> void:
	global_position = spawn_pos
	velocity = Vector3.ZERO
	state = State.IDLE
	_cooldown_timer = 0.0
	_search_timer = 0.0
	_search_change_timer = 0.0
	_chase_lose_timer = 0.0
	sound_target = Vector3.ZERO
	_search_wander_pos = Vector3.ZERO

extends GutTest

# 外卖侠 §五:饕餮怪物寻人系统(单人 MVP)
# 防御:
#   - EventBus 加 sound_emitted / monster_caught_player signal
#   - GameSession.apply_time_penalty(s) — 扣时间 + 立即广播 round_tick
#   - Player 加 is_invincible() / grant_invincibility() / 移动时按 stance 周期 emit sound
#   - Monster 状态机 IDLE / INVESTIGATE / COOLDOWN
#   - main.gd 单人模式 spawn 怪物;多人不 spawn
#   - round_started 重置怪物到 spawn 点

const MonsterScript := preload("res://scripts/entities/monster.gd")

var _gs: Node
var _bus: Node
var _mm: Node

func before_each() -> void:
	_gs = get_node("/root/GameSession")
	_bus = get_node("/root/EventBus")
	_mm = get_node("/root/MultiplayerManager")
	_mm.mode = _mm.Mode.SINGLE
	_mm.players.clear()
	_mm.peer = null
	_gs.round_active = false

func after_each() -> void:
	_gs.round_active = false

# ── EventBus signals ──

func test_event_bus_has_sound_emitted_signal() -> void:
	assert_true(_bus.has_signal("sound_emitted"),
		"EventBus 必须有 sound_emitted(pos, radius) 信号(§五 声音事件)")

func test_event_bus_has_monster_caught_player_signal() -> void:
	assert_true(_bus.has_signal("monster_caught_player"),
		"EventBus 必须有 monster_caught_player(time_penalty)(占位 catch 反馈)")

# ── GameSession.apply_time_penalty ──

func test_apply_time_penalty_subtracts_time() -> void:
	_gs.start_round()
	_gs.time_left = 600.0
	_gs.apply_time_penalty(180.0)
	assert_almost_eq(_gs.time_left, 420.0, 0.01,
		"apply_time_penalty(180) 应扣 180 秒")

func test_apply_time_penalty_clamps_to_zero() -> void:
	_gs.start_round()
	_gs.time_left = 50.0
	_gs.apply_time_penalty(180.0)
	assert_eq(_gs.time_left, 0.0,
		"apply_time_penalty 不能让 time_left 变负")

func test_apply_time_penalty_no_op_when_round_inactive() -> void:
	_gs.round_active = false
	_gs.time_left = 600.0
	_gs.apply_time_penalty(180.0)
	assert_eq(_gs.time_left, 600.0,
		"round 不活跃时 apply_time_penalty 应 no-op")

func test_apply_time_penalty_emits_signals() -> void:
	_gs.start_round()
	_gs.time_left = 600.0
	watch_signals(_bus)
	_gs.apply_time_penalty(180.0)
	assert_signal_emitted(_bus, "monster_caught_player",
		"apply_time_penalty 应 emit monster_caught_player")
	assert_signal_emitted(_bus, "round_tick",
		"apply_time_penalty 应立即 emit round_tick(给 HUD 更新)")

# ── Player invincibility ──

func test_player_has_invincibility_api() -> void:
	var src: String = load("res://scripts/entities/player.gd").source_code
	assert_true(src.contains("func is_invincible"),
		"Player 必须有 is_invincible() 方法")
	assert_true(src.contains("func grant_invincibility"),
		"Player 必须有 grant_invincibility(seconds) 方法")

func test_player_default_not_invincible() -> void:
	# 用源码层 + 最简 Node 测试方法逻辑(避免完整 player.tscn 实例化的副作用)
	var src: String = load("res://scripts/entities/player.gd").source_code
	var i: int = src.find("func is_invincible")
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0: j = src.length()
	var body: String = src.substr(i, j - i)
	# 默认 _invincible_until = 0.0 < 当前 ticks_msec/1000 → false
	assert_true(body.contains("Time.get_ticks_msec"),
		"is_invincible 必须用 Time.get_ticks_msec 判断时刻")
	assert_true(body.contains("_invincible_until"),
		"is_invincible 必须查 _invincible_until")
	# 确认默认值是 0.0
	assert_true(src.contains("_invincible_until: float = 0.0"),
		"_invincible_until 默认 0.0(默认不无敌)")

func test_player_grant_invincibility_works() -> void:
	var src: String = load("res://scripts/entities/player.gd").source_code
	var i: int = src.find("func grant_invincibility")
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0: j = src.length()
	var body: String = src.substr(i, j - i)
	assert_true(body.contains("_invincible_until"),
		"grant_invincibility 必须写 _invincible_until")
	assert_true(body.contains("Time.get_ticks_msec"),
		"grant_invincibility 必须用 Time.get_ticks_msec 算未来时刻")
	assert_true(body.contains("+ seconds") or body.contains("+seconds"),
		"grant_invincibility 必须 + seconds(未来时刻)")

# ── Player 移动 emit 声音 ──

func test_player_emits_sound_on_movement() -> void:
	var src: String = load("res://scripts/entities/player.gd").source_code
	# 必须有 _tick_sound_emit 函数(物理帧调)
	assert_true(src.contains("_tick_sound_emit"),
		"Player 必须有 _tick_sound_emit(给 _physics_process 调用)")
	# 必须有 SOUND_EMIT_INTERVAL 常量(节流)
	assert_true(src.contains("SOUND_EMIT_INTERVAL"),
		"Player 必须有 SOUND_EMIT_INTERVAL 常量(节流)")
	# 必须 emit sound_emitted
	var i: int = src.find("func _tick_sound_emit")
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0: j = src.length()
	var body: String = src.substr(i, j - i)
	assert_true(body.contains("sound_emitted.emit"),
		"_tick_sound_emit 必须 emit bus.sound_emitted")
	assert_true(body.contains("is_invincible"),
		"_tick_sound_emit 必须查 is_invincible(无敌期不 emit)")
	assert_true(body.contains("is_single") or body.contains("MultiplayerManager"),
		"_tick_sound_emit 多人模式应跳过(Phase 2C 再做 host 权威)")

# ── Monster 状态机 ──

func test_monster_has_states() -> void:
	var src: String = load("res://scripts/entities/monster.gd").source_code
	assert_true(src.contains("State.IDLE"),
		"Monster 必须有 IDLE 状态")
	assert_true(src.contains("State.INVESTIGATE"),
		"Monster 必须有 INVESTIGATE 状态")
	assert_true(src.contains("State.SEARCH"),
		"Monster 必须有 SEARCH 状态(到达声源后游荡 + 等新声音)")
	assert_true(src.contains("State.CHASE"),
		"Monster 必须有 CHASE 状态(看见玩家时实时追)")
	assert_true(src.contains("State.RETURNING"),
		"Monster 必须有 RETURNING 状态(§五 Plan A:SEARCH 失败回 spawn)")
	assert_true(src.contains("State.COOLDOWN"),
		"Monster 必须有 COOLDOWN 状态(catch 后 5s 不响应)")

func test_monster_has_vision_check() -> void:
	var src: String = load("res://scripts/entities/monster.gd").source_code
	assert_true(src.contains("func _can_see_player"),
		"Monster 必须有 _can_see_player(raycast 视野判定)")
	assert_true(src.contains("SEE_RADIUS"),
		"Monster 必须有 SEE_RADIUS 常量")
	# _physics_process 顶部必须查视野(但仅在已警觉状态)
	var i: int = src.find("func _physics_process")
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0: j = src.length()
	var body: String = src.substr(i, j - i)
	assert_true(body.contains("_can_see_player"),
		"_physics_process 必须调 _can_see_player(已警觉态看见玩家就 CHASE)")
	assert_true(body.contains("State.CHASE"),
		"_physics_process 必须能切换到 CHASE 状态")

# §五 Plan A 核心契约:IDLE 是聋瞎 — 玩家声圈外绝对安全
func test_monster_idle_does_not_check_vision() -> void:
	var src: String = load("res://scripts/entities/monster.gd").source_code
	var i: int = src.find("func _physics_process")
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0: j = src.length()
	var body: String = src.substr(i, j - i)
	# _can_see_player 调用之前必须有 state gate(包含 INVESTIGATE 与 SEARCH 两词)
	var see_idx: int = body.find("_can_see_player")
	assert_true(see_idx > 0, "_physics_process 必须调 _can_see_player")
	var pre: String = body.substr(0, see_idx)
	assert_true(pre.contains("INVESTIGATE") and pre.contains("SEARCH"),
		"§五 Plan A:_can_see_player 调用前必须 gate 在已警觉状态(IDLE 不查视野)")

# §五 Plan A 视野锥:90° 前向,玩家可绕到背后躲避
func test_monster_vision_has_cone_check() -> void:
	var src: String = load("res://scripts/entities/monster.gd").source_code
	assert_true(src.contains("VISION_HALF_ANGLE_DEG"),
		"Monster 必须有 VISION_HALF_ANGLE_DEG 常量(90° 锥半角)")
	var i: int = src.find("func _can_see_player")
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0: j = src.length()
	var body: String = src.substr(i, j - i)
	assert_true(body.contains("dot"),
		"_can_see_player 必须做前向夹角判定(forward.dot(dir))")
	assert_true(body.contains("basis"),
		"_can_see_player 必须用 transform.basis 取前向方向")

func test_monster_vision_sees_player_in_front() -> void:
	# rotation.y = 0 → forward = -basis.z = (0,0,-1)
	# 玩家在 -Z 前方 2m → 在锥内 + 距离内 → 看得见
	var m := _spawn_monster_at(Vector3.ZERO)
	m.rotation.y = 0.0
	var fake := _make_fake_player_at(Vector3(0.0, 0.0, -2.0))
	assert_true(m._can_see_player(fake),
		"玩家在前方 2m 锥内必须看得见")

func test_monster_vision_blocked_behind() -> void:
	# 玩家在 +Z 背后 2m → 锥外 → 看不见(可绕背后躲避)
	var m := _spawn_monster_at(Vector3.ZERO)
	m.rotation.y = 0.0  # forward = -Z
	var fake := _make_fake_player_at(Vector3(0.0, 0.0, 2.0))
	assert_false(m._can_see_player(fake),
		"玩家在背后必须看不见(90° 前向锥)")

func test_monster_vision_blocked_outside_radius() -> void:
	# 距离超 SEE_RADIUS 即使在锥内也看不见
	var m := _spawn_monster_at(Vector3.ZERO)
	m.rotation.y = 0.0
	var fake := _make_fake_player_at(Vector3(0.0, 0.0, -(m.SEE_RADIUS + 2.0)))
	assert_false(m._can_see_player(fake),
		"距离超 SEE_RADIUS 必须看不见")

func test_monster_reach_sound_enters_search_not_idle() -> void:
	# 用户报"只追几步" — 之前到达声源立刻 IDLE,现在应进 SEARCH 游荡
	var m := _spawn_monster_at(Vector3.ZERO)
	_gs.start_round()
	m.state = m.State.INVESTIGATE
	m.sound_target = Vector3(0.1, 0.0, 0.0)  # 极近,_tick_investigate 立刻判到达
	m._tick_investigate(0.016)
	assert_eq(m.state, m.State.SEARCH,
		"到达声源后应进 SEARCH(游荡找人),不是立刻 IDLE")

# §五 Plan A:SEARCH 超时不再回 IDLE,而是回 RETURNING(走回家)
func test_monster_search_times_out_returns_home() -> void:
	var m := _spawn_monster_at(Vector3.ZERO)
	_gs.start_round()
	m.state = m.State.SEARCH
	m._search_timer = 0.0
	m.sound_target = Vector3.ZERO
	# 模拟超时:推进 SEARCH_DURATION + 0.1 秒
	m._tick_search(m.SEARCH_DURATION + 0.1)
	assert_eq(m.state, m.State.RETURNING,
		"§五 Plan A:SEARCH 总时长用完应进 RETURNING(走回 spawn)")

# §五 Plan A:RETURNING 走到 spawn 才 IDLE(避免无限漫游)
func test_monster_has_returning_tick() -> void:
	var src: String = load("res://scripts/entities/monster.gd").source_code
	assert_true(src.contains("func _tick_return"),
		"Monster 必须有 _tick_return 处理回家逻辑")
	assert_true(src.contains("RETURN_REACH_DIST"),
		"Monster 必须有 RETURN_REACH_DIST 常量(到家阈值)")

func test_monster_returning_at_spawn_becomes_idle() -> void:
	var m := _spawn_monster_at(Vector3.ZERO)  # spawn_pos = 0 (在 _ready 锁定)
	_gs.start_round()
	m.global_position = Vector3.ZERO
	m.state = m.State.RETURNING
	m._tick_return(0.016)
	assert_eq(m.state, m.State.IDLE,
		"RETURNING 到达 spawn 应回 IDLE")

func test_monster_returning_walks_toward_spawn() -> void:
	var m := _spawn_monster_at(Vector3.ZERO)  # spawn_pos = 0
	_gs.start_round()
	m.global_position = Vector3(3.0, 0.0, 0.0)  # 远离 spawn
	m.state = m.State.RETURNING
	m._tick_return(0.016)
	assert_eq(m.state, m.State.RETURNING,
		"未到家应保持 RETURNING")
	# velocity 应朝 spawn(-X 方向)
	assert_lt(m.velocity.x, 0.0,
		"RETURNING velocity 应朝 spawn(-X)")

func test_monster_new_sound_during_search_resumes_investigate() -> void:
	# SEARCH 中收到新声音 → 切回 INVESTIGATE 追新声源
	var m := _spawn_monster_at(Vector3.ZERO)
	_gs.start_round()
	m.state = m.State.SEARCH
	m._search_timer = 3.0  # 已搜了 3s
	m.sound_target = Vector3.ZERO
	m._on_sound_emitted(Vector3(2.0, 0.0, 0.0), 12.0)  # spec run radius 100%
	assert_eq(m.state, m.State.INVESTIGATE,
		"SEARCH 中新声音 → 切 INVESTIGATE")
	assert_eq(m._search_timer, 0.0,
		"_search_timer 必须重置")

func test_monster_subscribes_sound_emitted() -> void:
	var src: String = load("res://scripts/entities/monster.gd").source_code
	assert_true(src.contains("sound_emitted.connect"),
		"Monster 必须订阅 EventBus.sound_emitted")
	assert_true(src.contains("func _on_sound_emitted"),
		"Monster 必须有 _on_sound_emitted handler")

func test_monster_idle_to_investigate_on_close_loud_sound() -> void:
	# 创建一个 monster + 模拟声音事件,验证状态切到 INVESTIGATE
	var m := _spawn_monster_at(Vector3.ZERO)
	_gs.start_round()
	# 距离 3m,radius 12m(spec run)→ prob = 12/12 = 100% 必听到
	m._on_sound_emitted(Vector3(3.0, 0.0, 0.0), 12.0)
	assert_eq(m.state, m.State.INVESTIGATE,
		"听到声音后应切 INVESTIGATE")
	assert_almost_eq(m.sound_target.x, 3.0, 0.01,
		"sound_target 必须是声源点(非玩家当前位置)")

func test_monster_ignores_sound_outside_radius() -> void:
	var m := _spawn_monster_at(Vector3.ZERO)
	_gs.start_round()
	# 距离 13m,radius 12m → 距离超过半径,直接忽略(spec 最大 run 12m)
	m._on_sound_emitted(Vector3(13.0, 0.0, 0.0), 12.0)
	assert_eq(m.state, m.State.IDLE,
		"距离超 radius 必须不响应")

func test_monster_ignores_sound_during_cooldown() -> void:
	var m := _spawn_monster_at(Vector3.ZERO)
	_gs.start_round()
	m.state = m.State.COOLDOWN
	m._on_sound_emitted(Vector3(1.0, 0.0, 0.0), 12.0)
	assert_eq(m.state, m.State.COOLDOWN,
		"COOLDOWN 期间必须忽略声音")

func test_monster_ignores_sound_round_inactive() -> void:
	var m := _spawn_monster_at(Vector3.ZERO)
	_gs.round_active = false
	m._on_sound_emitted(Vector3(1.0, 0.0, 0.0), 12.0)
	assert_eq(m.state, m.State.IDLE,
		"round 不活跃必须不响应")

func test_monster_target_is_sound_origin_not_player() -> void:
	# §五 关键设计:追声源点,玩家移动后怪物仍走原点
	var m := _spawn_monster_at(Vector3.ZERO)
	_gs.start_round()
	m._on_sound_emitted(Vector3(3.0, 0.0, 0.0), 12.0)
	assert_almost_eq(m.sound_target.x, 3.0, 0.01,
		"sound_target 应锁定为发声时刻的 pos(玩家移动后不更新)")

func test_monster_catch_applies_time_penalty() -> void:
	var m := _spawn_monster_at(Vector3.ZERO)
	_gs.start_round()
	_gs.time_left = 600.0
	# 模拟玩家:简单 Node3D + is_invincible/grant_invincibility 方法
	var fake := _make_fake_player_at(Vector3(0.5, 0.0, 0.0))
	m._catch(fake)
	assert_almost_eq(_gs.time_left, 420.0, 0.5,
		"catch 应扣 180s")
	assert_eq(m.state, m.State.COOLDOWN,
		"catch 后状态应 COOLDOWN")
	assert_true(fake.is_invincible(),
		"catch 后玩家应 2s 无敌")

func test_monster_catch_skipped_if_player_invincible() -> void:
	var m := _spawn_monster_at(Vector3.ZERO)
	_gs.start_round()
	_gs.time_left = 600.0
	var fake := _make_fake_player_at(Vector3(0.5, 0.0, 0.0))
	fake.grant_invincibility(2.0)
	m._catch(fake)
	assert_almost_eq(_gs.time_left, 600.0, 0.01,
		"玩家无敌时 catch 应被跳过(time_left 不变)")

# ── main.gd 单人 spawn / 多人不 spawn ──

func test_main_spawns_monster_in_single_mode() -> void:
	var src: String = load("res://scripts/main.gd").source_code
	assert_true(src.contains("_spawn_monster_if_single"),
		"main.gd 必须有 _spawn_monster_if_single 函数")
	assert_true(src.contains("MonsterScript"),
		"main.gd 必须 preload monster.gd")
	# 函数体必须按 _is_multiplayer 分支跳过多人
	var i: int = src.find("func _spawn_monster_if_single")
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0: j = src.length()
	var body: String = src.substr(i, j - i)
	assert_true(body.contains("_is_multiplayer"),
		"_spawn_monster_if_single 必须按 _is_multiplayer 跳过多人模式")

func test_main_resets_monster_on_round_started() -> void:
	# main.gd._on_round_started 必须 reset 怪物到 spawn 点
	var src: String = load("res://scripts/main.gd").source_code
	var i: int = src.find("func _on_round_started")
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0: j = src.length()
	var body: String = src.substr(i, j - i)
	assert_true(body.contains("monster") and body.contains("reset_to_spawn"),
		"_on_round_started 必须 reset monster 到 spawn 点(下一局重置)")

# ── 辅助 ──

func _spawn_monster_at(pos: Vector3) -> CharacterBody3D:
	var m := CharacterBody3D.new()
	m.set_script(MonsterScript)
	add_child_autofree(m)
	m.global_position = pos
	return m

class FakePlayer extends Node3D:
	var _inv_until: float = 0.0
	func is_invincible() -> bool:
		return Time.get_ticks_msec() / 1000.0 < _inv_until
	func grant_invincibility(s: float) -> void:
		_inv_until = Time.get_ticks_msec() / 1000.0 + s

func _make_fake_player_at(pos: Vector3) -> FakePlayer:
	var p := FakePlayer.new()
	add_child_autofree(p)
	p.global_position = pos
	return p

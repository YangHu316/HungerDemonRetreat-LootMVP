extends GutTest

# Phase 2B Tier B1:Round 生命周期 host-authoritative
# 防御:
#   - GameSession 加 _extracted_this_round 字段,start_round reset
#   - tick() timeout 触发要尊重 mm.is_client() 短路
#   - main.gd._ready 必须按 mm.mode 决定本地 start_round vs 等 RPC
#   - MultiplayerManager 加 broadcast_round_start / _rpc_apply_round_start

var _gs: Node
var _mm: Node
var _bus: Node

func before_each() -> void:
	_gs = get_node_or_null("/root/GameSession")
	_mm = get_node_or_null("/root/MultiplayerManager")
	_bus = get_node_or_null("/root/EventBus")
	# 重置 MM 状态,默认单人(避免上一个 test 残留)
	if _mm != null:
		_mm.mode = _mm.Mode.SINGLE
		_mm.players.clear()
		_mm.peer = null
	# 重置 round 状态
	if _gs != null:
		_gs.round_active = false
		_gs.state = "PLAYING"
		_gs.time_left = _gs.ROUND_TIME

func after_each() -> void:
	# 恢复
	if _mm != null:
		_mm.mode = _mm.Mode.SINGLE
		_mm.players.clear()
		_mm.peer = null
	if _gs != null:
		_gs.round_active = false
		_gs.state = "PLAYING"

# ── 字段/方法存在性 ──

func test_game_session_has_extracted_flag() -> void:
	assert_not_null(_gs, "GameSession autoload 应存在")
	assert_true("_extracted_this_round" in _gs,
		"GameSession 必须有 _extracted_this_round 字段(Phase 2B 区分 extracted vs 迷失)")

func test_game_session_has_mark_extracted_api() -> void:
	assert_true(_gs.has_method("mark_extracted_this_round"),
		"GameSession 必须有 mark_extracted_this_round() 给 extraction_zone 调")

func test_mm_has_broadcast_round_start() -> void:
	assert_not_null(_mm, "MultiplayerManager autoload 应存在")
	assert_true(_mm.has_method("broadcast_round_start"),
		"MM 必须有 broadcast_round_start(host 调,广播 round_start 给 client)")

func test_mm_has_rpc_apply_round_start() -> void:
	assert_true(_mm.has_method("_rpc_apply_round_start"),
		"MM 必须有 _rpc_apply_round_start RPC")

# ── start_round 行为 ──

func test_start_round_resets_extracted_flag() -> void:
	_gs._extracted_this_round = true  # 模拟上局撤离
	_gs.start_round()
	assert_false(_gs._extracted_this_round,
		"start_round 必须重置 _extracted_this_round = false")
	_gs.round_active = false

func test_start_round_clears_inspect_log_if_present() -> void:
	# LocalInspectLog 在 B3 加。如果存在,start_round 应 clear。
	# 这个测试在 B1 阶段对 null 容忍(soft-call)。
	var lil = get_node_or_null("/root/LocalInspectLog")
	if lil == null:
		# B3 未实施,跳过具体校验
		pending("LocalInspectLog autoload not yet registered (B3 will add)")
		return
	# B3 后:_gs.start_round 后 log 必须空
	lil.mark_inspected("test_path", 42)
	_gs.start_round()
	assert_false(lil.is_inspected("test_path", 42),
		"start_round 后 LocalInspectLog 应清空")
	_gs.round_active = false

# ── mark_extracted_this_round 行为 ──

func test_mark_extracted_sets_flag() -> void:
	_gs.start_round()
	assert_false(_gs._extracted_this_round, "新 round 默认未撤离")
	_gs.mark_extracted_this_round()
	assert_true(_gs._extracted_this_round, "mark_extracted 后 flag = true")
	_gs.round_active = false

# ── tick timeout host-authoritative ──

func test_tick_timeout_in_single_mode_triggers_end_round() -> void:
	# 单人模式:tick 减时钟到 0 → end_round("timeout")
	_mm.mode = _mm.Mode.SINGLE
	_gs.start_round()
	_gs.time_left = 0.1
	_gs.tick(1.0)
	assert_false(_gs.round_active,
		"单人 tick timeout 必须触发 end_round")

func test_tick_timeout_in_client_mode_does_not_trigger_end_round() -> void:
	# 多人 client:tick 减时钟到 0 但不触发 end_round(等 host 广播)
	_mm.mode = _mm.Mode.CLIENT
	_gs.start_round()
	_gs.time_left = 0.1
	_gs.tick(1.0)
	# round_active 仍 true,因为 client 不本地结束
	assert_true(_gs.round_active,
		"多人 client tick timeout 不能本地触发 end_round(等 host 广播)")
	# cleanup
	_gs.round_active = false

func test_tick_timeout_in_host_mode_does_not_trigger_end_round() -> void:
	# Phase 2B v2:多人模式 host gs.tick 不再本地 end_round
	# 全局 timer 由 mm._process 推进(host 即使本人撤了,仍要 tick 等其他 peer)
	# host 的 gs.tick 在多人下与 client 同 — 减 time_left 但不 end_round
	_mm.mode = _mm.Mode.HOST
	_gs.start_round()
	_gs.time_left = 0.1
	_gs.tick(1.0)
	assert_true(_gs.round_active,
		"多人 host gs.tick timeout 不能本地 end_round(全局 timer 由 mm._process 决定)")
	# cleanup
	_gs.round_active = false

# ── main.gd 源码层验证 ──

func test_main_gd_gates_start_round_by_mode() -> void:
	# main.gd._ready 必须分支:单人/host 本地 start_round,client 等 RPC
	var src: String = load("res://scripts/main.gd").source_code
	# 必须有 mm.is_single() 或 mm.is_host() 之一判断
	assert_true(src.contains("is_single()") or src.contains("is_host()"),
		"main.gd._ready 必须按 mm.mode 决定是否本地 start_round")
	# 必须调 broadcast_round_start 在 host 分支
	assert_true(src.contains("broadcast_round_start"),
		"main.gd host 分支必须调 mm.broadcast_round_start")

func test_mm_broadcast_round_start_calls_rpc() -> void:
	# 源码层验证 broadcast_round_start 走 _rpc_apply_round_start.rpc()
	var src: String = load("res://scripts/autoloads/multiplayer_manager.gd").source_code
	# 找 broadcast_round_start 函数体
	var i: int = src.find("func broadcast_round_start")
	assert_gte(i, 0, "broadcast_round_start 函数应存在")
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0:
		j = src.length()
	var body: String = src.substr(i, j - i)
	assert_true(body.contains("_rpc_apply_round_start.rpc"),
		"broadcast_round_start 必须调 _rpc_apply_round_start.rpc(广播给所有 peer)")
	assert_true(body.contains("is_host()") or body.contains("Mode.HOST"),
		"broadcast_round_start 必须先校验 is_host (防 client 误调)")

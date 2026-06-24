extends GutTest

# Phase 2B v2:Per-peer 独立 done + 全员 done 后团队订单结算
# 设计:
#   - 任一 peer 撤离 → mm.notify_extracted → host _rpc_request_peer_done
#   - host 标 peer status,广播 _rpc_apply_peer_done(本人 → end_round;其他人 → emit signal hide Player)
#   - host 检测全员 done(extracted/timeout)→ 计算订单合计 → _rpc_apply_team_result 广播
#   - timeout:host 全局 timer(mm._process)在 _global_round_active 时 tick;到 0 → broadcast_round_end_timeout
#   - extraction_zone 多人模式调 mm.request_extract(host 直接调 notify_extracted;client rpc_id)

var _gs: Node
var _mm: Node
var _bus: Node
var _inv: Node

func before_each() -> void:
	_gs = get_node("/root/GameSession")
	_mm = get_node("/root/MultiplayerManager")
	_bus = get_node("/root/EventBus")
	_inv = get_node("/root/PlayerInventory")
	# Reset
	_mm.mode = _mm.Mode.SINGLE
	_mm.players.clear()
	_mm.peer = null
	_mm._peer_round_status.clear()
	_mm._peer_inventories.clear()
	_mm._last_team_result.clear()
	_mm._global_round_active = false
	_mm._global_round_time_left = 0.0
	_gs.round_active = false
	_gs._extracted_this_round = false

func after_each() -> void:
	_mm.mode = _mm.Mode.SINGLE
	_mm.peer = null
	_mm._peer_round_status.clear()
	_mm._peer_inventories.clear()
	_mm._last_team_result.clear()
	_mm._global_round_active = false
	_gs.round_active = false

# ── extraction_zone 源码层 ──

func test_extraction_zone_branches_on_mode() -> void:
	var src: String = load("res://scripts/entities/extraction_zone.gd").source_code
	assert_true(src.contains("is_single"),
		"extraction_zone 必须按 mm.is_single 分支")
	# Q3 fix:helper request_extract 取代 _rpc_request_extract.rpc_id(host self-RPC bug)
	assert_true(src.contains("request_extract"),
		"extraction_zone 多人分支必须调 mm.request_extract")
	assert_true(src.contains("mark_extracted_this_round"),
		"extraction_zone 单人分支必须调 gs.mark_extracted_this_round")

# ── MM API + signals ──

func test_mm_has_per_peer_state() -> void:
	assert_true("_peer_round_status" in _mm,
		"MM 必须有 _peer_round_status 字段(host 权威 per-peer 状态)")
	assert_true("_peer_inventories" in _mm,
		"MM 必须有 _peer_inventories 字段(撤离 peer 上报的物品)")
	assert_true("_last_team_result" in _mm,
		"MM 必须有 _last_team_result(home 切场景过来主动查)")
	assert_true("_global_round_active" in _mm,
		"MM 必须有 _global_round_active(host 全局 timer 状态)")
	assert_true("_global_round_time_left" in _mm,
		"MM 必须有 _global_round_time_left")

func test_mm_has_per_peer_signals() -> void:
	assert_true(_mm.has_signal("peer_done"),
		"MM 必须有 peer_done(peer_id, reason) signal")
	assert_true(_mm.has_signal("team_result_ready"),
		"MM 必须有 team_result_ready(payload) signal")

func test_mm_has_per_peer_rpcs() -> void:
	assert_true(_mm.has_method("_rpc_request_peer_done"),
		"MM 必须有 _rpc_request_peer_done RPC(any_peer → host)")
	assert_true(_mm.has_method("_rpc_apply_peer_done"),
		"MM 必须有 _rpc_apply_peer_done RPC(authority,call_local)")
	assert_true(_mm.has_method("_rpc_apply_team_result"),
		"MM 必须有 _rpc_apply_team_result RPC(authority,call_local)")
	assert_true(_mm.has_method("notify_extracted"),
		"MM 必须有 notify_extracted helper")
	assert_true(_mm.has_method("broadcast_round_end_timeout"),
		"MM 必须有 broadcast_round_end_timeout(host 全局 timer 到 0 调)")
	assert_true(_mm.has_method("_check_all_done_and_settle"),
		"MM 必须有 _check_all_done_and_settle")

# ── _rpc_request_peer_done host check ──

func test_request_peer_done_only_host() -> void:
	var src: String = load("res://scripts/autoloads/multiplayer_manager.gd").source_code
	var i: int = src.find("func _rpc_request_peer_done")
	assert_gte(i, 0)
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0: j = src.length()
	var body: String = src.substr(i, j - i)
	assert_true(body.contains("is_host"),
		"_rpc_request_peer_done 必须以 is_host 校验开头")
	assert_true(body.contains("_rpc_apply_peer_done"),
		"_rpc_request_peer_done 通过后必须广播 _rpc_apply_peer_done")
	assert_true(body.contains("_check_all_done_and_settle"),
		"_rpc_request_peer_done 通过后必须 _check_all_done_and_settle(检测全员 done)")

# ── notify_extracted helper(host 直接调本地;client rpc_id) ──

func test_notify_extracted_branches_on_host() -> void:
	var src: String = load("res://scripts/autoloads/multiplayer_manager.gd").source_code
	var i: int = src.find("func notify_extracted")
	assert_gte(i, 0)
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0: j = src.length()
	var body: String = src.substr(i, j - i)
	assert_true(body.contains("is_host"),
		"notify_extracted 必须按 is_host 分支(host 直接调本地;client rpc_id)")
	assert_true(body.contains("_rpc_request_peer_done("),
		"host 分支必须直接调 _rpc_request_peer_done(本地)")
	assert_true(body.contains("rpc_id(1"),
		"client 分支必须 .rpc_id(1, ...)")

# ── _rpc_apply_peer_done 行为(本人 vs 其他) ──

func test_apply_peer_done_self_extracted_keeps_inv() -> void:
	# host mode + 本人(peer 1)撤离 → end_round("extracted") + mark_extracted
	_mm.mode = _mm.Mode.HOST
	_mm.peer = null
	_gs.round_active = true
	_gs._extracted_this_round = false
	_mm._rpc_apply_peer_done(1, "extracted")
	assert_false(_gs.round_active, "本人结束 → round_active = false")
	assert_true(_gs._extracted_this_round,
		"本人撤离 → mark_extracted_this_round 应被调")

func test_apply_peer_done_other_extracted_emits_signal() -> void:
	# host mode + 别人(peer 2)撤离 → 我不结束本局,只 emit peer_done signal
	_mm.mode = _mm.Mode.HOST
	_mm.peer = null
	_gs.round_active = true
	_gs._extracted_this_round = false
	watch_signals(_mm)
	_mm._rpc_apply_peer_done(2, "extracted")
	# 我自己的 round 还没结束(只有 peer 2 结束了)
	assert_true(_gs.round_active, "他人结束 → 我的 round 仍 active")
	assert_false(_gs._extracted_this_round, "他人撤离 → 我没标 extracted")
	# peer_done signal 应该 emit(给 main.gd hide Player)
	assert_signal_emitted(_mm, "peer_done")

func test_apply_peer_done_self_timeout_clears_inv() -> void:
	# host mode + 本人 timeout → end_round("timeout")
	_mm.mode = _mm.Mode.HOST
	_mm.peer = null
	_gs.round_active = true
	_gs._extracted_this_round = false
	_mm._rpc_apply_peer_done(1, "timeout")
	assert_false(_gs.round_active, "本人 timeout → round_active = false")
	assert_false(_gs._extracted_this_round, "timeout → _extracted_this_round 仍 false")

func test_apply_peer_done_idempotent_when_already_done() -> void:
	# round_active=false 时再调,不该崩
	_mm.mode = _mm.Mode.HOST
	_mm.peer = null
	_gs.round_active = false
	_mm._rpc_apply_peer_done(1, "extracted")
	pass_test("idempotent _rpc_apply_peer_done 不崩")

# ── _check_all_done_and_settle 行为 ──

func test_check_all_done_skips_when_someone_playing() -> void:
	# 还有 peer "playing" → 不广播 team_result
	_mm.mode = _mm.Mode.HOST
	_mm.peer = null
	_mm._peer_round_status = {1: "extracted", 2: "playing"}
	watch_signals(_mm)
	_mm._check_all_done_and_settle()
	assert_signal_not_emitted(_mm, "team_result_ready",
		"还有 peer playing 时,_check_all_done 不该 emit team_result")

func test_check_all_done_emits_team_result_when_all_done() -> void:
	_mm.mode = _mm.Mode.HOST
	_mm.peer = null
	_mm._peer_round_status = {1: "extracted", 2: "timeout"}
	_mm._peer_inventories = {1: []}  # peer 1 撤离但空背包
	watch_signals(_mm)
	_mm._check_all_done_and_settle()
	assert_signal_emitted(_mm, "team_result_ready",
		"全员 done → _check_all_done 必须 emit team_result_ready")

func test_check_all_done_payload_contains_required_fields() -> void:
	_mm.mode = _mm.Mode.HOST
	_mm.peer = null
	_mm._peer_round_status = {1: "extracted"}
	_mm._peer_inventories = {1: []}
	_mm._check_all_done_and_settle()
	# payload 应在 _last_team_result 中
	var payload: Dictionary = _mm._last_team_result
	assert_true(payload.has("per_peer_status"),
		"team_result payload 必须含 per_peer_status")
	assert_true(payload.has("reward_per_peer"),
		"team_result payload 必须含 reward_per_peer")
	assert_true(payload.has("reward_total"),
		"team_result payload 必须含 reward_total")
	assert_true(payload.has("ratio"),
		"team_result payload 必须含 ratio")

# ── broadcast_round_end_timeout(host 全局 timer 到 0) ──

func test_broadcast_round_end_timeout_marks_all_playing_as_timeout() -> void:
	_mm.mode = _mm.Mode.HOST
	_mm.peer = null
	_mm._peer_round_status = {1: "extracted", 2: "playing", 3: "playing"}
	_gs.round_active = true
	_mm.broadcast_round_end_timeout()
	# peer 1 已 extracted 不变,2/3 应改为 timeout
	assert_eq(String(_mm._peer_round_status[1]), "extracted",
		"已 extracted 的 peer 不该被 timeout 覆盖")
	assert_eq(String(_mm._peer_round_status[2]), "timeout",
		"playing 的 peer 应被标 timeout")
	assert_eq(String(_mm._peer_round_status[3]), "timeout",
		"playing 的 peer 应被标 timeout")

# ── host _process 全局 timer ──

func test_global_timer_starts_on_broadcast_round_start() -> void:
	# broadcast_round_start 应启动 _global_round_active + 设 _global_round_time_left
	_mm.mode = _mm.Mode.HOST
	_mm.peer = null
	_mm.players[1] = {"name": "host", "ready": true, "color": Color.WHITE}
	_mm.broadcast_round_start()
	assert_true(_mm._global_round_active, "broadcast_round_start 应启动 global timer")
	assert_almost_eq(_mm._global_round_time_left, 900.0, 0.1,
		"_global_round_time_left 应为 900s(等于 ROUND_TIME)")
	# cleanup
	_mm._global_round_active = false
	_gs.round_active = false

func test_global_timer_only_host() -> void:
	# CLIENT 模式 _process 应早 return,不动 _global_round_time_left
	_mm.mode = _mm.Mode.CLIENT
	_mm._global_round_active = true
	_mm._global_round_time_left = 100.0
	_mm._process(1.0)
	assert_eq(_mm._global_round_time_left, 100.0,
		"CLIENT 模式不该推进 _global_round_time_left")

func test_global_timer_progresses_on_host() -> void:
	_mm.mode = _mm.Mode.HOST
	_mm._global_round_active = true
	_mm._global_round_time_left = 100.0
	_mm._process(1.0)
	assert_almost_eq(_mm._global_round_time_left, 99.0, 0.01,
		"HOST 模式 _process 应推进 _global_round_time_left")

# ── broadcast_round_start 重置 per-peer 状态 ──

func test_broadcast_round_start_resets_peer_status() -> void:
	_mm.mode = _mm.Mode.HOST
	_mm.peer = null
	_mm.players[1] = {"name": "host", "ready": true, "color": Color.WHITE}
	_mm.players[2] = {"name": "client", "ready": true, "color": Color.WHITE}
	_mm._peer_round_status[1] = "timeout"  # 上局残留
	_mm._peer_inventories[1] = ["leftover"]
	_mm._last_team_result = {"old": "data"}
	_mm.broadcast_round_start()
	# 全员重设 "playing"
	assert_eq(String(_mm._peer_round_status[1]), "playing",
		"broadcast_round_start 应重置 peer 1 → playing")
	assert_eq(String(_mm._peer_round_status[2]), "playing",
		"broadcast_round_start 应重置 peer 2 → playing")
	# inventories / last result 应清空
	assert_true(_mm._peer_inventories.is_empty(),
		"broadcast_round_start 应清 _peer_inventories")
	assert_true(_mm._last_team_result.is_empty(),
		"broadcast_round_start 应清 _last_team_result")
	# cleanup
	_mm._global_round_active = false
	_gs.round_active = false

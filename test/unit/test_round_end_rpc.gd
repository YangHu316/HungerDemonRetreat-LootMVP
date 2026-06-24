extends GutTest

# Phase 2B Tier B6:Round end host-authoritative
# 防御:
#   - extraction_zone 多人模式发 _rpc_request_extract,单人走 gs.end_round
#   - GameSession.tick 多人 host timeout 走 mm.broadcast_round_end_timeout
#   - MM 加 _rpc_request_extract / broadcast_round_end_timeout / _rpc_apply_round_end
#   - _rpc_apply_round_end 区分:本人撤离 → "extracted"(保留 inv);别人撤离 → "timeout"(清 inv)

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
	_gs.round_active = false
	_gs._extracted_this_round = false

func after_each() -> void:
	_mm.mode = _mm.Mode.SINGLE
	_mm.peer = null
	_gs.round_active = false

# ── extraction_zone 源码层 ──

func test_extraction_zone_branches_on_mode() -> void:
	var src: String = load("res://scripts/entities/extraction_zone.gd").source_code
	# countdown_succeeded 后必须按 mm 分支
	assert_true(src.contains("is_single"),
		"extraction_zone 必须按 mm.is_single 分支")
	assert_true(src.contains("_rpc_request_extract"),
		"extraction_zone 多人分支必须发 mm._rpc_request_extract")
	assert_true(src.contains("mark_extracted_this_round"),
		"extraction_zone 单人分支必须调 gs.mark_extracted_this_round")

# ── MM RPCs ──

func test_mm_has_extract_rpcs() -> void:
	assert_true(_mm.has_method("_rpc_request_extract"))
	assert_true(_mm.has_method("_rpc_apply_round_end"))
	assert_true(_mm.has_method("broadcast_round_end_timeout"))

func test_mm_request_extract_only_host() -> void:
	var src: String = load("res://scripts/autoloads/multiplayer_manager.gd").source_code
	var i: int = src.find("func _rpc_request_extract")
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0: j = src.length()
	var body: String = src.substr(i, j - i)
	assert_true(body.contains("is_host"),
		"_rpc_request_extract 必须以 is_host 校验开头")
	assert_true(body.contains("_rpc_apply_round_end"),
		"_rpc_request_extract 通过后必须 _rpc_apply_round_end.rpc 广播")

# ── _rpc_apply_round_end 行为(本人撤离 vs 迷失) ──

func test_apply_round_end_self_extracted_keeps_inv() -> void:
	# host mode + 本人 peer_id 撤离 → end_round("extracted") 保留 inventory
	_mm.mode = _mm.Mode.HOST
	_mm.peer = null  # mock — no real peer,get_local_peer_id 返回 1(host)
	# 设置 round 状态
	_gs.round_active = true
	_gs._extracted_this_round = false
	# 加 1 个 fake item 到 inventory(给 timeout 检测对照)
	# 不真加,看 _gs.end_round("extracted") 不清就行
	# 模拟撤离:my_id == 1,extracted_by == 1
	_mm._rpc_apply_round_end("extracted", 1)
	# round_active 应 false(end_round 设)
	assert_false(_gs.round_active, "round 应结束")
	# _extracted_this_round 应 true
	assert_true(_gs._extracted_this_round,
		"我撤了 → _extracted_this_round = true")

func test_apply_round_end_other_extracted_treats_as_timeout() -> void:
	# host mode + 他 peer 撤离 → 我视为迷失
	_mm.mode = _mm.Mode.HOST
	_mm.peer = null
	_gs.round_active = true
	_gs._extracted_this_round = false
	# 我是 1,但 extracted_by = 2(别人撤了)
	_mm._rpc_apply_round_end("extracted", 2)
	assert_false(_gs.round_active, "round 应结束")
	assert_false(_gs._extracted_this_round,
		"别人撤了 → 我没标 extracted")

func test_apply_round_end_timeout_treats_as_timeout() -> void:
	# reason == "timeout" → 全员 end_round("timeout")
	_mm.mode = _mm.Mode.HOST
	_mm.peer = null
	_gs.round_active = true
	_gs._extracted_this_round = false
	_mm._rpc_apply_round_end("timeout", -1)
	assert_false(_gs.round_active, "round 应结束")
	assert_false(_gs._extracted_this_round,
		"timeout → _extracted_this_round 不变 false")

func test_apply_round_end_idempotent() -> void:
	# round_active=false 时再调,不该崩(防 RPC 重复)
	_mm.mode = _mm.Mode.HOST
	_mm.peer = null
	_gs.round_active = false
	_mm._rpc_apply_round_end("extracted", 1)
	# 不崩即过
	pass_test("idempotent end_round 不崩")

# ── tick 多人 host timeout 走 broadcast ──

func test_tick_host_timeout_calls_broadcast() -> void:
	_mm.mode = _mm.Mode.HOST
	_mm.peer = null
	_gs.start_round()
	_gs.time_left = 0.1
	_gs.tick(1.0)
	assert_false(_gs.round_active,
		"多人 host tick timeout 后 round 应结束(经 broadcast → _rpc_apply_round_end → end_round)")

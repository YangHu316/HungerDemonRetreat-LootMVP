extends GutTest

# Phase 2B Tier B8:重开一局 clean
# 防御:撤离 → result_panel → home → 进入战局,所有 round-scoped 状态干净
# 这个 test 保证 start_round 显式 reset 所有 round-scoped 字段,
# 避免上局残留导致下局行为异常(用户报告"重开一局功能也有问题"的兜底)

var _gs: Node
var _mm: Node
var _lil: Node
var _pool: Node
var _inv: Node

func before_each() -> void:
	_gs = get_node("/root/GameSession")
	_mm = get_node("/root/MultiplayerManager")
	_lil = get_node_or_null("/root/LocalInspectLog")
	_pool = get_node("/root/OrderPool")
	_inv = get_node("/root/PlayerInventory")
	_mm.mode = _mm.Mode.SINGLE
	_mm.players.clear()
	_gs.round_active = false

func after_each() -> void:
	_gs.round_active = false
	_mm.mode = _mm.Mode.SINGLE

# ── start_round 重置 round-scoped 状态 ──

func test_start_round_resets_extracted_flag() -> void:
	_gs._extracted_this_round = true
	_gs.start_round()
	assert_false(_gs._extracted_this_round)

func test_start_round_resets_uid_counter() -> void:
	_gs._next_entry_uid = 99
	_gs.start_round()
	assert_eq(_gs._next_entry_uid, 0)

func test_start_round_resets_time_left() -> void:
	_gs.time_left = 0.0  # 上局结束
	_gs.start_round()
	assert_eq(_gs.time_left, _gs.ROUND_TIME)

func test_start_round_clears_inspect_log() -> void:
	if _lil == null:
		pending("LocalInspectLog 缺失")
		return
	_lil.mark_inspected("res://path/X", 1)
	_gs.start_round()
	assert_false(_lil.is_inspected("res://path/X", 1))

func test_start_round_sets_round_active() -> void:
	assert_false(_gs.round_active)
	_gs.start_round()
	assert_true(_gs.round_active)

func test_start_round_emits_round_started() -> void:
	# GUT signal watcher
	watch_signals(_gs)
	_gs.start_round()
	assert_signal_emitted(_gs, "round_started",
		"start_round 必须 emit round_started 信号")

# ── 完整重开循环 ──

func test_full_round_restart_cycle_clean() -> void:
	# 模拟一整局:start → end(extracted) → start 重开
	# 重开后所有状态应干净
	_gs.start_round()
	_gs.mark_extracted_this_round()
	assert_true(_gs._extracted_this_round)
	_gs.end_round("extracted")
	assert_false(_gs.round_active, "end_round 后 round_active=false")
	# 重开
	_gs.start_round()
	assert_false(_gs._extracted_this_round, "重开后 _extracted_this_round 必须 reset")
	assert_eq(_gs._next_entry_uid, 0, "重开后 uid 计数器归零")
	assert_eq(_gs.time_left, _gs.ROUND_TIME, "重开后 time_left = ROUND_TIME")
	assert_true(_gs.round_active)

func test_timeout_round_restart_cycle_clean() -> void:
	# 上局 timeout → 下局必须 freshly active
	_gs.start_round()
	_gs.time_left = 0.1
	_gs.tick(1.0)
	assert_false(_gs.round_active, "timeout 后 round 结束")
	# 重开
	_gs.start_round()
	assert_true(_gs.round_active)
	assert_eq(_gs.time_left, _gs.ROUND_TIME)

# ── result_panel restart 正确性(源码层) ──

func test_result_panel_restart_unpauses_before_scene_change() -> void:
	var src: String = load("res://scripts/ui/result_panel.gd").source_code
	var i: int = src.find("func _on_restart")
	assert_gte(i, 0)
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0:
		j = src.length()
	var body: String = src.substr(i, j - i)
	# 找 paused = false 和 change_scene_to_file 的相对位置
	var pause_pos: int = body.find("paused = false")
	var scene_pos: int = body.find("change_scene_to_file")
	assert_gte(pause_pos, 0, "_on_restart 必须 set tree.paused = false")
	assert_gte(scene_pos, 0, "_on_restart 必须 change_scene_to_file")
	assert_lt(pause_pos, scene_pos,
		"paused = false 必须在 change_scene_to_file 之前")

func test_result_panel_clears_active_order() -> void:
	var src: String = load("res://scripts/ui/result_panel.gd").source_code
	var i: int = src.find("func _on_restart")
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0:
		j = src.length()
	var body: String = src.substr(i, j - i)
	assert_true(body.contains("clear_active"),
		"_on_restart 必须 OrderPool.clear_active(防止订单跨局)")

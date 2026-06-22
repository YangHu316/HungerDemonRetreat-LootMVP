extends GutTest

# Phase 2B Tier B3:per-peer inspect 状态 (LocalInspectLog autoload)
# 防御:
#   - LocalInspectLog autoload 存在,API 齐全 (mark/is/clear/hydrate/fully_inspected)
#   - mark + is_inspected 往返
#   - clear 归零
#   - hydrate_container_entries 把 entry["inspected"]/["examined"] cache 填好
#   - search_ui 用 log 替代 _container.is_searched(open_for 判断)
#   - search_ui 完成 inspect 时写 log(_process)

var _lil: Node

func before_each() -> void:
	_lil = get_node_or_null("/root/LocalInspectLog")
	if _lil != null:
		_lil.clear()

func after_each() -> void:
	if _lil != null:
		_lil.clear()

# ── autoload + API ──

func test_local_inspect_log_autoload_exists() -> void:
	assert_not_null(_lil, "LocalInspectLog autoload 必须存在")

func test_api_complete() -> void:
	assert_true(_lil.has_method("mark_inspected"))
	assert_true(_lil.has_method("is_inspected"))
	assert_true(_lil.has_method("clear"))
	assert_true(_lil.has_method("is_container_fully_inspected"))
	assert_true(_lil.has_method("hydrate_container_entries"))

# ── mark + is 往返 ──

func test_mark_then_is_returns_true() -> void:
	_lil.mark_inspected("res://path/A", 42)
	assert_true(_lil.is_inspected("res://path/A", 42))

func test_unmarked_returns_false() -> void:
	assert_false(_lil.is_inspected("res://path/A", 42))
	_lil.mark_inspected("res://path/A", 42)
	# 不同 path 不算
	assert_false(_lil.is_inspected("res://path/B", 42))
	# 不同 uid 不算
	assert_false(_lil.is_inspected("res://path/A", 99))

func test_negative_uid_ignored() -> void:
	# uid < 0 表示无效,mark/is 都该 false
	_lil.mark_inspected("res://path/A", -1)
	assert_false(_lil.is_inspected("res://path/A", -1))

func test_clear_resets_all() -> void:
	_lil.mark_inspected("res://path/A", 1)
	_lil.mark_inspected("res://path/B", 2)
	assert_true(_lil.is_inspected("res://path/A", 1))
	_lil.clear()
	assert_false(_lil.is_inspected("res://path/A", 1))
	assert_false(_lil.is_inspected("res://path/B", 2))

# ── is_container_fully_inspected ──

func test_fully_inspected_empty_container_false() -> void:
	# 假 container 节点(只需 contents/get_path)
	var fake: FakeContainer = _make_fake_container("FakeC1", [])
	add_child_autofree(fake)
	# 空 entries 不算 fully_inspected
	assert_false(_lil.is_container_fully_inspected(fake))

func test_fully_inspected_all_marked_true() -> void:
	var fake: FakeContainer = _make_fake_container("FakeC2", [10, 20, 30])
	add_child_autofree(fake)
	_lil.mark_inspected(String(fake.get_path()), 10)
	_lil.mark_inspected(String(fake.get_path()), 20)
	_lil.mark_inspected(String(fake.get_path()), 30)
	assert_true(_lil.is_container_fully_inspected(fake))

func test_fully_inspected_partial_false() -> void:
	var fake: FakeContainer = _make_fake_container("FakeC3", [10, 20, 30])
	add_child_autofree(fake)
	_lil.mark_inspected(String(fake.get_path()), 10)
	_lil.mark_inspected(String(fake.get_path()), 20)
	# uid 30 未标
	assert_false(_lil.is_container_fully_inspected(fake))

# ── hydrate ──

func test_hydrate_fills_cache() -> void:
	var fake: FakeContainer = _make_fake_container("FakeC4", [10, 20])
	add_child_autofree(fake)
	_lil.mark_inspected(String(fake.get_path()), 10)
	# uid 20 未标
	_lil.hydrate_container_entries(fake)
	var entries = fake.contents.entries
	# 找 uid 10 → inspected=true
	for e in entries:
		if int(e["uid"]) == 10:
			assert_true(bool(e["inspected"]), "uid 10 hydrate 后 inspected=true")
			assert_true(bool(e["examined"]), "examined 兼容字段也=true")
		elif int(e["uid"]) == 20:
			assert_false(bool(e["inspected"]), "uid 20 未 mark,inspected=false")

# ── search_ui 接线源码层 ──

func test_search_ui_uses_log_in_open_for() -> void:
	var src: String = load("res://scripts/ui/search_ui.gd").source_code
	var i: int = src.find("func open_for")
	assert_gte(i, 0)
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0:
		j = src.length()
	var body: String = src.substr(i, j - i)
	assert_true(body.contains("LocalInspectLog") or body.contains("hydrate_container_entries"),
		"search_ui.open_for 必须用 LocalInspectLog hydrate")
	assert_true(body.contains("is_container_fully_inspected"),
		"open_for 应通过 lil.is_container_fully_inspected 判断 IDLE")

func test_search_ui_marks_log_on_inspect_done() -> void:
	var src: String = load("res://scripts/ui/search_ui.gd").source_code
	var i: int = src.find("func _process")
	assert_gte(i, 0)
	var j: int = src.find("\nfunc ", i + 5)
	if j < 0:
		j = src.length()
	var body: String = src.substr(i, j - i)
	assert_true(body.contains("mark_inspected"),
		"_process 完成 inspect 时必须调 lil.mark_inspected 持久化")

# ── round_start 清空 inspect log ──

func test_start_round_clears_inspect_log() -> void:
	_lil.mark_inspected("res://path/X", 1)
	assert_true(_lil.is_inspected("res://path/X", 1))
	var gs = get_node("/root/GameSession")
	# 先停掉之前的 round(GUT 之间可能残留)
	gs.round_active = false
	gs.start_round()
	assert_false(_lil.is_inspected("res://path/X", 1),
		"GameSession.start_round 必须清 LocalInspectLog")
	gs.round_active = false

# ── helpers ──

# 用一个继承 Node 的脚本类(预编译好),contents 是 GridInventory
class FakeContainer extends Node:
	var contents: GridInventory = null

func _make_fake_container(_node_name: String, uids: Array) -> FakeContainer:
	var n := FakeContainer.new()
	var grid := GridInventory.new()
	grid.cells = []
	grid.entries = []
	for uid in uids:
		grid.entries.append({
			"uid": int(uid),
			"item": null,
			"x": 0, "y": 0, "rotated": false,
		})
	n.contents = grid
	return n

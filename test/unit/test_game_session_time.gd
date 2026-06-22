extends GutTest

# P0 护栏 #5: §三 时间系统 — 单局 15min 硬上限 + 迷失清空背包
# 防御对象: 外卖侠系统骨架 §三 / §十二
# 测的是"数值常量 + 倒计时 + timeout 迷失 + 撤离保留"四组逻辑

const ROUND_TIME_EXPECTED := 900.0   # 15 分钟
const EXTRACT_TIME_EXPECTED := 10.0  # 撤离倒计时

var gs: Node
var inv: Node
var bus: Node

func before_each() -> void:
	gs = get_node("/root/GameSession")
	inv = get_node("/root/PlayerInventory")
	bus = get_node("/root/EventBus")
	inv.reset()
	gs.start_round()
	# 关掉 _process,测试自己驱动 tick(delta)
	gs.set_process(false)

func after_each() -> void:
	gs.round_active = false
	gs.set_process(false)

# ---- 数值常量 ----
func test_round_time_constant_is_900() -> void:
	var script: GDScript = load("res://scripts/autoloads/game_session.gd")
	assert_eq(script.ROUND_TIME, ROUND_TIME_EXPECTED, "ROUND_TIME 必须 = 900s (15min 硬上限)")

func test_extract_time_constant_is_10() -> void:
	var script: GDScript = load("res://scripts/entities/extraction_zone.gd")
	assert_eq(script.EXTRACT_TIME, EXTRACT_TIME_EXPECTED, "EXTRACT_TIME 必须 = 10s")

# ---- start_round ----
func test_start_round_sets_full_time_and_active() -> void:
	assert_eq(gs.time_left, ROUND_TIME_EXPECTED, "新一局应有 900s")
	assert_true(gs.round_active, "round_active 应为 true")
	assert_eq(gs.state, "PLAYING")

# ---- tick 倒计时 ----
func test_tick_decrements_time_left() -> void:
	gs.tick(5.0)
	assert_almost_eq(gs.time_left, ROUND_TIME_EXPECTED - 5.0, 0.001)

func test_tick_does_nothing_when_round_inactive() -> void:
	gs.round_active = false
	var before: float = gs.time_left
	gs.tick(5.0)
	assert_eq(gs.time_left, before, "round_active=false 时 tick 不应推进")

# ---- timeout = 迷失 ----
func test_timeout_clears_inventory() -> void:
	var item: ItemData = load("res://resources/items/apple.tres")
	inv.try_place_item(item)
	assert_eq(inv.grid.entries.size(), 1, "前置:背包里应有 1 件物品")
	# tick 推到归零以下
	gs.tick(ROUND_TIME_EXPECTED + 1.0)
	assert_eq(inv.grid.entries.size(), 0, "timeout 后背包必须清空(迷失)")
	assert_false(gs.round_active)
	assert_eq(gs.state, "ROUND_END")

func test_timeout_emits_round_ended_with_zero_total() -> void:
	var item: ItemData = load("res://resources/items/apple.tres")
	inv.try_place_item(item)
	watch_signals(bus)
	gs.tick(ROUND_TIME_EXPECTED + 0.1)
	assert_signal_emitted_with_parameters(bus, "round_ended", [0, "timeout"])

# ---- 撤离保留背包 ----
func test_extracted_preserves_inventory() -> void:
	var item: ItemData = load("res://resources/items/apple.tres")
	inv.try_place_item(item)
	var size_before: int = inv.grid.entries.size()
	gs.end_round("extracted")
	assert_eq(inv.grid.entries.size(), size_before, "撤离不能清空背包")
	assert_false(gs.round_active)

func test_extracted_emits_round_ended_with_total() -> void:
	var bus_local: Node = get_node("/root/EventBus")
	var item: ItemData = load("res://resources/items/apple.tres")
	inv.try_place_item(item)
	watch_signals(bus_local)
	gs.end_round("extracted")
	assert_signal_emitted(bus_local, "round_ended", "应 emit round_ended")
	var args: Array = get_signal_parameters(bus_local, "round_ended", 0)
	assert_gt(int(args[0]), 0, "撤离 total_value 必须 > 0")
	assert_eq(String(args[1]), "extracted")

# ---- round_tick signal:为后续变质/UI/Logger 监听 ----
func test_tick_emits_round_tick_signal() -> void:
	var bus_local: Node = get_node("/root/EventBus")
	watch_signals(bus_local)
	gs.tick(1.0)
	assert_signal_emitted(bus_local, "round_tick", "GameSession.tick() 必须 emit EventBus.round_tick")
	var args: Array = get_signal_parameters(bus_local, "round_tick", 0)
	assert_almost_eq(float(args[0]), ROUND_TIME_EXPECTED - 1.0, 0.001, "round_tick 参数 0 = time_left")
	assert_eq(float(args[1]), ROUND_TIME_EXPECTED, "round_tick 参数 1 = total")

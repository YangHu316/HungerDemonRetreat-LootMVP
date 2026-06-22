extends GutTest

# 验证:InventoryComp 是独立组件 — 两个实例数据完全独立(联机基础)
# 这是 per-player 背包能成立的前提

func test_can_instantiate_standalone() -> void:
	var c := InventoryComp.new()
	add_child_autofree(c)
	# _ready 调用 reset → grid 已建
	assert_not_null(c.grid, "实例化后 grid 应已 setup")
	assert_eq(c.grid.cols, InventoryComp.COLS)
	assert_eq(c.grid.rows, InventoryComp.ROWS)

func test_two_instances_have_independent_data() -> void:
	var c1 := InventoryComp.new()
	var c2 := InventoryComp.new()
	add_child_autofree(c1)
	add_child_autofree(c2)
	var apple: ItemData = load("res://resources/items/apple.tres")
	assert_true(c1.try_place_item(apple))
	assert_eq(c1.grid.entries.size(), 1, "c1 有 1 个 apple")
	assert_eq(c2.grid.entries.size(), 0, "c2 必须仍空(数据互不影响)")
	assert_eq(c1.get_total_value(), apple.value)
	assert_eq(c2.get_total_value(), 0)

func test_changed_signal_emits_per_instance() -> void:
	var c1 := InventoryComp.new()
	var c2 := InventoryComp.new()
	add_child_autofree(c1)
	add_child_autofree(c2)
	watch_signals(c1)
	watch_signals(c2)
	var apple: ItemData = load("res://resources/items/apple.tres")
	c1.try_place_item(apple)
	assert_signal_emitted(c1, "changed", "c1.try_place_item 后 c1 应 emit changed")
	# c2 的 changed 应该没有(除 _ready 时 reset 那一次,我们 watch_signals 在那之后)
	assert_signal_emit_count(c2, "changed", 0, "c2 完全没动,signal 不应 emit")

func test_reset_clears_data() -> void:
	var c := InventoryComp.new()
	add_child_autofree(c)
	var apple: ItemData = load("res://resources/items/apple.tres")
	c.try_place_item(apple)
	assert_eq(c.grid.entries.size(), 1)
	c.reset()
	assert_eq(c.grid.entries.size(), 0)

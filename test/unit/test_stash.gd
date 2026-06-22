extends GutTest

# §九 仓库(网格化) + 跨局背包 + 撤离/迷失边界
# Stash 内部 = GridInventory(8×5),物品按 grid_w×grid_h 占格

const SAVE_PATH := "user://stash.json"

var stash: Node
var inv: Node
var gs: Node

func before_each() -> void:
	stash = get_node("/root/Stash")
	inv = get_node("/root/PlayerInventory")
	gs = get_node("/root/GameSession")
	stash.clear()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	inv.reset()
	gs.start_round()
	gs.set_process(false)

func after_each() -> void:
	gs.round_active = false
	gs.set_process(false)
	stash.clear()

# ---- Stash 网格基础 ----
func test_stash_grid_dims() -> void:
	assert_eq(stash.grid.cols, 8, "Stash 列数")
	assert_eq(stash.grid.rows, 5, "Stash 行数")

func test_stash_starts_empty() -> void:
	assert_eq(stash.grid.entries.size(), 0)
	assert_eq(stash.get_total_value(), 0)

func test_stash_try_add_succeeds() -> void:
	var apple: ItemData = load("res://resources/items/apple.tres")
	assert_true(stash.try_add(apple))
	assert_eq(stash.grid.entries.size(), 1)
	assert_eq(stash.get_total_value(), apple.value)

func test_stash_remove_entry() -> void:
	var apple: ItemData = load("res://resources/items/apple.tres")
	stash.try_add(apple)
	var e: Dictionary = stash.grid.entries[0]
	assert_true(stash.remove_entry(e))
	assert_eq(stash.grid.entries.size(), 0)

func test_stash_full_blocks_try_add() -> void:
	# 8×5 = 40 格,塞满 1×1 物品
	var apple: ItemData = load("res://resources/items/apple.tres")
	for i in 40:
		assert_true(stash.try_add(apple), "第 %d 件应成功" % i)
	# 第 41 件应失败
	assert_false(stash.try_add(apple), "满仓应失败")
	assert_eq(stash.grid.entries.size(), 40)

# ---- JSON 往返 ----
func test_stash_save_then_load_roundtrip() -> void:
	var apple: ItemData = load("res://resources/items/apple.tres")
	var bread: ItemData = load("res://resources/items/bread.tres")
	stash.try_add(apple)
	stash.try_add(bread)
	var before_count: int = stash.grid.entries.size()
	var before_value: int = stash.get_total_value()
	stash.save()
	stash.clear()
	assert_eq(stash.grid.entries.size(), 0)
	stash.load_from_disk()
	assert_eq(stash.grid.entries.size(), before_count, "load 后数量恢复")
	assert_eq(stash.get_total_value(), before_value, "load 后总价恢复")

# ---- 背包 → 仓库 ----
func test_transfer_to_stash_moves_item() -> void:
	var apple: ItemData = load("res://resources/items/apple.tres")
	inv.try_place_item(apple)
	var entry: Dictionary = inv.grid.entries[0]
	assert_true(inv.transfer_to_stash(entry))
	assert_eq(inv.grid.entries.size(), 0, "背包该项应消失")
	assert_eq(stash.grid.entries.size(), 1, "仓库应多 1 件")

func test_transfer_to_stash_unknown_entry_returns_false() -> void:
	var fake: Dictionary = {"item": load("res://resources/items/apple.tres")}
	assert_false(inv.transfer_to_stash(fake))

func test_transfer_to_stash_when_stash_full_keeps_inventory() -> void:
	var apple: ItemData = load("res://resources/items/apple.tres")
	# 仓库塞满
	for i in 40:
		stash.try_add(apple)
	# 背包放一件
	inv.try_place_item(apple)
	var entry: Dictionary = inv.grid.entries[0]
	assert_false(inv.transfer_to_stash(entry), "仓库满应失败")
	assert_eq(inv.grid.entries.size(), 1, "失败时背包不能丢")

# ---- 仓库 → 背包 ----
func test_transfer_from_stash_picks_up() -> void:
	var apple: ItemData = load("res://resources/items/apple.tres")
	stash.try_add(apple)
	var stash_entry: Dictionary = stash.grid.entries[0]
	assert_true(inv.transfer_from_stash(stash_entry))
	assert_eq(stash.grid.entries.size(), 0, "仓库应空")
	assert_eq(inv.grid.entries.size(), 1, "背包应多 1 件")

func test_transfer_from_stash_when_inv_full_keeps_stash() -> void:
	var apple: ItemData = load("res://resources/items/apple.tres")
	for i in 20:
		inv.try_place_item(apple)
	var diamond: ItemData = load("res://resources/items/diamond.tres")
	stash.try_add(diamond)
	var stash_entry: Dictionary = stash.grid.entries[0]
	assert_false(inv.transfer_from_stash(stash_entry), "背包满时应失败")
	assert_eq(stash.grid.entries.size(), 1, "失败时仓库不能丢")

# ---- 跨局纪律(搜打撤核心) ----
func test_start_round_does_not_clear_inventory() -> void:
	var apple: ItemData = load("res://resources/items/apple.tres")
	inv.try_place_item(apple)
	gs.round_active = false
	gs.start_round()
	assert_eq(inv.grid.entries.size(), 1, "新一局开始不能清空背包")

func test_extracted_keeps_inventory_for_user_decision() -> void:
	var apple: ItemData = load("res://resources/items/apple.tres")
	inv.try_place_item(apple)
	gs.end_round("extracted")
	assert_eq(inv.grid.entries.size(), 1, "撤离:背包保留")

func test_timeout_clears_inventory_but_keeps_stash() -> void:
	var apple: ItemData = load("res://resources/items/apple.tres")
	var bread: ItemData = load("res://resources/items/bread.tres")
	inv.try_place_item(apple)
	stash.try_add(bread)
	gs.tick(900.1)
	assert_eq(inv.grid.entries.size(), 0, "迷失:背包清空")
	assert_eq(stash.grid.entries.size(), 1, "迷失:仓库不动(安全资产)")

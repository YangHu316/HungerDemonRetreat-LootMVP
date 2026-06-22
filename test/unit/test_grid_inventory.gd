extends GutTest

# P0 护栏 #2: GridInventory 放置/旋转/重叠/越界 的核心规则
# 防御对象: 评估文档 §3.2 — 4×5 网格契约,can_place/place 一旦坏掉,搜刮全坏

func _make_item(w: int, h: int, id: String = "x") -> ItemData:
	var item := ItemData.new()
	item.id = id
	item.display_name = id
	item.value = 1
	item.rarity = "Common"
	item.grid_w = w
	item.grid_h = h
	return item

func _make_grid(cols: int, rows: int) -> GridInventory:
	var g := GridInventory.new()
	g.setup(cols, rows)
	return g

# ---- setup ----
func test_setup_creates_empty_grid() -> void:
	var g := _make_grid(4, 5)
	assert_eq(g.cols, 4)
	assert_eq(g.rows, 5)
	assert_eq(g.cells.size(), 5, "rows 维度")
	assert_eq(g.cells[0].size(), 4, "cols 维度")
	for y in 5:
		for x in 4:
			assert_null(g.cells[y][x], "(%d,%d) 应为空" % [x, y])

# ---- can_place ----
func test_can_place_in_empty_grid() -> void:
	var g := _make_grid(4, 5)
	var item := _make_item(2, 2)
	assert_true(g.can_place(item, 0, 0, false))
	assert_true(g.can_place(item, 2, 3, false))

func test_can_place_rejects_out_of_bounds() -> void:
	var g := _make_grid(4, 5)
	var item := _make_item(2, 2)
	assert_false(g.can_place(item, -1, 0, false), "x<0")
	assert_false(g.can_place(item, 0, -1, false), "y<0")
	assert_false(g.can_place(item, 3, 0, false), "x+w 越右")
	assert_false(g.can_place(item, 0, 4, false), "y+h 越下")

func test_can_place_rotation_swaps_wh() -> void:
	var g := _make_grid(4, 5)
	# 1×3 原方向: 在 col=3 放得下(占 1 列高 3 行)
	var item := _make_item(1, 3)
	assert_true(g.can_place(item, 3, 0, false))
	# 旋转后变 3×1,col=3 放不下(需 3 列宽)
	assert_false(g.can_place(item, 3, 0, true), "旋转后 3×1,x=3 越界")
	assert_true(g.can_place(item, 0, 0, true), "旋转后 3×1,x=0 OK")

# ---- place / 重叠 ----
func test_place_blocks_overlap() -> void:
	var g := _make_grid(4, 5)
	var a := _make_item(2, 2, "a")
	var b := _make_item(2, 2, "b")
	var ea := {"item": a, "rotated": false, "examined": false}
	var eb := {"item": b, "rotated": false, "examined": false}
	assert_true(g.place(ea, 0, 0))
	assert_false(g.can_place(b, 1, 1, false), "(1,1) 与 (0,0)2×2 重叠")
	assert_false(g.place(eb, 1, 1))
	assert_true(g.place(eb, 2, 0))

func test_place_records_entries_and_cells() -> void:
	var g := _make_grid(4, 5)
	var a := _make_item(2, 1, "a")
	var ea := {"item": a, "rotated": false, "examined": false}
	assert_true(g.place(ea, 1, 2))
	assert_eq(g.entries.size(), 1)
	assert_eq(g.cells[2][1], ea)
	assert_eq(g.cells[2][2], ea)
	assert_null(g.cells[2][0])

# ---- remove_entry ----
func test_remove_entry_clears_cells() -> void:
	var g := _make_grid(4, 5)
	var a := _make_item(2, 2, "a")
	var ea := {"item": a, "rotated": false, "examined": false}
	g.place(ea, 0, 0)
	g.remove_entry(ea)
	assert_eq(g.entries.size(), 0)
	for y in 2:
		for x in 2:
			assert_null(g.cells[y][x])

# ---- get_entry_at 越界 ----
func test_get_entry_at_out_of_bounds_returns_null() -> void:
	var g := _make_grid(4, 5)
	assert_null(g.get_entry_at(-1, 0))
	assert_null(g.get_entry_at(0, -1))
	assert_null(g.get_entry_at(4, 0))
	assert_null(g.get_entry_at(0, 5))

# ---- total_value 仅统计 examined ----
func test_total_value_only_counts_examined() -> void:
	var g := _make_grid(4, 5)
	var a := _make_item(1, 1, "a")
	var b := _make_item(1, 1, "b")
	a.value = 10
	b.value = 7
	var ea := {"item": a, "rotated": false, "examined": false}
	var eb := {"item": b, "rotated": false, "examined": true}
	g.place(ea, 0, 0)
	g.place(eb, 1, 0)
	assert_eq(g.total_value(), 7, "只 b 被 examined")
	ea["examined"] = true
	assert_eq(g.total_value(), 17)

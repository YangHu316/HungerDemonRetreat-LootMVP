extends GutTest

# P0 护栏 #3: GridPlacer.find_first_fit 的扫描顺序与旋转 fallback
# 防御对象: 评估文档 §3.3 — 容器初始填充用它,坏了等于满地装不下东西

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

func test_first_fit_returns_top_left_in_empty_grid() -> void:
	var g := _make_grid(4, 5)
	var item := _make_item(2, 2)
	var fit = GridPlacer.find_first_fit(g, item)
	assert_not_null(fit)
	assert_eq(fit[0], 0)
	assert_eq(fit[1], 0)
	assert_eq(fit[2], false, "空格优先 unrotated")

func test_first_fit_skips_occupied_cells() -> void:
	var g := _make_grid(4, 5)
	var a := _make_item(2, 2, "a")
	var ea := {"item": a, "rotated": false, "examined": false}
	g.place(ea, 0, 0)
	var b := _make_item(2, 2, "b")
	var fit = GridPlacer.find_first_fit(g, b)
	assert_not_null(fit)
	# 扫描顺序 y 外层 x 内层,(2,0) 应先于 (0,2)
	assert_eq(fit[0], 2)
	assert_eq(fit[1], 0)

func test_first_fit_falls_back_to_rotated_when_unrotated_fails() -> void:
	# 4×5 空格放 1×4: unrotated (1宽4高) 任意 x 都行 → 不用旋转
	# 改用 5×1 但 grid 宽只有 4 → 必须旋转成 1×5
	var g := _make_grid(4, 5)
	var item := _make_item(5, 1)  # 5宽1高,unrotated 放不进 4 列
	var fit = GridPlacer.find_first_fit(g, item)
	assert_not_null(fit, "应该旋转成 1×5 后能放下")
	assert_eq(fit[2], true, "rotated=true")

func test_first_fit_returns_null_when_no_space() -> void:
	var g := _make_grid(2, 2)
	var blocker := _make_item(2, 2, "block")
	var eb := {"item": blocker, "rotated": false, "examined": false}
	g.place(eb, 0, 0)
	var item := _make_item(1, 1)
	var fit = GridPlacer.find_first_fit(g, item)
	assert_null(fit, "格子全满应该返回 null")

func test_first_fit_respects_oversize_unrotatable() -> void:
	var g := _make_grid(2, 2)
	var item := _make_item(3, 3)  # 不管转不转都放不下
	var fit = GridPlacer.find_first_fit(g, item)
	assert_null(fit)
